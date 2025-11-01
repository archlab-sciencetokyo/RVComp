/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */
 
#ifndef RVCOM_UART_H_
#define RVCOM_UART_H_

#include <stdint.h>

void uart_putc(char ch);
int  uart_getc(void);
void uart_puts(char *str);

#endif // RVCOM_UART_H_
