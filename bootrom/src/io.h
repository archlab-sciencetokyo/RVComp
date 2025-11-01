/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */
 
#ifndef IO_H_
#define IO_H_

#include <stdint.h>

static inline void _writeb(uint8_t val, volatile void *addr) {
    asm volatile("sb %0, 0(%1)" : : "r"(val), "r"(addr));
}

static inline uint8_t _readb(const volatile void *addr) {
    uint8_t val;
    asm volatile("lb %0, 0(%1)" : "=r"(val) : "r"(addr));
    return val;
}

#define readb(addr) ({ uint8_t _val; _val = _readb(addr); _val; })
#define writeb(val, addr) ({ _writeb((val), (addr)); })

#endif // IO_H_
