# Modern Samsung Auto-Boot (EROFS / Android 10–14 / One UI 2–6)

Target devices: Samsung Galaxy A-series, S-series (S20+), Z-series, and any modern device using **Dynamic Partitions (`super.img`)**, **`erofs`** filesystems, and **MediaTek or Exynos** SoCs.

---

## The Modern Architecture Challenge

On modern Android devices:
1. **EROFS Filesystem:** `/system`, `/vendor`, `/product`, and `/odm` are strictly read-only at the Linux kernel level (`erofs`). The old trick of `mount -o remount,rw /system` fails with `Read-only file system`.
2. **Magisk v30+ Charger-Mode Abort:** Magisk's early-stage Rust binary (`magiskinit` at `/init` in `ramdisk.cpio`) explicitly detects charger mode (`androidboot.mode=charger`) and executes `self.recovery_or_charger()`, which restores stock `/init` and aborts all Magisk overlays/modules to prevent booting into full Android during off-mode charging.
3. **MediaTek / LK KPOC Low-Power Mode:** When booted via charger, the Little Kernel (LK) bootloader enters `boot_mode = 8 (KERNEL_POWER_OFF_CHARGING_BOOT)` and **does not initialize the Samsung TEEgris (TrustZone) `root_task`**. Attempting to force full boot directly from charger mode (`trigger late-init`) causes `/vendor/etc/init/teegris_v4.rc` to hang forever on `wait_for_prop vendor.tzdaemon Ready`. Because Android File-Based Encryption (FBE) requires Keystore/TEEgris to decrypt `/data`, the device freezes on a static charging screen.
4. **Generic Reboot Loops:** Running `sys.powerctl "reboot"` sends an empty reboot target to LK. Because the charger remains connected with no reason provided, LK re-enters charger mode in an infinite bootloop.

---

## The Solution: Two-Stage Systemless Interception

### 1. `magiskinit` Hex-Patch (`charger\0` -> `nocharg\0`)
We patch `magiskinit` directly inside `ramdisk.cpio`:
- Search: `6368617267657200` (`charger\0`, offset `0x24ac`)
- Replace: `6e6f636861726700` (`nocharg\0`)

Because `boot_mode` (`"charger"`) no longer matches `"nocharg"`, `magiskinit` skips the abort routine and proceeds with standard two-stage init, loading Magisk root overlays (`overlay.d`).

### 2. Ramdisk Overlay `overlay.d/autoboot.rc` with `reboot,lpm`
We inject `overlay.d/autoboot.rc` into the ramdisk:
```rc
on charger
    setprop sys.powerctl "reboot,lpm"

on property:ro.bootmode=charger
    setprop sys.powerctl "reboot,lpm"
```
The canonical `reboot,lpm` command tells the Little Kernel bootloader that Low Power Mode charging has completed and signals LK to execute a cold **`NORMAL_BOOT`**. On reboot, LK detects reason `lpm`, fully initializes TrustZone/hardware, and boots directly to the Android home screen!

---

## How to Install

```bash
# Ensure device is connected via USB with USB debugging and Root (Magisk) enabled
chmod +x apply_autoboot.sh
./apply_autoboot.sh
```

---

## Auto-Shutdown Daemon (`power_monitor.sh`)

`apply_autoboot.sh` automatically installs `/data/adb/service.d/power_monitor.sh`:
- Runs in the background at boot via Magisk.
- If external power is disconnected **AND** battery is **$< 15\%$** for 10 consecutive seconds:
  1. Calls `sync` to flush disk caches and open databases.
  2. Runs `/system/bin/reboot -p` (clean Android shutdown).
- Configurable via `/data/adb/power_monitor.conf` (e.g. `THRESHOLD=20`).

---

## Emergency Recovery (Download Mode)

If a bad boot image is ever flashed or the device hangs:
1. **Force Shutdown:** Unplug the USB cable, press and hold **`Power` + `Volume Down`** for 7–10 seconds until the screen cuts black.
2. **Enter Download Mode:** Hold **`Volume Up` + `Volume Down`** together and insert a **USB-A to USB-C cable** connected to your PC. Press **`Volume Up`** at the warning screen.
3. **Flash Stock Boot:**
   ```bash
   sudo ./odin4 -a boot_restore.tar
   ```
   *(Ensure `cdc_acm` kernel driver is blacklisted in `/etc/modprobe.d/cdc_acm-blacklist.conf` to avoid modem port lockup under Linux Odin4).*
