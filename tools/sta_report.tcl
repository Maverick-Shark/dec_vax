# sta_report.tcl - extra timing report, run by TimeQuest after every compile
# (TIMEQUEST_REPORT_SCRIPT in files.qip).
#
# Writes output_files/dec_vax_timing.txt with:
#   - the worst setup and hold paths of the whole design (these are usually
#     in the MiSTer framework's video scaler, which has its own clock),
#   - the worst paths inside this core's clock (clk_sys, 50 MHz),
#   - the SDRAM read-data and command/address paths at EVERY operating
#     condition Quartus has a model for (slow and fast silicon, hot and
#     cold). The project analyses only the slow 85 C corner by default
#     (TIMEQUEST_MULTICORNER_ANALYSIS OFF in the MiSTer template); the fast
#     corners are where hold margins shrink, so they are checked here.
# Any error is reported as a warning and never stops the compile.

proc dv_report {f args} {
    if {[catch {eval report_timing $args -file $f -append} err]} {
        post_message -type warning "tools/sta_report.tcl: $err"
    }
}

if {[catch {
    set f [file join output_files dec_vax_timing.txt]
    report_timing -setup -npaths 10 -detail summary \
        -panel_name "dec_vax: worst setup paths (whole design)" -file $f
    dv_report $f -hold -npaths 10 -detail summary \
        -panel_name "dec_vax: worst hold paths (whole design)"

    # the core PLL's output clock (glob: brackets in the full name would be
    # read as a character class)
    set sys [get_clocks -nowarn {emu|pll*divclk}]
    if {[llength $sys]} {
        dv_report $f -setup -npaths 20 -detail summary -from_clock $sys -to_clock $sys \
            -panel_name "dec_vax: worst setup paths inside clk_sys"
        dv_report $f -hold -npaths 10 -detail summary -from_clock $sys -to_clock $sys \
            -panel_name "dec_vax: worst hold paths inside clk_sys"
    }

    set dq  [get_ports -nowarn {SDRAM_DQ[*]}]
    set out [get_ports -nowarn {SDRAM_A[*] SDRAM_BA[*] SDRAM_DQ[*] SDRAM_DQML SDRAM_DQMH \
                                SDRAM_nCS SDRAM_nRAS SDRAM_nCAS SDRAM_nWE}]
    if {[llength $dq]} {
        set corners [list]
        if {[catch {set corners [get_available_operating_conditions]}]} {
            set corners [list]
        }
        if {![llength $corners]} { set corners [list current] }
        set oc0 ""
        catch {set oc0 [get_operating_conditions]}
        foreach oc $corners {
            if {$oc ne "current"} {
                if {[catch {set_operating_conditions $oc; update_timing_netlist} err]} {
                    post_message -type warning "tools/sta_report.tcl: corner $oc: $err"
                    continue
                }
            }
            dv_report $f -from $dq -setup -npaths 1 -detail summary \
                -panel_name "dec_vax: SDRAM read data, setup, $oc"
            dv_report $f -from $dq -hold -npaths 1 -detail summary \
                -panel_name "dec_vax: SDRAM read data, hold, $oc"
            dv_report $f -to $out -setup -npaths 1 -detail summary \
                -panel_name "dec_vax: SDRAM outputs, setup, $oc"
            dv_report $f -to $out -hold -npaths 1 -detail summary \
                -panel_name "dec_vax: SDRAM outputs, hold, $oc"
        }
        # back to the corner the default analysis used
        if {$oc0 ne ""} {
            catch {set_operating_conditions $oc0; update_timing_netlist}
        }
    }
} err]} {
    post_message -type warning "tools/sta_report.tcl: $err"
}
