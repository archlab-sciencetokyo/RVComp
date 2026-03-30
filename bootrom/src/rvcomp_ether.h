/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2026 Archlab, Science Tokyo
 */
 
#ifndef RVCOMP_ETHER_H_
#define RVCOMP_ETHER_H_

#include <stdint.h>
// 16 KiB
// Ethernet Memory Map (16-bit address space, [15:14] for region selection)
#define ETHER_CSR_BASE            0x14000000
#define ETHER_RXBUF_BASE          0x18000000
#define ETHER_RXBUF_SIZE          0x00004000  // 16 KiB
#define ETHER_TXBUF_BASE          0x1c000000
#define ETHER_TXBUF_SIZE          0x00002000  // 8 KiB
#define ETHER_REG_ADDR_START      0
#define ETHER_REG_ADDR_END        1
#define ETHER_REG_RX_READ_BYTE  2
#define ETHER_REG_RX_ERR        3
#define ETHER_REG_TX_BUSY       4
#define ETHER_REG_TX_BUFFER_START 5
#define ETHER_REG_TX_BUFFER_END   6

#define ETHER_MTU                 1514
void     ether_tx(uint8_t *data, uint32_t len);
uint32_t ether_rx(uint8_t *buf);
#endif // RVCOMP_ETHER_H_
