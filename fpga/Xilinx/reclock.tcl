# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025 Archlab, Science Tokyo

set RVCOMP_PATH     [lindex $argv 0]
set XPR_PATH        [lindex $argv 1]
set PROJECT_PATH    [lindex $argv 2]
set PROJECT_NAME    [lindex $argv 3]
set nproc           [exec nproc]

set file [open "$RVCOMP_PATH/src/config.vh"]
if {[regexp {`define\s+CLK_FREQ_MHZ\s*\(\s*([0-9]+)\s*\)} [read $file] -> freq]} {
    puts "Found frequency: $freq MHz"
} else {
    puts "CLK_FREQ_MHZ not found in config.vh"
    close $file
    exit 1
}
close $file

open_project $XPR_PATH
update_compile_order -fileset sources_1
set_property -dict [list \
  CONFIG.JITTER_SEL {Min_O_Jitter} \
  CONFIG.MMCM_BANDWIDTH {HIGH} \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ [subst $freq] \
] [get_ips clk_wiz_1]
catch { config_ip_cache -export [get_ips -all clk_wiz_1] }
catch { delete_ip_run [get_ips -all clk_wiz_1] }
export_ip_user_files -of_objects [get_files $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_1/clk_wiz_1.xci] -no_script -sync -force -quiet
create_ip_run [get_files -of_objects [get_fileset sources_1] $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_1/clk_wiz_1.xci] -force
export_simulation -of_objects [get_files $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_1/clk_wiz_1.xci] -directory $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.ip_user_files/sim_scripts -ip_user_files_dir $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.ip_user_files -ipstatic_source_dir $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.ip_user_files/ipstatic -lib_map_path [list {modelsim=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/modelsim} {questa=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/questa} {xcelium=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/xcelium} {vcs=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/vcs} {riviera=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/riviera}] -use_ip_compiled_libs -force -quiet

# Re-synthesize the IP so the new frequency takes effect
launch_runs clk_wiz_1_synth_1 -jobs $nproc
wait_on_run clk_wiz_1_synth_1

update_compile_order -fileset sources_1

# Full rebuild (same as rebuild.tcl)
reset_run synth_1
reset_run impl_1
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs $nproc
wait_on_run synth_1

launch_runs impl_1 -to_step write_bitstream -jobs $nproc
wait_on_run impl_1

source [file join [file dirname [info script]] check_build.tcl]
check_build_result [glob -nocomplain "[file dirname $XPR_PATH]/*.runs/impl_1/runme.log"]