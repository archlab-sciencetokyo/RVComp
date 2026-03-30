/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

#include "io.h"
#include <stdint.h>

int main(void) {
    uart_puts("Hello, world!\n");
    uint32_t len = *(volatile uint32_t *)(0x10004000 + 0x0); // ETHER_REG_RECV_PACKET_LEN
    uart_puts("Received packet length: ");
    char len_str[11];
    for (int i = 10; i > 0; i--) {
        len_str[i-1] = (len % 10) + '0';
        len /= 10;
    }
    len_str[10] = '\0';
    uart_puts(len_str);
    uart_puts("\n");

    return 0;
}
