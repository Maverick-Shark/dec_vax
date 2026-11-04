# The I/O side of the MiSTer VAX 8600

This note describes how the core reaches everything that is not the CPU:
the MBox's physical address map, the SBI adapter (SBIA 0) and its registers,
what happens to a reference nothing can answer (the 8600's machine check),
how adapter interrupts reach the EBox, how the SBI's DMA reaches memory,
the RH780 Massbus adapter with its two RP07 disks, whose contents are disk
images on the SD card, and the DW780 Unibus adapter. It is milestone 8 of
[ROADMAP.md](../ROADMAP.md).

The rule is the project's: whatever software can observe behaves like a
**VAX 8600**, as DEC's documents define it. Where the reference simulator
models the 8600 differently (it gives the SBIA the 11/780's register
layout, lets writes to non-existent addresses complete and marks every
machine check "process abort"), the core follows DEC, and the tests say so.

Status: milestones 8.1 to 8.4 are done and checked in simulation (tests
t47 to t59, the whole regression, the board suite and EVKAE):

- 8.1: the PAMM, SBIA 0's registers, CPU transactions to the SBI with their
  timeouts and errors, the machine check frame, the interrupt logic;
- 8.2: byte masks on every physical reference, the MBox's DMA port and its
  arbitration with the CPU, the SBIA's DMA side (receiver, transaction
  buffers and their error registers, quadclear, the memory interlock);
- 8.3: the RH780 at TR 8 and two RP07 drives (units 0 and 1) on its
  Massbus, their disks served by the HPS from image files;
- 8.4: the DW780 at TR 3: its registers, software references to the
  Unibus, the map, the direct and buffered data paths, Unibus interrupts,
  the adapter's initialization and the Unibus power fail sequence. No
  devices on the Unibus yet.

## Sources

| Document | Used for |
|---|---|
| *VAX 8600/8650 SBIA Technical Description*, EK-DB86X-TD-002 (1986), chapter 3 | The SBIA's registers bit by bit (3.14), CPU transactions to SBI nexus and to its own registers, timeouts and error confirmation (3.2-3.5), interrupt summary read and vector generation (3.6), quadclear (3.7), DMA: the receiver, transaction buffer selection, DMA writes and reads, DONE and ERROR from the MBox (3.10-3.12), the DMA command/address and ID registers (3.14.5, 3.14.6) |
| same, appendix A | ABus commands and length/status codes (ERRSUM<31:26>), the console's control of the adapters |
| *VAX 8600/8650 System Fault Isolation Manual*, EK-8600S-MM-004 | M-03 (non-existent memory, and DMA references the PAMM does not give to an array), M-04 (CP I/O buffer error): what the MBox and the error handling microcode do and what the frame shows; appendix K, every longword of the machine check frame and EHSR, MSTAT2 (ABus bad data); appendix A, the EHM flow (double errors) |
| *DEC STD 032*, EL-00032-00 (1990), appendix B | The 8600's physical address space (figure B-20), SCB (table B-23), machine check frame layout (table B-26), halt codes (table B-24), IPRs (table B-25) |
| *VAX Architecture Reference Manual*, EY-3459E-DP (1987), table 5.4 | SCB 00: passive release, at the IPL of the request |
| *RH780 Technical Description*, EK-RH780-TD-001 (1979) | 2.8.6: the SBI interrupt protocol as a nexus sees it (requests are levels, cleared by software); chapter 2: the Massbus signals; chapter 3: the MBA's registers bit by bit, interrupt conditions, how transfers end, drive register addresses; chapter 4: address and function validation, MBA BUSY and the confirmations, the data paths (silo, byte masks, VAR, byte counters), the control path (DEM, TRA, NED), the end of a transfer |
| *VAX Maintenance Handbook, VAX-11/780*, EK-VAXV2-HB-002 (1983) | MBA and UBA register summaries; the backpanel jumpers: TR 8 and BR5 for the first RH780, TR 3 and BR4 for the first DW780 |
| *DW780 Unibus Adapter Technical Description*, EK-DW780-TD-001 (1978) | Chapter 2: the Unibus and its cycles (2.3), the adapter's address space and references to the Unibus (2.5, table 2-7), the map and the data paths (2.6, table 2-9), interrupts (2.7), initialization and the power fail sequences (2.8), the registers bit by bit (2.9); chapter 3: the microsequencer's DMA routines (3.3), the function decoder and the in-progress flags (3.4.7, tables 3-11 to 3-13, figure 3-35), the timeouts (3.5); appendix A, longword access mode |
| *VAX Hardware Handbook*, Volume 1 (1986) | The 8600's Unibus subsystem: the DW780 on SBIA 0 |
| *RP04/RP05/RP06 Device Control Logic Maintenance Manual*, EK-RP056-MM-01 (1975) | The Massbus drive registers bit by bit (2.4.1.3), the commands and what DRY, PIP and ATA do for each (2.3, table 2-1), the sector format and the header words (2.4.4, 3.6, 3.9), seeks, implied and mid-transfer seeks (3.4), error classes (3.12) |
| *RP07 Service Manual*, ER-ORP07-SV (1980), *RP07 User Guide*, ER-ORP07-UG (1980) and *RP07 Pathfinder*, ER-ORP07-TM (1981) | The RP07: 630 cylinders, 32 tracks, 50 sectors of 512 bytes, 3633 rpm, seek times (table 1-2); serial number, interleave and dual port options (2.5.2); its drive registers as the microdiagnostics test them |
| DEC's TOPS-20 RP07 support (`rp07.mac`) | What the RP07 changes in the Massbus registers: drive type 042, DA's sector field <6:0> and track field <13:8>, the look-ahead sector count <12:6>, no offset magnitude in OF |

## Where it sits

```
cpu ── vcache ── mmu ── vax_io (MBox) ──┬── PAMM 00-07: vax_cache ── vax_sdram ── SDRAM
     (aligner)                          │       ^
                                        │       │ DMA (PAMM 00-07 only; CPU and DMA take turns)
                                        │       │
                                        ├── PAMM 18: vax_sbi (SBIA 0) ── SBI ──┬── TR 3 vax_uba (DW780) ── Unibus (no devices yet)
                                        │                                      └── TR 8 vax_mba (RH780)
                                        │                                           └── Massbus ── vax_rp07 units 0, 1
                                        │                                                          (images: hps_io)
                                        └── anything else: non-existent memory (machine check)
```

`rtl/mister/vax_io.v` is the MBox's view of the physical address space;
`rtl/mister/vax_sbi.v` is SBIA 0. The CPU test bench (`sim/cpu_tb`) uses
the same two modules in front of its memory array, so the directed tests
see the same machine as the full system.

## Byte masks

Every physical reference carries a byte mask, from the aligner (`vcache`,
which turns an operand that crosses a longword into two references, each
with its own mask) through the MMU to the MBox: a write writes only the
bytes of its mask, in the cache line and in the SDRAM (its DQM lines), so
the MBox never has to read a longword to merge a byte into it. A write that
crosses a page is probed first, both halves, with reads, so that a
translation fault or a machine check on the second page leaves memory
untouched; one that stays in its page is written low half first. The CPU
gets its acknowledge after the last cycle.

On the ABus the mask becomes what the SBIA puts on the SBI: a write carries
its byte mask (SBI write masked), a read asks for the even word (mask
0011), the odd word (1100) or the longword (1111); ERRSUM<27:26> records
that length (01, 10, 11) of every CPU transaction.

## The physical address memory map

Every physical reference goes through the PAMM (Fault Isolation Manual,
M-03): a five-bit code for each megabyte of the 1 GB physical address
space, addressed by PA<29:20>.

| Code | Meaning |
|---|---|
| 00-07 | memory array in slot 0-7; the array gets PA<21:0> (4 MB arrays) |
| 18-1B | ABus adapter 0-3 (18 is SBIA 0) |
| 1F | non-existent memory |
| others | reserved; treated as non-existent |

Software reads and writes it with the IPRs PAMLOC (40 hex is PAMACC, 41
PAMLOC): MTPR PAMLOC selects the megabyte (<29:20>), MTPR PAMACC writes its
code (<4:0>), MFPR PAMACC reads `{PAMLOC<29:20>, code}`. The console loads
it when it sizes the system; processor initialization does the same here:

| Physical addresses | Code |
|---|---|
| 0000 0000 - 01FF FFFF | 00-07: 32 MB as eight 4 MB arrays |
| 2000 0000 - 21FF FFFF | 18: SBIA 0 |
| everything else | 1F |

The PAMM is a real RAM (two copies of 1024 x 5 bits in M10K, one read for
every reference, one at PAMLOC for MFPR), so software can remap memory or
take a megabyte away, as the 8600's memory diagnostics do. Its lookup runs
in the same clock as the cache's tag lookup, so it costs no time. With the
console's map the array address is the physical address itself.

## SBIA 0

The adapter answers the ABus longword addresses PA<29:2> its PAMM code sends
it. 802 0000 - 802 FFFF (2008 0000 - 200B FFFF) is its own range: its
registers at 2008 0000 - 2008 004C, its vector registers at 2008 0090 -
2008 00B8; any other address in that range is an address error. Every other
address is a CPU transaction on the SBI (nexus registers at 2000 0000 +
2000 * TR, Unibus 0 at 2010 0000, SBI memory space below 2000 0000).

### Registers (EK-DB86X-TD-002, 3.14)

| Address | Register | What the core implements |
|---|---|---|
| 2008 0000 | CNF | <29:20> memory separator (megabytes reachable by DMA, read/write; the console sets 32), <7:4> adapter type 0001, <3:0> revision 0 |
| 2008 0004 | CSR | <31> master interrupt enable, <30> SBI cycles out (CPU access to the SBI), <29> SBI cycles in (DMA); <27:24> CPU TR select reads 0 |
| 2008 0008 | ERRSUM | <31:26> command and length of the last CPU transaction (read 0001, write mask 1101; even word 01, odd word 10, longword 11), <23> CPU buffer error lock, <20> address error, <19> error on command/address, <16> multiple CPU error; writing 1 to <23> clears <23,22:19,16>. <14:0>, the DMA transaction buffers' errors (C <14:12>, B <10:8>, A <6:4>, I <3:0>; the low bit of each group is "MBox detected error", I<3> the interlock timeout), written 1 to clear |
| 2008 000C | DCR | <19:16> force DMA buffer C, B, A, I busy (the receiver skips those buffers, and answers busy when none is left); <4> disable the SBI timeout, <0> short timeout (8 SBI cycles, reads as 0); <3> force quad data, <2> loopback, <1> force state parity error kept and read back, without effect; <8> clear silo address, <7>, <6> read as 0 |
| 2008 0010 - 002C | DMA I/A/B/C command/address and ID | the command/address (<31:28> function, <27:0> SBI longword address) and the master's ID of the last command each buffer took; frozen while that buffer has an error in ERRSUM |
| 2008 0030 | SILO | reads 0 (no SBI cycles are recorded) |
| 2008 0034 | SBIER | <12> CP timeout, <11:10> its status (00 no response, 01 busy), <08> CPU SBI error confirmation; writing 1 to <12> clears all three. The 11/780 bits (CRD, RDS, IB...) do not exist on the 8600 |
| 2008 0038 | TOADR | <27:0> SBI longword address of the last CPU transaction |
| 2008 003C | FS | <18> fault interrupt enable; <19> fault latch (write 1 to clear) never sets: nothing makes SBI faults |
| 2008 0040 | SC | <31> lock, <30> lock interrupt enable, <29> lock unconditional, <28:16> mode, command, tag, count; <15:0> maintenance TR, write only. The unconditional lock counts SBI cycles and locks at count F; the conditional modes never match |
| 2008 0044 | MAINT | <31:23>, <11>, <8>, <4:0> kept and read back; <04> (force SBI interrupt request) and <01> (force ISR data) work, see Interrupts |
| 2008 0048 | UNJAM | a write starts the unjam sequence (nothing to unjam here); reads 0 |
| 2008 004C | QCLR | quadclear: the longword written (function 1011 and a quadword address) goes on the SBI with two longwords of zeros; reads 0 |
| 2008 0090 - 009C | vectors, IPL 14-17 | interrupt summary read |
| 2008 00A4, 00AC, 00B0, 00B8 | vectors, IPL 19, 1B, 1C, 1E | 50, 58, 5C or 60, 64 |

ERRSUM<31:26> and TOADR follow every CPU transaction, the one that reads
them included, until ERRSUM<23> locks them: reading ERRSUM with no error
gives 1C00 0000 (a longword read) and reading TOADR gives 0802 000E (its
own address). The SBI cycle is 200 ns (ten clocks at 50 MHz).

### CPU transactions and their errors

A transaction ends with ABUS CPU BUF DONE or, when it cannot complete,
ABUS CPU BUF ERR, which the MBox turns into a machine check (CP I/O buffer
error). The errors:

| Error | Cause | Recorded |
|---|---|---|
| address error | a register that does not exist, a write to a vector register, an SBI reference (or a BR4-BR7 vector read, which is an SBI cycle) with CSR<30> clear | ERRSUM<23,20,19>; with <23> already set, <16> |
| SBI timeout | no acknowledge within 512 SBI cycles, 102.4 us (8 with DCR<0>; never with DCR<4>) | SBIER<12>, <11:10>; ERRSUM<23> |
| error confirmation | the nexus answered ERR | SBIER<08>; ERRSUM<23> |

ERRSUM<23> also locks ERRSUM<31:26>, SBIER<12:10,08> and TOADR, so they
describe the first error until software clears them. Reads and writes fail
alike: on the 8600 a write to a nexus that is not there is a machine check,
not an interrupt.

A read whose data comes back marked bad (below: a CPU reference to SBI
memory space that the MBox aborts) completes on the SBI but reaches the
MBox as ABus bad data: a machine check with MSTAT2<14>.

## DMA

### The receiver (EK-DB86X-TD-002 3.10-3.12)

SBIA 0's DMA side answers a command on the SBI when:

- CSR<29> (SBI cycles in) is set,
- the address is in SBI memory space (SBI address bit 27 clear),
- it is below the memory separator, CNF<29:20> megabytes;

otherwise nothing answers it (the master sees no response, and times out).
The command goes into a transaction buffer: I for the interlocked commands,
A, B and C in turn for the others, skipping those DCR<19:16> forces busy;
with none free the adapter answers busy. The buffer's command/address and
ID registers record the command, unless an error in ERRSUM has frozen them.

The adapter hands the MBox one longword at a time on the MBox's DMA port:
read masked and write masked are one longword, extended read and extended
write masked a quadword (the second longword with its own mask). Interlock
read masked takes the memory interlock, which interlock write masked
releases; another interlock read meanwhile is answered busy, and an
interlock read with no write within 512 SBI cycles sets ERRSUM<03>
(interlock timeout) and lets the interlock go.

### The MBox's DMA port

The MBox looks every DMA reference up in the PAMM (its third copy) and
sends it to memory only when the code is a memory array (Fault Isolation
Manual M-03, "DMA requests which result in a PAMM code of 1X"); any other
code aborts it. The adapter then sets the buffer's "MBox detected error" in
ERRSUM (I <00>, A <04>, B <08>, C <12>), which freezes that buffer's
registers and requests the adapter error interrupt (IPL 1C, SCB 60); read
data goes back to the master marked bad, a write is over as far as the
master is concerned.

DMA goes through the cache like the CPU's references, so both always see
the same memory (the cache writes through). The memory port changes hands
only between references; when the CPU and DMA both want it they take
turns, so neither waits for more than one reference of the other.

### Quadclear and SBI memory space

A CPU write to QCLR (2008 004C) puts the longword written on the SBI as a
command/address (it must be 1011, extended write masked, and a quadword
address) followed by two longwords of zeros. The adapter's own receiver
takes it like any other DMA, so the quadword in memory is cleared; beyond
the memory separator, with CSR<29> clear or every buffer forced busy,
nobody takes it and the CPU's transaction times out (machine check).

A CPU reference to SBI memory space (a megabyte the PAMM gives to SBIA 0
below 2000 0000) goes the same way: the receiver takes it and hands it to
the MBox, which aborts it, since that megabyte is not memory. The buffer
records the MBox detected error and the adapter error interrupt follows; a
read comes back marked bad (a machine check, ABus bad data), a write
completes.

## The RH780 Massbus adapter (TR 8)

`rtl/mister/vax_mba.v` is the RH780 at TR 8, its interrupts on BR5 (the
first RH780's jumpers, EK-VAXV2-HB-002): IPL 15, SCB 100 + 40 + 4 * 8 = 160.
Its 8 KB of nexus space starts at 2001 0000.

### Address space and references (TD 4.2.6-4.2.8)

| Byte offset | SBI address <9:8> | What |
|---|---|---|
| 000-01C | 00 | the eight internal registers (<7:3> must be 0) |
| 400-7FC | 01 | drive registers: 400 + 80 * drive + 4 * register |
| 800-BFC | 10 | the 256 map registers |
| C00-FFC | 11 | nothing: no response |
| 1000-1FFC | (<10> set) | nothing: no response |

The adapter takes only longwords (mask 1111) with the read masked or write
masked function, interlocked or not; a word or byte reference gets an error
confirmation (on the 8600: SBIER<08>, a machine check), and an address it
does not decode no response (an SBI timeout, a machine check). While a drive
register access is on the Massbus (MBA BUSY, about 0.8 us) every other
command gets busy confirmations until it is over: writes are acknowledged at
once, reads when the drive's data is there.

### Registers (TD 3.6)

| Offset | Register | What the core implements |
|---|---|---|
| 00 | CSR | <23> adapter power down, <22> power up (write 1 to clear; never set: processor initialization is not a power-up), <7:0> adapter code 20; the SBI fault bits <31:26> never set |
| 04 | CR | <3> maintenance mode (not while a transfer runs: program error), <2> interrupt enable, <1> abort data transfer, <0> INIT (reads 0: clears CSR status, CR<2:1>, SR, BCR and DR, aborts a transfer, Massbus INIT to every drive) |
| 08 | SR | <31> DT busy, <30> no response confirmation, <19> program error, <18> non-existent drive, <16> attention (set by the Massbus ATTN line), <13> DT complete, <12> DT aborted, <11> data late, <10>/<09> write check upper/lower byte, <08> missed transfer, <07> Massbus exception, <04> invalid map, <02> read data substitute, <01> interface sequence timeout; written 1 to clear (<31> read only). CRD, MCPE, map and data parity, error confirmation and read data timeout never happen here |
| 0C | VAR | <16:9> map pointer, <8:0> byte offset |
| 10 | BCR | <31:16> Massbus byte counter (read only), <15:0> SBI byte counter; a write loads the 2's complement of the byte count into both |
| 14 | DR | <31:21> written in maintenance mode only (<28> blocks commands to the SBI); <20:8> the Massbus FAIL, RUN, WCLK, EXC, CTOD lines, DS and RS of the last control operation; <7:0> a byte of the Massbus data input buffer (<23> selects the upper one) |
| 18 | SMR | the map register VAR<16:9> selects |
| 1C | CAR | the command/address of the next DMA command (function 1000 extended read or 1011 extended write masked, the SBI address) |
| 800-BFC | MAP | <31> valid, <20:0> page frame number |

VAR, BCR and the map registers cannot be written while a transfer runs (the
write is ignored, program error). A drive register read returns the drive's
16 bits with SR<31:16> above them; a write writes the low 16 bits. A drive
that does not answer (TRA) within 1.5 us sets NED, and a read gets 0; the
attention summary register is answered by every drive at once and never sets
NED.

### Data transfers

Writing a data transfer function with GO to a drive's control register (CS1
<5:3> 101 write check, 110 write, 111 read; TD table 4-3) sets DT BUSY and
sends the command to the drive, unless a transfer is already running
(program error, the command is not sent). The data goes through a 32-byte
silo between the Massbus (16-bit words, the low byte first in memory) and
the SBI, where the adapter is a master: extended read (a quadword, mask
1111) for writes and write checks, extended write masked for reads, the
bytes a quadword gets in its two masks, so a transfer may start and end on
any byte. VAR<16:9> picks the map register of each page; a map register
not valid when its page is reached is INVMAP. VAR<2:0> follows the bytes
and VAR<16:3> advances after every memory reference: a transfer that does
not end on a quadword boundary leaves VAR eight bytes past its last byte
(TD 3.6.4, note).

The SBI byte counter counts the bytes to or from memory, the Massbus byte
counter two for every word on the Massbus; when that one goes through 0 the
adapter negates RUN, the drive finishes its sector (a write completed with
zeros, a read's extra words dropped) and ends with EBL. The normal end (TD
4.5.4): RUN negated, EBL, the SBI byte counter at 0 and, for a read, the last
memory write done: DT COMP, DT BUSY cleared. A write check compares each
word the drive reads with memory: a difference in the low byte is WCK LWR,
in the high byte WCK UP.

An error that aborts (data late, write check, Massbus exception, invalid
map, read data substitute, interface sequence timeout) or CR<1> negates RUN
and sends EXC to the drive, which stops at once; the transfer ends at its
EBL with DT ABORTED and DT COMP. No OCC or SCLK from the drive within 50 us
of DT BUSY (the drive was not there, or rejected the command) is a missed
transfer: MXF, DT ABORTED, DT COMP. An SBI memory reference nothing takes
(beyond the memory separator) is retried, NRCONF, until the interface
sequence timeout (512 SBI cycles); one the MBox aborts (a page that is not
memory) comes back as read data substitute.

### Interrupts (TD 3.4)

With CR<2> set the adapter requests BR5 for DT COMP, DT ABORTED, attention,
program error, NED, missed transfer (or adapter power up/down), but never
while a transfer runs: attention from another drive's seek waits for the end
of the transfer. The request is a level, until software clears the SR bits.

### Processor initialization

The adapter as INIT leaves it: IE clear, SR and BCR 0, no power-up interrupt
pending; VAR 0; the map registers keep what was written (0 after power-up).
The drives are initialized too (errors and ATA cleared, the heads at
cylinder 0, VV clear), but a mounted image stays mounted.

## The RP07 drives

`rtl/mister/vax_rp07.v`, units 0 and 1 on the Massbus (units 2-7 are not
there: NED). An RP07 is 630 cylinders of 32 tracks of 50 sectors of 512
bytes (16-bit format), 1 008 000 sectors, 516 096 000 bytes. Each drive's
disk is an image on the SD card, mounted in the OSD (*RP07 Unit 0*, *RP07
Unit 1*): the sectors in order, LBA = (cylinder * 32 + track) * 50 + sector,
512 bytes each, the low byte of each word first (the reference simulator's
RP07 images are the same). An image shorter than a full RP07 reads as zeros
beyond its end, and those sectors are not written; a read-only image is
write-locked (DS<WRL>, WLE on a write).

### Registers (EK-RP056-MM-01 2.4.1.3, with the RP07's fields)

| Reg (octal) | Register | Bits |
|---|---|---|
| 00 | CS1 | <11> DVA (a single port drive: always), <5:1> function, <0> GO (set while a command runs) |
| 01 | DS | <15> ATA, <14> ERR, <13> PIP, <12> MOL (an image is mounted), <11> WRL, <10> LST, <9> PGM 0, <8> DPR 1, <7> DRY, <6> VV, <2> ILV 0, <1> EW 0, <0> OM |
| 02 | ER1 | DCK UNS OPI DTE WLE IAE AOE HCRC HCE ECH WCF FER PAR RMR ILR ILF (<15>-<0>); UNS, WLE, IAE, AOE, FER, RMR, ILR, ILF can happen |
| 03 | MR | maintenance, read/write; <15> diagnostic mode, cleared by drive clear |
| 04 | AS | attention summary: every drive answers with its ATA on the bit of its unit; writing 1 there clears it |
| 05 | DA | <13:8> track, <6:0> sector |
| 06 | DT | 020042: moving head, drive type 042 |
| 07 | LA | <12:6> the sector under the heads |
| 10 | SN | serial number, BCD: 1001 for unit 0, 1002 for unit 1 |
| 11 | OF | <15> command modifier, <14> move track descriptor, <12> FMT (16-bit format), <11> ECI, <10> HCI |
| 12 | DC | <9:0> desired cylinder |
| 13 | CC | <9:0> current cylinder |
| 14, 15 | ER2, ER3 | drive errors: read/write, never set by the drive |
| 16, 17 | EC1, EC2 | ECC position and pattern: 0 |
| 20-37 | | no such register: ILR |

Read-only registers ignore writes without an error. While a command runs
only MR and AS can be written: anything else is RMR (and ignored). A drive
with ERR set ignores every command but drive clear (RH780 TD 3.3), so a data
transfer to it becomes a missed transfer in the adapter. Writing CS1 without
an error clears ATA. An error sets ATA at once, or at the end of a data
transfer; positioning commands set it when they are over; so does the drive
coming on or off line (an image mounted or removed).

### Commands

| Code (octal, with GO) | Command | What it does here |
|---|---|---|
| 01 | no-op | nothing |
| 03 | unload | off line (MOL, VV clear), PIP and GO until an image is mounted again, which ends it with ATA |
| 05 | seek | to DC; PIP, ATA when there (at once if the heads are there); IAE for an address out of range |
| 07 | recalibrate | to cylinder 0, PIP, ATA |
| 11, 13 | drive clear, release | ER1-ER3, ATA, MR<15> cleared |
| 15, 17 | offset, return to centerline | OM set or cleared, 5 ms, PIP, ATA |
| 21 | read-in preset | VV; DA, DC 0; OF<12:10> cleared |
| 23 | pack acknowledge | VV |
| 31 | search | seek if needed, then ATA when the DA sector comes under the heads |
| 51, 53 | write check data, header and data | the drive reads, the adapter compares |
| 61, 63 | write data, header and data | |
| 71, 73 | read data, header and data | |

Anything else is ILF. Positioning or transferring with no image is UNS.

A data transfer seeks first if DC is not CC (an implied seek: no PIP), waits
for its sector, then transfers sector after sector while the adapter keeps
RUN asserted, sampling RUN at each sector's end (EBL); the address advances
through the tracks and cylinders (a mid-transfer seek at the end of a
cylinder), and DA and DC are left at the sector after the last one. Past the
disk's last sector with RUN still asserted the transfer stops with AOE (EXC,
ATA at the end); LST says the last sector was done (until INIT). A header
command moves four header words before each sector's 256 data words: the
cylinder with the format bit <12>, the sector/track word and two key words
(0); written headers are not kept, the image holding only the data. With
OF<12> (FMT) and HCI clear, read data, write data and write check data stop
at once with FER, since no header written in 16-bit format verifies; the
header commands flag FER and go on. EXC from the adapter ends a transfer at
once, and a sector it was writing is not written.

### Timing

From the RP07's specifications (table 1-2): 3633 rpm, 330 us a sector, the
data at 2.16 MB/s within a sector (a word every 0.93 us), so 1.55 MB/s over
consecutive sectors; seeks 5 ms for one cylinder, 23 ms on average, 46 ms
full stroke (5 ms + 41 ms * (distance / 629)^0.75, in bands of 16
cylinders); offset and return to centerline 5 ms. The first sector of a
transfer, or of a search, waits for the platter to bring it. The drive is
ready as soon as an image is mounted (a real RP07 takes 82 s to spin up).
Each drive keeps two sectors of buffer: the next sector of a read is
fetched from the SD card while the current one goes out, and a written
sector goes back to the card while the next one comes in; when the card is
slower than the platter, a sector waits for its data. The simulation benches
divide the mechanical times (TSCALE 16), not the data rate.

## The DW780 Unibus adapter (TR 3)

`rtl/mister/vax_uba.v` is the 8600's first DW780: TR 3, Unibus 0, its own
interrupts on BR4 (the first DW780's backpanel jumpers, EK-VAXV2-HB-002):
IPL 14, SCB 100 + 4 * 3 = 10C. Its registers are at 2000 6000, the
Unibus's 256 KB at 2010 0000 - 2013 FFFF. There are no Unibus devices in
the core yet; the CPU bench puts a test device on the Unibus
(`sim/cpu_tb/ubdev.v`) to exercise the adapter's device side.

### Address space (TD 2.5)

| SBI byte address | What |
|---|---|
| 2000 6000 - 2000 607C | the registers below |
| 2000 6800 - 2000 6FBC | the 496 map registers |
| 2000 6080 - 2000 67FC, 2000 6FC0 - 2000 7FFC | nothing: no response |
| 2010 0000 - 2013 FFFF | Unibus 0: UA<17:0> is the byte address's <17:0> (the SBI carries UA<17:2>, the mask UA<1:0>) |

The address and function decoder (TD 3.4.7.2) does not look at the mask:
a register read of any length returns the longword, a write writes it. A
write to FMER, FUBAR or a BRRVR gets an error confirmation, and so does an
extended function, which the adapter does not take (TD table 3-11).

### Registers (TD 2.9)

| Offset | Register | What the core implements |
|---|---|---|
| 000 | CNFGR | <18> Unibus INIT asserted, <17> Unibus power down, <16> Unibus initialization complete (write 1 to clear), <7:0> adapter code 28; the SBI fault bits <31:26> and adapter power down/up <23:22> are never set |
| 004 | CR | <30:26> map register disable (UA<17:13> below it is not the adapter's), <6> interrupt field switch (IFS), <5> BR interrupt enable (BRIE), <4> Unibus to SBI error interrupt enable, <3> SBI to Unibus error interrupt enable, <2> configuration interrupt enable, <1> Unibus power fail, <0> adapter init (reads 0) |
| 008 | SR | <10> RDTO, <9> RDS, <8> CRD, <7> CXTER, <6> CXTMO, <5> DPPE, <4> IVMR, <3> MRPF (the DMA error field), <2> lost error bit, <1> Unibus select timeout, <0> Unibus slave sync timeout (the SBI to Unibus field); write 1 to clear. <27:24>, BRRVR full, read 0: every BRRVR's read data gets its ACK |
| 00C | DCR | <31> spare, <30> disable interrupts (DINTR), <29> defeat map parity, <28> defeat data path parity, <27> microsequencer OK (read only), <23:0> CNFGR<23:0> (read only) |
| 010, 018 | FMER | <8:0> the map register of the failing DMA or purge (valid while the DMA field is locked) |
| 014, 01C | FUBAR | <15:0> UA<17:2> of the failing software transfer (valid while the SBI to Unibus field is locked) |
| 020-02C | BRSVR 0-3 | <15:0>, no effect |
| 030-03C | BRRVR 4-7 | <31> the adapter's own request on that level, <15:0> the vector of the device interrupting on it |
| 040-07C | DPR 0-15 | <31> buffer not empty (write 1: purge), <30> buffer transfer error (write 1 to clear), <29> data path function (1: DMA write), <23:16> buffer state, <15:0> buffered Unibus address (UA<17:2> of the last DMA write, plus the byte offset); DPR 0 reads 0 |
| 800-FBC | MR 0-495 | <31> valid, <30:27> read/write, <26> longword access enable (appendix A), <25> byte offset, <24:21> data path (0 direct, 1-15 buffered), <20:0> SBI page (<20> is SBI address <27>, I/O space) |

The first error in a field of SR locks it, with FMER or FUBAR, until
software clears it; a DMA error meanwhile sets the lost error bit.

### Software references to the Unibus (TD 2.5.2, table 2-7)

A read of a byte or a word is DATI of the word (masks 0001, 0010 and 0011
the even word, 0100, 1000 and 1100 the odd one); a byte write is DATOB, a
word write DATO; any other mask (a longword, a word across the longword's
middle) gets an error confirmation. The SBIA sends no interlock functions,
so the adapter's DATIP-DATO sequence is not reached from the CPU. The
adapter becomes Unibus master, its own highest NPR device, and runs the
cycle: address, control and data, the deskew, MSYN, the slave's SSYN with
the read data. Not master within 51.2 us is a Unibus select timeout, no
SSYN within 12.8 us a slave sync timeout (TD 2.9.3): FUBAR keeps the
address and a read returns zeros. A write is acknowledged on the SBI at
once and done on the Unibus afterwards.

The confirmations follow the in-progress flags (TD figure 3-35, table
3-13): a Unibus read is acknowledged unless a Unibus transfer (UIP) or a
read (RIP) is in progress or an interlock read waits for its write (RIFF),
a Unibus write unless UIP or RIFF; a register read unless the
microsequencer (AIP) or a read is busy; a write to a map register, BRSVR or
DPR unless AIP; writes to CNFGR, CR, SR and DCR always. Anything else gets
a busy confirmation, which the SBIA repeats. During the 500 us of the
adapter's initialization routine only CNFGR and DCR can be read and CNFGR,
CR, SR and DCR written.

A reference below the I/O page (760000) goes out on the Unibus like any
other and, when its map register is valid, comes back through the
adapter's own DMA side to memory (wraparound, TD 1.9.2): the CPU can reach
memory through the map, which is how t56 and t57 exercise the data paths.

### DMA (TD 2.6, 3.3)

A Unibus master's cycle below the I/O page, with UA<17:13> not below
CR<30:26>, is the adapter's: UA<17:9> selects the map register; one not
valid is IVMR, and no slave sync (the master times out). The direct data
path makes each DATI, DATIP, DATO and DATOB one SBI read masked, interlock
read masked, write masked or interlock write masked of its word or byte
(TD table 2-9). The buffered data paths 1-15 are a quadword buffer each:

- writes collect in the buffer; writing its last byte sends the quadword
  (extended write masked, the masks from the buffer state); a purge
  (DPR<31> written 1) sends what is left, by a write masked when only
  bytes 0-3 have data;
- reads: an empty buffer reads the quadword (extended read) or, from byte 4
  on, the longword (read masked); the next words come from the buffer,
  even after memory changes; reading its last word prefetches the next
  quadword; a purge empties it;
- with byte offset (MR<25>) the SBI address is the Unibus address plus one:
  the byte that spills over the quadword goes to the next one, and BUBA is
  one longword on; the direct data path and SBI I/O space ignore the bit;
- in longword access mode (MR<26>, appendix A) reads are longwords from
  memory and a write goes out when the longword's high word or byte 3 is
  written; no prefetch;
- a buffered data path takes no DATIP: no slave sync (TD 3.3.1).

Errors: read data marked bad (RDS); an invalid map register (IVMR); with
the parity defeat bits, a map register byte (MRPF) or a buffer's data byte
(DPPE) with an even number of ones; an SBI transfer nobody confirms (an
address beyond the memory separator), which the adapter repeats - through
the direct data path until the Unibus master gives up waiting for its slave
sync (nothing recorded), for a buffer until its master gives up or for
100 us, which is CXTMO. Each locks the DMA error field and FMER; with
USEFIE it is an adapter interrupt. A buffer write or a purge that fails
also sets the DPR's BTE, and that buffer takes nothing until software
clears it. A prefetch that fails leaves the buffer empty and records
nothing. The DMA goes through the SBIA's receiver like the RH780's: memory
only.

### Interrupts (TD 2.7, 2.9.8)

The adapter's own requests are on BR4: status errors with CR<4> or <3>,
the configuration register's power and initialization bits with CR<2>, a
level until software clears them. With IFS and BRIE set (and DINTR clear)
the Unibus's BR4-BR7 go to the SBI as REQ4-REQ7: the interrupt summary
read finds TR 3, and the vector is 100 + 40 * (IPL - 14) + 4 * 3 (10C,
14C, 18C, 1CC). The service routine reads the level's BRRVR: the adapter
gives the bus grant, the device answers with its vector (INTR), and that
is the read data, negative when the adapter's own request is pending on
the same level. A BRRVR read with IFS set but BRIE clear does the same
(polling); with IFS clear, DINTR set, or no request on that BR (a passive
release) it reads 0, bit 31 apart.

### Initialization (TD 2.8, 2.9.1, 2.9.2)

Adapter init (CR<0>) clears the map, data path, status, control, BRSVR
and DCR registers, runs the microsequencer's initialization routine for
500 us (DCR<27> clear meanwhile) and a power fail sequence on the Unibus:
AC LO at once (CNFGR<17>, <16> cleared), DC LO and INIT 5 ms later
(<18>), during which no master can get the Unibus; then the power up: DC
LO and INIT released after 10 ms, AC LO after 20 ms, which sets <16> and
clears <18:17>, about 25 ms from the start. CR<1> runs the same power
fail, the Unibus staying down while it is set. SBI UNJAM clears CR<5:2>
and starts the sequence too.
Processor initialization leaves the adapter as an adapter init long
finished: CNFGR 0001 0028, every other register clear, no interrupt
pending.

### The Unibus inside the core

The Unibus is a set of signals between the adapter and its devices, not
the bus's wired-OR lines: `ub_*` is the bus as device registers see it,
driven by the master of the moment (the adapter, or a device doing DMA);
`dv_*` is the port of a device that is master after an NPR, granted while
the bus is free, held for as long as the device keeps its request; `ub_br`,
`ub_bg`, `ub_intr` and `ub_vec` are the interrupt lines; `ub_init` is INIT.
Each cycle is the four phase handshake: MSYN with address, control and
data, SSYN (with the read data) until MSYN goes away. PB reaches only the
adapter's own master cycles (a wraparound read through a buffer with a
data path parity error), which return it to the SBI as read data
substitute. The microsequencer steps at 5 MHz, its timeouts counted in
those 200 ns ticks.

## Machine checks

Two kinds of reference end in a machine check (SCB 04), reads and writes,
instruction stream or data:

- a PAMM code that is not an array or adapter 0 (Fault Isolation Manual
  M-03): MBox fatal error, MSTAT2<03> non-existent memory, the code in
  MSTAT2<20:16>;
- a CP I/O buffer error from SBIA 0 (M-04): MSTAT2<02>;
- read data SBIA 0 returns marked bad: MSTAT2<14>, ABus bad data.

The error handling microcode rolls the instruction back: the frame's PC is
the instruction's, and registers an autoincrement or autodecrement changed
are restored (the processor already does that for translation faults).

### The frame (DEC STD 032 table B-26, EK-8600S-MM-004 appendix K)

The microcode pushes a byte count (58) and 22 longwords, which the
processor keeps for it behind an internal register (`IPR_MCFRAME`, 7A, not
reachable with MFPR); then PC and PSL.

| Longword | Contents |
|---|---|
| EHM.STS | 4000 0800: EHM entered, micro-trap vector 8 (MBox fatal error); <31>, <28>, <27:19>, <18>, <17> copied from EHSR as the microcode found it. Process abort (<17>) is not set: it is for parity errors the instruction cannot be retried after |
| EVMQSAV | the virtual address of the operand (0 for an instruction fetch) |
| EBCS | 0020 C000: stack frame revision 1, MBox fatal error, MBox interrupt pending; <20> PME; <02> a write was in progress; <01> an I/O register read failed |
| EDPSR, IBESR, EBXWD1, EBXWD2 | 0: no E-box or I-box error |
| CSLINT | 081D 0000 plus the interrupt requests pending: <29> console halt, <27> MBox error, <26> interval timer, <24> console transmit done, <23> console receive; <20>, <19:16> the highest is internal, IPL 1D |
| IVASAV | the operand's virtual address (0 for a fetch) |
| VIBASAV | the last longword of the instruction stream fetched (the failing one for a fetch) |
| ESASAV, ISASAV, CPC | the instruction's PC |
| MSTAT1 | <31:30> destination: 10 E-box, 11 I-buffer (fetch); <29:26> cycle: E CP read, D CP write |
| MSTAT2 | 001F 0008 (non-existent, code 1F), 0018 0004 (CP I/O buffer error) or 0018 4000 (ABus bad data) |
| MDECC | 0 |
| MERG | MERG<12:9,5:0> as software wrote them, <8> MAPEN |
| CSHCTL | 3: both caches on |
| MEAR | the physical address of the longword (for an I/O error the manual calls it not valid; it is the address all the same) |
| MEDR, FBXERR, CSES | 0 |

### EHSR and double errors

EHSR (IPR 4A) is an E-box scratch pad longword: MTPR writes all of it,
MFPR reads it back. Taking a machine check sets <23:16> to the micro-trap
vector, 8, and <05>, VMS entered; VMS's handler clears <05> before its REI.
A machine check while <05> is still set does not reach VMS: the processor
halts with code 5, "non-E-box double error", the instruction rolled back.
So does one while an exception or interrupt is being initiated.

A reference that gets no answer at all (nothing on the bus responds for
2^16 clocks; an SBI timeout takes about 5 000) halts with code 2, r-vax's
own: the 8600 would find the machine hung.

## Interrupts

SBIA 0 presents the EBox with the highest level it has a request at (ABUS
IPR RETURN), when CSR<31> is set:

| IPL | Request | Vector |
|---|---|---|
| 1E | SBI fail | 64 |
| 1C | SBI fault (FS<19> and <18>) or adapter error (an error of a DMA transaction buffer in ERRSUM<14:0>) | 5C, or 60 for the adapter error |
| 1B | SBI alert | 58 |
| 19 | silo comparator lock with SC<30> | 50 |
| 17-14 | SBI REQ7-REQ4 | 100 + 40 * (IPL - 14) + 4 * TR |

Nothing drives SBI fail, faults or alert in this model; DEC STD 032 gives
the adapter error IPL 1D, the SBIA's description (its vector register sits
at 2008 00B0 with the fault's) 1C, which the core follows.

The REQ lines are levels: a nexus keeps its request until software clears
its cause (RH780 TD 2.8.6.1), and the interrupt is taken again after REI if
it has not. To take an interrupt the EBox microcode reads the level's
vector register with a physical reference, 2008 0080 + 4 * (IPL - 10). For
IPL 14-17 that is an interrupt summary read on the SBI: every nexus
requesting at that level answers with its TR bit, the adapter takes the
lowest TR and returns the vector; with no answer it returns 0, and the
interrupt goes through SCB 00, passive release, at the request's IPL. At
IPL 14 the console's interrupts (internal) go first. Software can read the
vector registers too, with the same result.

For testing without devices, MAINT<04> lets the maintenance TR bits in
SC<7:4> drive REQ4-REQ7 and SC<3> SBI alert, and MAINT<01> makes the
adapter answer interrupt summary reads with its write data latch, the last
longword the CPU wrote to it.

## Processor initialization

Power-up, the OSD reset and every program load leave the I/O side as the
console leaves it after booting: the PAMM as above, CNF 0200 0010, CSR
E000 0000 (interrupts, SBI cycles out and in enabled), every other SBIA
register 0 (the DMA buffers' registers included; buffer A takes the next
command), no memory interlock, EHSR and MERG 0.

## How it was checked

| Test | What |
|---|---|
| `tests/mmu/t47_sbia.s` | PAMM reads, a remap and its undoing; the SBIA registers after initialization and what each keeps; address errors (nonexistent register, multiple error, write to a vector register, SBI cycles out off), SBI timeouts (read, write, SBI memory space, short timeout), an error confirmation (a longword in Unibus space), the nexus that are there; non-existent memory (read, write, instruction fetch, an unaligned read whose second half is missing, autoincrement put back); EHSR in EHM.STS. 16 machine checks, 385 longwords, expected values from the DEC documents (`tests/mmu/gen/mk_t47.py`) |
| `tests/mmu/t48_sbiaint.s` | the vector registers; interrupts at IPL 14-17 with the lowest TR first and the highest level first, requests that stay until cleared, passive release, SBI alert, silo comparator lock, master interrupt enable, the console before the SBIA at IPL 14 |
| `tests/mmu/t49_mchk2.s` | a second machine check with EHSR<05> set: halt 5 at the failing instruction, registers put back |
| `tests/mmu/t51_mba.s` | the RH780's registers after initialization and what each keeps, the map registers and SMR, the drive register space of an RP07 with no image (DT, DS, CS1, SN, DA, DC, OF; ILR, ATA and SR<16>, drive clear), a drive that is not there (NED), references the adapter does not take (error confirmation for a word and a byte, no response for three addresses: machine checks), its interrupt at SCB 160 on IPL 15, INIT and UNJAM. 93 longwords |
| `tests/mmu/t52_rp07.s` | an RP07 with an image: DS, pack acknowledge, read-in preset; a seek (PIP, GO, ATA, CC, AS); RMR during a seek, a command ignored while ERR is set, drive clear; IAE, ILF; search and LA; recalibrate, offset, return to centerline, a seek in offset mode, a seek to where the heads are; no image (UNS); unload |
| `tests/mmu/t53_mbard.s` | reads: one sector (DT COMP, VAR, BCR, DA), three sectors across a head switch into pages mapped apart, seven bytes to an odd address (masked writes, VAR eight past, the Massbus counter past 0), read header and data, a mid-transfer seek, the disk's last sector (AOE, LST), a page not valid (INVMAP), FMT clear (FER), the interrupt at the end of a transfer |
| `tests/mmu/t54_mbawr.s` | writes read back and compared, write checks (equal, upper byte, lower byte), three bytes (the sector completed with zeros), five bytes from an odd address, write header and data, write check header and data, program errors during a transfer, missed transfers (no drive, an illegal function, a read only image), CR<1> |
| `tests/mmu/t50_dma.s` | read lengths and write masks in ERRSUM<27:26> (odd and even words, a byte, address errors, an SBI timeout); quadclear clearing memory, the buffers A, B, C in turn and their registers; quadclears nobody takes (beyond the memory separator, CSR<29> clear, every buffer forced busy: timeout with busy status); a DMA the MBox aborts (MBox detected error, the buffer's registers frozen, the adapter error interrupt at IPL 1C); CPU references to SBI memory space (a read marked bad, a write that completes). 96 longwords |
| `tests/mmu/t55_uba.s` | the DW780's registers after initialization and what each keeps (map registers all 32 bits, BRSVR, DCR, CR); references it does not take (a longword or an unaligned word in Unibus space, writes to FMER, FUBAR and BRRVR, an extended function: error confirmations; reserved offsets: no response) and the machine checks they make; the I/O page with nothing in it (slave sync timeouts for reads, writes and bytes, FUBAR, zeros read); SUEFIE and CNFIE, BRRVR<31>, the adapter's interrupt at SCB 10C on IPL 14. 117 longwords |
| `tests/mmu/t56_ubadma.s` | the data paths, through wraparound: the direct data path's words and bytes; an invalid map register (IVMR, FMER, LEB), map registers disabled by CR<30:26>; a buffered data path written (the quadword on its last byte, the buffer state, BUBA, the purge, byte by byte), with byte offset, read (the quadword or longword, words from the buffer, the prefetch, a prefetch into an invalid map register), with byte offset, longword access mode. 85 longwords |
| `tests/mmu/t57_ubaerr.s` | DMA errors: read data substitute (a megabyte the PAMM takes away), SBI transfers beyond the memory separator (the direct path's master gives up; a buffer's write: CXTMO, BTE), a buffer with BTE set, a purge through an invalid map register, map and data path parity defeat (MRPF, DPPE, a read with PB: read data substitute, a machine check), USEFIE. 53 longwords |
| `tests/mmu/t58_ubainit.s` | adapter init: what it clears, CR read during the routine (a machine check), CR written meanwhile, MIC OK; the power fail sequence (UB PDN, UB INIT, a select timeout during INIT, UBIC about 25 ms on), CR<1> holding the Unibus down, SBI UNJAM. 36 longwords |
| `tests/mmu/t59_ubdev.s` | the device side, with the bench's Unibus test device (`sim/cpu_tb/ubdev.v`): its registers by words and bytes; Unibus interrupts (IFS clear, IFS alone polled, DINTR, IFS and BRIE at SCB 14C, a passive release, BR4 with the adapter's request in one interrupt at SCB 10C, BR6 and BR7 at SCB 18C and 1CC); the device as DMA master (DATO, DATI, DATOB and DATIP-DATO through the direct data path; a buffered path written, purged, read with the prefetch; DATIP through a buffer, an invalid map register, the I/O page: no slave sync; a long burst that makes the adapter's read a select timeout; the interrupt at the end of the DMA); INIT clearing the device. 90 longwords |
| the rest of `tests/mmu`, `mmutest.bin` (52 tests on the full system), EVKAE | nothing else changed |

These are `noref` tests: the reference simulator gives different results by
design (780 register layout, writes that complete, no PAMM writes, no SBIA
DMA side; its RH780 and RP07 leave out the header words, timing, the silo's
byte alignment and several errors), so the log is checked against the values
DEC's documents give (`tests/mmu/gen/mk_t*.py`). t52 to t54 run with
generated disks on the CPU bench (`;@ disk0=pattern`, see `sim/hpsdisk.h`)
and are left out of the board suite, which cannot know what is mounted; t51
compares DS without MOL and VV for the same reason. t59 needs the bench's
Unibus test device and is left out of the board suite too.
`tests/mmu/run.py` now dumps every longword a test checks, so a test cannot
pass without being compared.

## Where the core and the reference simulator differ, on purpose

| | Reference simulator | Core (DEC) |
|---|---|---|
| CNF | 0040 0010 (4 MB) | 0200 0010: the memory separator the console sets for 32 MB |
| CSR after initialization | 6000 0000 | E000 0000, as the console leaves it |
| SBIER, TOADR | 11/780 layout (CRD, RDS, IB bits; TOADR with mode and virtual bits) | 8600 layout |
| a write nothing answers | completes, interrupt at IPL 1D (SCB 60) | machine check |
| the PAMM | fixed | a RAM software can write |
| EHM.STS | 0002 0000, process abort | 4000 0800 |
| EBCS, MSTAT1, MSTAT2 | one value for every case | per case (read/write, fetch, NXM or I/O) |
| EHSR | <05> only | the whole longword |
| MERG | reads 0 | <12:9,5:0>, <8> MAPEN |
| DMA side | quadclear and DMA go straight to memory | the receiver's rules (CSR<29>, memory separator), transaction buffers and their registers, MBox abort of non-memory PAMM codes |
| RH780 | starting a transfer clears SR's status bits; no missed transfer or data late | SR bits only cleared by software or INIT; MXF, DLT; byte-exact transfers through the silo |
| RP07 | header commands move data only; a command to a drive with ERR set is ILF; times counted in instructions | four header words per sector; the command ignored (RH780 TD 3.3); the RP07's times |
| DW780's own interrupts | BR5 (IPL 15, SCB 14C) | BR4 (IPL 14, SCB 10C): the first DW780's jumpers |
| DW780 registers | longwords only (others an error confirmation) | any read length (TD 3.4.7.2) |
| BRRVR | the adapter's request cleared by reading it; a vector only with IFS and BRIE | the adapter's request a level until its cause is cleared; IFS alone polls (TD 2.9.8) |
| CPU references below the I/O page | non-existent (no Unibus memory) | wraparound through the adapter's map (TD 1.9.2) |
| buffered data paths | DMA straight to memory, the DPR only follows the address | quadword buffers, prefetch, purge (TD 3.3), longword access mode |
| Unibus timing | a reference completes at once; a missing device is a slave sync timeout at once, never a select timeout | the adapter arbitrates for the bus: select timeout after 51.2 us, slave sync timeout after 12.8 us, busy confirmations while a transfer is in progress |
| a second Unibus timeout while SR<1:0> is locked | sets LEB | sets nothing: LEB belongs to the DMA error field (TD 2.9.3) |

## Not done yet

- Unibus devices: a DZ11 next (more terminals on the MiSTer UART), later
  perhaps a UDA50.
- The DW780's SBI parity and faults, its own power supply (AD PDN, AD PUP),
  Unibus parity but for the data path parity error it makes, CRD, RDTO and
  CXTER (nothing on this SBI returns them), DMA to SBI I/O space (no nexus
  here takes it), BRRVR full (every read data gets its ACK), interlock
  sequence faults (the SBIA sends no interlock functions).
- The RH780's maintenance mode beyond its register bits (the simulated
  Massbus signals DR<27:24>), parity inversion, reverse transfers (tape).
- RP07 errors that need a real platter: data checks and ECC, header compare
  and CRC errors, drive timing, offset magnitudes; a drive's dual port.
- MERG<12> (inhibit DMA) is kept and read back but does not hold DMA off.
- The DMA buffers working in parallel: the receiver takes one command at a
  time, which only a diagnostic timing the SBI could tell.
- The silo itself, conditional silo comparisons, parity error injection,
  loopback, SBI faults: diagnostics' business, with nothing in this model
  that could produce them.
- SBIA 1 (I/O adapter 1, 2200 0000).

## Files

| File | What |
|---|---|
| `rtl/mister/vax_io.v` | PAMM (three copies), routing to memory, SBIA 0 or non-existent memory, MSTAT2/MEAR; the DMA port and the CPU/DMA arbitration; the SBI: its nexus, their confirmations, interrupt requests and DMA masters |
| `rtl/mister/vax_sbi.v` | SBIA 0: registers, CPU transactions, the receiver (DMA), interrupts |
| `rtl/mister/vax_mba.v` | the RH780: registers, map, the Massbus control path, the data path (silo, DMA), interrupts |
| `rtl/mister/vax_rp07.v` | an RP07: registers, commands, rotation and seeks, its two sector buffers and the SD card requests |
| `rtl/mister/vax_uba.v` | the DW780: registers, the map and data paths (two M10K RAMs), the microsequencer, the adapter as Unibus master, interrupts, initialization and the power fail sequence |
| `sim/cpu_tb/ubdev.v` | the CPU bench's Unibus test device: registers, an interrupt, DMA |
| `sim/hpsdisk.h` | the HPS's side of the block devices for the benches |
| `rtl/vcache.v`, `rtl/mmu.v`, `rtl/mister/vax_cache.v` | byte masks: the aligner makes them, the MMU passes them on, the cache writes only those bytes |
| `rtl/cpu.v` | machine check frame (`mc_frame`), EHSR, MERG, the double error halt, the SBIA interrupt level |
| `rtl/ucode.def` | `intrq_hw`, `intrq_io` (vector register read), `mcheck` (frame) |
| `tests/mmu/t47_sbia.s` to `t59_ubdev.s`, `gen/mk_t*.py`, `gen/explog.py` | the tests and their expected values |
