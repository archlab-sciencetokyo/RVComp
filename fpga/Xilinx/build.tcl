# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025 Archlab, Science Tokyo

set RVCOMP_PATH     [lindex $argv 0]
set PROJECT_PATH    [lindex $argv 1]
set PROJECT_NAME    [lindex $argv 2]
set BOARD_DATA_PATH [lindex $argv 3]
set BOARD_PART      [lindex $argv 4]
set BOARD           [lindex $argv 5]
set MIG_XML_PATH    [lindex $argv 6]
set CONSTR_PATH     [lindex $argv 7]
set SRC_FILES       [lrange $argv 8 end]
set nproc           [exec nproc]

set file [open "$RVCOMP_PATH/src/config.vh"]
set config_vh [read $file]
close $file

if {[regexp {`define\s+CLK_FREQ_MHZ\s*\(\s*([0-9]+)\s*\)} $config_vh -> freq]} {
  puts "Found frequency: $freq MHz"
} else {
  puts "CLK_FREQ_MHZ not found in config.vh"
  exit 1
}

if {[regexp -line {^\s*`define\s+NEXYS} $config_vh]} {
  set eth_if_mode "RMII"
  set refclk_freq 50.0
} else {
  set eth_if_mode "MII"
  set refclk_freq 25.0
}
puts "Ethernet mode from config.vh: $eth_if_mode, REFCLK: [format %.6f $refclk_freq] MHz"
set_param board.repoPaths [list "$BOARD_DATA_PATH"]
create_project $PROJECT_NAME $PROJECT_PATH/$PROJECT_NAME -part $BOARD_PART -force

set_property board_part $BOARD [current_project]
put "$MIG_XML_PATH"
create_ip -name mig_7series -vendor xilinx.com -library ip -version 4.2 -module_name mig_7series_0
set_property -dict [list \
  CONFIG.ARESETN.INSERT_VIP {0} \
  CONFIG.BOARD_MIG_PARAM {Custom} \
  CONFIG.C0_ARESETN.INSERT_VIP {0} \
  CONFIG.C0_CLOCK.INSERT_VIP {0} \
  CONFIG.C0_DDR2_RESET.INSERT_VIP {0} \
  CONFIG.C0_DDR3_RESET.INSERT_VIP {0} \
  CONFIG.C0_LPDDR2_RESET.INSERT_VIP {0} \
  CONFIG.C0_MMCM_CLKOUT0.INSERT_VIP {0} \
  CONFIG.C0_MMCM_CLKOUT1.INSERT_VIP {0} \
  CONFIG.C0_MMCM_CLKOUT2.INSERT_VIP {0} \
  CONFIG.C0_MMCM_CLKOUT3.INSERT_VIP {0} \
  CONFIG.C0_MMCM_CLKOUT4.INSERT_VIP {0} \
  CONFIG.C0_QDRIIP_RESET.INSERT_VIP {0} \
  CONFIG.C0_RESET.INSERT_VIP {0} \
  CONFIG.C0_RLDIII_RESET.INSERT_VIP {0} \
  CONFIG.C0_RLDII_RESET.INSERT_VIP {0} \
  CONFIG.C0_SYS_CLK_I.INSERT_VIP {0} \
  CONFIG.C1_ARESETN.INSERT_VIP {0} \
  CONFIG.C1_CLOCK.INSERT_VIP {0} \
  CONFIG.C1_DDR2_RESET.INSERT_VIP {0} \
  CONFIG.C1_DDR3_RESET.INSERT_VIP {0} \
  CONFIG.C1_LPDDR2_RESET.INSERT_VIP {0} \
  CONFIG.C1_MMCM_CLKOUT0.INSERT_VIP {0} \
  CONFIG.C1_MMCM_CLKOUT1.INSERT_VIP {0} \
  CONFIG.C1_MMCM_CLKOUT2.INSERT_VIP {0} \
  CONFIG.C1_MMCM_CLKOUT3.INSERT_VIP {0} \
  CONFIG.C1_MMCM_CLKOUT4.INSERT_VIP {0} \
  CONFIG.C1_QDRIIP_RESET.INSERT_VIP {0} \
  CONFIG.C1_RESET.INSERT_VIP {0} \
  CONFIG.C1_RLDIII_RESET.INSERT_VIP {0} \
  CONFIG.C1_RLDII_RESET.INSERT_VIP {0} \
  CONFIG.C1_SYS_CLK_I.INSERT_VIP {0} \
  CONFIG.C2_ARESETN.INSERT_VIP {0} \
  CONFIG.C2_CLOCK.INSERT_VIP {0} \
  CONFIG.C2_DDR2_RESET.INSERT_VIP {0} \
  CONFIG.C2_DDR3_RESET.INSERT_VIP {0} \
  CONFIG.C2_LPDDR2_RESET.INSERT_VIP {0} \
  CONFIG.C2_MMCM_CLKOUT0.INSERT_VIP {0} \
  CONFIG.C2_MMCM_CLKOUT1.INSERT_VIP {0} \
  CONFIG.C2_MMCM_CLKOUT2.INSERT_VIP {0} \
  CONFIG.C2_MMCM_CLKOUT3.INSERT_VIP {0} \
  CONFIG.C2_MMCM_CLKOUT4.INSERT_VIP {0} \
  CONFIG.C2_QDRIIP_RESET.INSERT_VIP {0} \
  CONFIG.C2_RESET.INSERT_VIP {0} \
  CONFIG.C2_RLDIII_RESET.INSERT_VIP {0} \
  CONFIG.C2_RLDII_RESET.INSERT_VIP {0} \
  CONFIG.C2_SYS_CLK_I.INSERT_VIP {0} \
  CONFIG.C3_ARESETN.INSERT_VIP {0} \
  CONFIG.C3_CLOCK.INSERT_VIP {0} \
  CONFIG.C3_DDR2_RESET.INSERT_VIP {0} \
  CONFIG.C3_DDR3_RESET.INSERT_VIP {0} \
  CONFIG.C3_LPDDR2_RESET.INSERT_VIP {0} \
  CONFIG.C3_MMCM_CLKOUT0.INSERT_VIP {0} \
  CONFIG.C3_MMCM_CLKOUT1.INSERT_VIP {0} \
  CONFIG.C3_MMCM_CLKOUT2.INSERT_VIP {0} \
  CONFIG.C3_MMCM_CLKOUT3.INSERT_VIP {0} \
  CONFIG.C3_MMCM_CLKOUT4.INSERT_VIP {0} \
  CONFIG.C3_QDRIIP_RESET.INSERT_VIP {0} \
  CONFIG.C3_RESET.INSERT_VIP {0} \
  CONFIG.C3_RLDIII_RESET.INSERT_VIP {0} \
  CONFIG.C3_RLDII_RESET.INSERT_VIP {0} \
  CONFIG.C3_SYS_CLK_I.INSERT_VIP {0} \
  CONFIG.C4_ARESETN.INSERT_VIP {0} \
  CONFIG.C4_CLOCK.INSERT_VIP {0} \
  CONFIG.C4_DDR2_RESET.INSERT_VIP {0} \
  CONFIG.C4_DDR3_RESET.INSERT_VIP {0} \
  CONFIG.C4_LPDDR2_RESET.INSERT_VIP {0} \
  CONFIG.C4_MMCM_CLKOUT0.INSERT_VIP {0} \
  CONFIG.C4_MMCM_CLKOUT1.INSERT_VIP {0} \
  CONFIG.C4_MMCM_CLKOUT2.INSERT_VIP {0} \
  CONFIG.C4_MMCM_CLKOUT3.INSERT_VIP {0} \
  CONFIG.C4_MMCM_CLKOUT4.INSERT_VIP {0} \
  CONFIG.C4_QDRIIP_RESET.INSERT_VIP {0} \
  CONFIG.C4_RESET.INSERT_VIP {0} \
  CONFIG.C4_RLDIII_RESET.INSERT_VIP {0} \
  CONFIG.C4_RLDII_RESET.INSERT_VIP {0} \
  CONFIG.C4_SYS_CLK_I.INSERT_VIP {0} \
  CONFIG.C5_ARESETN.INSERT_VIP {0} \
  CONFIG.C5_CLOCK.INSERT_VIP {0} \
  CONFIG.C5_DDR2_RESET.INSERT_VIP {0} \
  CONFIG.C5_DDR3_RESET.INSERT_VIP {0} \
  CONFIG.C5_LPDDR2_RESET.INSERT_VIP {0} \
  CONFIG.C5_MMCM_CLKOUT0.INSERT_VIP {0} \
  CONFIG.C5_MMCM_CLKOUT1.INSERT_VIP {0} \
  CONFIG.C5_MMCM_CLKOUT2.INSERT_VIP {0} \
  CONFIG.C5_MMCM_CLKOUT3.INSERT_VIP {0} \
  CONFIG.C5_MMCM_CLKOUT4.INSERT_VIP {0} \
  CONFIG.C5_QDRIIP_RESET.INSERT_VIP {0} \
  CONFIG.C5_RESET.INSERT_VIP {0} \
  CONFIG.C5_RLDIII_RESET.INSERT_VIP {0} \
  CONFIG.C5_RLDII_RESET.INSERT_VIP {0} \
  CONFIG.C5_SYS_CLK_I.INSERT_VIP {0} \
  CONFIG.C6_ARESETN.INSERT_VIP {0} \
  CONFIG.C6_CLOCK.INSERT_VIP {0} \
  CONFIG.C6_DDR2_RESET.INSERT_VIP {0} \
  CONFIG.C6_DDR3_RESET.INSERT_VIP {0} \
  CONFIG.C6_LPDDR2_RESET.INSERT_VIP {0} \
  CONFIG.C6_MMCM_CLKOUT0.INSERT_VIP {0} \
  CONFIG.C6_MMCM_CLKOUT1.INSERT_VIP {0} \
  CONFIG.C6_MMCM_CLKOUT2.INSERT_VIP {0} \
  CONFIG.C6_MMCM_CLKOUT3.INSERT_VIP {0} \
  CONFIG.C6_MMCM_CLKOUT4.INSERT_VIP {0} \
  CONFIG.C6_QDRIIP_RESET.INSERT_VIP {0} \
  CONFIG.C6_RESET.INSERT_VIP {0} \
  CONFIG.C6_RLDIII_RESET.INSERT_VIP {0} \
  CONFIG.C6_RLDII_RESET.INSERT_VIP {0} \
  CONFIG.C6_SYS_CLK_I.INSERT_VIP {0} \
  CONFIG.C7_ARESETN.INSERT_VIP {0} \
  CONFIG.C7_CLOCK.INSERT_VIP {0} \
  CONFIG.C7_DDR2_RESET.INSERT_VIP {0} \
  CONFIG.C7_DDR3_RESET.INSERT_VIP {0} \
  CONFIG.C7_LPDDR2_RESET.INSERT_VIP {0} \
  CONFIG.C7_MMCM_CLKOUT0.INSERT_VIP {0} \
  CONFIG.C7_MMCM_CLKOUT1.INSERT_VIP {0} \
  CONFIG.C7_MMCM_CLKOUT2.INSERT_VIP {0} \
  CONFIG.C7_MMCM_CLKOUT3.INSERT_VIP {0} \
  CONFIG.C7_MMCM_CLKOUT4.INSERT_VIP {0} \
  CONFIG.C7_QDRIIP_RESET.INSERT_VIP {0} \
  CONFIG.C7_RESET.INSERT_VIP {0} \
  CONFIG.C7_RLDIII_RESET.INSERT_VIP {0} \
  CONFIG.C7_RLDII_RESET.INSERT_VIP {0} \
  CONFIG.C7_SYS_CLK_I.INSERT_VIP {0} \
  CONFIG.CLK_REF_I.INSERT_VIP {0} \
  CONFIG.CLOCK.INSERT_VIP {0} \
  CONFIG.DDR2_RESET.INSERT_VIP {0} \
  CONFIG.DDR3_RESET.INSERT_VIP {0} \
  CONFIG.LPDDR2_RESET.INSERT_VIP {0} \
  CONFIG.MIG_DONT_TOUCH_PARAM {Custom} \
  CONFIG.MMCM_CLKOUT0.INSERT_VIP {0} \
  CONFIG.MMCM_CLKOUT1.INSERT_VIP {0} \
  CONFIG.MMCM_CLKOUT2.INSERT_VIP {0} \
  CONFIG.MMCM_CLKOUT3.INSERT_VIP {0} \
  CONFIG.MMCM_CLKOUT4.INSERT_VIP {0} \
  CONFIG.QDRIIP_RESET.INSERT_VIP {0} \
  CONFIG.RESET.INSERT_VIP {0} \
  CONFIG.RESET_BOARD_INTERFACE {Custom} \
  CONFIG.RLDIII_RESET.INSERT_VIP {0} \
  CONFIG.RLDII_RESET.INSERT_VIP {0} \
  CONFIG.S0_AXI.INSERT_VIP {0} \
  CONFIG.S0_AXI_CTRL.INSERT_VIP {0} \
  CONFIG.S1_AXI.INSERT_VIP {0} \
  CONFIG.S1_AXI_CTRL.INSERT_VIP {0} \
  CONFIG.S2_AXI.INSERT_VIP {0} \
  CONFIG.S2_AXI_CTRL.INSERT_VIP {0} \
  CONFIG.S3_AXI.INSERT_VIP {0} \
  CONFIG.S3_AXI_CTRL.INSERT_VIP {0} \
  CONFIG.S4_AXI.INSERT_VIP {0} \
  CONFIG.S4_AXI_CTRL.INSERT_VIP {0} \
  CONFIG.S5_AXI.INSERT_VIP {0} \
  CONFIG.S5_AXI_CTRL.INSERT_VIP {0} \
  CONFIG.S6_AXI.INSERT_VIP {0} \
  CONFIG.S6_AXI_CTRL.INSERT_VIP {0} \
  CONFIG.S7_AXI.INSERT_VIP {0} \
  CONFIG.S7_AXI_CTRL.INSERT_VIP {0} \
  CONFIG.SYSTEM_RESET.INSERT_VIP {0} \
  CONFIG.SYS_CLK_I.INSERT_VIP {0} \
  CONFIG.S_AXI.INSERT_VIP {0} \
  CONFIG.S_AXI_CTRL.INSERT_VIP {0} \
  CONFIG.XML_INPUT_FILE "[subst $MIG_XML_PATH]" \
] [get_ips mig_7series_0]
generate_target {instantiation_template} [get_files $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/mig_7series_0/mig_7series_0.xci]
update_compile_order -fileset sources_1
generate_target all [get_files  $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/mig_7series_0/mig_7series_0.xci]
export_ip_user_files -of_objects [get_files $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/mig_7series_0/mig_7series_0.xci] -no_script -sync -force -quiet
create_ip_run [get_files -of_objects [get_fileset sources_1] $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/mig_7series_0/mig_7series_0.xci]
launch_runs mig_7series_0_synth_1 -jobs $nproc
wait_on_run mig_7series_0_synth_1
export_simulation -of_objects [get_files $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/mig_7series_0/mig_7series_0.xci] -directory $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.ip_user_files/sim_scripts -ip_user_files_dir $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.ip_user_files -ipstatic_source_dir $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.ip_user_files/ipstatic -lib_map_path [list {modelsim=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/modelsim} {questa=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/questa} {xcelium=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/xcelium} {vcs=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/vcs} {riviera=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/riviera}] -use_ip_compiled_libs -force -quiet

create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_0
set_property -dict [list \
  CONFIG.CLKOUT1_JITTER {118.758} \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {166.66667} \
  CONFIG.CLKOUT2_JITTER {114.829} \
  CONFIG.CLKOUT2_PHASE_ERROR {98.575} \
  CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {200.00000} \
  CONFIG.CLKOUT2_USED {true} \
  CONFIG.MMCM_CLKOUT0_DIVIDE_F {6.000} \
  CONFIG.MMCM_CLKOUT1_DIVIDE {5} \
  CONFIG.NUM_OUT_CLKS {2} \
] [get_ips clk_wiz_0]

generate_target {instantiation_template} [get_files $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci]
update_compile_order -fileset sources_1
generate_target all [get_files  $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci]
catch { config_ip_cache -export [get_ips -all clk_wiz_0] }
export_ip_user_files -of_objects [get_files $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci] -no_script -sync -force -quiet
create_ip_run [get_files -of_objects [get_fileset sources_1] $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci]
launch_runs clk_wiz_0_synth_1 -jobs 32
wait_on_run clk_wiz_0_synth_1
export_simulation -of_objects [get_files $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci] -directory $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.ip_user_files/sim_scripts -ip_user_files_dir $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.ip_user_files -ipstatic_source_dir $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.ip_user_files/ipstatic -lib_map_path [list {modelsim=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/modelsim} {questa=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/questa} {xcelium=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/xcelium} {vcs=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/vcs} {riviera=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/riviera}] -use_ip_compiled_libs -force -quiet
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_1

set_property -dict [list \
  CONFIG.JITTER_SEL {Min_O_Jitter} \
  CONFIG.MMCM_BANDWIDTH {HIGH} \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ [subst $freq]\
  CONFIG.PRIM_IN_FREQ {100.00000} \
] [get_ips clk_wiz_1]
 

# Clock Settings End
generate_target {instantiation_template} [get_files $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_1/clk_wiz_1.xci]
generate_target all [get_files  $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_1/clk_wiz_1.xci]
catch { config_ip_cache -export [get_ips -all clk_wiz_1] }
export_ip_user_files -of_objects [get_files $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_1/clk_wiz_1.xci] -no_script -sync -force -quiet
create_ip_run [get_files -of_objects [get_fileset sources_1] $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_1/clk_wiz_1.xci]
launch_runs clk_wiz_1_synth_1 -jobs $nproc
wait_on_run clk_wiz_1_synth_1
export_simulation -of_objects [get_files $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_1/clk_wiz_1.xci] -directory $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.ip_user_files/sim_scripts -ip_user_files_dir $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.ip_user_files -ipstatic_source_dir $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.ip_user_files/ipstatic -lib_map_path [list {modelsim=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/modelsim} {questa=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/questa} {xcelium=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/xcelium} {vcs=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/vcs} {riviera=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/riviera}] -use_ip_compiled_libs -force -quiet

create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_2
set_property -dict [list \
  CONFIG.NUM_OUT_CLKS {2}\
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {50.000000}\
  CONFIG.CLKOUT2_REQUESTED_OUT_FREQ [format %.6f $refclk_freq]\
  CONFIG.CLKOUT2_REQUESTED_PHASE {-45.000}\
  CONFIG.CLKOUT2_USED {true}\
  CONFIG.PRIM_IN_FREQ {100.00000} \
] [get_ips clk_wiz_2]
# Clock Settings End
generate_target {instantiation_template} [get_files $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_2/clk_wiz_2.xci]
generate_target all [get_files  $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_2/clk_wiz_2.xci]
catch { config_ip_cache -export [get_ips -all clk_wiz_2] }
export_ip_user_files -of_objects [get_files $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_2/clk_wiz_2.xci] -no_script -sync -force -quiet
create_ip_run [get_files -of_objects [get_fileset sources_1] $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_2/clk_wiz_2.xci]
launch_runs clk_wiz_2_synth_1 -jobs $nproc
wait_on_run clk_wiz_2_synth_1
export_simulation -of_objects [get_files $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_2/clk_wiz_2.xci] -directory $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.ip_user_files/sim_scripts -ip_user_files_dir $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.ip_user_files -ipstatic_source_dir $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.ip_user_files/ipstatic -lib_map_path [list {modelsim=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/modelsim} {questa=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/questa} {xcelium=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/xcelium} {vcs=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/vcs} {riviera=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/riviera}] -use_ip_compiled_libs -force -quiet

create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_3
set_property -dict [list \
  CONFIG.NUM_OUT_CLKS {2}\
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {24.000000}\
  CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {24.000000}\
  CONFIG.CLKOUT2_USED {true}\
  CONFIG.PRIM_IN_FREQ {100.00000} \
] [get_ips clk_wiz_3]
# Clock Settings End
generate_target {instantiation_template} [get_files $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_3/clk_wiz_3.xci]
generate_target all [get_files  $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_3/clk_wiz_3.xci]
catch { config_ip_cache -export [get_ips -all clk_wiz_3] }
export_ip_user_files -of_objects [get_files $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_3/clk_wiz_3.xci] -no_script -sync -force -quiet
create_ip_run [get_files -of_objects [get_fileset sources_1] $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_3/clk_wiz_3.xci]
launch_runs clk_wiz_3_synth_1 -jobs $nproc
wait_on_run clk_wiz_3_synth_1
export_simulation -of_objects [get_files $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.srcs/sources_1/ip/clk_wiz_3/clk_wiz_3.xci] -directory $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.ip_user_files/sim_scripts -ip_user_files_dir $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.ip_user_files -ipstatic_source_dir $PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.ip_user_files/ipstatic -lib_map_path [list {modelsim=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/modelsim} {questa=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/questa} {xcelium=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/xcelium} {vcs=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/vcs} {riviera=$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.cache/compile_simlib/riviera}] -use_ip_compiled_libs -force -quiet

# Avoid primary clock re-definition from clock-wizard packaged XDCs.
foreach wiz_name {clk_wiz_0 clk_wiz_1 clk_wiz_2 clk_wiz_3} {
    set wiz_xdc [get_files -quiet "$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.gen/sources_1/ip/$wiz_name/$wiz_name.xdc"]
    if {[llength $wiz_xdc] > 0} {
        set_property USED_IN_SYNTHESIS false $wiz_xdc
        set_property USED_IN_IMPLEMENTATION false $wiz_xdc
    }
}

add_files -norecurse $SRC_FILES
add_files -fileset constrs_1 -norecurse $CONSTR_PATH
update_compile_order -fileset sources_1
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs $nproc
wait_on_run impl_1

source [file join [file dirname [info script]] check_build.tcl]
check_build_result "$PROJECT_PATH/$PROJECT_NAME/$PROJECT_NAME.runs/impl_1/runme.log"
