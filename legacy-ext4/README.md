# Legacy Samsung Auto-Boot (ext4 / Android 6–9 / TouchWiz & One UI 1)

Target devices: Samsung Galaxy S6, S7, S8, S9, Note 4–9, and any device using physical **`ext4`** partitions (`system.img`) and Android 6.0 Marshmallow through Android 9.0 Pie.

---

## Architectural Mechanism

On legacy devices:
1. When powered off and connected to a charger, Samsung's proprietary Low Power Mode daemon (`/system/bin/lpm`) is invoked by `init.rc` to display the offline charging animation.
2. Because `/system` is formatted as `ext4`, it can be remounted read-write (`mount -o remount,rw /system`) by root.
3. Replacing `/system/bin/lpm` with a script that calls `/system/bin/reboot` causes the bootloader to execute a cold reboot into standard Android mode.

---

## Critical Traps & Best Practices

- **Preserve File Inode:** Never delete (`rm`) or move (`mv`) `/system/bin/lpm`. Deleting and recreating the file creates a new filesystem inode, which causes Android's `init` or the bootloader to reject the binary, resulting in an empty battery outline that freezes indefinitely. Instead, overwrite the existing file contents in-place using `cat script > /system/bin/lpm`.
- **SELinux Context:** The file must retain the `u:object_r:lpm_exec:s0` SELinux context so `init` has permission to execute it from the charger context.
- **Stock Recovery Auto-Restore:** Disable `/system/recovery-from-boot.p` by renaming it to `.bak` to prevent stock Samsung firmware from overwriting TWRP on reboot.

---

## How to Install

```bash
# Ensure device is connected via USB with USB debugging and Root (Magisk/SuperSU) enabled
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

## Emergency Recovery

If anything goes wrong:
1. Boot into TWRP Recovery (`Power` + `Home` + `Volume Up`).
2. Restore your boot or system partition backup.
3. Alternatively, flash stock firmware via Odin or Heimdall in Download Mode (`Power` + `Home` + `Volume Down`).
