# DEC VAX (r-vax) for MiSTer

Port of [r-vax](README.md), Anders Magnusson's VAX CPU in Verilog, to the
MiSTer FPGA platform (Terasic DE10-Nano).

**Status: milestone 1 — the system runs VAX programs.** It boots into the r-vax
hardware console monitor. Programs are loaded from the OSD, and an 80x30
terminal on HDMI/VGA with a USB keyboard serves as the console. VMS cannot run
yet: the CPU has no MMU, no F/D floating point, no decimal instructions and no
disk controller. See *Limitations*.

## What the core contains

| Block | File | Notes |
|---|---|---|
| VAX CPU | `rtl/cpu.v` + `rtl/*.v` (r-vax) | Microcoded base instruction set; microcode ROMs in `rtl/uc-*.hex` |
| Memory | `rtl/mister/vax_sdram.v` | 32 MB on the MiSTer SDRAM module, 50 MHz, CL2 |
| System glue | `rtl/mister/vax_core.v` | Replaces `sbi.v`: CPU, alignment unit (`vcache.v`), SBI/UBA/MBA register stubs, loader port |
| Console terminal | `rtl/mister/vt_term.v`, `vt_font.v` | 80x30 text, 640x480, VT100 subset, DEC line drawing, bold and reverse video |
| Keyboard | `rtl/mister/vax_kbd.v` | USB keyboard to ASCII; US or Spanish layout, cursor keys, PF1-PF4 |
| Integration | `rtl/mister/vax_system.v`, `dec_vax.sv` | HPS loader, autostart, UART console, beeper, `emu` top level |

The console serial lines of r-vax (`tto_tx` / `tti_rx`, 8N1) stay as serial
lines inside the FPGA. Their speed is 115200 baud (`CLKPERBIT=434` in
`files.qip`).

## Building

1. Use Quartus Prime Lite **17.0.2** or **17.1** (the MiSTer standard is
   17.0.x; 17.1 also works). The device is 5CSEBA6U23I7.
2. Open `dec_vax.qpf` and run *Start Compilation*, or run
   `quartus_sh --flow compile dec_vax` from the command line.
3. The result is `output_files/dec_vax.rbf`. Copy it to the SD card as
   `/media/fat/_Computer/DEC_VAX_yyyymmdd.rbf`.

Do not edit anything under `sys/`. It is the unmodified MiSTer framework from
Template_MiSTer. When Quartus 17.1 saves the project, it rewrites the
`LAST_QUARTUS_VERSION` line in `dec_vax.qsf`. That change is harmless.

## Using it

At power-up the CPU is halted in the r-vax **hardware console monitor**. The
monitor prints the halt code and a `>` prompt.

### OSD

| Option | Meaning |
|---|---|
| Load Program | Loads a `.BIN`/`.EXE` image into RAM at *Load Address*. The CPU is held in reset while loading |
| Load Address | `0x00001000` (default), `0x00000000`, `0x00000200`, `0x00010000` |
| Autostart | After a load, types `FR<address><CR>G` into the monitor, which sets PC = load address and starts the program |
| Text Color | Green / Amber / White phosphor |
| Keyboard | US or ES (Spanish) layout |
| UART Console | The console is always copied to the MiSTer UART (`/dev/ttyS1` in Linux). When this option is *On*, input from the UART is also accepted |
| Reset | Resets the CPU and clears the screen. RAM keeps its contents |

### Console monitor commands

Commands are `<hex number><command letter>`. They use **uppercase only**.

| Command | Action |
|---|---|
| `nnnn/` or `nnnnP` | Open the physical memory longword at `nnnn`. The monitor prints its value. Type a new hex value and Enter to write it, or press Enter alone to leave it unchanged |
| `nV` | Open a virtual memory longword (same as physical; there is no MMU yet) |
| `nR` | Open general register `n` (`FR` = PC, `ER` = SP) |
| `nI` | Open internal processor register `n` (IPR) |
| `G` | Continue execution at the current PC |
| `S` | Execute one instruction, then return to the monitor |

Example: `FR` `1000` Enter, then `G`, runs a program loaded at 0x1000.

### Test program

`software/hello.py` builds `hello.bin` (`python3 software/hello.py
software/hello.bin`). Copy it to `/media/fat/games/DEC_VAX/`, then load it
with the default address and Autostart on. It draws a box with DEC line
drawing, prints `SUM 1..100 = 5050`, `MOVC3 OK`, `42` and reverse and bold
text, then halts back to the monitor.

## Memory map

| Physical address | Contents |
|---|---|
| `0x00000000-0x01FFFFFF` | 32 MB RAM (SDRAM) |
| `0x20000000-...` | SBI adapter, DW780 (TR3) and RH780 (TR8) register stubs, as in `sbi.v` |
| other | No response; the bus times out into a machine check |

The console is accessed through IPRs `RXCS`/`RXDB`/`TXCS`/`TXDB` (0x20-0x23).
The interval clock (ICCS/NICR/ICR) and TODR are implemented in `intclk.v`.

## Limitations (what blocks VMS)

- No memory management: `MAPEN` is ignored, there are no TB or page tables, and
  no restart after a translation fault.
- No F/D/G/H floating point, no packed decimal, and several string instructions
  are missing. Unimplemented opcodes halt the CPU.
- No mass storage: an MSCP/UDA50 or Massbus disk emulation over the MiSTer SD
  interface (`sd_lba`/`sd_rd`) is the next big step.
- The terminal does not yet implement scrolling regions (`ESC [ t;b r`),
  insert/delete line, or answerback (`ESC [ c`, `ESC [ 6 n`).

## Simulation (Verilator 5)

```
make -C sim                                   # full system: CPU + SDRAM model + terminal
sim/obj/Vtb_top software/hello.bin 0 "1000P~"   # load, autostart, then type 1000P <Enter>
make -C sim unit && (cd sim && python3 term_test.py 40)   # terminal vs pyte VT100 reference
```

`tb.cpp` acts as `hps_io`: it downloads the file through the ioctl port and
sends PS/2 events. It then prints the terminal text RAM and writes one video
frame (`frame.ppm`). `term_test.py` compares `vt_term` with the
[pyte](https://github.com/selectel/pyte) emulator (`pip install pyte`) on
fixed and random escape-sequence streams.

## Regenerating generated files

- Microcode ROMs: in `rtl/`, `rm -f uc-*.hex && awk -f mkucode.awk`. The
  script reads `ucode.def`, `ucode.v` and `aluops.vh`.
- Font ROM: `python3 tools/mkfont.py spleen-8x16.bdf rtl/mister/vt_font.v`.
- r-vax source fixes: `python3 tools/patch_rvax.py` (idempotent). It applies
  `always @*` to four incomplete sensitivity lists and sets the `rtl/` path of
  the microcode ROMs under `` `define MISTER``.

## Credits and licenses

- r-vax VAX CPU: (c) 2021 Anders Magnusson, BSD 2-Clause (`LICENSE`).
- MiSTer framework (`sys/`) and `dec_vax.sv`: from Template_MiSTer, GPL v2 or later.
- Terminal font: Spleen 8x16 (c) Frederic Cambus, BSD 2-Clause
  (`rtl/mister/LICENSE.spleen`).
- MiSTer glue (`rtl/mister/`, `tools/`, `sim/`, `software/`): BSD 2-Clause.
