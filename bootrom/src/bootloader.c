/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */
 
#include <stdint.h>

#include "rvcom_uart.h"

#define DRAM_BASE   0x80000000

static volatile uint8_t * const addr = (volatile uint8_t *)DRAM_BASE;

void bootloader(void) {
    uart_puts("[     bootrom] Hello, world!\n");
    int byte;
    for (int i=0; i<BIN_SIZE; i++) {
        while ((byte = uart_getc()) == -1);
        *(addr+i) = (uint8_t)byte;
    }
    uart_puts("[     bootrom] dram initialization finished!\n");
}
