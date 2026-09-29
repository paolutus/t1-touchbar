#!/usr/bin/env bash
# No hardware I/O: source functions, then replace all writes and subprocess waits.
set -euo pipefail
tool_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$tool_dir/test-protected-s2idle.sh"

# A fake PCI directory makes the suite runnable without this Mac or root.
# All sysfs writes remain mocked below; only empty fixture directories are created.
pci=$(mktemp -d /tmp/t1-sleep-mock-pci.XXXXXX)
cleanup_fixture() {
    local dev
    for dev in "${roots[@]}" "${endpoints[@]}"; do rmdir -- "$pci/$dev"; done
    rmdir -- "$pci"
}
trap cleanup_fixture EXIT
for dev in "${roots[@]}" "${endpoints[@]}"; do mkdir -- "$pci/$dev"; done

# Preserve inhibitor checks and request sleep as the original desktop user.
request_user=testuser
runuser() { printf '%s\n' "$*"; }
[[ $(request_suspend --dry-run) == '-u testuser -- systemctl --check-inhibitors=yes --dry-run suspend' ]]
[[ $(request_suspend) == '-u testuser -- systemctl --check-inhibitors=yes suspend' ]]
runuser() { return 17; }
if request_suspend --dry-run; then exit 1; else [[ $? == 17 ]]; fi
unset -f runuser

in_thunderbolt_tree /sys/devices/pci0000:00/0000:00:1c.4/0000:03:00.0/0000:06:00.0
in_thunderbolt_tree /sys/devices/pci0000:00/0000:00:1d.0/0000:79:00.0
if in_thunderbolt_tree /sys/devices/pci0000:00/0000:00:14.0/usb1/1-3; then exit 1; fi
if in_thunderbolt_tree /sys/devices/pci0000:00/0000:00:1c.0/0000:01:00.0; then exit 1; fi
if in_thunderbolt_tree /sys/devices/0000:03:00.01; then exit 1; fi

# Queue -> active -> inactive. Do not restore just because the initial state is inactive.
tick=0
sleep_before=42
sleep() { tick=$((tick + 1)); }
systemctl() {
    case "$*" in
        *InactiveExitTimestampMonotonic*)
            if (( tick == 0 )); then printf '42\n'; else printf '99\n'; fi ;;
        *ActiveState*)
            if (( tick == 1 )); then printf 'activating\n'; else printf 'inactive\n'; fi ;;
        *) return 1 ;;
    esac
}
wait_for_resume
[[ "$tick" == 2 && "$sleep_finished" == 1 ]]

# A fast completed cycle must also be detected without observing 'activating'.
tick=2
sleep_finished=0
wait_for_resume
[[ "$tick" == 2 && "$sleep_finished" == 1 ]]

# Restoration is tested in a subshell because the real EXIT handler calls exit.
# Exact expected writes ensure that iBridge and NVMe are never removed/rescanned.
output=$(
    changed=1
    removed=1
    sleep_requested=0
    old_sleep=deep
    for dev in "${pm_devices[@]}"; do saved_pm[$dev]=1; done
    put() { printf 'WRITE %s %s\n' "$1" "$2"; }
    sleep() { :; }
    note() { :; }
    # Device-presence checks read only the empty temporary fixture.
    restore
)
expected=$(printf '%s\n' \
    'WRITE /sys/bus/pci/devices/0000:00:1c.4/rescan 1' \
    'WRITE /sys/bus/pci/devices/0000:00:1d.0/rescan 1' \
    'WRITE /sys/bus/pci/devices/0000:00:1c.4/rescan 1' \
    'WRITE /sys/bus/pci/devices/0000:00:1d.0/rescan 1' \
    'WRITE /sys/bus/pci/devices/0000:01:00.0/d3cold_allowed 1' \
    'WRITE /sys/bus/pci/devices/0000:05:00.0/d3cold_allowed 1' \
    'WRITE /sys/bus/pci/devices/0000:7b:00.0/d3cold_allowed 1' \
    'WRITE /sys/power/mem_sleep deep')
expected=${expected//\/sys\/bus\/pci\/devices/$pci}
[[ "$output" == "$expected" ]]

# The previous brightness must be restored exactly, including an initially OFF LED.
for brightness in 0 122; do
    output=$(
        changed=1
        removed=0
        kbd_changed=1
        saved_kbd=$brightness
        old_sleep=deep
        for dev in "${pm_devices[@]}"; do saved_pm[$dev]=1; done
        put() { printf 'WRITE %s %s\n' "$1" "$2"; }
        note() { :; }
        restore_hardware
    )
    [[ "$output" == *"WRITE /sys/class/leds/spi::kbd_backlight/brightness $brightness"* ]]
done

# Keyboard recovery is still attempted if PCI restoration reports an error.
output=$(
    changed=1
    removed=0
    kbd_changed=1
    saved_kbd=122
    old_sleep=deep
    for dev in "${pm_devices[@]}"; do saved_pm[$dev]=1; done
    put() {
        [[ "$1" != */d3cold_allowed ]] || return 1
        printf 'WRITE %s %s\n' "$1" "$2"
    }
    note() { :; }
    if restore_hardware; then exit 99; fi
)
[[ "$output" == *'WRITE /sys/class/leds/spi::kbd_backlight/brightness 122'* ]]

# Read-only exit must not write anything; an interrupted/failed test preserves its error.
output=$(
    changed=0
    sleep_requested=0
    put() { printf 'UNEXPECTED WRITE\n'; }
    restore
)
[[ -z "$output" ]]
set +e
(
    changed=0
    sleep_requested=0
    false
    restore
)
rc=$?
set -e
[[ "$rc" == 1 ]]
printf '%s\n' 'PASS: inhibitors, PCI scope, asynchronous wait, restoration, keyboard zero/nonzero/error paths, read-only exit'
