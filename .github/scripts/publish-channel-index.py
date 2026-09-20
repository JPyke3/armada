#!/usr/bin/env python3

import copy
import datetime
import json
import os
import re
import subprocess
from pathlib import Path


KEEP_BUILDS = 5


def image_pattern(channel):
    if channel not in ("preview", "staging"):
        raise ValueError("Disk publishing is restricted to preview/ and staging/")
    return re.compile(rf"{channel}/armada-(\d{{8}}(?:\.[0-9a-f]{{7,40}})?)(?:-(abl|efi))?\.img\.gz")


def expired_keys(objects, current_keys, channel="preview"):
    pattern = image_pattern(channel)
    if isinstance(current_keys, str):
        current_keys = [current_keys]
    current_keys = set(current_keys)
    matches = [pattern.fullmatch(key) for key in current_keys]
    if not matches or any(match is None for match in matches) or len({match[1] for match in matches}) != 1:
        raise ValueError("Current images are outside the selected disk channel")

    keys = {obj["Key"] for obj in objects}
    nonempty_keys = {obj["Key"] for obj in objects if obj["Size"] > 0}
    groups = {}
    for obj in objects:
        match = pattern.fullmatch(obj["Key"])
        if match:
            modified = datetime.datetime.fromisoformat(obj["LastModified"].replace("Z", "+00:00"))
            groups.setdefault(match[1], []).append((modified, obj["Key"], match[2]))

    def complete(items):
        variants = {variant for _, _, variant in items}
        expected = {None} if None in variants else {"abl", "efi"}
        return variants >= expected and all(key in nonempty_keys and key + ".sha256" in nonempty_keys
                                            for _, key, variant in items if variant in expected)

    current_version = matches[0][1]
    if current_version not in groups or not complete(groups[current_version]) or not current_keys <= nonempty_keys:
        raise ValueError("Current images and checksums must exist before pruning")

    retained = {current_version}
    ordered = sorted(groups.items(), key=lambda item: max(row[0] for row in item[1]), reverse=True)
    for version, items in ordered:
        if complete(items) and len(retained) < KEEP_BUILDS:
            retained.add(version)

    expired = []
    for version, items in ordered:
        if version not in retained:
            for _, key, _ in items:
                if key + ".sha256" in keys:
                    expired.append(key + ".sha256")
                expired.append(key)
    return expired


def build_images(build):
    return build["images"] if "images" in build else {"abl": build["image"]}


def build_checksums(build):
    if "checksums" in build:
        return build["checksums"]
    return {"abl": build.get("checksum", {"key": build["image"]["key"] + ".sha256"})}


def main():
    channel = os.environ.get("R2_PREFIX", "preview").strip("/")
    pattern = image_pattern(channel)
    index_key = f"{channel}/builds.json"
    endpoint = os.environ["R2_ENDPOINT_URL"]
    bucket = os.environ["R2_BUCKET"]
    current = json.loads(Path("output/current-build.json").read_text())
    current_keys = [image["key"] for image in build_images(current).values()]
    aws = ["aws", "--endpoint-url", endpoint, "s3api"]
    listing = subprocess.check_output(
        aws + ["list-objects-v2", "--bucket", bucket, "--prefix", f"{channel}/", "--output", "json"],
        text=True,
    )
    objects = json.loads(listing).get("Contents", [])
    managed_keys = set()
    for obj in objects:
        key = obj["Key"]
        if not pattern.fullmatch(key):
            continue
        details = json.loads(subprocess.check_output(
            aws + ["head-object", "--bucket", bucket, "--key", key, "--output", "json"],
            text=True,
        ))
        if details.get("Metadata", {}).get(f"armada-{channel}") == "true":
            managed_keys.update((key, key + ".sha256"))
    managed_objects = [obj for obj in objects if obj["Key"] in managed_keys]
    expired = expired_keys(managed_objects, current_keys, channel)

    def read_object(key):
        return subprocess.check_output(
            ["aws", "s3", "cp", f"s3://{bucket}/{key}", "-",
             "--endpoint-url", endpoint, "--only-show-errors"], text=True,
        )

    keys = {obj["Key"] for obj in objects}
    previous = []
    if index_key in keys:
        previous = json.loads(read_object(index_key))["builds"]
    known = {build["version"]: build for build in previous}
    builds = [current]
    image_objects = {obj["Key"]: obj for obj in managed_objects if pattern.fullmatch(obj["Key"])}
    versions = {}
    for key, obj in image_objects.items():
        versions.setdefault(pattern.fullmatch(key)[1], []).append(obj)
    for version, objects_for_version in sorted(versions.items(), key=lambda item: max(obj["LastModified"] for obj in item[1]), reverse=True):
        if version not in known or version == current["version"] or any(obj["Key"] in expired for obj in objects_for_version):
            continue
        build = copy.deepcopy(known[version])
        changed = False
        for variant, image in build_images(build).items():
            obj = image_objects.get(image["key"])
            if obj is None:
                raise ValueError(f"Missing image for {version} {variant}")
            sha256 = read_object(image["key"] + ".sha256").split()[0]
            if not re.fullmatch(r"[a-f0-9]{64}", sha256):
                raise ValueError(f"Invalid checksum for {image['key']}")
            changed |= image["sha256"] != sha256
            image.update(size=obj["Size"], sha256=sha256)
        if changed:
            build["published_at"] = max(obj["LastModified"] for obj in objects_for_version)
        build["published_at"] = build["published_at"].replace("+00:00", "Z")
        if "images" in build:
            build["image"] = build["images"]["abl"]
            build["checksum"] = build_checksums(build)["abl"]
        builds.append(build)
    index = {"channel": channel, "latest": current["version"], "builds": builds}
    Path("output/builds.json").write_text(json.dumps(index, indent=2) + "\n")
    for key in expired:
        subprocess.run(aws + ["delete-object", "--bucket", bucket, "--key", key], check=True)
        print(f"Deleted s3://{bucket}/{key}")

    subprocess.run(
        ["aws", "s3", "cp", "output/builds.json", f"s3://{bucket}/{index_key}",
         "--endpoint-url", endpoint, "--content-type", "application/json",
         "--cache-control", "no-store", "--only-show-errors"], check=True,
    )

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as output:
            output.write(f"\n{channel.capitalize()} retention: keep {KEEP_BUILDS} builds; deleted {len(expired)} older objects.\n")


if __name__ == "__main__":
    main()
