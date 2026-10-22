# Decimal and string instructions on the MiSTer VAX 8600

The VAX 8600 has the whole VAX instruction set in hardware, the decimal
string instructions and the long character string instructions included
(the commercial instruction set, CIS, which the MicroVAX left to software).
This page describes how the core does them: microcode in `rtl/ucode.def`,
helped by a small decimal unit, `rtl/decunit.v`. The VAX Architecture
Reference Manual defines every result, condition code and register value;
where it leaves a choice, the core makes the one a VAX 8600 reference
simulator makes, and the tests compare the two on random operands.

## The instructions

| Group | Instructions |
|---|---|
| Decimal (packed) | MOVP, CMPP3, CMPP4, ADDP4, ADDP6, SUBP4, SUBP6, MULP, DIVP, ASHP, CVTLP, CVTPL, CVTPS, CVTSP, CVTPT, CVTTP, EDITPC |
| Character string | MOVTC, MOVTUC, MATCHC, CRC (MOVC3, MOVC5, CMPC3, CMPC5, LOCC were there), SKPC, SCANC, SPANC |
| Other integer | INDEX, ADAWI, INSQHI, INSQTI, REMQHI, REMQTI |

The four octaword instructions of the group (CLRO, MOVO, MOVAO, PUSHAO) use
two-byte opcodes (prefix FD); they came with G and H floating point and are
described in [FPU.md](FPU.md).

## The decimal unit

A packed decimal string of up to 31 digits is held as 32 BCD nibbles in 128
bits, exactly as its bytes stand in memory, right-aligned: nibble 0 is the
sign position (kept at 0 while the value is worked on), nibble 1 the least
significant digit, nibble 31 the most significant.

The unit has two operand registers A and B (A also takes the result), two
working registers C and D for MUL and DIV, a 32-bit register X for the
binary conversions, and four longwords U0-U3 in which the microcode keeps
the operands while its subroutines run. The microcode reaches it as
internal processor registers 60-6F, which MTPR and MFPR cannot reach:

| Register | Write | Read |
|---|---|---|
| 60 | a command (below) | status: busy, A = 0, A > B, A = B, overflow, CVTPL overflow, B = 0, the highest nonzero nibble of A and of B |
| 61 | the next byte of A (shifted in from the right; flags for the first byte and the sign byte) | the top byte of A |
| 62 | the same for B | nibble *n* of A |
| 63 | X | X |
| 64-67 | U0-U3 | U0-U3 |

Commands: CLR, SWAP, COPY, ADD (A + B, a carry out of the 31st digit is
overflow), SUB (A - B), RSUB (B - A), SHL and SHR by *n* digits (left: a
nonzero digit shifted out is overflow), ROL by *n* nibbles (to write a
string out), SETLEN *n* (the digits above the destination's length make
overflow and are cleared), SETNIB, SETIDX, MUL, DIV, CVTLP, CVTPL, CLROVF and
INC. Addition and subtraction work 8 digits a clock, ripple-carry within the
32 bits (a ten's-complement add for the subtractions); MUL adds the
multiplicand once for each unit of each multiplier digit and shifts the
product down a digit at a time into A; DIV aligns the
divisor with the dividend and subtracts it while it fits, one quotient digit
at a time; CVTLP is a 32-step double dabble, CVTPL 31 steps of times ten
plus the next digit (overflow when the value passes 2^32 - 1; the microcode
then checks the signed range). The longest command, a 31 by
31 digit MUL or DIV, takes about 1500 clocks.

A command keeps the CPU in a new state, DUWAIT, until the unit is done, so
the microcode never polls it.

## The microcode

Two subroutines do the memory side of every decimal instruction. `dsrd`
reads a string into A or B: the first byte of a string of even length has
no high digit, the low nibble of the last byte is the sign (B and D minus,
anything else plus), and a zero is plus. `dswr` writes A
as a string of the destination's length: the digits that do not fit make V,
the sign is the preferred one (C or D) and is plus for a zero result
without overflow, PSL N Z V are set, and V with PSL<DV> requests the decimal
overflow trap (type 6). A subroutine
returns through a computed goto, a new destination `jmp` of the microcode
ALU, to the address the caller left in a register (`@label` constants).

Faults: a source string may fault while it is read, and the instruction is
started again from the beginning (the registers, PC and PSL are put back as
for any fault). Before the first byte of a destination is stored, its first
and last bytes are probed for writing, so that a fault cannot leave a
destination half written - which matters, because the destination of ADDP4
and SUBP4 is also a source. The general registers are written only at the
end; until then the operands are kept in U0-U3.

Traps: DIVP by zero is the decimal divide by zero trap (type 4), with
nothing else done; a destination too short gives V and, with
PSL<DV>, the decimal overflow trap (type 6); CVTPL with a result that does
not fit in a longword gives V and, with PSL<IV>, the integer overflow trap.

EDITPC runs its pattern with all of its state in microcode registers: the
digits and leading zeros still to come (EO$ADJUST_INPUT supplies zeros or
drops digits), the source, pattern and destination addresses, and the sign
character, fill character and condition codes together in one register. A
reserved operand (an undefined operator, a zero repeat count or length, the
source used up too early or not used up at EO$END) is a fault. EO$FLOAT
clears Z only for the digit that sets significance.

MOVTC translates forward, or backward when the source is below the
destination, so that overlapping strings come out right; before it moves a
byte it reads the first and last entries of the table and one byte in every
page of the source, and probes every page of the destination for writing,
so that no fault can come once it has started; MOVTUC stops at a
byte that translates to the escape character (V); MATCHC finds the object
string in the source (an empty object at once); CRC takes four bits at a time
through the 16-longword table. SKPC, SCANC and SPANC are LOCC's companions.

MOVTUC, MATCHC and CRC can be stopped part way, as MOVC3 and MOVC5 are
(docs/MMU.md): a memory management fault, or an interrupt that becomes
pending while they run, makes the microcode store their progress in R0-R5
(the instruction's length in bits 31:24 of R0, of R2 for
CRC, so that the next PC can be found again), set PSL<FPD>, put the PC back
at the opcode and clear PSL<TP>, and then take the fault or the interrupt.
When the instruction is fetched again with FPD set, it skips its operands
and goes on from R0-R5. Each loop does all its memory references for a byte
before it changes its state, so the step that faulted is simply done again.
For MOVTUC this is a matter of the result, not only of speed: a
translation in place, with the source and the destination at the same
address, which the SRM defines, would translate again the bytes before the
fault if it started from the beginning.
INDEX checks the subscript against both limits with signed compares that
cannot overflow and requests the subscript range trap (type 7). ADAWI takes
its sum as a write operand, so that an odd address is a reserved operand
before the word is read. The interlocked queue instructions check every
alignment the SRM asks for (reserved operand), answer "interlocked" (C, or V
and C) when the header's bit 0 is set, and probe every page they will write
before writing anything; with one processor nothing else can see the queue
in the middle of the instruction, so the interlock bit is not set in memory.

## Where the core and the reference simulator differ

* MOVTC, EDITPC and the decimal instructions run to the end without
  looking at interrupts, and after a fault they start again from the
  beginning, with the registers put back; the reference simulator keeps the
  progress of MOVTC and EDITPC in R0-R5 with PSL<FPD>. Both are allowed by
  the architecture,
  and it shows only in the registers a fault handler sees: MOVTC, whose
  source and destination may overlap, cannot fault once it moves (above),
  and EDITPC and the decimal instructions write destinations that the SRM
  does not allow to overlap their sources, so doing them again from the
  start gives the same result.
* MOVTUC and CRC take interrupts part way (with PSL<FPD>); the reference
  simulator takes them between instructions, but in the middle of MATCHC,
  as the core does.
* CVTPT probes the last byte of its destination, the reference simulator
  the byte after it.

## How it was checked

* `sim/du_tb/du_tb.cpp` (`make -C sim dutb`, `sim/obj_du/Vdecunit 20000`):
  the decimal unit alone against a C model of the same operations on random
  operands: ADD, SUB, RSUB, the status bits, MUL, DIV, CVTLP, CVTPL, SHL,
  SHR, SETLEN, the nibble access, INC.
* `tests/mmu` (run with `tests/mmu/run.py`, as the memory management tests):
  t31 (arithmetic traps, with INDEX's), t32 (trace), t33 (INDEX, SKPC,
  LOCC, SCANC, SPANC, ADAWI and the interlocked queues, their reserved
  operand faults included), t34 (MOVTC, MOVTUC, MATCHC, CRC), t35 (the
  sixteen decimal instructions on random operands, with PSL<DV>, PSL<IV>
  and C set before some, zero divisors among them), t36 (EDITPC with every
  operator, classic patterns and random ones), t37 (bit fields with a high
  base address), t39 (MOVTUC, MATCHC and CRC stopped by a page fault and
  by timer interrupts, with trace on; a MOVTUC in place across an invalid
  page), t40 (CMPC3 and CMPC5). The generators are in `tests/mmu/gen`; t35 and t36 take a
  seed: other seeds were run too (another 900 decimal and 240 EDITPC cases),
  all the same as the reference simulator.
* DEC's EVKAB, the basic instruction exerciser, under the 8600 Diagnostic
  Supervisor (README_MiSTer.md).

## Files

| File | What |
|---|---|
| `rtl/decunit.v` | New: the decimal unit |
| `rtl/cpu.v` | The decimal unit at internal registers 60-6F, the DUWAIT state, the computed goto, argp0/argp1 as right ALU operands, savpsw<5:4> (argp0, argp1 are registers) |
| `rtl/ucode.def` | The instructions above; `dsrd`, `dswr`, `ed_dig` |
| `rtl/mkucode.awk`, `rtl/ucode.v` | 4096 microcode steps (12-bit step addresses), 512 argument entries |
| `sim/du_tb/du_tb.cpp`, `tests/mmu/t3[1-9]*.s`, `t40_cmpc.s`, `tests/mmu/gen/` | Tests |
