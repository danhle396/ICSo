# =============================================================================
# CE2031 Project 23 - Traffic Light Controller FSM with Emergency Override
# Quartus II flow of the single project de2_traffic (PLAN 5.3)
#   cd quartus
#   quartus_sh -t run_quartus.tcl > ..\logs\quartus_compile.log
#
#   1. Full compile three times, one per FSM encoding (STATE_MACHINE_PROCESSING):
#        SEQUENTIAL (binary) -> ..\logs\enc_binary\
#        GRAY                -> ..\logs\enc_gray\
#        ONE-HOT             -> ..\logs\enc_onehot\
#      The last one is the hand-in version: output_files\de2_traffic.sof and
#      the .qsf keep ONE-HOT.
#   2. TimeQuest on that fit, into ..\logs\timing\
#        fmax.rpt, fmax_fast.rpt     Fmax summary, Slow / Fast Model
#        datasheet.rpt               tsu / th / tco of the pins
#        setup.rpt, setup_path.rpt   worst setup paths, worst one in full
#        hold.rpt, recovery.rpt, removal.rpt
#        setup_10ns.rpt, setup_10ns_path.rpt
#                                    same fit checked against a 10 ns clock
#                                    (de2_traffic_10ns.sdc): the 100 MHz target
# =============================================================================
load_package flow

cd [file dirname [file normalize [info script]]]
set rev  de2_traffic
set logs [file normalize "../logs"]

proc compile_enc {enc tag} {
    global rev logs
    post_message "==== STATE_MACHINE_PROCESSING = $enc ($tag) ===="
    project_open $rev -revision $rev
    set_global_assignment -name STATE_MACHINE_PROCESSING $enc
    export_assignments
    set fail [catch {execute_flow -compile} msg]
    project_close
    if {$fail} { error "compilation ($tag) failed: $msg" }
    set out [file join $logs enc_$tag]
    file mkdir $out
    foreach kind {flow map fit sta} {
        file copy -force "output_files/$rev.$kind.rpt" "$out/$rev.$kind.rpt"
    }
    foreach kind {map fit sta} {
        if {[file exists "output_files/$rev.$kind.summary"]} {
            file copy -force "output_files/$rev.$kind.summary" "$out/$rev.$kind.summary"
        }
    }
}

foreach {enc tag} {SEQUENTIAL binary GRAY gray ONE-HOT onehot} {
    compile_enc $enc $tag
}

# ---- Detailed timing of the hand-in version (ONE-HOT) ------------------------
set out [file normalize "$logs/timing"]
file mkdir $out
set f [open "$out/sta_cmds.tcl" w]
puts $f "project_open $rev -revision $rev"
puts $f "create_timing_netlist"
puts $f "read_sdc"
puts $f "update_timing_netlist"
puts $f "report_clock_fmax_summary -file {$out/fmax.rpt}"
puts $f "report_datasheet -file {$out/datasheet.rpt}"
puts $f "report_timing -setup -npaths 10 -detail summary -file {$out/setup.rpt}"
puts $f "report_timing -setup -npaths 1 -detail full_path -file {$out/setup_path.rpt}"
puts $f "report_timing -hold -npaths 5 -detail summary -file {$out/hold.rpt}"
puts $f "report_timing -recovery -npaths 5 -detail full_path -file {$out/recovery.rpt}"
puts $f "report_timing -removal -npaths 5 -detail summary -file {$out/removal.rpt}"
puts $f "delete_timing_netlist"
puts $f "create_timing_netlist -fast_model"
puts $f "read_sdc"
puts $f "update_timing_netlist"
puts $f "report_clock_fmax_summary -file {$out/fmax_fast.rpt}"
puts $f "delete_timing_netlist"
puts $f "create_timing_netlist"
puts $f "read_sdc de2_traffic_10ns.sdc"
puts $f "update_timing_netlist"
puts $f "report_timing -setup -npaths 10 -detail summary -file {$out/setup_10ns.rpt}"
puts $f "report_timing -setup -npaths 1 -detail full_path -file {$out/setup_10ns_path.rpt}"
puts $f "delete_timing_netlist"
puts $f "project_close"
close $f
exec [file join $quartus(binpath) quartus_sta] -t "$out/sta_cmds.tcl"
file delete "$out/sta_cmds.tcl"
post_message "done: output_files\\$rev.sof (ONE-HOT), ..\\logs\\enc_*, ..\\logs\\timing"
