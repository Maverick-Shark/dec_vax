#============================================================================
#  Timing constraints for the DEC VAX (r-vax) core.
#
#  sys/sys_top.sdc already creates the board clocks, separates the clock
#  groups and cuts the framework's quasi-static paths. What this file adds is
#  the SDRAM interface: the forwarded SDRAM clock and the I/O timing of the
#  chip. Everything inside the core is timed at the full 50 MHz.
#
#  The SDRAM part is guarded: if the PLL clock pin is not found (a different
#  Quartus version may name it differently) it is skipped with a warning in
#  the compile messages instead of failing the compile.
#============================================================================

derive_pll_clocks
derive_clock_uncertainty

# Set this to 0 to drop the SDRAM I/O constraints and fall back to the usual
# MiSTer arrangement, where the SDRAM pins are left to their I/O registers.
set constrain_sdram 1

#----------------------------------------------------------------------------
# SDRAM
#
# SDRAM_CLK is clk_sys inverted, produced by a DDR output register, so the
# chip's clock edges are the clk_sys FALLING edges.
#
# Outputs (commands, address, write data) are registered on the clk_sys
# rising edge and sampled by the chip on the SDRAM_CLK rising edge half a
# clock (10 ns) later. TimeQuest's default relationship covers that.
#
# Inputs: with CAS latency 2 a read word is valid from tAC after one chip edge
# until tOH after the next one. rtl/mister/vax_sdram.v captures it on the
# clk_sys FALLING edge that coincides with that next chip edge, which is the
# middle of the window. TimeQuest's default relationship for this pair (launch
# on an SDRAM_CLK rising edge, latch on the clk_sys falling edge 20 ns later)
# is exactly that capture, so no multicycle is needed: -max is tAC, -min tOH.
# Expect several ns of slack on both setup and hold for SDRAM_DQ. A design
# that captured on the rising edge instead would show up here as a setup or
# hold failure on SDRAM_DQ - that is the check to look at after a compile.
#
# Device numbers (W9825G6KH-6 / AS4C32M16SB-6 class, CAS latency 2):
#   tSU 1.5 ns   tH 0.8 ns   tAC 6.0 ns   tOH 2.5 ns
#----------------------------------------------------------------------------
set clk_sys_pin [get_pins -nowarn -compatibility_mode \
    {*|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]

if {$constrain_sdram && [llength $clk_sys_pin] && [llength [get_ports -nowarn SDRAM_CLK]]} {

    create_generated_clock -name SDRAM_CLK -source $clk_sys_pin \
                           -invert [get_ports SDRAM_CLK]

    set sdram_out [get_ports -nowarn {SDRAM_A[*] SDRAM_BA[*] SDRAM_DQ[*] \
                                      SDRAM_DQML SDRAM_DQMH SDRAM_nCS \
                                      SDRAM_nRAS SDRAM_nCAS SDRAM_nWE SDRAM_CKE}]
    set sdram_dq  [get_ports -nowarn {SDRAM_DQ[*]}]

    set_output_delay -clock SDRAM_CLK -max  1.5 $sdram_out
    set_output_delay -clock SDRAM_CLK -min -0.8 $sdram_out

    set_input_delay  -clock SDRAM_CLK -max  6.0 $sdram_dq
    set_input_delay  -clock SDRAM_CLK -min  2.5 $sdram_dq

} else {
    post_message -type warning "dec_vax.sdc: SDRAM I/O constraints skipped (PLL clock pin not found)"
}

#----------------------------------------------------------------------------
# No other exceptions.
#
# Earlier versions relaxed the terminal's video pipeline (multicycle 2 and 4)
# and cut the paths from the OSD status bits, the SDRAM size and to the
# autostart counter. They covered short register-to-register paths that do
# not need the help, and some of them were wrong: a "-to" multicycle also
# relaxes the clock-enable (ce_pix) path, which must settle in one clock, and
# the font/attribute fetch registers take data that is only one or two clocks
# old, not four. A cut path from status[10] could even make "Run Memory Test"
# miss its trigger. output_files/dec_vax_timing.txt lists the worst clk_sys
# paths after each compile, so any path that does get tight shows up there.
#----------------------------------------------------------------------------
