#!/system/bin/sh
#
# lpm_payload.sh - Replaces /system/bin/lpm on legacy ext4 Samsung devices
# Triggers an immediate reboot into full Android when connected to charger.
#
echo "AUTOBOOT: Charger connected, rebooting..." > /dev/kmsg 2>/dev/null || true
/system/bin/reboot 2>/dev/null || true
sleep 1
/system/bin/setprop sys.powerctl reboot 2>/dev/null || true
sleep 1
echo 1 > /proc/sys/kernel/sysrq 2>/dev/null || true
echo b > /proc/sysrq-trigger 2>/dev/null || true
