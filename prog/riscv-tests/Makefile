# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025 Archlab, Science Tokyo

#===============================================================================
# Makefile for riscv-tests/isa
#-------------------------------------------------------------------------------

# User Settings
RISCV_PATH          := 

XLEN                ?= 32

BLOCK_SIZE          := 64KiB

SRC_DIR             := riscv-tests/isa

include $(SRC_DIR)/rv32ui/Makefrag
include $(SRC_DIR)/rv32uc/Makefrag
include $(SRC_DIR)/rv32um/Makefrag
include $(SRC_DIR)/rv32ua/Makefrag
include $(SRC_DIR)/rv32uf/Makefrag
include $(SRC_DIR)/rv32ud/Makefrag
include $(SRC_DIR)/rv32uzfh/Makefrag
include $(SRC_DIR)/rv32si/Makefrag
include $(SRC_DIR)/rv32mi/Makefrag
ifeq ($(XLEN),64)
include $(SRC_DIR)/rv64ui/Makefrag
include $(SRC_DIR)/rv64uc/Makefrag
include $(SRC_DIR)/rv64um/Makefrag
include $(SRC_DIR)/rv64ua/Makefrag
include $(SRC_DIR)/rv64uf/Makefrag
include $(SRC_DIR)/rv64ud/Makefrag
include $(SRC_DIR)/rv64uzfh/Makefrag
include $(SRC_DIR)/rv64si/Makefrag
include $(SRC_DIR)/rv64ssvnapot/Makefrag
include $(SRC_DIR)/rv64mi/Makefrag
include $(SRC_DIR)/rv64mzicbo/Makefrag
endif

# TVM: Target Virtual Machines
TVMS                := rv32ui rv32um rv32ua rv32si rv32mi

default: $(TVMS)

# $(eval $(call tvm_env_template,tvm,env))
define tvm_env_template
$1_$2_tests         := $$(addprefix $1-$2-,$$($1_sc_tests))
endef

$(foreach tvm,$(TVMS),$(foreach env,p,$(eval $(call tvm_env_template,$(tvm),$(env)))))

#-------------------------------------------------------------------------------
# Build rules
#-------------------------------------------------------------------------------
-include ../../config.mk

RISCV_PREFIX        ?= $(RISCV_PATH)riscv$(XLEN)-unknown-elf-
RISCV_GCC           ?= $(RISCV_PREFIX)gcc
RISCV_GCC_OPTS      ?= -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles
RISCV_OBJDUMP       ?= $(RISCV_PREFIX)objdump --disassemble-all --disassemble-zeroes --section=.text --section=.text.startup --section=.text.init --section=.data
RISCV_OBJCOPY       ?= $(RISCV_PREFIX)objcopy

#-------------------------------------------------------------------------------
# Build assembly tests
#-------------------------------------------------------------------------------
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
	dd if=$@.tmp of=$@ bs=$(BLOCK_SIZE) conv=sync
	rm -f $@.tmp

# $(eval $(call compile_template,TVM,-march=ARCH -mabi=ABI))
define compile_template
$1_tests += $$(addprefix $1/,$$($1_p_tests))
$1_tests += $$(addprefix $1/,$$($1_pm_tests))
$1_tests += $$(addprefix $1/,$$($1_pt_tests))
$1_tests += $$(addprefix $1/,$$($1_v_tests))

$1_p_tests_elf = $$(addprefix $1/,$$(addsuffix .elf,$$($1_p_tests)))
$1_pm_tests_elf = $$(addprefix $1/,$$(addsuffix .elf,$$($1_pm_tests)))
$1_pt_tests_elf = $$(addprefix $1/,$$(addsuffix .elf,$$($1_pt_tests)))
$1_v_tests_elf = $$(addprefix $1/,$$(addsuffix .elf,$$($1_v_tests)))

$$($1_p_tests_elf): $1/$1-p-%.elf: $(SRC_DIR)/$1/%.S
	$$(RISCV_GCC) $2 $$(RISCV_GCC_OPTS) -O2 -Ienv -Ienv/p -I$$(SRC_DIR)/macros/scalar -Tenv/link.ld $$< -o $$@

$$($1_pm_tests_elf): $1/$1-pm-%.elf: $(SRC_DIR)/$1/%.S
	$$(RISCV_GCC) $2 $$(RISCV_GCC_OPTS) -O2 -Ienv -Ienv/pm -I$$(SRC_DIR)/macros/scalar -Tenv/link.ld $$< -o $$@

$$($1_pt_tests_elf): $1/$1-pt-%.elf: $(SRC_DIR)/$1/%.S
	$$(RISCV_GCC) $2 $$(RISCV_GCC_OPTS) -O2 -Ienv -Ienv/pt -I$$(SRC_DIR)/macros/scalar -Tenv/link.ld $$< -o $$@

$$($1_v_tests_elf): $1/$1-v-%.elf: $(SRC_DIR)/$1/%.S
	$$(RISCV_GCC) $2 $$(RISCV_GCC_OPTS) -DENTROPY=0x$$(shell echo \$$@ | md5sum | cut -c 1-7) -std=gnu99 -O2 -Ienv -Ienv/v -I$$(SRC_DIR)/macros/scalar -Tenv/link.ld env/v/entry.S env/v/*.c $$< -o $$@

$1_tests_elf     = $$(addsuffix .elf, $$($1_tests))
$1_tests_bin     = $$(addsuffix .bin, $$($1_tests))
$1_tests_32_hex  = $$(addsuffix .32.hex, $$($1_tests))
$1_tests_64_hex  = $$(addsuffix .64.hex, $$($1_tests))
$1_tests_128_hex = $$(addsuffix .128.hex, $$($1_tests))
$1_tests_dump    = $$(addsuffix .dump, $$($1_tests))

.PHONY: $1
$1: mkdir_$1 $$($1_tests_elf) $$($1_tests_bin) $$($1_tests_32_hex) $$($1_tests_64_hex) $$($1_tests_128_hex) $$($1_tests_dump)

.PHONY: mkdir_$1
mkdir_$1:
	mkdir -p $1

COMPILER_SUPPORTS_$1 := $$(shell $$(RISCV_GCC) $2 -c -x c /dev/null -o /dev/null 2> /dev/null; echo $$$$?)

ifeq ($$(COMPILER_SUPPORTS_$1),0)
tests += $$($1_tests)
endif
endef # compile_template

$(eval $(call compile_template,rv32ui,-march=rv32g -mabi=ilp32))
$(eval $(call compile_template,rv32uc,-march=rv32g -mabi=ilp32))
$(eval $(call compile_template,rv32um,-march=rv32g -mabi=ilp32))
$(eval $(call compile_template,rv32ua,-march=rv32g -mabi=ilp32))
$(eval $(call compile_template,rv32uf,-march=rv32g -mabi=ilp32))
$(eval $(call compile_template,rv32ud,-march=rv32g -mabi=ilp32))
$(eval $(call compile_template,rv32uzfh,-march=rv32g_zfh -mabi=ilp32))
$(eval $(call compile_template,rv32si,-march=rv32g -mabi=ilp32))
$(eval $(call compile_template,rv32mi,-march=rv32g -mabi=ilp32))
ifeq ($(XLEN),64)
$(eval $(call compile_template,rv64ui,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,rv64uc,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,rv64um,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,rv64ua,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,rv64uf,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,rv64ud,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,rv64uzfh,-march=rv64g_zfh -mabi=lp64))
$(eval $(call compile_template,rv64mzicbo,-march=rv64g_zicboz -mabi=lp64))
$(eval $(call compile_template,rv64si,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,rv64ssvnapot,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,rv64mi,-march=rv64g -mabi=lp64))
endif

.PHONY: clean distclean
clean:
	rm -f *.elf *.bin *.hex *.dump

distclean:
	rm -rf rv32*/ rv64*/
