/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

OUTPUT_ARCH("riscv")
ENTRY("_start")

SECTIONS
{
    . = 0x80000000;
    .text.init : { *(.text.init) }
    .text.startup : { *(.text.startup) }
    .text : { *(.text) }
    . = ALIGN(0x1000);
    .data : { *(data) }
    . = ALIGN(0x1000);
    .rodata : { *(.rodata) }
    . = ALIGN(0x1000);
    .bss : { *(.bss) }
    _end = .;
}
