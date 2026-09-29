# MacBookPro14,2: Touch Bar and keyboard backlight after suspend on Kubuntu

[Italiano](MACBOOKPRO14-2-SUSPEND-IT.md) | English

Status as of **September 28, 2026**: confirmed working by the user on the reference
Mac, through multiple manual cycles and subsequent permanent integration.
This is a suspend workaround, not a demonstrated fix for the underlying firmware
cause. This guide reproduces that configuration on another **MacBookPro14,2**;
the marketing name “2017 MacBook Pro” alone is not sufficient.

## 1. Outcome and limitations

Before: the Touch Bar worked at boot but remained black after `deep`/S3, even
when USB display-on commands completed without errors.

After: `s2idle` suspend with NVMe power protection, temporary removal of the
Thunderbolt subtrees before suspend, and re-enumeration on wake. The Touch Bar
lights up again. The physical keyboard's backlight level is saved, set to zero
before suspend, and restored to its original value, including zero.

**Important limitations:**

- Tested on one machine; other 14,2 units must be validated, not assumed compatible.
- Do not apply directly to 13,2, 14,3, T2, or Apple Silicon machines. PCI addresses are specific.
- The permanent setup **refuses suspend if it detects peripherals on the
  USB-C/Thunderbolt subtrees or external displays**. Even an unmounted disk causes refusal.
- The Mac may therefore remain awake with the lid closed. Check that it is
  actually asleep before putting it in a bag; if unsure, shut it down.
- Do not connect peripherals during the suspend/restore cycle.
- Hibernation and suspend-then-hibernate are not covered. KDE must request
  ordinary suspend, not either of those modes.
- Overnight drain, battery life, extended cycles, and compatibility with other
  kernels have not been measured. Do not assume the battery life of `deep` sleep.
- Different hardware or firmware may still hang. Save your work.

## 2. Reference machine

| Item | Observed value |
| --- | --- |
| DMI model | `MacBookPro14,2`, 13-inch 2017, T1 |
| System | Kubuntu; `Ubuntu 26.04.1 LTS` base |
| Kernel | `7.0.0-34-generic` |
| systemd | `259.5-0ubuntu3.4` |
| BIOS/firmware | `529.140.2.0.0` |
| Kernel parameters present | `pcie_port_pm=off pcie_ports=compat` |
| iBridge | USB `05ac:8600`, path `00:14.0/usb1/1-3` |
| SSD | Apple S3X `106b:2003`, `0000:01:00.0` |
| Thunderbolt subtrees | `0000:03:00.0`, `0000:79:00.0`, Intel `8086:1578` |
| Parent PCI ports | `0000:00:1c.4`, `0000:00:1d.0` |
| Thunderbolt NHI | `0000:05:00.0`, `0000:7b:00.0` |
| Thunderbolt xHCI | `0000:06:00.0`, `0000:7c:00.0` |
| Keyboard LED | `/sys/class/leds/spi::kbd_backlight`, maximum `255` |
| DKMS package | `apple-ib-drv/0.1` |
| Loaded `apple_ibridge` srcversion | `EA3883CC7FE2B9994D38BB1` |
| Loaded `apple_touchbar` srcversion | `E8CEB54C26CE50C4955BFCA` |

The firmware version is provided for comparison, **not as an instruction to update
or modify firmware**. Both PCIe parameters were present in the successful setup;
their individual necessity has not been established. Keep them when reproducing it.

## 3. Distribute the correct copy

Use **this modified project copy**, including `apple-ib-drv/`, `tools/` (including
`tools/permanent/`), `docs/`, and the licenses. Copying only the two `.c` files is
insufficient, as is cloning upstream and assuming it contains these patches.
Distribute the snapshot of this branch and record its commit with
`git rev-parse HEAD`; do not rely on the repository name alone. Publishing a fork
is separate from preparing the local copy.

Run commands from the root of the received copy, in a directory of your choice.
You do not need the same username or path as the reference Mac.

```bash
sha256sum --check docs/macbookpro14-2-tested.sha256
```

These checksums identify the source and scripts used by this procedure; they do
not authenticate the sender. Review the code before running it with `sudo`.
Later revisions should update the manifest and results only after revalidation.

## 4. Prerequisites and inventory before making changes

The Touch Bar must be capable of working at boot and iBridge must enumerate as
`05ac:8600`. This procedure does not solve an absent device or recovery mode
(`05ac:1281`). Do not format EFI/macOS partitions or use firmware recovery tools
as part of this guide.

```bash
cat /sys/class/dmi/id/product_name
cat /sys/class/dmi/id/bios_version
cat /etc/os-release
uname -r
systemctl --version
cat /proc/cmdline
cat /sys/power/mem_sleep
lspci -nn
lsusb
dkms status
```

Compare the model, kernel, and topology with the table. A different kernel needs
new build and resume validation. The scripts also check a specific `srcversion`:
**do not remove that check just to accept a different, unreviewed version**.

Before installation, inspect and back up existing configuration in
`/etc/modprobe.d/apple-touchbar.conf`, `/etc/modules-load.d/apple-touchbar.conf`,
`/etc/udev/rules.d/99-ibridge.rules`, GRUB files, and existing DKMS sources.
If another Touch Bar driver, sleep hook, or differently named package is present,
stop and resolve the conflict. Do not install two competing stacks.

Dependencies for the Ubuntu family used here:

```bash
sudo apt-get update
sudo apt-get install build-essential dkms "linux-headers-$(uname -r)" pciutils usbutils util-linux python3
```

Stop if headers for the running kernel are unavailable. Do not blindly change
kernels just to satisfy this command.

### Boot parameters in the verified setup

If missing, back up `/etc/default/grub`, open it with
`sudoedit /etc/default/grub`, and **append without removing other parameters** to
`GRUB_CMDLINE_LINUX_DEFAULT`:

```text
pcie_port_pm=off pcie_ports=compat
```

Then run `sudo update-grub`, save your work, and reboot. Verify the parameters
in `/proc/cmdline`. This step is for GRUB installations; do not apply it to a
different bootloader without adapting it. Do not add `mem_sleep_default=s2idle`:
this procedure selects s2idle only through the guarded path, after its checks.

## 5. Install the patched driver without live reloading

### A. First installation, with no previous Touch Bar stack

These commands initialize the files required by the project's scripts. Use them
only after verifying that the destinations do not contain configuration you need
to preserve. This is not an automatic migration from other forks.

```bash
sudo install -m 644 apple-ib-drv/packaging/apple-touchbar.modprobe.conf /etc/modprobe.d/apple-touchbar.conf
sudo install -m 644 apple-ib-drv/packaging/apple-touchbar.modules-load.conf /etc/modules-load.d/apple-touchbar.conf
sudo install -m 644 apple-ib-drv/packaging/99-ibridge.rules /etc/udev/rules.d/99-ibridge.rules
sudo install -d /usr/src/apple-ib-drv-0.1
sudo install -m 644 apple-ib-drv/Makefile apple-ib-drv/dkms.conf apple-ib-drv/apple-ibridge.c apple-ib-drv/apple-ibridge.h apple-ib-drv/apple-touchbar.c apple-ib-drv/hid-ids.h /usr/src/apple-ib-drv-0.1/
sudo dkms add -m apple-ib-drv -v 0.1
```

Stop at the first error. Do not run `modprobe`, unbind/rebind, `udevadm trigger`,
or unload modules to try the result immediately. Continue to section C.
The first-install path is derived from the code's requirements; the reference
machine already had the DKMS package installed.

### B. Updating the same already-installed package

If **`apple-ib-drv/0.1`** already exists with sources in `/usr/src/apple-ib-drv-0.1`,
do not run `dkms add` again. Verify the three configuration files in section A,
especially `options apple_ibridge skip_acpi_power=1`.
Do not use this shortcut for a differently named package.

### C. Build, initramfs, and reboot

```bash
sudo bash tools/install-display-fix.sh
```

Despite its historical name, this script updates both C sources, forces DKMS
build/install for the current kernel, and updates initramfs. It saves previous
sources under `/var/tmp/t1-display-backup.*` and prints the path. Keep that path.
It neither loads modules live nor reboots automatically.

If installation completes without errors, save your work and reboot. Then run:

```bash
dkms status
cat /sys/module/apple_ibridge/srcversion
cat /sys/module/apple_touchbar/srcversion
cat /sys/module/apple_ibridge/parameters/skip_acpi_power
sudo cat /sys/module/apple_ibridge/parameters/test_resume_acpi_once
sudo cat /sys/module/apple_touchbar/parameters/test_skip_suspend_display_off_once
journalctl -b -k --no-pager | grep -E 'apple-ibridge|apple-touchbar|SOCW'
```

Expected: the table's `srcversion` values, `skip_acpi_power=1`, both tests `N`,
a visibly lit Touch Bar, and working keys. Logs should include
`Touchbar activated with mode and display interfaces`.
`modinfo` describes the module on disk; `/sys/module/.../srcversion` identifies
the module actually loaded. A successful USB transfer does not prove the display
is lit. If the bar is already black at boot, do not start resume testing.

**Never arm `test_resume_acpi_once` or set `skip_acpi_power=0`: the SOCW test
froze the reference Mac.** The diagnostic parameters remain in the code for
traceability; they are not part of the solution.

## 6. Test the temporary configuration first

Save your work and close applications. Disconnect all USB-C/Thunderbolt peripherals
and external displays; the power adapter may remain connected. Use a local terminal
in your graphical session, not SSH or a previously opened root shell.

```bash
sudo bash tools/test-protected-s2idle.sh --check
```

This is read-only. Resolve any `STOP` before proceeding; do not remove the checks.
If it passes:

```bash
sudo bash tools/test-protected-s2idle.sh --run
```

Confirm by typing **`PROVA`** (the scripts retain their Italian prompts). Keep the
lid open, then wake with a key or a brief press of the power button. Wait for
restoration to finish before reconnecting peripherals. Do not use
`systemctl suspend -i`.

Success criteria:

1. The Mac wakes without a forced shutdown.
2. The Touch Bar lights up and its keys work.
3. The keyboard backlight turns off during sleep and returns to its initial level.
   Test both a nonzero initial brightness and zero.
4. Logs contain `PM: suspend entry (s2idle)`, `PM: suspend exit`, `ACPI test=0`,
   and, in the verified case, `Touchbar restore queued (reset=0)`.
5. The script reports no controller-restoration errors.

Repeat at least three cycles and record the outcomes. Multiple successful cycles
were confirmed on the original Mac. The test restores the initial power settings:
seeing `[deep]` again afterwards is expected, not an error. Until permanent
installation, ordinary lid-close suspend does not necessarily use this guarded setup.

## 7. Make lid-close handling permanent

Only after the preceding tests:

```bash
sudo bash tools/install-permanent-sleep.sh --install
```

Confirm with **`INSTALLA`**, exactly as shown. The installer does not overwrite
existing files, suspend, change GRUB/drivers/Wi-Fi, or change KDE preferences.
No rebuild or reboot is required. KDE's lid action must be **Suspend**; the
installer does not select it for you.

| Installed file | Purpose |
| --- | --- |
| `/usr/local/libexec/t1-sleep-common.sh` | Checks and operations shared with the manual test |
| `/usr/local/libexec/t1-sleep-guard` | Automatic preparation and restoration |
| `/etc/systemd/system/systemd-suspend.service.d/90-t1-sleep-guard.conf` | `ExecStartPre` and `ExecStopPost` |
| `/etc/systemd/sleep.conf.d/90-t1-s2idle.conf` | `SuspendState=mem`, `MemorySleepMode=s2idle` |
| `/var/lib/t1-sleep-guard/manifest` | Checksums to avoid uninstalling altered files |

A cycle's snapshot is stored in `/run/t1-sleep-guard`, accessible only to root.
It is removed after successful restoration. If restoration fails, it is retained
to prevent blindly continuing; save your work and reboot in that case.

A failed `ExecStartPre` prevents the suspend command from running; `ExecStopPost`
provides restoration even after an initial failure. A simple `system-sleep` hook
exiting with an error would not provide the same blocking behavior.
[systemd 259 semantics](https://github.com/systemd/systemd/blob/v259/man/systemd.service.xml).

After installation, stop using manual `--run`: it is refused to prevent two
concurrent preparations. Test closing and reopening the lid with no peripherals
connected and collect:

```bash
journalctl -b -u systemd-suspend.service --no-pager -n 100
journalctl -b -k --no-pager | grep -E 'PM: suspend|Touchbar|Display command|iBridge platform|ACPI one-shot'
```

The original Mac's logs confirm two permanent-setup cycles on September 28,
at 03:06 and 03:07, with successful preparation, resume, and restoration. In those
two logs, keyboard brightness was already zero and was correctly kept at zero;
the user confirmed overall operation after the update. On every new machine,
also verify the case with nonzero initial keyboard brightness.

## 8. What the workaround changes, and what it does not prove

Each cycle follows this sequence:

```text
check model/modules/peripherals and save settings
  -> exclude SSD and NHI from D3cold; select s2idle
  -> remove only Thunderbolt subtrees; set keyboard brightness to zero
  -> suspend and ordinary iBridge resume
  -> rescan only the Thunderbolt parent ports
  -> restore power policies and keyboard brightness
```

The SSD is not removed. The internal `00:14.0` iBridge controller is not removed.
SOCW is not executed and Touch Bar modules are not unloaded. Re-enumerating
devices does not erase their data, but can interrupt I/O; this is why the checks
refuse connected peripherals.

Local driver changes include HID classification of the virtual Touch Bar device
to avoid incorrect `hid-sensor-hub` binding; use of both mode/display interfaces;
sending and checking display reports; normalization of mode-write return values;
forced state restoration and ordinary/reset resume callbacks; and platform PM
registration through `driver.pm`, while retaining the SOCW guard.

The tests demonstrate the result of the **combination**. They do not establish
which individual parameter is essential or whether USB reset is the primary
cause. Thunderbolt errors observed during S3 affected controllers other than iBridge.

## 9. Attempts not to repeat as supposed solutions

| Attempt on the original Mac | Result |
| --- | --- |
| Resend display ON after S3 | Successful transfer, bar still black |
| Turn mode/display off and on while awake | Works; does not fix resume |
| Skip only display OFF before S3 | No improvement |
| Add only PCIe parameters | Did not fix the Touch Bar |
| s2idle without the guarded combination | Attempts without successful wake |
| SOCW(1) actually executed on resume | Mac froze; approach abandoned |
| s2idle with NVMe/Thunderbolt protections and current driver | Successful cycles |

An earlier SOCW test did not run because of the old callbacks: its parameter
remained `Y`. Only after correcting the callbacks did the test actually run and
freeze the Mac. Do not confuse those two results.

## 10. Troubleshooting, updates, and rollback

**`User ... is logged in on tty2`:** use the updated script, which issues the
request as the user who invoked `sudo`, retaining inhibitor checks. Do not log
out of your own session to work around this, and do not use `-i`.

**Peripheral refusal:** disconnect peripherals and retry after verifying that
the controllers are healthy. Do not remove the disk check.

**Different srcversion, updated kernel, or missing controllers:** stop. DKMS can
rebuild, but this does not guarantee functional compatibility. The module check
is intentionally restrictive: a new build must be reviewed and revalidated before
updating the allowed version. Editing the checkout does not update installed
copies under `/usr/local/libexec`.

**Complete hang:** wait and try to wake the Mac; if it remains unresponsive,
a forced shutdown may be necessary. Unsaved work is at risk. Do not repeat the
identical test; after reboot, collect `journalctl -b -1 -k --no-pager`.

To remove only the permanent handling:

```bash
sudo bash tools/install-permanent-sleep.sh --remove
```

Files are moved to `/var/tmp/t1-sleep-removed.*`, not deleted. If they have been
modified, automatic removal stops. This does not uninstall the driver or revert
manual GRUB changes. Remove permanent handling **before** changing/removing the
driver stack. The previous suspend behavior may leave the Touch Bar black again.

To roll back DKMS sources, use the exact backup path printed by
`install-display-fix.sh`: restore both `.c` files into `/usr/src/apple-ib-drv-0.1`,
then run `dkms build --force`, `dkms install --force` for the current kernel,
`update-initramfs -u -k ...`, and reboot. The script prints the command for copying
its backups. Do not rerun the update script after restoring, because it would
copy the new sources back again. Always retain `skip_acpi_power=1` and do not
live-reload modules.

## 11. Code tests and reporting a new machine

```bash
bash -n tools/test-protected-s2idle.sh tools/install-permanent-sleep.sh tools/permanent/t1-sleep-guard
bash tools/test-protected-s2idle-mocks.sh
python3 tools/test-touchbar-update.py
python3 tools/test-touchbar-suspend.py
python3 tools/test-ibridge-resume.py
```

These tests do not suspend the Mac or execute SOCW. Mock tests do not replace
visual and hardware validation.

For each new installation, record model, BIOS, distro/kernel/systemd, boot
parameters, `srcversion`, manifest result, successful cycle count, keyboard
brightness before/during/after sleep, Touch Bar operation, and complete
preparation/restoration logs. Do not publish personal identifiers, disk UUIDs,
or other unnecessary data.

Background references, not additional installers to run:

- [MacBookPro13,2 s2idle procedure](https://gist.github.com/bgausden/c7f8a3737c1e52a260dfcdb1fb2e90b2): suggested the combination; not a test on the 14,2.
- [nohzafk's T1 setup](https://github.com/nohzafk/omarchy-macbookpro-t1): initial comparison, not a guarantee for this installation.
- [Local operating notes](../tools/PROTECTED-S2IDLE-EN.md) and [driver](../apple-ib-drv/apple-touchbar.c).
