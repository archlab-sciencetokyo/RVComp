/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */
 
OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
    . = 0x10000;
    .text.start : { *(.text.start) }
    .text : { *(.text) }
    .rodata.dtb : { *(.rodata.dtb) }
}
