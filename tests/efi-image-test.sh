#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FINALIZE=${ROOT}/post_process/finalize-efi-image.sh

bash -n "${FINALIZE}"
grep -Fq '0fc63daf-8483-4772-8e79-3d69d8477de4' "${FINALIZE}"
grep -Fq '"${usr}/libexec/armada/armada-efi-update"' "${FINALIZE}"
grep -Fq 'BACKEND="${usr}/libexec/armada/armada-boot-backend"' "${FINALIZE}"
grep -Fq 'ARGS_FILE="${usr}/lib/armada/bootimg-args"' "${FINALIZE}"
grep -Fq '"${ROOT}/efi/adtbloader" "${WORK}/esp/adtbloader"' "${FINALIZE}"
grep -Fq 'ARMADA_BOOT_BACKEND=efi' "${FINALIZE}"
grep -Fq 'bootprefix=false' "${FINALIZE}"
grep -Fq 'subvol=root' "${FINALIZE}"
grep -Fq " /boot auto rw " "${FINALIZE}"
! grep -Fq 'systemd-bootaa64.efi' "${FINALIZE}"
! grep -Fq 'loader/entries' "${FINALIZE}"
! grep -i 'refind' "${FINALIZE}"
! grep -i 'grub' "${FINALIZE}"
bash -n "${ROOT}/efi/adtbloader/describe_android_dt.sh"
grep -Fq '/sdcard/adtbloader/active-dtbo.img' "${ROOT}/efi/adtbloader/describe_android_dt.sh"

recipe=$(sed -n '/^build-armada-image /,/^\[group/p' "${ROOT}/Justfile")
grep -Fq 'disk-abl.raw' <<< "${recipe}"
grep -Fq 'disk-efi.raw' <<< "${recipe}"
grep -Fq -- '-abl.img.gz' <<< "${recipe}"
grep -Fq -- '-efi.img.gz' <<< "${recipe}"
grep -Fq 'abl|efi|all' <<< "${recipe}"
grep -Fq 'abl_pid=$!' <<< "${recipe}"
grep -Fq 'efi_pid=$!' <<< "${recipe}"
