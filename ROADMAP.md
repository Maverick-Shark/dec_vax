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
supervisor.

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
  instructions. It passes **EVKAA V8.0**, DEC's hardcore instruction test.
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
- 47 directed and random tests (`tests/mmu`) give the same results as the
  reference simulator; `software/mmutest.bin` runs them on the core. **EVKAE**, DEC's
  privileged architecture exerciser, passes 10 of its 11 tests under the 8600
  Diagnostic Supervisor (loaded as a memory image taken from a simulator); the
  eleventh needs compatibility mode. **EVKAB**, the basic instruction
  exerciser, passes all of its 161 tests under it (README_MiSTer.md).
- 16 KB cache in M10K, SDRAM controller with read-phase calibration, power-on
  memory test, on-screen VT terminal with USB keyboard, MiSTer UART, program
  loader with autostart, and r-vax's hardware console monitor (`>` prompt).
- Not there yet: PDP-11 compatibility mode, real I/O adapters, and a disk.

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
| Instructions | All 304 opcodes in hardware, plus PDP-11 compatibility mode. | All 304 opcodes ([docs/FPU.md](docs/FPU.md) for the floating point and octaword ones). Missing: PDP-11 compatibility mode. |
| Exceptions and privileged architecture | Every SCB vector with its parameters; four access modes with five stack pointers; CHMx; REI with all its checks; ASTs (ASTLVL); software interrupts; LDPCTX/SVPCTX; privileged-instruction checks; arithmetic traps; trace; 8600 machine-check frame; kernel stack not valid; the 8600's halt codes. | Done: SCB dispatch for the interval timer, console and software interrupts; CHMK, CHME, CHMS, CHMU; BPT, XFC; reserved instruction, reserved operand and reserved addressing mode faults; machine check and the memory management faults; kernel stack not valid; interrupt stack not valid; REI with all its checks; AST delivery; LDPCTX/SVPCTX; MTPR/MFPR privileged and checked; trace; the arithmetic traps (integer overflow, integer and decimal divide by zero, decimal overflow, subscript range); the 8600's halt codes (4, 6, 7, 8, A, B, 11). the floating faults (overflow, divide by zero, underflow; types 8, 9, A). Missing: PDP-11 compatibility mode, the 8600 machine-check frame's contents. |
| Memory management | P0, P1 and S0 regions, page tables, translation buffer, protection, modify bit, access-violation and translation-not-valid faults, restartable instructions. | Done, in simulation ([docs/MMU.md](docs/MMU.md)). |
| 8600 registers | SID with type 4; IPRs ACCS, PAMACC, PAMLOC, CSWP, MDECC, MENA, MDCTL, MCCTL, MERG, CRBT, DFI, EHSR, STXCS, STXDB, ESPA, ESPD; console registers with the 8600's ID codes (console terminal, remote services, environmental monitor, logical console). | SID returns `040704D2`: type 4 (8600), ECO level 7, serial number 1234. ACCS (no accelerator), PAMACC, PAMLOC, CSWP, MDCTL, MERG, CRBT, EHSR and PME are there; MDECC, MENA, MCCTL, DFI, ESPA and ESPD are not yet (reserved operands, as the 780's and 750's registers are). Missing: STXCS and STXDB (console storage); console registers in the basic 780 format. |
| I/O | SBIA with SBI fault and error registers; memory controllers; DW780 Unibus adapter (map registers, interrupt vectors); RH780 Massbus adapter (map registers); disks behind them; interrupts at IPL 20-23; DMA. | Fixed-value stubs for the SBIA, DW780 and RH780 configuration registers. No DMA, no device interrupts. |
| Boot | The console loads VMB.EXE at `0x200` with R0-R5 describing the boot device. | Programs are loaded from the OSD and started by the monitor. |

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

### M8 - SBI, Massbus disk and Unibus (XL)

- The SBIA for real: configuration, silo, fault and error registers, nexus
  interrupts at IPL 20-23 with the 8600's vectors.
- Memory controller registers at TR 1 and 2, reporting the memory size.
- RH780 Massbus adapter at TR 8: its registers and map, DMA, interrupts. The
  disk behind it: an **RP07** (516 MB, enough for VMS 7.3) on the MiSTer SD
  card through `sd_lba`/`sd_rd`/`sd_wr`, as a raw image of the disk's
  blocks. Massbus disks are register-level devices, much simpler than MSCP, and
  an 8600 could boot from them.
- DW780 Unibus adapter at TR 3: map registers, data paths, interrupt vector
  registers. Behind it, later: a DZ11 for more terminals on the MiSTer UART, a
  UDA50 if MSCP disks are ever wanted.
- Every DMA write invalidates the matching cache lines.

**Done when:** the core and a reference simulator read and write the same
image identically.

### M9 - Boot like an 8600 (M)

- VMB.EXE, DEC's primary bootstrap, loaded at `0x200` with R0 = device type,
  R1 = adapter TR, R2 and R3 = unit, R5 = boot flags, as the 8600 console does.
  A *Boot* entry in the OSD (or a `B` command in the monitor) sets them for the
  RP07. VMS media carry their own VMB.EXE.
- The 8600/8650 Diagnostic Supervisor (EDSAA) from `VAX_MINIMUM_DIAGS.dsk`,
  with EVKAB (basic instructions), EVKAC (floating point), EVKAD
  (compatibility mode, once it exists) and EVKAE (privileged architecture).
  On the core it goes on the Massbus disk. Until then,
  `tests/evkae/mkdsimage.py` brings the supervisor over as a memory image
  taken from a simulator at its `DS>` prompt, with any of the four
  exercisers loaded; that is how EVKAB and EVKAE run now.
- NetBSD/vax: its kernel supports the 8600 (`options VAX8600`, two SBIs on the
  ABus, Massbus disks). A complete, free OS as the rehearsal before VMS.

**Done when:** the Diagnostic Supervisor's exercisers pass and NetBSD boots
multi-user.

### M10 - OpenVMS VAX 7.3 (L)

- Install OpenVMS VAX 7.3 on an RP07 image (on a simulator), copy the image
  to `/media/fat/games/DEC_VAX/`, mount it from the OSD, boot through VMB.
- Whatever goes wrong is chased with the trace comparison, the reference
  simulator booting the same image.
- Licences: HPE stopped issuing OpenVMS hobbyist licences in 2020, VAX
  included, and VSI's community licence covers only x86-64. OpenVMS VAX boots
  without a licence and lets you log in on the console, with `%LICENSE`
  warnings. The core will not ship any VMS media; where they come from is up
  to each user.

**Done when:** OpenVMS reaches `Username:` on the console and runs DCL.

### M11 - The rest of the 8600 (optional)

- PDP-11 compatibility mode. Only the RSX application layer uses it, and VMS
  runs without it, but the 8600 has it: EVKAE's REI test (test 3) and EVKAD
  need it.
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
| `tests/mmu` (47 programs) | memory management, faults and restart, FPD, PROBE, LDPCTX/SVPCTX, REI, CHMx, BPT, XFC, halt codes, IPRs, reserved addressing modes, CASE, BBx, ACB, arithmetic traps, trace, the string, queue and decimal instructions, the octaword and floating point instructions (random operands), compared with the reference simulator | pass now |
| `software/mmutest.bin` | the same programs on the core itself, self-checking | passes on the full-system model; the MMU ones on the board |
| EVKAB (Basic Instructions Exerciser) | every integer, branch, bit field, queue, character string and decimal instruction, with every addressing mode, page faults on the operands, timer interrupts and trace | all 161 tests pass under the Diagnostic Supervisor image |
| EVKAC (Floating Point Instructions Exerciser) | every floating point instruction of the four formats, with every addressing mode, page faults on the operands and timer interrupts | all 98 tests pass under the Diagnostic Supervisor image, with the QUICK flag and without it (page faults on the operands) |
| EVKAE (Privileged Architecture Exerciser) | interrupts, exceptions, REI, CHMx, IPRs, interval timer, memory management, kernel stack not valid, PROBE, LDPCTX/SVPCTX - DEC's own test of the MMU work | 10 of 11 tests pass under the Diagnostic Supervisor image; test 3 needs compatibility mode (M11) |
| Own C and assembler tests | each new instruction and exception, traced against the reference simulator | from M3 |
| SVK | MMU, SCB, interval timer and console interrupts, software interrupts, SVPCTX/LDPCTX | M5 |
| Random-operand comparison with the reference simulator | decimal, string, floating point (done) | M6, M7 |
| EDSAA + EVKAB, EVKAC, EVKAD, EVKAE | DEC's own exercisers under the 8600 Diagnostic Supervisor | M9 |
| NetBSD/vax | a complete OS | M9 |
| OpenVMS VAX 7.3 | the goal | M10 |

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
