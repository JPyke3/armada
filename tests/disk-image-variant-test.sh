#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap

root = Path(sys.argv[1])
recipe = (root / 'Justfile').read_text().split('build-armada-image $', 1)[1]
recipe = textwrap.dedent(recipe.split('\n', 1)[1].split('\n[group(', 1)[0])
for variant in ('handheld', 'desktop', None, 'invalid'):
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        (work / 'bin').mkdir()
        (work / 'post_process').mkdir()
        podman = work / 'bin/podman'
        podman.write_text('#!/bin/bash\nprintf "%s\\n" "$INSPECTION"\n')
        podman.chmod(0o755)
        for name in ('make-bootimg.sh', 'finalize-armada-image.sh'):
            script = work / 'post_process' / name
            script.write_text('#!/bin/bash\nprintf "%s\\n" "${OUT:-}" >> "$TEST_LOG"\n')
            script.chmod(0o755)
        labels = {'org.opencontainers.image.version': '20261009.abcdef0'}
        if variant is not None:
            labels['dev.armada.variant'] = variant
        log = work / 'log'
        env = dict(os.environ, PATH=str(work / 'bin') + ':' + os.environ['PATH'],
                   target_image='localhost/fixture', tag='testing', TEST_LOG=str(log),
                   INSPECTION=json.dumps([{'Config': {'Labels': labels}}]))
        result = subprocess.run(['bash', '-c', recipe], cwd=work, env=env,
                                capture_output=True, text=True)
        if variant == 'invalid':
            assert result.returncode != 0 and not log.exists(), result.stderr
        else:
            assert result.returncode == 0, result.stderr
            prefix = 'armada-desktop' if variant == 'desktop' else 'armada'
            assert log.read_text().splitlines()[-1] == f'output/{prefix}-20261009.abcdef0.img.gz'
        print(f'PASS: disk filename for {variant or "legacy handheld"}')
PY
