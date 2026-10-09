#!/bin/sh
# Follow dracut's upstream qcom-adsp pre-udev ordering (PR #2302): loading
# ADSP resets USB-C, so do it before udev discovers and mounts the root disk.
# Firmware bundled by this module is specific to the Yoga Slim 7x.
if grep -q 'lenovo,yoga-slim7x' /sys/firmware/devicetree/base/compatible 2>/dev/null; then
    modprobe qcom_q6v5_pas
fi
