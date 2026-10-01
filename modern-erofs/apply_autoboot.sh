#!/usr/bin/env bash
#
# apply_autoboot.sh (Modern EROFS / One UI 2-6 / Android 10-14)
# Enables automatic boot on power/charger connect and auto-shutdown on disconnect (< 15% battery).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================================="
echo " Samsung Auto-Boot Installer (Modern EROFS / Android 10+)"
echo "=========================================================="

# 1. Verify ADB connection
if ! adb get-state 1>/dev/null 2>&1; then
    echo "[!] Error: No ADB device detected. Ensure USB debugging is enabled."
    exit 1
fi

DEVICE_MODEL="$(adb shell getprop ro.product.model | tr -d '\r')"
ANDROID_VER="$(adb shell getprop ro.build.version.release | tr -d '\r')"
echo "[+] Connected to: ${DEVICE_MODEL} (Android ${ANDROID_VER})"

# 2. Verify Root
ROOT_CHECK="$(adb shell "su -c 'id'" 2>/dev/null | tr -d '\r' || true)"
if [[ ! "${ROOT_CHECK}" =~ "uid=0(root)" ]]; then
    echo "[!] Error: Root access via 'su' is required. Please grant root permissions in Magisk."
    exit 1
fi
echo "[+] Root access confirmed: ${ROOT_CHECK}"

# 3. Patch Boot Partition Ramdisk
echo "[*] Applying boot image ramdisk overlay and magiskinit hex-patch..."
adb shell "su -c '
mkdir -p /data/local/tmp/autoboot_patch && cd /data/local/tmp/autoboot_patch

# 1. Unpack boot partition
cp /dev/block/by-name/boot boot_orig.img
/data/adb/magisk/magiskboot unpack boot_orig.img

# 2. Extract init, hexpatch charger -> nocharg, re-add to ramdisk
# Prevents Magisk Rust init from aborting during off-mode charging
/data/adb/magisk/magiskboot cpio ramdisk.cpio \"extract init init_bin\"
/data/adb/magisk/magiskboot hexpatch init_bin 6368617267657200 6e6f636861726700
/data/adb/magisk/magiskboot cpio ramdisk.cpio \"add 0750 init init_bin\"

# 3. Add overlay.d/autoboot.rc
# \"reboot,lpm\" signals the Little Kernel (LK) bootloader to perform a cold
# NORMAL_BOOT with TrustZone/TEE fully initialized.
cat << \"EOF\" > autoboot.rc
on charger
    setprop sys.powerctl \"reboot,lpm\"

on property:ro.bootmode=charger
    setprop sys.powerctl \"reboot,lpm\"
EOF

/data/adb/magisk/magiskboot cpio ramdisk.cpio \"add 0644 overlay.d/autoboot.rc autoboot.rc\"

# 4. Repack and flash
/data/adb/magisk/magiskboot repack boot_orig.img new_boot.img
dd if=new_boot.img of=/dev/block/by-name/boot bs=4096
sync

# 5. Clean up
cd /data/local/tmp
rm -rf /data/local/tmp/autoboot_patch
'"

# 4. Install Auto-Shutdown Daemon
echo "[*] Installing auto-shutdown power monitor daemon..."
adb push "${SCRIPT_DIR}/power_monitor.sh" /data/local/tmp/power_monitor.sh
adb shell "su -c '
mkdir -p /data/adb/service.d
cp /data/local/tmp/power_monitor.sh /data/adb/service.d/power_monitor.sh
chmod 0755 /data/adb/service.d/power_monitor.sh
chown root:root /data/adb/service.d/power_monitor.sh
rm -f /data/local/tmp/power_monitor.sh
'"
echo "[+] Power monitor daemon installed to /data/adb/service.d/power_monitor.sh"

echo ""
echo "=========================================================="
echo " [SUCCESS] Auto-boot and power monitor installed!"
echo " Device: ${DEVICE_MODEL}"
echo "=========================================================="
