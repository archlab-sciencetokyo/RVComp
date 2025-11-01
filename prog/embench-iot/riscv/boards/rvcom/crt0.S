/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

    .equ UART_BASE      , 0x10000000
    .equ DRAM_BASE      , 0x80000000
    .equ DRAM_SIZE      , 0x10000000 # 256 MiB
    .section .text.init
    .align 4
    .globl _start
_start:
    j reset_vector

trap_vector: # exit(1)
    li t0, 1
write_tohost:
    sw t0, tohost, t1
    sw zero, tohost+4, t1
    j write_tohost

    .globl uart_putc
uart_putc:
    li t0, UART_BASE
    sb a0, 0(t0)
    ret

    .globl uart_puts
uart_puts:
    li t0, UART_BASE
1:  lbu t1, 0(a0)
    bnez t1, 2f
    ret
2:  sb t1, 0(t0)
    addi a0, a0, 1
    j 1b

reset_vector:
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
    li sp, DRAM_BASE+DRAM_SIZE # set the stack pointer
    la t0, trap_vector
    csrw mtvec, t0
    jal main
    unimp # trap_illgal_instruction, jump to trap_vector, exit(1)

    .pushsection .tohost,"aw",@progbits
    .align 6
    .global tohost
tohost:
    .dword 0
    .size tohost, 8

    .align 6
    .global fromhost
fromhost:
    .dword 0
    .size fromhost, 8
    .popsection

    .align 4
    .globl start_trigger
start_trigger:
    addi sp, sp, -16
    sw ra, 12(sp)
    la a0, str_start
    jal uart_puts
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

    .align 4
    .globl stop_trigger
stop_trigger:
    addi sp, sp, -16
    sw ra, 12(sp)
    la a0, str_stop
    jal uart_puts
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

    .section .rodata
    .align 4
str_start:
    .string "start!\n"
    .align 4
str_stop:
    .string "stop!\n"
    .align 4
