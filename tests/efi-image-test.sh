#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FINALIZE=${ROOT}/post_process/finalize-efi-image.sh

bash -n "${FINALIZE}"
grep -Fq 'bc13c2ff-59e6-4262-a352-b275fd6f7172' "${FINALIZE}"
grep -Fq 'EFI/BOOT/BOOTAA64.EFI' "${FINALIZE}"
grep -Fq 'EFI/systemd/systemd-bootaa64.efi' "${FINALIZE}"
grep -Fq 'EFI/systemd/drivers/ext4aa64.efi' "${FINALIZE}"
! grep -Fq 'EFI/systemd/drivers/dtbloaderaa64.efi' "${FINALIZE}"
grep -Fq 'timeout menu-force' "${FINALIZE}"
grep -Fq 'ARMADA_BOOT_BACKEND=efi' "${FINALIZE}"
grep -Fq 'bootprefix=false' "${FINALIZE}"
grep -Fq 'supported-dtbs' "${FINALIZE}"
grep -Fq 'subvol=root' "${FINALIZE}"
grep -Fq 'find -L "${WORK}/boot/loader/entries"' "${FINALIZE}"
grep -Fq " /boot auto rw " "${FINALIZE}"
grep -Fq 'armada.device=auto' "${FINALIZE}"
! grep -Fq 'armada.dtb=' "${FINALIZE}"

recipe=$(sed -n '/^build-armada-image /,/^\[group/p' "${ROOT}/Justfile")
grep -Fq 'disk-abl.raw' <<< "${recipe}"
grep -Fq 'disk-efi.raw' <<< "${recipe}"
grep -Fq -- '-abl.img.gz' <<< "${recipe}"
grep -Fq -- '-efi.img.gz' <<< "${recipe}"
grep -Fq 'abl_pid=$!' <<< "${recipe}"
grep -Fq 'efi_pid=$!' <<< "${recipe}"

grep -Fq 'Expected ABL and EFI disk images' "${ROOT}/.github/workflows/pr.yml"
grep -Fq 'armada-disk-pr${{ github.event.pull_request.number }}-abl' "${ROOT}/.github/workflows/pr.yml"
grep -Fq 'armada-disk-pr${{ github.event.pull_request.number }}-efi' "${ROOT}/.github/workflows/pr.yml"
grep -Fq '^armada-disk-pr[0-9]+-(abl|efi)$' "${ROOT}/.github/workflows/pr-disk-link.yml"
grep -Fq 'Expected ABL and EFI disk images' "${ROOT}/.github/workflows/build-disk.yml"
