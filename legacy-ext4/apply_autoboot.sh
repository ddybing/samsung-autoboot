#!/usr/bin/env bash
#
# apply_autoboot.sh (Legacy ext4 / Android 6-9 / TouchWiz & early One UI)
# Enables automatic boot on power/charger connect and auto-shutdown on disconnect (< 15% battery).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups"
mkdir -p "${BACKUP_DIR}"

echo "=========================================================="
echo " Samsung Auto-Boot Installer (Legacy ext4 / Android 6-9)"
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

# 3. Locate LPM binary
POSSIBLE_PATHS=(
    "/system/bin/lpm"
    "/system/vendor/bin/lpm"
    "/vendor/bin/lpm"
    "/bin/lpm"
)

TARGET_LPM=""
for p in "${POSSIBLE_PATHS[@]}"; do
    if adb shell "su -c '[ -f \"$p\" ] && echo exists'" 2>/dev/null | grep -q "exists"; then
        TARGET_LPM="$p"
        break
    fi
done

if [[ -z "${TARGET_LPM}" ]]; then
    echo "[!] Error: Could not locate 'lpm' binary in known paths: ${POSSIBLE_PATHS[*]}"
    exit 1
fi
echo "[+] Found LPM binary at: ${TARGET_LPM}"

MOUNT_POINT="/system"
if [[ "${TARGET_LPM}" =~ ^/vendor ]]; then
    MOUNT_POINT="/vendor"
fi

# 4. Backup original binary
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
HOST_BACKUP="${BACKUP_DIR}/lpm_${DEVICE_MODEL}_${TIMESTAMP}.orig"
echo "[*] Backing up original LPM binary to host: ${HOST_BACKUP}"
adb shell "su -c 'cp -p \"${TARGET_LPM}\" \"${TARGET_LPM}.orig\" 2>/dev/null || true'"
adb pull "${TARGET_LPM}" "${HOST_BACKUP}"

SELINUX_CTX="$(adb shell "su -c 'ls -Z \"${TARGET_LPM}\"'" | tr -d '\r' | awk '{print $1}')"
echo "[+] Current SELinux context: ${SELINUX_CTX}"

# 5. Push payload script to device
PAYLOAD_TMP="/data/local/tmp/lpm_autoboot.sh"
adb push "${SCRIPT_DIR}/lpm_payload.sh" "${PAYLOAD_TMP}"

# 6. Apply patch: remount rw, overwrite via cat to preserve inode, restore permissions/SELinux, remount ro
echo "[*] Applying patch to ${TARGET_LPM}..."
adb shell "su -c '
    BB=\"/data/adb/magisk/busybox\"
    if [ ! -x \"\$BB\" ]; then
        BB=\"busybox\"
    fi

    # Remount target filesystem read-write
    \$BB mount -o remount,rw \"${MOUNT_POINT}\" 2>/dev/null || mount -o remount,rw \"${MOUNT_POINT}\" 2>/dev/null || true

    # Overwrite content using cat to preserve file inode
    cat \"${PAYLOAD_TMP}\" > \"${TARGET_LPM}\"

    # Set proper permissions and ownership
    chmod 0755 \"${TARGET_LPM}\"
    chown root:shell \"${TARGET_LPM}\"

    # Preserve or assign proper SELinux context
    if [ -n \"${SELINUX_CTX}\" ] && [ \"${SELINUX_CTX}\" != \"?\" ]; then
        chcon \"${SELINUX_CTX}\" \"${TARGET_LPM}\" 2>/dev/null || true
    else
        chcon u:object_r:lpm_exec:s0 \"${TARGET_LPM}\" 2>/dev/null || true
    fi

    # Disable stock recovery restore script if present
    if [ -f /system/recovery-from-boot.p ]; then
        mv /system/recovery-from-boot.p /system/recovery-from-boot.p.bak 2>/dev/null || true
    fi

    # Sync and remount read-only
    sync
    \$BB mount -o remount,ro \"${MOUNT_POINT}\" 2>/dev/null || mount -o remount,ro \"${MOUNT_POINT}\" 2>/dev/null || true
    rm -f \"${PAYLOAD_TMP}\"
'"

# 7. Install Auto-Shutdown Daemon
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
echo " [SUCCESS] Auto-boot on charger successfully configured!"
echo " Backup saved to: ${HOST_BACKUP}"
echo "=========================================================="
