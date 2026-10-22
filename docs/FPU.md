# Floating point, octawords and the two-byte opcodes

This note describes milestone 7 of the MiSTer port: the VAX floating point
instructions in all four formats (F, D, G and H), the octaword instructions
and the two-byte (`FD xx`) opcodes they need. It follows the VAX Architecture
Reference Manual (SRM, 1987): chapter 1 for the data types, chapter 2 for
the addressing modes and the floating point short literals, chapter 3 for
the instructions and chapter 5 (6 in some editions) for the exceptions.

The VAX 8600 implements the whole instruction set, H_floating and octaword
included, with or without its optional floating point accelerator; the
accelerator only makes the instructions faster. The core behaves as an 8600
without it (`ACCS` reads 0), and the results, condition codes and
exceptions are the ones the SRM defines for every VAX.

## What is in

| Opcodes | Instructions |
|---|---|
| 40-56 | F_floating: ADDF2/3, SUBF2/3, MULF2/3, DIVF2/3, CVTFB/FW/FL, CVTRFL, CVTBF/WF/LF, ACBF, MOVF, CMPF, MNEGF, TSTF, EMODF, POLYF, CVTFD |
| 60-76 | D_floating: the same set, CVTDF |
| FD 40-56 | G_floating: the same set, CVTGH |
| FD 60-76 | H_floating: the same set, CVTHG |
| FD 32, 33, 98, 99, F6, F7 | CVTDH, CVTGF, CVTFH, CVTFG, CVTHF, CVTHD |
| FD 7C-7F | CLRO (CLRH), MOVO, MOVAO (MOVAH), PUSHAO (PUSHAH) |

CLRF, CLRD, CLRG, MOVAF, MOVAD, MOVAG, PUSHAF, PUSHAD and PUSHAG are the
longword and quadword instructions of the same opcodes, which were already
there. Every other two-byte opcode takes the reserved instruction fault with
the PC at the `FD` byte (`FD 00` is not HALT).

## Decoding

**Two-byte opcodes** (`cpu.v`, `S_FETCH`). The `FD` byte starts the
instruction as any opcode does (old PC and PSL saved, PSL\<TP\> from T) and
sets `ext_op`; the next byte is fetched without looking again for a console
halt, an interrupt or a trace fault, and selects one of the upper 256 rows of
the instruction ROM, which now has 512 (`ucode.v`; `mkucode.awk` takes
`FDxx` in its opcode list). A fault on the fetch of that byte - the opcode
split across a page boundary - has the PC of the `FD` byte. `ext_op` is
cleared when the instruction ends or faults. An instruction that cannot
resume with PSL\<FPD\> set now takes the reserved instruction fault through
the restoring path (`XFAULT`), so the PC goes back to the opcode, one or two
bytes.

**Octaword and H_floating operands.** The argument ROM has three new fields:
bit 7 marks a 16-byte operand (`o`, `h`), bit 20 a floating operand (`f`,
`d`, `g`, `h`) and bits 23:21 its format. For 16 bytes the operand decoder
scales an index register by 16, moves (Rn)+ and -(Rn) by 16, reads
immediate data of 16 bytes and reads the operand as four longwords
(`arg_wd` counts them, from memory or from Rn to Rn+3; `OP`, `OPu`, `OP2`,
`OP3`). A register operand of 16 bytes in AP, FP, SP or PC is a reserved
addressing mode fault (the operand would run past R14). A raw octaword
(MOVO's source) goes to arg1-arg4; a floating operand goes to the floating
point unit.

## The floating point unit

`rtl/fpunit.v` holds three operand slots and a result register, unpacked:
a sign, a true exponent (18 bits, signed) and a 128-bit fraction with the
hidden bit at bit 127. Every format fits: H_floating's 113 bits of
precision are bits 127:15. The value is (-1)^s x f/2^128 x 2^e.

When the operand decoder has read a floating source operand (read or
modify access), it hands the longwords, the format and, for a short
literal, the literal to the unit, which unpacks them into the slot the
argument ROM names (`ARGEND`): S0 for the first floating operand read, S1,
S2 for the next ones. A biased exponent of 0 is zero whatever the fraction
(the SRM's "dirty zero" is zero), or with the sign set the reserved operand.
A short literal is 0.1fff (binary) x 2^exp, the same value in every format
(SRM chapter 2, literal mode): 0.5 to 120.

The microcode reaches the unit as internal processor registers 50-5F, which
MTPR and MFPR cannot reach:

| Register | Write | Read |
|---|---|---|
| 50 | command | status: \<0\> reserved operand, \<1\> floating overflow, \<2\> floating underflow (only with PSL\<FU\> set), \<3\> divide by zero, \<4\> integer overflow, \<5\> N, \<6\> Z, \<31\> busy |
| 51-54 | W0-W3, an operand for LD | the result packed in the command's format, longwords 0-3 |
| 55 | IR: an integer operand (CVTIF; EMOD's multiplier extension) | IR: the integer result (CVTFI, EMOD) |
| 56 | | N and Z as a longword for the microcode's savnz |
| 58-5B | X0-X3, the microcode's scratch longwords | X0-X3 |

A command is 16 bits: \<3:0\> the operation, \<5:4\> source a, \<7:6\>
source b (slots 0-2 or the result), \<9:8\> the format, \<11:10\> a slot,
\<12\> negate, \<14:13\> integer size, \<15\> round. Writing it starts the
unit; the CPU waits in `DUWAIT` (shared with the decimal unit) while the
unit is busy.

| Op | Name | Does |
|---|---|---|
| 1 | LD | slot <- W0-W3 unpacked |
| 2 | MOV | R <- a, negated with \<12\> (MOV, MNEG) |
| 3 | CMP | N <- a < b, Z <- a = b |
| 4 | ADD | R <- a + b, or a - b with \<12\>, rounded |
| 5 | MUL | R <- a x b, rounded |
| 6 | DIV | R <- a / b, rounded; divide by zero when b is 0 |
| 7 | CVTIF | R <- IR (signed), rounded |
| 8 | CVTFI | IR <- a as an integer of the size given, chopped or rounded, integer overflow if it does not fit |
| 9 | RND | R <- a rounded to the format (conversions between formats) |
| 10 | EMOD | IR <- integer part, R <- fraction part of a x b (see below) |
| 11 | POLY | R <- R x a + b, one step of POLY (see below) |
| 12 | STO | slot <- R |
| 13 | TST | N, Z <- a |

Every command checks the sources it uses for the reserved operand before
anything else.

### Rounding

The SRM defines the result of every floating instruction exactly: the
infinitely precise result is normalized and chopped to the format's
precision (24, 56, 53 or 113 bits); if the first bit chopped off, the
rounding bit, is 1, one is added to the last bit kept (and the result
renormalized if that carries out). Only the rounding bit matters - a tie
rounds away from zero - so the unit needs the infinitely precise result
only down to that bit, and develops 128 bits of every result:

- **ADD/SUB**: the operand of the smaller magnitude is shifted right by the
  difference of the exponents. For an addition the bits shifted out are
  dropped, for a subtraction the shifted operand is rounded up instead
  (one is added if anything was shifted out), which is the borrow they
  would cause. Either way the 129-bit sum is the floor of the exact one, so
  all its bits are the exact result's. Cancellation of more than one bit
  happens only when the exponents differ by one or less, when nothing was
  shifted out.
- **MUL**: the full 256-bit product, made of 32 x 32-bit products four at a
  time (one to four passes, as many as the multiplier's format has 32-bit
  chunks); the high 128 bits, normalized by at most one place.
- **DIV**: a restoring division, one quotient bit a clock, the precision
  plus two bits (26 for F, 115 for H): the quotient of two normalized
  fractions lies between 1/2 and 2.
- The rounding adds one at the format's rounding bit (bit 103 for F, 71 D,
  74 G, 14 H) and clears what is below the last bit kept.

After rounding the exponent is checked: above the format's range is
floating overflow; below it is floating underflow, which faults with
PSL\<FU\> set and otherwise gives a result of 0 (all bits clear, as every
zero result is).

### Integer conversions

CVTxB, CVTxW, CVTxL chop the value toward zero; CVTRxL rounds it in sign
and magnitude, so a half goes away from zero (SRM, CVT note 5). An integer
that does not fit the destination sets V and stores its low-order bits
(integer overflow, which traps with PSL\<IV\> set); a value of 2^128 or more
stores the bits its fraction gives at that position, usually 0. CVTBx,
CVTWx and CVTLx are exact except CVTLF, which rounds a value of more than 24
bits.

### EMOD

EMODx mulr, mulrx, muld, int, fract: the multiplier extension (mulrx, a
byte for F and D, a word for G and H) supplies 8 (F, D), 11 (G: its bits
15:5) or 15 (H: bits 15:1) more fraction bits below mulr's. The product of
the extended multiplier and muld is chopped to 32 (F), 64 (D, G) or 128
(H) bits before it is normalized, as the SRM says; then its integer part
goes to int (the low-order 32 bits, integer overflow if it does not fit -
which is also how a floating overflow shows) and its fraction part, with
the same sign, is rounded to the format and goes to fract. The fraction can
round up to 1. An underflowing product faults with FU set, and otherwise
both parts are 0. N and Z come from fract, V from the integer overflow.

### POLY

POLYx arg, degree, tbladdr evaluates the polynomial by Horner's method from
the table, highest order coefficient first. A degree above 31 is a reserved
operand. R starts as the first coefficient; then, degree times, R becomes
R x arg + the next coefficient: the product chopped to 31 (F), 63 (D, G) or
127 (H) bits before it is normalized, then added to the coefficient, the sum
chopped the same way (below the leading bit of the larger operand, or of
the carry) before it is normalized and rounded, and checked for overflow
and underflow after every step (SRM, POLY). R0, R1'R0 or R3'R2'R1'R0 get
the result; R1, R2 (F), R2, R4, R5 (D, G) or R4 (H) become 0; R3 (R5 for
POLYH) points past the table.

The SRM lets an implementation either suspend POLY with PSL\<FPD\> set when
a floating fault, a memory fault or an interrupt comes in the middle, or
fault with nothing changed and start again. The core does the latter: POLY
holds interrupts off until it ends (some 100 microseconds for POLYH of
degree 31), a fault puts the registers back, and POLYH does not keep arg on
the stack (SRM, POLY note 9: an implementation that is never suspended need
not).

### ACB

ACBx limit, add, index, displ: index + add, rounded, is stored in index;
N and Z from it, V = 0, C unchanged. The branch is taken if add >= 0 and the
new index <= limit, or add < 0 and index >= limit. A floating overflow or
underflow fault leaves index as it was.

## Exceptions

| Event | Exception | Frame |
|---|---|---|
| Reserved operand (sign 1, exponent 0) in any floating source, POLY's degree above 31 | Reserved operand fault, SCB 18 | PC of the instruction, PSL |
| Floating overflow (also of a conversion to a smaller range) | Arithmetic fault, SCB 34, type 8 | type code, PC of the instruction, PSL |
| Floating divide by zero | Arithmetic fault, type 9 | the same |
| Floating underflow with PSL\<FU\> set | Arithmetic fault, type A | the same |
| Integer overflow (CVTxB/W/L, CVTRxL, EMOD) with PSL\<IV\> set | Arithmetic trap, type 1 | PC of the next instruction |

The floating exceptions are faults (types 8, 9, A), as the SRM's
descriptions of the floating point instructions say ("On floating overflow,
the instruction faults"; the trap types 3, 4, 5 of its table of arithmetic
exceptions are not produced): nothing is stored, and the registers changed
by the operand specifiers - (Rn)+, -(Rn) - are put back, so the handler sees
the instruction as it was. The
microcode writes the type code to internal register 76 (`IPR_AFLT`) and
ends in a reserved operand fault; `ENDINST` then restores the instruction
(`XFAULT`) and enters the arithmetic exception microcode, which reads the
code from `IPR_ARITH` and clears it. With PSL\<T\> set the frame has
PSL\<TP\> clear, as for any fault.

A destination of more than four bytes in memory is checked for writing at
both ends before anything is stored (`fp_q`, `fp_wr`), and EMOD checks the
fraction's destination before it stores the integer, so a translation
fault leaves the destinations as they were and the instruction can run
again with the same sources even when they overlap.

## Microcode

`rtl/ucode.def`, after the octaword instructions. Most instructions are one
step that loads a command constant and jumps to a common tail:

- `fp_l`, `fp_q`, `fp_o`: give the command, check the status, and store an
  F result (in argd0, stored by the hardware writeback), a D or G result
  (argd0 and argd1, the writeback stores both, after `fp_q` has checked a
  memory destination), or an H result (`fp_wr`).
- `fp_t`: TST and CMP, only condition codes.
- `fp_cvi`: conversions to integers, N and Z on the byte, word or longword
  stored.
- `fp_exc`: the exceptions.
- `fp_wr`: stores the result of 8 or 16 bytes into registers Rn.. or memory
  and returns through X0; used by H results, EMOD's fraction and the index
  of ACBD, ACBG, ACBH.
- `em`, `poly`, `acbx`: EMOD, POLY (with `poly_rd`, which reads a
  coefficient into W0-W3), ACB.

## Tests

- `sim/fpu_tb`: `vaxfp.py` is an exact model of the arithmetic, written
  from the SRM with Python fractions (it shares no code with the unit), and
  writes random test vectors: ordinary values, zeros, dirty zeros, reserved
  operands, the largest and smallest values, fractions of all ones and of
  few bits (ties and carries), close pairs for cancellation, for every
  command and format, with PSL\<FU\> set and clear. `make -C sim fputb`
  builds the unit alone under Verilator; `fpu_tb.cpp` feeds it the vectors.
  Some 150 000 vectors pass.
- `tests/mmu/t41_octa.s`: the two-byte opcodes and octaword operands in
  every addressing mode, the condition codes, an opcode split across a page
  boundary, a destination running into an invalid page, the reserved
  addressing mode for AP, FP, SP, undefined FD opcodes.
- `tests/mmu/t42_fpf.s` to `t45_fph.s`, generated by
  `tests/mmu/gen/mk_fp.py`: some 1 600 cases of every instruction of each
  format on random operands in register, memory, short literal and
  immediate modes, with FU and IV set at random; every fault and trap is
  logged. They are compared with the reference simulator, like the rest of
  `tests/mmu`, and go into the board suite (`software/mmutest.bin`).
- `tests/mmu/t46_fpexc.s`: the exceptions in detail - frames, registers put
  back, TP with trace, CVTR's halves, dirty zeros, destinations and a POLY
  table running into an invalid page.
- `tests/fp/mkfptest.py` builds `software/fptest.bin`, a self-checking
  program for the core itself (board or simulation): any number of random
  cases of each of the 98 instructions (`--seed`, `--cases`, `--only`),
  with the expected result, condition codes and exception worked out by
  `vaxfp.py` and the SRM's instruction rules, so it needs no reference
  simulator. The driver (`tests/fp/fpharness.s`) sets FU, IV and the
  condition codes at random, fills the destination with random bytes, runs
  the instruction once and compares the exception, the condition codes
  (not after a fault) and the destination (unchanged after a fault). See the
  README, *Testing the floating point instructions with your own random
  cases*.
- EVKAC, DEC's floating point exerciser (ZZ-EVKAC 7.2), under the
  Diagnostic Supervisor: all 98 tests pass in the full-system simulation,
  with the QUICK flag (each case once per addressing mode combination) and
  without it (each case again with its operands across page boundaries that
  fault). See the README, *Running EVKAC*.

One difference from the reference simulator is documented in `t41_octa`:
for an octaword destination that runs into an invalid page, the simulator
reports the translation fault with access parameter 0 (a read); the core
reports 4 (write intent), as the SRM says for a write (SRM 4.9). The
faulting virtual address may also be another one in the same page, which
the SRM allows ("some address in the faulting page").

## Resources

From a Yosys synthesis for Cyclone V (`synth_intel_alm`), until Quartus
gives the real figures: `fpunit.v` is about 9 700 LUTs (2 100 of them adder
cells on carry chains), 3 100 registers and 16 multipliers (eight 27 x 27
and eight 18 x 18, some twelve of the 112 DSP blocks), and no block RAM.
Most of it is the 128-bit datapath: the operand and result registers, the
alignment and normalisation shifters, the adder, the product accumulator
and the divider. The changes to `cpu.v` add little logic. The whole core
comes to about 25 900 LUTs (README, *Building*).

## Files

| File | What |
|---|---|
| `rtl/fpunit.v` | The floating point unit |
| `rtl/cpu.v` | Two-byte opcodes, 16-byte operands, the unit's operand loads and registers, the floating fault (`afault_code`) |
| `rtl/ucode.v`, `rtl/mkucode.awk` | 512 instruction ROM rows, the new argument fields and operand types (`o f d g h`) |
| `rtl/ucode.def` | The microcode and the instruction table |
| `rtl/ipr.vh`, `rtl/opcodes.vh` | `IPR_FPU` (50), `IPR_AFLT` (76), `PSL_FU` |
| `tools/vasm.py`, `tools/vaxfloat.py` | Two-byte opcodes; floating constants: `.f_floating`, `.d_floating`, `.g_floating`, `.h_floating`, `.octa`, and `#1.5` as an operand (a short literal when it is one); `vaxfloat.py -d` turns the bits back into a number |
| `sim/fpu_tb/` | The unit test |
| `tests/mmu/t41_octa.s` ... `t46_fpexc.s`, `tests/mmu/gen/mk_fp.py` | The instruction tests |
| `tests/fp/mkfptest.py`, `tests/fp/fpharness.s` | The random test for the core (`software/fptest.bin`) |
