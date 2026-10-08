# r-vax: DEC VAX Verilog code.
This is an basic implementation of the DEC VAX cpu.  It was written by me for a way to learn verilog, hence not pretty.  I also assume it is quite incorrect in quite some places.

It implements the Vax basic instruction set and passes the **EVKAA.EXE** basic instruction set test program.

There are quite some parts missing; for example memory management and floating point instructions.

It runs on the Waveshare Open3S500E Spartan-3 board.  
Code for simulation in Verilator also exist and works.

## MiSTer port

This branch adds a MiSTer (DE10-Nano) version of r-vax: CPU, 32 MB SDRAM,
on-screen VT100-style console terminal and USB keyboard. See
[README_MiSTer.md](README_MiSTer.md).
