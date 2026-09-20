#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FINALIZE=${ROOT}/post_process/finalize-efi-image.sh

bash -n "${FINALIZE}"
grep -Fq 'bc13c2ff-59e6-4262-a352-b275fd6f7172' "${FINALIZE}"
grep -Fq 'EFI/BOOT/BOOTAA64.EFI' "${FINALIZE}"
grep -Fq 'EFI/systemd/systemd-bootaa64.efi' "${FINALIZE}"
grep -Fq 'EFI/systemd/drivers/ext4aa64.efi' "${FINALIZE}"
grep -Fq 'EFI/systemd/drivers/dtbloaderaa64.efi' "${FINALIZE}"
grep -Fq 'ARMADA_BOOT_BACKEND=efi' "${FINALIZE}"
grep -Fq 'bootprefix=false' "${FINALIZE}"
grep -Fq 'supported-dtbs' "${FINALIZE}"
! grep -Fq 'subvol=root' "${FINALIZE}"

recipe=$(sed -n '/^build-armada-image /,/^\[group/p' "${ROOT}/Justfile")
grep -Fq 'disk-abl.raw' <<< "${recipe}"
grep -Fq 'disk-efi.raw' <<< "${recipe}"
grep -Fq -- '-abl.img.gz' <<< "${recipe}"
grep -Fq -- '-efi.img.gz' <<< "${recipe}"

grep -Fq 'Expected ABL and EFI disk images' "${ROOT}/.github/workflows/pr.yml"
grep -Fq 'Expected ABL and EFI disk images' "${ROOT}/.github/workflows/build-disk.yml"
