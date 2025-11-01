# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025 Archlab, Science Tokyo

#===============================================================================
# Sources
#-------------------------------------------------------------------------------
srcs-to-objs         = $(patsubst %.s,%.o,$(filter %.s,$1)) \
                       $(patsubst %.S,%.o,$(filter %.S,$1)) \
                       $(patsubst %.c,%.o,$(filter %.c,$1))
srcs-to-deps         = $(patsubst %.s,%.d,$(filter %.s,$1)) \
                       $(patsubst %.S,%.d,$(filter %.S,$1)) \
                       $(patsubst %.c,%.d,$(filter %.c,$1))

srcs                := $(wildcard *.s *.S *.c)
objs                := $(call srcs-to-objs,$(srcs))
deps                := $(call srcs-to-deps,$(srcs))

inc_dir             += .
build_dir           := build
target              := test

#===============================================================================
# RISC-V
#-------------------------------------------------------------------------------
XLEN                ?= 32
RISCV_ARCH          ?= rv$(XLEN)i
RISCV_ABI           ?= ilp32

-include ../../config.mk

RISCV_PREFIX        ?= $(RISCV_PATH)riscv$(XLEN)-unknown-elf-
RISCV_GCC           := $(RISCV_PREFIX)gcc
RISCV_CFLAGS        += -Os -march=$(RISCV_ARCH) -mabi=$(RISCV_ABI) -nostartfiles
RISCV_CFLAGS        += -MMD
RISCV_CFLAGS        += $(addprefix -I,$(inc_dir))
RISCV_LDFLAGS       += -Tlink.ld
RISCV_OBJCOPY       := $(RISCV_PREFIX)objcopy
RISCV_OBJDUMP       := $(RISCV_PREFIX)objdump

#===============================================================================
# Build rules
#-------------------------------------------------------------------------------
.PHONY: all clean
all: $(build_dir) $(addprefix $(build_dir)/$(target),.elf .bin .32.hex .64.hex .128.hex .dump)

%.dump: %.elf
	$(RISCV_OBJDUMP) -D $< > $@

%.32.hex: %.bin
	od -v -An -tx4 -w4 $< | sed 's/^ *\([0-9a-f]\+\)/\1/' > $@

%.64.hex: %.bin
	od -v -An -tx8 -w8 $< | sed 's/^ *\([0-9a-f]\+\)/\1/' > $@

%.128.hex: %.64.hex
	awk '{if(NR%2){buf=$$0}else{print $$0 buf; buf=""}}' $< > $@

%.bin: %.elf
	$(RISCV_OBJCOPY) -O binary $< $@.tmp
	dd if=$@.tmp of=$@ conv=sync bs=16KiB
	rm -f $@.tmp

%.elf: $(objs)
	$(RISCV_GCC) $(RISCV_CFLAGS) $(RISCV_LDFLAGS) -o $@ $^

%.o: %.c
	$(RISCV_GCC) $(RISCV_CFLAGS) -c -o $@ $<

%.o: %.S
	$(RISCV_GCC) $(RISCV_CFLAGS) -c -o $@ $<

%.o: %.s
	$(RISCV_GCC) $(RISCV_CFLAGS) -c -o $@ $<

-include $(deps)

$(build_dir):
	@mkdir -p $@

clean:
	-rm -f $(shell find .  \
		    -name '*.d'    \
		-or -name '*.o'    \
		-or -name '*.elf'  \
		-or -name '*.bin'  \
		-or -name '*.hex'  \
		-or -name '*.dump' \
	)
	-rm -rf $(build_dir)
