# DEC VAX (r-vax) for MiSTer

Port of [r-vax](README.md), Anders Magnusson's VAX CPU in Verilog, to the
MiSTer FPGA platform (Terasic DE10-Nano).

**Status: the core runs real VAX software.** It boots into the r-vax hardware
console monitor, runs programs loaded from the OSD, and **passes EVKAA V8.0,
DEC's own Hardcore Instruction Test**, in simulation of the full MiSTer core
(and the first version of this port ran it on a DE10-Nano).
OpenVMS cannot run yet: there is no MMU, no floating point and no disk
controller. See *What is missing*.

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
| Microcode ROMs | `rtl/uc-*.hex`, `rtl/ucode.v` | 110 Kbit, forced into M10K block RAM |
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
cpu ── vcache ──┬── vax_cache ── vax_sdram ── 32 MB SDRAM      (0000 0000-01FF FFFF)
   (aligner)    │
                └── SBI / DW780 / RH780 register stubs          (2000 0000 and up)
```

* **`vcache.v`** despite its name is not a cache. It is the alignment unit: the
  VAX allows a longword operand to start on any byte, so this block turns one
  unaligned CPU access into one or two aligned longword bus cycles, and does
  the read-modify-write for byte and word stores. Everything below it sees
  nothing but full longword transfers.

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

**Microcode.** The three ROMs in `ucode.v` are 256x64, 256x64 and 1024x72 bits,
about 110 Kbit in total. `tools/patch_rvax.py` marks them `ramstyle = "M10K"`,
because left to itself Quartus may decide to build a ROM that size out of
logic, which costs thousands of ALMs and ruins the timing. The CPU register
file and the IPR file are deliberately kept *out* of block RAM (`ramstyle =
"logic"`): they have several read ports and belong in LUT RAM.

**Cache.** `vax_cache.v` is new. It sits between the aligner and the SDRAM:

* 16 KB, direct mapped, 16-byte lines (four longwords), physically indexed and
  tagged - with no MMU there is no aliasing to worry about.
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
The device has 553 M10K blocks and the whole core uses 37, so there is room to
go much larger if a future MMU makes it worthwhile.

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

The logic has room to spare: the compile of this version reports +2.4 ns of
setup slack on `clk_sys` at 50 MHz (slow 85 C model).

## Building

1. Quartus Prime Lite **17.0.2** or **17.1**. Device 5CSEBA6U23I7.
2. Open `dec_vax.qpf`, *Start Compilation* (or
   `quartus_sh --flow compile dec_vax`).
3. Copy `output_files/dec_vax.rbf` to the SD card as
   `/media/fat/_Computer/DEC_VAX_yyyymmdd.rbf`.

Do not edit anything under `sys/` - it is the unmodified MiSTer framework.

Resource estimate from an independent synthesis (Yosys, Cyclone V target):
about 6 500 LUTs, 3 270 registers, 37 M10K, 112 MLAB, 4 DSP. That is roughly
10-15 % of the logic and 7 % of the block RAM on the DE10-Nano.

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
| Load Program | Loads a `.BIN`/`.EXE` image into RAM at *Load Address*. The CPU is held in reset while loading |
| Load Address | `0x00001000` (default), `0x00000000`, `0x00000200`, `0x00010000` |
| Start Address | *Load address*, or `0x00000200` - DEC stand-alone diagnostics load at 0 and start at 200h |
| Autostart | After a load, types `FR<start address><CR>G` into the monitor |
| Text Color | Green / Amber / White phosphor |
| Keyboard | US or ES (Spanish) layout |
| UART Console In | Also accept keystrokes from `/dev/ttyS1`. Output always goes there |
| Power-on Memory Test | On by default |
| SDRAM Read Phase | *Calibrated* (default) uses what the memory test found; *Force 0..3* overrides it, for diagnosis only |
| Run Memory Test | Runs it again now. **This clears the first 64 KB of RAM** |
| Reset | Resets the CPU and clears the screen. RAM keeps its contents |

### Loading and running a program

*Where* a file goes in memory is decided by the OSD option **Load Address**,
when you load it. The console's `FR` only sets the PC - where the CPU starts -
so it cannot move a program; `G` at an address where nothing was loaded runs
whatever is there (zeros are `HALT`, so you just get `00000001` back).

| Program | Load Address | Start Address | Then |
|---|---|---|---|
| `hello.bin`, `bench.bin` | `0x00001000` | Load address | *Load Program* |
| `evkaa.exe` | `0x00000000` | `0x00000200` | *Load Program*, Enter at `Hit any key` |

With *Autostart* = Yes the core types `FR<start>`, Enter and `G` for you right
after the load. With *Autostart* = No, do it by hand at the `>` prompt: `FR`,
then the start address and Enter, then `G`. The options are saved, so after
running EVKAA set them back before loading a `.bin`.

`bench.bin` prints its first line at once and the results about 3 seconds
later, then halts (`00000001` is the `HALT` at its end):

```
BENCH: 1000000 x (ADDL2, MOVL store, MOVL load, SOBGTR)
elapsed: 3027275 us
speed: 1.321 MIPS = 37.8 clocks per instruction
data check: OK
00000001
>
```

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
| `nV` | Open a virtual memory longword (identical - there is no MMU) |
| `nR` | Open general register `n`. `ER` = SP (14), `FR` = PC (15) |
| `nI` | Open internal processor register `n` |
| `G` | Continue at the current PC |
| `S` | Execute one instruction and return to the monitor |

### Halt codes

The number printed before each `>` is `{resopflt, haltpos}` - bit 8 is the
reserved operand flag, the low byte is why the CPU stopped:

| Code | Meaning |
|---|---|
| `00000000` | Power-up / reset |
| `00000001` | A `HALT` instruction - **or an opcode this CPU does not implement** |
| `00000002` | Machine check: a bus access got no answer within 128 clocks |
| `00000003` | Single step finished (after `S`) |
| `00000005` | Fault while already handling a fault |
| `00000007` | CPU reached an undefined state (a bug) |
| `000001xx` | The same, plus a reserved operand fault |

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
step gives you `00000001` instead, the CPU hit an opcode it does not implement -
`1ER` tells you where and `1CR` what it was. If it gives you `00000002`, the
instruction touched an address that nothing answers.

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
* Everything works but a loaded program halts with `00000001` straight away:
  the program's first instruction is one r-vax does not implement, or the load
  address and start address do not match.

## Running the DEC diagnostics

`EVKAA` is the VAX Hardcore Instruction Test, the same program the simh test
suite uses to certify its VAX emulation. It ships with simh:

* <https://github.com/simh/simh/raw/master/VAX/tests/evkaa.exe> (60 928 bytes)
* or the same file in <https://github.com/open-simh/simh>, at `VAX/tests/evkaa.exe`

The same directory holds `VAX_MINIMUM_DIAGS.dsk`, the disk image the Diagnostic
Supervisor boots to run EVKAB (basic instructions), EVKAC (floating point),
EVKAD (compatibility mode) and EVKAE (privileged architecture). Those need a
disk controller and an MMU, so they are for a later milestone. These are DEC
programs, distributed for use with simulators; they are not mine to relicense.

To run EVKAA on the core:

1. Copy `evkaa.exe` to `/media/fat/games/DEC_VAX/`.
2. OSD: *Load Address* = `0x00000000`, *Start Address* = `0x00000200`,
   *Autostart* = Yes.
3. *Load Program* -> `evkaa.exe`.
4. The banner appears and it asks `Hit any key to continue`. Press Enter.
5. After about six seconds it should print:

```
EVKAA V8.0 pass # 1(X) done!
```

`done!` is the pass indication - it is exactly the string simh's own test script
looks for. EVKAA then keeps running further passes quietly. Anything else, or a
return to the `>` prompt with a halt code, is a failure worth sending me
together with `1ER` and `1CR`.

**Ctrl+C** stops EVKAA's loop and asks `Input breakpoint:` - it echoes what you
type there (a test number to stop at). To get back to the console monitor use
the OSD *Reset*; memory is kept, so `FR200` + `G` restarts EVKAA without
loading it again.

**If EVKAA prints `DS>` instead of its banner**, it found bit 31 set in the
longword at `FE00h` and believes the VAX Diagnostic Supervisor loaded it. In
that mode it runs passes for ever, printing a pass count each time, and after
Ctrl+C it prints `DS>` and waits for commands from a supervisor that does not
exist - it reads every key you type (the simulation shows each one arriving)
but answers none of them, so the keyboard *looks* dead. The previous build left the
memory test's pattern at `FE00h` and always started EVKAA that way; the test
now leaves zeros. If it ever happens again (another program left data there),
run the memory test from the OSD, or deposit `FE00P` = `0`, and reload.

## What is missing

- **Memory management.** `MAPEN` is ignored, there is no translation buffer and
  no page tables, and no instruction restart after a translation fault. This is
  the single biggest piece of work before VMS.
- **Floating point** (F, D, G, H), packed decimal, and several string
  instructions. An unimplemented opcode halts the CPU with code 1.
- **Mass storage.** An MSCP/UDA50 or Massbus disk behind the MiSTer SD
  interface (`sd_lba`/`sd_rd`) is the next large step.
- **Terminal.** No scrolling regions (`ESC [ t;b r`), no insert/delete line, no
  answerback (`ESC [ c`, `ESC [ 6 n`).
- **Speed.** About 40 clocks per instruction is r-vax's microarchitecture, not
  the memory. Widening the instruction fetch - the CPU fetches one byte at a
  time out of a single-longword buffer - is the obvious next gain.

## Simulation (Verilator 5)

```
make -C sim                      # full system: CPU + cache + SDRAM model + terminal
make -C sim unit                 # terminal and keyboard only
make -C sim nocache              # same, with the cache forced to always miss

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
reset and `!Wn` waits n clocks. `PRELOAD=file@hexaddr` puts a file into memory
after the memory test, as if an earlier program had left it there.

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

- Microcode ROMs: in `rtl/`, `rm -f uc-*.hex && awk -f mkucode.awk`.
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
- MiSTer glue (`rtl/mister/`, `tools/`, `sim/`, `software/`): BSD 2-Clause.
- `software/evkaa.exe`, if you copy it here, is a DEC diagnostic obtained from
  the simh distribution; it is not covered by this repository's license.
