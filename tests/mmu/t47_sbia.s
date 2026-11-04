; t47_sbia - the VAX 8600's MBox and SBIA 0 seen from software, mapping off:
; the physical address memory map (PAMLOC, PAMACC: read, remapped, restored),
; the SBIA 0 registers at 2008 0000 (EK-DB86X-TD-002, 3.14), and the
; references the MBox cannot complete - all machine checks (SCB 04) with
; the 8600 frame (DEC STD 032 table B-26; EK-8600S-MM-004, M-03, M-04 and
; appendix K):
;
;   - non-existent memory, PAMM code 1F: read, write, instruction fetch,
;     an unaligned read whose second longword is missing, autoincrement
;     put back (MSTAT2<03>, the code in <20:16>);
;   - CP I/O buffer errors from the SBIA (MSTAT2<02>): address errors (a
;     register that does not exist, a write to a vector register, the SBI
;     with CSR<30> clear), SBI timeouts (a nexus that is not there: read,
;     write, SBI memory space, the short timeout), an error confirmation
;     (a longword in Unibus space, which the DW780 takes only by words and
;     bytes), with ERRSUM, SBIER and TOADR locked by ERRSUM<23> until
;     software clears them;
;   - EHSR: what the error handling microcode makes of it, and EHM.STS.
;
; The reference simulator does not model these (780-style SBIA registers,
; writes that complete): noref, and the expected log is the DEC behaviour.
;
; The machine check handler logs a summary of each frame (18 longwords):
; the byte count, EHM.STS, EVMQSAV, EBCS, CSLINT, IVASAV, VIBASAV -
; (instruction & ~3), ESASAV, ISASAV and CPC - instruction (0), MSTAT1,
; MSTAT2, MERG, CSHCTL, MEAR, the OR of the other ten (0), PC - instruction
; (0), PSL and EHSR; it then clears EHSR as VMS does and continues at R8.
; R7 holds the address of the instruction that is expected to fail.
;@ noref
;@ rtl=18000:00000000,18004:00000000,18008:00300000,1800C:00300000,18010:00400000,18014:00400001
;@ rtl=18018:01F00000,1801C:01F00007,18020:02000000,18024:0200001F,18028:1FF00000,1802C:1FF0001F
;@ rtl=18030:20000000,18034:20000018,18038:21F00000,1803C:21F00018,18040:22000000,18044:2200001F
;@ rtl=18048:30000000,1804C:3000001F,18050:3FF00000,18054:3FF0001F,18058:3FF00000,1805C:3FF0001F
;@ rtl=18060:03000002,18064:11223344,18068:55667788,1806C:0300001F,18070:00000058,18074:40000800
;@ rtl=18078:03000010,1807C:0020C000,18080:081D0000,18084:03000010,18088:00000000,1808C:00000000
;@ rtl=18090:00000000,18094:00000000,18098:B8000000,1809C:001F0008,180A0:00000000,180A4:00000003
;@ rtl=180A8:03000010,180AC:00000000,180B0:00000000,180B4:041F0000,180B8:00080020,180BC:02000010
;@ rtl=180C0:E0000000,180C4:1C000000,180C8:00000000,180CC:00000000,180D0:00000000,180D4:0802000E
;@ rtl=180D8:00000000,180DC:00000000,180E0:00000000,180E4:00000000,180E8:00000000,180EC:3FF00010
;@ rtl=180F0:02000010,180F4:00000000,180F8:E0000000,180FC:000F001E,18100:00000000,18104:00040000
;@ rtl=18108:FF80091F,1810C:FFFF0000,18110:00000000,18114:00000058,18118:40000800,1811C:20080050
;@ rtl=18120:0020C002,18124:081D0000,18128:20080050,1812C:00000000,18130:00000000,18134:00000000
;@ rtl=18138:00000000,1813C:B8000000,18140:00180004,18144:00000000,18148:00000003,1814C:20080050
;@ rtl=18150:00000000,18154:00000000,18158:041F0000,1815C:00080020,18160:1C980000,18164:08020014
;@ rtl=18168:00000000,1816C:00000058,18170:40000800,18174:20080054,18178:0020C004,1817C:081D0000
;@ rtl=18180:20080054,18184:00000004,18188:00000000,1818C:00000000,18190:00000000,18194:B4000000
;@ rtl=18198:00180004,1819C:00000000,181A0:00000003,181A4:20080054,181A8:00000000,181AC:00000000
;@ rtl=181B0:041F0000,181B4:00080020,181B8:1C990000,181BC:1C000000,181C0:00000058,181C4:40000800
;@ rtl=181C8:20080090,181CC:0020C004,181D0:081D0000,181D4:20080090,181D8:00000004,181DC:00000000
;@ rtl=181E0:00000000,181E4:00000000,181E8:B4000000,181EC:00180004,181F0:00000000,181F4:00000003
;@ rtl=181F8:20080090,181FC:00000000,18200:00000000,18204:041F0000,18208:00080020,1820C:DC980000
;@ rtl=18210:08020024,18214:00000058,18218:40000800,1821C:20006000,18220:0020C002,18224:081D0000
;@ rtl=18228:20006000,1822C:00000000,18230:00000000,18234:00000000,18238:00000000,1823C:B8000000
;@ rtl=18240:00180004,18244:00000000,18248:00000003,1824C:20006000,18250:00000000,18254:00000000
;@ rtl=18258:041F0000,1825C:00080020,18260:1C980000,18264:08001800,18268:00000058,1826C:40000800
;@ rtl=18270:20080094,18274:0020C002,18278:081D0000,1827C:20080094,18280:00000004,18284:00000000
;@ rtl=18288:00000000,1828C:00000000,18290:B8000000,18294:00180004,18298:00000000,1829C:00000003
;@ rtl=182A0:20080094,182A4:00000000,182A8:00000000,182AC:041F0000,182B0:00080020,182B4:00000050
;@ rtl=182B8:00000058,182BC:40000800,182C0:2000A000,182C4:0020C002,182C8:081D0000,182CC:2000A000
;@ rtl=182D0:00000000,182D4:00000000,182D8:00000000,182DC:00000000,182E0:B8000000,182E4:00180004
;@ rtl=182E8:00000000,182EC:00000003,182F0:2000A000,182F4:00000000,182F8:00000000,182FC:041F0000
;@ rtl=18300:00080020,18304:00001000,18308:08002800,1830C:1C800000,18310:00000000,18314:08002800
;@ rtl=18318:0802000E,1831C:00000058,18320:40000800,18324:2000C000,18328:0020C004,1832C:081D0000
;@ rtl=18330:2000C000,18334:00000004,18338:00000000,1833C:00000000,18340:00000000,18344:B4000000
;@ rtl=18348:00180004,1834C:00000000,18350:00000003,18354:2000C000,18358:00000000,1835C:00000000
;@ rtl=18360:041F0000,18364:00080020,18368:00001000,1836C:08003000,18370:DC800000,18374:00000058
;@ rtl=18378:40000800,1837C:20100000,18380:0020C002,18384:081D0000,18388:20100000,1838C:00000000
;@ rtl=18390:00000000,18394:00000000,18398:00000000,1839C:B8000000,183A0:00180004,183A4:00000000
;@ rtl=183A8:00000003,183AC:20100000,183B0:00000000,183B4:00000000,183B8:041F0000,183BC:00080020
;@ rtl=183C0:20100000,183C4:08040000,183C8:00000100,183CC:00000058,183D0:40000800,183D4:03000020
;@ rtl=183D8:0020C002,183DC:081D0000,183E0:03000020,183E4:00000000,183E8:00000000,183EC:00000000
;@ rtl=183F0:00000000,183F4:B8000000,183F8:00180004,183FC:00000000,18400:00000003,18404:03000020
;@ rtl=18408:00000000,1840C:00000000,18410:041F0000,18414:00080020,18418:00C00008,1841C:00000058
;@ rtl=18420:40000800,18424:2001E000,18428:0020C002,1842C:081D0000,18430:2001E000,18434:00000000
;@ rtl=18438:00000000,1843C:00000000,18440:00000000,18444:B8000000,18448:00180004,1844C:00000000
;@ rtl=18450:00000003,18454:2001E000,18458:00000000,1845C:00000000,18460:041F0000,18464:00080020
;@ rtl=18468:00001000,1846C:08007800,18470:00010028,18474:00000020,18478:00000000,1847C:1C000000
;@ rtl=18480:00000058,18484:40000800,18488:02000000,1848C:0020C000,18490:081D0000,18494:02000000
;@ rtl=18498:00000000,1849C:00000000,184A0:00000000,184A4:00000000,184A8:B8000000,184AC:001F0008
;@ rtl=184B0:00000000,184B4:00000003,184B8:02000000,184BC:00000000,184C0:00000000,184C4:041F0000
;@ rtl=184C8:00080020,184CC:1C000000,184D0:00000058,184D4:40000800,184D8:30000004,184DC:0020C004
;@ rtl=184E0:081D0000,184E4:30000004,184E8:00000008,184EC:00000000,184F0:00000000,184F4:00000000
;@ rtl=184F8:B4000000,184FC:001F0008,18500:00000000,18504:00000003,18508:30000004,1850C:00000000
;@ rtl=18510:00000000,18514:041F0000,18518:00080020,1851C:00000058,18520:40000800,18524:01FFFFFE
;@ rtl=18528:0020C000,1852C:081D0000,18530:01FFFFFE,18534:00000000,18538:00000000,1853C:00000000
;@ rtl=18540:00000000,18544:B8000000,18548:001F0008,1854C:00000000,18550:00000003,18554:02000000
;@ rtl=18558:00000000,1855C:00000000,18560:041F0000,18564:00080020,18568:00000058,1856C:40000800
;@ rtl=18570:00000000,18574:0020C000,18578:081D0000,1857C:00000000,18580:00000000,18584:00000000
;@ rtl=18588:00000000,1858C:00000000,18590:F8000000,18594:001F0008,18598:00000000,1859C:00000003
;@ rtl=185A0:02000000,185A4:00000000,185A8:00000000,185AC:041F0000,185B0:00080020,185B4:00000058
;@ rtl=185B8:D1060800,185BC:3FFFFFFC,185C0:0020C000,185C4:081D0000,185C8:3FFFFFFC,185CC:00000000
;@ rtl=185D0:00000000,185D4:00000000,185D8:00000000,185DC:B8000000,185E0:001F0008,185E4:00000000
;@ rtl=185E8:00000003,185EC:3FFFFFFC,185F0:00000000,185F4:00000000,185F8:041F0000,185FC:060800B1
;@ rtl=18600:00000000
;@ clocks=4000000
LOG	= ^x18000
SCBB	= ^x11
IPL	= ^x12
PAMACC	= ^x40
PAMLOC	= ^x41
EHSR	= ^x4A
SBIA	= ^x20080000

	.org	^x1000
start:	movl	#^xE000, sp		; interrupt stack (PSL<IS> is set)
	clrl	r0
	movab	unexp+1, r1
scbfill:
	movl	r1, (r0)+
	cmpl	r0, #^x200
	blss	scbfill
	movab	mchk_h+1, @#^x04	; machine check: interrupt stack
	mtpr	#0, #SCBB
	movl	#LOG, r11
	clrl	r9

; ------------------------------------------------ the physical address map
; the console's: eight 4 MB arrays in slots 0-7, SBIA 0 at 2000 0000 - 21FF
; FFFF (code 18), nothing else (1F). PAMLOC keeps <29:20>.
	moval	pamtab, r6
	movl	#12, r5
pamm:	mtpr	(r6)+, #PAMLOC
	mfpr	#PAMLOC, (r11)+
	mfpr	#PAMACC, (r11)+
	sobgtr	r5, pamm
; megabyte 30 (0300 0000) to array slot 2: it is then 0080 0000
	movl	#^x11223344, @#^x00800010
	mtpr	#^x03000000, #PAMLOC
	mtpr	#2, #PAMACC
	mfpr	#PAMACC, (r11)+
	movl	@#^x03000010, (r11)+	; 11223344
	movl	#^x55667788, @#^x03000014
	movl	@#^x00800014, (r11)+	; 55667788
	mtpr	#^x1F, #PAMACC		; back to non-existent
	mfpr	#PAMACC, (r11)+
	movab	f01, r7
	movab	n01, r8
	tstl	r8
f01:	movl	@#^x03000010, r0	; machine check
	movl	#^x600D, (r11)+		; (skipped)
n01:

; ------------------------------------------- SBIA 0 after initialization
; CNF: memory separator 32 MB, adapter type 1. CSR: interrupts, SBI cycles
; out and in enabled. ERRSUM and TOADR, unlocked, show the transaction
; that reads them: a longword read (0001, 11) of 2008 0008, 2008 0038.
	movl	@#SBIA, (r11)+		; 02000010
	movl	@#SBIA+^x04, (r11)+	; E0000000
	movl	@#SBIA+^x08, (r11)+	; 1C000000
	movl	@#SBIA+^x0C, (r11)+	; 0
	movl	@#SBIA+^x10, (r11)+	; DMA I command/address: 0
	movl	@#SBIA+^x34, (r11)+	; SBIER 0
	movl	@#SBIA+^x38, (r11)+	; TOADR 0802000E
	movl	@#SBIA+^x3C, (r11)+	; 0
	movl	@#SBIA+^x40, (r11)+	; 0
	movl	@#SBIA+^x44, (r11)+	; 0
	movl	@#SBIA+^x48, (r11)+	; unjam: reads 0
	movl	@#SBIA+^x4C, (r11)+	; quadclear: reads 0
; what each keeps of all ones
	movl	#-1, @#SBIA		; memory separator <29:20>
	movl	@#SBIA, (r11)+		; 3FF00010
	movl	#^x02000000, @#SBIA
	movl	@#SBIA, (r11)+		; 02000010
	clrl	@#SBIA+^x04
	movl	@#SBIA+^x04, (r11)+	; 0
	movl	#-1, @#SBIA+^x04
	movl	@#SBIA+^x04, (r11)+	; E0000000
	movl	#^x000F001E, @#SBIA+^x0C	; DCR, not diag dead nor short
	movl	@#SBIA+^x0C, (r11)+	; 000F001E
	clrl	@#SBIA+^x0C
	movl	#-1, @#SBIA+^x34	; SBIER: nothing to clear
	movl	@#SBIA+^x34, (r11)+	; 0
	movl	#-1, @#SBIA+^x3C	; FS: <18> fault interrupt enable
	movl	@#SBIA+^x3C, (r11)+	; 00040000
	clrl	@#SBIA+^x3C
	movl	#-1, @#SBIA+^x44	; MAINT
	movl	@#SBIA+^x44, (r11)+	; FF80091F
	clrl	@#SBIA+^x44
; silo comparator: unconditional lock with count F locks at the next SBI
; cycle (IE set too: at IPL 1F nothing is taken); a count other than F
; clears the lock
	movl	#-1, @#SBIA+^x40
	movl	#20, r0
w1:	sobgtr	r0, w1
	movl	@#SBIA+^x40, (r11)+	; FFFF0000
	clrl	@#SBIA+^x40
	movl	@#SBIA+^x40, (r11)+	; 0

; ------------------------------------------------- SBIA address errors
; a register that does not exist: 2008 0050
	movab	f02, r7
	movab	n02, r8
	tstl	r8
f02:	movl	@#SBIA+^x50, r0
	movl	#^x600D, (r11)+
n02:	movl	@#SBIA+^x08, (r11)+	; ERRSUM 1C980000: read, lock, ADE, C/A
	movl	@#SBIA+^x38, (r11)+	; TOADR 08020014
	movl	@#SBIA+^x34, (r11)+	; SBIER 0
; another one while locked: a write, ERRSUM<16> multiple
	movab	f03, r7
	movab	n03, r8
	tstl	r8
f03:	movl	#5, @#SBIA+^x54
	movl	#^x600D, (r11)+
n03:	movl	@#SBIA+^x08, (r11)+	; 1C990000
	movl	#^x00800000, @#SBIA+^x08	; clear the lock
	movl	@#SBIA+^x08, (r11)+	; 1C000000
; a write to a vector register
	movab	f04, r7
	movab	n04, r8
	tstl	r8
f04:	movl	#5, @#SBIA+^x90
	movl	#^x600D, (r11)+
n04:	movl	@#SBIA+^x08, (r11)+	; DC980000: write mask, longword
	movl	@#SBIA+^x38, (r11)+	; 08020024
	movl	#^x00800000, @#SBIA+^x08
; SBI cycles out disabled: the nexus and the BR4-7 vector registers (an
; interrupt summary read is an SBI cycle) are address errors; the adapter's
; own registers and vectors are not
	movl	#^xA0000000, @#SBIA+^x04
	movab	f05, r7
	movab	n05, r8
	tstl	r8
f05:	movl	@#^x20006000, r0	; TR 3
	movl	#^x600D, (r11)+
n05:	movl	@#SBIA+^x08, (r11)+	; 1C980000
	movl	@#SBIA+^x38, (r11)+	; 08001800
	movl	#^x00800000, @#SBIA+^x08
	movab	f06, r7
	movab	n06, r8
	tstl	r8
f06:	movl	@#SBIA+^x94, r0		; IPL 15 vector
	movl	#^x600D, (r11)+
n06:	movl	#^x00800000, @#SBIA+^x08
	movl	@#SBIA+^xA4, (r11)+	; IPL 19 vector: 50
	movl	#^xE0000000, @#SBIA+^x04

; --------------------------------------------------------- SBI timeouts
; nothing at TR 5: no response for 512 SBI cycles
	movab	f07, r7
	movab	n07, r8
	tstl	r8
f07:	movl	@#^x2000A000, r0
	movl	#^x600D, (r11)+
n07:	movl	@#SBIA+^x34, (r11)+	; SBIER 00001000: CP timeout, no response
	movl	@#SBIA+^x38, (r11)+	; TOADR 08002800
	movl	@#SBIA+^x08, (r11)+	; ERRSUM 1C800000
	movl	#^x1000, @#SBIA+^x34	; clear SBIER<12,11:10,08>
	movl	@#SBIA+^x34, (r11)+	; 0
	movl	@#SBIA+^x38, (r11)+	; still locked: 08002800
	movl	#^x00800000, @#SBIA+^x08
	movl	@#SBIA+^x38, (r11)+	; 0802000E
; a write: TR 6
	movab	f08, r7
	movab	n08, r8
	tstl	r8
f08:	movl	#^x12345678, @#^x2000C000
	movl	#^x600D, (r11)+
n08:	movl	@#SBIA+^x34, (r11)+	; 00001000
	movl	@#SBIA+^x38, (r11)+	; 08003000
	movl	@#SBIA+^x08, (r11)+	; DC800000
	movl	#^x1000, @#SBIA+^x34
	movl	#^x00800000, @#SBIA+^x08
; a longword in Unibus space: the DW780 answers with an error
; confirmation; autoincrement put back
	movl	#^x20100000, r2
	movab	f09, r7
	movab	n09, r8
	tstl	r8
f09:	movl	(r2)+, r0
	movl	#^x600D, (r11)+
n09:	movl	r2, (r11)+		; 20100000
	movl	@#SBIA+^x38, (r11)+	; 08040000
	movl	@#SBIA+^x34, (r11)+	; 00000100: error confirmation
	nop				; (keeps the code after it in place mod 4)
	movl	#^x1000, @#SBIA+^x34
	movl	#^x00800000, @#SBIA+^x08
; SBI memory space: megabyte 30 to SBIA 0, an SBI address with <27> clear
	mtpr	#^x03000000, #PAMLOC
	mtpr	#^x18, #PAMACC
	movab	f10, r7
	movab	n10, r8
	tstl	r8
f10:	movl	@#^x03000020, r0
	movl	#^x600D, (r11)+
n10:	movl	@#SBIA+^x38, (r11)+	; 00C00008
	mtpr	#^x1F, #PAMACC
	movl	#^x1000, @#SBIA+^x34
	movl	#^x00800000, @#SBIA+^x08
; the short timeout, DCR<0>: 8 SBI cycles
	movl	#1, @#SBIA+^x0C
	movab	f11, r7
	movab	n11, r8
	tstl	r8
f11:	movl	@#^x2001E000, r0	; TR 15
	movl	#^x600D, (r11)+
n11:	movl	@#SBIA+^x34, (r11)+	; 00001000
	movl	@#SBIA+^x38, (r11)+	; 08007800
	clrl	@#SBIA+^x0C
	movl	#^x1000, @#SBIA+^x34
	movl	#^x00800000, @#SBIA+^x08
; the nexus that are there
	movl	@#^x20006000, (r11)+	; TR 3, DW780: 00010028
	movl	@#^x20010000, (r11)+	; TR 8, RH780: 00000020
	movl	@#SBIA+^x34, (r11)+	; 0
	movl	@#SBIA+^x08, (r11)+	; 1C000000

; --------------------------------------------------- non-existent memory
	movab	f12, r7
	movab	n12, r8
	tstl	r8
f12:	movl	@#^x02000000, r0	; read
	movl	#^x600D, (r11)+
n12:	movl	@#SBIA+^x08, (r11)+	; not an SBIA error: 1C000000
	movab	f13, r7
	movab	n13, r8
	tstl	r8
f13:	movl	#^x77, @#^x30000004	; write
	movl	#^x600D, (r11)+
n13:
; an unaligned longword whose second half does not exist
	movab	f14, r7
	movab	n14, r8
	tstl	r8
f14:	movl	@#^x01FFFFFE, r0
	movl	#^x600D, (r11)+
n14:
; an instruction fetch
	movl	#^x02000000, r7
	movab	n15, r8
	tstl	r8
	jmp	@#^x02000000
	movl	#^x600D, (r11)+
n15:
; EHSR: what software left in it is part of EHM.STS (<7>, <4>, <3:0>,
; <31:27>, <26>, <25>), and the microcode sets the vector and VMS entered
	mtpr	#^x06000091, #EHSR
	movab	f16, r7
	movab	n16, r8
	tstl	r8
f16:	movl	@#^x3FFFFFFC, r0
	movl	#^x600D, (r11)+
n16:	movl	r9, (r11)+		; no unexpected interrupt or exception
	halt

pamtab:	.long	^x00000000, ^x00312345, ^x00400000, ^x01F00000
	.long	^x02000000, ^x1FF00000, ^x20000000, ^x21F00000
	.long	^x22000000, ^x30000000, ^x3FF00000, ^x3FFFFFFF

; machine check: log the frame's summary, PC and PSL, EHSR; clear EHSR;
; continue at R8
	.align	4
mchk_h:	movl	(sp)+, r3		; byte count
	movl	r3, (r11)+
	movl	sp, r4			; the frame
	movl	(r4), (r11)+		; EHM.STS
	movl	4(r4), (r11)+		; EVMQSAV
	movl	8(r4), (r11)+		; EBCS
	movl	16(r4), (r11)+		; CSLINT
	movl	32(r4), (r11)+		; IVASAV
	bicl3	#3, r7, r5
	subl3	r5, 36(r4), (r11)+	; VIBASAV - (instruction & ~3)
	subl3	r7, 40(r4), (r11)+	; ESASAV - instruction
	subl3	r7, 44(r4), (r11)+	; ISASAV - instruction
	subl3	r7, 48(r4), (r11)+	; CPC - instruction
	movl	52(r4), (r11)+		; MSTAT1
	movl	56(r4), (r11)+		; MSTAT2
	movl	64(r4), (r11)+		; MERG
	movl	68(r4), (r11)+		; CSHCTL
	movl	72(r4), (r11)+		; MEAR
	bisl3	12(r4), 20(r4), r5	; EDPSR, IBESR
	bisl2	24(r4), r5		; EBXWD1
	bisl2	28(r4), r5		; EBXWD2
	bisl2	60(r4), r5		; MDECC
	bisl2	76(r4), r5		; MEDR
	bisl2	80(r4), r5		; FBXERR
	bisl2	84(r4), r5		; CSES
	movl	r5, (r11)+
	addl2	r3, sp			; pop the frame
	subl3	r7, (sp), (r11)+	; PC - instruction
	movl	4(sp), (r11)+		; PSL
	mfpr	#EHSR, (r11)+
	mtpr	#0, #EHSR		; as VMS does before its REI
	movl	r8, (sp)
	rei

	.align	4
unexp:	movl	#^xBAD, r9
	halt
