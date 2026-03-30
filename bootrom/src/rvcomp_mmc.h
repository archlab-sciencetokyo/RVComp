/*
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2026 Archlab, Science Tokyo
 */

#ifndef RVCOMP_MMC_H_
#define RVCOMP_MMC_H_

#include <stdint.h>

#define MMC_CSR_BASE           0xA0000000u

/* CSR offsets (byte) */
#define MMC_CSR_ADDR29         0x000u
#define MMC_CSR_FLUSH          0x018u
#define MMC_CSR_FLUSH_DONE     0x01Cu
#define MMC_CSR_FLUSH_DONE_CLR 0x020u

/* 4 KiB MMIO window */
#define MMC_WINDOW_BASE        0x1000u
#define MMC_WINDOW_SIZE        0x1000u
#define MMC_WINDOW_WORDS       (MMC_WINDOW_SIZE / 4u)

void mmc_csr_write(uint32_t byte_offset, uint32_t data);
uint32_t mmc_csr_read(uint32_t byte_offset);

#endif // RVCOMP_MMC_H_
