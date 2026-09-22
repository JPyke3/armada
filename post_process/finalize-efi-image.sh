#!/bin/bash
set -euxo pipefail

RAW=${1:-output/image/disk-efi.raw}
OUT=${OUT:-output/armada-$(TZ=America/New_York date +%Y%m%d)-efi.img.gz}
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DTB_LIST=${ROOT}/system_files/usr/lib/armada/supported-dtbs
WORK=$(mktemp -d)
LOOP=$(sudo losetup -fP --show "${RAW}")
trap 'sudo umount "${WORK}/esp" "${WORK}/boot" "${WORK}/root" 2>/dev/null || true; sudo losetup -d "${LOOP}" 2>/dev/null || true; rm -rf "${WORK}"' EXIT

mkdir -p "${WORK}"/{esp,boot,root}
sudo sfdisk --part-type "${LOOP}" 2 bc13c2ff-59e6-4262-a352-b275fd6f7172
sudo mount "${LOOP}p1" "${WORK}/esp"
sudo mount "${LOOP}p2" "${WORK}/boot"
sudo mount -o subvol=root "${LOOP}p3" "${WORK}/root"

deploy=$(sudo find "${WORK}/root/ostree/deploy/default/deploy" -mindepth 1 -maxdepth 1 -type d | head -1)
usr=${deploy}/usr
loader=${usr}/lib/systemd/boot/efi/systemd-bootaa64.efi
ext4=${usr}/share/edk2/drivers/ext4aa64.efi
dtbloader=${usr}/lib/armada/efi/drivers/dtbloaderaa64.efi
sudo test -s "${loader}"
sudo test -s "${ext4}"
sudo test -s "${dtbloader}"

sudo mkdir -p "${WORK}/esp/EFI/BOOT" "${WORK}/esp/EFI/systemd/drivers" \
    "${WORK}/esp/armada" "${WORK}/esp/loader" "${WORK}/esp/dtbloader/dtbs/qcom"
sudo cp "${loader}" "${WORK}/esp/EFI/BOOT/BOOTAA64.EFI"
sudo cp "${loader}" "${WORK}/esp/EFI/systemd/systemd-bootaa64.efi"
sudo cp "${ext4}" "${WORK}/esp/EFI/systemd/drivers/ext4aa64.efi"
sudo cp "${dtbloader}" "${WORK}/esp/EFI/systemd/drivers/dtbloaderaa64.efi"
printf 'ARMADA_BOOT_BACKEND=efi\nARMADA_BOOT_CONTRACT=1\n' \
    | sudo tee "${WORK}/esp/armada/backend.conf" >/dev/null
printf 'timeout 5\neditor no\n' | sudo tee "${WORK}/esp/loader/loader.conf" >/dev/null

mapfile -t entries < <(sudo find -L "${WORK}/boot/loader/entries" -maxdepth 1 -name '*.conf' -type f)
[ "${#entries[@]}" -gt 0 ]
for entry in "${entries[@]}"; do
    sudo sed -i -e 's|^title .*|title Armada OS (Automatic)|' \
        -e 's|^linux /boot/|linux /|' -e 's|^initrd /boot/|initrd /|' \
        -e '/^fdtdir /d' -e 's/ armada\.dtb=[^ ]*//g' \
        -e 's|^options |options armada.dtb=auto |' "${entry}"
    linux=$(sudo sed -n 's/^linux //p' "${entry}" | head -1)
    while read -r name; do
        sudo test -f "${WORK}/boot$(dirname "${linux}")/dtb/qcom/${name}.dtb"
        device=${entry%.conf}-dtb-${name}.conf
        sudo cp "${entry}" "${device}"
        sudo sed -i -e "s|^title .*|title Armada OS (${name})|" \
            -e "s|armada.dtb=auto|armada.dtb=${name}|" "${device}"
        printf 'devicetree %s/dtb/qcom/%s.dtb\n' "$(dirname "${linux}")" "${name}" \
            | sudo tee -a "${device}" >/dev/null
    done < "${DTB_LIST}"
done

linux=$(sudo sed -n 's/^linux //p' "${entries[0]}" | head -1)
dtbs=${WORK}/boot/$(dirname "${linux}")/dtb/qcom
sudo find "${dtbs}" -maxdepth 1 -type f -name '*.dtb' \
    -exec cp -t "${WORK}/esp/dtbloader/dtbs/qcom" {} +

repo=${WORK}/root/ostree/repo/config
sudo sed -i 's/^bootprefix=.*/bootprefix=false/' "${repo}"
sudo grep -qx 'bootprefix=false' "${repo}"
sudo sync
sudo umount "${WORK}/esp" "${WORK}/boot" "${WORK}/root"
sudo fatlabel "${LOOP}p1" ARMADA
sudo losetup -d "${LOOP}"
trap 'rm -rf "${WORK}"' EXIT

mkdir -p "$(dirname "${OUT}")"
pigz -f "-${GZIP_LEVEL:-6}" -p "$(nproc)" -c "${RAW}" > "${OUT}"
rm -f "${RAW}"
echo "Built: ${OUT}"
