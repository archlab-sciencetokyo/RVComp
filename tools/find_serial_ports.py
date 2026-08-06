#!/usr/bin/env python3

# SPDX-License-Identifier: MIT
#
# Copyright (c) 2026 Archlab, Science Tokyo

"""List the serial ports currently visible to the operating system."""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence

from serial.tools import list_ports


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description=(
            "List serial ports without opening them. By default, only USB "
            "serial ports are shown."
        ),
        epilog=(
            "Use --all to include built-in UARTs, virtual serial ports, and "
            "other non-USB devices."
        ),
    )
    parser.add_argument(
        "-a",
        "--all",
        action="store_true",
        dest="show_all",
        help="show every serial port, including non-USB devices",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    """Print verbose information for matching serial ports."""
    args = parse_args(argv)

    try:
        ports = sorted(list_ports.comports())
    except Exception as error:
        print(
            f"Error: Could not enumerate serial ports: "
            f"{type(error).__name__}: {error}",
            file=sys.stderr,
        )
        return 1

    if not args.show_all:
        ports = [port for port in ports if port.vid is not None]

    if not ports:
        if args.show_all:
            print("No serial ports found.")
        else:
            print("No USB serial ports found. Use --all to show every serial port.")
        return 0

    for port in ports:
        print(port.device)
        print(f"    desc: {port.description}")
        print(f"    hwid: {port.hwid}")

    suffix = "port" if len(ports) == 1 else "ports"
    port_kind = "serial" if args.show_all else "USB serial"
    print(f"{len(ports)} {port_kind} {suffix} found.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
