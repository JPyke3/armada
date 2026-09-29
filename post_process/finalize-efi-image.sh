#!/bin/bash
set -euxo pipefail

RAW=${1:-output/image/disk-efi.raw}
OUT=${OUT:-output/armada-$(TZ=America/New_York date +%Y%m%d)-efi.img.gz}
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
command -v fdtget >/dev/null
LOOP=$(sudo losetup -fP --show "${RAW}")
trap 'sudo umount "${WORK}/esp" "${WORK}/boot" "${WORK}/root" 2>/dev/null || true; sudo losetup -d "${LOOP}" 2>/dev/null || true; rm -rf "${WORK}"' EXIT

mkdir -p "${WORK}"/{esp,boot,root}
sudo sfdisk --part-type "${LOOP}" 2 0fc63daf-8483-4772-8e79-3d69d8477de4
sudo mount "${LOOP}p1" "${WORK}/esp"
sudo mount "${LOOP}p2" "${WORK}/boot"
sudo mount -o subvol=root "${LOOP}p3" "${WORK}/root"

deploy=$(sudo find "${WORK}/root/ostree/deploy/default/deploy" -mindepth 1 -maxdepth 1 -type d | head -1)
usr=${deploy}/usr
sudo sed -i '\| /boot |s| auto ro | auto rw |' "${deploy}/etc/fstab"
sudo grep -q ' /boot auto rw ' "${deploy}/etc/fstab"
repo=${WORK}/root/ostree/repo/config
sudo sed -i 's/^bootprefix=.*/bootprefix=false/' "${repo}"
sudo grep -qx 'bootprefix=false' "${repo}"
sudo env ARMADA_BOOT_BACKEND=efi ESP="${WORK}/esp" BOOTROOT="${WORK}/boot" \
    SYSROOT="${WORK}/root" \
    BACKEND="${usr}/libexec/armada/armada-boot-backend" \
    ARGS_FILE="${usr}/lib/armada/bootimg-args" CMDLINE=/dev/null \
    "${usr}/libexec/armada/armada-efi-update"
sudo cp -r "${ROOT}/efi/adtbloader" "${WORK}/esp/adtbloader"
sudo sync
sudo umount "${WORK}/esp" "${WORK}/boot" "${WORK}/root"
sudo fatlabel "${LOOP}p1" ARMADA
sudo losetup -d "${LOOP}"
trap 'rm -rf "${WORK}"' EXIT

mkdir -p "$(dirname "${OUT}")"
pigz -f "-${GZIP_LEVEL:-6}" -p "$(nproc)" -c "${RAW}" > "${OUT}"
rm -f "${RAW}"
echo "Built: ${OUT}"
