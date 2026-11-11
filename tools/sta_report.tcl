# sta_report.tcl - extra timing report, run by TimeQuest after every compile
# (TIMEQUEST_REPORT_SCRIPT in files.qip).
#
# Writes output_files/dec_vax_timing.txt, the one file that says how a
# compile went:
#   - a summary: the worst setup and hold slack inside this core's clock
#     (clk_sys, 50 MHz) at EVERY operating condition Quartus has a model for
#     (slow and fast silicon, hot and cold), and whether timing is met:
#     cold silicon can be the slower one, and the fast corners are where
#     hold margins shrink. (The MiSTer template analyses one slow corner
#     only; dec_vax.qsf turns the multi-corner analysis on, and this
#     summary does not depend on that setting.)
#   - what the fitter used (the fit summary) and every block RAM it built,
#     with its size, its mode and what it does when a location is read
#     while it is written; the RAMs the synthesis did not infer, if any,
#     and the core's registers the synthesis found stuck at a value and
#     removed (a register it removes and the simulation needs would be a
#     difference between the two);
#   - the worst setup and hold paths of the whole design (these are usually
#     in the MiSTer framework's video scaler, which has its own clock),
#   - the worst paths inside clk_sys, the three worst node by node,
#   - the SDRAM read-data and command/address paths at every operating
#     condition.
# Any error is reported as a warning and never stops the compile.

proc dv_report {f args} {
    if {[catch {eval report_timing $args -file $f -append} err]} {
        post_message -type warning "tools/sta_report.tcl: $err"
    }
}

# the worst slack of one kind (setup, hold) between two clocks, or "n/a"
proc dv_slack {kind clk} {
    set s "n/a"
    catch {
        foreach_in_collection p [get_timing_paths -$kind -npaths 1 \
                                     -from_clock $clk -to_clock $clk] {
            set s [get_path_info $p -slack]
        }
    }
    return $s
}

# how many objects a collection holds (a plain list outside TimeQuest)
proc dv_size {c} {
    if {[catch {set n [get_collection_size $c]}]} { set n [llength $c] }
    return $n
}

# copy the lines of a report that match a pattern
proc dv_grep {out path pattern title {maxlen 420} {maxlines 400}} {
    puts $out ""
    puts $out "---- $title"
    if {[catch {set fh [open $path r]}]} {
        puts $out "     ($path not found)"
        return
    }
    set n 0
    while {[gets $fh line] >= 0} {
        if {[regexp -- $pattern $line]} {
            if {$n < $maxlines} { puts $out [string range $line 0 $maxlen] }
            incr n
        }
    }
    close $fh
    if {$n == 0} { puts $out "     (none)" }
    if {$n > $maxlines} { puts $out "     ... [expr {$n - $maxlines}] more" }
}

# the Fitter RAM Summary, one short line per RAM: the columns are found by
# their titles, so their order does not matter
proc dv_rams {out path} {
    puts $out ""
    puts $out "---- block RAMs as built ($path, Fitter RAM Summary):"
    puts $out "     name | mode | port A depth x width | port B depth x width | M10K blocks |"
    puts $out "     read during write: mixed ports, port A, port B"
    if {[catch {set fh [open $path r]}]} {
        puts $out "     ($path not found)"
        return
    }
    set want [list "Name" "Mode" "Port A Depth" "Port A Width" "Port B Depth" \
                  "Port B Width" "M10K blocks" "Mixed-Port Read-During-Write Mode" \
                  "Port A RDW Mode" "Port B RDW Mode"]
    set idx [list]
    set n 0
    while {[gets $fh line] >= 0} {
        set c0 [string index $line 0]
        if {![llength $idx]} {
            if {$c0 ne ";"} { continue }
            set cols [list]
            foreach c [split $line ";"] { lappend cols [string trim $c] }
            if {[lsearch -exact $cols "Mixed-Port Read-During-Write Mode"] >= 0 &&
                [lsearch -exact $cols "Name"] >= 0} {
                foreach w $want { lappend idx [lsearch -exact $cols $w] }
            }
            continue
        }
        if {$c0 eq "+"} { continue }
        if {$c0 ne ";"} { break }
        set cols [list]
        foreach c [split $line ";"] { lappend cols [string trim $c] }
        set v [list]
        foreach i $idx { lappend v [expr {$i >= 0 ? [lindex $cols $i] : "?"}] }
        # the name without the framework's part of the hierarchy and without
        # the megafunction's generated levels
        set name [lindex $v 0]
        regsub {^.*vax_system:vax\|} $name "" name
        regsub {\|altsyncram_[a-z0-9]+:auto_generated.*$} $name "" name
        puts $out [format "  %s | %s | %s x %s | %s x %s | %s | %s, %s, %s" $name \
                       [lindex $v 1] [lindex $v 2] [lindex $v 3] [lindex $v 4] \
                       [lindex $v 5] [lindex $v 6] [lindex $v 7] [lindex $v 8] \
                       [lindex $v 9]]
        incr n
    }
    close $fh
    if {$n == 0} { puts $out "     (no RAM Summary table found)" }
}

if {[catch {
    set f   [file join output_files dec_vax_timing.txt]
    set f2  [file join output_files dec_vax_timing_io.tmp]
    file delete -force $f2

    # the core PLL's output clock (glob: brackets in the full name would be
    # read as a character class)
    set sys [get_clocks -nowarn {emu|pll*divclk}]
    set dq  [get_ports -nowarn {SDRAM_DQ[*]}]
    set out [get_ports -nowarn {SDRAM_A[*] SDRAM_BA[*] SDRAM_DQ[*] SDRAM_DQML SDRAM_DQMH \
                                SDRAM_nCS SDRAM_nRAS SDRAM_nCAS SDRAM_nWE}]

    # ---- every operating condition: clk_sys slack, SDRAM paths (to f2)
    set corners [list]
    if {[catch {set corners [get_available_operating_conditions]}]} {
        set corners [list]
    }
    if {![llength $corners]} { set corners [list current] }
    set oc0 ""
    catch {set oc0 [get_operating_conditions]}
    set lines [list]
    set met 1
    set seen 0
    foreach oc $corners {
        if {$oc ne "current"} {
            if {[catch {set_operating_conditions $oc; update_timing_netlist} err]} {
                post_message -type warning "tools/sta_report.tcl: corner $oc: $err"
                continue
            }
        }
        if {[dv_size $sys]} {
            set ss [dv_slack setup $sys]
            set hs [dv_slack hold $sys]
            lappend lines [format "  %-22s setup %8s ns   hold %8s ns%s" $oc $ss $hs \
                               [expr {$oc eq $oc0 ? "   (the default corner)" : ""}]]
            if {[string is double -strict $ss]} { set seen 1; if {$ss < 0} { set met 0 } }
            if {[string is double -strict $hs]} { set seen 1; if {$hs < 0} { set met 0 } }
        }
        if {[dv_size $dq]} {
            dv_report $f2 -from $dq -setup -npaths 1 -detail summary \
                -panel_name "dec_vax: SDRAM read data, setup, $oc"
            dv_report $f2 -from $dq -hold -npaths 1 -detail summary \
                -panel_name "dec_vax: SDRAM read data, hold, $oc"
            dv_report $f2 -to $out -setup -npaths 1 -detail summary \
                -panel_name "dec_vax: SDRAM outputs, setup, $oc"
            dv_report $f2 -to $out -hold -npaths 1 -detail summary \
                -panel_name "dec_vax: SDRAM outputs, hold, $oc"
        }
    }
    # back to the corner the default analysis used
    if {$oc0 ne ""} {
        catch {set_operating_conditions $oc0; update_timing_netlist}
    }

    # ---- the summary, the fitter's resources, the RAMs
    set o [open $f w]
    puts $o "dec_vax: timing and resources of this compile"
    puts $o ""
    puts $o "Worst slack inside clk_sys (the core's 50 MHz clock), per operating condition:"
    foreach l $lines { puts $o $l }
    if {![llength $lines]} { puts $o "  (clk_sys not found)" }
    puts $o ""
    if {!$seen} {
        puts $o "clk_sys: no slack could be read; see the panels below."
    } elseif {$met} {
        puts $o "clk_sys: timing MET at every operating condition."
    } else {
        puts $o "clk_sys: timing NOT MET (negative slack above): the core cannot be"
        puts $o "trusted on the board, whatever the simulation says. The worst paths"
        puts $o "are listed below."
    }
    dv_grep $o [file join output_files dec_vax.fit.summary] {.} \
        "the fitter's summary (output_files/dec_vax.fit.summary)"
    dv_rams $o [file join output_files dec_vax.fit.rpt]
    dv_grep $o [file join output_files dec_vax.map.rpt] {[Uu]ninferred RAM|is uninferred} \
        "RAMs the synthesis did not infer (output_files/dec_vax.map.rpt)" 300 60
    dv_grep $o [file join output_files dec_vax.map.rpt] {vax_core:core.*; Stuck at} \
        "registers of the core removed as stuck (output_files/dec_vax.map.rpt)" 220 300
    puts $o ""
    close $o

    # ---- the paths
    dv_report $f -setup -npaths 10 -detail summary \
        -panel_name "dec_vax: worst setup paths (whole design)"
    dv_report $f -hold -npaths 10 -detail summary \
        -panel_name "dec_vax: worst hold paths (whole design)"
    if {[dv_size $sys]} {
        dv_report $f -setup -npaths 40 -detail summary -from_clock $sys -to_clock $sys \
            -panel_name "dec_vax: worst setup paths inside clk_sys"
        dv_report $f -setup -npaths 3 -detail path_only -from_clock $sys -to_clock $sys \
            -panel_name "dec_vax: the three worst setup paths inside clk_sys, node by node"
        dv_report $f -hold -npaths 10 -detail summary -from_clock $sys -to_clock $sys \
            -panel_name "dec_vax: worst hold paths inside clk_sys"
    }

    # ---- the SDRAM paths of every corner, after them
    if {[file exists $f2]} {
        set i [open $f2 r]
        set o [open $f a]
        fcopy $i $o
        close $i
        close $o
        file delete -force $f2
    }
} err]} {
    post_message -type warning "tools/sta_report.tcl: $err"
}
