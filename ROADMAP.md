# DEC VAX for MiSTer - Roadmap

Where the core stands, what it needs to run OpenVMS, and in which order to
build it. Milestones 1 and 2 are on the `MiSTer` branch on GitHub; this plan
starts at milestone 3. Memory management (M5) was taken first, because
everything after it depends on it; it is complete and passes its tests on the
board. M4, the 8600's privileged architecture, followed, and DEC's privileged
architecture exerciser, EVKAE, runs under the 8600 Diagnostic Supervisor.
Then M6: the decimal and character string instructions, with a decimal unit
in the datapath; DEC's basic instruction exerciser, EVKAB, passes under the
supervisor too. Then M7: floating point in its four formats, with a
floating point unit in the datapath, the octaword instructions and the
two-byte opcodes, which completes the VAX instruction set but for PDP-11
compatibility mode; DEC's floating point exerciser, EVKAC, runs under the
supervisor. Then M8: the 8600's I/O side - the physical address memory map,
SBIA 0, the RH780 Massbus adapter with two RP07 disks on SD card images and
the DW780 Unibus adapter. Then M9: the core boots like an 8600, VMB from
the OSD and the Diagnostic Supervisor from an RP07, with the 8600's console
registers; the exercisers load from the disk. Then PDP-11 compatibility
mode (planned for M11), which the 8600 has: DEC's compatibility mode
exerciser, EVKAD, passes, and so does EVKAE in full, on the board too.
Then NetBSD 11.0, the rest of M9, which found three bugs in the core on the
way and boots on the board. Now OpenVMS VAX 7.3 (M10): its first boots
found the 8600 console's transmitter wrong with no line enabled, and TODR
now comes from MiSTer's clock.

Relative size: **S** a change in one module, **M** a new module or a block of
microcode, **L** a subsystem, **XL** the largest pieces.

## Which VAX this is

r-vax is Anders Magnusson's own implementation of the VAX architecture: its own
datapath and its own microcode, not a copy of a DEC CPU's logic. The machine
around it is a **VAX 8600**: the SBI adapter and nexus addresses are the 8600's
(SBIA at `0x20080000`, Unibus adapter at TR 3, Massbus adapter at TR 8), the
microcode accepts the 8600's own IPRs (ACCS, PAMACC, PAMLOC, CSWP, MDCTL, MERG,
CRBT, EHSR) and halts with its halt codes, its machine check frame is the
8600's size, the interval timer is the 780/8600 one at IPL
24, and its author ran EDSAA, the 8600/8650 Diagnostic Supervisor, on it.

So the target is the 8600, and one rule decides everything below: **whatever
software can observe behaves like a VAX 8600**, taking DEC's documentation
as the reference, and checking the results against a VAX 8600 reference
simulator run on the PC. What software cannot see
(pipeline, cycle counts) is r-vax's own; where it costs nothing, it follows the
8600 as well - the cache is 16 KB like the 8600's, and the translation buffer
has the 8600's size and organisation. No logic is taken from other VAX
implementations; they are read, not mixed in.

OpenVMS VAX 7.3, the last VAX release, still supports the 8600.

## Where it stands

- r-vax CPU: microcode for every VAX instruction - integer, string, queue,
  packed decimal (with a decimal unit, [docs/CIS.md](docs/CIS.md)), EDITPC,
  and the two-byte (FD) opcodes: F, D, G and H floating point (with a
  floating point unit, [docs/FPU.md](docs/FPU.md)) and the octaword
  instructions - and **PDP-11 compatibility mode**
  ([docs/CMODE.md](docs/CMODE.md)). It passes **EVKAA V8.0**, DEC's
  hardcore instruction test.
- **Memory management as on the VAX 8600** (M5, below): the 8600's translation
  buffer, page table walk, protection and modify bit, access-control and
  translation-not-valid faults with instruction restart, PSL<FPD> for MOVC3 and
  MOVC5, PROBER/PROBEW, TBIA/TBIS/TBCHK, LDPCTX/SVPCTX, REI with all its
  checks and AST delivery, privileged MTPR/MFPR with the 8600's operand
  checks, kernel stack not valid and interrupt stack not valid. Design and
  sources: [docs/MMU.md](docs/MMU.md). Runs on the board.
- **The 8600's privileged architecture** (M4): CHMK, CHME, CHMS, CHMU with
  their stack probe, BPT, XFC, the reserved instruction and reserved
  addressing mode faults, HALT as a privileged instruction, trace (PSL<T>,
  <TP>), the arithmetic traps, the 8600's halt codes, its internal registers,
  a console halt with Ctrl+P or from the OSD.
- **The 8600's I/O side** (M8, below): the physical address memory map,
  SBIA 0 with interrupts and DMA, the 8600's machine checks, an RH780
  Massbus adapter with two RP07 disks on SD card images, and a DW780
  Unibus adapter, with no devices on its Unibus yet
  ([docs/IO.md](docs/IO.md)). Its tests in `mmutest.bin` pass on the
  board (the disk transfers of t52-t54 need generated disks and run in
  simulation only).
- 65 directed and random tests (`tests/mmu`) give the same results as the
  reference simulator, or the values DEC's documents give where the
  simulator models the 8600 differently; `software/mmutest.bin` runs them on
  the core, in simulation and on the board. DEC's exercisers run under the
  8600 Diagnostic Supervisor, booted from the RP07 and loaded from it:
  **EVKAB** (basic instructions, 161 tests), **EVKAC** (floating point,
  98), **EVKAD** (compatibility mode, 4) and **EVKAE** (privileged
  architecture, 11) all pass, in simulation and on the board
  (README_MiSTer.md).
- 16 KB cache in M10K, SDRAM controller with read-phase calibration, power-on
  memory test, on-screen VT terminal with USB keyboard, MiSTer UART, program
  loader with autostart, and r-vax's hardware console monitor (`>` prompt).
- Not there yet: Unibus devices, and VMS itself (M10).

## Milestone 3: Halt, and the tools for everything after

### Halt from the OSD and with Ctrl+P (done)

- An OSD trigger *Halt CPU* and **Ctrl+P** on the keyboard (or on the MiSTer
  UART with *UART Console In*) stop the CPU at the end of the current
  instruction. The console monitor prints the halt code and `>`; registers
  and memory are untouched, and `G` continues from where it stopped. An OSD
  switch makes Ctrl+P an ordinary character for the rare program that wants
  it.
- The halt code is **11**, the 8600's "invoked by console" (DEC STD 032,
  table B-24; an earlier reading of a scanned copy gave 1). The HALT
  instruction moved to 6, "kernel mode HALT", and became privileged.
- Implementation: a `halt_req` input into r-vax's `cpu.v`, checked in
  `S_FETCH` before the next instruction starts. `vax_system.v` removes
  Ctrl+P (0x10) from the keyboard stream, and from the UART stream when
  *UART Console In* is on, and turns the OSD trigger into a one-clock pulse.

### Auto load and start address (optional, S)

*Load Address* = *Auto*: `.EXE` files such as EVKAA load at `0x0` and start at
`0x200`; `.BIN` files load and start at `0x1000`.

### VAX cross-compiler (M)

GNU binutils and GCC for `vax-netbsdelf` (GCC kept its VAX back end; it was
converted to MODE_CC in December 2020), C only, freestanding. Enough for test
programs and for SVK (see below). Built once under WSL; the Python generators
in `software/` stay for the smallest tests.

### Golden model and trace comparison (M)

A VAX 8600 reference simulator, run on the PC, is the golden model. The same
program runs on the Verilator model and on the simulator; both write one line
per instruction (PC, PSL, R0-R15) and a script reports the first instruction
where they differ. Every later milestone is debugged this way.

Started with the MMU: `tools/vasm.py` assembles test programs written in a
subset of VAX MACRO, and `tests/mmu/run.py` runs each one on the reference
simulator and on a CPU-level test bench and compares the final registers,
PSL, PC and memory. The per-instruction trace came with EVKAE: the
full-system bench writes PC, PSL, opcode and R0-R14 for every instruction
(`ITRACE`, `ITRACE_REGS`), the simulator writes its instruction history, and
the two are aligned instruction by instruction - this is how every EVKAE
failure was found.

**Done when:** Halt works on the board, and a C test program built with the
cross-compiler gives the same trace on the core and on the simulator.

## What the 8600 needs that r-vax does not have yet

| Area | VAX 8600 | r-vax today |
|---|---|---|
| Instructions | All 304 opcodes in hardware, plus PDP-11 compatibility mode. | All 304 opcodes ([docs/FPU.md](docs/FPU.md) for the floating point and octaword ones), and PDP-11 compatibility mode ([docs/CMODE.md](docs/CMODE.md)). |
| Exceptions and privileged architecture | Every SCB vector with its parameters; four access modes with five stack pointers; CHMx; REI with all its checks; ASTs (ASTLVL); software interrupts; LDPCTX/SVPCTX; privileged-instruction checks; arithmetic traps; trace; 8600 machine-check frame; kernel stack not valid; the 8600's halt codes. | Done: SCB dispatch for the interval timer, console and software interrupts; CHMK, CHME, CHMS, CHMU; BPT, XFC; reserved instruction, reserved operand and reserved addressing mode faults; machine check and the memory management faults; kernel stack not valid; interrupt stack not valid; REI with all its checks; AST delivery; LDPCTX/SVPCTX; MTPR/MFPR privileged and checked; trace; the arithmetic traps (integer overflow, integer and decimal divide by zero, decimal overflow, subscript range); the 8600's halt codes (4, 6, 7, 8, A, B, 11). the floating faults (overflow, divide by zero, underflow; types 8, 9, A); the compatibility mode exceptions (SCB 30, types 0-6). Missing: the 8600 machine-check frame's contents. |
| Memory management | P0, P1 and S0 regions, page tables, translation buffer, protection, modify bit, access-violation and translation-not-valid faults, restartable instructions. | Done, in simulation ([docs/MMU.md](docs/MMU.md)). |
| 8600 registers | SID with type 4; IPRs ACCS, PAMACC, PAMLOC, CSWP, MDECC, MENA, MDCTL, MCCTL, MERG, CRBT, DFI, EHSR, STXCS, STXDB, ESPA, ESPD; console registers with the 8600's ID codes (console terminal, remote services, environmental monitor, logical console). | SID returns `040704D2`: type 4 (8600), ECO level 7, serial number 1234. ACCS (no accelerator), PAMACC, PAMLOC, CSWP, MDCTL, MERG, CRBT, EHSR and PME are there; MDECC, MENA, MCCTL, DFI, ESPA and ESPD are not yet (reserved operands, as the 780's and 750's registers are). The console registers have the 8600's lines and ID codes, with the logical console's requests (`rtl/cons86.v`); no remote services port, no EMM. Missing: STXCS and STXDB (console storage). |
| I/O | SBIA with SBI fault and error registers; memory controllers; DW780 Unibus adapter (map registers, interrupt vectors); RH780 Massbus adapter (map registers); disks behind them; interrupts at IPL 20-23; DMA. | Done ([docs/IO.md](docs/IO.md)): the PAMM (the 8600's memory arrays hang off the MBox, not the SBI), SBIA 0 with its registers, errors, interrupts and DMA side, the RH780 at TR 8 with two RP07 disks on SD card images, the DW780 at TR 3 with its map, data paths and interrupts. Missing: Unibus devices. |
| Boot | The console loads VMB.EXE at `0x200` with R0-R5 describing the boot device. | The OSD's *Boot (VMB.EXE)* entry does the same (M9). |

## How the MMU was built

The full description, with the DEC documents each rule comes from, is in
[docs/MMU.md](docs/MMU.md). In short:

- **Where.** In the slot r-vax's own original top level (`sbi.v`) reserves
  for it, between the aligner (`vcache`) and the cache: every access it sees
  is one aligned longword inside one page, and the cache stays physical.
  Physical references (SCB vectors, PCB, console `P`) and everything while
  MAPEN is clear go straight through, with no extra clock.
- **Translation buffer.** The 8600's, from its print set: 512 entries, direct
  mapped, index VA<31>,VA<16:9>, tag VA<30:17>, holding PFN, protection code
  and M bit. (The first plan here said 2-way set associative, after comet-rtl's
  750; the 8600's address module shows one tag and one compare for the TB.)
  Two M10K blocks for the entries, flip-flops for the valid bits so that TBIA
  and the process-space flush of LDPCTX take one clock.
- **Miss.** A hardware walker: S0 PTEs in physical memory at SBR, P0/P1 PTEs at
  system virtual addresses (translated through the TB or the system page
  table), length checks, protection before valid, M set in memory on the
  first write.
- **Faults and restart.** The CPU stops the instruction at once, restores
  R0-R14 from a shadow copy taken at the start of each instruction (the job
  the 8600's register log does), puts PC and PSL back and takes SCB 20 or 24
  with the architected parameter and address. MOVC3 and MOVC5 keep their
  progress in R0-R5 and set PSL<FPD> instead, on faults and on interrupts.
  A partial or unaligned write reads every longword it will write, with write
  intent, before writing any.
- **Checked against** a VAX 8600 reference simulator with directed tests
  (`tests/mmu/`). Three differences are deliberate and allowed by the
  architecture (docs/MMU.md lists them).

## Milestones toward OpenVMS

### M4 - 8600 identity and the privileged architecture (L) - done

- The 8600 IPRs that hold a value; CHME, CHMS and CHMU with their stack
  checks; BPT and XFC; HALT privileged, with the 8600's halt code 6 in kernel
  mode; the reserved instruction and reserved addressing mode faults; the
  8600's halt codes for SCB vectors with bits 1:0 = 2 or 3 and for CHMx on the
  interrupt stack; ACBB, ACBW, CVTWB, CVTLB, CVTBW. With M5: privileged
  MTPR/MFPR, REI with all its checks, ASTLVL and AST delivery, LDPCTX/SVPCTX,
  PROBER/PROBEW, kernel stack not valid, interrupt stack not valid.
- Trace (T and TP) and the arithmetic traps (integer overflow with PSL<IV>,
  divide by zero, subscript range; the decimal ones with M6), with RET's and
  CALLx's PSW and entry-mask checks; INDEX, SKPC, SCANC, SPANC, ADAWI and the
  four interlocked queue instructions; the interval clock now interrupts on
  the overflow of ICR, as the SRM says (EVKAB's initialization depends on
  it).
- Left for later: the 8600 machine-check frame's contents (with the I/O
  adapters, M8) and STXCS/STXDB (with the console, M11).

**Done when:** EVKAA still passes, EVKAE passes but for compatibility mode,
and new instruction and exception tests give the same results as the
reference simulator - all true.

### M5 - Memory management (XL) - done

As described above and in [docs/MMU.md](docs/MMU.md). The directed tests
match the reference simulator, on the CPU test bench and, as
`software/mmutest.bin`, on the
full-system model and on the board. The Quartus build meets timing (33 % of
the ALMs with the MiSTer framework). EVKAE's memory management, kernel stack
not valid, PROBE and context switch tests pass. Still to do: random tests,
and SVK (which needs the cross-compiler from milestone 3).

**Done when:** directed and random tests match the reference simulator, and
SVK runs.

### M6 - Decimal, string and octaword instructions (L) - done

- Done ([docs/CIS.md](docs/CIS.md)): ADDP4, ADDP6, SUBP4, SUBP6, MULP, DIVP,
  CMPP3, CMPP4, MOVP, ASHP, CVTLP, CVTPL, CVTPT, CVTTP, CVTPS, CVTSP, EDITPC,
  CRC, MATCHC, MOVTC, MOVTUC, with the decimal traps. A decimal unit in the
  datapath (`rtl/decunit.v`) holds two 31-digit strings and adds, subtracts,
  multiplies, divides, shifts and converts them; the microcode moves the
  strings between memory and the unit. Random operands give the same results
  as the reference simulator (`tests/mmu/t35_dec`, `t36_editpc`, more seeds
  run), and EVKAB's string and decimal tests pass.
- MOVTUC, MATCHC and CRC keep their progress in R0-R5 with PSL<FPD>, as
  MOVC3 and MOVC5 do, on faults and on interrupts; MOVTC probes all its
  pages before it moves.
- CLRO, MOVO, MOVAO, PUSHAO came with the two-byte opcodes in M7.
- Left: PSL<FPD> for MOVTC and EDITPC, which start again after a fault
  (allowed, but they hold off interrupts until they finish).
- Reference: the VAX Architecture Reference Manual.

**Done when:** random operands give the same results as the reference
simulator - true for the 21 that exist.

### M7 - Floating point: F, D, G and H (XL) - done

- Done ([docs/FPU.md](docs/FPU.md)): the two-byte opcodes; the 98 floating
  point opcodes and the 4 octaword ones. A floating point unit in the
  datapath (`rtl/fpunit.v`) works on 128-bit fractions, so that every
  result has its exact rounding bit: add and subtract with alignment and
  normalisation, multiply on the DSP blocks (32 x 32 products, one to four
  passes), a divide one bit a clock, all conversions, rounded and chopped,
  EMOD and POLY with the SRM's chopping, ACB; reserved operands, and the
  floating overflow, divide by zero and underflow faults (types 8, 9, A)
  with the instruction put back.
- Golden models: an exact model of the arithmetic written from the SRM
  (`sim/fpu_tb/vaxfp.py`, some 150 000 random vectors against the unit
  alone), and random operands compared bit for bit with the reference
  simulator (`tests/mmu/t42`-`t45`, some 1 600 cases).
- On the core itself: `software/fptest.bin`, built by
  `tests/fp/mkfptest.py`, runs any number of random cases of the 98
  instructions (a new set for each seed) and checks them against
  `vaxfp.py` - no reference simulator needed.
- The Quartus build meets timing: 53 % of the ALMs with the MiSTer
  framework, +1.9 ns of setup slack on the 50 MHz clock in the slow model.
- Found on the board: loading a program while another one ran could leave
  the old program's memory reference standing across the reset, and the new
  program then failed at once. The reset of every load is now a processor
  initialization as the SRM defines it (PSL `041F0000`, ASTLVL, SISR, MAPEN,
  PME, ICCS, RXCS, TXCS), with the console and every bus request cleared;
  `tb.cpp` loads over a running program at any chosen moment (`!L`,
  `!L+w`, `!L+r` in `SESSION`) to check it.

**Done when:** the random comparison is clean and the Diagnostic Supervisor's
EVKAC passes - both true in simulation.

### M8 - SBI, Massbus disk and Unibus (XL) - done

- 8.1 (done): the 8600's I/O side as DEC documents it - the physical
  address memory map (PAMM) in the MBox, which also says how much memory
  there is (the 8600 has no memory controllers on the SBI: its arrays hang
  off the MBox); SBIA 0 with its registers, CPU transactions to the SBI,
  timeouts and errors; the 8600's machine check frame and EHSR; SBI
  interrupts at IPL 20-23 (14-17 hex) with the interrupt summary read and
  the 8600's vectors. Tests t47-t49.
- 8.2 (done): byte masks on every physical reference; the MBox's DMA port,
  sharing memory with the CPU through the cache (which writes through, so
  DMA and the CPU always see the same memory); the SBIA's DMA side, its
  transaction buffers, quadclear and the memory interlock. Test t50.
- 8.3 (done): the RH780 Massbus adapter at TR 8 (BR5) - registers, map,
  silo, DMA, interrupts, its errors - with two **RP07** drives (516 MB,
  enough for VMS 7.3) whose disks are raw images on the MiSTer SD card,
  through `sd_lba`/`sd_rd`/`sd_wr`, mounted from the OSD. Massbus disks are
  register-level devices, much simpler than MSCP, and an 8600 could boot
  from them. Tests t51-t54, on the CPU bench and on the full system.
- 8.4 (done): the DW780 Unibus adapter at TR 3 (its own interrupts on
  BR4) - registers, software references to the Unibus with its timeouts,
  the 496 map registers, the direct data path and 15 buffered data paths
  (prefetch, purge, byte offset, longword access mode), its DMA errors,
  Unibus interrupts through the BRRVRs, the adapter's initialization and
  the Unibus power fail sequence. Tests t55-t59; t59 with a test device on
  the CPU bench's Unibus. Behind it, later: a DZ11 for more terminals on
  the MiSTer UART, a UDA50 if MSCP disks are ever wanted.

All of it in [docs/IO.md](docs/IO.md).

**Done when:** the adapters behave as DEC's documents say, test by test
(the reference simulator models them differently in several places, so the
tests check DEC's values), and an image written by the core reads back the
same on a reference simulator and the other way round.

Found on the board after M8: the M8 bitstreams failed `mmutest.bin` from
its first test with memory management on, and EVKAE from `START/TEST:4`
(halt code 4), while every simulation passed. Quartus 17.1 had built the
translation buffer's RAM with one data input (PFN bit 8) connected to
nothing; the map report listed the register that should have fed it as
removed for "lost fanout", and the same fault in the simulation gives the
board's results. The RAM is now an explicit `altsyncram` instance, every
compile checks the netlist for this kind of difference
(`output_files/dec_vax_timing.txt`), and `mmudiag.bin` names a stuck PFN
bit on the board (step T). Confirmed on the board with the build of 17
November 2026: `mmudiag.bin`, `mmutest.bin` and EVKAE (tests 1-2 and 4-11)
pass on the DE10-Nano.

### M9 - Boot like an 8600 (M)

- VMB.EXE, DEC's primary bootstrap, loaded at `0x200` with R0 = device type,
  R1 = adapter TR, R2 and R3 = unit, R5 = boot flags, as the 8600 console does.
  The console's side is in *OpenVMS Systems Operations Guide: VAX 8600
  Systems* (EK-V8600-OG, chapter 3): the boot command procedures on the
  console RL02 (DB0BOO.COM and the others for an RP07: device code DB), what
  they deposit in R0-R5 and `LOAD/START:@ VMB`. Done: the OSD's *Boot
  (VMB.EXE)* entry loads VMB from the SD card at 200 and deposits them
  (*Boot Device*, *Boot Flags*, *VMB Memory Test*); VMB runs on the RTL as on
  the reference simulator (README_MiSTer.md, *Booting from a disk: VMB*).
- The 8600/8650 Diagnostic Supervisor (EDSAA) from `VAX_MINIMUM_DIAGS.dsk`,
  with EVKAB (basic instructions), EVKAC (floating point), EVKAD
  (compatibility mode) and EVKAE (privileged architecture).
  On the core it goes on the Massbus disk. The first board test stopped
  after VMB: the supervisor's bootstrap, DIAGBOOT, asks the console for the
  microcode version through the logical console, and the console registers
  were still the 780's. Done: the 8600's console registers, with the
  console terminal, remote services, EMM and logical console lines and the
  logical console's requests (*VAX Hardware Handbook* 1986, chapter 10;
  `rtl/cons86.v`, `tests/mmu/t60_cons86.s`); the supervisor boots from the
  disk to `DS>` on the RTL in simulation, 5.3 s after VMB starts, and loads
  EVKAE from it once the RH780 leaves maintenance mode on an INIT written
  with CR<3> clear, as the supervisor leaves it after checking the adapter
  (`tests/mmu/t51_mba.s`). Confirmed on the board with the build of 21
  November 2026: the supervisor boots from the RP07 and loads EVKAE from
  it. In the full-system simulation EVKAB, EVKAC and EVKAE loaded from the
  disk pass as their images do, and so they do on the board (the build of
  21 November 2026: EVKAB and EVKAC in full, without QUICK, and EVKAE's
  tests 1-2 and 4-11). With compatibility mode (below) EVKAD and EVKAE's
  test 3 pass too, in simulation and on the board (the build of 24
  November 2026). Before that, `tests/evkae/mkdsimage.py` brought the supervisor over
  as a memory image taken from a simulator at its `DS>` prompt, with any of
  the four exercisers loaded; that is how EVKAB, EVKAC and EVKAE ran, and
  the images still work.
- NetBSD/vax, the rehearsal before VMS: a complete, free OS whose kernel
  still supports the 8600 (NetBSD 11.0, July 2026: `options VAX8600`,
  `abus0 at mainbus0`, `sbi* at abus0`, `mba* at sbi?`, `hp* at mba?` in
  GENERIC; `sys/arch/vax/vax/ka860.c`). It boots differently from VMS: VMB
  with R5<3> (the OSD's *Boot Flags* `8 Boot block`) reads LBN 0 of the
  RP07, NetBSD's boot block (`xxboot`, which VMB enters at offset 8) reads
  LBNs 1-15 through VMB's QIO routine and loads `/boot`, and `/boot` reads
  the kernel with its own RH780 driver. What the kernel asks of an 8600,
  read from its source: SID type 4; SBIA 0's configuration register at
  2008 0000 and a machine check for the absent SBIA 1; machine checks for
  the empty SBI nexus slots; CSWP and MERG at start, ACCS (no FPA); the
  logical console's "clear warm start", "clear cold start" and "reboot"
  requests through TXCS and TXDB; EHSR cleared after a machine check; the
  interval timer and TODR. The console RL02 driver only takes SCB vector F0
  until it is used. The core has all of these. Done: the RP07 image,
  `tools/netbsd/mkimage.py`. NetBSD's install ISO does not boot on the
  reference simulator's 11/780 and 8600 (its `/boot` corrupts the kernel it
  reads from the CD; port-vax, March 2024), so the script installs on the
  simulator's MicroVAX 3900 onto an RA92 labelled with the RP07's geometry,
  cuts that to an RP07 image and boots it once on the 8600 model, to the
  login prompt. Two bugs in NetBSD 11.0 keep it from using any Massbus disk
  (`hp.c` reads the label through partition `a`, `disksubr.c` indexes a
  page table with a byte address); `tools/netbsd/nbpatch.py` patches both
  into the kernel. Then NetBSD found three bugs in the core, all fixed with
  a test: the RH780's SR<16> was a latch instead of the ATTN line (t51,
  t52); LDPCTX executed on the kernel stack - undefined in the SRM, and how
  NetBSD's soft interrupts give the CPU back - saved SP in ISP (t65); and
  the write intent of a modify operand's read stayed on for the next
  reference, so an instruction fetch from a read-only page took an
  access-control violation (t66). README_MiSTer.md, *Booting NetBSD*, has
  the story and how to boot it. In the full-system simulation NetBSD now
  boots single user and runs `ls /` with the reference simulator's output
  (41 million instructions; the model runs some 5 000 a second, and `make
  -C sim save` adds checkpoints for runs like this); multi-user is for the
  board.

**Done when:** the Diagnostic Supervisor's exercisers pass and NetBSD boots
multi-user. Done: confirmed on the board with the build of 27 November
2026 - NetBSD boots from the RP07, and the tests pass there as in
simulation.

### M10 - OpenVMS VAX 7.3 (L)

- Install OpenVMS VAX 7.3 on an RP07 image (on a simulator), copy the image
  to `/media/fat/games/DEC_VAX/`, mount it from the OSD, boot through VMB.
  Done: `tools/vms/mkimage.py` installs it from the V7.3 CD image on the
  reference simulator's 8600 as an 8600 with a CD-ROM drive on a UDA50
  would (standalone BACKUP from the CD onto the RP07, then the installation
  procedure and AUTOGEN on the RP07) and boots the result once more with
  only what the core has, to the login prompt (README_MiSTer.md, *Booting
  OpenVMS*).
- Whatever goes wrong is chased with the trace comparison, the reference
  simulator booting the same image. The first boot on the RTL, in the
  full-system simulation, went as on the reference simulator to the
  `%WBM-I-WBMINFO` message and then printed nothing more. TODR's made-up
  initial value was behind the time VMS had kept on the disk, so VMS asked
  for the date - and the question never came out: VMS's console driver
  stops the console line with a transmit mask of 0 and writes the next
  mask only while TXCS<7> is set, otherwise its transmit interrupt routine
  writes it at the next interrupt; the core's console cleared TXCS<7> with
  no line enabled, and no interrupt came. Now the console offers ID F
  ("no lines currently enabled") with TXCS<7> set and an interrupt, as the
  reference simulator does (`rtl/cons86.v`, `tests/mmu/t67_txidle.s`).
  And TODR comes from MiSTer's real-time clock at power-up, as the 8600's
  battery-backed TOY clock would have kept it (`rtl/mister/vax_toy.v`,
  checked against the C library's calendar for 100 000 dates by
  `make -C sim toytb`). With both, VMS goes on into its startup procedure
  in the full-system simulation (`%STDRV-I-STARTUP`, with the date from
  MiSTer's clock); the reference simulator needs some hundred million
  instructions to the login prompt, hours for the model at some 5 000 a
  second, minutes for the board.
- The on-screen terminal answers what VMS's terminal driver asks a VT100
  (`SET TERMINAL/INQUIRE` at login): its device attributes for `ESC [ c`
  and `ESC Z`, its status and the cursor position (`vt_term.v`,
  `sim/term_test.py`).
- Licences: HPE stopped issuing OpenVMS hobbyist licences in 2020, VAX
  included, and VSI's community licence covers only x86-64. OpenVMS VAX boots
  without a licence and lets you log in on the console, with `%LICENSE`
  warnings. The core will not ship any VMS media; where they come from is up
  to each user.

**Done when:** OpenVMS reaches `Username:` on the console and runs DCL.

### M11 - The rest of the 8600 (optional)

- PDP-11 compatibility mode - done ([docs/CMODE.md](docs/CMODE.md)):
  the PDP-11 instructions decoded in hardware (`rtl/cmdecode.v`), their
  operand specifiers evaluated as the CPU evaluates VAX ones and their
  operations in microcode, REI into it with its checks, the compatibility
  mode exceptions (SCB 30), the odd address abort, trace, memory management
  faults with restart. Only the RSX application layer uses it, and VMS runs
  without it, but the 8600 has it: EVKAD and EVKAE's REI test (test 3)
  pass with it, in simulation and on the board (the build of 24 November
  2026, which meets timing with 1.77 ns of setup slack and uses 64 % of
  the ALMs).
- The 8600 console's own command language (`>>>`, BOOT, EXAMINE, DEPOSIT,
  CONTINUE, HALT), replacing r-vax's minimal monitor.
- Console RL02 (`CSA1:`) through STXCS/STXDB.
- 64 or 128 MB with larger SDRAM modules.
- Ethernet (DEUNA/DELUA on the Unibus): it needs a path from the core to the
  network, which MiSTer cores normally do not have.
- Speed: instruction prefetch and a faster operand decoder (r-vax needs about
  40 clocks per instruction; a real 8600 is about 4 VUPs). The ALU's
  bit-serial shifter is already a barrel shifter.

## Test programs along the way

| Program | What it exercises | When |
|---|---|---|
| EVKAA V8.0 | basic instructions | passes now |
| `tests/mmu` (68 programs) | memory management, faults and restart, FPD, PROBE, LDPCTX/SVPCTX (also LDPCTX on the kernel stack, as NetBSD uses it), REI, CHMx, BPT, XFC, halt codes, IPRs, reserved addressing modes, CASE, BBx, ACB, arithmetic traps, trace, the string, queue and decimal instructions, the octaword and floating point instructions (random operands), the I/O side, PDP-11 compatibility mode (random operands too), the 8600 console's transmitter with no line enabled, compared with the reference simulator | pass now |
| `software/mmutest.bin` | the same programs on the core itself, self-checking | passes on the full-system model and on the board |
| EVKAB (Basic Instructions Exerciser) | every integer, branch, bit field, queue, character string and decimal instruction, with every addressing mode, page faults on the operands, timer interrupts and trace | all 161 tests pass under the Diagnostic Supervisor image, and loaded from the RP07 (QUICK in simulation, in full on the board) |
| EVKAC (Floating Point Instructions Exerciser) | every floating point instruction of the four formats, with every addressing mode, page faults on the operands and timer interrupts | all 98 tests pass under the Diagnostic Supervisor image, with the QUICK flag and without it (page faults on the operands), and loaded from the RP07 (QUICK in simulation, in full on the board) |
| EVKAE (Privileged Architecture Exerciser) | interrupts, exceptions, REI, CHMx, IPRs, interval timer, memory management, kernel stack not valid, PROBE, LDPCTX/SVPCTX - DEC's own test of the MMU work | all 11 tests pass, in simulation (loaded from the RP07 or as an image) and on the board |
| EVKAD (Compatibility Mode Instructions Exerciser) | REI into compatibility mode and the exceptions out of it, the single and double operand and program control instructions | its 4 tests pass, loaded from the RP07, in simulation and on the board |
| Own C and assembler tests | each new instruction and exception, traced against the reference simulator | from M3 |
| SVK | MMU, SCB, interval timer and console interrupts, software interrupts, SVPCTX/LDPCTX | M5 |
| Random-operand comparison with the reference simulator | decimal, string, floating point (done) | M6, M7 |
| EDSAA + EVKAB, EVKAC, EVKAD, EVKAE | DEC's own exercisers under the 8600 Diagnostic Supervisor, booted from the RP07 | M9: the supervisor boots from the RP07 (simulation and board) and loads the four exercisers from it, which pass |
| NetBSD/vax | a complete OS | M9: single user and `ls /` in the full-system simulation; boots on the board |
| OpenVMS VAX 7.3 | the goal | M10: into its startup procedure in the full-system simulation; the login prompt on the board next |

## SVK, the vax-kernel repository

[javimunhoz/vax-kernel](https://github.com/javimunhoz/vax-kernel) is **SVK,
Simple VAX Kernel** (Javier M. Mellid, 2013, BSD licence): bootstrap, loader,
kernel and shell. It is software that runs on a VAX, not part of the hardware,
and it is the right size to test the MMU: it relocates itself to 1 MB, builds
S0, P0 and P1 page tables and turns on MAPEN, jumps into S0 space, sets up the
SCB, runs the interval timer and console receive interrupts, switches processes
with a software interrupt (IPL 3) and SVPCTX/LDPCTX, and offers a shell with
mutex, clock and console tests.

It was written for a MicroVAX 3900, so two things change for the 8600, both in
SVK and not in the core: the interval timer needs NICR loaded for a 10 ms tick
(the MicroVAX timer has a fixed period), and the kernel image is loaded with
the OSD loader together with a small parameter block giving the memory size,
instead of through the MicroVAX ROM's boot services. SVK wants at least 8 MB.
Building it needs the cross-compiler from milestone 3.

## Other VAX implementations: reference, not parts

- **DEC documentation**: the *VAX Architecture Reference Manual*, DEC STD 032,
  the VAX 8600 training print set and I-box microcode listing; the ones each
  part of the MMU follows are listed in [docs/MMU.md](docs/MMU.md).
- **peterbjornx/comet-rtl**: the VAX-11/750 rebuilt from its schematics, running
  DEC's microcode. A faithful 750 - which is exactly why its parts do not
  belong in an 8600 built on r-vax. Worth reading for how DEC built a
  translation buffer (`src/mic/tlb.v`: 512 entries, 2-way, split by VA bit 31;
  the 8600's is direct mapped) and the access checks.
- **glennswest/vax**: an early VHDL VAX-11/780. Its MMU (`rtl/mmu/vax_mmu.vhd`)
  was read while building ours: a 64-entry TLB searched linearly, P0BR and
  P1BR used as physical addresses, S1 mapped through SBR, no length or
  protection checks, no modify bit, no fault parameter, a 26-bit PFN. It is
  a sketch of the idea rather than the VAX rules, so nothing of it is used.
- **NetBSD/vax** (`sys/arch/vax`, maintained by r-vax's author): shows what an
  operating system expects from an 8600.

## Alternative considered: MicroVAX 3900

A MicroVAX 3900 (KA655) would need less CPU work, because VMS emulates 62 of
the instructions in software on a MicroVAX. It would also change what the
machine is: Q-bus instead of SBI, the KA655 firmware and its `>>>` console,
MSCP disks, a different interval timer and SID. dec_vax is an 8600, so it
stays one.
