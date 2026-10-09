#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
moddir=${ROOT}/system_files/usr/lib/dracut/modules.d/91armada-x1e-adsp
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# Exercise the installer with Fedora-style compressed firmware and an updates
# directory. No firmware or kernel modules from the test host are installed.
source "$moddir/module-setup.sh"
fw_dir="$work/updates $work/firmware"
relative=qcom/x1e80100/LENOVO/83ED
mkdir -p "$work/updates/$relative" "$work/firmware/$relative"
printf old > "$work/firmware/$relative/qcadsp8380.mbn.xz"
printf updated > "$work/updates/$relative/qcadsp8380.mbn.zst"
printf dtb > "$work/firmware/$relative/adsp_dtbs.elf.xz"
inst_simple() {
    mkdir -p "$work/image$(dirname "$2")"
    cp -L "$1" "$work/image$2"
}
inst_multiple() { printf '%s\n' "$*" >> "$work/binaries"; }
inst_hook() { printf '%s\n' "$*" > "$work/hook"; }
instmods() { printf '%s:%s\n' "${hostonly:-}" "$*" > "$work/modules"; }
derror() { echo "$*" >&2; }
hostonly=yes installkernel
[[ $(cat "$work/modules") == ':qcom_q6v5_pas' ]] || fail 'driver omitted in hostonly mode'
install
cmp "$work/updates/$relative/qcadsp8380.mbn.zst" "$work/image/usr/lib/firmware/$relative/qcadsp8380.mbn.zst"
cmp "$work/firmware/$relative/adsp_dtbs.elf.xz" "$work/image/usr/lib/firmware/$relative/adsp_dtbs.elf.xz"
[[ $(cat "$work/hook") == "pre-udev 30 $moddir/armada-x1e-adsp.sh" ]] || fail 'wrong startup order'
grep -q 'grep modprobe' "$work/binaries" || fail 'hook dependencies missing'
rm "$work/firmware/$relative/adsp_dtbs.elf.xz"
if install 2> "$work/error"; then fail 'missing firmware accepted'; fi
grep -q adsp_dtbs.elf "$work/error" || fail 'missing firmware not diagnosed'
printf raw > "$work/firmware/$relative/adsp_dtbs.elf"
install
cmp "$work/firmware/$relative/adsp_dtbs.elf" "$work/image/usr/lib/firmware/$relative/adsp_dtbs.elf"

# Run the actual hook with a fake DT compatible property. Other handhelds and
# systems without DT must not eagerly start their remote processors.
for board in yoga handheld absent; do
    case $board in
        yoga) printf 'lenovo,yoga-slim7x\0qcom,x1e80100\0' > "$work/compatible" ;;
        handheld) printf 'ayn,thor\0qcom,sm8550\0' > "$work/compatible" ;;
        absent) rm "$work/compatible" ;;
    esac
    (
        grep() {
            [[ ${*: -1} == /sys/firmware/devicetree/base/compatible ]] || exit 1
            command grep -q "$2" "$work/compatible"
        }
        modprobe() { printf '%s\n' "$*" > "$work/loaded"; }
        source "$moddir/armada-x1e-adsp.sh"
    )
    if [[ $board == yoga ]]; then
        [[ $(cat "$work/loaded") == qcom_q6v5_pas ]] || fail 'Yoga ADSP not started'
        rm "$work/loaded"
    else
        [[ ! -e $work/loaded ]] || fail 'ADSP forced on another board'
    fi
done

# Run the real image generation script with commands stubbed at its boundary.
# This checks that validation rejects silently omitted dracut artifacts.
mkdir -p "$work/bin"
export X1E_TEST_WORK=$work
cat > "$work/bin/ls" <<'EOF'
#!/bin/sh
echo test-kernel
EOF
cat > "$work/bin/mkdir" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$work/bin/dracut" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$X1E_TEST_WORK/dracut-args"
EOF
cat > "$work/bin/lsinitrd" <<'EOF'
#!/bin/sh
cat "$X1E_TEST_WORK/listing"
EOF
chmod +x "$work/bin/"*
cat > "$work/complete" <<'EOF'
usr/lib/systemd/system/armada-splash-initrd.service
usr/lib/systemd/system/dracut-pre-mount.service.d/armada-splash.conf
usr/libexec/armada/armada-splash
usr/libexec/armada/armada-splash-launcher
usr/libexec/armada/device-env
usr/share/armada/splash/splash.asp
usr/libexec/armada/armada-ostree-fallback
usr/lib/systemd/system/ostree-prepare-root.service.d/armada-fallback.conf
usr/lib/ostree/ostree-prepare-root
var/lib/dracut/hooks/pre-udev/30-armada-x1e-adsp.sh
usr/lib/modules/test-kernel/kernel/drivers/remoteproc/qcom_q6v5_pas.ko.xz
usr/lib/firmware/qcom/x1e80100/LENOVO/83ED/qcadsp8380.mbn.zst
usr/lib/firmware/qcom/x1e80100/LENOVO/83ED/adsp_dtbs.elf.xz
EOF
cp "$work/complete" "$work/listing"
PATH="$work/bin:$PATH" bash "$ROOT/build_files/55-generate-initramfs.sh" > "$work/build-log" 2>&1
grep -q -- '--add armada-x1e-adsp' "$work/dracut-args" || fail 'module not requested'
for missing in qcadsp8380 adsp_dtbs qcom_q6v5_pas 30-armada-x1e-adsp; do
    grep -v "$missing" "$work/complete" > "$work/listing"
    # A similarly named backup must not satisfy the archive check.
    grep "$missing" "$work/complete" | sed 's/$/.bak/' >> "$work/listing"
    if PATH="$work/bin:$PATH" bash "$ROOT/build_files/55-generate-initramfs.sh" > "$work/build-log" 2>&1; then
        fail "image accepted without $missing"
    fi
    grep -q 'missing from initramfs' "$work/build-log" || fail 'unexpected build failure'
done

echo 'PASS: x1e-adsp'
