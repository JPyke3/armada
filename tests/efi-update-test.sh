#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
UPDATE=${ROOT}/system_files/usr/libexec/armada/armada-efi-update
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT
esp=${work}/esp
boot=${work}/boot
sysroot=${work}/sysroot
deploy=${sysroot}/ostree/deploy/default/deploy/test.0
bootdir=${boot}/ostree/default-test
mkdir -p "${esp}/armada" "${boot}/loader/entries" "${deploy}/usr/lib/systemd/boot/efi" \
    "${deploy}/usr/share/edk2/drivers" "${deploy}/usr/lib/armada" "${bootdir}/dtb/qcom"
printf 'ARMADA_BOOT_BACKEND=efi\nARMADA_BOOT_CONTRACT=1\n' > "${esp}/armada/backend.conf"
mkdir -p "${esp}/EFI/systemd/drivers"
printf stale > "${esp}/EFI/systemd/drivers/dtbloaderaa64.efi"
printf loader > "${deploy}/usr/lib/systemd/boot/efi/systemd-bootaa64.efi"
printf ext4 > "${deploy}/usr/share/edk2/drivers/ext4aa64.efi"
printf thor > "${bootdir}/dtb/qcom/qcs8550-ayn-thor.dtb"
printf x1e > "${bootdir}/dtb/qcom/x1e-test.dtb"
printf 'qcs8550-ayn-thor\n' > "${deploy}/usr/lib/armada/supported-dtbs"
cat > "${boot}/loader/entries/ostree-1.conf" <<EOF
title old
version 2
options ostree=/ostree/deploy/default/deploy/test.0
linux /ostree/default-test/vmlinuz
initrd /ostree/default-test/initramfs
fdtdir /ostree/default-test/dtb
EOF
mkdir "${work}/bin"
printf '#!/bin/sh\nexit 0\n' > "${work}/bin/findmnt"
chmod +x "${work}/bin/findmnt"
printf 'quiet armada.device=qcs8550-ayn-thor\n' > "${work}/cmdline"

PATH=${work}/bin:${PATH} ESP=${esp} BOOTROOT=${boot} SYSROOT=${sysroot} \
    CMDLINE=${work}/cmdline \
    BACKEND=${ROOT}/system_files/usr/libexec/armada/armada-boot-backend \
    ARGS_FILE=${ROOT}/system_files/usr/lib/armada/bootimg-args "${UPDATE}"

cmp "${deploy}/usr/lib/systemd/boot/efi/systemd-bootaa64.efi" "${esp}/EFI/BOOT/BOOTAA64.EFI"
cmp "${deploy}/usr/share/edk2/drivers/ext4aa64.efi" "${esp}/EFI/systemd/drivers/ext4aa64.efi"
! test -e "${esp}/EFI/systemd/drivers/dtbloaderaa64.efi"
grep -qx 'title Armada OS (Automatic)' "${boot}/loader/entries/ostree-1.conf"
grep -qx 'title Armada OS (qcs8550-ayn-thor)' "${boot}/loader/entries/ostree-1-dtb-qcs8550-ayn-thor.conf"
grep -q '^options armada.device=qcs8550-ayn-thor ' \
    "${boot}/loader/entries/ostree-1-dtb-qcs8550-ayn-thor.conf"
grep -qx 'devicetree /ostree/default-test/dtb/qcom/qcs8550-ayn-thor.dtb' \
    "${boot}/loader/entries/ostree-1-dtb-qcs8550-ayn-thor.conf"
! test -e "${boot}/loader/entries/ostree-1-dtb-x1e-test.conf"
grep -q '^options armada.device=auto ' "${boot}/loader/entries/ostree-1.conf"
! grep -q '^fdtdir ' "${boot}/loader/entries/ostree-1.conf"
grep -qx 'ARMADA_BOOT_BACKEND=efi' "${esp}/armada/backend.conf"
grep -qx 'qcs8550-ayn-thor' "${esp}/armada/device"
grep -Fqx 'default *-dtb-qcs8550-ayn-thor' "${esp}/loader/loader.conf"

printf 'quiet armada.device=auto\n' > "${work}/cmdline"
PATH=${work}/bin:${PATH} ESP=${esp} BOOTROOT=${boot} SYSROOT=${sysroot} \
    CMDLINE=${work}/cmdline \
    BACKEND=${ROOT}/system_files/usr/libexec/armada/armada-boot-backend \
    ARGS_FILE=${ROOT}/system_files/usr/lib/armada/bootimg-args "${UPDATE}"
! test -e "${esp}/armada/device"
! grep -q '^default ' "${esp}/loader/loader.conf"
grep -Fxq 'timeout menu-force' "${esp}/loader/loader.conf"

unit=${ROOT}/system_files/usr/lib/systemd/system/armada-efi-sync.service
grep -Fq 'ExecCondition=/usr/libexec/armada/armada-boot-backend is efi' "${unit}"
grep -Fq 'systemctl enable armada-efi-sync.service' "${ROOT}/build_files/40-vendor-system-files.sh"
