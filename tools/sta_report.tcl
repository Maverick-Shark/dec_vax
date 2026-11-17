# sta_report.tcl - extra compile report, run by TimeQuest after every compile
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
#   - the netlist against the source: the simulation runs the Verilog, the
#     board runs what Quartus made of it, and the two are not always the
#     same thing. In the M8 compiles Quartus 17.1 left one bit of the
#     translation buffer's write data unconnected (see rtl/mmu.v); the
#     simulation passed every test and the board failed the first one with
#     memory management on. The only trace was one line in the map report:
#     the register that fed that bit, removed for "Lost fanout". So the
#     report checks the source of each data input of the translation
#     buffer's RAM in the timing netlist, and lists every register of the
#     core removed for lost fan-out that is not on the list of expected
#     ones below. Both are said in the summary.
#   - what the fitter used (the fit summary) and every block RAM it built,
#     with its size, its mode and what it does when a location is read
#     while it is written; the RAMs the synthesis did not infer, if any,
#     and the core's registers the synthesis found stuck at a value and
#     removed;
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
    # (the mixed-port column is "Mixed Width RDW Mode" in Quartus 17.1 and
    # "Mixed-Port Read-During-Write Mode" elsewhere: any title "Mixed*")
    set want [list "Name" "Mode" "Port A Depth" "Port A Width" "Port B Depth" \
                  "Port B Width" "M10K blocks" "Mixed*" \
                  "Port A RDW Mode" "Port B RDW Mode"]
    set idx [list]
    set n 0
    while {[gets $fh line] >= 0} {
        set c0 [string index $line 0]
        if {![llength $idx]} {
            if {$c0 ne ";"} { continue }
            set cols [list]
            foreach c [split $line ";"] { lappend cols [string trim $c] }
            if {[lsearch -exact $cols "Port A Depth"] >= 0 &&
                [lsearch -exact $cols "Name"] >= 0} {
                foreach w $want { lappend idx [lsearch -glob $cols $w] }
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

# Registers of the core that the synthesis removed because nothing used
# them: the "Lost fanout" lines of the map report's "Registers Removed
# During Synthesis" table. Three kinds are normal: the binary state
# registers of a state machine Quartus re-encoded one-hot (name~n), states
# of such a machine that nothing looks at (name.STATE), and the bits listed
# here, each with the reason why nothing reads it. Anything else is a
# register the Verilog uses and the netlist has not got - or one more bit
# that the Verilog does not need either, which then belongs on this list.
# Returns the text for the report and the list of the unexpected ones.
proc dv_lost {path} {
    # register (after vax_system:vax|), the bits nothing reads (empty for a
    # one-bit register), why
    set expected [list \
        {vax_core:core|mmu:mmu|sbr} {30 31} \
            "SBR<31:30>: the page table walk uses physical addresses <29:0>" \
        {vax_core:core|vax_io:io|adr_r} {0 1 30 31} \
            "the CPU port's latch: nothing past it uses address bits <1:0>, <31:30>" \
        {vax_core:core|vax_io:io|vax_uba:uba0|u_acl} {} \
            "ACLO on the Unibus: no device on this Unibus asks for it" \
        {vt_term:term|frame} {5} "top bit of the cursor's blink counter" \
        {vax_selftest:selftest|pace} {6 7} "top bits of the banner's pace counter"]
    set txt [list]
    set bad [list]
    if {[catch {set fh [open $path r]}]} {
        return [list [list "     ($path not found)"] $bad]
    }
    set in 0
    set nfsm 0
    while {[gets $fh line] >= 0} {
        if {!$in} {
            if {[string match "; Registers Removed During Synthesis*" $line]} { set in 1 }
            continue
        }
        if {[string match "; Removed Registers Triggering*" $line] ||
            [string match "; General Register Statistics*" $line]} { break }
        if {![regexp {^; (.*vax_system:vax\|\S+) +; Lost fanout} $line -> name]} { continue }
        regsub {^.*vax_system:vax\|} $name "" short
        if {[regexp {~[0-9]+$} $short] || [regexp {\.[A-Za-z0-9_]+$} $short]} {
            incr nfsm
            continue
        }
        # the register and its bits: name[3,5..7] -> name, 3 5 6 7
        set base $short
        set bits [list]
        if {[regexp {^(.*)\[([0-9,.]+)\]$} $short -> base blist]} {
            foreach r [split $blist ","] {
                if {[regexp {^([0-9]+)\.\.([0-9]+)$} $r -> lo hi]} {
                    for {set i $lo} {$i <= $hi} {incr i} { lappend bits $i }
                } else {
                    lappend bits $r
                }
            }
        }
        set why ""
        foreach {reg ok reason} $expected {
            if {$reg ne $base} { continue }
            set all 1
            foreach i $bits { if {[lsearch -exact $ok $i] < 0} { set all 0 } }
            if {$all && ([llength $bits] || ![llength $ok])} { set why $reason }
        }
        if {$why ne ""} {
            lappend txt [format "  %-46s expected: %s" $short $why]
        } else {
            lappend bad $short
            lappend txt [format "  %-46s <<< NOT EXPECTED" $short]
        }
    }
    close $fh
    if {!$in} {
        lappend txt "     (no \"Registers Removed During Synthesis\" table found)"
    } else {
        lappend txt "  and $nfsm left over from re-encoded state machines (name~n, name.STATE)"
    }
    return [list $txt $bad]
}

# A register's name as a pattern that matches it: the brackets of a bus
# index become "?", so that it does not matter how this Quartus reads them
proc dv_pat {name} {
    regsub -all {[][]} $name {?} name
    return $name
}

# The data inputs of the core's block RAMs in the timing netlist. A data
# input is a register inside a RAM block (...|ram_block1aN~porta_datain_regI).
# The translation buffer's RAM is checked input by input: each of its 40 data
# inputs must come from one bit of mmu:mmu|tb_wd, and each bit of tb_wd must
# drive exactly one of them. Which input holds which bit is the fitter's
# choice: it packs the 40 one-bit columns of the RAM into two 20-bit M10K
# blocks, named after the lowest bit each holds, and orders the columns as
# routing suits it (the read data comes out of the same column, so the order
# does not matter). For the other RAMs only the number of inputs with no
# path from a register is given (an input the Verilog ties to a constant has
# none, so that is not wrong in itself). Returns the text, and for the
# translation buffer "ok", "bad" or "unknown" with the list of what is wrong.
proc dv_ramins {} {
    set txt [list]
    set bad [list]
    set state unknown
    if {[catch {
        set filter {*vax_system:vax|*~port?_datain_reg*}
        set regs [get_registers -nowarn $filter]
        if {[get_collection_size $regs] == 0} {
            set regs [get_keepers -nowarn $filter]
        }
        set order [list]
        set ntot 0
        set nnone 0
        set tbn 0
        foreach_in_collection r $regs {
            set name [get_register_info -name $r]
            set ram $name
            regsub {\|ram_block[^|]*$} $ram "" ram
            regsub {\|altsyncram_[a-z0-9]+:auto_generated$} $ram "" ram
            regsub {^.*vax_system:vax\|} $ram "" ram
            regsub {^.*\|} $name "" pin
            if {![info exists tot($ram)]} {
                set tot($ram) 0
                set none($ram) 0
                lappend order $ram
            }
            incr tot($ram)
            incr ntot
            set paths [get_timing_paths -to [dv_pat $name] -setup -npaths 4]
            if {[get_collection_size $paths] == 0} {
                incr none($ram)
                incr nnone
            }
            if {[string match "*vax_core:core|mmu:mmu|*" $name]} {
                incr tbn
                # the bit of tb_wd that drives this input: one, and only one
                set srcs [list]
                set k -1
                set one 1
                foreach_in_collection p $paths {
                    set sn [get_node_info -name [get_path_info $p -from]]
                    regsub {^.*vax_system:vax\|vax_core:core\|} $sn "" sn
                    if {[lsearch -exact $srcs $sn] < 0} { lappend srcs $sn }
                    if {[regexp {^mmu:mmu\|tb_wd\[([0-9]+)\](~.*)?$} $sn -> j]} {
                        if {$k < 0} { set k $j } elseif {$k != $j} { set one 0 }
                    } else {
                        set one 0
                    }
                }
                if {![llength $srcs]} { set srcs [list "NOTHING"] }
                if {$one && $k >= 0} {
                    lappend drv($k) $pin
                    lappend tbl [list $k [format "      tb_wd\[%d\]%s -> %s" $k \
                        [string repeat " " [expr {2 - [string length $k]}]] $pin]]
                } else {
                    lappend tbl [list 99 [format "      %s -> %s   <<< WRONG" \
                        [join $srcs ", "] $pin]]
                    lappend bad "translation buffer RAM, input $pin: from [join $srcs {, }]"
                }
            }
        }
        if {$ntot == 0} {
            lappend txt "     (no RAM data input registers found in the netlist)"
        } elseif {$nnone == $ntot} {
            # not one path to any of them: the query, not the netlist
            lappend txt "     (no path found to any of the $ntot RAM data inputs: this query"
            lappend txt "     does not work here; nothing can be said)"
            set bad [list]
        } else {
            foreach ram $order {
                lappend txt [format "  %-58s %3d data inputs, %d with no path from a register" \
                                 $ram $tot($ram) $none($ram)]
            }
            lappend txt "  (an input the Verilog ties to a constant has no path; for the RAMs"
            lappend txt "  other than the translation buffer's that is all this says)"
            if {$tbn != 40} {
                lappend bad "translation buffer RAM: $tbn data inputs in the netlist, not 40"
            }
            # each bit of tb_wd drives exactly one input
            set nodrv [list]
            for {set i 0} {$i < 40} {incr i} {
                if {![info exists drv($i)]} {
                    lappend nodrv $i
                } elseif {[llength $drv($i)] > 1} {
                    lappend bad "translation buffer RAM: tb_wd\[$i\] drives [llength $drv($i)] inputs: [join $drv($i) {, }]"
                }
            }
            if {[llength $nodrv]} {
                lappend bad "translation buffer RAM: no input from tb_wd bit(s) [join $nodrv ,]"
            }
            if {[info exists tbl]} {
                lappend txt "  the translation buffer's RAM: each bit of tb_wd (tag<13:0>, pfn<20:0>,"
                lappend txt "  prot<3:0>, m) must drive exactly one data input; which one is the"
                lappend txt "  fitter's choice:"
                foreach l [lsort -integer -index 0 $tbl] { lappend txt [lindex $l 1] }
            }
            set state [expr {[llength $bad] ? "bad" : "ok"}]
        }
        # the 40 registers of the write data themselves
        set miss [list]
        for {set i 0} {$i < 40} {incr i} {
            set c [get_registers -nowarn "*vax_core:core|mmu:mmu|tb_wd?$i?"]
            if {[get_collection_size $c] == 0} { lappend miss $i }
        }
        if {[llength $miss]} {
            lappend txt "  mmu:mmu|tb_wd: bit(s) [join $miss ,] NOT IN THE NETLIST"
            lappend bad "mmu:mmu|tb_wd: bit(s) [join $miss ,] not in the netlist"
            set state bad
        } else {
            lappend txt "  mmu:mmu|tb_wd: all 40 bits in the netlist"
        }
    } err]} {
        lappend txt "     (the netlist could not be queried: $err)"
    }
    return [list $txt $state $bad]
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
    puts $o ""
    set lost [dv_lost [file join output_files dec_vax.map.rpt]]
    set rin  [dv_ramins]
    set tbst [lindex $rin 1]
    if {$tbst eq "ok"} {
        puts $o "Netlist, translation buffer RAM: each bit of tb_wd drives one data input."
    } elseif {$tbst eq "bad"} {
        puts $o "Netlist, translation buffer RAM: WRONG. The bitstream does not do what the"
        puts $o "Verilog says, whatever the simulation and the timing say:"
        foreach b [lindex $rin 2] { puts $o "  $b" }
    } else {
        puts $o "Netlist, translation buffer RAM: could not be checked (see below)."
        foreach b [lindex $rin 2] { puts $o "  $b" }
    }
    set nl [llength [lindex $lost 1]]
    if {$nl} {
        puts $o "Netlist, registers removed for lost fan-out: $nl NOT ON THE LIST of the"
        puts $o "expected ones (marked below). Each is a register the Verilog uses and the"
        puts $o "bitstream has not got - a difference between the board and the simulation"
        puts $o "- unless the Verilog does not need it either (then it belongs on the list"
        puts $o "in tools/sta_report.tcl):"
        foreach b [lindex $lost 1] { puts $o "  $b" }
    } else {
        puts $o "Netlist, registers removed for lost fan-out: only the expected ones."
    }
    puts $o ""
    puts $o "---- registers of the core removed for having no fan-out"
    puts $o "     (output_files/dec_vax.map.rpt, Registers Removed During Synthesis):"
    foreach l [lindex $lost 0] { puts $o $l }
    puts $o ""
    puts $o "---- data inputs of the core's block RAMs (timing netlist):"
    foreach l [lindex $rin 0] { puts $o $l }
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
