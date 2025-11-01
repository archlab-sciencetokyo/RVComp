/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

#ifndef IO_H_
#define IO_H_

void uart_putc(const char c);
void uart_puts(const char * const s);

const static char * const s = "0123456789abcdef";

void uart_put_num(int num, const int base) {
    char buf[256];
    int i = 0;
    while (num!=0) {
        buf[i] = s[num%base];
        num /= base;
        i++;
    }
    while (--i>=0) {
        uart_putc(buf[i]);
    }
}

void uart_putb(int num) {
    uart_put_num(num, 2);
}

void uart_putd(int num) {
    uart_put_num(num, 10);
}

void uart_puth(int num) {
    uart_put_num(num, 16);
}

#endif // IO_H_
