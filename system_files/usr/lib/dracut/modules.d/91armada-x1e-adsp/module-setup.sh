#!/bin/bash
# Board firmware names come from the Yoga DTB, not MODULE_FIRMWARE, so
# dracut's generic module dependency scan does not include them.

check() {
    return 255
}

depends() {
    echo kernel-modules
}

installkernel() {
    hostonly='' instmods qcom_q6v5_pas
}

install() {
    local name dir suffix found
    for name in qcadsp8380.mbn adsp_dtbs.elf; do
        found=
        # Respect dracut's firmware search order, including updates directories.
        for dir in $fw_dir; do
            for suffix in '' .xz .zst; do
                if [[ -f "$dir/qcom/x1e80100/LENOVO/83ED/$name$suffix" ]]; then
                    inst_simple "$dir/qcom/x1e80100/LENOVO/83ED/$name$suffix" \
                        "/usr/lib/firmware/qcom/x1e80100/LENOVO/83ED/$name$suffix" || return 1
                    found=1
                    break 2
                fi
            done
        done
        if [[ -z $found ]]; then
            derror "Yoga USB boot requires ADSP firmware: qcom/x1e80100/LENOVO/83ED/$name"
            return 1
        fi
    done

    inst_multiple grep modprobe || return 1
    inst_hook pre-udev 30 "$moddir/armada-x1e-adsp.sh"
}
