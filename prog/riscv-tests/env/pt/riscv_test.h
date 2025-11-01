// See LICENSE for license details.
//
// Modified by Archlab, Science Tokyo (2025) - modified for RVComp sim

#ifndef _ENV_PHYSICAL_SINGLE_CORE_TIMER_H
#define _ENV_PHYSICAL_SINGLE_CORE_TIMER_H

#include "../p/riscv_test.h"

#define CLINT_MTIMECMP_OFFSET   0x4000
#define CLINT_MTIME_OFFSET      0xbff8

#define MTIMECMP_ADDR           (CLINT_BASE+CLINT_MTIMECMP_OFFSET)
#define MTIME_ADDR              (CLINT_BASE+CLINT_MTIME_OFFSET)

#if __riscv_xlen == 32
# define REGWIDTH 4
# define SREG sw
# define LREG lw
# define CLEAR_MSTATUS_MDT addi s1, s1, -REGWIDTH; SREG s0, 0(s1); li s0, MSTATUSH_MDT; csrc mstatush, s0; LREG s0, 0(s1); addi s1, s1, REGWIDTH;
#elif __riscv_xlen == 64
# define REGWIDTH 8
# define SREG sd
# define LREG ld
# define CLEAR_MSTATUS_MDT addi s1, s1, -REGWIDTH; SREG s0, 0(s1); li s0, MSTATUS_MDT; csrc mstatus, s0; LREG s0, 0(s1); addi s1, s1, REGWIDTH;
#else
# define REGWIDTH 16
# define SREG sq
# define LREG lq
# define CLEAR_MSTATUS_MDT addi s1, s1, -REGWIDTH; SREG s0, 0(s1); li s0, MSTATUS_MDT; csrc mstatus, s0; LREG s0, 0(s1); addi s1, s1, REGWIDTH;
#endif

#define TIMER_INTERVAL 2

#undef EXTRA_INIT_TIMER
//#define EXTRA_INIT_TIMER                                                \
        li a0, MIP_MTIP;                                                \
        csrs mie, a0;                                                   \
        csrr a0, mtime;                                                 \
        addi a0, a0, TIMER_INTERVAL;                                    \
        csrw mtimecmp, a0;                                              \

#define EXTRA_INIT_TIMER                                                \
        li a0, MIP_MTIP;                                                \
        csrs mie, a0;                                                   \
        li t0, MTIME_ADDR;                                              \
        LREG a0, 0(t0);                                                 \
        addi a0, a0, TIMER_INTERVAL;                                    \
        li t0, MTIMECMP_ADDR;                                           \
        SREG a0, 0(t0);                                                 \
        CLEAR_MSTATUS_MDT;                                              \
        csrwi mstatus, MSTATUS_MIE;

#if SSTATUS_XS != 0x18000
# error
#endif
#define XS_SHIFT 15

#undef INTERRUPT_HANDLER
//#define INTERRUPT_HANDLER                                               \
        slli t5, t5, 1;                                                 \
        srli t5, t5, 1;                                                 \
        add t5, t5, -IRQ_M_TIMER;                                       \
        bnez t5, other_exception; /* other interrupts shouldn't happen */\
        csrr t5, mtime;                                                 \
        addi t5, t5, TIMER_INTERVAL;                                    \
        csrw mtimecmp, t5;                                              \
        mret;                                                           \

#define INTERRUPT_HANDLER                                               \
        addi s1, s1, -REGWIDTH;                                         \
        SREG s0, 0(s1);                                                 \
        slli t5, t5, 1;                                                 \
        srli t5, t5, 1;                                                 \
        add t5, t5, -IRQ_M_TIMER;                                       \
        bnez t5, other_exception; /* other interrupts shouldn't happen */\
        li s0, MTIME_ADDR;                                              \
        LREG t5, 0(s0);                                                 \
        addi t5, t5, TIMER_INTERVAL;                                    \
        li s0, MTIMECMP_ADDR;                                           \
        SREG t5, 0(s0);                                                 \
        CLEAR_MSTATUS_MDT;                                              \
        csrwi mstatus, MSTATUS_MIE;                                     \
        LREG s0, 0(s1);                                                 \
        addi s1, s1, REGWIDTH;                                          \
        mret;

//-----------------------------------------------------------------------
// Data Section Macro
//-----------------------------------------------------------------------

#undef EXTRA_DATA
#define EXTRA_DATA                                                      \
        .align 3;                                                       \
regspill:                                                               \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
        .dword 0xdeadbeefcafebabe;                                      \
evac:                                                                   \
        .skip 32768;                                                    \

#endif
