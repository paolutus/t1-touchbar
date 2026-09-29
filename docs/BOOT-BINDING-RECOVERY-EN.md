# Touch Bar boot recovery — MacBookPro14,2

[Italiano](BOOT-BINDING-RECOVERY-IT.md) | English

## Problem and cause

On the reference MacBookPro14,2, the Touch Bar was black already at boot, before suspend, with the correct DKMS driver and iBridge `05ac:8600` present.

`hid-sensor-hub` had claimed the internal display interface:

```text
hid-sensor-hub ... HID_PHYS=usb-0000:00:14.0-3/input3
apple-ibridge-hid ... HID_PHYS=usb-0000:00:14.0-3/input2
```

The iBridge driver received only the virtual keyboard and `Touchbar activated with mode and display interfaces` was absent. HID numbers such as `.0002` and `.0006` vary between boots and must not be fixed in configuration.

## Permanent correction

The late service identifies iBridge by physical path `00:14.0-3/input3`; if `hid-sensor-hub` owns it, it unbinds that interface and binds it to `apple-ibridge-hid`. It does not change firmware, GRUB, DKMS, or suspend settings.

```bash
cd /path/to/the/t1-touchbar-copy
bash -n tools/t1-touchbar-enable.sh tools/install-touchbar-boot-fix.sh
sudo bash tools/install-touchbar-boot-fix.sh --install
```

The operational files, independent of the checkout, are:

| File | Purpose |
| --- | --- |
| `/usr/local/libexec/t1-touchbar/t1-touchbar-enable` | Helper run at boot |
| `/etc/systemd/system/t1-touchbar-enable.service` | Enabled systemd unit |
| `/var/lib/t1-touchbar-enable/manifest` | Hashes for guarded update/removal |

The checkout can be moved after installation. Reboot normally and check:

```bash
systemctl status t1-touchbar-enable.service --no-pager
journalctl -b -u t1-touchbar-enable.service --no-pager
journalctl -b -k --no-pager | grep -E 'Touchbar activated|Display command' | tail -20
```

Expected: `active (exited)`, `SUCCESS`, Touch Bar activation in the kernel, and a visibly lit bar. Visual confirmation remains required.

To update unmodified installed copies:

```bash
sudo bash tools/install-touchbar-boot-fix.sh --update
```

Reversible removal:

```bash
sudo bash tools/install-touchbar-boot-fix.sh --remove
```

Removal moves files to a printed `/var/tmp/t1-touchbar-enable-removed.*` directory; it does not uninstall the driver and the Touch Bar may be black at boot again.

## Limits

Tested on one MacBookPro14,2 only. Do not apply it to other models or USB topologies without new validation. If the service sees an unexpected driver, it leaves the interface untouched. Do not perform arbitrary unbind/rebind operations, unload modules live, or arm the SOCW test.

It complements, but does not replace, the [complete suspend guide](MACBOOKPRO14-2-SUSPEND-EN.md).
