#!/system/bin/sh
#
# power_monitor.sh - Auto-shutdown daemon when disconnected & battery below threshold
# Location: /data/adb/service.d/power_monitor.sh
#

# Default configuration
THRESHOLD=15
CHECK_INTERVAL=5
GRACE_CHECKS=2
LOG_FILE="/data/adb/power_monitor.log"

# Wait until Android has finished booting
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 3
done

# Optional user config override
CONF_FILE="/data/adb/power_monitor.conf"
if [ -f "$CONF_FILE" ]; then
    . "$CONF_FILE"
fi

# Limit log file size to 100KB to prevent filling storage
if [ -f "$LOG_FILE" ] && [ "$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)" -gt 102400 ]; then
    tail -n 200 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Power monitor started (Threshold: ${THRESHOLD}%, Grace: $((GRACE_CHECKS * CHECK_INTERVAL))s)" >> "$LOG_FILE"

DISCONNECT_COUNT=0

while true; do
    # Reload config if updated
    if [ -f "$CONF_FILE" ]; then
        . "$CONF_FILE"
    fi

    # Read power status
    USB=$(cat /sys/class/power_supply/usb/online 2>/dev/null || echo 0)
    AC=$(cat /sys/class/power_supply/ac/online 2>/dev/null || echo 0)
    WIRELESS=$(cat /sys/class/power_supply/wireless/online 2>/dev/null || echo 0)
    BATT_STATUS=$(cat /sys/class/power_supply/battery/status 2>/dev/null || echo "Discharging")
    CAPACITY=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo 100)

    # Sanitize capacity to integer
    case "$CAPACITY" in
        ''|*[!0-9]*) CAPACITY=100 ;;
    esac

    # Determine if external power is supplied
    POWER_CONNECTED=0
    if [ "$USB" = "1" ] || [ "$AC" = "1" ] || [ "$WIRELESS" = "1" ] || [ "$BATT_STATUS" = "Charging" ]; then
        POWER_CONNECTED=1
    fi

    if [ "$POWER_CONNECTED" -eq 1 ]; then
        if [ "$DISCONNECT_COUNT" -gt 0 ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Power reconnected. Resetting disconnect counter." >> "$LOG_FILE"
        fi
        DISCONNECT_COUNT=0
    else
        # Power disconnected: check battery level
        if [ "$CAPACITY" -lt "$THRESHOLD" ]; then
            DISCONNECT_COUNT=$((DISCONNECT_COUNT + 1))
            echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] Power disconnected & battery ${CAPACITY}% < ${THRESHOLD}% (Check ${DISCONNECT_COUNT}/${GRACE_CHECKS})" >> "$LOG_FILE"

            if [ "$DISCONNECT_COUNT" -ge "$GRACE_CHECKS" ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') [CRITICAL] Initiating shutdown (Battery: ${CAPACITY}%, Threshold: ${THRESHOLD}%)..." >> "$LOG_FILE"
                echo "POWER_MONITOR: Shutting down due to power disconnected and battery ${CAPACITY}% < ${THRESHOLD}%" > /dev/kmsg 2>/dev/null || true
                
                # Flush disk caches before shutting down (safeguards open databases)
                sync
                
                # Standard clean Android poweroff
                /system/bin/reboot -p 2>/dev/null || true
                
                # Fallbacks in case reboot -p blocks
                sleep 5
                setprop sys.powerctl shutdown 2>/dev/null || true
                sleep 5
                echo 1 > /proc/sys/kernel/sysrq 2>/dev/null || true
                echo o > /proc/sysrq-trigger 2>/dev/null || true
                exit 0
            fi
        else
            DISCONNECT_COUNT=0
        fi
    fi

    sleep "$CHECK_INTERVAL"
done
