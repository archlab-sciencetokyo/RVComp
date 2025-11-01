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
`define DDR2

// CLKFREQ
`ifndef CLK_FREQ_MHZ
    `define CLK_FREQ_MHZ        (160     ) // MHz
`endif

// cpu
`define PHT_ENTRIES             (8*1024  ) // pattern history table size
`define BTB_ENTRIES             (512     ) // branch target buffer size

// cache
`define L0_ICACHE_SIZE          (1024    ) // L0I$ size [bytes] need to be less than 4KiB
`define L1_ICACHE_SIZE          (32*1024 ) // L1I$ size [bytes] need to be greater than 4KiB
`define L1_DCACHE_SIZE          (32*1024 ) // L1D$ size [bytes] need to be greater than 4KiB
`define L2_CACHE_SIZE           (128*1024) // L2$ (128*1024) size [bytes]

// TLB cache size
`define ITLB_ENTRIES            (128     ) // instruction TLB entry           
`define DTLB_ENTRIES            (128     ) // data TLB entry

// uart
`define BAUD_RATE               (3200000 ) // uart baud rate
`define DETECT_COUNT            (2       ) // uart detect count
`define FIFO_DEPTH              (2048    ) // uart fifo depth


/******************************************************************************************/

`endif // CONFIG_VH_
