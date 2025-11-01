# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025 Archlab, Science Tokyo

set PROJECT_PATH [lindex $argv 0]
set PROJECT_NAME [lindex $argv 1]
set IPADDRESS    [lindex $argv 2]
set SERIAL       [lindex $argv 3]
set BITSTREAM    [lindex $argv 4]
set DEVICE       [lindex $argv 5]

if {$IPADDRESS == "" || $SERIAL == ""} {
    puts "Error: Both IP address and Serial number must be specified."    
    exit 1
}
puts "bitstream: $BITSTREAM"
open_hw_manager
connect_hw_server -url $IPADDRESS:3121 -allow_non_jtag
current_hw_target [get_hw_targets */xilinx_tcf/Digilent/$SERIAL]
set_property PARAM.FREQUENCY 15000000 [get_hw_targets */xilinx_tcf/Digilent/$SERIAL]
open_hw_target
set_property PROGRAM.FILE "$BITSTREAM" [get_hw_devices $DEVICE]
current_hw_device [get_hw_devices $DEVICE]
refresh_hw_device -update_hw_probes false [lindex [get_hw_devices $DEVICE] 0]
set_property PROBES.FILE {} [get_hw_devices $DEVICE]
set_property FULL_PROBES.FILE {} [get_hw_devices $DEVICE]
set_property PROGRAM.FILE "$BITSTREAM" [get_hw_devices $DEVICE]
program_hw_devices [get_hw_devices $DEVICE]
refresh_hw_device [lindex [get_hw_devices $DEVICE] 0]