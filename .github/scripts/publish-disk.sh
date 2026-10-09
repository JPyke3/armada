#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob
images=(output/armada-*.img.gz)
if [ "${#images[@]}" -ne 1 ] || [ ! -s "${images[0]}" ]; then
  echo "::error::Expected exactly one nonempty disk image."
  exit 1
fi
image="${images[0]}"
(cd output && sha256sum -c "${image##*/}.sha256")
filename="${image##*/}"
prefix="${R2_PREFIX#/}"
prefix="${prefix%/}"

case "${prefix}:${CONTAINER_TAG}" in
  preview:testing|staging:staging|desktop-preview:testing|desktop-staging:staging) ;;
  *) echo "::error::Invalid disk publication channel/tag."; exit 1 ;;
esac

require_current_channel() {
  current=$(skopeo inspect --no-creds --override-arch arm64 --format '{{.Digest}}' \
    "docker://${IMAGE_REGISTRY}/${IMAGE_NAME}:${CONTAINER_TAG}")
  if [ "${current}" != "${CONTAINER_DIGEST}" ]; then
    echo "::error::${R2_PREFIX} has advanced to ${current}; refusing to publish stale disk ${CONTAINER_DIGEST}."
    exit 1
  fi
}
require_current_channel

commit_title=$(git show -s --format=%s "${BUILD_COMMIT}")
# The high-level S3 command handles multipart uploads for large images.
aws configure set default.s3.multipart_chunksize 64MB
for file in "${image}" "${image}.sha256"; do
  key="${prefix}/${file##*/}"
  aws s3 cp "${file}" "s3://${R2_BUCKET}/${key}" \
    --endpoint-url "${R2_ENDPOINT_URL}" \
    --metadata "armada-${prefix}=true" --cache-control no-store --only-show-errors
  uploaded_size=$(aws s3api head-object \
    --endpoint-url "${R2_ENDPOINT_URL}" \
    --bucket "${R2_BUCKET}" --key "${key}" \
    --query ContentLength --output text)
  if [ "${uploaded_size}" != "$(stat -c %s "${file}")" ]; then
    echo "::error::Uploaded size does not match ${file##*/}."
    exit 1
  fi
done

require_current_channel
version="${filename#armada-}"
version="${version#desktop-}"
version="${version%.img.gz}"
read -r image_sha256 checksum_filename < "${image}.sha256"
jq -n \
  --arg version "${version}" \
  --arg published_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg build_commit "${BUILD_COMMIT}" \
  --arg build_commit_title "${commit_title}" \
  --arg container "${IMAGE_REGISTRY}/${IMAGE_NAME}:${CONTAINER_TAG}" \
  --arg digest "${CONTAINER_DIGEST}" \
  --arg filename "${filename}" \
  --arg key "${prefix}/${filename}" \
  --arg public_url "${R2_PUBLIC_URL%/}" \
  --arg sha256 "${image_sha256}" \
  --argjson size "$(stat -c %s "${image}")" \
  '{version: $version,
    published_at: $published_at, build_commit: $build_commit, build_commit_title: $build_commit_title,
    container: {reference: $container, digest: $digest},
    image: {filename: $filename, key: $key, url: ($public_url + "/" + $key),
      size: $size, sha256: $sha256},
    checksum: {key: ($key + ".sha256"), url: ($public_url + "/" + $key + ".sha256")}}' \
  > output/current-build.json
publisher="${ARMADA_SOURCE_ROOT:-.}/.github/scripts/publish-channel-index.py"
# Historical Preview source commits use the original publisher filename.
if [ ! -f "${publisher}" ] && [ "${prefix}" = preview ]; then
  publisher="${ARMADA_SOURCE_ROOT:-.}/.github/scripts/publish-preview-index.py"
fi
python3 "${publisher}"

# Only advertise the download after both objects have been uploaded.
echo "image_key=${prefix}/${filename}" >> "${GITHUB_OUTPUT}"
echo "checksum_key=${prefix}/${filename}.sha256" >> "${GITHUB_OUTPUT}"
{
  printf '### Disk image uploaded to R2\n\n'
  printf 'Container: `%s/%s:%s`\n\n' "${IMAGE_REGISTRY}" "${IMAGE_NAME}" "${CONTAINER_TAG}"
  printf 'Image: `s3://%s/%s/%s`\n\n' "${R2_BUCKET}" "${prefix}" "${filename}"
  printf 'Checksum: `s3://%s/%s/%s.sha256`\n\n' "${R2_BUCKET}" "${prefix}" "${filename}"
  if [ -n "${R2_PUBLIC_URL}" ]; then
    printf '[Download image](%s/%s/%s) · [SHA-256](%s/%s/%s.sha256)\n' \
      "${R2_PUBLIC_URL%/}" "${prefix}" "${filename}" \
      "${R2_PUBLIC_URL%/}" "${prefix}" "${filename}"
    printf '\n[Channel builds](%s/%s/builds.json)\n' "${R2_PUBLIC_URL%/}" "${prefix}"
  fi
} >> "${GITHUB_STEP_SUMMARY}"
