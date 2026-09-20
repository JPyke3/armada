#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "${ROOT}/efi/release.env"

[[ ${ARMADA_DTBLOADER_VERSION} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ ${ARMADA_DTBLOADER_SHA256} =~ ^[a-f0-9]{64}$ ]]
grep -Fq 'systemd-boot-unsigned' "${ROOT}/build_files/10-base-packages.sh"
grep -Fq 'edk2-ext4' "${ROOT}/build_files/10-base-packages.sh"
grep -Fq '/usr/lib/armada/efi/drivers/dtbloaderaa64.efi' \
    "${ROOT}/build_files/40-vendor-system-files.sh"
grep -Fq '/usr/share/licenses/armada-dtbloader/LICENSE' \
    "${ROOT}/build_files/40-vendor-system-files.sh"
