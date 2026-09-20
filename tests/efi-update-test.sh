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
    "${deploy}/usr/share/edk2/drivers" "${deploy}/usr/lib/armada/efi/drivers" "${bootdir}/dtb/qcom"
printf 'ARMADA_BOOT_BACKEND=efi\nARMADA_BOOT_CONTRACT=1\n' > "${esp}/armada/backend.conf"
printf loader > "${deploy}/usr/lib/systemd/boot/efi/systemd-bootaa64.efi"
printf ext4 > "${deploy}/usr/share/edk2/drivers/ext4aa64.efi"
printf dtbloader > "${deploy}/usr/lib/armada/efi/drivers/dtbloaderaa64.efi"
printf thor > "${bootdir}/dtb/qcom/qcs8550-ayn-thor.dtb"
printf x1e > "${bootdir}/dtb/qcom/x1e-test.dtb"
printf 'qcs8550-ayn-thor\nx1e-test\n' > "${deploy}/usr/lib/armada/supported-dtbs"
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

PATH=${work}/bin:${PATH} ESP=${esp} BOOTROOT=${boot} SYSROOT=${sysroot} \
    BACKEND=${ROOT}/system_files/usr/libexec/armada/armada-boot-backend \
    ARGS_FILE=${ROOT}/system_files/usr/lib/armada/bootimg-args "${UPDATE}"

cmp "${deploy}/usr/lib/systemd/boot/efi/systemd-bootaa64.efi" "${esp}/EFI/BOOT/BOOTAA64.EFI"
cmp "${deploy}/usr/share/edk2/drivers/ext4aa64.efi" "${esp}/EFI/systemd/drivers/ext4aa64.efi"
cmp "${deploy}/usr/lib/armada/efi/drivers/dtbloaderaa64.efi" "${esp}/EFI/systemd/drivers/dtbloaderaa64.efi"
grep -qx 'title Armada OS (Automatic)' "${boot}/loader/entries/ostree-1.conf"
grep -qx 'title Armada OS (qcs8550-ayn-thor)' "${boot}/loader/entries/ostree-1-dtb-qcs8550-ayn-thor.conf"
grep -qx 'devicetree /ostree/default-test/dtb/qcom/qcs8550-ayn-thor.dtb' \
    "${boot}/loader/entries/ostree-1-dtb-qcs8550-ayn-thor.conf"
grep -qx 'title Armada OS (x1e-test)' "${boot}/loader/entries/ostree-1-dtb-x1e-test.conf"
! grep -q '^fdtdir ' "${boot}/loader/entries/ostree-1.conf"
grep -qx 'ARMADA_BOOT_BACKEND=efi' "${esp}/armada/backend.conf"

unit=${ROOT}/system_files/usr/lib/systemd/system/armada-efi-sync.service
grep -Fq 'ExecCondition=/usr/libexec/armada/armada-boot-backend is efi' "${unit}"
grep -Fq 'systemctl enable armada-efi-sync.service' "${ROOT}/build_files/40-vendor-system-files.sh"
