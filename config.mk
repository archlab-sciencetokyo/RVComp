# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025 Archlab, Science Tokyo

### config
DISPLAY_CYCLES      := 10000000
ENABLE_DEBUG_LOG    := 0
NO_UART_BOOT        := 1

# DIFF_SPIKE_TRACE    := 1
# SC_TRACE            := 1
# TRACE_RF_FILE       := trace_rf_after.log
# TRACE_FST_FILE      := dump.fst

NEXYS4DDR        := 1
ARTY_A7          := 0
BAUD_RATE        := 2000000

### verilator
verilator           := verilator

### OpenSBI/Linux/Buildroot
fw_payload_dir      := $(shell pwd)/image
linux_image         := $(shell pwd)/image/fw_payload.bin
# bootrom: BIN_SIZE=$(shell stat -c %s $(linux_image))

### RISCV toolchain
RISCV_PATH          := 

### vivado
vivado              := vivado
board_data_path     := $(shell pwd)/tools/XilinxBoardStore

### Remote Load Settings (If you want to use it, uncomment below and set the IP address and serial number)
ip_address          :=
ifeq (1, $(NEXYS4DDR))
	serial_number       :=  # nexys4ddr
	COM_PORT            := /dev/ttyUSB1
else ifeq (1, $(ARTY_A7))
	serial_number       :=  # arty_a7
	COM_PORT            := /dev/ttyUSB2
endif
