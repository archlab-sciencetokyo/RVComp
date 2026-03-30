/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2026 Archlab, Science Tokyo
 */
 
#include <stdint.h>

#include "rvcomp_mmc.h"
#include "rvcomp_uart.h"

#define DRAM_BASE   0x80000000

// #define UART_BOOT

static inline volatile uint32_t *mmc_window_words(void) {
    return (volatile uint32_t *)(MMC_CSR_BASE + MMC_WINDOW_BASE);
}

static inline void mmc_set_addr29(uint32_t addr29) {
    mmc_csr_write(MMC_CSR_ADDR29, addr29 & 0x1FFFFFFFu);
}

static void mmc_copy_to_dram(volatile uint32_t *dram_word_addr, uint32_t image_words) {
    volatile uint32_t * const mmc_win = mmc_window_words();
    uint32_t copied = 0;
    uint32_t addr29 = 0;

    while (copied < image_words) {
        uint32_t words_this_page = image_words - copied;
        if (words_this_page > MMC_WINDOW_WORDS) {
            words_this_page = MMC_WINDOW_WORDS;
        }

        mmc_set_addr29(addr29++);
        for (uint32_t i = 0; i < words_this_page; i++) {
            dram_word_addr[copied + i] = mmc_win[i];
        }
        copied += words_this_page;
    }
}

void bootloader(void) {
    uart_puts("[     bootrom] Hello, world!\n");
#ifdef UART_BOOT
    int byte;
    static volatile uint8_t * const addr = (volatile uint8_t *)DRAM_BASE;
    for (int i=0; i<BIN_SIZE; i++) {
        while ((byte = uart_getc()) == -1);
        *(addr+i) = (uint8_t)byte;
    }
#else // MMC_BOOT
    static volatile uint32_t * const dram_word_addr = (volatile uint32_t *)DRAM_BASE;
    const uint32_t image_words = (BIN_SIZE + 3u) / 4u;
    mmc_copy_to_dram(dram_word_addr, image_words);
#endif
    uart_puts("[     bootrom] dram initialization finished!\n");
}
