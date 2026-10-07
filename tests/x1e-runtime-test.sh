#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT" <<'PY'
import hashlib
import os
from pathlib import Path
import runpy
import struct
import subprocess
import sys
from unittest.mock import patch

root = Path(sys.argv[1])
firmware = root / 'system_files/usr/lib/firmware/ath12k/WCN7850/hw2.0/board-2.bin'
data = firmware.read_bytes()
assert data[:20] == b'QCA-ATH12K-BOARD\0mmm'
assert hashlib.sha256(data[:113260]).hexdigest() == '8cc9a64baf68681ece5e26a8445630749eccbfb4517bdbf6802856787afa7c2d', 'existing handheld data changed'

def records(blob, offset=0):
    while offset < len(blob):
        kind, size = struct.unpack_from('<II', blob, offset)
        end = offset + 8 + size
        assert end <= len(blob), 'truncated board entry'
        yield kind, blob[offset + 8:end]
        offset = end + (-size % 4)
    assert offset == len(blob), 'invalid board padding'

name = b'bus=pci,vendor=17cb,device=1107,subsystem-vendor=17aa,subsystem-device=e0e9,qmi-chip-id=2,qmi-board-id=255'
matches = []
for kind, value in records(data, 20):
    entries = list(records(value))
    if kind == 0 and (0, name) in entries:
        matches.extend(v for k, v in entries if k == 1)
assert len(matches) == 1, 'missing or duplicate Yoga board data'
assert hashlib.sha256(matches[0]).hexdigest() == 'd4f92e9f11bc530d7287f346b96ad3f7e56e6ad6c12f2a0977b267a0ee274a6a'

controller = runpy.run_path(str(root / 'system_files/usr/libexec/armada/controller-type'))
main = controller['main']
settings = controller['device_settings']
profile_dir = root / 'system_files/usr/lib/armada/devices'
device_env = root / 'system_files/usr/libexec/armada/device-env'

def refuse_poll(value):
    raise AssertionError('must skip controller polling')

for model, expected in [('Lenovo Yoga Slim 7x', '0'), ('AYN Thor', '1'), ('Unknown device', '1')]:
    env = dict(os.environ, ARMADA_DEVICE_DIR=str(profile_dir), ARMADA_MODEL=model,
               ARMADA_SLEEP_CONFIG='/nonexistent', ARMADA_MEM_SLEEP_PATH='/nonexistent')
    result = subprocess.run([str(device_env)], env=env, capture_output=True, text=True, check=True)
    with patch.object(subprocess, 'run', return_value=result):
        assert settings()['ARMADA_BUILTIN_GAMEPAD'] == expected
        if model == 'Lenovo Yoga Slim 7x':
            assert settings()['ARMADA_PRIMARY_CONNECTOR'] == 'eDP-1'
            assert settings()['ARMADA_DEVICE_ID'] == 'lenovo-yoga-slim7x'
        with patch.dict(main.__globals__, apply_with_retry=refuse_poll if expected == '0' else lambda value: False):
            assert main(['controller-type', 'apply']) == (0 if expected == '0' else 1)

# An explicit controller request still applies on laptops; failures must not
# silently change the saved setting. A failed profile lookup also fails open.
with patch.dict(main.__globals__, device_settings=lambda: {'ARMADA_BUILTIN_GAMEPAD': '0'}, apply_with_retry=lambda value: False):
    assert main(['controller-type', 'set', 'ds5']) == 1
with patch.object(subprocess, 'run', side_effect=OSError('device-env unavailable')):
    assert settings() == {}
    assert controller['available_types']() == list(controller['CONTROLLER_TYPES'])
print('PASS: x1e-runtime')
PY
