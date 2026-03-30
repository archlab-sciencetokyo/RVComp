# SPDX-License-Identifier: MIT
#
# Copyright (c) 2026 Archlab, Science Tokyo

# User Settings
RISCV_PATH          :=

srcs-to-objs         = $(patsubst %.S,%.o,$(filter %.S,$1)) \
                       $(patsubst %.c,%.o,$(filter %.c,$1))
src_dir             := src
srcs                := $(wildcard $(addprefix $(src_dir)/,*.S *.c))
objs                := $(call srcs-to-objs,$(srcs))

bootloader_c        := $(src_dir)/bootloader.c

dtb                 := rvcomp.dtb

linker_ld           := $(src_dir)/linker.ld

bootrom             := bootrom
bootrom_elf         := $(bootrom).elf
bootrom_bin         := $(bootrom).bin
bootrom_32_hex      := $(bootrom).32.hex
bootrom_64_hex      := $(bootrom).64.hex
bootrom_128_hex     := $(bootrom).128.hex
bootrom_mem         := $(bootrom).mem
bootrom_dump        := $(bootrom).dump

#===============================================================================
# Build rules
#-------------------------------------------------------------------------------
XLEN                := 32
RISCV_ARCH          := rv$(XLEN)i_zicsr_zifencei_zicntr
RISCV_ABI           := $(if $(filter 64,$(XLEN)),lp64,ilp32)

-include ../config.mk

RISCV_PREFIX        ?= $(RISCV_PATH)riscv$(XLEN)-unknown-elf-
RISCV_GCC           := $(RISCV_PREFIX)gcc
RISCV_OBJCOPY       := $(RISCV_PREFIX)objcopy
RISCV_OBJDUMP       := $(RISCV_PREFIX)objdump

RISCV_CFLAGS        += -Os
RISCV_CFLAGS        += -march=$(RISCV_ARCH)
RISCV_CFLAGS        += -mabi=$(RISCV_ABI)
RISCV_CFLAGS        += -nostartfiles

ifeq (1,$(NO_UART_BOOT))
RISCV_CFLAGS        += -DNO_UART_BOOT
RISCV_CFLAGS        += -DBIN_SIZE=0
else
RISCV_CFLAGS        += $(if $(BIN_SIZE),-DBIN_SIZE="($(BIN_SIZE))",$(error Usage: make BIN_SIZE=<bin_size>))
endif

RISCV_LDFLAGS       += -T$(linker_ld)
RISCV_LDFLAGS       += -Wl,-no-gc-sections

.PHONY: all
all: $(bootrom_elf) $(bootrom_bin) $(bootrom_32_hex) $(bootrom_64_hex) $(bootrom_128_hex) $(bootrom_mem) $(bootrom_dump)

%.dump: %.elf
	$(RISCV_OBJDUMP) -D $< > $@

%.mem: %.128.hex
	cp $< $@

%.128.hex: %.64.hex
	awk '{if(NR%2){buf=$$0}else{print $$0 buf; buf=""}}' $< > $@

%.64.hex: %.bin
	hexdump -v -e '1/8 "%016x\n"' $< > $@

%.32.hex: %.bin
	hexdump -v -e '1/4 "%08x\n"' $< > $@

%.bin: %.elf
	$(RISCV_OBJCOPY) -O binary $< $@.tmp
	dd if=$@.tmp of=$@ bs=8192 count=1 conv=sync 2> /dev/null
	rm -f $@.tmp

%.elf: $(dtb) $(objs) $(linker_ld)
	$(RISCV_GCC) $(RISCV_CFLAGS) $(RISCV_LDFLAGS) -o $@ $(objs)

.PHONY: $(bootloader_c)
%.o: %.c
	$(RISCV_GCC) $(RISCV_CFLAGS) -c -o $@ $<

%.o: %.S
	$(RISCV_GCC) $(RISCV_CFLAGS) -c -o $@ $<

%.dtb: %.dts
	dtc -O dtb -o $@ $<

clean:
	rm -f *.elf *.bin *.hex *.mem *.dump *.dtb
