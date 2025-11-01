# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025 Archlab, Science Tokyo

set PROJECT_PATH [lindex $argv 0]
set PROJECT_NAME [lindex $argv 1]
set BITSTREAM    [lindex $argv 2]
set DEVICE       [lindex $argv 3]

puts "bitstream: $BITSTREAM"
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set_property PROGRAM.FILE "$BITSTREAM" [get_hw_devices $DEVICE]
current_hw_device [get_hw_devices $DEVICE]
refresh_hw_device -update_hw_probes false [lindex [get_hw_devices $DEVICE] 0]
set_property PROBES.FILE {} [get_hw_devices $DEVICE]
set_property FULL_PROBES.FILE {} [get_hw_devices $DEVICE]
set_property PROGRAM.FILE "$BITSTREAM" [get_hw_devices $DEVICE]
program_hw_devices [get_hw_devices $DEVICE]
refresh_hw_device [lindex [get_hw_devices $DEVICE] 0]
