#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/bin"

python3 - "$ROOT/Justfile" "$WORK/load-image" <<'PY'
from pathlib import Path
import sys
# Extraction depends on these recipe names and their order.
recipe = Path(sys.argv[1]).read_text().split('_rootful_load_image $', 1)[1]
recipe = recipe.split('\n', 1)[1].split('\n_build-bib ', 1)[0]
Path(sys.argv[2]).write_text('\n'.join(line[4:] for line in recipe.splitlines()))
PY

cat > "$WORK/bin/just" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TEST_LOG"
[[ "${FAIL_PULL:-}" != 1 || "$3" != pull ]]
SH
cat > "$WORK/bin/sudo" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TEST_LOG"
SH
chmod +x "$WORK/bin/just" "$WORK/bin/sudo"
export PATH="$WORK/bin:$PATH" TEST_LOG="$WORK/log"
export target_image=ghcr.io/armada-os/armada tag=testing
export ARMADA_IMAGE_DIGEST="sha256:$(printf 'a%.0s' {1..64})"

bash "$WORK/load-image" 2>/dev/null
printf 'sudoif podman pull %s@%s\nsudoif podman tag %s@%s %s:testing\n' \
    "$target_image" "$ARMADA_IMAGE_DIGEST" "$target_image" "$ARMADA_IMAGE_DIGEST" \
    "$target_image" > "$WORK/expected"
cmp "$WORK/expected" "$TEST_LOG"

: > "$TEST_LOG"
if ARMADA_IMAGE_DIGEST=invalid bash "$WORK/load-image" 2>"$WORK/error"; then
    echo 'Invalid image digest accepted' >&2
    exit 1
fi
[[ ! -s "$TEST_LOG" ]]
grep -q 'Invalid ARMADA_IMAGE_DIGEST' "$WORK/error"

if FAIL_PULL=1 bash "$WORK/load-image" 2>/dev/null; then
    echo 'Failed digest pull accepted' >&2
    exit 1
fi
[[ "$(wc -l < "$TEST_LOG")" == 1 ]]

: > "$TEST_LOG"
ARMADA_IMAGE_DIGEST='' SUDO_USER=fixture bash "$WORK/load-image" 2>/dev/null
[[ "$(cat "$TEST_LOG")" == "podman pull ${target_image}:testing" ]]

python3 - "$ROOT" "$WORK" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys
import textwrap

workflow = (Path(sys.argv[1]) / '.github/workflows/build-disk.yml').read_text()
build_workflow = (Path(sys.argv[1]) / '.github/workflows/build.yml').read_text()
channel_workflow = (Path(sys.argv[1]) / '.github/workflows/publish-channel-disk.yml').read_text()
step = workflow.split('      - name: Resolve container source\n', 1)[1]
script = textwrap.dedent(step.split('        run: |\n', 1)[1].split('\n\n  build:', 1)[0])
root = Path(sys.argv[2])
(root/'bin/skopeo').write_text('''#!/usr/bin/env python3
import json, os, sys
ref = sys.argv[-1]
base = 'docker://ghcr.io/armada-os/armada'
assert ref in (base + ':testing', base + '-desktop:testing'), ref
variant = 'desktop' if ref == base + '-desktop:testing' else 'handheld'
labels = {'org.opencontainers.image.revision': 'b'*40}
digest = 'sha256:' + ('d' if variant == 'desktop' else 'a')*64
if variant == os.environ['FAIL_VARIANT']:
    case = os.environ['TEST_CASE']
    if case == 'missing-revision': labels = {}
    if case == 'revision-mismatch': labels['org.opencontainers.image.revision'] = 'c'*40
    if case == 'digest-mismatch': digest = 'sha256:' + 'c'*64
print(json.dumps({'Digest': digest, 'Labels': labels}))
''')
(root/'bin/skopeo').chmod(0o755)
digest = 'sha256:' + 'a'*64
desktop_digest = 'sha256:' + 'd'*64
revision = 'b'*40
for variant in ['handheld', 'desktop']:
    for case in ['pinned', 'digest-mismatch', 'revision-mismatch', 'manual', 'missing-revision']:
        output = root / ('inspect-' + variant + '-' + case)
        env = dict(os.environ, IMAGE_REGISTRY='ghcr.io/armada-os', IMAGE_NAME='armada',
                   CONTAINER_TAG='testing', EXPECTED_DIGEST=digest,
                   EXPECTED_DESKTOP_DIGEST=desktop_digest, EXPECTED_REVISION=revision,
                   GITHUB_OUTPUT=str(output), FAIL_VARIANT=variant, TEST_CASE=case)
        if case == 'manual':
            env['EXPECTED_DIGEST'] = env['EXPECTED_DESKTOP_DIGEST'] = ''
        result = subprocess.run(['bash', '-c', script], env=env, capture_output=True, text=True)
        if case in ('digest-mismatch', 'revision-mismatch', 'missing-revision'):
            assert result.returncode != 0 and not output.exists(), case
        else:
            assert result.returncode == 0, result.stderr
            outputs = dict(line.split('=', 1) for line in output.read_text().splitlines())
            assert json.loads(outputs['digests']) == {'handheld': digest, 'desktop': desktop_digest}
            assert outputs['revision'] == revision
        print(f'PASS: Disk source resolution {variant} {case}')

assert build_workflow.count('uses: ./.github/workflows/build-disk.yml') == 1
assert 'needs: [build_push, build_desktop]' in build_workflow
assert 'tests_passed: true' in build_workflow
assert 'desktop_image_digest: ${{ needs.build_desktop.outputs.digest }}' in build_workflow
assert 'image_digest: ${{ needs.build_push.outputs.digest }}' in build_workflow
assert 'if: ${{ !inputs.tests_passed }}' in workflow
assert 'variant: [handheld, desktop]' in workflow
publish_job = workflow.split('\n  publish:', 1)[1]
assert 'needs: [prepare, build]' in publish_job
assert 'if: inputs.publish_r2' in publish_job
assert 'matrix:' not in publish_job
# Execute the fan-in loop with a recording publisher, without contacting R2.
step = publish_job.split('      - name: Publish disk images to R2\n', 1)[1]
fan_in = textwrap.dedent(step.split('        run: |\n', 1)[1])
(root / '.github/scripts').mkdir(parents=True)
(root / '.github/scripts/publish-disk.sh').write_text('''#!/bin/bash
set -euo pipefail
printf '%s %s %s %s\\n' "$PWD" "$IMAGE_NAME" "$R2_PREFIX" "$CONTAINER_DIGEST" >> "$PUBLICATION_LOG"
[[ "${FAIL_PUBLISH:-}" != "$IMAGE_NAME" ]]
''')
for variant in ('handheld', 'desktop'):
    (root / 'disks' / variant).mkdir(parents=True)
for fail in ('', 'armada'):
    log = root / ('publish-' + (fail or 'success'))
    env = dict(os.environ, GITHUB_WORKSPACE=str(root), PUBLICATION_LOG=str(log),
               CONTAINER_DIGESTS=json.dumps({'handheld': digest, 'desktop': desktop_digest}),
               IMAGE_NAME='armada', R2_PREFIX='preview', FAIL_PUBLISH=fail)
    result = subprocess.run(['bash', '-c', fan_in], cwd=root, env=env, capture_output=True, text=True)
    calls = log.read_text().splitlines()
    assert calls[0] == f'{root}/disks/handheld armada preview {digest}'
    if fail:
        assert result.returncode != 0 and len(calls) == 1
    else:
        assert result.returncode == 0, result.stderr
        assert calls[1:] == [f'{root}/disks/desktop armada-desktop desktop-preview {desktop_digest}']
print('PASS: Shared publication preserves variant digests and stops on failure')

assert 'ref: ${{ needs.prepare.outputs.revision }}' in workflow
assert 'ARMADA_IMAGE_DIGEST: ${{ fromJSON(needs.prepare.outputs.digests)[matrix.variant] }}' in workflow
assert 'CONTAINER_DIGESTS: ${{ needs.prepare.outputs.digests }}' in workflow
assert 'BUILD_COMMIT: ${{ needs.prepare.outputs.revision }}' in workflow
assert 'EXPECTED_REVISION: ${{ inputs.source_ref || github.sha }}' in workflow
assert workflow.count('persist-credentials: false') == 2
assert 'podman login ghcr.io' not in workflow
assert 'actions: read\n      contents: read\n      packages: read\n    uses: ./.github/workflows/build-disk.yml' in build_workflow
assert 'permissions:\n  actions: read\n  contents: read\n  packages: read' in channel_workflow
PY

echo 'Disk image digest tests passed'
