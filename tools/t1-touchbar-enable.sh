#!/bin/sh
# Recover the T1 iBridge display HID interface after the boot-time driver race.
set -eu

readonly model_file=/sys/class/dmi/id/product_name
readonly hid_root=/sys/bus/hid/devices
readonly sensor_driver=/sys/bus/hid/drivers/hid-sensor-hub
readonly ibridge_driver=/sys/bus/hid/drivers/apple-ibridge-hid

log() { printf '%s\n' "t1-touchbar-enable: $*"; }

if [ ! -r "$model_file" ] || [ "$(cat "$model_file")" != 'MacBookPro14,2' ]; then
	log 'not a MacBookPro14,2; no action taken'
	exit 0
fi

modprobe apple_ibridge
modprobe apple_touchbar

candidate=
for device in "$hid_root"/0003:05AC:8600.*; do
	[ -r "$device/uevent" ] || continue
	if grep -qx 'HID_PHYS=usb-0000:00:14.0-3/input3' "$device/uevent"; then
		candidate=${device##*/}
		break
	fi
done

if [ -z "$candidate" ]; then
	log 'iBridge input3 was not found; no action taken'
	exit 0
fi

driver=$(basename "$(readlink -f "$hid_root/$candidate/driver" 2>/dev/null || true)")
case "$driver" in
	apple-ibridge-hid)
		log "$candidate is already bound to apple-ibridge-hid"
		;;
	hid-sensor-hub)
		printf '%s' "$candidate" > "$sensor_driver/unbind"
		printf '%s' "$candidate" > "$ibridge_driver/bind"
		log "rebound $candidate from hid-sensor-hub to apple-ibridge-hid"
		;;
	*)
		log "$candidate is owned by unexpected driver '$driver'; no action taken"
		exit 1
		;;
esac

# A sysfs bind write fails if the HID probe fails.  Do not infer failure from a
# second virtual-HID modalias check: its collection value varies across kernels,
# while the successful bind itself is the authoritative result.
log 'SUCCESS: iBridge display interface is available to apple-touchbar'
