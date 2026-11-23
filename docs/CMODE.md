# PDP-11 compatibility mode on the MiSTer VAX 8600

The VAX 8600, like the VAX-11/780, 750 and 730 before it, runs PDP-11
programs in **compatibility mode**: user-mode PDP-11 code in the first 64 KB
of a process's P0 space, with a VAX-mode executive around it (VMS's RSX-11
application migration executive is one). The MicroVAX and the VAX 8200 left
it out, to software. The VAX Architecture Reference Manual (EY-3459E-DP,
1987) defines it in chapter 9, the exceptions it raises in chapter 5; this
page describes how the core does it. Where the manual leaves a choice, the
core makes the one the VAX 8600 reference simulator makes, and the tests
compare the two.

## What the architecture asks

* **Entering and leaving.** REI with PSL\<CM\> set in the PSL it pops enters
  compatibility mode; that PSL must have FPD, IS, DV, FU and IV clear and
  CUR_MOD user (so PRV_MOD user and IPL 0), else REI takes a reserved
  operand fault. Any exception or interrupt returns to VAX mode.
* **Registers.** PDP-11 R0-R6 are the low words of VAX R0-R6, the PDP-11 PC
  (R7) the low word of R15. The upper halves are ignored on the way in, and
  "either cleared or left unchanged" on the way out; VAX R7 is
  UNPREDICTABLE afterwards, R8-R14 are not touched. The PSW is PSL\<4:0\>:
  T, N, Z, V, C.
* **Memory.** 16-bit addresses, zero extended: compatibility mode reaches
  P0 addresses 0-FFFF, in user mode, through the normal memory management,
  with all its faults. A word reference at an odd address is the odd address
  abort.
* **Instructions** (table 9.1): the PDP-11 basic set and EIS - MOV, CMP,
  BIT, BIC, BIS (word and byte), ADD, SUB; CLR, COM, INC, DEC, NEG, ADC, SBC,
  TST, ROR, ROL, ASR, ASL (word and byte), SWAB, SXT; MUL, DIV, ASH, ASHC,
  XOR; all the branches, SOB, JMP, JSR, RTS, RTI, RTT; MFPI, MFPD, MTPI, MTPD
  (a push and a pop on the current stack); the condition code operators -
  with the eight addressing modes.
* **Exceptions** (SCB 30, a type code pushed after the PSL and PC): the
  faults reserved instruction (0: HALT, WAIT, RESET, MFPT, SPL, MARK, CSM,
  MTPS, MFPS, FIS, CIS, FP11 and every opcode not in table 9.1), BPT (1),
  IOT (2), EMT (3), TRAP (4) and illegal instruction (5: JMP or JSR to a
  register), and the odd address abort (6). Everything else - memory
  management faults, machine checks, interrupts, trace - goes through its
  usual vector, with PSL\<CM\> in the saved PSL.
* **Trace.** As in VAX mode: TP \<- T at the start of each instruction, the
  trace fault before the next one; RTI and RTT load T from the PSW they pop.
* **Program synchronization.** A compatibility mode program may write the
  instructions it executes next, with nothing in between.

## How the core does it

r-vax decodes VAX operand specifiers in hardware and runs each
instruction's operation in microcode; compatibility mode is built the same
way.

**Fetch.** When an instruction starts (`S_FETCH`) with PSL\<CM\> set, the
CPU reads the word at PC as a data read - the instruction buffer is not
used in compatibility mode, so a program can modify the very next
instruction - and moves PC past it (16 bits: FFFE + 2 is 0). TP \<- T as in
VAX mode, and the registers are copied to the shadow set the fault logic
restores from, so every compatibility mode instruction can be put back.

**Decode** (`rtl/cmdecode.v`). The instruction word gives: the microcode
routine; whether the instruction faults at once (the reserved, trap and
illegal instructions, with their type code); its operands - A, a source read
from IR\<11:6\> (or from IR\<5:0\> for MUL, DIV, ASH, ASHC, MFPx, or the
implied (SP)+ of MTPx), and B, IR\<5:0\> (or the implied -(SP) of MFPx) to
read, write, modify or take the address of; when the register field is read
(before the operands for XOR, after them for JSR, RTS, SOB and the EIS
instructions); the size; and how the condition codes are set: N and Z from
the result, V cleared, from the ALU or N XOR C, C cleared, from the ALU or
set. For a branch it gives what the branch adds to PC: twice the
displacement if the condition holds, else 0.

**Operands** (the `CM_*` states of `rtl/cpu.v`). Each specifier is
evaluated as the PDP-11 does: register, (Rn), (Rn)+ and -(Rn) (by 1 for a
byte in R0-R5, else by 2), @(Rn)+ and @-(Rn), X(Rn) and @X(Rn) with the index
word from the instruction stream (with PC as the register, the PC past that
word); so #n, @#a, a and @a are PC's modes 2, 3, 6 and 7. A register update
is made at once, so the next specifier sees it; a fault later in the
instruction puts it back with the rest. Operand A is read before operand B
is evaluated. Values go to the microcode sign extended from their size (the
32-bit ALU then gives the 8- and 16-bit carries and overflows), operand B's
location to the write back.

**Microcode** (`rtl/ucode.def`, from `cm_table`, a table at step 16 that
the hardware enters at 16 + the routine number). Most routines are one
step: CLR, MOV (also MFPx and MTPx), CMP and the others compute the result
with the flags at the operand size (`cmsz`, a new step bit) and leave the
write back to the end of the instruction, which writes a register or memory
at the operand's size (MOVB to a register: the whole word, sign extended).
The shifts and rotates, SWAB, SXT, the condition code operators, the
branches and SOB, JMP, JSR, RTS, RTI and RTT take a few steps; MUL, DIV, ASH
and ASHC a dozen or two (DIV with the ALU's divider on the magnitudes;
ASH and ASHC on the 32-bit shifter, with V from shifting back). New right
ALU operands give the microcode the register field's register numbers, the
branch displacement and the instruction word.

**A 16-bit machine.** While a compatibility mode instruction runs, the
microcode reads the registers' low words, registers are written as words
(the upper half cleared) and the addresses it makes are 16 bits; the
operand logic does the same. REI into compatibility mode keeps the low word
of the PC it pops and clears the upper halves of R0-R6, as the reference
simulator does.

**Exceptions.** The faults of the decode, and the odd address abort (taken
before the reference is made, on any word reference: fetch, operands,
pushes and pops), enter a new microcode entry, 11, with the registers, PC
and PSL as they were at the start of the instruction - the reference
simulator also backs the instruction up for the odd address abort, which
the manual allows - and the type code in a new internal register
(`IPR_CMCODE`, 77, which MTPR and MFPR cannot reach). The routine pushes
the code after PSL and PC, as an arithmetic exception does, through SCB
30. Memory management faults and machine checks work as in VAX mode, the
instruction restarted after the handler.

**Speed.** About 30 clocks per instruction for a loop of simple
instructions on the CPU bench, as for VAX instructions: some 1.5 million
PDP-11 instructions a second at 50 MHz. All of EVKAD, its VAX code and its
PDP-11 code, is 635 million clocks on the full system: 12.7 seconds.

## Choices where the manual leaves them open

* The upper halves of R0-R6: cleared by REI into compatibility mode and by
  each write there; VAX R7 is left alone.
* DIV: when the quotient does not fit in 16 bits the registers are not
  changed and N, Z, C are clear (V set); a zero divisor sets V and C and
  clears N and Z. The manual makes N and Z UNPREDICTABLE then.
* The odd address abort is taken as a fault (registers and PC back).
* RTI and RTT are the same instruction (as the manual says), as are MFPI
  and MFPD, MTPI and MTPD.

## How it was checked

* `tests/mmu` (with `tests/mmu/run.py`, against the reference simulator):
  * t61: REI's checks into compatibility mode (FPD, IS, DV, FU, IV,
    CUR_MOD, PRV_MOD, IPL), the PC and register upper halves ignored, every
    fault code (BPT, IOT, EMT, TRAP, fifteen reserved opcodes, JMP and JSR
    to a register), the odd address abort on the fetch, a read, a write
    and a push, with the autoincrements undone, and an interrupt pending
    at the REI;
  * t62: 600 instructions with random operands and addressing modes - the
    double and single operand ones, word and byte, SWAB, SXT, MUL, DIV,
    ASH, ASHC, XOR, MFPx, MTPx, the condition code operators - each
    followed by BPT, the registers and PSL logged, the memory compared at
    the end (`tests/mmu/gen/mk_t62.py`, which takes a seed: sixteen more
    seeds, another 10 400 instructions, were run too);
  * t63: every branch with each of the 16 condition code patterns, the
    longest displacements, JMP in each mode, JSR and RTS with PC and R5
    (an argument after the call, JSR R1,@(R1)+), SOB, MOV and ADD to PC,
    RTI and RTT, and tracing: REI with T, RTI and RTT popping T, a BPT with
    T set, an RTI traced because T was set at its start
    (`tests/mmu/gen/mk_t63.py`);
  * t64: with memory management on - translation not valid on the
    instruction fetch, on an index word across a page boundary, on a
    destination written at the end (the autoincrement undone), on JSR's
    push; access-control violations in user mode, a modify of a read-only
    page; an odd address on an invalid page is the odd address abort.
* The decode alone, for all 65536 instruction words and the 16 condition
  code patterns, against an independent model written from the reference
  simulator's instruction switch.
* DEC's EVKAD (VAX compatibility mode instructions exerciser, 4 tests) and
  EVKAE test 3 (REI) under the 8600 Diagnostic Supervisor, booted from the
  RP07 and loaded from it, in the full-system simulation: 0 errors detected
  (README_MiSTer.md, *Running EVKAD*). `software/mmutest.bin` runs t61-t64
  on the core itself.

## Files

| File | What |
|---|---|
| `rtl/cmdecode.v` | New: the compatibility mode instruction decode |
| `rtl/cpu.v` | PSL\<CM\>; the compatibility mode fetch and the operand states (`CM_*`); the 16-bit rules; the odd address abort; the condition codes at the end of the instruction; `IPR_CMCODE`; microcode entry 11 |
| `rtl/ucode.def` | `cm_table` and the routines, `cmflt` (SCB 30), REI into compatibility mode |
| `rtl/mkucode.awk`, `rtl/ucode.v` | The `cmsz` step bit (the goto address is 12 bits), the right operands `cmr`, `cmr1`, `cmbr`, `cmir`; a check that a step does not use two different constants (it has one constant field) |
| `rtl/ipr.vh` | `IPR_CMCODE` (77) |
| `tools/vasm.py` | PDP-11 instructions after `.pdp11` (MACRO-11 syntax), for the tests |
| `tests/mmu/t61_cmode.s` - `t64_cmmm.s`, `tests/mmu/gen/mk_t62.py`, `mk_t63.py` | Tests |
