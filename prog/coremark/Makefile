# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025 Archlab, Science Tokyo

#===============================================================================
# Config
#-------------------------------------------------------------------------------
XLEN                := 32
#XLEN                := 64
#USE_MULDIV          := 1
#USE_ATOMIC          := 1
#USE_COMPRESSED      := 1

ITERATIONS          := 10
TARGET              := coremark

#===============================================================================
# Makefile
#-------------------------------------------------------------------------------
srcs-to-objs         = \
    $(patsubst %.s,%.o, $(filter %.s,$1)) \
    $(patsubst %.S,%.o, $(filter %.S,$1)) \
    $(patsubst %.c,%.o, $(filter %.c,$1))

#===============================================================================
# Sources
#-------------------------------------------------------------------------------
SRC_DIR             := coremark
PORT_DIR            := riscv
INC_DIR             += $(PORT_DIR) $(SRC_DIR)

SRCS                += $(wildcard $(PORT_DIR)/*.s)
SRCS                += $(wildcard $(PORT_DIR)/*.S)
SRCS                += $(wildcard $(PORT_DIR)/*.c)
SRCS                += $(wildcard $(SRC_DIR)/*.c)
OBJS                := $(call srcs-to-objs,$(SRCS))

#===============================================================================
# RISC-V
#-------------------------------------------------------------------------------
### Architecture
RISCV_ARCH          := rv$(XLEN)i
ifdef USE_MULDIV
RISCV_ARCH          := $(addsuffix m,$(RISCV_ARCH))
endif
ifdef USE_ATOMIC
RISCV_ARCH          := $(addsuffix a,$(RISCV_ARCH))
endif
ifdef USE_COMPRESSED
RISCV_ARCH          := $(addsuffix c,$(RISCV_ARCH))
endif

### ABI
RISCV_ABI           := $(if $(filter $(XLEN),64),lp64,ilp32)

-include ../../config.mk

RISCV_PREFIX        := $(RISCV_PATH)riscv$(XLEN)-unknown-elf-
RISCV_GCC           := $(RISCV_PREFIX)gcc
RISCV_OBJDUMP       := $(RISCV_PREFIX)objdump -d
RISCV_OBJCOPY       := $(RISCV_PREFIX)objcopy

RISCV_CFLAGS        += -O2
RISCV_CFLAGS        += -march=$(RISCV_ARCH)
RISCV_CFLAGS        += -mabi=$(RISCV_ABI)
RISCV_CFLAGS        += -nostartfiles
RISCV_CFLAGS        += -DXLEN=$(XLEN)
RISCV_CFLAGS        += -DITERATIONS=$(ITERATIONS)
RISCV_CFLAGS        += $(addprefix -I,$(INC_DIR))

RISCV_LDFLAGS       += -T$(PORT_DIR)/link.ld

#===============================================================================
# Build rules
#-------------------------------------------------------------------------------
.PHONY: default clean distclean
default: $(RISCV_ARCH) $(addprefix $(RISCV_ARCH)/$(TARGET), .elf .bin .32.hex .64.hex .128.hex .dump)

$(RISCV_ARCH):
	mkdir -p $@

%.dump: %.elf
	$(RISCV_OBJDUMP) $< > $@

%.32.hex: %.bin
	od -v -An -tx4 -w4 $< | sed 's/^ *\([0-9a-f]\+\)/\1/' > $@

%.64.hex: %.bin
	od -v -An -tx8 -w8 $< | sed 's/^ *\([0-9a-f]\+\)/\1/' > $@

%.128.hex: %.64.hex
	awk '{if(NR%2){buf=$$0}else{print $$0 buf; buf=""}}' $< > $@

%.bin: %.elf
	$(RISCV_OBJCOPY) -O binary $< $@.tmp
	dd if=$@.tmp of=$@ bs=32KiB conv=sync
	rm -f $@.tmp

%.elf: $(OBJS)
	$(RISCV_GCC) $(RISCV_CFLAGS) $(RISCV_LDFLAGS) $^ -o $@

%.o: %.c
	$(RISCV_GCC) -c $(RISCV_CFLAGS) -DFLAGS_STR=\""$(RISCV_CFLAGS)"\" $< -o $@

%.o: %.S
	$(RISCV_GCC) -c $(RISCV_CFLAGS) $< -o $@

%.o: %.s
	$(RISCV_GCC) -c $(RISCV_CFLAGS) $< -o $@

clean:
	rm -f *.elf *.bin *.hex *.dump

distclean: clean
	rm -rf rv32*/ rv64*/
