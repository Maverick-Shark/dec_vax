# Memory management on the MiSTer VAX 8600

r-vax had no memory management: `MAPEN` only changed the width of the address.
This note describes what was added for the MiSTer port - the translation
buffer, the page table walk, the faults, and the parts of the privileged
architecture that only make sense with them - where each rule comes from, and
how it was checked.

The rule from [ROADMAP.md](../ROADMAP.md) applies: whatever software can
observe behaves like a **VAX 8600**. DEC's documents define the behaviour,
a VAX 8600 reference simulator run on the PC is the executable cross-check,
and no logic is taken from other VAX implementations.

Status: complete. 47 directed tests give the same results as the reference
simulator (or, where it departs from the SRM, the SRM's); EVKAA,
`hello.bin` and `bench.bin` still pass; the Quartus build meets timing and
the memory management tests pass on the board. DEC's EVKAE, under the 8600
Diagnostic Supervisor, passes 10 of its 11 tests in simulation; the other
needs PDP-11 compatibility mode.

## Sources

| Document | Used for |
|---|---|
| *VAX Architecture Reference Manual*, EY-3459E-DP (1987), chapter 4, Memory Management | Regions, PTE format, length checks, protection codes, modify bit, the two faults and their parameter, PROBE, TBIA/TBIS/TBCHK, MAPEN |
| same, chapter 5, Exceptions and Interrupts | Initiating an exception (the new PSL is set before the pushes), kernel stack not valid, interrupt stack not valid, REI and its checks, ASTs, PSL\<FPD\> |
| same, chapter 6, Process Structure | LDPCTX, SVPCTX and the process control block |
| *DEC STD 032, VAX Architecture Standard*, EL-00032-00 (1990), chapter 4 | The same rules in their normative form, with the pseudo-code for translation and PROBE |
| DEC STD 032, appendix B, VAX 8600 | The 8600's halt codes (table B-24: 4 interrupt stack not valid, 6 kernel mode HALT, 7 and 8 bad SCB vectors, A and B CHMx, 11 invoked by console) and IPR numbers (table B-25) |
| *VAX 8600 Training Print Set*, EY-4818E-PP | The M-box address module: the 8600's translation buffer |
| VAX 8600 I-box microcode listing (`venus-ibox.pdf`) | How the 8600 undoes the register changes of a faulting instruction (the RLOG and its unwind microtrap) |

## Where it sits

```
cpu ── vcache ── mmu ──┬── vax_cache ── vax_sdram ── 32 MB SDRAM   (0000 0000-01FF FFFF)
     (aligner)         └── SBI / DW780 / RH780 register stubs       (2000 0000 and up)
```

`rtl/mmu.v` goes into the slot r-vax's own original top level (`sbi.v`)
describes as "cpu, mmu, cache": after the aligner, so every cycle it sees is
one aligned longword inside one page, and before the cache, which therefore
stays physically indexed and tagged with no aliasing to worry about.

Besides address and data, the CPU tells the MMU, for each access:

| Signal | Meaning |
|---|---|
| `pmem` | Physical reference, no translation: SCB vectors, the PCB in LDPCTX/SVPCTX, the console's `P` command |
| `wint` | Write or modify intent: set for writes, for the read half of a modify operand, and for the reads `vcache` does before a partial or unaligned write |
| `probe` | PROBER/PROBEW (or, with `pmem`, the TBCHK test): answer the question, touch nothing |
| `mode` | Access mode for the protection check: PSL\<CUR_MOD\>, or the probe mode |
| `con` | Console access while the CPU is halted: never faults |

With `MAPEN` clear, or for a physical reference, the address goes straight
through (PA\<29:0\> = VA\<29:0\>) in the same clock: a program that does not
turn on memory management runs exactly as fast as before.

## Translation buffer

As on the 8600 (Training Print Set, address module): **512 entries, direct
mapped**, addressed by VA\<31\> and VA\<16:9\>, tag VA\<30:17\>, holding the
PFN, the protection code and the modify bit. VA\<31\> splits it into a system
half and a process half.

| Bits | Field |
|---|---|
| 39:26 | Tag, VA\<30:17\> |
| 25:5 | PFN |
| 4:1 | Protection code |
| 0 | M |

The entries are one 512 x 40 M10K RAM (two blocks). The valid bits are 512
flip-flops, so that every flush takes a single clock:

| Event | Effect |
|---|---|
| MTPR to P0BR, P0LR, P1BR, P1LR (and so LDPCTX) | Process half invalid |
| MTPR to SBR, SLR, MAPEN; MTPR TBIA | Whole TB invalid |
| MTPR TBIS | The entry for that address invalid |
| MTPR TBCHK | PSL\<V\> set if the TB holds a valid translation for the page |

Only valid PTEs are ever loaded. A miss loads the PTE that was used, and for a
process page also the system PTE that maps its page table.

## Translation

On a TB miss, a walker in the same module follows chapter 4 of the SRM:

* **S0** (VA\<31:30\> = 10): VPN must be below SLR; the PTE is at physical
  SBR + 4 x VPN.
* **P0** (00): VPN must be below P0LR. **P1** (01): VPN must be at least P1LR.
  The PTE is at the system virtual address PxBR + 4 x VPN, which is translated
  first - through the TB, or through its system PTE (length check against
  SLR, valid bit), which is then kept in the TB.
* **S1** (11): always a length violation.

Then the access is checked: the protection code against the mode first
(access-control violation), the valid bit second (translation not valid), so
ACV wins when both apply. A write or modify access to a page whose PTE has M
clear writes the PTE back with M set before the access, and the TB entry is
loaded with M set; a write that hits an entry with M clear goes through the
walk once to set it.

Protection codes (SRM table 4.3), as a table of which modes may read and
which may write:

| Code | Name | Read | Write |
|---|---|---|---|
| 0 | NA | - | - |
| 1 | reserved | - | - |
| 2 | KW | K | K |
| 3 | KR | K | - |
| 4 | UW | KESU | KESU |
| 5 | EW | KE | KE |
| 6 | ERKW | KE | K |
| 7 | ER | KE | - |
| 8 | SW | KES | KES |
| 9 | SREW | KES | KE |
| 10 | SRKW | KES | K |
| 11 | SR | KES | - |
| 12 | URSW | KESU | KES |
| 13 | UREW | KESU | KE |
| 14 | URKW | KESU | K |
| 15 | UR | KESU | - |

Cost when mapping is on: a TB hit adds two clocks to each longword access.
On the CPU test bench (plain memory, two wait states) a loop of ADDL2, MOVL
store, MOVL load and SOBGTR goes from 28.3 to 31.3 clocks per instruction,
about 10 %. Issuing the bus cycle in the same clock as the TB compare would
save one of the two clocks; it is left for when Quartus has shown how much
timing margin there is.

## Faults

A refused access is not done. The MMU reports:

* the **parameter** of SRM table 4.4: bit 0 length violation, bit 1 PTE
  reference (the fault happened on the page table of a process address),
  bit 2 write or modify intent;
* the **virtual address**: the address of the longword being accessed, which
  lies in the faulting page (the SRM asks for "some address in the page");
  for a PTE-reference fault, the process address;
* which **vector**: access-control violation (SCB 20) or translation not
  valid (SCB 24).

The CPU stops the instruction at once and puts everything back as it was when
the instruction started: R0-R14, PC and PSL (see the next section). Then it
initiates the exception as SRM 5.6 describes: the new PSL first (kernel mode,
PRV_MOD = the old mode, IPL unchanged, on the kernel stack unless already on
the interrupt stack), then it pushes PSL, PC, the virtual address and the
parameter, and continues at the vector.

Errors while doing that:

* **Kernel stack not valid.** If a push of the exception frame onto the kernel
  stack faults, the CPU takes SCB 08 on the interrupt stack at IPL 1F, with
  the PC and PSL of the exception it was trying to take.
* **Interrupt stack not valid.** If a push onto the interrupt stack faults,
  the processor halts with **halt code 4**, the 8600's code for this case.
* The **console** never takes a fault: an `nV` reference that does not
  translate reads as 0, and a deposit to it is dropped.

A partial or unaligned write is safe: `vcache` reads every longword it will
write, with write intent, before it writes any of them, so a fault on the
second page of an operand leaves the first page untouched.

## Restarting instructions

r-vax changes registers while it decodes operands (autoincrement,
autodecrement, deferred) and in the middle of multi-step instructions
(CALLS, PUSHR, ...). The 8600 undoes such changes with its register log: the
I-box records each change, and a microtrap unwinds the log when an
instruction has to be backed out. The core does the same job with a **shadow
copy of R0-R14**, taken in one clock when each instruction starts and copied
back in one clock on a fault. The register file is already in flip-flops,
so this is 15 x 32 more flip-flops and no extra time.

Instructions that can run long and write memory keep their progress in
registers, as the architecture defines:

* **MOVC3 and MOVC5** run on one engine that keeps its state in R0-R5. On a
  fault part way through, the shadow copy is not used: the CPU sets
  PSL\<FPD\>, leaves PC at the MOVC, and takes the fault. After the REI the
  instruction sees FPD set, skips the operand decode and carries on from
  R0-R5. The same happens when an interrupt above the current IPL becomes
  pending during the move: it is taken in the middle of the instruction, as
  on a real VAX, so a long move does not hold off the interval timer. Like
  a fault, such an interrupt clears PSL\<TP\> in the saved PSL (SRM 5.4.4,
  rule 3), so that a traced MOVC is traced once, when it completes (EVKAB
  test 134 checks this).
  The intermediate contents of R0-R5 are implementation specific, as the SRM
  allows.
* MOVTUC, MATCHC and CRC do the same ([CIS.md](CIS.md)).
* Every other instruction restarts from its beginning. That is correct for all
  of them: the ones that only read memory (CMPC3, LOCC, ...) can simply run
  again, and the ones that write (CALLS, PUSHR, MOVQ, ...) write the same
  values again after the registers have been restored.

The instruction stream needs nothing special: r-vax fetches instruction bytes
when it needs them, so an instruction-stream fault is only taken when the
bytes are really used, with the PC of the instruction they belong to.

## Resources

From a Yosys synthesis for Cyclone V (`synth_intel_alm`), until Quartus
gives the real figures: `mmu.v` alone is about 2 000 LUTs, 1 000 registers
and 2 M10K blocks - most of the logic is the 512 valid bits, their decoder
and their read multiplexer. The whole change, with the register shadow, the
new CPU signals and the step store doubled to 2048 words, adds about 2 750
LUTs, 1 550 registers and 8 M10K to the core.

## The privileged architecture around it

These were added or completed together with the MMU, or after it to run
EVKAE, because the tests and any operating system need them:

* **MTPR and MFPR** are privileged: outside kernel mode they take the
  privileged-instruction fault (the reserved instruction vector, SCB 10). A
  register number above 7F, or one the machine does not have, is a reserved
  operand. The value checks: P0BR must be an S0 address with bits 1:0 clear (P1BR the same, tested on
  P1BR + 2^23), SBR, PCBB and SCBB must have bits 1:0 clear, a length above
  2^21 is reserved, ASTLVL must be 0-4. MFPR reads all the memory management
  registers, PCBB, SCBB, ASTLVL and MAPEN. MAPEN (38) can now be set (r-vax
  answered a reserved operand fault), and TBIA (39), TBIS (3A) and TBCHK (3F)
  act on the TB.
* **PROBER and PROBEW**: the mode is the less privileged of the operand and
  PSL\<PRV_MOD\>; the first and last byte are checked; the valid bit is
  ignored and a length violation means "not accessible"; only an invalid
  system PTE for a process page table gives a fault (translation not valid,
  PTE reference). Z is set if the access would not be allowed.
* **LDPCTX and SVPCTX** (new): PCB layout of SRM chapter 6, through physical
  references at PCBB: the four stack pointers, R0-R13, PC and PSL, P0BR,
  P0LR with ASTLVL in bits 26:24, P1BR, P1LR. LDPCTX leaves the CPU on the
  kernel stack with PC and PSL of the new process pushed for the REI; SVPCTX
  pops them and moves to the interrupt stack.
* **REI** with all the checks of SRM 5.7 (a reserved operand fault for a PSL
  with must-be-zero bits set, a return to a more privileged mode, PRV_MOD
  more privileged than CUR_MOD, the interrupt stack outside kernel mode or
  with IPL 0, a higher IPL, and so on), and AST delivery: when the number of
  the new mode is at least ASTLVL (ASTLVL = 3 delivers on the return to user
  mode) and the processor is not on the interrupt stack, REI requests the
  IPL 2 software interrupt.
* **CHMK, CHME, CHMS and CHMU** as the SRM's CHMx: the new mode is the more
  privileged of the operand's mode and the current one, the old stack
  pointer is saved, and the new mode's stack is probed for writing (bytes
  SP-1 and SP-12, in the new mode) before the frame - sign-extended code, PC,
  PSL - is pushed; the vector is SCB 40 + 4 x mode. On the interrupt stack the
  8600 halts with code A instead, and through a vector with bits 1:0 not zero
  with code B.
* **BPT** (SCB 2C) and **XFC** (SCB 14) are faults with the PC at the opcode.
* **The reserved instruction fault** (SCB 10, PC at the opcode) for an opcode
  the microcode does not have, and for a privileged instruction outside
  kernel mode. **HALT** is privileged: in kernel mode the 8600 halts with
  code 6, elsewhere it is a reserved instruction.
* **The reserved addressing mode fault** (SCB 1C), with the cases the SRM
  leaves UNPREDICTABLE decided this way: a literal for anything but a read
  operand; a register for an address
  operand, PC as a register, SP for a quadword; PC with register deferred or
  autodecrement mode or as an index register; index mode with a literal,
  register or index base. (Immediate mode as an index base is legal on the
  8600, as on the 780.) The decoder checks each specifier as it reaches it,
  so the registers changed by earlier operands are put back with the rest.
* **SCB vectors with bits 1:0 = 2 or 3** halt the 8600 with code 8 (service
  in writable control store, which it has not got) or 7.
* **The console halt**: Ctrl+P on the keyboard or the MiSTer UART, or the OSD
  trigger, stop the CPU before the next instruction with the 8600's code 11
  ("invoked by console"); the console monitor's `G` continues.
* **The internal processor registers** are the 8600's that hold a value
  (registers above 4F do not exist). MTPR accepts the architectural ones (SISR among them, bits 15:1),
  ICCS, NICR, TODR, RXCS, TXCS, TXDB, PME (bit 0), and of the 8600's own
  ACCS (no floating point accelerator: ignored, reads as 0), PAMACC
  (ignored), PAMLOC, CSWP (bits 3:0), MDCTL (bits 14:13, 11:8, 3:0), MERG and
  CRBT (ignored) and EHSR (bit 5). MFPR reads the same set less the
  write-only ones (SIRR, TBIA, TBIS, TBCHK, TXDB, CRBT) plus ICR, RXDB and
  SID. Anything else - the 780's and 750's registers among them - is a
  reserved operand. The console storage registers STXCS and STXDB are not
  there yet. MTPR to SIRR with level 0 requests nothing.
* **Processor initialization** - the reset at power-up, with the OSD *Reset*
  and with every *Load Program* - sets what the SRM's chapter *System
  Bootstrapping and Console* lists: PSL `041F0000`, ASTLVL 4, SISR 0, MAPEN 0
  (and the TB invalidated), PME 0, ICCS\<6\> and \<0\> clear (the interval
  clock stops, with no request pending), RXCS 0 and TXCS\<IE\> clear. No
  instruction, interrupt or memory reference is left in progress, and the
  console monitor starts afresh. ASTLVL, SISR, MAPEN and PME are read from
  registers that the reset clears, not from the IPR RAM, which it cannot.
* **Trace** (PSL\<T\> and \<TP\>): when an instruction is about to be
  fetched, a set TP takes the trace fault (SCB 28) with TP clear in the
  saved PSL and the PC of that instruction; otherwise TP is loaded from T as
  the instruction starts. Traps and interrupts are looked at first and save
  TP set, so the trace fault comes when their handler returns; faults (the
  memory management ones, reserved operand and instruction, BPT, XFC, a
  machine check) clear TP, so the instruction is traced once, when it
  completes. REI keeps TP set if it was (REI itself is traced) or takes it
  from the saved PSL; CHMx saves it; CALLx saves the PSW with T clear and
  RET restores it.
* **Arithmetic traps** (SCB 34, the type code pushed after PC and PSL),
  taken after the instruction has stored its results and before interrupts:
  integer overflow (type 1) when PSL\<IV\> is set and an instruction that can
  overflow (instruction flag `intov`: ADD, SUB, INC, DEC, MNEG, MUL, DIV,
  ADWC, SBWC, ADAWI, ACB, AOB, SOB, ASHL, ASHQ, EDIV, CVTLB, CVTLW, CVTWB,
  CVTPL) ends with V set; integer divide by zero (2: DIVx gives the
  dividend, EDIV the low dividend and remainder 0, both with V), decimal
  divide by zero (4), decimal overflow (6) and subscript range (7, INDEX),
  which the microcode requests through a new internal register (IPR_ARITH,
  74). DIVx overflow (most negative / -1) gives the dividend.
* **RET** restores PSW\<15:0\> from the frame (DV, FU, IV, T and the
  condition codes; r-vax cleared it) and a frame with PSW\<15:8\> not zero is
  a reserved operand; CALLG and CALLS take an entry mask with bits 13:12 set
  as a reserved operand, before anything is pushed.
* **The interval clock** interrupts when ICR overflows as it counts, as the
  SRM has it: r-vax set INT as soon as ICR held FFFFFFFF, so loading NICR =
  -1 with XFR interrupted before RUN, and the INT that the software then
  cleared never came back (EVKAB's initialization measures the clock that
  way).

Found while getting the Diagnostic Supervisor and EVKAE to run (next
sections), and fixed, each with a test in `tests/mmu`:

* CASEB, CASEW and CASEL compared the selector with the limit as signed
  numbers and set the condition codes at 32 bits; the limit is unsigned,
  and the codes are those of a compare at the operand's size.
* BBS, BBC and the BBxx modify forms read the base as a longword; the field
  is the byte at base + position/8, with a signed position, and a position
  above 31 in a register is a reserved operand.
* ACBB and ACBW did not exist, and ACBL compared index and limit by the sign
  of their difference, which fails when the subtraction overflows.
* CVTWB, CVTLB and CVTBW had opcodes but no microcode.
* The interrupt and exception microcode ran with the byte or word ALU size of
  the instruction just finished: after an INCB or a DECW a timer interrupt
  read its own level wrongly and went through SCB E0.

Found with EVKAB, or while adding the arithmetic traps, and fixed:

* ASHL and ASHQ missed the overflow of the last shift step (ASHL 1 of
  40000000); ASHL now uses the barrel shifter both ways, with the SRM's
  results for counts of 32 and more.
* ADWC and SBWC set V when the first of their two additions overflowed and
  the second undid it (80000000 + FFFFFFFF + C); V is now that of the whole
  sum.
* AOBLEQ set V when the index went from -1 to 0, AOBLSS did not set V at
  all, AOBLSS, AOBLEQ and SOBGTR compared with a subtraction that can
  overflow (SOBGTR branched for 80000000).
* LOCC took its length as a signed word.
* The bit field instructions (BBx, INSV, EXTV, EXTZV, CMPV, CMPZV, FFS, FFC)
  and ADAWI took a base address with bits 31:30 set for a register (their
  register test looked at the address): a base in S1 space with a position
  that wraps the field back into P0 space is legal. The microcode now has a
  flag for it (savpsw\<5:4\>).

## How it was checked

`tests/mmu/` holds 47 test programs in VAX assembler (assembled by
`tools/vasm.py`). `tests/mmu/run.py` runs each one on the reference
simulator and on a CPU-level test bench (`sim/cpu_tb/`: cpu, vcache, mmu and 8 MB of plain
memory), and compares R0-R14, PSL, PC after the final HALT, and the memory
the test names, which includes a log that the fault handlers write: for every
fault, its parameter, VA, PC, PSL and the PSL the handler ran with.

| Test | What it checks |
|---|---|
| t00_harness | The harness itself |
| t01_xlate | Translation through S0 and P0, M bits, TBCHK, TBIS |
| t02_tnv | Translation not valid on a read and a write: the frame, and the restart after the fix-up |
| t03_acv | Access-control violations; ACV wins over TNV |
| t04_lnv | Length violations in S0, P0, P1 and S1 |
| t05_pteref | Faults on the reference to a process page table |
| t06_probe | PROBER/PROBEW: mode, first and last byte, valid bit ignored, length |
| t07_unaligned | Accesses that cross a page boundary: fault on the second page, nothing written |
| t08_autoinc | (Rn)+, -(Rn), @(Rn)+ undone by a fault and done once after it |
| t09_user | Faults from user mode, the frame PSL, CHMK back to kernel |
| t10_ksnv | Kernel stack not valid |
| t11_mbit | PTE\<M\>: set by writes, modifies and unaligned writes, not by reads |
| t12_mtpr | MTPR/MFPR of the memory management registers and their reserved operands |
| t13_movc | MOVC3/MOVC5: forward, backward with overlap, fill, all length cases |
| t14_movcflt | MOVC3/MOVC5 that fault part way and resume with PSL\<FPD\> |
| t15_movcint | Interval timer interrupts in the middle of a long MOVC3 |
| t16_isnv | Interrupt stack not valid: halt code 4 |
| t17_ctx | Two processes with their own P0 page tables, switched by SVPCTX/LDPCTX |
| t18_rei | REI checks, AST delivery, MTPR from user mode |
| t19_chmx | CHMK, CHME, CHMS, CHMU from every mode: new mode, stacks, frame |
| t20_chmprobe | CHMx onto a stack that is not writable: the probe faults before the push |
| t21_bpt | BPT and XFC faults, HALT outside kernel mode, an undefined opcode, HALT in kernel mode (code 6) |
| t22_chmis | CHMx on the interrupt stack: halt code A |
| t23_vec3 | An exception through an SCB vector with bits 1:0 = 3: halt code 7 |
| t24_chmvec | CHMx through a vector with bits 1:0 not zero: halt code B (checked against the SRM, where the reference simulator differs) |
| t25_case | CASEB, CASEW, CASEL: unsigned limit, condition codes at the operand size |
| t26_bbx | BBS, BBC and the modify forms with positions outside the base byte, negative, in a register |
| t27_ipr | The 8600's internal registers: what reads back, which numbers are reserved |
| t28_acb | ACBB, ACBW, ACBL at the edges of their ranges; CVTLB, CVTWB, CVTBW, CVTLW |
| t29_resad | Reserved addressing mode faults, and the legal cases next to them |
| t30_intsize | Interval timer interrupts right after byte and word instructions |
| t31_arith | Arithmetic traps: integer overflow with and without PSL\<IV\>, divide by zero, the results of the overflowing instructions; IV through the CALLx entry mask and RET; the reserved operands of CALLx and RET |
| t32_trace | Trace: BISPSW/BICPSW, with an arithmetic trap, BPT, XFC, a reserved operand, a page fault, a software interrupt, CALLS/RET, REI, CHMK |
| t33_strq | INDEX (subscript range trap), SKPC, LOCC, SCANC, SPANC, ADAWI, INSQHI, INSQTI, REMQHI, REMQTI ([CIS.md](CIS.md)) |
| t34_strx | MOVTC, MOVTUC, MATCHC, CRC |
| t35_dec | The decimal instructions on random operands (generated: `tests/mmu/gen/mk_t35.py`) |
| t36_editpc | EDITPC, classic and random patterns (`tests/mmu/gen/mk_t36.py`) |
| t37_negbase | Bit fields with a base address in S1 space and a position that wraps back into P0; FFS/FFC of size 0; the reserved operand and addressing mode cases of the bit fields; fields at the end of a page |
| t38_tracemovc | Trace with interval timer interrupts in the middle of MOVC3 and MOVC5: each traced once, when it completes |
| t39_strfpd | MOVTUC, MATCHC, CRC stopped by a page fault and by timer interrupts (with trace), resumed with PSL\<FPD\>; MOVTUC in place across an invalid page |
| t40_cmpc | CMPC3 and CMPC5: empty strings, the fill on either side, bytes that compare differently signed and unsigned, a fault part way (generated: `tests/mmu/gen/mk_t40.py`) |
| t41_octa | The two-byte (FD) opcodes and octaword operands: CLRO, MOVO, MOVAO, PUSHAO in every addressing mode; an opcode split across a page boundary; a destination running into an invalid page; AP, FP, SP as octaword registers (reserved addressing mode); undefined FD opcodes ([FPU.md](FPU.md)) |
| t42_fpf, t43_fpd, t44_fpg, t45_fph | The F, D, G and H floating point instructions on random operands, with every floating exception and the integer overflow trap (generated: `tests/mmu/gen/mk_fp.py`) |
| t46_fpexc | Floating faults in detail: frames, registers put back, TP with trace, CVTR's halves, dirty zeros, destinations and a POLY table running into an invalid page |

```
make -C sim cputb                 # the CPU test bench
python3 tests/mmu/run.py          # all tests; -v prints both machines' output
```

`run.py` needs the reference simulator's binary (its header says where it
looks for it).

On the full-system model, after the MMU: EVKAA V8.0 still passes, `hello.bin`
runs, and the `bench.bin` loop takes exactly the same time as before
(30 275 us for 10 000 passes), since it runs with mapping off.

**On the core itself.** `software/mmutest.bin` (built by
`tests/mmu/mkboard.py`) is the same programs as one self-checking program:
each HALT becomes a branch to a routine that saves the registers and the PSL
(`tests/mmu/board.inc`), the reference simulator is run up to that point to
record the expected values with run.py's rules, and a runner (`tests/mmu/runner.s`) resets the
machine to its power-up state before each test, runs it and prints PASS or
FAIL. t22, t23 and t24 end in halts of their own and are left out. On the
full-system model - so through the cache and the SDRAM controller as well,
which the CPU test bench leaves out - all 37 comparable tests pass and t16
halts with code 4, as on the board. README_MiSTer.md says
how to run it there.

## DEC's own test: EVKAE

For the 8600, DEC's test of this part of the machine is **EVKAE, the VAX
Privileged Architecture Exerciser**, which runs under the 8600 Diagnostic
Supervisor (ZZ-EDSAA) from DEC's `VAX_MINIMUM_DIAGS.dsk`.

The core has no disk controller yet, so the supervisor comes over as a
memory image: `tests/evkae/mkdsimage.py` boots it in a VAX 8600 simulator on
the PC, loads EVKAE, and at the `DS>` prompt - where the supervisor runs
with memory management off and polls the console - saves physical memory
and appends the code (`tests/evkae/dsrestore.s`) that puts back the
internal registers the supervisor had set and returns to it with REI. README_MiSTer.md says how
to make it and run it; `tests/evkae/run_sim.sh` runs it on the full-system
simulation.

EVKAE 6.5, test by test, on the core (full-system simulation):

| Test | Name | Core |
|---|---|---|
| 1 | Interrupt Test | passes |
| 2 | Exception Test | passes |
| 3 | REI Instruction Test | fails: REI into compatibility mode |
| 4 | Change Mode Instructions Test | passes |
| 5 | Processor Register Instructions | passes |
| 6 | Interval Timer | passes |
| 7 | MEMORY MANAGEMENT | passes |
| 8 | KERNEL STACK NOT VALID | passes |
| 9 | CHMx TO WRITE PROTECTED STACKS | passes |
| 10 | PROBE Instruction Test | passes |
| 11 | Process Context switching instructions | passes |

Test 3 returns with REI to a PSL with \<CM\> set and expects the PDP-11
instruction there (a BPT) to come back as a compatibility mode exception
(SCB 30, type 1). The 8600 has compatibility mode - "the 8600 includes all
the instructions, architecturally defined processor registers, and
compatibility mode" (SRM, chapter 8); the core does not have it yet, and
does what the SRM asks of a processor without it, a reserved operand fault
on the REI.

Test 8 exercises exactly the case where the frame of kernel stack not valid
matters (see the next section). The core, which follows the SRM, passes it.

The way there was a comparison of instruction traces: the reference
simulator's instruction history against the core's (`ITRACE`, with
`ITRACE_REGS` for the registers), aligned instruction by instruction, with
the supervisor's console polling loop left out and the interrupts that come
at different times on the two machines skipped over. Every difference that
was not just time of day turned out to be one of the fixes listed above.

## Where the core and the reference simulator differ, on purpose

| Case | Core | Reference simulator |
|---|---|---|
| Kernel stack not valid | Pushes the PSL of the original exception, as SRM 5.6 says | Pushes the intermediate kernel-mode PSL |
| VA of a fault on the second page of an operand that crosses a page boundary | The first longword address in that page (9400 for a longword at 93FE) | The operand address plus its length (9402) |
| Interrupts during MOVC3, MOVC5, MOVTUC, CRC | Taken in the middle (PSL\<FPD\> in the frame) | Taken between instructions (in the middle for MATCHC, as on the core) |

All three are within what the architecture allows; the tests check the
page of the VA, and the core's own value for the KSNV frame.

## Not done yet

* PDP-11 compatibility mode (EVKAE test 3).
* The console storage registers STXCS and STXDB.
* PSL\<FPD\> for MOVTC and EDITPC (see [CIS.md](CIS.md)). They,
  CMPC3/CMPC5, LOCC, SKPC, SCANC, SPANC and the decimal instructions
  restart from the beginning after a fault, which is correct, but hold off
  interrupts until they finish.
* The 8600's machine check for TB parity errors, and the performance
  monitor enable bit (P1LR\<31\>) in LDPCTX/SVPCTX.

## Files

| File | What |
|---|---|
| `rtl/mmu.v` | New: TB, walker, protection, fault report, probes |
| `rtl/cpu.v` | Fault entry, register shadow, PSL\<FPD\>, new access signals, IPR snoop for the MMU; halt codes, console halt request, reserved addressing mode check, the 8600's CSWP, MDCTL and EHSR |
| `rtl/alu.v` | One-clock barrel shifter in place of r-vax's bit-serial one |
| `rtl/vcache.v` | Gives up a cycle the MMU refused, before any write |
| `rtl/ucode.def`, `rtl/mkucode.awk`, `rtl/ucode.v`, `rtl/uc-*.hex` | Microcode: exception entry, faults, MTPR/MFPR, PROBE, LDPCTX/SVPCTX, REI, MOVC engine, CHMx, BPT, XFC, CASE, BBx, ACBx; the step store grows from 1024 to 2048 words |
| `rtl/ipr.vh` | New IPR numbers |
| `rtl/mister/vax_core.v` | The MMU between `vcache` and the bus |
| `sim/cpu_tb/`, `tests/mmu/`, `tools/vasm.py` | Test bench, tests, assembler |
| `tests/evkae/` | The Diagnostic Supervisor image (`mkdsimage.py`, `dsrestore.s`) and `run_sim.sh` |
| `sim/tb.cpp` | Full-system bench: `ITRACE`, `ITRACE_REGS`, `EXCTRACE`, `INTTRACE`, `PROFILE` |
