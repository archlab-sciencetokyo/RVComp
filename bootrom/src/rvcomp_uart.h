/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2026 Archlab, Science Tokyo
 */
 
#ifndef RVCOMP_UART_H_
#define RVCOMP_UART_H_

#include <stdint.h>

void uart_putc(char ch);
int  uart_getc(void);
void uart_puts(char *str);
void printIntAsHex(uint32_t value); 

#endif // RVCOMP_UART_H_
