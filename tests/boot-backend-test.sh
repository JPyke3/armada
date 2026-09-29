#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BACKEND=${ROOT}/system_files/usr/libexec/armada/armada-boot-backend
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

[ "$(ESP=${work} "${BACKEND}")" = unknown ]
mkdir -p "${work}/armada"
printf 'ARMADA_BOOT_BACKEND=efi\nARMADA_BOOT_CONTRACT=1\n' > "${work}/armada/backend.conf"
[ "$(ESP=${work} "${BACKEND}")" = efi ]
ESP=${work} "${BACKEND}" is efi
! ESP=${work} "${BACKEND}" is abl
printf 'ARMADA_BOOT_BACKEND=efi\nARMADA_BOOT_CONTRACT=2\n' > "${work}/armada/backend.conf"
[ "$(ESP=${work} "${BACKEND}")" = unknown ]
rm "${work}/armada/backend.conf"
printf x > "${work}/KERNEL"
[ "$(ESP=${work} "${BACKEND}")" = abl ]

grep -Fq 'ExecCondition=/usr/libexec/armada/armada-boot-backend is abl' \
    "${ROOT}/system_files/usr/lib/systemd/system/armada-bootimg-sync.service"
