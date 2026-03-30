// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Archlab, Science Tokyo

// rvcomp_ether.c
#include "rvcomp_ether.h"

static volatile uint32_t * const ether_reg  = (volatile uint32_t *)ETHER_CSR_BASE;
static volatile uint32_t  * const ether_rxbuf = (volatile uint32_t  *)(ETHER_RXBUF_BASE);
static volatile uint32_t  * const ether_txbuf = (volatile uint32_t  *)(ETHER_TXBUF_BASE);

static uint32_t ether_tx_enqueue_one(const uint8_t *data, uint32_t len, uint32_t end) {
    const uint32_t min_frame_len = 60U;
    uint32_t frame_len = (len < min_frame_len) ? min_frame_len : len;
    uint32_t payload_aligned = (frame_len + 3U) & ~0x3U;
    uint32_t payload_idx = 0;
    uint32_t pos = end;

    *(ether_txbuf + (pos >> 2)) = frame_len;
    pos = (pos + 4U) % ETHER_TXBUF_SIZE;

    while (payload_idx < payload_aligned) {
        uint32_t word = 0;
        for (uint32_t i = 0; i < 4U; i++) {
            uint8_t b = 0;
        if (payload_idx < len) {
            b = data[payload_idx];
        }
        word |= ((uint32_t)b) << (i * 8U);
        payload_idx++;
    }
    *(ether_txbuf + (pos >> 2)) = word;
    pos = (pos + 4U) % ETHER_TXBUF_SIZE;
    }

    return pos;
}

void ether_tx(uint8_t *data, uint32_t len) {
    const uint32_t min_frame_len = 60U;
    while (len > 0U) {
        uint32_t chunk_len = (len > ETHER_MTU) ? ETHER_MTU : len;
        uint32_t frame_len = (chunk_len < min_frame_len) ? min_frame_len : chunk_len;
        uint32_t record_size = 4U + ((frame_len + 3U) & ~0x3U);
        uint32_t start;
        uint32_t end;
        uint32_t used;
        uint32_t free_bytes;

        while (1) {
            start = *(ether_reg + ETHER_REG_TX_BUFFER_START);
            end   = *(ether_reg + ETHER_REG_TX_BUFFER_END);
            start = (start & (ETHER_TXBUF_SIZE - 1U)) & ~0x3U;
            end   = (end & (ETHER_TXBUF_SIZE - 1U)) & ~0x3U;
            used = (end + ETHER_TXBUF_SIZE - start) % ETHER_TXBUF_SIZE;
            free_bytes = ETHER_TXBUF_SIZE - used - 4U;
            if (free_bytes >= record_size) {
                uint32_t new_end = ether_tx_enqueue_one(data, chunk_len, end);
                __asm__ volatile("fence w,w" ::: "memory");
                *(ether_reg + ETHER_REG_TX_BUFFER_END) = new_end;
                break;
            }
        }

        data += chunk_len;
        len  -= chunk_len;
    }
}

uint32_t ether_rx(uint8_t *buf) {
    uint32_t start = *(ether_reg + ETHER_REG_ADDR_START);
    uint32_t end = *(ether_reg + ETHER_REG_ADDR_END);
    if (start == end) {
        return 0;
    } else{
        start = ((start + 3) % ETHER_RXBUF_SIZE) & ~0x3; // Align to 4 bytes
    }
    uint32_t len;
    if (end < start) {
        len = end + ETHER_RXBUF_SIZE - start;
    } else {
        len = end - start;
    }
    len = (len > ETHER_MTU) ? ETHER_MTU : len;
    // Use 32-bit word access and manually extract bytes (little-endian)
    uint32_t eth_index = start >> 2;
    uint32_t buf_index = 0;
    while (1) {
        uint32_t word = *(ether_rxbuf + eth_index);
        if (buf_index < len) buf[buf_index++] = (word >>  0) & 0xFF;
        if (buf_index < len) buf[buf_index++] = (word >>  8) & 0xFF;
        if (buf_index < len) buf[buf_index++] = (word >> 16) & 0xFF;
        if (buf_index < len) buf[buf_index++] = (word >> 24) & 0xFF;
        eth_index += 1;
        eth_index %= (ETHER_RXBUF_SIZE >> 2); // 1 word = 4 bytes
        if (buf_index >= len) break;
    }
    *(ether_reg + ETHER_REG_ADDR_START) = (start + len) % ETHER_RXBUF_SIZE; // Align to 4 bytes
    return len;
}
