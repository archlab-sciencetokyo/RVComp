#!/usr/bin/python3

# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025 Archlab, Science Tokyo

import sys
import os
import re
import argparse
from typing import Optional, Callable

boards = ["nexys4ddr", "arty_a7"]

# fpga, clk-freq, l0-size, l1-icache-size, l1-dcache-size, uart-baudrate, itlb-entry, dtlb-entry ,l2-size, 
def parse_args() -> argparse.ArgumentParser: 
    """Parse command line arguments.
    
    Returns:
        dict[str, int]: Dictionary of arguments
    """
    global boards
    def make_checker(parameter: str, greater_than: int, power_of_2: bool) -> Callable[[Optional[str]], int]:
        def checker(value: Optional[str]) -> None:
            if value is not None:
                try:
                    value = int(value)
                    if value <= greater_than:
                        raise argparse.ArgumentTypeError(f"{parameter} must be greater than {greater_than}")
                    if power_of_2 and (value & (value - 1)) != 0:
                        raise argparse.ArgumentTypeError(f"{parameter} must be power of 2")
                    return value
                except ValueError:
                    raise argparse.ArgumentTypeError(f"{parameter} must be an integer")
        return checker
            
    description =  "RVComp Settings\n\nAvailable boards:\n" 
    description += "- " + "\n- ".join(boards)
    parser = argparse.ArgumentParser(description=description, formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("--board", help="FPGA board name", type=str, default=None, choices=boards) 
    parser.add_argument("--default", help="Set all to default values", action="store_true")
    parser.add_argument("--clk-freq", help="Clock frequency [MHz]", type=make_checker("Clock Frequency", 0, False), default=None)
    parser.add_argument("--l0-icache-size", help="L0 instruction cache size [byte]", type=make_checker("L0 ICache Size", 0, True), default=None)
    parser.add_argument("--l1-icache-size", help="L1 instruction cache size [byte]", type=make_checker("L1 ICache Size", 4096, True), default=None)
    parser.add_argument("--l1-dcache-size", help="L1 data cache size [byte]", type=make_checker("L1 DCache Size", 4096, True), default=None)
    parser.add_argument("--l2-cache-size", help="L2 cache size [byte]", type=make_checker("L2 Cache Size", 0, True), default=None)
    parser.add_argument("--baudrate", help="UART baudrate", type=make_checker("UART Baudrate", 0, False), default=None)
    parser.add_argument("--itlb-entry", help="ITLB entries", type=make_checker("ITLB Entries", 0, True), default=None)
    parser.add_argument("--dtlb-entry", help="DTLB entries", type=make_checker("DTLB Entries", 0, True), default=None)
    parser.add_argument("--pht-entry", help="PHT entries", type=make_checker("PHT Entries", 0, True), default=None)
    parser.add_argument("--btb-entry", help="BTB entries", type=make_checker("BTB Entries", 0, True), default=None)
    parser.add_argument("--fifo-depth", help="UART FIFO depth", type=make_checker("UART FIFO Depth", 0, True), default=None)

    args = parser.parse_args()
    if args.board is not None and args.board not in boards:
        print(f"Error: {args.board} is not supported.")
        sys.exit(1)
    
    if args.default and args.board is None:
        print("Error: --board is required when --default is specified.")
        sys.exit(1)
    
    if args.default:
        if args.board == "nexys4ddr":
            args.clk_freq = 160
            args.pht_entry = 8192
            args.btb_entry = 512
            args.l0_icache_size = 1024
            args.l1_icache_size = 32768
            args.l1_dcache_size = 32768
            args.l2_cache_size = 131072
            args.baudrate = 3200000
            args.itlb_entry = 128
            args.dtlb_entry = 128
            args.fifo_depth = 2048
        elif args.board == "arty_a7":
            args.clk_freq = 150
            args.pht_entry = 8192
            args.btb_entry = 512
            args.l0_icache_size = 1024
            args.l1_icache_size = 16384
            args.l1_dcache_size = 16384
            args.l2_cache_size = 65536
            args.baudrate = 3300000
            args.itlb_entry = 128
            args.dtlb_entry = 128
            args.fifo_depth = 2048
    return args

def update_dts_file(args: argparse.ArgumentParser) -> None:
    """Update the device tree source file with the given arguments.
    
    Args:
        args (argparse.ArgumentParser): Parsed command line arguments
    """
    global boards    
    now_file = os.path.abspath(__file__)
    now_dir = os.path.dirname(now_file)
    dts_file = os.path.join(now_dir, "bootrom/rvcom.dts")
    with open(dts_file, "r") as f:
        lines = f.readlines()

    # frequency
    if args.clk_freq:
        clk_freq_hz = args.clk_freq * 1000000
        for i in range(len(lines)):
            if re.search("frequency", lines[i]):
                lines[i] = re.sub(r"[0-9]+", str(clk_freq_hz), lines[i])
    # board
    if args.board:
        for i in range(len(lines)):
            for board in boards:
                if re.search(board, lines[i]):
                    if board == args.board:
                        lines[i] = re.sub(r"^//", "", lines[i])
                    else:
                        lines[i] = re.sub(r"^(\s)", r"//\1", lines[i])    
    
    with open(dts_file, "w") as f:
        f.writelines(lines)
    return 


def replace_config(lines: list[str], key: str, value: int, is_mul: bool) -> list[str]:
    """Replace the value of a key in the configuration lines.
    
    Args:
        lines (list[str]): List of lines in the configuration file
        key (str): Key to be replaced
        value (str): New value for the key
    
    Returns:
        list[str]: Updated list of lines
    """
    wordnum: int = 10
    for i in range(len(lines)):
        if re.search(key, lines[i]):
            words: str = "("
            if is_mul and value > 1024:
                words += str(value // 1024) + "*1024"
            else:
                words += str(value)
            for _ in range(len(words), wordnum-1):
                words += " "
            words += ")"
            lines[i] = re.sub(r"\([^\)]+\)", words, lines[i])
        
    return lines

def update_config_file(args: argparse.ArgumentParser) -> None:
    """Update the configuration file with the given arguments.
    
    Args:
        args (argparse.ArgumentParser): Parsed command line arguments
    """

    now_file = os.path.abspath(__file__)
    now_dir = os.path.dirname(now_file)
    config_file = os.path.join(now_dir, "src/config.vh")
    with open(config_file, "r") as f:
        lines = f.readlines()
    
    # board
    if args.board:
        if args.board == "nexys4ddr":
            for i in range(len(lines)):
                if re.match(r"//\s*`define\s+DDR2", lines[i]):
                    lines[i] = re.sub(r"^//", "", lines[i])
        if args.board == "arty_a7":
            for i in range(len(lines)):
                if re.match(r"`define\s+DDR2", lines[i]):
                    lines[i] = "//" + lines[i]
    
    # clock frequency
    if args.clk_freq:
        replace_config(lines, r"`define\s+CLK_FREQ", args.clk_freq, False)
    # l0 icache size
    if args.l0_icache_size:
        replace_config(lines, r"`define\s+L0_ICACHE_SIZE", args.l0_icache_size, True)
    # l1 icache size
    if args.l1_icache_size:
        replace_config(lines, r"`define\s+L1_ICACHE_SIZE", args.l1_icache_size, True)
    # l1 dcache size
    if args.l1_dcache_size:
        replace_config(lines, r"`define\s+L1_DCACHE_SIZE", args.l1_dcache_size, True)
    # l2 cache size
    if args.l2_cache_size:
        replace_config(lines, r"`define\s+L2_CACHE_SIZE", args.l2_cache_size, True)
    # baudrate
    if args.baudrate:
        replace_config(lines, r"`define\s+BAUD_RATE", args.baudrate, False)
    # itlb etnry
    if args.itlb_entry:
        replace_config(lines, r"`define\s+ITLB_ENTRIES", args.itlb_entry, True)
    # dtlb entry
    if args.dtlb_entry:
        replace_config(lines, r"`define\s+DTLB_ENTRIES", args.dtlb_entry, True)
    # pht entry
    if args.pht_entry:
        replace_config(lines, r"`define\s+PHT_ENTRIES", args.pht_entry, True)
    # btb entry
    if args.btb_entry:
        replace_config(lines, r"`define\s+BTB_ENTRIES", args.btb_entry, True) 
    with open(config_file, "w") as f:
        f.writelines(lines)

    return

def update_configmk(args: argparse.ArgumentParser) -> None:
    """Update the config.mk file with the given arguments.
    
    Args:
        args (argparse.ArgumentParser): Parsed command line arguments
    """
    if args.board is None and args.baudrate is None:
        return
    global boards
    now_file = os.path.abspath(__file__)
    now_dir = os.path.dirname(now_file)
    configmk_file = os.path.join(now_dir, "config.mk")
    with open(configmk_file, "r") as f:
        lines = f.readlines()

    # board
    if args.board:
        board_num = -1
        for i in range(len(boards)):
            if args.board == boards[i]:
                board_num = i
        board_variables = [r"^(NEXYS4DDR\s*:=)\s*[0-9]+", r"^(ARTY_A7\s*:=)\s*[0-9]+"]
        for i in range(len(lines)):
            for j in range(len(board_variables)):
                if re.search(board_variables[j], lines[i]):
                    if j == board_num:
                        lines[i] = re.sub(board_variables[j], r"\1 1", lines[i])
                    else:
                        lines[i] = re.sub(board_variables[j], r"\1 0", lines[i])
    # baudrate
    if args.baudrate:
        for i in range(len(lines)):
            lines[i] = re.sub(r"^(BAUD_RATE\s*:=)\s*[0-9]+", r"\1 " + str(args.baudrate), lines[i])
    
    with open(configmk_file, "w") as f:
        f.writelines(lines)
    return

if __name__=="__main__":
    args = parse_args()
    now_file = os.path.abspath(__file__)
    now_dir = os.path.dirname(now_file)
    update_dts_file(args)
    update_config_file(args)
    update_configmk(args)
    # subprocess.run(["make", "clean"], cwd=now_dir)
    # subprocess.run(["make", "bootrom"], cwd=now_dir)
    