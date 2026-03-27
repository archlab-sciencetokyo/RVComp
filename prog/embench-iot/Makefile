# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025 Archlab, Science Tokyo

#===============================================================================
# Config
#-------------------------------------------------------------------------------

# User Settings
RISCV_PATH          := 

XLEN                := 32
#XLEN                := 64
#USE_MULDIV          := 1
#USE_ATOMIC          := 1
#USE_COMPRESSED      := 1

EMBENCH_DIR         := embench-iot
BUILD_DIR           := $(CURDIR)/bd
LOG_DIR             := $(CURDIR)/log
CONFIG_DIR          := $(EMBENCH_DIR)/config
ARCH                := riscv
CHIP                := generic
BOARD               := rvcom

#===============================================================================
# Sources
#-------------------------------------------------------------------------------
embench             := \
	aha-mont64 crc32 cubic edn huffbench matmult-int md5sum minver nbody \
	nettle-aes nettle-sha256 nsichneu picojpeg primecount qrduino \
	sglib-combined slre st statemate tarfind ud wikisort

embench_base_dir    := $(addprefix $(BUILD_DIR)/src/, $(embench))
embench_base        := $(join $(addsuffix /,$(embench_base_dir)), $(embench))
embench_elf         := $(addsuffix .elf,$(embench_base))
embench_bin         := $(addsuffix .bin,$(embench_base))
embench_32_hex      := $(addsuffix .32.hex,$(embench_base))
embench_64_hex      := $(addsuffix .64.hex,$(embench_base))
embench_128_hex     := $(addsuffix .128.hex,$(embench_base))
embench_dump        := $(addsuffix .dump,$(embench_base))

#===============================================================================
# RISC-V
#-------------------------------------------------------------------------------
### Architecture
RISCV_ARCH          := rv$(XLEN)i
ifdef USE_MULDIV
RISCV_ARCH          := $(RISCV_ARCH)m
endif
ifdef USE_ATOMIC
RISCV_ARCH          := $(RISCV_ARCH)a
endif
ifdef USE_COMPRESSED
RISCV_ARCH          := $(RISCV_ARCH)c
endif

### ABI
RISCV_ABI           := $(if $(filter $(XLEN),64),lp64,ilp32)

-include ../../config.mk

RISCV_PREFIX        := $(RISCV_PATH)riscv$(XLEN)-unknown-elf-
RISCV_GCC           := $(RISCV_PREFIX)gcc
RISCV_OBJDUMP       := $(RISCV_PREFIX)objdump -d
RISCV_OBJCOPY       := $(RISCV_PREFIX)objcopy

RISCV_CFLAGS        += -O2 -std=gnu11 # for compile gcc > 15 cause bool error
RISCV_CFLAGS        += -march=$(RISCV_ARCH)
RISCV_CFLAGS        += -mabi=$(RISCV_ABI)
RISCV_CFLAGS        += -nostartfiles

RISCV_LDFLAGS       += -T$(CURDIR)/embench-iot/config/$(ARCH)/boards/$(BOARD)/link.ld

#===============================================================================
# Build rules
#-------------------------------------------------------------------------------
.PHONY: default all build clean distclean install
default: clean all install

all: build $(embench_elf) $(embench_bin) $(embench_32_hex) $(embench_64_hex) $(embench_128_hex) $(embench_dump)

build: $(CONFIG_DIR)/$(ARCH)
	$(EMBENCH_DIR)/build_all.py \
	--arch $(ARCH) \
	--chip $(CHIP) \
	--board $(BOARD) \
	--cc $(RISCV_GCC) \
	--cflags="$(RISCV_CFLAGS) -c" \
	--ldflags="$(RISCV_CFLAGS) $(RISCV_LDFLAGS)" \
	--user-libs="-lm" \
	--builddir $(BUILD_DIR) \
	--logdir $(LOG_DIR)
	@rm -rf $(CONFIG_DIR)/$(ARCH)

$(CONFIG_DIR)/$(ARCH):
	cp -r $(ARCH) $(EMBENCH_DIR)/config

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
	dd if=$@.tmp of=$@ conv=sync bs=128KiB
	rm -f $@.tmp

$(embench_elf): %.elf: %
	mv $< $@

clean:
	rm -rf $(BUILD_DIR)
	rm -rf $(LOG_DIR)
	rm -rf $(CONFIG_DIR)/$(ARCH)
	rm -rf $(shell find . -name __pycache__)

distclean: clean
	rm -rf rv32*/ rv64*/

INSTALL_DIR         := $(RISCV_ARCH)
install: $(embench_elf) $(embench_bin) $(embench_32_hex) $(embench_64_hex) $(embench_128_hex) $(embench_dump)
	install -p -m 644 -D -t $(INSTALL_DIR) $^
