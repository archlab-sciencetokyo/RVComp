/*
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2026 Archlab, Science Tokyo
 */

#include "rvcomp_mmc.h"

static volatile uint32_t * const mmc_csr = (volatile uint32_t *)MMC_CSR_BASE;

void mmc_csr_write(uint32_t byte_offset, uint32_t data)
{
    mmc_csr[byte_offset >> 2] = data;
}

uint32_t mmc_csr_read(uint32_t byte_offset)
{
    return mmc_csr[byte_offset >> 2];
}
