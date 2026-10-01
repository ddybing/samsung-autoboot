# Samsung Auto-Boot & Power Toolkit

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-Android%206%20--%2014-green.svg)](https://android.com)
[![Samsung One UI](https://img.shields.io/badge/Samsung-One%20UI%201%20--%206-blue.svg)](https://samsung.com)

A comprehensive, production-grade toolkit to enable **automatic power-on / auto-boot on charger connection** and **safe auto-shutdown on power disconnect** for Samsung Galaxy devices across all Android generations.

Perfect for **in-car dashboard head units (Android Auto), digital kiosks, solar-powered field monitors, and automated IoT deployments**.

> [!NOTE]
> **Development Notice**: This project was built through human–AI pair programming (vibe coding), combining deep reverse-engineering of vendor binaries (`lpm`, `libcutils`), Linux kernel console log analysis, and rigorous validation on physical Samsung hardware.

---

## The Android Generation Divide

| Feature | Modern Architecture (`modern-erofs/`) | Legacy Architecture (`legacy-ext4/`) |
| :--- | :--- | :--- |
| **Target Devices** | Galaxy A-series, S20–S24, Z Fold/Flip, modern Tab | Galaxy S6, S7, S8, S9, Note 4–9, Tab S2–S4 |
| **Android Versions** | Android 10, 11, 12, 13, 14 (One UI 2 – 6) | Android 6, 7, 8, 9 (TouchWiz, Experience, One UI 1) |
| **Storage Architecture** | Dynamic Partitions (`super.img`), `erofs` read-only | Physical partitions, `ext4` read-write |
| **Root Method** | Magisk v26–v31 (Systemless 2-Stage Init) | Magisk or SuperSU |
| **Auto-Boot Technique** | `magiskinit` Hex-Patch + Ramdisk `overlay.d` (`reboot,lpm`) | Inode-preserving `/system/bin/lpm` shell payload |
| **Flash / Recovery Tool** | Odin4 (Linux CLI) / Odin3 (Windows) | Odin3 / Heimdall / TWRP |

---

## 1. Modern Devices (Android 10–14 / EROFS)

Modern Samsung devices format system partitions with **`erofs`** (strictly read-only at the kernel driver level), making direct edits to `/system/bin/lpm` impossible. Modern Magisk also contains a Rust-level check in `magiskinit` that intentionally aborts in charger mode.

### The Modern Breakthrough
1. **`magiskinit` Hex-Patch:** Replaces `charger\0` with `nocharg\0` inside `ramdisk.cpio` so Magisk does not abort during off-mode charging and successfully loads root overlays (`overlay.d`).
2. **MediaTek / LK `reboot,lpm` Cold Boot:** In offline charging mode, the bootloader (Little Kernel) runs in a low-power mode with TrustZone (TEEgris) disabled. Running standard `sys.powerctl "reboot"` causes an infinite loop, while forcing full boot freezes on TrustZone. Issuing `sys.powerctl "reboot,lpm"` signals Little Kernel that Low Power Mode charging has completed, cleanly directing the bootloader into a cold **`NORMAL_BOOT`** with TrustZone fully active.

### Quick Start (Modern)
```bash
cd modern-erofs
chmod +x apply_autoboot.sh
./apply_autoboot.sh
```
*See [`modern-erofs/README.md`](modern-erofs/README.md) for full architectural deep dive and emergency recovery instructions.*

---

## 2. Legacy Devices (Android 6–9 / ext4)

On older devices where `/system` is `ext4`, auto-boot is achieved by replacing `/system/bin/lpm` with a reboot payload.

### Critical Legacy Trap: Inode Preservation
Never delete (`rm`) or move (`mv`) `/system/bin/lpm`! Modern and legacy Samsung bootloaders track file inodes. Recreating the file produces a new filesystem inode, causing the bootloader to reject the binary and display a frozen empty battery icon. This tool overwrites the binary in-place using `cat payload > /system/bin/lpm` to preserve the original inode and restores SELinux context `u:object_r:lpm_exec:s0`.

### Quick Start (Legacy)
```bash
cd legacy-ext4
chmod +x apply_autoboot.sh
./apply_autoboot.sh
```
*See [`legacy-ext4/README.md`](legacy-ext4/README.md) for detailed notes and TWRP recovery.*

---

## 3. Auto-Shutdown Daemon (`power_monitor.sh`)

Both modern and legacy setups include an intelligent background daemon installed to `/data/adb/service.d/power_monitor.sh` (executed as root by Magisk at boot):

- **Power Monitoring:** Monitors battery capacity and USB/AC charging status every 5 seconds.
- **Configurable Threshold:** Automatically powers off if external power is disconnected **AND** battery drops below **15%**.
- **10-Second Grace Period:** Requires 2 consecutive disconnected checks before triggering shutdown to prevent accidental power-offs if the power cable is momentarily bumped or jiggled.
- **Database Safety Flush:** Executes `sync` immediately prior to `/system/bin/reboot -p` to safely flush disk caches and prevent filesystem/database corruption.

### Optional User Configuration
Create `/data/adb/power_monitor.conf` to override defaults without editing scripts:
```sh
THRESHOLD=20        # Shut down if battery < 20%
CHECK_INTERVAL=3    # Check every 3 seconds
GRACE_CHECKS=3      # Require 3 consecutive checks (9 seconds total)
```

---

## Repository Structure

```
samsung-autoboot/
├── .gitignore
├── LICENSE
├── README.md                 # Master documentation
├── modern-erofs/             # Android 10–14 / EROFS / One UI 2–6
│   ├── README.md             # In-depth Little Kernel & TEEgris architecture
│   ├── apply_autoboot.sh     # Automated boot patcher & daemon installer
│   └── power_monitor.sh      # Auto-shutdown daemon
└── legacy-ext4/              # Android 6–9 / ext4 / TouchWiz & One UI 1
    ├── README.md             # In-depth inode & SELinux architecture
    ├── apply_autoboot.sh     # Automated LPM patcher & daemon installer
    ├── lpm_payload.sh        # LPM replacement payload
    └── power_monitor.sh      # Auto-shutdown daemon
```

---

## Contributing & License

Pull requests and device reports are welcome! If you test this on other Samsung models (Exynos, Snapdragon, or MediaTek), please share your findings.

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for details.
