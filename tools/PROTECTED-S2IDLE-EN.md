# Temporary s2idle test — MacBookPro14,2

[Italiano](PROTECTED-S2IDLE.md) | English

This combination was confirmed working on the reference MacBookPro14,2 on
September 28, 2026, with manual cycles and permanent handling. This is not a
guarantee for every unit. To reproduce it from scratch on another Mac, follow
the [complete guide](../docs/MACBOOKPRO14-2-SUSPEND-EN.md).
It can still hang and require a forced shutdown, losing unsaved data.
Save your work and close applications.

## Rationale and limitations

Tests on September 27, 2026 showed that mode/display OFF are reversible while
awake, but skipping display OFF during S3 does not restore the bar. Logs show
an iBridge reset on S3 resume and separate Thunderbolt controller failures.
iBridge is on the internal 00:14.0 controller: Thunderbolt failures do not
demonstrate the cause of the black Touch Bar.

A [public procedure for MacBookPro13,2](https://gist.github.com/bgausden/c7f8a3737c1e52a260dfcdb1fb2e90b2)
reports a working Touch Bar after s2idle with NVMe protection and removal/
re-enumeration of Thunderbolt subtrees. That model differs from the 14,2.
This script adapts only the power-management test to the checked local topology;
it does not run the external installer, replace drivers/firmware, or change Wi-Fi.

## Before testing

- Run from a local terminal with the Touch Bar lit after a reboot.
- Disconnect all USB-C/Thunderbolt peripherals, including monitors and hubs;
  only the power adapter may remain connected.
- Do not reconnect devices until restoration finishes.
- Leave both the SOCW and display tests disarmed; the script checks this.
- Do not update the driver for this test: the previously reviewed module is
  checked, with srcversion `E8CEB54C26CE50C4955BFCA`.

```bash
# From the root of the modified project copy:
sudo bash tools/test-protected-s2idle.sh --check
```

This check is read-only. If it fails, stop and report the error. The request is
also checked with `systemctl --dry-run`, run as the user who invoked `sudo`:
your own graphical session must not be mistaken for another user's session.
Inhibitors remain respected in both preflight and the actual request. Do not
use `-i`. If the check passes, start the test:

```bash
sudo bash tools/test-protected-s2idle.sh --run
```

The script retains Italian prompts: type **`PROVA`** exactly when asked, before
any hardware changes. Keep the lid open. Wake with a key or, if necessary, a
brief press of the power button. Wait at least a minute before concluding that
the Mac has hung. Do not close the terminal during the test.

## What changes and how it is restored

Only until restoration or reboot:

1. `d3cold_allowed=0` on SSD `01:00.0` and NHI `05:00.0`, `7b:00.0`.
2. Select `s2idle` in `/sys/power/mem_sleep`.
3. Remove PCI Thunderbolt subtrees `03:00.0` and `79:00.0`, not SSD/iBridge.
4. Request ordinary suspend through logind without ignoring inhibitors.
5. After the cycle, rescan only parent ports `00:1c.4` and `00:1d.0` and restore
   the saved power-management values.

The brightness of `spi::kbd_backlight` is also saved and set to zero before
suspend, then restored to its exact value, including zero, after resume or if
the request is refused.

No services/hooks are installed and no GRUB, firmware, modprobe, network, or
ACPI configuration is changed. The only coordination file is a lock in `/run`,
cleared by reboot. The code does not call SOCW or unload iBridge modules.

If the kernel hangs, no script can guarantee automatic restoration. If the Mac
is completely unresponsive, you may need to hold the power button until it
shuts down. Do not repeat the test after a hang. If restoration reports missing
controllers, save your work and reboot.

## What to report

- Did the Mac wake up?
- Is the Touch Bar visibly lit and do its keys work?
- Copy the complete script output, including any restoration errors.

The script prints relevant kernel logs before restoration. Successful USB messages
do not replace visual confirmation. The result evaluates the combined workarounds;
it does not independently identify the original cause.

## Checks without hardware I/O

```bash
bash -n tools/test-protected-s2idle.sh
bash tools/test-protected-s2idle-mocks.sh
```

The tests mock waiting and restoration writes; they do not prove actual suspend,
PCI re-enumeration, or display behavior.

## Optional permanent installation

The user confirmed manual s2idle cycles and overall operation after adding
backlight handling. Logs also show two successful permanent-setup cycles.
On another unit, repeat the manual tests first, including initial keyboard
brightness at both zero and a nonzero value.

```bash
sudo bash tools/install-permanent-sleep.sh --install
```

Confirm with **`INSTALLA`**, exactly as shown. This does not suspend or change
GRUB, drivers, firmware, Wi-Fi, or KDE preferences. It uses a drop-in for
`systemd-suspend.service` with `ExecStartPre` for checks/preparation and
`ExecStopPost` for restoration, including after an initial failure, plus
`MemorySleepMode=s2idle` in sleep.conf.d. It does not install a system-sleep hook,
whose failure could not cancel suspend. Ordinary KDE/lid-close suspend goes
through this service. Hibernation and suspend-then-hibernate are not covered.

**Suspend is refused, not forced, when USB-C/Thunderbolt peripherals or external
displays are detected. The Mac may remain awake with the lid closed: do not put
it in a bag without checking.** Do not connect devices during the cycle. The
checks are conservative, but cannot eliminate every race with physical hotplug.

The code also checks the model, reviewed Touch Bar module, PCI topology, and
SOCW exclusion. Driver/configuration changes may therefore block suspend until
reassessed. A hard lock prevents software restoration: always save work before
initial tests.

After installation, stop using the manual script's `--run`: it is refused to
prevent duplicate PCI removal. Test ordinary lid close/open without connected
peripherals, checking both the Touch Bar and keyboard backlight.

```bash
journalctl -b -u systemd-suspend.service --no-pager -n 100
```

Reversible uninstall:

```bash
sudo bash tools/install-permanent-sleep.sh --remove
```

The installer refuses to overwrite existing files. The uninstaller checks that
its files have not been modified, moves them to a backup directory printed on
screen, and reloads systemd. It does not remove drivers or other user files.
The previous normal settings take effect again; the Touch Bar may consequently
go black after ordinary suspend again.
