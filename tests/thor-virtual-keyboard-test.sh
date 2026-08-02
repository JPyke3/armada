#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

assert_contains() {
    local file="$1" needle="$2"
    if ! grep -Fq "$needle" "$file"; then
        printf 'missing %s in %s\n' "$needle" "$file" >&2
        exit 1
    fi
}

assert_contains "$ROOT/system_files/usr/lib/armada/devices/defaults.conf" 'ARMADA_VIRTUAL_KEYBOARD_CONNECTOR='
assert_contains "$ROOT/system_files/usr/lib/armada/devices/ayn-thor.conf" 'ARMADA_VIRTUAL_KEYBOARD_CONNECTOR=DSI-1'
assert_contains "$ROOT/system_files/usr/libexec/armada/device-env" 'ARMADA_VIRTUAL_KEYBOARD_CONNECTOR'
assert_contains "$ROOT/system_files/usr/libexec/armada/start-plasma" '/usr/libexec/armada/device-env'
assert_contains "$ROOT/system_files/usr/libexec/armada/start-plasma" 'set -a'
assert_contains "$ROOT/docs/kwin-input-panel-output.patch" 'ARMADA_VIRTUAL_KEYBOARD_CONNECTOR'
assert_contains "$ROOT/docs/kwin-input-panel-output.patch" 'workspace()->findOutput(QString::fromUtf8(outputName))'
assert_contains "$ROOT/Containerfile" 'ARG ARMADA_BUILD_PATCHED_KWIN=0'
assert_contains "$ROOT/Containerfile" 'COPY docs /docs/'
assert_contains "$ROOT/build_files/build.sh" 'ARMADA_BUILD_PATCHED_KWIN'
assert_contains "$ROOT/build_files/15-install-patched-kwin.sh" 'KWIN_VERSION=6.7.3'
assert_contains "$ROOT/build_files/15-install-patched-kwin.sh" 'KWIN_RELEASE=1.fc44'
assert_contains "$ROOT/build_files/15-install-patched-kwin.sh" 'Release: \1.armada.1'
assert_contains "$ROOT/.github/workflows/build.yml" 'build_patched_kwin:'
assert_contains "$ROOT/.github/workflows/build.yml" "ARMADA_BUILD_PATCHED_KWIN=\${{ inputs.build_patched_kwin && '1' || '0' }}"

printf 'Thor virtual keyboard packaging test passed\n'
