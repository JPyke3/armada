#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

pocket_ds_conf="$ROOT/system_files/usr/lib/armada/devices/ayaneo-pocket-ds.conf"
setup_dual="$ROOT/system_files/usr/libexec/armada/setup-dual-screen"
session_control="$ROOT/system_files/usr/libexec/armada/session-control"

# Pocket DS advertises the lower panel to desktop-bootstrap, while gamescope
# still targets the primary connector through sessions.d/steam.
grep -q '^ARMADA_PRIMARY_CONNECTOR=DSI-1$' "$pocket_ds_conf"
grep -q '^ARMADA_SECONDARY_CONNECTOR=DSI-2$' "$pocket_ds_conf"
grep -q "^ARMADA_PRIMARY_TOUCHSCREEN='Generic ft5x06 (44)'$" "$pocket_ds_conf"
grep -q "^ARMADA_SECONDARY_TOUCHSCREEN='Goodix Capacitive TouchScreen'$" "$pocket_ds_conf"

# Desktop setup must actively re-enable the second output, not just position it.
grep -q 'f"output.{primary}.enable"' "$setup_dual"
grep -q 'f"output.{secondary}.enable"' "$setup_dual"
grep -q 'dual_required=1' "$ROOT/system_files/usr/libexec/armada/desktop-bootstrap"
grep -q 'elif /usr/libexec/armada/setup-dual-screen; then' "$ROOT/system_files/usr/libexec/armada/desktop-bootstrap"

# Switching back to game mode should explicitly disable the secondary output
# and inhibit lower touch before leaving Plasma, so the second panel remains
# desktop-only and the dark lower digitizer cannot steer Steam during handoff.
grep -q 'set_secondary_touchscreen 1' "$session_control"
grep -q 'set_secondary_output disable' "$session_control"
grep -q 'touchscreen-inhibit "${ARMADA_SECONDARY_TOUCHSCREEN}" "${inhibited}"' "$session_control"
grep -q 'kscreen-doctor "output.${ARMADA_SECONDARY_CONNECTOR}.${state}"' "$session_control"

grep -q 'touchscreen-inhibit "$ARMADA_SECONDARY_TOUCHSCREEN" 1' "$ROOT/system_files/etc/gamescope-session-plus/sessions.d/steam"
grep -q 'touchscreen-inhibit "$ARMADA_SECONDARY_TOUCHSCREEN" 0' "$ROOT/system_files/usr/libexec/armada/desktop-bootstrap"

python3 -m py_compile "$setup_dual"
bash -n "$session_control"

printf 'Pocket DS desktop-only dual-screen checks passed\n'
