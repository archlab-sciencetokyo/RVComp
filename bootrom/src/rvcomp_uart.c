/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2026 Archlab, Science Tokyo
 */
 
#include "rvcomp_uart.h"

#include <stdint.h>

#include "io.h"

#define UART_REG_RXTX       0
#define UART_REG_TXFULL     1
#define UART_REG_RXEMPTY    2

static volatile uint32_t * const uart_base = (volatile uint32_t *)0x10000000;

static uint8_t get_reg(uint8_t reg) {
    return readb(uart_base+reg);
}

static void set_reg(uint8_t reg, uint8_t val) {
    writeb(val, uart_base+reg);
}

void uart_putc(char ch) {
    while (get_reg(UART_REG_TXFULL));
    set_reg(UART_REG_RXTX, ch);
}

int uart_getc(void) {
    if (get_reg(UART_REG_RXEMPTY))
        return -1;
    return get_reg(UART_REG_RXTX);
}

void uart_puts(char *str) {
    while (*str!='\0') uart_putc(*str++);
}

void printIntAsHex(uint32_t value) {
    uart_puts("0x");
    for (int i = 28; i >= 0; i -= 4) {
        uint8_t nibble = (value >> i) & 0xF;
        uart_putc("0123456789ABCDEF"[nibble]);
    }
    uart_puts("\r\n");
}