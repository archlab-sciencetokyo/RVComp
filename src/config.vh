/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */
 
`ifndef CONFIG_VH_
`define CONFIG_VH_
/* Flexivle value */ 
/******************************************************************************************/
// Nexys
  `define NEXYS
 
// Ethernet PHY interface selection
// `ETH_IF_RMII : RMII (2-bit, 50MHz reference clock)
// `ETH_IF_MII  : MII  (4-bit, RX/TX clocks from PHY)
`ifdef NEXYS
    `define ETH_IF_RMII
`else
    `define ETH_IF_MII
`endif

// Ethernet destination MAC filter target (on-wire byte order)
`define ETH_MAC_ADDR_0        8'hAA
`define ETH_MAC_ADDR_1        8'hBB
`define ETH_MAC_ADDR_2        8'hCC
`define ETH_MAC_ADDR_3        8'hDD
`define ETH_MAC_ADDR_4        8'hEE
`define ETH_MAC_ADDR_5        8'hFF

`ifndef ETHER_RXBUF_SIZE
    `define ETHER_RXBUF_SIZE      (16*1024 )
`endif
`ifndef ETHER_TXBUF_SIZE
    `define ETHER_TXBUF_SIZE      (8*1024  )
`endif

`define DEBUG_ILA_RMII
// CLKFREQ
`ifndef CLK_FREQ_MHZ
    `define CLK_FREQ_MHZ        (100     ) // MHz
`endif

// cpu
`define PHT_ENTRIES             (8*1024  ) // pattern history table size
`define BTB_ENTRIES             (512     ) // branch target buffer size

// cache
`define L0_ICACHE_SIZE          (1024    ) // L0I$ size [bytes] need to be less than 4KiB
`define L1_ICACHE_SIZE          (16*1024 ) // L1I$ size [bytes] need to be greater than 4KiB
`define L1_DCACHE_SIZE          (16*1024 ) // L1D$ size [bytes] need to be greater than 4KiB
`define L2_CACHE_SIZE           (32*1024 ) // L2$ (32*1024 ) size [bytes]

// TLB cache size
`define ITLB_ENTRIES            (64      ) // instruction TLB entry           
`define DTLB_ENTRIES            (64      ) // data TLB entry

// uart
`define BAUD_RATE               (2000000 ) // uart baud rate
`define DETECT_COUNT            (2       ) // uart detect count
`define FIFO_DEPTH              (2*1024  ) // uart fifo depth

/******************************************************************************************/

`endif // CONFIG_VH_
