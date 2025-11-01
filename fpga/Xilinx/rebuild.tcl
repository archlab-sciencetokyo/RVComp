# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025 Archlab, Science Tokyo

set XPR_PATH    [lindex $argv 0]
set nproc           [exec nproc]

open_project $XPR_PATH
update_compile_order -fileset sources_1
reset_run synth_1
reset_run impl_1
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs $nproc
wait_on_run synth_1

launch_runs impl_1 -to_step write_bitstream -jobs $nproc
wait_on_run impl_1