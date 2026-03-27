/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */
 
`ifndef RVCPU_H_
`define RVCPU_H_

`include "config.vh"

/* Constant Value */
/******************************************************************************************/
// soc
`define RESET_VECTOR                'h00010000
`define START_PC                    'h80000000

`define DRAM_BASE                   'h80000000
`ifdef NEXYS // 
    `define DRAM_SIZE               (128*1024*1024) // Nexys
`else // DDR3
    `define DRAM_SIZE               (256*1024*1024) // Arty
`endif
`define UART_BASE                   'h10000000

`define SIG_ADDR                    'h7ffffff8

// cpu
`define XLEN                        32
`define XBYTES                      (`XLEN/8)

`define VLEN                        32 // VLEN = (XLEN==32) ? 32 : 64
`define PLEN                        34 // PLEN = (XLEN==32) ? 34 : 56
`define PPN_WIDTH                   22 
`define VPN_WIDTH                   20
`define PG_OFFSET_WIDTH             12

`define ISA_CODE                    32'h40141101 // 32-bit | U | S | M | I | A

// instruction bus
`define IBUS_ADDR_WIDTH             `PLEN
`define IBUS_DATA_WIDTH             128
`define IBUS_OFFSET_WIDTH           $clog2(`IBUS_DATA_WIDTH/8)

// data bus
`define DBUS_ADDR_WIDTH             `PLEN
`define DBUS_DATA_WIDTH             `XLEN
`define DBUS_STRB_WIDTH             (`DBUS_DATA_WIDTH/8)
`define DBUS_OFFSET_WIDTH           $clog2(`DBUS_DATA_WIDTH/8)

// bus
`define BUS_ADDR_WIDTH              `PLEN
`define BUS_DATA_WIDTH              128
`define BUS_STRB_WIDTH              (`BUS_DATA_WIDTH/8)
`define BUS_OFFSET_WIDTH            $clog2(`BUS_DATA_WIDTH/8)

// bootrom
`define BOOTROM_SIZE                (8*1024)
`define BOOTROM_ADDR_WIDTH          13
`define BOOTROM_DATA_WIDTH          128

// clint
`define CLINT_ADDR_WIDTH            20
`define CLINT_DATA_WIDTH            `XLEN
`define CLINT_STRB_WIDTH            (`CLINT_DATA_WIDTH/8)

// plic
`define PLIC_ADDR_WIDTH             22
`define PLIC_DATA_WIDTH             32
`define PLIC_STRB_WIDTH             (`PLIC_DATA_WIDTH/8)

// uart
`define UART_ADDR_WIDTH             8
`define UART_DATA_WIDTH             32
`define UART_STRB_WIDTH             (`UART_DATA_WIDTH/8)

// ether
`define ETHER_ADDR_WIDTH            32
`define ETHER_DATA_WIDTH            32
`define ETHER_STRB_WIDTH            (`ETHER_DATA_WIDTH/8)
`define ETHER_MTU                   1514 // 6 (dst) + 6 (src) + 2 (type) + 1500 (data)
`define ETHER_CSR_BASE              'h14000000
`define ETHER_CSR_SIZE              (16*1024)
`define ETHER_RXBUF_BASE            'h18000000
`define ETHER_TXBUF_BASE            'h1c000000


// dram
`define DRAM_ADDR_WIDTH             $clog2(`DRAM_SIZE)
`define DRAM_DATA_WIDTH             128
`define DRAM_STRB_WIDTH             (`DRAM_DATA_WIDTH/8)

// sdcram
`define SDCRAM_BASE                 'ha0000000
`define SDCRAM_SIZE                 (1536*1024*1024) // 1.5 GiB (0xa0000000-0xffffffff)
`define SDCRAM_ADDR_WIDTH           32
`define SDCRAM_DATA_WIDTH           32
`define SDCRAM_STRB_WIDTH           (`SDCRAM_DATA_WIDTH/8)
`define SD_ADDR_WIDTH               41

// instruction type
`define NONE_TYPE                   0
`define R_TYPE                      1
`define I_TYPE                      2
`define S_TYPE                      3
`define B_TYPE                      4
`define U_TYPE                      5
`define J_TYPE                      6
`define INSTR_TYPE_WIDTH            3

// source 1 control
`define SRC1_CTRL_USE_UIMM          0
`define SRC1_CTRL_WIDTH             1

// source 2 control
`define SRC2_CTRL_USE_AUIPC         0
`define SRC2_CTRL_USE_IMM           1
`define SRC2_CTRL_WIDTH             2

// system control
`define SYS_CTRL_ECALL              0
`define SYS_CTRL_EBREAK             1
`define SYS_CTRL_SRET               2
`define SYS_CTRL_MRET               3
`define SYS_CTRL_WFI                4
`define SYS_CTRL_SFENCE_VMA         5
`define SYS_CTRL_WIDTH              6

// csr control
`define CSR_CTRL_IS_CSR             0
`define CSR_CTRL_IS_WRITE           1
`define CSR_CTRL_IS_SET             2
`define CSR_CTRL_IS_CLEAR           3
`define CSR_CTRL_IS_READ            4
`define CSR_CTRL_WIDTH              5

// alu control
`define ALU_CTRL_IS_SIGNED          0
`define ALU_CTRL_IS_NEG             1
`define ALU_CTRL_IS_LESS            2
`define ALU_CTRL_IS_ADD             3
`define ALU_CTRL_IS_SHIFT_LEFT      4
`define ALU_CTRL_IS_SHIFT_RIGHT     5
`define ALU_CTRL_IS_XOR_OR          6
`define ALU_CTRL_IS_OR_AND          7
`define ALU_CTRL_IS_SRC2            8
`define ALU_CTRL_WIDTH              9

// bru control
`define BRU_CTRL_IS_CTRL_TSFR       0
`define BRU_CTRL_IS_SIGNED          1
`define BRU_CTRL_IS_BEQ             2
`define BRU_CTRL_IS_BNE             3
`define BRU_CTRL_IS_BLT             4
`define BRU_CTRL_IS_BGE             5
`define BRU_CTRL_IS_JALR            6
`define BRU_CTRL_IS_JAL_JALR        7
`define BRU_CTRL_WIDTH              8

// lsu control
`define LSU_CTRL_IS_LOAD            0
`define LSU_CTRL_IS_STORE           1
`define LSU_CTRL_IS_LRSC            2
`define LSU_CTRL_IS_AMO             3
`define LSU_CTRL_IS_SIGNED          4
`define LSU_CTRL_IS_BYTE            5
`define LSU_CTRL_IS_HALFWORD        6
`define LSU_CTRL_IS_WORD            7
`define LSU_CTRL_WIDTH              8

// mul control
`define MUL_CTRL_IS_MUL             0
`define MUL_CTRL_IS_SRC1_SIGNED     1
`define MUL_CTRL_IS_SRC2_SIGNED     2
`define MUL_CTRL_IS_HIGH            3
`define MUL_CTRL_WIDTH              4

// div control
`define DIV_CTRL_IS_DIV             0
`define DIV_CTRL_IS_SIGNED          1
`define DIV_CTRL_IS_REM             2
`define DIV_CTRL_WIDTH              3

// amo control
`define AMO_CTRL_IS_ADD             0
`define AMO_CTRL_IS_CLR_SET         1
`define AMO_CTRL_IS_EOR             2
`define AMO_CTRL_IS_SIGNED          3
`define AMO_CTRL_IS_MAX             4
`define AMO_CTRL_IS_MINMAX          5
`define AMO_CTRL_IS_SET_SWAP        6
`define AMO_CTRL_WIDTH              7

// AWATOP encodings
`define AWATOP_NON_ATOMIC           6'b000000
`define AWATOP_ADD                  6'b100000
`define AWATOP_CLR                  6'b100001
`define AWATOP_EOR                  6'b100010
`define AWATOP_SET                  6'b100011
`define AWATOP_SMAX                 6'b100100
`define AWATOP_SMIN                 6'b100101
`define AWATOP_UMAX                 6'b100110
`define AWATOP_UMIN                 6'b100111
`define AWATOP_SWAP                 6'b110000

// pseudo instruction
`define NOP                         32'h00000013 // addi  x0, x0, 0
`define UNIMP                       32'hC0001073 // csrrw x0, cycle, x0

// privilege level
`define PRIV_LVL_M                  2'b11
`define PRIV_LVL_S                  2'b01
`define PRIV_LVL_U                  2'b00

// supervisor status (sstatus) register
`define SSTATUS_MXR_MASK            'h00080000
`define SSTATUS_SUM_MASK            'h00040000
`define SSTATUS_SPP_MASK            'h00000100
`define SSTATUS_SPIE_MASK           'h00000020
`define SSTATUS_SIE_MASK            'h00000002

`define SSTATUS_READ_MASK           (`SSTATUS_MXR_MASK | `SSTATUS_SUM_MASK | `SSTATUS_SPP_MASK | `SSTATUS_SPIE_MASK | `SSTATUS_SIE_MASK)
`define SSTATUS_WRITE_MASK          (`SSTATUS_MXR_MASK | `SSTATUS_SUM_MASK | `SSTATUS_SPP_MASK | `SSTATUS_SPIE_MASK | `SSTATUS_SIE_MASK)

// supervisor address translation and protection (satp) register
`define SATP_MODE                   31
`define SATP_ASID                   30:22
`define SATP_PPN                    21:0

`define SATP_MODE_SV32              1
`define ASIDMAX                     9
`define ASIDLEN                     0

// virtual address
`define VA_VPN_1                    31:22
`define VA_VPN_0                    21:12
`define VA_PGOFF                    11:0

// physical address
`define PA_PPN_1                    33:22
`define PA_PPN_0                    21:12
`define PA_PGOFF                    11:0

// page table entry
`define PTE_PPN_1                   31:20
`define PTE_PPN_0                   19:10
`define PTE_RSW                     9:8
`define PTE_D                       7
`define PTE_A                       6
`define PTE_G                       5
`define PTE_U                       4
`define PTE_X                       3
`define PTE_W                       2
`define PTE_R                       1
`define PTE_V                       0

`define PAGESIZE                    (4*1024)
`define PT_LEVELS                   2 // (XLEN==64) ? 3 : 2
`define PTESIZE                     4 // (XLEN==64) ? 8 : 4

// machine status (mstatus) register
`define MSTATUS_WPRI6               63:43       // write preserved reads ignore
`define MSTATUS_MDT                 42          // machine-mode disable trap
`define MSTATUS_MPELP               41          //
`define MSTATUS_WPRI5               40          // write preserved reads ignore
`define MSTATUS_MPV                 39          //
`define MSTATUS_GVA                 38          //
`define MSTATUS_MBE                 37          //
`define MSTATUS_SBE                 36          //
`define MSTATUS_WPRI4               35:32       // write preserved reads ignore
`define MSTATUS_SD                  31          // signal dirty state
`define MSTATUS_WPRI3               30:25       // write preserved reads ignore
`define MSTATUS_SDT                 24          // supervisor-mode disable trap
`define MSTATUS_SPELP               23          //
`define MSTATUS_TSR                 22          // trap sret
`define MSTATUS_TW                  21          // timeout wait
`define MSTATUS_TVM                 20          // trap virtual memory
`define MSTATUS_MXR                 19          // make executable readable (for load)
`define MSTATUS_SUM                 18          // permit supervisor user memory access (for load/store)
`define MSTATUS_MPRV                17          // modify privilege (for load/store)
`define MSTATUS_XS                  16:15       // extension register
`define MSTATUS_FS                  14:13       // floating point extension register
`define MSTATUS_MPP                 12:11       // machine previous privilege mode
`define MSTATUS_VS                  10:9        // vector extension register
`define MSTATUS_SPP                 8           // supervisor previous privilege mode
`define MSTATUS_MPIE                7           // machine previous interrupts enable
`define MSTATUS_UBE                 6           // endian selection of load/store memory accesses in user mode (0: little endian, 1: big endian)
`define MSTATUS_SPIE                5           // supervisor previous interrupts enable
`define MSTATUS_WPRI2               4           // write preserved reads ignore
`define MSTATUS_MIE                 3           // machine interrupts enable
`define MSTATUS_WPRI1               2           // write preserved reads ignore
`define MSTATUS_SIE                 1           // supervisor interrupts enable
`define MSTATUS_WPRI0               0           // write preserved reads ignore

`define MSTATUSH_MDT_MASK           'h00000400

`define MSTATUS_TSR_MASK            'h00400000
`define MSTATUS_TW_MASK             'h00200000
`define MSTATUS_TVM_MASK            'h00100000
`define MSTATUS_MXR_MASK            'h00080000
`define MSTATUS_SUM_MASK            'h00040000
`define MSTATUS_MPRV_MASK           'h00020000
`define MSTATUS_MPP_MASK            'h00001800
`define MSTATUS_SPP_MASK            'h00000100
`define MSTATUS_MPIE_MASK           'h00000080
`define MSTATUS_SPIE_MASK           'h00000020
`define MSTATUS_MIE_MASK            'h00000008
`define MSTATUS_SIE_MASK            'h00000002

`define MSTATUSH_WRITE_MASK         (`MSTATUSH_MDT_MASK)
`define MSTATUS_WRITE_MASK          (`MSTATUS_TSR_MASK | `MSTATUS_TW_MASK | `MSTATUS_TVM_MASK | `MSTATUS_MXR_MASK | `MSTATUS_SUM_MASK | `MSTATUS_MPRV_MASK | `MSTATUS_MPP_MASK | `MSTATUS_SPP_MASK | `MSTATUS_MPIE_MASK | `MSTATUS_SPIE_MASK | `MSTATUS_MIE_MASK | `MSTATUS_SIE_MASK)

// exceptions
`define CAUSE_DOUBLE_TRAP           16
`define CAUSE_STORE_PAGE_FAULT      15
`define CAUSE_LOAD_PAGE_FAULT       13
`define CAUSE_INSTR_PAGE_FAULT      12
`define CAUSE_MACHINE_ECALL         11
`define CAUSE_SUPERVISOR_ECALL      9
`define CAUSE_USER_ECALL            8
`define CAUSE_ST_ACCESS_FAULT       7
`define CAUSE_ST_ADDR_MISALIGNED    6
`define CAUSE_LD_ACCESS_FAULT       5
`define CAUSE_LD_ADDR_MISALIGNED    4
`define CAUSE_BREAKPOINT            3
`define CAUSE_ILLEGAL_INSTR         2
`define CAUSE_INSTR_ACCESS_FAULT    1
`define CAUSE_INSTR_ADDR_MISALIGNED 0

`define MEDELEG_WRITE_MASK          ((1 << `CAUSE_STORE_PAGE_FAULT) | (1 << `CAUSE_LOAD_PAGE_FAULT) | (1 << `CAUSE_INSTR_PAGE_FAULT) | (1 << `CAUSE_USER_ECALL) | (1 << `CAUSE_ST_ACCESS_FAULT) | (1 << `CAUSE_ST_ADDR_MISALIGNED) | (1 << `CAUSE_LD_ACCESS_FAULT) | (1 << `CAUSE_LD_ADDR_MISALIGNED) | (1 << `CAUSE_BREAKPOINT) | (1 << `CAUSE_ILLEGAL_INSTR) | (1 << `CAUSE_INSTR_ACCESS_FAULT) | (1 << `CAUSE_INSTR_ADDR_MISALIGNED))

// interrupts
`define IRQ_M_EXT                   11
`define IRQ_S_EXT                   9
`define IRQ_M_TIMER                 7
`define IRQ_S_TIMER                 5
`define IRQ_M_SOFT                  3
`define IRQ_S_SOFT                  1

`define CAUSE_M_EXT                 ((1 << (`XLEN-1)) | 11)
`define CAUSE_S_EXT                 ((1 << (`XLEN-1)) | 9)
`define CAUSE_M_TIMER               ((1 << (`XLEN-1)) | 7)
`define CAUSE_S_TIMER               ((1 << (`XLEN-1)) | 5)
`define CAUSE_M_SOFT                ((1 << (`XLEN-1)) | 3)
`define CAUSE_S_SOFT                ((1 << (`XLEN-1)) | 1)

`define MIP_MEIP                    11          // machine external interrupts pending
`define MIP_SEIP                    9           // supervisor external interrupts pending
`define MIP_MTIP                    7           // machine timer interrupts pending
`define MIP_STIP                    5           // supervisor timer interrupts pending
`define MIP_MSIP                    3           // machine software interrupts pending
`define MIP_SSIP                    1           // supervisor software interrupts pending

`define MIP_MEIP_MASK               'h00000800  // machine external interrupts pending
`define MIP_SEIP_MASK               'h00000200  // supervisor external interrupts pending
`define MIP_MTIP_MASK               'h00000080  // machine timer interrupts pending
`define MIP_STIP_MASK               'h00000020  // supervisor timer interrupts pending
`define MIP_MSIP_MASK               'h00000008  // machine software interrupts pending
`define MIP_SSIP_MASK               'h00000002  // supervisor software interrupts pending

`define MIDELEG_WRITE_MASK          (                 `MIP_SEIP_MASK                  | `MIP_STIP_MASK                  | `MIP_SSIP_MASK)
`define MIE_WRITE_MASK              (`MIP_MEIP_MASK | `MIP_SEIP_MASK | `MIP_MTIP_MASK | `MIP_STIP_MASK | `MIP_MSIP_MASK | `MIP_SSIP_MASK)
`define MIP_WRITE_MASK              (                 `MIP_SEIP_MASK                  | `MIP_STIP_MASK                  | `MIP_SSIP_MASK)

`define MIE_MEIE                    11          // machine external interrupts enable
`define MIE_SEIE                    9           // supervisor external interrupts enable
`define MIE_MTIE                    7           // machine timer interrupts enable
`define MIE_STIE                    5           // supervisor timer interrupts enable
`define MIE_MSIE                    3           // machine software interrupts enable
`define MIE_SSIE                    1           // supervisor software interrupts enable

`define MIE_MEIE_MASK               'h00000800  // machine external interrupts enable
`define MIE_SEIE_MASK               'h00000200  // supervisor external interrupts enable
`define MIE_MTIE_MASK               'h00000080  // machine timer interrupts enable
`define MIE_STIE_MASK               'h00000020  // supervisor timer interrupts enable
`define MIE_MSIE_MASK               'h00000008  // machine software interrupts enable
`define MIE_SSIE_MASK               'h00000002  // supervisor software interrupts enable
/******************************************************************************************/

`endif // RVCPU_H_
