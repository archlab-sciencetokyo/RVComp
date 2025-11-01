# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025 Archlab, Science Tokyo

#===============================================================================
# Config
#-------------------------------------------------------------------------------

# User Setting Paths
# For Simulation

# For FPGA
vivado              := vivado                 # vivado path
board_data_path     :=                        # board data path
serial_number       :=                        # serial number
ip_address          :=                        # ip address
BAUD_RATE		    := 32000000               # baud rate for pyserial
COM_PORT		    := /dev/ttyUSB1           # serial port for pyserial


DISPLAY_CYCLES      := 100000000 # display . every n cycles
ENABLE_DEBUG_LOG    := 0 # 1: enable debug log
PREFIX			    := 
NO_UART_BOOT        := 1 # 1: no uart boot, 0: uart boot　(uart boot needs a lot of time)

#TRACE_VCD_FILE      := dump.vcd
#TRACE_FST_FILE      := dump.fst

#SIG_FILE            := rvcom.signature

#COMMIT_LOG_FILE     := commit.log

DIFF_SPIKE_TRACE    := 0 # trace and diff with spike
RVCOM_TRACE         := 0 # trace only rvcom

#TRACE_RF_FILE       := trace_rf.log
#TRACE_RF_BEGIN      := 0
#TRACE_RF_END        := -1

#TRACE_DMEM_FILE     := trace_dmem.log

### application program config
XLEN                := 32

RVM                 := 1
RVA                 := 1
RVS                 := 1

### riscv-tests config
TGT_ENV             := p
# TGT_ENV             := pm
# TGT_ENV             := pt
# TGT_ENV             := v

#-------------------------------------------------------------------------------
log_dir             := log
diff_dir            := $(log_dir)/diff

spike               := spike

#-------------------------------------------------------------------------------
RISCV_ARCH          := rv$(XLEN)i
ifeq (1,$(RVM))
RISCV_ARCH          := $(RISCV_ARCH)m
endif
ifeq (1,$(RVA))
RISCV_ARCH          := $(RISCV_ARCH)a
endif
RISCV_ARCH          := $(RISCV_ARCH)_zicsr_zifencei_zicntr

RISCV_ABI           := $(if $(filter $(XLEN),64),lp64,ilp32)

#===============================================================================
# Sources
#-------------------------------------------------------------------------------
bootrom_dir         := bootrom
bootrom_v           := $(bootrom_dir)/bootrom.v

src_dir             := src
srcs                += $(bootrom_v)
srcs                += $(wildcard $(src_dir)/*.v)
srcs                += $(wildcard $(src_dir)/soc/*.v)
srcs                += $(wildcard $(src_dir)/cpu/*.v)
srcs                += $(wildcard $(src_dir)/mmu/*.v)
srcs                += $(wildcard $(src_dir)/cache/*.v)
srcs                += $(wildcard $(src_dir)/clint/*.v)
srcs                += $(wildcard $(src_dir)/plic/*.v)
srcs                += $(wildcard $(src_dir)/uart/*.v)
srcs                += $(wildcard $(src_dir)/dram/*.v)
inc_dir             += $(src_dir)
configs             := $(wildcard $(src_dir)/*.vh)

test_src_dir        := test
test_srcs           += $(wildcard $(test_src_dir)/*.sv)

### program root dir
prog_dir            := prog
riscv-tests_dir     := $(prog_dir)/riscv-tests
coremark_dir        := $(prog_dir)/coremark
embench_dir         := $(prog_dir)/embench-iot
rvtest_dir          := $(prog_dir)/rvtest

### linux
fw_jump_dir         :=
kernel_dir          :=
initrd_dir          :=
fw_payload_dir      :=

kernel_128_hex      :=
initrd_128_hex      :=

kernel_base         :=
initrd_base         :=
linux_image         :=

### Vivado
NEXYS4DDR	    	:=
ARTY_A7	        	:= 
rvcomp_path 	    := $(shell pwd)
project_path        := $(rvcomp_path)/vivado
vivado_local_tcl    := $(rvcomp_path)/fpga/Xilinx/load.tcl
vivado_remote_tcl   := $(rvcomp_path)/fpga/Xilinx/load_remote.tcl
vivado_build_tcl    := $(rvcomp_path)/fpga/Xilinx/build.tcl
vivado_rebuild_tcl  ?= $(rvcomp_path)/fpga/Xilinx/rebuild.tcl
board               :=                        # board name
constr_path         :=                        # constraint path
mig_xml_path        :=                        # mig xml path
project_name 	    := project                # project name
board_part          :=                        # board part
device              :=                        # device name

# pyserial settings
pyserial_path	      := $(rvcomp_path)/tools/
pyserial_project_name := term

-include config.mk

ifeq (1, $(NEXYS4DDR))
	board               := digilentinc.com:nexys4_ddr:part0:1.1
	constr_path         := $(shell pwd)/constr/Nexys-A7-100T-Master.xdc
	mig_xml_path	    := $(shell pwd)/fpga/Xilinx/nexys4ddr/mig.prj
	project_name        := nexys4ddr
	board_part          := xc7a100tcsg324-1
	device              := xc7a100t_0
else ifeq (1, $(ARTY_A7))
	board               := digilentinc.com:arty-a7-35:part0:1.1
	constr_path         := $(shell pwd)/constr/Arty-A7-35T-Master.xdc
	mig_xml_path	    := $(shell pwd)/fpga/Xilinx/arty_a7/mig.prj
	project_name        := arty_a7
	board_part          := xc7a35ticsg324-1L
	device              := xc7a35t_0
	serial_number       := 210319B268BEA  # arty_a7
endif

pyserial_flags        := --linux-boot --linux-file-path $(linux_image)

RVTEST_MODE         ?= 0
ifeq (1,$(DIFF_SPIKE_TRACE))
DISPLAY_CYCLES      := 0
ENABLE_DEBUG_LOG    := 0
endif
ifeq (1,$(RVCOM_TRACE))
DISPLAY_CYCLES      := 0
ENABLE_DEBUG_LOG    := 0
endif

#===============================================================================
# Verilator
#-------------------------------------------------------------------------------
### use Verilator version >= v5.002
verilator           ?= verilator

topmodule           := top
topname             := rvcom

### See verilator Arguments (https://veripool.org/guide/latest/exe_verilator.html)

### --binary: Alias for --main --exe --build --timing
verilator_flags     += --binary
verilator_flags     += --top-module $(topmodule)
verilator_flags     += --prefix $(topname)
verilator_flags     += --assert
verilator_flags     += --assert-case
verilator_flags     += --x-assign unique

verilator_flags     += $(if $(inc_dir),$(addprefix -I,$(inc_dir)))

verilator_flags     += -Wno-WIDTHTRUNC
verilator_flags     += -Wno-WIDTHEXPAND

verilator_flags     += $(if $(TRACE_VCD_FILE),--trace)
verilator_flags     += $(if $(TRACE_FST_FILE),--trace-fst)

ifeq (1,$(NO_UART_BOOT))
verilator_flags     += -DNO_UART_BOOT
else
verilator_flags     += $(if $(BIN_SIZE),-DBIN_SIZE=\($(BIN_SIZE)\),$(error specify BIN_SIZE))
endif
# verilator_flags     += -DCLK_FREQ_MHZ=100

verilator_input     += $(test_srcs) $(srcs)

#===============================================================================
# Plusargs
#-------------------------------------------------------------------------------
plusargs            += $(if $(filter-out 0,$(DISPLAY_CYCLES)),+display_cycles=$(DISPLAY_CYCLES))
plusargs            += $(if $(MAX_CYCLES),+max_cycles=$(MAX_CYCLES))
plusargs            += $(if $(MEM_FILE),+mem_file="$(MEM_FILE)")
plusargs            += $(if $(KERNEL),+kernel="$(KERNEL)")
plusargs            += $(if $(KERNEL_BASE),+kernel_base="$(KERNEL_BASE)")
plusargs            += $(if $(INITRD),+initrd="$(INITRD)")
plusargs            += $(if $(INITRD_BASE),+initrd_base="$(INITRD_BASE)")
plusargs            += $(if $(SIG_FILE),+signature="$(log_dir)/$(SIG_FILE)")
plusargs            += $(if $(COMMIT_LOG_FILE),+commit_log_file="$(log_dir)/$(COMMIT_LOG_FILE)")
plusargs            += $(if $(TRACE_SC_FILE),+trace_sc_file="$(log_dir)/$(TRACE_SC_FILE)")
plusargs            += $(if $(TRACE_VCD_FILE),+trace_vcd_file="$(log_dir)/$(TRACE_VCD_FILE)")
plusargs            += $(if $(TRACE_FST_FILE),+trace_fst_file="$(log_dir)/$(TRACE_FST_FILE)")
plusargs            += $(if $(TRACE_RF_FILE),+trace_rf_file="$(log_dir)/$(TRACE_RF_FILE)")
plusargs            += $(if $(TRACE_RF_BEGIN),+trace_rf_begin=$(TRACE_RF_BEGIN))
plusargs            += $(if $(TRACE_RF_END),+trace_rf_end=$(TRACE_RF_END))
plusargs            += $(if $(TRACE_DMEM_FILE),+trace_dmem_file="$(log_dir)/$(TRACE_DMEM_FILE)")
plusargs            += $(if $(filter $(ENABLE_DEBUG_LOG),1),+enable_debug_log=1)
plusargs            += $(if $(filter $(RVTEST_MODE),1),+rvtest_mode=1)

#===============================================================================
# Vivado
#-------------------------------------------------------------------------------
xrppath             ?= $(project_path)/$(project_name)/$(project_name).xpr
bitstream           := $(project_path)/$(project_name)/$(project_name).runs/impl_1/soc.bit

vivado_build_flags  := -mode batch -source $(vivado_build_tcl)
vivado_build_flags  += -tclargs $(rvcomp_path) $(project_path) $(project_name) $(board_data_path) 
vivado_build_flags  += $(board_part) $(board) $(mig_xml_path) $(constr_path)
vivado_build_flags  += $(srcs) $(configs)

vivado_rebuild_flags:= -mode batch -source $(vivado_rebuild_tcl)
vivado_rebuild_flags+= -tclargs $(xrppath) 

vivado_remote_flags   := -mode batch -source $(vivado_remote_tcl)
vivado_remote_flags   += -tclargs $(project_path) $(project_name) $(ip_address) 
vivado_remote_flags   += $(serial_number) $(bitstream) $(device)

vivado_load_flags   := -mode batch -source $(vivado_local_tcl)
vivado_load_flags   += -tclargs $(project_path) $(project_name) $(bitstream) $(device)

#===============================================================================
# UV
#-------------------------------------------------------------------------------
uv                  := uv run
uv_flags            := --project $(pyserial_path) $(pyserial_project_name)
uv_flags            += $(COM_PORT) $(BAUD_RATE)

#===============================================================================
# Build rules
#-------------------------------------------------------------------------------
.PHONY: default build run riscof_model
default: ;

build:
	make -C $(bootrom_dir) $(if $(filter $(NO_UART_BOOT),1),NO_UART_BOOT=1,NO_UART_BOOT=0 BIN_SIZE="$(BIN_SIZE)") --no-print-directory
	$(verilator) $(verilator_flags) $(verilator_input)

run: $(log_dir)
	$(PREFIX)obj_dir/$(topname) $(plusargs)

riscof_model:
	make build NO_UART_BOOT=1 --no-print-directory

$(log_dir):
	@mkdir -p $@

$(diff_dir):
	@mkdir -p $@

#-------------------------------------------------------------------------------
.PHONY: clean progclean vivadoclean distclean
clean:
	-rm -rf obj_dir/
	-rm -rf $(log_dir)
	-rm -f *.vcd *.fst
	-rm -f *.log *.diff
	-rm -f pytest/nlogs/*
	@make clean -C $(bootrom_dir) --no-print-directory

progclean:
	@echo $(riscv-tests_dir)
	@make distclean -C $(riscv-tests_dir) --no-print-directory
	@echo $(coremark_dir)
	@make distclean -C $(coremark_dir) --no-print-directory
	@echo $(embench_dir)
	@make distclean -C $(embench_dir) --no-print-directory
	@echo $(rvtest_dir)
	@make clean -C $(rvtest_dir) --no-print-directory

vivado_proj_dir     ?= vivado
vivadoclean:
	-rm -rf $(shell find .                     \
		    -name '.Xil'                       \
		-or -name 'vivado*.jou'                \
		-or -name 'vivado*.log'                \
		-or -name 'vivado*.str'                \
	)
	-if [ -d "$(vivado_proj_dir)" ]; then      \
		rm -rf $(shell find $(vivado_proj_dir) \
			     -name '*.cache'               \
			-or  -name '*.hw'                  \
			-or  -name '*.runs'                \
			-or  -name '*.sim'                 \
			-or  -name '*.ip_user_files'       \
		);                                     \
	fi

distclean: clean progclean vivadoclean

#===============================================================================
# result-template
#-------------------------------------------------------------------------------
#                                $1           , $2           , $3                 , $4               , $5       , $6
# $(eval $(call result-template, $program-name, @program-list, $program-target-dir, $program-root-dir, $ram-size, $max-cycles))
define result-template
.PHONY: $1 $2
$1: $2

ifeq (1,$(DIFF_SPIKE_TRACE))
$2: $3 $$(log_dir) $$(diff_dir)
	@echo $$@
	@echo --------------------------------------------------------------------------------
	@echo spike
	@echo ------------------------------------------------------------
	$$(spike) --isa=rv32ima_zicntr_zicsr_zifencei --misaligned --log-commits --log="$$(log_dir)/$$@_spike_commit.log" "$3/$$@.elf"
	@sed -i '1,5d' "$$(log_dir)/$$@_spike_commit.log"
	@echo ------------------------------------------------------------
	@echo
	@echo rvcom
	@echo ------------------------------------------------------------
	@make build BIN_SIZE="$5" --no-print-directory > /dev/null
	@make run MEM_FILE="$3/$$@.128.hex" MAX_CYCLES="$6" COMMIT_LOG_FILE="$$@_rvcom_commit.log" RVTEST_MODE=$7 --no-print-directory
	-@diff "$$(log_dir)/$$@_spike_commit.log" "$$(log_dir)/$$@_rvcom_commit.log" > $$(diff_dir)/$$@_commit_log.diff
	@echo ------------------------------------------------------------
	@echo
else ifeq (1,$(RVCOM_TRACE))
$2: $3 $$(log_dir)
	@echo $$@
	@echo --------------------------------------------------------------------------------
	@echo rvcom
	@echo ------------------------------------------------------------
	@make build BIN_SIZE="$5" --no-print-directory > /dev/null
	@make run MEM_FILE="$3/$$@.128.hex" MAX_CYCLES="$6" COMMIT_LOG_FILE="$$@_rvcom_commit.log" RVTEST_MODE=$7 --no-print-directory
	@echo ------------------------------------------------------------
	@echo
else ifeq (1,$(SC_TRACE))
$2: $3 $$(log_dir)
	@echo $$@
	@echo --------------------------------------------------------------------------------
	@echo rvcom
	@echo ------------------------------------------------------------
	@make build BIN_SIZE="$5" --no-print-directory > /dev/null
	@make run MEM_FILE="$3/$$@.128.hex" MAX_CYCLES="$6" TRACE_SC_FILE="$$@_trace_sc.log" RVTEST_MODE=$7 --no-print-directory
	@echo ------------------------------------------------------------
	@echo
else
$2: SHELL=bash
$2: $3
	@echo $$@
	@echo --------------------------------------------------------------------------------
	@echo rvcom
	@echo ------------------------------------------------------------
	@make build BIN_SIZE="$5" --no-print-directory > /dev/null
	@make run MEM_FILE="$3/$$@.128.hex" MAX_CYCLES="$6" RVTEST_MODE=$7 --no-print-directory
	@echo
endif

$3:
	make XLEN=$$(XLEN) RISCV_ARCH=$$(RISCV_ARCH) RISCV_ABI=$$(RISCV_ABI) -C $4
endef

#===============================================================================
# riscv-tests/isa
#-------------------------------------------------------------------------------
.PHONY: $(rv32ui_tests) $(rv32um_tests) $(rv32ua_tests) $(rv32si_tests) $(rv32mi_tests)
rv32ui_tests        := \
	simple \
	add addi sub and andi or ori xor xori \
	sll slli srl srli sra srai slt slti sltiu sltu \
	beq bge bgeu blt bltu bne jal jalr \
	sb sh sw lb lbu lh lhu lw \
	auipc lui \
	fence_i ma_data

rv32um_tests        := \
	mul mulh mulhsu mulhu \
	div divu \
	rem remu

rv32ua_tests        := \
	amoadd_w amoand_w amomax_w amomaxu_w amomin_w amominu_w amoor_w amoxor_w amoswap_w \
	lrsc

rv32si_tests        := \
	csr dirty ma_fetch scall sbreak wfi

rv32mi_tests        := \
	breakpoint csr mcsr illegal \
	ma_fetch ma_addr \
	scall sbreak shamt \
	lw-misaligned lh-misaligned sh-misaligned sw-misaligned \
	zicntr

.PHONY: $(rv32ui_$(TGT_ENV)_tests) $(rv32um_$(TGT_ENV)_tests) $(rv32ua_$(TGT_ENV)_tests) $(rv32si_$(TGT_ENV)_tests) $(rv32mi_$(TGT_ENV)_tests)
rv32ui_$(TGT_ENV)_tests := $(addprefix rv32ui-$(TGT_ENV)-, $(rv32ui_tests))
rv32um_$(TGT_ENV)_tests := $(addprefix rv32um-$(TGT_ENV)-, $(rv32um_tests))
rv32ua_$(TGT_ENV)_tests := $(addprefix rv32ua-$(TGT_ENV)-, $(rv32ua_tests))
rv32si_$(TGT_ENV)_tests := $(addprefix rv32si-$(TGT_ENV)-, $(rv32si_tests))
rv32mi_$(TGT_ENV)_tests := $(addprefix rv32mi-$(TGT_ENV)-, $(rv32mi_tests))

#-------------------------------------------------------------------------------
.PHONY: isa
isa: rv32ui_test
ifeq (1,$(RVM))
isa: rv32um_test
endif
ifeq (1,$(RVA))
isa: rv32ua_test
endif

ifneq (v,$(TGT_ENV))
ifeq (1,$(RVS))
isa: rv32si_test
else
isa: rv32mi_test
endif
endif

.PHONY: rv32ui_test rv32um_test rv32ua_test rv32si_test rv32mi_test
rv32ui_test: $(rv32ui_$(TGT_ENV)_tests)
rv32um_test: $(rv32um_$(TGT_ENV)_tests)
rv32ua_test: $(rv32ua_$(TGT_ENV)_tests)
rv32si_test: $(rv32si_$(TGT_ENV)_tests)
rv32mi_test: $(rv32mi_$(TGT_ENV)_tests)

### $(eval $(call result-template, $program-name, $program-list, $program-target-dir, $program-root-dir, $bin-size, $max-cycles, $rvtest_mode))
$(eval $(call result-template,rv32ui_test,$(rv32ui_$(TGT_ENV)_tests),$(riscv-tests_dir)/rv32ui,$(riscv-tests_dir),64*1024,1000000,1))
$(eval $(call result-template,rv32um_test,$(rv32um_$(TGT_ENV)_tests),$(riscv-tests_dir)/rv32um,$(riscv-tests_dir),64*1024,1000000,1))
$(eval $(call result-template,rv32ua_test,$(rv32ua_$(TGT_ENV)_tests),$(riscv-tests_dir)/rv32ua,$(riscv-tests_dir),64*1024,1000000,1))
ifeq (1,$(RVS))
$(eval $(call result-template,rv32si_test,$(rv32si_$(TGT_ENV)_tests),$(riscv-tests_dir)/rv32si,$(riscv-tests_dir),64*1024,1000000,1))
else
$(eval $(call result-template,rv32mi_test,$(rv32mi_$(TGT_ENV)_tests),$(riscv-tests_dir)/rv32mi,$(riscv-tests_dir),64*1024,1000000,1))
endif

### alias
$(rv32ui_tests): %: rv32ui-$(TGT_ENV)-%
$(rv32um_tests): %: rv32um-$(TGT_ENV)-%
$(rv32ua_tests): %: rv32ua-$(TGT_ENV)-%
$(rv32si_tests): %: rv32si-$(TGT_ENV)-%
$(rv32mi_tests): %: rv32mi-$(TGT_ENV)-%

#===============================================================================
# Coremark
#-------------------------------------------------------------------------------
# max-cycles:
#     ITERATIONS=1  : 1000000
#     ITERATIONS=100: 100000000
### $(eval $(call result-template, $program-name, $program-list, $program-target-dir, $program-root-dir, $bin-size, $max-cycles, $rvtest_mode))
$(eval $(call result-template,cmark,coremark,$(coremark_dir)/$(RISCV_ARCH),$(coremark_dir),32*1024,10000000000,0))

#===============================================================================
# Embench-iot
#-------------------------------------------------------------------------------
embench             := \
	aha-mont64 crc32 cubic edn huffbench matmult-int md5sum minver nbody \
	nettle-aes nettle-sha256 nsichneu picojpeg primecount qrduino \
	sglib-combined slre st statemate tarfind ud wikisort

### $(eval $(call result-template, $program-name, $program-list, $program-target-dir, $program-root-dir, $bin-size, $max-cycles, $rvtest_mode))
$(eval $(call result-template,embench,$(embench),$(embench_dir)/$(RISCV_ARCH),$(embench_dir),128*1024,200000000,0))

#===============================================================================
# rvtest
#-------------------------------------------------------------------------------
rvtest              := \
	test

### $(eval $(call result-template, $program-name, $program-list, $program-target-dir, $program-root-dir, $bin-size, $max-cycles, $rvtest_mode))
$(eval $(call result-template,rvtest,$(rvtest),$(rvtest_dir)/build,$(rvtest_dir),16*1024,20000000,0))

#===============================================================================
# OpenSBI/Linux/Buildroot
#-------------------------------------------------------------------------------
# When using initrd, you need to add "linux,initrd-start = <initrd_start_addr>;"
# and "linux,initrd-end = <initrd_end_addr>;" to the chosen node of the device tree.
linux_jump:
	@echo fw_jump
	@echo --------------------------------------------------------------------------------
	@make build BIN_SIZE="24*1024*1024" --no-print-directory > /dev/null
	@make run \
		MEM_FILE="$(fw_jump_dir)/fw_jump.128.hex" \
		KERNEL="$(kernel_dir)/$(kernel_128_hex)" KERNEL_BASE="$(kernel_base)" \
		INITRD="$(initrd_dir)/$(initrd_128_hex)" INITRD_BASE="$(initrd_base)" \
		MAX_CYCLES="20000000000" --no-print-directory
	@echo

linux:
	@echo fw_payload
	@echo --------------------------------------------------------------------------------
	@make build BIN_SIZE="24*1024*1024" --no-print-directory > /dev/null
	@echo "Ensuring fw_payload.128.hex exists..."
	@if [ ! -f "$(fw_payload_dir)/fw_payload.128.hex" ]; then \
		$(MAKE) -C image; \
	fi
	@make run MEM_FILE="$(fw_payload_dir)/fw_payload.128.hex" MAX_CYCLES="4000000000" --no-print-directory
	@echo
# 4,000,000,000
# Specify BIN_SIZE in config.mk as follows
# bootrom: BIN_SIZE=
.PHONY: bootrom
bootrom:
	make -C $(bootrom_dir) NO_UART_BOOT=0 BIN_SIZE="$(BIN_SIZE)" --no-print-directory

.PHONY: bit load
#===============================================================================
# FPGA
#-------------------------------------------------------------------------------
bit: 
	make -C $(bootrom_dir) clean 
	make bootrom
	$(vivado) $(vivado_build_flags)

rebit:
	make -C $(bootrom_dir) clean
	make bootrom
	$(vivado) $(vivado_rebuild_flags)

load:
	$(vivado) $(vivado_load_flags)

remoteload:
	$(vivado) $(vivado_remote_flags)

termnb:
	$(uv) $(uv_flags)

term:
	$(uv) $(uv_flags) $(pyserial_flags)

config:
	$(uv) $(uv_flags) $(pyserial_flags) --bitstream-load local

#===============================================================================