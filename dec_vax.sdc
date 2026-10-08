derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
# SDRAM_CLK is clk_sys inverted (altddio_out); read data is captured on the
# falling edge (vax_sdram.v), so the SDRAM I/O paths are left to the fast I/O
# registers set in sys/sys.tcl.
