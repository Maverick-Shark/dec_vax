# DEC VAX (r-vax) for MiSTer

Port of [r-vax](README.md), Anders Magnusson's VAX CPU in Verilog, to the
MiSTer FPGA platform (Terasic DE10-Nano).

**Status: the core runs real VAX software.** It boots into the r-vax hardware
console monitor, runs programs loaded from the OSD, and **passes EVKAA V8.0,
DEC's own Hardcore Instruction Test**, on a DE10-Nano and in simulation of
the full MiSTer core.
It has **memory management** as the VAX 8600 does it - translation buffer,
page tables, protection, restartable faults, PROBE, LDPCTX/SVPCTX - checked
in simulation and on the board ([docs/MMU.md](docs/MMU.md)), and the 8600's
**privileged architecture**:
CHMK/CHME/CHMS/CHMU, BPT, XFC, trace, the arithmetic traps, the reserved
instruction and reserved addressing mode faults, HALT as a privileged
instruction, the 8600's halt codes and internal registers, and a console
halt (Ctrl+P or the OSD). **Every VAX instruction** is there: the integer
ones, the **packed decimal and long character string instructions**, which
the 8600 has in hardware (a small decimal unit does their arithmetic,
[docs/CIS.md](docs/CIS.md)), and the **floating point instructions in all
four formats, F, D, G and H**, with the octaword instructions and the
two-byte opcodes (a floating point unit, exactly rounded,
[docs/FPU.md](docs/FPU.md)); only PDP-11 compatibility mode is missing.
DEC's **VAX 8600 Diagnostic Supervisor** runs on the core with three of its
exercisers. In the full-system simulation **EVKAB**, the basic instruction
exerciser, passes all of its 161 tests, **EVKAC**, the floating point
exerciser, all of its 98, and **EVKAE**, the privileged architecture
exerciser, 10 of its 11; the other one needs PDP-11 compatibility mode,
which the 8600 has and the core does not yet (see *Running the Diagnostic
Supervisor and EVKAE*, *Running EVKAB* and *Running EVKAC*).
OpenVMS cannot run yet: there is no disk controller.
See *What is missing*, and [ROADMAP.md](ROADMAP.md) for the plan.

```
== r-vax / MiSTer   cache 16 KB   clock 50 MHz
== SDRAM module: 32 MB
== read phase 0123 = 0100  using 1
== memory test: PASS
00000000
>
```

## Contents

| Block | File | Notes |
|---|---|---|
| VAX CPU | `rtl/cpu.v` + `rtl/*.v` (r-vax) | Microcoded base instruction set |
| Microcode ROMs | `rtl/uc-*.hex`, `rtl/ucode.v` | 352 Kbit, forced into M10K block RAM |
| Memory management | `rtl/mmu.v` | 8600 translation buffer, page table walk, protection ([docs/MMU.md](docs/MMU.md)) |
| Decimal unit | `rtl/decunit.v` | Packed decimal arithmetic for the decimal string instructions ([docs/CIS.md](docs/CIS.md)) |
| Floating point unit | `rtl/fpunit.v` | F, D, G and H floating point, exactly rounded ([docs/FPU.md](docs/FPU.md)) |
| Cache | `rtl/mister/vax_cache.v` | 16 KB, M10K block RAM |
| Memory | `rtl/mister/vax_sdram.v` | 32 MB on the MiSTer SDRAM module |
| Bus and I/O stubs | `rtl/mister/vax_core.v` | SBI, DW780 (TR3), RH780 (TR8) registers |
| Power-on test | `rtl/mister/vax_selftest.v`, `vax_msg.v` | Memory test and banner |
| Console terminal | `rtl/mister/vt_term.v`, `vt_font.v` | 80x30, VT100 subset |
| Keyboard | `rtl/mister/vax_kbd.v` | USB keyboard, US or ES layout |
| Serial | `rtl/mister/vax_uart.v` | Internal console line and the MiSTer UART |
| Integration | `rtl/mister/vax_system.v`, `dec_vax.sv` | Loader, autostart, `emu` top level |

## Which console is this?

Two different things are both called "the console" on a VAX, and the core has
both.

**The console serial line.** On a real VAX-11/780 the operator's terminal hangs
off the console subsystem and the CPU reaches it through four internal
processor registers: `RXCS` (20h), `RXDB` (21h), `TXCS` (22h) and `TXDB` (23h),
with SCB vectors F8h and FCh. r-vax implements exactly that in `consrx.v` and
`constx.v`, as a real 8N1 serial line inside the FPGA. Software that runs on
the core - including EVKAA - talks to this and nothing else.

In this port the line runs at one bit per 17 clocks, about 2.9 Mbaud. It never
leaves the FPGA, so the usual 9600 or 115200 baud would only make the screen
crawl. The same characters are *also* re-serialised at a real 115200 baud onto
the MiSTer UART (`/dev/ttyS1` on the HPS side), through its own FIFOs, so you
can run `screen /dev/ttyS1 115200` on the MiSTer and get the same session over
the network. That FIFO holds 2 KB, so bursts much longer than a screenful at
full speed can still lose characters on the UART copy; the screen gets them
all.

In the other direction the keyboard, the UART and the autostart typist share a
256-byte FIFO that hands characters to the CPU **no faster than one every
200 us**. The r-vax receiver holds a single character, and at the line's own
speed the three bytes of a cursor or PF key would arrive 3.4 us apart - faster
than a VAX program can read them, so the second would overwrite the first.
200 us is still five times a real console's 9600 baud.

**The console monitor.** This is r-vax's own small hardware state machine
(`console.v`), the equivalent of a VAX-11/750's console microcode or a
MicroVAX's ODT. It owns the serial line while the CPU is halted, prints the
halt code and a `>` prompt, and lets you examine and deposit memory and
registers, single-step and start the CPU. It is *not* a DEC console program,
so it does not understand `EXAMINE`, `DEPOSIT`, `BOOT` or `>>>`; its commands
are the single letters in the table below.

What the terminal on the screen adds is only the display and the keyboard: an
80x30 VT100-subset terminal (`vt_term.v`) decodes the serial line and draws it,
and `vax_kbd.v` turns USB keystrokes back into characters. The CPU cannot tell
the difference between that and a real VT100 on a 25-pin plug.

## How the bus and the I/O adapters are built

The CPU has a single 32-bit synchronous master port with a strobe/acknowledge
handshake (the `STB`/`ACK` pair of a Wishbone-style bus, without the rest of
Wishbone). Everything hangs off it in a flat decode, and the slaves' read data
is simply OR-ed together, which is r-vax's own convention and is kept here.

```
cpu ── vcache ── mmu ──┬── vax_cache ── vax_sdram ── 32 MB SDRAM   (0000 0000-01FF FFFF)
     (aligner)         │
                       └── SBI / DW780 / RH780 register stubs       (2000 0000 and up)
```

* **`vcache.v`** despite its name is not a cache. It is the alignment unit: the
  VAX allows a longword operand to start on any byte, so this block turns one
  unaligned CPU access into one or two aligned longword bus cycles, and does
  the read-modify-write for byte and word stores. Everything below it sees
  nothing but full longword transfers.

* **`mmu.v`** translates virtual to physical addresses when `MAPEN` is set,
  with the VAX 8600's translation buffer (512 entries), and refuses accesses
  the page tables do not allow; the CPU then takes the fault and restarts the
  instruction. With mapping off it is a wire. See [docs/MMU.md](docs/MMU.md).

* **`vax_cache.v`** is the real cache, added by this port (see below).

* **The I/O adapters are stubs.** At 2000 0000h the core answers the SBI
  adapter configuration and silo registers, the DW780 Unibus adapter at TR 3
  and the RH780 Massbus adapter at TR 8, with the fixed values a VAX expects to
  read when it probes for them. There is no Unibus, no Massbus and no device
  behind any of it. An address that matches nothing gets no acknowledge, the
  CPU's 128-clock bus timer expires, and that becomes a machine check - halt
  code 2 on the console, which is how you can tell "nothing is there" from
  "something answered wrongly".

* **No DMA and no interrupts from I/O.** The only other bus master is the
  program loader and the power-on memory test, and both only run while the CPU
  is held in reset. The interval timer (`intclk.v`) and the console receive and
  transmit interrupts are wired through `intrpt.v` as on a real machine.

## Memory: the cache and the microcode in block RAM

Both now live in Cyclone V M10K block RAM, as you asked.

**Microcode.** The three ROMs in `ucode.v` are 512x64, 512x64 and 4096x72
bits, 352 Kbit in total (in r-vax the instruction table had 256 rows, the
argument store 256 and the step store 1024 words; memory management, the
decimal and string instructions, and then the two-byte opcodes and the
floating point instructions needed more). `tools/patch_rvax.py` marks them
`ramstyle = "M10K"`, because left to itself Quartus may decide to build a
ROM that size out of logic, which costs thousands of ALMs and ruins the
timing. The CPU register file and the IPR file are deliberately kept *out*
of block RAM (`ramstyle = "logic"`): they have several read ports and belong
in LUT RAM.

**Cache.** `vax_cache.v` is new. It sits between the aligner and the SDRAM:

* 16 KB, direct mapped, 16-byte lines (four longwords), physically indexed and
  tagged. It sits after the MMU and only ever sees physical addresses, so
  there is no aliasing to worry about.
* Write through, no write allocate, with a one-entry posted write buffer, so a
  write costs the CPU about two clocks instead of fourteen. A write that hits
  also updates the cached line, and a line fill is held back while the write
  buffer is draining, so a read can never pass an older write to the same
  address.
* Valid bits are cleared by walking the tag RAM after reset, which also covers
  the case where the HPS loader has written to memory behind the cache's back.
* Cost: 16 M10K for data, 2 for tags.

Measured on the core, in a full simulation of the MiSTer system:

| | Instructions | Time | CPI | MIPS at 50 MHz |
|---|---|---|---|---|
| `bench.bin` loop, cache on | 40 003 | 30 275 us | 37.8 | 1.32 |
| `bench.bin` loop, every access forced to miss | 40 003 | 62 797 us | 78.4 | 0.64 |
| EVKAA V8.0 full run | 7 882 724 | 6.19 s | 39.3 | 1.27 |

(`bench.bin` measures itself with the VAX interval clock and prints these
numbers on the console; the simulation runs it with 10 000 passes, the copy in
`software/` does 1 000 000, about 3 seconds.) The cache is worth **2.1x** on
that loop, and its hit rate on EVKAA is 99.4 %. What is left
is the CPU itself: r-vax is a multicycle design that walks a long state machine
for every operand specifier, so about 40 clocks per instruction is its natural
speed, not a memory problem. For scale, a real VAX-11/780 is 1 VUP, roughly
0.5 MIPS, so the core already runs at about 2.4 times the machine it imitates.

The cache size is the `CACHEIDX` macro in `files.qip` (10 = 1024 lines = 16 KB).
The device has 553 M10K blocks and the whole core uses about 70, so there is
room to go much larger if it ever pays off.

## Memory: the SDRAM module

The controller drives one 32 MB window and **works on every MiSTer SDRAM
module - 32, 64 or 128 MB** - without a rebuild.

All of those modules present at least 13 row bits, 4 banks and 9 column bits on
the chip selected by `SDRAM_nCS = 0`, which is exactly the 32 MB the core uses.
A 64 MB module has a larger chip with a 10th column bit; a 128 MB module is two
such chips whose chip selects are wired in opposite polarity, so `nCS` picks
between them. Using more than 32 MB would mean driving that extra column bit,
or toggling `nCS` per access, and a VAX-11/780 could not address more than
32 MB of physical memory anyway, so the core deliberately stays inside chip 0's
first 32 MB.

The banner line `== SDRAM module:` is what the MiSTer main program reports
through `hps_io` (`sdram_sz`), which arrives some time after the core starts;
the memory test waits up to one second for it. It is informational only - the
controller drives the same 32 MB on every module and never uses the value. If
the main program has no size to report, the banner says `not reported by the
HPS`. That is not an error, and it does not mean the module is missing: the
memory test is what tells you whether the module works.

Addressing, with the word address `WA[23:0]`:

    column = WA[8:0]      bank = WA[10:9]      row = WA[23:11]

One row holds 1 KB, so a 16-byte cache line never crosses a row boundary. The
mode register is the one r-vax used on its own board: CAS latency 2, burst of
2, sequential, bursts on writes too. A cache line fill is four READs of two
words, issued every other clock in the same open row (the last one with
auto-precharge), so eight words stream back without a gap. A write is one
WRITE of two words with byte masks and auto-precharge. ACTIVE to READ/WRITE is
2 clocks (40 ns), refresh is every 333 clocks.

**Byte masks on A11/A12.** On some modules - the 128 MB ones among them - the
chips' `DQML`/`DQMH` inputs are not wired to the FPGA's `SDRAM_DQML`/`DQMH`
pins but to the address lines A11 and A12, which the chips ignore in READ and
WRITE commands; MiSTer's own memory test drives them that way. So the
controller puts each write's byte masks on both: on `DQML`/`DQMH`, and on A11
(low byte) and A12 (high byte) in the WRITE cycle and in the cycle of its
second word; in every other cycle that moves data A12:A11 are 00, since a read
is never masked. Until this was done, a byte or word write on such a module
wrote the whole 16 bits: the memory test, which writes longwords, passed, but
every program the OSD loaded (byte by byte) came out corrupted. `make -C sim
dqma` builds the full-system model with the masks taken from A11/A12; `mmutest.bin`
and EVKAA pass on it, and fail with the old controller at the first load.

**Read data capture.** `SDRAM_CLK` is `clk_sys` inverted (a DDR output
register), so the chip's clock edges are our *falling* edges. With CAS latency
2 a read word is valid from about 6 ns after one chip edge until about 3 ns
after the next; seen from inside the FPGA, with the time the forwarded clock
needs to reach the chip, that window is centred on a `clk_sys` **falling** edge
and the rising edges either side of it fall on its borders. The controller
therefore captures `SDRAM_DQ` on the falling edge, in one register that nothing
else reads, and uses it on the next rising edge.

This is how the first version of this port did it, and that version ran
`hello.bin` and EVKAA on the board. The second version moved the capture to the
rising edge - outside the window - and failed the memory test on the board
while passing in simulation, because the simulation model was too optimistic
about when the data is valid. Both are fixed: the controller is back on the
falling edge (and the board now passes), and `sim/sdram_model.v` shows the data
only around the falling edge, so a rising-edge capture fails in simulation
exactly as it did on the board (checked both ways: the first version passes on
the new model, the rising-edge version fails it with the same `FAIL` the board
printed).

On top of that the power-on test calibrates which falling edge to use - see
*The power-on memory test* below.

The compile of this version confirms it with real numbers. TimeQuest, slow
85 C model, `SDRAM_DQ` into the `dq_n` registers (packed into the I/O cells):
**setup slack +5.8 ns, hold slack +8.4 ns**. From the same report, the data
window at the register runs from about 6 ns before the falling edge to 8.4 ns
after it; the rising edge 10 ns later, where the second version sampled, is
outside it. (That version's compile showed -7.177 ns on these paths, but that
number was TimeQuest checking the rising edge *before* the window - its .sdc
did not tell TimeQuest which edge the design really used. Either way, there
was no rising edge that works at 50 MHz.)

**Which controller is this, and why not MiSTer's `sdram.sv`?** All versions
use `rtl/mister/vax_sdram.v`, written for this port. Version 1 did one longword
per access, the way r-vax's own `rtl/sdram.v` does; the current one fetches a
whole cache line per access. r-vax's original controller samples on the third
rising edge after the READ, which only works on its Spartan-3E board because it
adds an input delay of nine IBUF steps to push the data into that edge's
window. Sorgelig's generic MiSTer `sdram.sv` also samples on the third rising
edge after the READ (CAS latency 2, `data_ready_delay`), the same point as
the second version of this port - it is written for a clock of about 100 MHz,
where that edge does sit in the window. At 50 MHz it does not, as that version
showed on
the board. Using `sdram.sv` would mean running it at about 100 MHz in a second
clock domain, with one 16-bit access per request (eight accesses of about
90 ns for each 16-byte cache line, against one burst of about 280 ns here), and
it would still address 32 MB through chip 0 only. With this board's own numbers
from the timing report, its sampling edge at 100 MHz has about 1 ns of setup
margin in the slow corner, against 5.8 ns for the falling edge at 50 MHz.

**The 2 MB SRAM on your dual module is not used.** Nothing in the core needs it:
32 MB of SDRAM is far more memory than the machine can address, and the cache is
faster than the SRAM would be. If a later milestone makes it worth using - the
most likely candidate is a disk track buffer - I will ask you first.

## Clocking

One clock domain: **`clk_sys` = 50 MHz**, from the core PLL, driving the CPU, the
cache, the SDRAM controller, the terminal and both UARTs. `CLK_VIDEO` is the
same 50 MHz with `CE_PIXEL` every second clock, giving a 25 MHz pixel clock and
a 640x480 at 59.5 Hz frame.

50 MHz is what r-vax's own timing constants assume (`intclk.v` divides it to a
microsecond tick, and the original board ran at 50 MHz too). The divider had
an off-by-one: it counted 51 clocks per microsecond, so the interval clock and
the time-of-year clock ran 2 % slow. `tools/patch_rvax.py` corrects it to 50
(and the 10 ms TODR divider to exactly 10 000 microseconds).

The logic still has room to spare with the floating point unit. The
compile of milestone 7 (Quartus 17.1, 5CSEBA6U23I7) reports +1.911 ns of
setup slack on `clk_sys` at 50 MHz in the slow 1100 mV 100 C model and
+5.897 ns in the fast one - about 55 MHz would still close - and the
summaries show positive slack for every clock (TNS 0). An earlier
milestone's compile had +2.4 ns.

TimeQuest still shows its folder in red: that is only the *Unconstrained
Paths* report (4 input and 50 output ports). They are the framework's own
pins - buttons, LEDs, VGA, audio, SD card - which `sys/sys_top.sdc` cuts
with `set_false_path` and gives no I/O delays, so TimeQuest lists them as
unconstrained in every MiSTer core. The core's own pins, the SDRAM, are
constrained (the `SDRAM_CLK` row of the summaries: +4.124 ns setup in the
slow model).

## Building

1. Quartus Prime Lite **17.0.2** or **17.1**. Device 5CSEBA6U23I7.
2. Open `dec_vax.qpf`, *Start Compilation* (or
   `quartus_sh --flow compile dec_vax`).
3. Copy `output_files/dec_vax.rbf` to the SD card as
   `/media/fat/_Computer/DEC_VAX_yyyymmdd.rbf`.

Do not edit anything under `sys/` - it is the unmodified MiSTer framework.

Resource estimate from an independent synthesis (Yosys `synth_intel_alm`,
Cyclone V, with the register files in logic as their `ramstyle` asks), with
the floating point unit: about 25 900 LUTs, 11 800 registers, 70 M10K and 20
multipliers (some 15 of the 112 DSP blocks). Of these the floating point
unit is about 9 700 LUTs, 3 100 registers and 16 multipliers, the decimal
unit about 5 000 LUTs and 750 registers, and the memory management about
2 750 LUTs, 1 550 registers and 8 M10K (before the memory management the
same synthesis gave 8 300 LUTs, 6 500 registers and 39 M10K, and with it
11 100 LUTs, 8 100 registers and 47 M10K). The Quartus compiles have
followed it: 33 % of the ALMs with the MiSTer framework after the memory
management, 41 % before the floating point unit, and with it (milestone 7)
**22 374 of 41 910 ALMs (53 %)**, 24 128 registers, 917 309 block memory
bits (16 %) and 48 of the 112 DSP blocks (43 %; the framework's video
scaler and audio filters use DSP blocks too).

### What `dec_vax.sdc` constrains

`sys/sys_top.sdc` already creates the board clocks, separates the clock groups
and cuts the framework's quasi-static paths, so the core file only adds its own:

* `SDRAM_CLK` as a generated clock, inverted from `clk_sys`, with the real
  device numbers for the SDRAM pins (`tSU` 1.5 ns, `tH` 0.8 ns, `tAC` 6.0 ns,
  `tOH` 2.5 ns). With the falling-edge capture, TimeQuest's default
  relationships are exactly the real ones, so no multicycle is needed, and the
  `SDRAM_DQ` setup and hold slacks in the timing report are meaningful. If the
  PLL clock pin is not found the SDRAM constraints are skipped with a
  **warning** in the compile messages.
* Nothing else. Earlier versions relaxed the terminal's video pipeline and cut
  the paths from the OSD settings; those paths are short and do not need it,
  and some of those exceptions were wrong (a `-to` multicycle also relaxes the
  `ce_pix` clock enable, which must settle in one clock). Everything inside the
  core is now timed at the full 50 MHz.

`tools/sta_report.tcl` runs after the timing analysis and writes
`output_files/dec_vax_timing.txt`: the worst paths of the whole design, the
worst paths inside `clk_sys`, and the SDRAM read and command paths at **every**
operating condition Quartus has a model for. The MiSTer project analyses only
the slow 85 C corner; the fast corners are where hold margins shrink, so they
are worth the extra minute.

**After every compile, check that TimeQuest does not print `Critical Warning:
Timing requirements not met`.** The worst paths of the whole design are in the
MiSTer framework's HDMI scaler (about +0.5 ns), not in this core.

## Using it

At power-up the core waits until the MiSTer has finished starting it - the main
program holds the core in reset (OSD status bit 0) while it loads the saved
settings, and the memory test starts 50 ms after that reset is released. It
then prints the banner and leaves the CPU halted in the console monitor.
(The previous build started the test as soon as the module size arrived, a few
microseconds *before* that reset, and the reset wiped the start of the banner:
`r cache 16 KB ...` instead of `== r-vax / MiSTer   cache 16 KB ...`.)

### OSD

| Option | Meaning |
|---|---|
| Load Program | Loads a `.BIN`/`.EXE` image into RAM at *Load Address*. The CPU is held in reset while loading, and that reset initializes it (see below), whatever was running |
| Load Address | `0x00001000` (default), `0x00000000`, `0x00000200`, `0x00010000` |
| Start Address | *Load address*, or `0x00000200` - DEC stand-alone diagnostics load at 0 and start at 200h |
| Autostart | After a load, types `FR<start address><CR>G` into the monitor |
| Text Color | Green / Amber / White phosphor |
| Keyboard | US or ES (Spanish) layout |
| UART Console In | Also accept keystrokes from `/dev/ttyS1`. Output always goes there |
| Power-on Memory Test | On by default |
| SDRAM Read Phase | *Calibrated* (default) uses what the memory test found; *Force 0..3* overrides it, for diagnosis only |
| Run Memory Test | Runs it again now. **This clears the first 64 KB of RAM** |
| Ctrl+P | *Halts the CPU* (default): Ctrl+P on the keyboard, or on the MiSTer UART when *UART Console In* is on, stops the running program as a VAX 8600 console does. *Is a character*: it goes to the program like any other key |
| Halt CPU (Ctrl+P) | Stops the running program now, like Ctrl+P |
| Reset | Resets the CPU and clears the screen. RAM keeps its contents |

### Loading and running a program

*Where* a file goes in memory is decided by the OSD option **Load Address**,
when you load it. The console's `FR` only sets the PC - where the CPU starts -
so it cannot move a program; `G` at an address where nothing was loaded runs
whatever is there (zeros are `HALT`, so you just get `00000006` back).

| Program | Load Address | Start Address | Then |
|---|---|---|---|
| `hello.bin`, `bench.bin`, `mmutest.bin` | `0x00001000` | Load address | *Load Program* |
| `evkaa.exe` | `0x00000000` | `0x00000200` | *Load Program*, Enter at `Hit any key` |
| `evkae_ds.bin` | `0x00000000` | `0x00000200` | *Load Program*, then `START` at `DS>` |

With *Autostart* = Yes the core types `FR<start>`, Enter and `G` for you right
after the load. With *Autostart* = No, do it by hand at the `>` prompt: `FR`,
then the start address and Enter, then `G`. The options are saved, so after
running EVKAA set them back before loading a `.bin`.

A program can be loaded at any moment, also while another one is running or
waiting at its prompt. The reset that holds the CPU during the load is a
*processor initialization* as the SRM defines it (chapter *System
Bootstrapping and Console*): PSL `041F0000` (kernel mode, interrupt stack,
IPL 1F), ASTLVL 4, SISR, MAPEN and PME 0, ICCS<IE> and <RUN> clear (the
interval clock stops), RXCS 0 and TXCS<IE> clear, and nothing left of the
instruction or the memory reference that was in progress. The OSD *Reset* does
the same. (In the first M7 build a load made while a program was running
could leave that program's last memory reference standing across the reset.
It completed once the console started the new program: a write could land in
the program just loaded, and its acknowledge was taken for the first
instruction fetch. The new program then stopped almost at once - EVKAB in
`Test 1` with `00000004`, EVKAC right after `Testing: _KA0`, mmutest in
`t01_xlate` with `00000006` - while the same program loaded after a power-up
ran correctly. The PSL, the interval clock, the console interrupt enables and
the IPRs above were also left as the previous program had them.)

`bench.bin` prints its first line at once and the results about 3 seconds
later, then halts (`00000006` is the `HALT` at its end, executed in kernel
mode):

```
BENCH: 1000000 x (ADDL2, MOVL store, MOVL load, SOBGTR)
elapsed: 3027275 us
speed: 1.321 MIPS = 37.8 clocks per instruction
data check: OK
00000006
>
```

**To stop a running program**, press Ctrl+P (or use *Halt CPU* in the OSD).
The CPU stops at the end of the current instruction, the monitor prints
`00000011` - the 8600's halt code for "invoked by console" - and `>`.
Registers and memory are untouched: `FR` shows where it stopped, and `G`
continues from there.

LED_USER blinks on console activity; LED_DISK is on while the CPU is running
and off while it sits in the monitor.

### The power-on memory test

It writes `address XOR A5A5A5A5h` to every longword of the first 64 KB and to
one longword on each of the nine top address bits, then reads it all back. The
pattern is unique per address, so a swapped address line, a stuck data bit or a
read captured on the wrong clock edge all show up, and the report says which:

The read-back is done four times, once per *read phase* - which falling edge
after the READ the first word is taken from (phase 1 is the CAS latency 2
value). The result is printed as a map, one digit per phase, and the first
phase that read everything back correctly is the one the core uses:

```
== read phase 0123 = 0100  using 1
== memory test: PASS
```

On a healthy board the map is always `0100`: the neighbouring phases read the
word before or after the right one, so they *must* fail. If every phase fails:

```
== read phase 0123 = 0000  using 1
== memory test: FAIL lw=00001234 got=A5A5B7D1 exp=A5A5B791
```

`lw` is the longword address (multiply by 4 for the byte address), and the
detail is taken at phase 1. A map of `0000` is not a timing problem: look at
the difference between `got` and `exp` - one bit (here `0040h`) is a data line,
a wrong half or a wrong address is an address line or the module not seated.
This is the first thing to look at if the core misbehaves on your board.

**The test leaves memory zeroed.** Afterwards everything it wrote is set back
to zero, and the first 64 KB are cleared even when the test is switched off. A
simulator starts with zeroed memory and DEC's stand-alone diagnostics count on
it: EVKAA reads the longword at `FE00h`, just past its own image, and if bit 31
is set it believes the Diagnostic Supervisor started it (see *Running the DEC
diagnostics*). The test pattern there, `A5A59A25h`, has that bit set.

## Troubleshooting from the console

Commands are `<hex number><letter>`, **uppercase only**. `G` and `S` act
immediately; `P`, `V`, `R` and `I` open a cell, print its contents, and then
wait - press Enter to leave it alone, or type a new hex value and Enter to
store it.

| Command | Action |
|---|---|
| `nP` or `n/` | Open the physical memory longword at `n` |
| `nV` | Open a virtual memory longword: with `MAPEN` set, translated through the current page tables in kernel mode (a page that does not translate reads as 0 and ignores a deposit); with `MAPEN` clear, the same as `P` |
| `nR` | Open general register `n`. `ER` = SP (14), `FR` = PC (15) |
| `nI` | Open internal processor register `n` |
| `G` | Continue at the current PC |
| `S` | Execute one instruction and return to the monitor |

### Halt codes

The number printed before each `>` is `{resopflt, haltpos}` - bit 8 is the
reserved operand flag, the low byte is why the CPU stopped. Where the VAX
8600 has a code for the same event (DEC STD 032, table B-24) it is that code;
2, 3, 5 and 0F are r-vax's own:

| Code | Meaning |
|---|---|
| `00000000` | Power-up / reset |
| `00000002` | Machine check: a bus access got no answer within 128 clocks |
| `00000003` | Single step finished (after `S`) |
| `00000004` | Interrupt stack not valid: a fault while pushing an exception frame onto the interrupt stack |
| `00000005` | Fault while already handling a fault |
| `00000006` | `HALT` instruction in kernel mode (outside kernel mode `HALT` is a privileged instruction: reserved instruction fault) |
| `00000007` | An exception or interrupt through an SCB vector whose bits 1:0 are 3 |
| `00000008` | The same with bits 1:0 = 2 (service in writable control store, which the 8600 has not got) |
| `0000000A` | CHMx executed on the interrupt stack |
| `0000000B` | CHMx through an SCB vector whose bits 1:0 are not 0 |
| `0000000F` | CPU reached an undefined state (a bug) |
| `00000011` | Halted from the console: Ctrl+P or the OSD *Halt CPU* |
| `000001xx` | The same, plus a reserved operand fault |

An opcode the CPU does not implement is not a halt any more: as on a VAX, it
takes the reserved instruction fault through SCB vector 10. A program that
has set up neither the stack pointer nor the SCB then usually stops with
`00000002` (the exception frame went to memory that does not exist), and
`FR` shows the PC of that instruction.

### Registers above 15: the CPU's internals

`R` accepts numbers above F, and r-vax exposes its state there. These are
invaluable when something stops unexpectedly:

| Command | Shows |
|---|---|
| `1FR` | PSL |
| `1ER` | PC of the instruction that was executing |
| `1DR` | The halt code again (`{resopflt, haltpos}`) |
| `1CR` | The instruction longword being decoded |
| `1BR` | `{instruction buffer tag, 0, valid}` |
| `18R`, `19R` | Operand pointers |
| `10R`-`13R` | Decoded operand values |

### A session that checks the machine end to end

Every line below is real output, captured from a full simulation of this core.

**1. Does memory work?** Write a value and read it back:

```
>2000P
2000P00000000 DEADBEEF
>2000P
2000PDEADBEEF
```

The monitor echoes your command, prints what was there, and then takes your new
value. Reading it back must give it to you again. (`00000000` is what the
power-on memory test left behind.) If this fails, so does everything else - the
memory test report at the top of the screen will usually say why.

**2. Can you set up the CPU?** Stack pointer and program counter:

```
>ER800
ER00000000 800
>FR1000
FR00000000 1000
```

**3. Does it execute?** Single-step three instructions, then look at the PC:

```
>S
S00000003
>S
S00000003
>S
S00000003
>FR
FR00001074
```

Halt code 3 after each `S` means the step completed normally. The PC moved from
1000h to 1074h because the third instruction of `hello.bin` is a `CALLS`. If a
step gives you `00000002` instead, the instruction (or the exception it took,
for an opcode the CPU does not implement) touched an address that nothing
answers - `1ER` tells you where and `1CR` what the instruction was.

**4. Let it run:**

```
>G
```

### If the screen stays blank or shows only the prompt

* No banner at all, just `00000000` and `>`: the self test is disabled in the
  OSD, or an older `.rbf` is still on the card.
* `== memory test: FAIL`: the SDRAM path is wrong. Send me the whole line
  and the `read phase` line above it. While it fails, the CPU cannot run
  anything from memory, so loaded programs halt at once.
* `== SDRAM module: not reported by the HPS`: the main program did not send a
  size. Informational only; it does not affect anything.
* A map other than `0100` with `PASS` (for example `0010  using 2`): the
  board works, but its read timing is a whole clock off the datasheet. Tell me
  - it would mean something unusual about the module.
* Banner and prompt but nothing echoes when you type: keyboard. The core only
  accepts a USB keyboard through `ps2_key`; try the UART console instead
  (`screen /dev/ttyS1 115200` on the MiSTer).
* Everything works but a loaded program halts straight away with `00000006`
  (it ran into zeros) or `00000002`: the load address and start address do
  not match, or the program's first instruction is one r-vax does not
  implement.

## Running the DEC diagnostics

`EVKAA` is DEC's VAX Hardcore Instruction Test (`evkaa.exe`, 60 928 bytes).
`VAX_MINIMUM_DIAGS.dsk` is a disk image with the Diagnostic Supervisor and
EVKAB (basic instructions), EVKAC (floating point), EVKAD (compatibility
mode) and EVKAE (privileged architecture, memory management among it). The
core has no disk controller yet, so the supervisor is brought over as a
memory image instead - see *Running the Diagnostic Supervisor and EVKAE*
below. These are DEC programs; they are not part of this repository and
not mine to relicense.

`tools/vaxdisk.py` lists or extracts the files of such an image - a Files-11
ODS-2 disk like `VAX_MINIMUM_DIAGS.dsk`, or an RT-11 floppy such as the
console and diagnostic floppies (also as written by VMS EXCHANGE):

```
python3 tools/vaxdisk.py list software/VAX_MINIMUM_DIAGS.dsk
python3 tools/vaxdisk.py extract software/VAX_MINIMUM_DIAGS.dsk   # -> software/VAX_MINIMUM_DIAGS/
```

Each file goes under its directory with the date the volume records, and a
`CONTENTS.txt` lists them with their sizes and record formats; text files
with variable length records come out as plain lines. `.gitignore` keeps the
images and what is extracted from them out of the repository.

To run EVKAA on the core:

1. Copy `evkaa.exe` to `/media/fat/games/DEC_VAX/`.
2. OSD: *Load Address* = `0x00000000`, *Start Address* = `0x00000200`,
   *Autostart* = Yes.
3. *Load Program* -> `evkaa.exe`.
4. The banner appears and it asks `Hit any key to continue`. Press Enter.
5. Almost at once it prints:

```
EVKAA V8.0 pass # 1(X) done!
```

`done!` is the pass indication. EVKAA then keeps running further passes
quietly. Anything else, or a
return to the `>` prompt with a halt code, is a failure worth sending me
together with `1ER` and `1CR`.

**Ctrl+C** makes EVKAA print `Input breakpoint:` (it looks for the key between
passes, so it can take a moment). That prompt is EVKAA's own breakpoint
editor, not the console monitor:

* **Enter** on its own resumes the test.
* A hex address (capital letters) and Enter plants a breakpoint there - EVKAA
  writes a `BPT` instruction into its own code - and asks again. `X` and an
  address removes that breakpoint, `X` alone removes them all. When the
  program reaches a breakpoint, EVKAA's own handler prints, for instance,
  `Breakpoint at 827E` and halts the CPU: the monitor shows `00000006` and
  `>`, and `G` continues - on a real VAX that is the console's `CONTINUE`.

**Ctrl+P** stops EVKAA (or anything else) and returns to the console monitor
with `00000011`; `G` continues where it stopped. Memory is kept, so EVKAA can
also be restarted without loading it: type `FR` (the monitor shows the PC),
then `200` and Enter, then `G`. *Load Program* also works straight away.

**If EVKAA prints `DS>` instead of its banner**, it found bit 31 set in the
longword at `FE00h` and believes the VAX Diagnostic Supervisor loaded it. In
that mode it runs passes for ever, printing a pass count each time, and after
Ctrl+C it prints `DS>` and waits for commands from a supervisor that does not
exist - it reads every key you type (the simulation shows each one arriving)
but answers none of them, so the keyboard *looks* dead. The previous build left the
memory test's pattern at `FE00h` and always started EVKAA that way; the test
now leaves zeros. If it ever happens again (another program left data there),
run the memory test from the OSD, or deposit `FE00P` = `0`, and reload.

## Running the Diagnostic Supervisor and EVKAE

EVKAE, the VAX Privileged Architecture Exerciser, runs under the VAX 8600
Diagnostic Supervisor (ZZ-EDSAA), which a real 8600 boots from a disk. The
core has no disk yet, so `tests/evkae/mkdsimage.py` does the booting in a
VAX 8600 simulator on the PC: it boots the supervisor from
`VAX_MINIMUM_DIAGS.dsk`, attaches the CPU, loads EVKAE and stops at the
`DS>` prompt. Then it saves that machine as a memory image - physical memory
up to the end of what the supervisor uses (C3200h), followed by a little
code that puts back the internal registers the supervisor had set (SCBB,
PCBB, the five stack pointers, the interval timer, the console) and returns
to it with `REI`. At its prompt the supervisor runs with memory management
off and polls the console, so nothing else of that machine is needed.

```
python3 tests/evkae/mkdsimage.py      # -> software/evkae_ds.bin (800 400 bytes)
```

It needs the simulator and DEC's `vmb.exe` (the header of the script says
where it looks for them) and `software/VAX_MINIMUM_DIAGS.dsk`. With `-p EVKAB` (or `EVKAC`, `EVKAD`) it
loads another exerciser of that disk instead, into `software/evkab_ds.bin`
(and so on): EVKAB and EVKAC run (*Running EVKAB*, *Running EVKAC* below);
EVKAD needs compatibility mode, which the core does not have yet. The image is
DEC software in another form, so `.gitignore` keeps it out of the
repository, like the disk.

On the core:

1. OSD: *Load Address* = `0x00000000`, *Start Address* = `0x00000200`,
   *Autostart* = Yes (the settings for EVKAA).
2. *Load Program* -> `evkae_ds.bin`. A banner says what is loaded, then
   `DS>`.
3. Type a command of the supervisor:

| Command | Runs |
|---|---|
| `START` | The whole program |
| `START/TEST:7` | Test 7 and the ones after it |
| `START/TEST:4:8` | Tests 4 to 8 |
| `START/SECTION:MEM_MGT` | One section: `DEFAULT`, `MEM_MGT`, `EXCEPTIONS`, `REGISTERS`, `CHANGE_MODE`, `TIMERS` or `CONTEXT` |
| `SET FLAGS TRACE` | From then on, each test prints its name as it starts |

```
DS> START/TEST:4:8

.. Program: ZZ-EVKAE, VAX Privileged Architecture Exerciser , revision 6.5, 11 t
ests,
   at 12:14:38.11.
Testing: _KA0

.. End of run, 0 errors detected, pass count is 1,
   time is  1-JAN-1987 00:00:04.66
DS>
```

(captured from the full-system simulation). A test takes one to six seconds.
The supervisor's clock starts from the time it had when the image was made
and then follows the core's time-of-day register, which test 6 sets back to
1-JAN-1987. A failure prints a report with the test, subtest and the values
involved; an unexpected exception prints `??`, the SCB vector, PC and PSL and
returns to `DS>`.

What the tests give in the full-system simulation:

| Test | | Core |
|---|---|---|
| 1 | Interrupt Test | pass |
| 2 | Exception Test | pass |
| 3 | REI Instruction Test | **fails**: an `REI` into PDP-11 compatibility mode (PSL\<CM\> set), which the 8600 has and the core has not yet, takes a reserved operand fault at `87D0` |
| 4 | Change Mode Instructions Test | pass |
| 5 | Processor Register Instructions | pass |
| 6 | Interval Timer | pass |
| 7 | Memory Management | pass |
| 8 | Kernel Stack Not Valid | pass |
| 9 | CHMx to Write Protected Stacks | pass |
| 10 | PROBE Instruction Test | pass |
| 11 | Process Context Switching Instructions | pass |

`START` stops at test 3, so for now run `START/TEST:1:2`, then
`START/TEST:4`. To run the same in the simulation:
`make -C sim fast`, then `tests/evkae/run_sim.sh 1:2 4:11`.

## Running EVKAB

EVKAB, the VAX Basic Instructions Exerciser (ZZ-EVKAB, revision 5.2), is
the supervisor's test of the instructions themselves: 161 tests, one per
instruction, for the integer, logical, branch, bit field, queue, character
string and packed decimal instructions. Each one is tried with every
addressing mode for its operands, with operands that end on the last byte
of a page, and - for the long ones - with the interval timer interrupting
them and with trace (PSL\<T\>) on. Its image is made like EVKAE's:

```
python3 tests/evkae/mkdsimage.py -p EVKAB     # -> software/evkab_ds.bin (800 400 bytes)
```

and loaded with the same OSD settings (*Load Address* `0x00000000`, *Start
Address* `0x00000200`, *Autostart* Yes). At `DS>`, `SET FLAGS TRACE` first
makes it name each test as it starts; then `START` runs all of them:

```
DS> SET FLAGS TRACE
DS> START

.. Program:  ZZ-EVKAB, VAX Basic Instructions Exerciser , revision 5.2, 161 test
s,
   at 17:07:55.99.
Testing: _KA0

Test 1: BRB Instruction Test
Test 2: BRW Instruction Test
   ...
Test 161: EDITPC Packed Decimal String Instruction Test

.. End of run, 0 errors detected, pass count is 1,
   time is 12-JUL-1987 09:41:45.74
DS>
```

`START/TEST:134:144` runs the character string tests only, and so on. Each
`START` first spends about a second setting the supervisor's page tables
up; the whole run takes about two minutes on the core. In the full-system
simulation all 161 tests pass:

| Tests | Instructions |
|---|---|
| 1-4 | BRB, BRW, BBC, BBS |
| 5-27 | MOVB, MOVW, MOVL, MOVQ, CLRx, MNEGx, MCOMx, MOVZxx, CVT between the integer types |
| 28-33 | CMPx, TSTx |
| 34-54 | ADDx, ADAWI, INCx, ADWC, SUBx, DECx, SBWC |
| 55-70 | MULx, EMUL, DIVx, EDIV, ASHL, ASHQ |
| 71-92 | BITx, BISx, BICx, XORx, ROTL |
| 93-99 | FFC, FFS, INSV, EXTV, EXTZV, CMPV, CMPZV |
| 100-127 | the conditional branches, BLBx, BBxx, BBxxI, ACBx, AOBxxx, SOBxxx, INDEX |
| 128-133 | INSQUE, INSQHI, INSQTI, REMQUE, REMQHI, REMQTI |
| 134-144 | MOVC3, MOVC5, MOVTC, MOVTUC, CMPC3, CMPC5, SPANC, SCANC, SKPC, LOCC, MATCHC |
| 145-161 | MOVP, CMPP3, CMPP4, ADDP4, ADDP6, SUBP4, SUBP6, MULP, DIVP, CVTLP, CVTPL, CVTPT, CVTTP, CVTPS, CVTSP, ASHP, EDITPC |

What it found on the way, all fixed and now covered by `tests/mmu` as well:
the interval clock did not interrupt exactly when ICR overflows, which
EVKAB's start-up checks; the supervisor's timer handler uses DIVP, so
nothing ran before the decimal instructions were there; BBC on a base
address with bits 31:30 set was taken for a register; FFC and FFS of a
field of size 0, and the operand checks of the bit field instructions (a
size above 32 is a reserved operand, and so is a position above 31 in a
register; a field that would run from R14 into PC is a reserved addressing
mode); a traced MOVC3 that the timer interrupted part way was traced before
it had finished (t38); and, in r-vax's own microcode, CMPC5 compared the
fill character with the wrong string, and CMPC3 and CMPC5 took N from an
unsigned comparison (t40).

## Running EVKAC

EVKAC, the VAX Floating Point Instructions Exerciser (ZZ-EVKAC, revision
7.2), tests every floating point instruction of the four formats, one test
per instruction: 98 tests, from MOVF (1) to ACBH (98). Like EVKAB it tries
each with every addressing mode for its operands and, unless the QUICK
flag is set, again with the operands placed across page boundaries so that
they page fault, and with the interval timer interrupting. Its image:

```
python3 tests/evkae/mkdsimage.py -p EVKAC     # -> software/evkac_ds.bin (800 400 bytes)
```

Same OSD settings as for the other images (*Load Address* `0x00000000`,
*Start Address* `0x00000200`, *Autostart* Yes). At `DS>`:

```
DS> SET FLAGS TRACE,QUICK
DS> START

.. Program:  VAX Floating Point Instructions Exerciser, ZZ-EVKAC , revision 7.2,
 98 tests,
   at 13:15:53.06.
Testing: _KA0

Test 1: MOVF Single Precision Floating Point Instruction Test
Test 2: MNEGF Single Precision Floating Point Instruction Test
   ...
Test 98: ACBH Extended Range Quad Precision Floating Point Instruction Test
.. End of run, 0 errors detected, pass count is 1,
   time is 12-JUL-1987 09:41:41.94
DS>
```

(captured from the full-system simulation). With QUICK the whole run is
some 20 million instructions, about 20 seconds on the core; without it each
case runs again for every way its operands can page fault, some 130 million
instructions, a little over two minutes. `START/TEST:71:98` runs the
H_floating tests only, and so on;
`HELP EVKAC SECTION` in the supervisor lists the sections (F_FLOATING,
D_FLOATING, G_FLOATING, H_FLOATING, POLYX, EMODX...).

| Tests | Instructions |
|---|---|
| 1-22 | F_floating: MOVF, MNEGF, TSTF, CVTBF, CVTWF, CVTLF, CVTFB, CVTFW, CVTFL, CVTRFL, CMPF, ADDF2/3, SUBF2/3, MULF2/3, DIVF2/3, EMODF, POLYF, ACBF |
| 23-46 | D_floating: MNEGD, MOVD, TSTD, CVTBD, CVTWD, CVTLD, CVTDB, CVTDW, CVTDL, CVTFD, CVTDF, CVTRDL, CMPD, ADDD2/3, SUBD2/3, MULD2/3, DIVD2/3, EMODD, POLYD, ACBD |
| 47-70 | G_floating: the same, with CVTFG and CVTGF |
| 71-98 | H_floating: the same, with CVTFH, CVTDH, CVTGH, CVTHF, CVTHD, CVTHG |

In the full-system simulation all 98 pass, with QUICK and in the slow mode
with the page faults. To run it there:
`IMAGE=software/evkac_ds.bin TRACE=1 QUICK=1 BUDGET=2000000000 tests/evkae/run_sim.sh 1:98`
(about an hour of simulation); without `QUICK=1`, and with
`BUDGET=8000000000`, the slow mode (some hours).

## Testing the memory management and the privileged architecture on the core

`software/mmutest.bin` runs the programs of `tests/mmu` on the core itself
and checks each one against the results a VAX 8600 reference simulator gave
for the same program, which are stored inside the file. Besides memory management they
cover CHMx, BPT, XFC, CASE, the bit branches, ACB, the 8600's internal
registers, the reserved addressing mode fault, interrupts after byte and
word instructions, the arithmetic traps, trace, the string, queue and
packed decimal instructions (the decimal ones and EDITPC on a few hundred
random operands), the octaword instructions and the floating point ones
(some 1 600 random cases of the four formats, and their faults). (Three
programs that end in a processor halt other than
t16's, `t22`-`t24`, are only run in simulation.)

1. OSD: *Load Address* = `0x00001000`, *Start Address* = *Load address*,
   *Autostart* = Yes (the settings for `hello.bin`).
2. *Load Program* -> `mmutest.bin`. About six seconds later the screen
   shows:

```
Test suite: the tests/mmu programs (memory management and privileged
architecture), checked against their expected results

t00_harness....... PASS
t01_xlate......... PASS
   ...
t46_fpexc......... PASS

Passed: 43   Failed: 00
All tests passed.

Last, t16_isnv: the CPU must halt here with code 00000004.
t16_isnv.......... 00000004
>
```

The last two lines are the point of `t16_isnv`: a fault while an exception
frame is pushed onto the interrupt stack halts the processor, and the 8600's
halt code for that is 4. A failing test prints `FAIL` and up to six lines
such as `R05   is 00001234, expected 00001200`, or `[00018004] is ...` for a
longword of memory; those lines are what to send me.

Before each test the program puts the machine back in the state the
expected results start from - memory 0-47FFF cleared, mapping off, timer stopped, R0-R13 zero, PSL
`041F0000` - copies the test to 1000 and runs it; the test ends by saving
its registers and PSL and returning. The runner itself sits at 300000, out of
the tests' way. After changing a test, `python3 tests/mmu/mkboard.py` rebuilds
the file (it runs the reference simulator to produce the expected values).

## Testing the floating point instructions with your own random cases

`software/fptest.bin` tests the 98 floating point instructions on the core:
200 random cases each (seed 1), 19 600 in all, each checked against the
result, condition codes and exception that `sim/fpu_tb/vaxfp.py` - the exact
model of the SRM's arithmetic that the floating point unit was written
against - predicts. It needs no reference simulator to build, so any number
of new sets can be made, on any computer with Python 3, from the project
root:

```
python3 tests/fp/mkfptest.py                     # software/fptest.bin: seed 1, 200 cases each
python3 tests/fp/mkfptest.py --seed 7 --cases 1000 -o software/fp7.bin
python3 tests/fp/mkfptest.py --only MULH3,DIVH3 --cases 5000 -o software/fph.bin
```

A file takes about 50 bytes a case: 1 MB for the default, 4.7 MB with
1000 cases each.

1. OSD: *Load Address* = `0x00001000`, *Start Address* = *Load address*,
   *Autostart* = Yes (as for `mmutest.bin`).
2. *Load Program* -> `fptest.bin`. Once it is loaded the cases take under a
   second (some 29 000 a second), and the screen shows:

```
VAX floating point test - seed 1, 98 instructions, 200 cases each
(tests/fp/mkfptest.py, expected values from sim/fpu_tb/vaxfp.py)

MOVF   ok  MNEGF  ok  TSTF   ok  CMPF   ok  ADDF2  ok  ADDF3  ok  SUBF2  ok
SUBF3  ok  MULF2  ok  MULF3  ok  DIVF2  ok  DIVF3  ok  CVTBF  ok  CVTWF  ok
   ...
CVTRHL ok  CVTHF  ok  CVTHD  ok  CVTHG  ok  EMODH  ok  POLYH  ok  ACBH   ok

Cases: 19600   Failed: 0
All tests passed.
End of the floating point test.
00000006
>
```

(captured from the full-system simulation; 00000006 is the halt code of the
HALT that ends the program.)

For each case the program sets PSL\<FU\>, PSL\<IV\> and the condition codes
at random, puts random bytes in the destination, runs the instruction once
with its sources in memory, and checks three things: the exception (none, a
reserved operand fault, or the arithmetic exception's type: integer overflow
trap, floating overflow, divide by zero or underflow fault), the condition
codes (except after a fault, where the SRM leaves them UNPREDICTABLE) and the
destination (which a fault must leave as it was; POLY's is R0-R5, ACB's the
index and whether it branched, EMOD's the integer and the fraction). The
operands go for the hard parts: values near 1 and across the whole exponent
range (overflow, underflow), sparse and all-ones fractions (rounding ties
and carries), zeros, "dirty" zeros (sign 0, exponent 0, fraction not 0),
reserved operands, the largest and smallest numbers, pairs that cancel when
subtracted, halves for CVTR, ties for the narrowing conversions, integers at
the edges of their ranges, EMOD products with large integer parts, POLY
tables of every degree and some invalid ones.

A failing instruction shows `ERR` in the table. Below it come the failed
cases by instruction and the first four failures in detail, for example
(made by altering one expected value):

```
ADDF3   case 1   PSW 68
  sources  36111EB6 3D70F501
  found    exception none   cc 8  destination 3D70F501
  expected exception none   cc 8  destination 3D70F500
```

The values are longwords in memory order; PSW is the low byte of the PSL
before the instruction (FU, IV and N Z V C). Those lines and the seed are what
to send me. On the PC, `--show` prints the same case with its values
decoded (give it the same `--seed`, `--cases` and `--only` the file was built
with), and `tools/vaxfloat.py -d` decodes one value:

```
$ python3 tests/fp/mkfptest.py --seed 1 --show ADDF3:1
ADDF3 case 1 (seed 1), record at 00009910
  PSL before: FU 1, IV 1, condition codes 8 (N Z V C = 1 0 0 0)
  add1     36111EB6                            4.82309022E-21
  add2     3D70F501                            -4.09577878E+31
  sum      8A7E1255                            1.68454135E-28   (before)
  expected: no exception
            condition codes 8 (N Z V C = 1 0 0 0)
  sum      3D70F501                            -4.09577878E+31
$ python3 tools/vaxfloat.py -d F 3D70F501
-4.09577878E+31
```

How it works: `tests/fp/mkfptest.py` makes the cases and works out what each
should give with `vaxfp.py` (the instruction rules - which operands are
checked for reserved operands, which condition codes each instruction sets
or keeps, what POLY leaves in R0-R5 - are written in it from the SRM), then
assembles `tests/fp/fpharness.s` (the driver, the exception handlers and the
console output) with a few lines per instruction and puts the cases after
the program. On the full-system simulation seeds 1 to 9, seed 100 with
1000 cases each, and seed 200 with 5000 cases each of the POLYs, the EMODs,
DIVH3, CVTHF, CVTRHL and ACBH all pass (some 330 000 cases); the reference
simulator gives the expected values for seeds 1 to 31 and that seed 200 set
(some 670 000 cases).

## What is missing

The plan for all of this, in order, is in [ROADMAP.md](ROADMAP.md).

- **PDP-11 compatibility mode**, which the 8600 has (EVKAE test 3 and EVKAD
  use it).
- **The rest of the privileged architecture**: the 8600's console storage
  registers (STXCS, STXDB) and the contents of its machine check frame.
  Everything else is in, described in [docs/MMU.md](docs/MMU.md) and
  [docs/CIS.md](docs/CIS.md).
- **PSL\<FPD\> for MOVTC, EDITPC and the decimal instructions.** MOVC3,
  MOVC5, MOVTUC, MATCHC and CRC keep their progress in R0-R5 and take
  interrupts in the middle; the others start again after a fault, which
  the architecture allows, and hold off interrupts until they finish: some
  tens of microseconds for EDITPC and the decimal ones, but tens of
  milliseconds for a MOVTC of 65535 bytes.
- **Mass storage.** An MSCP/UDA50 or Massbus disk behind the MiSTer SD
  interface (`sd_lba`/`sd_rd`) is the next large step.
- **Terminal.** No scrolling regions (`ESC [ t;b r`), no insert/delete line, no
  answerback (`ESC [ c`, `ESC [ 6 n`).
- **Speed.** About 40 clocks per instruction is r-vax's microarchitecture, not
  the memory: even a taken branch costs some 26 clocks. Widening the
  instruction fetch - the CPU fetches one byte at a time out of a
  single-longword buffer - is the obvious next gain. (The ALU's shifter, which
  r-vax built bit-serial, one clock per bit, is now a one-clock barrel
  shifter: REI and CHMK take about half the clocks they did, CASE and the
  bit branches about a third less.)

## Simulation (Verilator 5)

```
make -C sim                      # full system: CPU + cache + SDRAM model + terminal
make -C sim unit                 # terminal and keyboard only
make -C sim nocache              # same, with the cache forced to always miss
make -C sim cputb                # CPU, aligner, MMU and plain memory, for tests/mmu
make -C sim fast                 # full system, optimised harder, for long runs
make -C sim dutb && sim/obj_du/Vdecunit 20000   # the decimal unit against a C model
make -C sim fputb && python3 sim/fpu_tb/vaxfp.py v.txt 20000 && sim/obj_fpu/Vfpunit v.txt
                                 # the floating point unit against an exact model
make -C sim dqma                 # full system, SDRAM byte masks on A11/A12 (128 MB modules)
make -C sim lint                 # the whole design through Icarus Verilog as well
python3 tests/mmu/run.py         # the tests/mmu programs, compared with the reference simulator
NOTEST=1 UNTIL="00000004" BUDGET=600000000 TTOLOG=mmu.txt \
    sim/obj/Vtb_top software/mmutest.bin 0 ""         # the same tests on the full system
NOTEST=1 UNTIL="End of the floating point test" BUDGET=400000000 TTOLOG=fp.txt \
    sim/obj_fast/Vtb_top software/fptest.bin 0 ""    # the floating point test (some minutes)
tests/evkae/run_sim.sh 1:2 4:11  # EVKAE under the Diagnostic Supervisor (sim/obj_fast)
IMAGE=software/evkab_ds.bin TRACE=1 tests/evkae/run_sim.sh 134:144   # EVKAB's string tests
IMAGE=software/evkac_ds.bin TRACE=1 QUICK=1 BUDGET=2000000000 \
    tests/evkae/run_sim.sh 1:98  # EVKAC, floating point (QUICK: about an hour)

sim/obj/Vtb_top software/hello.bin 0 "1000P~"        # load, autostart, then type
NOAUTO=1 SESSION="2000P~|2000PDEADBEEF~|2000P~" sim/obj/Vtb_top software/hello.bin 0 ""
NOTEST=1 START200=1 UNTIL="Hit any key" UNTIL2="done!" \
    sim/obj/Vtb_top software/evkaa.exe 1 "~"          # run the DEC diagnostic
FAULT=0x1234 BANNER=1 sim/obj/Vtb_top software/hello.bin 0 ""   # check the FAIL report
START200=1 BUDGET=70000000 UNTIL="Hit any key" SESSION="@done!|^C|@breakpoint|5~" \
    sim/obj/Vtb_top software/evkaa.exe 1 "~"          # EVKAA, then Ctrl+C at the end
RXTRACE=1 ...                                         # log every character the CPU receives

cd sim && python3 term_test.py 40     # terminal against pyte's VT100 (pip install pyte)
```

Startup is modelled on what MiSTer Main really does: the module size arrives,
then the core is held in reset for 40 ms (`HPSRST=n` to change it, `NOHPSRST`
to skip it) before the power-on test may start. `MEMFILL=0x...` or
`MEMFILL=rand` fills the SDRAM model before power-up, like a real module's
leftover contents. In key strings `~` is Enter, `^C` is Ctrl+C and `{` is the
cursor-up key; in `SESSION`, `@text` waits for text to appear, `!R` is an OSD
reset, `!Wn` waits n clocks, `!Lfile` loads another program over whatever is
running, as *Load Program* does (`!L+wfile` / `!L+rfile` first wait until the
CPU has a write / read cycle in flight, so that the load lands on one), and
`!Bn` / `!Sn` set *Load Address* and *Start Address* (n is the OSD option's
index: `!B0` is 1000, `!B1` 0; `!S1` is 200) for the loads after them.
`PRELOAD=file@hexaddr` puts a file into memory after the memory test, as if an
earlier program had left it there. `TTOLOG=file` writes everything the CPU
sent to the console line into a file. A load over a running program, which
must start the new one cleanly (`Memory management works.`):

```
NOTEST=1 UNTIL="VAX floating point test" TTOLOG=ld.txt \
SESSION="!W3000000|!L+wsoftware/mmudiag.bin|@End of the diagnostic" \
sim/obj_fast/Vtb_top software/fptest.bin 0 ""
```

For finding where the core and a reference simulator part ways:

| Variable | Prints |
|---|---|
| `ITRACE=file` | PC, PSL and opcode of every instruction (from clock `ITRACE_FROM` on), one line each, to compare with another machine's instruction trace |
| `ITRACE_REGS=1` | R0-R14 on each `ITRACE` line as well |
| `EXCTRACE=1` | Every entry into the fault microcode and every halt |
| `INTTRACE=1` | Every interrupt or exception the CPU starts, and the SCB vector it ends up with |
| `PROFILE=1` | At the end, the clocks spent per opcode |

`tb.cpp` plays the part of `hps_io`: it downloads through the ioctl port, sends
PS/2 events, decodes both the internal console line and the MiSTer UART, counts
cache hits and instructions, and writes one video frame as `frame.ppm`.
`sim/sdram_model.v` models the inverted SDRAM clock, CAS latency 2, bursts of
2 on reads and writes, and **when read data is really valid**: the word is
presented only around the `clk` falling edge, and a register sampling on the
rising edge gets garbage, as it would on the board. It complains about an
unopened row, a refresh with a bank open, bus contention or a missed refresh
interval. `make -C sim skew` builds two more models whose read data comes one
SDRAM clock early or late; the calibration must pick phase 0 and phase 2 on
them.

## Regenerating generated files

- Microcode ROMs: in `rtl/`, `rm -f uc-*.hex && awk -f mkucode.awk` (the
  source is `rtl/ucode.def`).
- Generated tests: `python3 tests/mmu/gen/mk_t35.py > tests/mmu/t35_dec.s`
  and the like (each script's header says which); `python3
  tests/mmu/gen/mk_fp.py` writes the floating point ones, t42-t45 (it runs
  the reference simulator to size their logs).
- `software/fptest.bin`: `python3 tests/fp/mkfptest.py` (see *Testing the
  floating point instructions with your own random cases*).
- Font ROM: `python3 tools/mkfont.py spleen-8x16.bdf rtl/mister/vt_font.v`.
- Self-test text: `python3 tools/mkmsg.py rtl/mister/vax_msg.v`.
- r-vax source fixes: `python3 tools/patch_rvax.py` (idempotent) - four
  incomplete sensitivity lists, the `rtl/` path and `ramstyle` of the microcode
  ROMs, `ramstyle = "logic"` on the register files, a `halted` output port, the
  interval clock's divide-by-51, and
  two stray `$fdisplay` calls.

## Credits and licenses

- r-vax VAX CPU: (c) 2021 Anders Magnusson, BSD 2-Clause (`LICENSE`).
- MiSTer framework (`sys/`) and `dec_vax.sv`: from Template_MiSTer, GPL v2 or later.
- Terminal font: Spleen 8x16 (c) Frederic Cambus, BSD 2-Clause
  (`rtl/mister/LICENSE.spleen`).
- MiSTer glue and the memory management (`rtl/mister/`, `rtl/mmu.v`, the
  port's changes to r-vax, `tools/`, `sim/`, `software/`, `tests/`, `docs/MMU.md`):
  BSD 2-Clause.
- The DEC manuals the design follows (listed in [docs/MMU.md](docs/MMU.md))
  are DEC's documents, not covered by this license; `.gitignore` keeps the
  PDFs in `docs/` out of the repository.
- `software/evkaa.exe` and the disk images in `software/` (`*.dsk`), if you
  copy them here, are DEC diagnostics, and the `software/*_ds.bin` images
  that `tests/evkae/mkdsimage.py` makes from a disk contain them, as do the
  folders `tools/vaxdisk.py` extracts the disks into; they are not covered
  by this repository's license, and `.gitignore` keeps them out of it.
