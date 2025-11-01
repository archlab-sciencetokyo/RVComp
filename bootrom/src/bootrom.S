/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */
 
    .equ DRAM_BASE  , 0x80000000
    .equ STACK_BASE , DRAM_BASE+0x08000000

    .section .text.start, "ax", @progbits
    .globl _start
_start:
#if !defined(NO_UART_BOOT)
    li x1, 0
    li x3, 0
    li x4, 0
    li x5, 0
    li x6, 0
    li x7, 0
    li x8, 0
    li x9, 0
    li x10, 0
    li x11, 0
    li x12, 0
    li x13, 0
    li x14, 0
    li x15, 0
    li x16, 0
    li x17, 0
    li x18, 0
    li x19, 0
    li x20, 0
    li x21, 0
    li x22, 0
    li x23, 0
    li x24, 0
    li x25, 0
    li x26, 0
    li x27, 0
    li x28, 0
    li x29, 0
    li x30, 0
    li x31, 0
    li sp, STACK_BASE
    jal bootloader
    li x1, 0
    li x2, 0
    li x3, 0
    li x4, 0
    li x5, 0
    li x6, 0
    li x7, 0
    li x9, 0
    li x12, 0
    li x13, 0
    li x14, 0
    li x15, 0
    li x16, 0
    li x17, 0
    li x18, 0
    li x19, 0
    li x20, 0
    li x21, 0
    li x22, 0
    li x23, 0
    li x24, 0
    li x25, 0
    li x26, 0
    li x27, 0
    li x28, 0
    li x29, 0
    li x30, 0
    li x31, 0
#endif // !defined(NO_UART_BOOT)
    li s0, DRAM_BASE
    csrr a0, mhartid
    la a1, _dtb
    jr s0

    .section .rodata.dtb, "a", @progbits
    .globl _dtb
    .align 5, 0
_dtb:
    .incbin "rvcom.dtb"
