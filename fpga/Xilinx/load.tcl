# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025 Archlab, Science Tokyo

set PROJECT_PATH   [lindex $argv 0]
set PROJECT_NAME   [lindex $argv 1]
set BITSTREAM      [lindex $argv 2]
set DEVICE         [lindex $argv 3]
set SERIAL_NUMBER  [lindex $argv 4]

puts "bitstream: $BITSTREAM"
open_hw_manager

if {$SERIAL_NUMBER ne ""} {
    puts "select connect: serial_number=$SERIAL_NUMBER"
    connect_hw_server -url localhost:3121 -allow_non_jtag
    current_hw_target [get_hw_targets */xilinx_tcf/Digilent/$SERIAL_NUMBER]
    set_property PARAM.FREQUENCY 15000000 [get_hw_targets */xilinx_tcf/Digilent/$SERIAL_NUMBER]
    open_hw_target
} else {
    puts "auto connect"
    connect_hw_server -allow_non_jtag
    open_hw_target
}
set_property PROGRAM.FILE "$BITSTREAM" [get_hw_devices $DEVICE]
current_hw_device [get_hw_devices $DEVICE]
refresh_hw_device -update_hw_probes false [lindex [get_hw_devices $DEVICE] 0]
set_property PROBES.FILE {} [get_hw_devices $DEVICE]
set_property FULL_PROBES.FILE {} [get_hw_devices $DEVICE]
set_property PROGRAM.FILE "$BITSTREAM" [get_hw_devices $DEVICE]
program_hw_devices [get_hw_devices $DEVICE]
refresh_hw_device [lindex [get_hw_devices $DEVICE] 0]
