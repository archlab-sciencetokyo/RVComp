# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025 Archlab, Science Tokyo
#
# check_build_result log_file
#   Prints red error/timing messages if the build had issues.
#   Call after wait_on_run impl_1.

proc check_build_result {log_file} {
    set RED   "\033\[1;31m"
    set GRN   "\033\[1;32m"
    set RESET "\033\[0m"

    # 1. Extract WNS from timing summary report
    set wns "?"
    set timing_not_met 0
    set rpt [glob -nocomplain -directory [file dirname $log_file] "*timing_summary_postroute_physopted.rpt"]
    if {[llength $rpt] > 0} {
        set rfh [open [lindex $rpt 0] r]
        set header 0
        while {[gets $rfh line] >= 0} {
            if {[string match "*Timing constraints are not met*" $line]} {
                set timing_not_met 1
            }
            if {$wns eq "?" && [string match "*WNS*TNS*" $line]} { set header 1; continue }
            if {$header} {
                # Use regexp instead of lindex to avoid Tcl list-parsing errors
                # on lines that contain special chars like { } (e.g. clock waveforms).
                # Match an optional leading sign and digits at the start of the line.
                if {[regexp {^\s*(-?[0-9]+\.[0-9]+)} $line -> val]} {
                    set wns $val
                    set header 0
                }
            }
        }
        close $rfh
    }

    # 2. Check for ERRORS in the log file
    set errors {}
    if {[file exists $log_file]} {
        set fh [open $log_file r]
        while {[gets $fh line] >= 0} {
            if {[string match -nocase "ERROR:*" $line]} { lappend errors $line }
        }
        close $fh
    }

    # 3. Check run status
    set progress [get_property PROGRESS [get_runs impl_1]]
    set status   [get_property STATUS   [get_runs impl_1]]

    # 4. Determine failure
    set failed 0
    if {$progress ne "100%"} { set failed 1 }
    if {$timing_not_met}     { set failed 1 }
    if {$wns ne "?" && $wns < 0} { set failed 1 }
    if {[llength $errors] > 0} { set failed 1 }

    # 5. Print result
    if {$failed} {
        puts "${RED}================================================================================${RESET}"
        if {$progress ne "100%"} {
            puts "${RED}  Error: Generating bitstream failed. (status: $status)${RESET}"
        }
        if {$wns ne "?" && $wns < 0} {
            puts "${RED}  Error: The design failed to meet the timing requirements. (WNS = $wns ns)${RESET}"
        } elseif {$wns ne "?"} {
            # failed for other reasons but WNS is available
            puts "${RED}  (WNS = $wns ns)${RESET}"
        }
        puts "${RED}================================================================================${RESET}"
        foreach e $errors { puts "${RED}$e${RESET}" }
        # Note: 'exit 1' removed per user request
    } else {
        puts "${GRN}Bitstream generation succeeded. (WNS = $wns ns)${RESET}"
    }
}
