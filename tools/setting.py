#!/usr/bin/python3

# SPDX-License-Identifier: MIT
#
# Copyright (c) 2026 Archlab, Science Tokyo

"""
Interactive settings configuration tool for RVComp (menuconfig-like TUI).
Uses curses for a keyboard-driven terminal UI.

Usage:
    make menuconfig
    # or directly:
    uv run --project tools/ setting
"""

import curses
import os
import re
import sys
from dataclasses import dataclass
from typing import Optional

# Fix slow Esc key (default is 1000ms)
os.environ.setdefault("ESCDELAY", "25")

# ==============================================================================
# Constants
# ==============================================================================

BOARDS = ["nexys4ddr", "arty_a7"]

BOARD_DISPLAY = {
    "nexys4ddr": "Nexys A7-100T",
    "arty_a7": "Arty A7-35T",
}

BOARD_DIALOG_DESC = {
    "nexys4ddr": "Nexys A7-100T (128 MiB DDR)",
    "arty_a7": "Arty A7-35T (256 MiB DDR)",
}

BOOT_DISPLAY = {
    "mmc": "MMC",
    "uart": "UART",
}

ETHER_CSR_BASE = 0x14000000
ETHER_CSR_SIZE = 0x4000
ETHER_RXBUF_BASE = 0x18000000
ETHER_TXBUF_BASE = 0x1C000000
ETHER_BUF_MAX = 64 * 1024 * 1024

BOARD_DEFAULTS = {
    "nexys4ddr": {
        "clk_freq": 150,
        "pht_entry": 8192,
        "btb_entry": 512,
        "l0_icache_size": 1024,
        "l1_icache_size": 16384,
        "l1_dcache_size": 16384,
        "l2_cache_size": 131072,
        "baudrate": 3000000,
        "itlb_entry": 128,
        "dtlb_entry": 128,
        "fifo_depth": 2048,
        "ether_rxbuf_size": 16384,
        "ether_txbuf_size": 8192,
    },
    "arty_a7": {
        "clk_freq": 150,
        "pht_entry": 8192,
        "btb_entry": 512,
        "l0_icache_size": 1024,
        "l1_icache_size": 16384,
        "l1_dcache_size": 16384,
        "l2_cache_size": 65536,
        "baudrate": 3000000,
        "itlb_entry": 128,
        "dtlb_entry": 128,
        "fifo_depth": 2048,
        "ether_rxbuf_size": 16384,
        "ether_txbuf_size": 4096,
    },
}

CONFIG_VH_MAP = {
    "clk_freq": "CLK_FREQ_MHZ",
    "pht_entry": "PHT_ENTRIES",
    "btb_entry": "BTB_ENTRIES",
    "l0_icache_size": "L0_ICACHE_SIZE",
    "l1_icache_size": "L1_ICACHE_SIZE",
    "l1_dcache_size": "L1_DCACHE_SIZE",
    "l2_cache_size": "L2_CACHE_SIZE",
    "baudrate": "BAUD_RATE",
    "itlb_entry": "ITLB_ENTRIES",
    "dtlb_entry": "DTLB_ENTRIES",
    "fifo_depth": "FIFO_DEPTH",
    "ether_rxbuf_size": "ETHER_RXBUF_SIZE",
    "ether_txbuf_size": "ETHER_TXBUF_SIZE",
}


@dataclass
class SettingItem:
    key: str
    label: str
    description: str
    greater_than: int
    power_of_2: bool
    unit: str = ""
    kind: str = "int"  # "int", "choice", "separator"
    choices: list[str] | None = None


MENU_ITEMS: list[SettingItem] = [
    SettingItem("_sep_board", "── Board ──", "", 0, False, kind="separator"),
    SettingItem("board", "Board", "FPGA board selection", 0, False, kind="choice", choices=BOARDS),
    SettingItem("boot", "Boot Method", "Boot method (Nexys A7-100T: MMC/UART selectable, Arty A7-35T: UART only)", 0, False, kind="choice", choices=["mmc", "uart"]),
    SettingItem("_sep_cpu", "── CPU / Branch Predictor ──", "", 0, False, kind="separator"),
    SettingItem("clk_freq", "Clock Frequency", "Clock frequency for the FPGA design", 0, False, "MHz"),
    SettingItem("pht_entry", "PHT Entries", "Pattern History Table size for branch prediction", 0, True, "entries"),
    SettingItem("btb_entry", "BTB Entries", "Branch Target Buffer size", 0, True, "entries"),
    SettingItem("_sep_cache", "── Cache ──", "", 0, False, kind="separator"),
    SettingItem("l0_icache_size", "L0 ICache Size", "L0 instruction cache size", 0, True, "bytes"),
    SettingItem("l1_icache_size", "L1 ICache Size", "L1 instruction cache size", 4096, True, "bytes"),
    SettingItem("l1_dcache_size", "L1 DCache Size", "L1 data cache size", 4096, True, "bytes"),
    SettingItem("l2_cache_size", "L2 Cache Size", "L2 unified cache size", 0, True, "bytes"),
    SettingItem("_sep_tlb", "── TLB ──", "", 0, False, kind="separator"),
    SettingItem("itlb_entry", "ITLB Entries", "Instruction TLB entry count", 0, True, "entries"),
    SettingItem("dtlb_entry", "DTLB Entries", "Data TLB entry count", 0, True, "entries"),
    SettingItem("_sep_uart", "── UART ──", "", 0, False, kind="separator"),
    SettingItem("baudrate", "UART Baud Rate", "UART communication baud rate", 0, False, "bps"),
    SettingItem("fifo_depth", "UART FIFO Depth", "UART FIFO buffer depth", 0, True, "entries"),
    SettingItem("_sep_ether", "── Ethernet ──", "", 0, False, kind="separator"),
    SettingItem("ether_rxbuf_size", "Ethernet RXBuf Size", "Ethernet receive ring buffer size", 1024, True, "bytes"),
    SettingItem("ether_txbuf_size", "Ethernet TXBuf Size", "Ethernet transmit ring buffer size", 1024, True, "bytes"),
]

SELECTABLE_ITEMS = [i for i, item in enumerate(MENU_ITEMS) if item.kind != "separator"]

BUTTONS = ["< Save >", "< Load Defaults >", "< Exit >"]


# ==============================================================================
# Helpers
# ==============================================================================


def format_value(val: int, unit: str) -> str:
    """Format a value with unit; show KiB for byte values >= 1024."""
    if unit == "bytes" and val >= 1024:
        return f"{val} ({val // 1024} KiB)"
    return str(val)


def format_p2_option(val: int, unit: str) -> str:
    """Format a power-of-2 option for the selection dialog."""
    if unit == "bytes" and val >= 1024:
        return f"{val} ({val // 1024} KiB)"
    return f"{val} {unit}"


def p2_options(default: int, item: SettingItem) -> list[int]:
    """Generate 5 power-of-2 options centered on the board default value."""
    candidates = [default // 4, default // 2, default, default * 2, default * 4]
    opts = []
    for v in candidates:
        if v > item.greater_than and v > 0:
            if v not in opts:
                opts.append(v)
    return opts


# ==============================================================================
# Config file parsing / writing (same logic as original setting.py)
# ==============================================================================


def get_project_root() -> str:
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def parse_boot_method() -> str:
    """Read current boot method from bootloader.c."""
    root = get_project_root()
    bootloader_file = os.path.join(root, "bootrom", "src", "bootloader.c")
    if os.path.exists(bootloader_file):
        with open(bootloader_file, "r") as f:
            content = f.read()
        if re.search(r"^\s*#define\s+UART_BOOT", content, re.MULTILINE):
            return "uart"
    return "mmc"


def parse_config_vh() -> dict:
    root = get_project_root()
    config_file = os.path.join(root, "src", "config.vh")
    values = {}

    with open(config_file, "r") as f:
        content = f.read()

    if re.search(r"^\s*`define\s+NEXYS\b", content, re.MULTILINE):
        values["board"] = "nexys4ddr"
    else:
        values["board"] = "arty_a7"

    values["boot"] = parse_boot_method()
    # Force UART for arty_a7
    if values["board"] == "arty_a7":
        values["boot"] = "uart"

    for key, define_name in CONFIG_VH_MAP.items():
        pattern = rf"`define\s+{define_name}\s+\(([^)]+)\)"
        match = re.search(pattern, content)
        if match:
            expr = match.group(1).strip()
            try:
                val = eval(expr, {"__builtins__": {}})
                values[key] = int(val)
            except Exception:
                values[key] = 0

    return values


def replace_config(lines: list[str], key: str, value: int, is_mul: bool) -> list[str]:
    wordnum: int = 10
    for i in range(len(lines)):
        if re.search(key, lines[i]):
            words: str = "("
            if is_mul and value > 1024:
                words += str(value // 1024) + "*1024"
            else:
                words += str(value)
            for _ in range(len(words), wordnum - 1):
                words += " "
            words += ")"
            lines[i] = re.sub(r"\([^\)]+\)", words, lines[i])
    return lines


def format_u32_hex(value: int) -> str:
    return f"0x{value:08x}"


def sync_ethernet_dts(dts_lines: list[str], rxbuf_size: int, txbuf_size: int) -> list[str]:
    in_ethernet = False
    for i, line in enumerate(dts_lines):
        if re.search(r"ethernet@[0-9a-fA-F]+", line):
            in_ethernet = True
            dts_lines[i] = re.sub(r"ethernet@[0-9a-fA-F]+", f"ethernet@{ETHER_CSR_BASE:08x}", line)
        elif in_ethernet and "reg = <0x0" in line:
            indent = re.match(r"^(\s*)", line).group(1)
            dts_lines[i:i + 3] = [
                f"{indent}reg = <0x0 {format_u32_hex(ETHER_CSR_BASE)} 0x0 {format_u32_hex(ETHER_CSR_SIZE)}>,\n",
                f"{indent}      <0x0 {format_u32_hex(ETHER_RXBUF_BASE)} 0x0 {format_u32_hex(rxbuf_size)}>,\n",
                f"{indent}      <0x0 {format_u32_hex(ETHER_TXBUF_BASE)} 0x0 {format_u32_hex(txbuf_size)}>;\n",
            ]
            break
        elif in_ethernet and line.strip() == "};":
            in_ethernet = False
    return dts_lines


def sync_ethernet_header(header_lines: list[str], rxbuf_size: int, txbuf_size: int) -> list[str]:
    replacements = {
        "ETHER_CSR_BASE": ETHER_CSR_BASE,
        "ETHER_RXBUF_BASE": ETHER_RXBUF_BASE,
        "ETHER_RXBUF_SIZE": rxbuf_size,
        "ETHER_TXBUF_BASE": ETHER_TXBUF_BASE,
        "ETHER_TXBUF_SIZE": txbuf_size,
    }
    for i, line in enumerate(header_lines):
        for macro, value in replacements.items():
            if re.match(rf"^#define\s+{macro}\b", line):
                comment = ""
                if macro.endswith("_SIZE"):
                    comment = f"  // {value // 1024} KiB"
                header_lines[i] = f"#define {macro:<25} {format_u32_hex(value)}{comment}\n"
                break
    return header_lines


def apply_settings(values: dict) -> None:
    root = get_project_root()
    rxbuf_size = values.get("ether_rxbuf_size", 16384)
    txbuf_size = values.get("ether_txbuf_size", 16384)

    # --- src/config.vh ---
    config_file = os.path.join(root, "src", "config.vh")
    with open(config_file, "r") as f:
        lines = f.readlines()

    board = values.get("board")
    if board:
        for i in range(len(lines)):
            if board == "nexys4ddr":
                if re.match(r"\s*//\s*`define\s+NEXYS", lines[i]):
                    lines[i] = re.sub(r"^//", "", lines[i])
            elif board == "arty_a7":
                if re.match(r"\s*`define\s+NEXYS", lines[i]):
                    lines[i] = "//" + lines[i]

    for key, define_name in CONFIG_VH_MAP.items():
        if key in values and values[key] is not None:
            is_mul = key not in ("clk_freq", "baudrate")
            replace_config(lines, rf"`define\s+{define_name}", values[key], is_mul)

    with open(config_file, "w") as f:
        f.writelines(lines)

    # --- bootrom/rvcomp.dts ---
    dts_file = os.path.join(root, "bootrom", "rvcomp.dts")
    with open(dts_file, "r") as f:
        dts_lines = f.readlines()

    if values.get("clk_freq"):
        clk_freq_hz = values["clk_freq"] * 1000000
        for i in range(len(dts_lines)):
            if re.search("frequency", dts_lines[i]):
                dts_lines[i] = re.sub(r"[0-9]+", str(clk_freq_hz), dts_lines[i])

    if board:
        for i in range(len(dts_lines)):
            for b in BOARDS:
                if re.search(b, dts_lines[i]):
                    if b == board:
                        dts_lines[i] = re.sub(r"^//", "", dts_lines[i])
                    else:
                        dts_lines[i] = re.sub(r"^(\s)", r"//\1", dts_lines[i])

    dts_lines = sync_ethernet_dts(dts_lines, rxbuf_size, txbuf_size)

    with open(dts_file, "w") as f:
        f.writelines(dts_lines)

    # --- bootrom/src/rvcomp_ether.h ---
    ether_header = os.path.join(root, "bootrom", "src", "rvcomp_ether.h")
    with open(ether_header, "r") as f:
        ether_lines = f.readlines()
    ether_lines = sync_ethernet_header(ether_lines, rxbuf_size, txbuf_size)
    with open(ether_header, "w") as f:
        f.writelines(ether_lines)

    # --- config.mk ---
    configmk_file = os.path.join(root, "config.mk")
    if os.path.exists(configmk_file):
        with open(configmk_file, "r") as f:
            mk_lines = f.readlines()
    else:
        mk_lines = [
            "# Auto-generated by setting tool\n",
            "NEXYS4DDR := 0\n",
            "ARTY_A7   := 0\n",
            "BAUD_RATE := 2500000\n",
        ]

    if board:
        board_variables = [r"^(NEXYS4DDR\s*:=)\s*[0-9]+", r"^(ARTY_A7\s*:=)\s*[0-9]+"]
        board_num = BOARDS.index(board)
        for i in range(len(mk_lines)):
            for j in range(len(board_variables)):
                if re.search(board_variables[j], mk_lines[i]):
                    if j == board_num:
                        mk_lines[i] = re.sub(board_variables[j], r"\1 1", mk_lines[i])
                    else:
                        mk_lines[i] = re.sub(board_variables[j], r"\1 0", mk_lines[i])

    if values.get("baudrate"):
        for i in range(len(mk_lines)):
            mk_lines[i] = re.sub(
                r"^(BAUD_RATE\s*:=)\s*[0-9]+", r"\1 " + str(values["baudrate"]), mk_lines[i]
            )

    with open(configmk_file, "w") as f:
        f.writelines(mk_lines)

    # --- Makefile (BAUD_RATE) ---
    makefile = os.path.join(root, "Makefile")
    if os.path.exists(makefile) and values.get("baudrate"):
        with open(makefile, "r") as f:
            mf_lines = f.readlines()
        for i in range(len(mf_lines)):
            mf_lines[i] = re.sub(
                r"^(BAUD_RATE\s*:=)\s*[0-9]+", r"\1 " + str(values["baudrate"]), mf_lines[i]
            )
        with open(makefile, "w") as f:
            f.writelines(mf_lines)

    # --- bootrom/src/bootloader.c ---
    boot = values.get("boot")
    if board == "arty_a7":
        boot = "uart"

    if boot:
        bootloader_file = os.path.join(root, "bootrom", "src", "bootloader.c")
        if os.path.exists(bootloader_file):
            with open(bootloader_file, "r") as f:
                boot_lines = f.readlines()
            for i in range(len(boot_lines)):
                if boot == "uart":
                    if re.match(r"\s*//\s*#define\s+UART_BOOT", boot_lines[i]):
                        boot_lines[i] = re.sub(r"^//\s*", "", boot_lines[i])
                if boot == "mmc":
                    if re.match(r"\s*#define\s+UART_BOOT", boot_lines[i]):
                        boot_lines[i] = "// " + boot_lines[i]
            with open(bootloader_file, "w") as f:
                f.writelines(boot_lines)


def validate_value(item: SettingItem, value: int) -> str | None:
    """Validate a setting value. Returns error message or None if valid."""
    if value <= item.greater_than:
        return f"Must be > {item.greater_than}"
    if item.power_of_2 and (value & (value - 1)) != 0:
        return "Must be power of 2"
    if item.key in ("ether_rxbuf_size", "ether_txbuf_size") and value > ETHER_BUF_MAX:
        return f"Must be <= {ETHER_BUF_MAX} (64 MiB)"
    return None


# ==============================================================================
# Curses TUI
# ==============================================================================


def safe_addstr(win, y: int, x: int, text: str, attr=0):
    """addstr that silently ignores writes outside the window."""
    h, w = win.getmaxyx()
    if y < 0 or y >= h or x >= w:
        return
    max_len = w - x
    if max_len <= 0:
        return
    try:
        win.addnstr(y, x, text, max_len, attr)
    except curses.error:
        pass


def draw_menu(stdscr, values: dict, cursor: int, btn_idx: int, focus: str,
              scroll_offset: int, status_msg: str):
    """Draw the full menu screen."""
    stdscr.erase()
    h, w = stdscr.getmaxyx()

    # Colors
    TITLE = curses.color_pair(1)
    HIGHLIGHT = curses.color_pair(2)
    SEP = curses.color_pair(3)
    VALUE = curses.color_pair(4)
    BTN_NORMAL = curses.color_pair(5)
    BTN_ACTIVE = curses.color_pair(6)
    DESC = curses.color_pair(8)
    STATUS_OK = curses.color_pair(10)

    # Title bar
    title = " RVComp Settings "
    safe_addstr(stdscr, 0, 0, " " * w, TITLE | curses.A_BOLD)
    safe_addstr(stdscr, 0, max(0, (w - len(title)) // 2), title, TITLE | curses.A_BOLD)

    # Help line
    help_text = " \u2191\u2193:Select  \u2190\u2192:Buttons  Enter:Edit  Esc:Quit "
    safe_addstr(stdscr, 1, 0, " " * w, curses.color_pair(9))
    safe_addstr(stdscr, 1, max(0, (w - len(help_text)) // 2), help_text, curses.color_pair(9))

    # Menu area
    menu_top = 3
    menu_bottom = h - 6
    menu_height = max(1, menu_bottom - menu_top)

    # Adjust scroll
    cursor_visual = SELECTABLE_ITEMS[cursor]
    if cursor_visual - scroll_offset >= menu_height:
        scroll_offset = cursor_visual - menu_height + 1
    if cursor_visual < scroll_offset:
        scroll_offset = cursor_visual

    board = values.get("board", "nexys4ddr")

    for row in range(menu_height):
        item_idx = row + scroll_offset
        if item_idx >= len(MENU_ITEMS):
            break

        y = menu_top + row
        item = MENU_ITEMS[item_idx]

        if item.kind == "separator":
            safe_addstr(stdscr, y, 1, item.label, SEP | curses.A_BOLD)
            continue

        is_selected = (focus == "menu" and item_idx == SELECTABLE_ITEMS[cursor])
        attr = HIGHLIGHT | curses.A_BOLD if is_selected else curses.A_NORMAL
        prefix = " > " if is_selected else "   "

        label_col = 3
        value_col = 26
        default_col = 50

        safe_addstr(stdscr, y, 0, prefix, attr)
        safe_addstr(stdscr, y, label_col, item.label, attr)

        if item.key == "board":
            display_name = BOARD_DISPLAY.get(values.get("board", ""), values.get("board", ""))
            val_str = f"[{display_name}]"
            safe_addstr(stdscr, y, value_col, val_str, VALUE | curses.A_BOLD)
        elif item.key == "boot":
            boot_val = values.get("boot", "mmc")
            display_boot = BOOT_DISPLAY.get(boot_val, boot_val)
            if board == "arty_a7":
                val_str = f"[{display_boot}] (fixed)"
                safe_addstr(stdscr, y, value_col, val_str, curses.A_DIM)
            else:
                val_str = f"[{display_boot}]"
                safe_addstr(stdscr, y, value_col, val_str, VALUE | curses.A_BOLD)
        elif item.kind == "choice":
            val_str = f"[{values.get(item.key, '')}]"
            safe_addstr(stdscr, y, value_col, val_str, VALUE | curses.A_BOLD)
        else:
            val = values.get(item.key, 0)
            val_str = format_value(val, item.unit)
            safe_addstr(stdscr, y, value_col, val_str, VALUE | curses.A_BOLD)
            if item.unit:
                safe_addstr(stdscr, y, value_col + len(val_str) + 1, item.unit, curses.A_DIM)

            # Show default
            default_val = BOARD_DEFAULTS[board].get(item.key, "?")
            default_str = f"(default: {format_value(default_val, item.unit) if isinstance(default_val, int) else default_val})"
            safe_addstr(stdscr, y, default_col, default_str, curses.A_DIM)

    # Description area
    desc_y = h - 5
    safe_addstr(stdscr, desc_y, 0, "\u2500" * w, curses.A_DIM)
    current_item = MENU_ITEMS[SELECTABLE_ITEMS[cursor]]
    desc_label = "Description: "
    desc_text = current_item.description
    constraints = []
    if current_item.power_of_2:
        constraints.append("power of 2")
    if current_item.greater_than > 0:
        constraints.append(f"> {current_item.greater_than}")
    if constraints:
        desc_text += "  [Constraint: " + ", ".join(constraints) + "]"
    safe_addstr(stdscr, desc_y + 1, 2, desc_label, DESC | curses.A_BOLD)
    safe_addstr(stdscr, desc_y + 1, 2 + len(desc_label), desc_text, DESC)

    # Buttons bar
    btn_y = h - 3
    safe_addstr(stdscr, btn_y, 0, "\u2500" * w, curses.A_DIM)
    total_btn_w = sum(len(b) for b in BUTTONS) + 3 * (len(BUTTONS) - 1)
    btn_x = max(0, (w - total_btn_w) // 2)
    for i, btn_label in enumerate(BUTTONS):
        if focus == "buttons" and i == btn_idx:
            attr = BTN_ACTIVE | curses.A_BOLD
        else:
            attr = curses.color_pair(11) | curses.A_BOLD
        safe_addstr(stdscr, btn_y + 1, btn_x, btn_label, attr)
        btn_x += len(btn_label) + 3

    # Status bar (green)
    if status_msg:
        safe_addstr(stdscr, h - 1, 0, " " * w, STATUS_OK)
        safe_addstr(stdscr, h - 1, 1, status_msg, STATUS_OK | curses.A_BOLD)

    stdscr.refresh()
    return scroll_offset


def edit_value_dialog(stdscr, item: SettingItem, current_value: int) -> int | None:
    """Show an inline edit dialog for a numeric value. Returns new value or None."""
    h, w = stdscr.getmaxyx()
    dw = min(50, w - 4)
    dh = 10
    dy = max(0, (h - dh) // 2)
    dx = max(0, (w - dw) // 2)

    BORDER = curses.color_pair(6)
    FIELD  = curses.color_pair(13)   # black on white  = text input box
    CURSOR = curses.color_pair(12)   # black on yellow = cursor position

    edit_buf = str(current_value)
    cursor_pos = len(edit_buf)
    error_msg = ""

    while True:
        for row in range(dh):
            safe_addstr(stdscr, dy + row, dx, " " * dw, BORDER)

        title = f" Edit: {item.label} "
        safe_addstr(stdscr, dy + 1, dx + max(0, (dw - len(title)) // 2), title, BORDER | curses.A_BOLD)

        field_y = dy + 3
        field_x = dx + 2
        field_w = dw - 4
        # Draw field as black-on-white (clear text-input look)
        safe_addstr(stdscr, field_y, field_x, " " * field_w, FIELD)
        safe_addstr(stdscr, field_y, field_x, edit_buf[:field_w], FIELD)
        # Software cursor: highlight the character at cursor_pos with a gray rectangle.
        # This is reliable across terminals unlike A_BLINK or hardware cursor.
        cur_ch = edit_buf[cursor_pos] if cursor_pos < len(edit_buf) else " "
        cx = field_x + min(cursor_pos, field_w - 1)
        try:
            stdscr.addch(field_y, cx, cur_ch, CURSOR)
        except curses.error:
            pass

        unit_hint = f"Unit: {item.unit}"
        safe_addstr(stdscr, dy + 5, dx + 2, unit_hint[:dw - 4], BORDER | curses.A_DIM)
        constraints = []
        if item.power_of_2:
            constraints.append("power of 2")
        if item.greater_than > 0:
            constraints.append(f"> {item.greater_than}")
        if constraints:
            constraint_hint = "Constraint: " + ", ".join(constraints)
            safe_addstr(stdscr, dy + 6, dx + 2, constraint_hint[:dw - 4], BORDER | curses.A_DIM)

        if error_msg:
            safe_addstr(stdscr, dy + 7, dx + 2, error_msg[:dw - 4], curses.color_pair(7) | curses.A_BOLD)

        safe_addstr(stdscr, dy + dh - 2, dx + 2, "Enter:OK  Esc:Cancel", BORDER | curses.A_DIM)

        try:
            stdscr.move(field_y, cx)
        except curses.error:
            pass
        curses.curs_set(0)  # hide hardware cursor; we use software cursor above
        stdscr.refresh()

        ch = stdscr.getch()

        if ch == 27:
            curses.curs_set(0)
            return None
        elif ch in (curses.KEY_ENTER, 10, 13):
            try:
                val = int(edit_buf)
                err = validate_value(item, val)
                if err:
                    error_msg = f"Error: {err}"
                    continue
                curses.curs_set(0)
                return val
            except ValueError:
                error_msg = "Error: Not a valid integer"
        elif ch in (curses.KEY_BACKSPACE, 127, 8):
            if cursor_pos > 0:
                edit_buf = edit_buf[:cursor_pos - 1] + edit_buf[cursor_pos:]
                cursor_pos -= 1
                error_msg = ""
        elif ch == curses.KEY_DC:
            if cursor_pos < len(edit_buf):
                edit_buf = edit_buf[:cursor_pos] + edit_buf[cursor_pos + 1:]
                error_msg = ""
        elif ch == curses.KEY_LEFT:
            if cursor_pos > 0:
                cursor_pos -= 1
        elif ch == curses.KEY_RIGHT:
            if cursor_pos < len(edit_buf):
                cursor_pos += 1
        elif ch == curses.KEY_HOME:
            cursor_pos = 0
        elif ch == curses.KEY_END:
            cursor_pos = len(edit_buf)
        elif 32 <= ch < 127:
            c = chr(ch)
            if c.isdigit() or (c == '-' and cursor_pos == 0):
                edit_buf = edit_buf[:cursor_pos] + c + edit_buf[cursor_pos:]
                cursor_pos += 1
                error_msg = ""


def p2_select_dialog(stdscr, item: SettingItem, current_value: int, board: str) -> int | None:
    """Show a selection dialog for power-of-2 values.
    5 options centered on board default: default/4, /2, default, *2, *4, plus Custom.
    """
    h, w = stdscr.getmaxyx()
    default_val = BOARD_DEFAULTS.get(board, {}).get(item.key, current_value)
    options = p2_options(default_val, item)
    custom_label = "Custom..."
    n_opts = len(options) + 1  # +1 for Custom
    dw = min(60, w - 4)
    dh = n_opts + 7
    dy = max(0, (h - dh) // 2)
    dx = max(0, (w - dw) // 2)

    BORDER = curses.color_pair(6)
    SELECTED = curses.color_pair(2)

    # Pre-select current value, or default if current not in options
    if current_value in options:
        sel = options.index(current_value)
    elif default_val in options:
        sel = options.index(default_val)
    else:
        sel = len(options) // 2

    while True:
        for row in range(dh):
            safe_addstr(stdscr, dy + row, dx, " " * dw, BORDER)

        title = f" Select: {item.label} "
        safe_addstr(stdscr, dy + 1, dx + max(0, (dw - len(title)) // 2), title, BORDER | curses.A_BOLD)

        for i, opt in enumerate(options):
            cy = dy + 3 + i
            marker = "(*)" if opt == current_value else "( )"
            label = f"  {marker} {format_p2_option(opt, item.unit)}"
            if opt == default_val:
                label += " [default]"
            if opt == current_value:
                label += "  <-- current"
            if i == sel:
                safe_addstr(stdscr, cy, dx + 2, label[:dw - 4], SELECTED | curses.A_BOLD)
            else:
                safe_addstr(stdscr, cy, dx + 2, label[:dw - 4], BORDER)

        # Custom option
        custom_y = dy + 3 + len(options)
        custom_marker = "  ( ) " + custom_label
        if sel == len(options):
            safe_addstr(stdscr, custom_y, dx + 2, custom_marker[:dw - 4], SELECTED | curses.A_BOLD)
        else:
            safe_addstr(stdscr, custom_y, dx + 2, custom_marker[:dw - 4], BORDER)

        safe_addstr(stdscr, dy + dh - 2, dx + 2, "\u2191\u2193:Select  Enter:OK  Esc:Cancel", BORDER | curses.A_DIM)

        stdscr.refresh()
        ch = stdscr.getch()

        if ch == curses.KEY_UP:
            if sel > 0:
                sel -= 1
        elif ch == curses.KEY_DOWN:
            if sel < n_opts - 1:
                sel += 1
        elif ch in (curses.KEY_ENTER, 10, 13):
            if sel < len(options):
                return options[sel]
            else:
                # Signal to caller to handle custom input with proper layering
                return "CUSTOM"
        elif ch == 27:
            return None


def board_select_dialog(stdscr, current: str) -> str | None:
    """Show board selection dialog with friendly names."""
    h, w = stdscr.getmaxyx()
    dw = min(60, w - 4)
    dh = len(BOARDS) + 7
    dy = max(0, (h - dh) // 2)
    dx = max(0, (w - dw) // 2)

    BORDER = curses.color_pair(6)
    SELECTED = curses.color_pair(2)

    try:
        sel = BOARDS.index(current)
    except ValueError:
        sel = 0

    while True:
        for row in range(dh):
            safe_addstr(stdscr, dy + row, dx, " " * dw, BORDER)

        title = " Select Board "
        safe_addstr(stdscr, dy + 1, dx + max(0, (dw - len(title)) // 2), title, BORDER | curses.A_BOLD)

        for i, board_key in enumerate(BOARDS):
            cy = dy + 3 + i
            marker = "(*)" if board_key == current else "( )"
            desc = BOARD_DIALOG_DESC.get(board_key, board_key)
            label = f"  {marker} {desc}"

            if i == sel:
                safe_addstr(stdscr, cy, dx + 2, label[:dw - 4], SELECTED | curses.A_BOLD)
            else:
                safe_addstr(stdscr, cy, dx + 2, label[:dw - 4], BORDER)

        safe_addstr(stdscr, dy + dh - 2, dx + 2, "\u2191\u2193:Select  Enter:OK  Esc:Cancel", BORDER | curses.A_DIM)

        stdscr.refresh()
        ch = stdscr.getch()

        if ch == curses.KEY_UP:
            if sel > 0:
                sel -= 1
        elif ch == curses.KEY_DOWN:
            if sel < len(BOARDS) - 1:
                sel += 1
        elif ch in (curses.KEY_ENTER, 10, 13):
            return BOARDS[sel]
        elif ch == 27:
            return None


def boot_select_dialog(stdscr, current: str) -> str | None:
    """Show boot method selection dialog."""
    boot_choices = ["mmc", "uart"]
    h, w = stdscr.getmaxyx()
    dw = min(50, w - 4)
    dh = len(boot_choices) + 7
    dy = max(0, (h - dh) // 2)
    dx = max(0, (w - dw) // 2)

    BORDER = curses.color_pair(6)
    SELECTED = curses.color_pair(2)

    try:
        sel = boot_choices.index(current)
    except ValueError:
        sel = 0

    while True:
        for row in range(dh):
            safe_addstr(stdscr, dy + row, dx, " " * dw, BORDER)

        title = " Select Boot Method "
        safe_addstr(stdscr, dy + 1, dx + max(0, (dw - len(title)) // 2), title, BORDER | curses.A_BOLD)

        for i, boot_key in enumerate(boot_choices):
            cy = dy + 3 + i
            marker = "(*)" if boot_key == current else "( )"
            display = BOOT_DISPLAY.get(boot_key, boot_key)
            label = f"  {marker} {display}"
            if i == sel:
                safe_addstr(stdscr, cy, dx + 2, label[:dw - 4], SELECTED | curses.A_BOLD)
            else:
                safe_addstr(stdscr, cy, dx + 2, label[:dw - 4], BORDER)

        safe_addstr(stdscr, dy + dh - 2, dx + 2, "\u2191\u2193:Select  Enter:OK  Esc:Cancel", BORDER | curses.A_DIM)

        stdscr.refresh()
        ch = stdscr.getch()

        if ch == curses.KEY_UP:
            if sel > 0:
                sel -= 1
        elif ch == curses.KEY_DOWN:
            if sel < len(boot_choices) - 1:
                sel += 1
        elif ch in (curses.KEY_ENTER, 10, 13):
            return boot_choices[sel]
        elif ch == 27:
            return None


def confirm_dialog(stdscr, message: str) -> bool:
    """Show a yes/no confirmation dialog."""
    h, w = stdscr.getmaxyx()
    dw = min(40, w - 4)
    dh = 5
    dy = max(0, (h - dh) // 2)
    dx = max(0, (w - dw) // 2)

    BORDER = curses.color_pair(6)
    selected = 1  # default: No (safer — accidental Enter won't discard changes)

    # Drain any buffered keypresses so rapid Enter/Esc doesn't auto-confirm.
    stdscr.nodelay(True)
    while stdscr.getch() != -1:
        pass
    stdscr.nodelay(False)

    while True:
        for row in range(dh):
            safe_addstr(stdscr, dy + row, dx, " " * dw, BORDER)

        safe_addstr(stdscr, dy + 1, dx + max(0, (dw - len(message)) // 2), message, BORDER | curses.A_BOLD)

        yes_label = "< Yes >"
        no_label = "< No >"
        btn_y = dy + 3
        yes_x = dx + dw // 2 - len(yes_label) - 2
        no_x = dx + dw // 2 + 2

        yes_attr = (curses.color_pair(2) | curses.A_BOLD) if selected == 0 else BORDER
        no_attr = (curses.color_pair(2) | curses.A_BOLD) if selected == 1 else BORDER
        safe_addstr(stdscr, btn_y, yes_x, yes_label, yes_attr)
        safe_addstr(stdscr, btn_y, no_x, no_label, no_attr)

        stdscr.refresh()
        ch = stdscr.getch()

        if ch in (curses.KEY_LEFT, curses.KEY_RIGHT):
            selected = 1 - selected
        elif ch in (curses.KEY_ENTER, 10, 13):
            return selected == 0
        elif ch == 27:
            return False


def run_tui(stdscr):
    """Main TUI loop."""
    curses.curs_set(0)
    curses.use_default_colors()

    curses.init_pair(1, curses.COLOR_WHITE, curses.COLOR_BLUE)    # Title
    curses.init_pair(2, curses.COLOR_BLACK, curses.COLOR_CYAN)    # Highlight
    curses.init_pair(3, curses.COLOR_YELLOW, -1)                  # Separator
    curses.init_pair(4, curses.COLOR_GREEN, -1)                   # Value
    curses.init_pair(5, curses.COLOR_WHITE, -1)                   # Button normal
    curses.init_pair(6, curses.COLOR_WHITE, curses.COLOR_BLUE)    # Button active / dialog
    curses.init_pair(7, curses.COLOR_WHITE, curses.COLOR_RED)     # Error
    curses.init_pair(8, curses.COLOR_CYAN, -1)                    # Description
    curses.init_pair(9, curses.COLOR_BLACK, curses.COLOR_WHITE)   # Help line
    curses.init_pair(10, curses.COLOR_WHITE, curses.COLOR_GREEN)  # Status (green)
    curses.init_pair(11, curses.COLOR_BLACK, curses.COLOR_WHITE)  # Button inactive (prominent)
    # Cursor: black text on gray background.
    # color 250 ≈ #bcbcbc (light gray) in 256-color terminals; fall back to white.
    _cursor_bg = 244 if curses.COLORS >= 256 else curses.COLOR_WHITE
    curses.init_pair(12, curses.COLOR_BLACK, _cursor_bg) # Edit cursor (gray block)
    curses.init_pair(13, curses.COLOR_BLACK, curses.COLOR_WHITE)  # Input field

    values = parse_config_vh()
    original_values = dict(values)
    cursor = 0
    btn_idx = 0
    focus = "menu"
    scroll_offset = 0
    status_msg = ""

    while True:
        scroll_offset = draw_menu(stdscr, values, cursor, btn_idx, focus, scroll_offset, status_msg)
        ch = stdscr.getch()
        status_msg = ""

        if ch == curses.KEY_RESIZE:
            stdscr.clear()
            continue

        if focus == "menu":
            if ch == curses.KEY_UP:
                if cursor > 0:
                    cursor -= 1
            elif ch == curses.KEY_DOWN:
                if cursor < len(SELECTABLE_ITEMS) - 1:
                    cursor += 1
            elif ch in (curses.KEY_LEFT, curses.KEY_RIGHT):
                focus = "buttons"
            elif ch in (curses.KEY_ENTER, 10, 13, ord(' ')):
                item = MENU_ITEMS[SELECTABLE_ITEMS[cursor]]
                if item.key == "board":
                    result = board_select_dialog(stdscr, values.get("board", ""))
                    if result is not None:
                        values["board"] = result
                        display = BOARD_DISPLAY.get(result, result)
                        status_msg = f"Board: {display}"
                        # Force boot to UART for arty_a7
                        if result == "arty_a7":
                            values["boot"] = "uart"
                elif item.key == "boot":
                    if values.get("board") == "arty_a7":
                        status_msg = "Boot method is fixed to UART for Arty A7-35T"
                    else:
                        result = boot_select_dialog(stdscr, values.get("boot", "mmc"))
                        if result is not None:
                            values["boot"] = result
                            status_msg = f"Boot: {BOOT_DISPLAY.get(result, result)}"
                elif item.kind == "int" and item.power_of_2:
                    result = p2_select_dialog(stdscr, item, values.get(item.key, 0), values.get("board", "nexys4ddr"))
                    if result == "CUSTOM":
                        # Redraw main menu (layer 1) then show custom input (layer 3)
                        scroll_offset = draw_menu(stdscr, values, cursor, btn_idx, focus, scroll_offset, "")
                        result = edit_value_dialog(stdscr, item, values.get(item.key, 0))
                    if result is not None:
                        values[item.key] = result
                        status_msg = f"{item.label}: {format_value(result, item.unit)}"
                elif item.kind == "int":
                    result = edit_value_dialog(stdscr, item, values.get(item.key, 0))
                    if result is not None:
                        values[item.key] = result
                        status_msg = f"{item.label}: {result}"
            elif ch == 27:
                if values != original_values:
                    if confirm_dialog(stdscr, "Discard changes?"):
                        break
                else:
                    break

        elif focus == "buttons":
            if ch == curses.KEY_LEFT:
                if btn_idx > 0:
                    btn_idx -= 1
            elif ch == curses.KEY_RIGHT:
                if btn_idx < len(BUTTONS) - 1:
                    btn_idx += 1
            elif ch in (curses.KEY_UP, curses.KEY_DOWN):
                focus = "menu"
            elif ch in (curses.KEY_ENTER, 10, 13):
                if btn_idx == 0:  # Save
                    if confirm_dialog(stdscr, "Save settings?"):
                        try:
                            apply_settings(values)
                            original_values = dict(values)
                            status_msg = "Settings saved successfully!"
                        except Exception as e:
                            status_msg = f"Error: {e}"
                elif btn_idx == 1:  # Load Defaults
                    board = values.get("board", "nexys4ddr")
                    if confirm_dialog(stdscr, f"Load defaults for {BOARD_DISPLAY.get(board, board)}?"):
                        defaults = BOARD_DEFAULTS[board]
                        for key, val in defaults.items():
                            values[key] = val
                        # Board-specific boot default
                        values["boot"] = "uart" if board == "arty_a7" else "mmc"
                        status_msg = f"Loaded defaults for {BOARD_DISPLAY.get(board, board)}"
                elif btn_idx == 2:  # Exit
                    if values != original_values:
                        if confirm_dialog(stdscr, "Discard changes?"):
                            break
                    else:
                        break
            elif ch == 27:
                focus = "menu"


def main():
    curses.wrapper(run_tui)


# ==============================================================================
# CLI entry point  (make cliconfig)
# ==============================================================================

def cli_main():
    """Non-interactive CLI configuration.

    Usage:
        make cliconfig ARGS="--clk-freq 150 --board nexys4ddr"
        # or directly:
        uv run --project tools/ cliconfig --clk-freq 150
    """
    import argparse

    def _checker(name: str, gt: int, p2: bool):
        def check(v: str) -> int:
            try:
                iv = int(v)
            except ValueError:
                raise argparse.ArgumentTypeError(f"{name} must be an integer")
            if iv <= gt:
                raise argparse.ArgumentTypeError(f"{name} must be > {gt}")
            if p2 and (iv & (iv - 1)) != 0:
                raise argparse.ArgumentTypeError(f"{name} must be a power of 2")
            return iv
        return check

    parser = argparse.ArgumentParser(
        prog="cliconfig",
        description="RVComp CLI configuration tool\n\nAvailable boards: " + ", ".join(BOARDS),
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument("--board",           choices=BOARDS,       default=None, help="FPGA board")
    parser.add_argument("--boot",            choices=["mmc","uart"], default=None, help="Boot method")
    parser.add_argument("--default",         action="store_true",                help="Load board defaults (requires --board)")
    parser.add_argument("--clk-freq",        type=_checker("Clock Frequency", 0,    False), default=None, metavar="MHz")
    parser.add_argument("--pht-entry",       type=_checker("PHT Entries",     0,    True),  default=None, metavar="N")
    parser.add_argument("--btb-entry",       type=_checker("BTB Entries",     0,    True),  default=None, metavar="N")
    parser.add_argument("--l0-icache-size",  type=_checker("L0 ICache Size",  0,    True),  default=None, metavar="bytes")
    parser.add_argument("--l1-icache-size",  type=_checker("L1 ICache Size",  4096, True),  default=None, metavar="bytes")
    parser.add_argument("--l1-dcache-size",  type=_checker("L1 DCache Size",  4096, True),  default=None, metavar="bytes")
    parser.add_argument("--l2-cache-size",   type=_checker("L2 Cache Size",   0,    True),  default=None, metavar="bytes")
    parser.add_argument("--itlb-entry",      type=_checker("ITLB Entries",    0,    True),  default=None, metavar="N")
    parser.add_argument("--dtlb-entry",      type=_checker("DTLB Entries",    0,    True),  default=None, metavar="N")
    parser.add_argument("--baudrate",        type=_checker("UART Baud Rate",  0,    False), default=None, metavar="bps")
    parser.add_argument("--fifo-depth",      type=_checker("UART FIFO Depth", 0,    True),  default=None, metavar="N")

    args = parser.parse_args()

    # --default requires --board
    if args.default and args.board is None:
        parser.error("--default requires --board")

    # Read current config as baseline
    values = parse_config_vh()

    # Apply --board first (also forces boot for arty_a7)
    if args.board is not None:
        values["board"] = args.board
        if args.board == "arty_a7":
            values["boot"] = "uart"

    # Apply --default (overrides everything with board defaults)
    if args.default:
        for k, v in BOARD_DEFAULTS[args.board].items():
            values[k] = v
        values["boot"] = "uart" if args.board == "arty_a7" else "mmc"

    # Map CLI args → setting keys
    _map = {
        "boot":           args.boot,
        "clk_freq":       args.clk_freq,
        "pht_entries":    args.pht_entry,
        "btb_entries":    args.btb_entry,
        "l0_icache_size": args.l0_icache_size,
        "l1_icache_size": args.l1_icache_size,
        "l1_dcache_size": args.l1_dcache_size,
        "l2_cache_size":  args.l2_cache_size,
        "itlb_entries":   args.itlb_entry,
        "dtlb_entries":   args.dtlb_entry,
        "baudrate":       args.baudrate,
        "fifo_depth":     args.fifo_depth,
    }

    # Validate and apply individual overrides
    item_map = {item.key: item for item in MENU_ITEMS if item.kind == "int"}
    for key, val in _map.items():
        if val is None:
            continue
        if key == "boot":
            if args.board == "arty_a7" and val == "mmc":
                print(f"Warning: arty_a7 does not support MMC boot; keeping 'uart'", file=sys.stderr)
                continue
            values["boot"] = val
            continue
        item = item_map.get(key)
        if item:
            err = validate_value(item, val)
            if err:
                print(f"Error [{key}]: {err}", file=sys.stderr)
                sys.exit(1)
        values[key] = val

    apply_settings(values)

    # Summary
    board_disp = BOARD_DISPLAY.get(values.get("board", ""), values.get("board", ""))
    print(f"Settings applied successfully. Board: {board_disp}")
    changed = {k: v for k, v in _map.items() if v is not None}
    if args.board:
        changed["board"] = args.board
    if args.default:
        changed["(loaded defaults for)"] = args.board
    for k, v in changed.items():
        print(f"  {k} = {v}")


if __name__ == "__main__":
    main()
