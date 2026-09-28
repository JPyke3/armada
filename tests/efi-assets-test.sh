#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "${ROOT}/efi/release.env"

[[ ${ARMADA_ADTBLOADER_VERSION} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ ${ARMADA_ADTBLOADER_SHA256} =~ ^[a-f0-9]{64}$ ]]
grep -Fq 'systemd-boot-unsigned' "${ROOT}/build_files/10-base-packages.sh"
grep -Fq 'edk2-ext4' "${ROOT}/build_files/10-base-packages.sh"
grep -Fq '/usr/lib/armada/efi/drivers/adtbloaderaa64.efi' \
    "${ROOT}/build_files/40-vendor-system-files.sh"
grep -Fq '/usr/share/licenses/armada-adtbloader/LICENSE' \
    "${ROOT}/build_files/40-vendor-system-files.sh"
grep -Fq '/usr/lib/armada/efi/refind/refind_aa64.efi' \
    "${ROOT}/build_files/40-vendor-system-files.sh"
grep -Fq '/usr/share/licenses/armada-refind/LICENSE' \
    "${ROOT}/build_files/40-vendor-system-files.sh"
grep -Fqx 'bdf44aa0f9d339449ad979a3c39e07fc13b94cb7b19febbbe33f668461495419  efi/refind/refind_aa64.efi' \
    < <(cd "${ROOT}" && sha256sum efi/refind/refind_aa64.efi)
grep -Fq 'case 0x0102:' "${ROOT}/efi/refind/refind-power-key.patch"
grep -Fq 'loader /EFI/systemd/systemd-bootaa64.efi' "${ROOT}/efi/refind/refind.conf"
