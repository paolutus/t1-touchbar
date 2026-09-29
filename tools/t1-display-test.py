#!/usr/bin/env python3
"""Inspect T1 display ownership; --wake sends its display-on feature report.

No ACPI calls, USB resets, driver rebinding, or persistent configuration changes.
The write is restricted to the exact report layout observed on this MacBook.
"""

import argparse
import fcntl
import os
from pathlib import Path
import struct
import sys


# Report 2: auxiliary byte, display byte, two 32-bit values. The following
# report ID terminates this layout. Source: the device's HID descriptor and
# t2linux/apple-ib-drv (mbp15), appletb_set_tb_disp().
DISPLAY_LAYOUT = bytes.fromhex(
    "85 02 09 20 15 01 25 04 35 01 45 04 75 08 95 01 b1 02 "
    "09 21 15 01 25 04 35 01 45 04 75 08 95 01 b1 02 "
    "09 22 15 00 27 a0 86 01 00 35 00 45 64 75 20 95 01 b1 02 "
    "09 23 15 00 26 e8 03 35 00 45 01 75 20 95 01 b1 02 85 03"
)
REPORT_SIZE = 11  # includes report ID


def ioc(direction, number, size):
    # Linux x86 _IOC; this diagnostic targets Intel T1 MacBooks.
    return (direction << 30) | (size << 16) | (ord("H") << 8) | number


def find_display():
    matches = []
    for raw in Path("/sys/class/hidraw").glob("hidraw*"):
        device = (raw / "device").resolve()
        if not device.name.upper().startswith("0003:1D6B:0301."):
            continue
        if not any(p.name.upper().startswith("0003:05AC:8600.")
                   for p in device.parents):
            continue
        descriptor = (device / "report_descriptor").read_bytes()
        if bytes.fromhex("06 12 ff 09 01 a1 01") not in descriptor:
            continue
        if descriptor.count(DISPLAY_LAYOUT) != 1:
            continue
        matches.append((Path("/dev") / raw.name, device))
    if len(matches) != 1:
        raise RuntimeError(f"Atteso un display T1 verificato, trovati {len(matches)}; nessuna scrittura.")
    return matches[0]


def get_report(fd):
    report = bytearray(REPORT_SIZE)
    report[0] = 2
    count = fcntl.ioctl(fd, ioc(3, 0x07, REPORT_SIZE), report, True)
    if count != REPORT_SIZE or report[0] != 2:
        raise RuntimeError(f"GET_FEATURE inatteso: lunghezza={count}, ID={report[0]}; interrotto.")
    return report


def display_on(report):
    if len(report) != REPORT_SIZE or report[0] != 2:
        raise ValueError("Report display non valido")
    result = bytearray(report)
    result[1] = 1  # HID_USAGE_DISP_AUX1
    result[2] = 1  # HID_USAGE_DISP: ON
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wake", action="store_true", help="invia display ON (richiede sudo)")
    parser.add_argument("--read", action="store_true", help="legge il report senza SET_FEATURE (richiede sudo)")
    args = parser.parse_args()
    node, device = find_display()
    print(f"Display: {device.name}; nodo: {node}")
    print(f"Driver: {(device / 'driver').resolve().name}")
    print("Formato report display 2 verificato: 11 byte.")
    if not (args.wake or args.read):
        print("Solo ispezione; nessun comando inviato. Usare --wake per il test.")
        return

    fd = os.open(node, os.O_RDWR | os.O_CLOEXEC)
    try:
        info = bytearray(8)
        fcntl.ioctl(fd, ioc(2, 0x03, 8), info, True)  # HIDIOCGRAWINFO
        if struct.unpack("=IHH", info) != (3, 0x1D6B, 0x0301):
            raise RuntimeError("Identita hidraw cambiata; nessuna scrittura.")
        before = get_report(fd)
        print(f"Report letto (hex): {before.hex(' ')}")
        print(f"Prima: aux={before[1]}, display={before[2]} (1=on, 2=dim, 4=off)")
        if not args.wake:
            return
        requested = display_on(before)
        print(f"Report inviato (hex): {requested.hex(' ')}")
        count = fcntl.ioctl(fd, ioc(3, 0x06, REPORT_SIZE), requested, True)
        if count != REPORT_SIZE:
            raise RuntimeError(f"SET_FEATURE ha restituito {count}, attesi {REPORT_SIZE}.")
        print(f"SET_FEATURE display ON completato: {count} byte.")
        after = get_report(fd)
        print(f"Report riletto (hex): {after.hex(' ')}")
        print(f"Dopo: aux={after[1]}, display={after[2]}")
        print("La conferma visiva resta necessaria: il risultato USB non prova che il display sia acceso.")
    finally:
        os.close(fd)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"Test interrotto: {exc}", file=sys.stderr)
        sys.exit(1)
