; t58_ubainit - initialization of the DW780 (EK-DW780-TD-001 2.8, 2.9.1,
; 2.9.2, 2.9.4, 3.3.3, 3.5.9):
;
;   - adapter init (CR<0>): the map, data path, status and BRSVR registers
;     and DCR<31:28> cleared, the control register too (and written again
;     during the initialization, as software does); for its 500 us only
;     CNFGR and DCR can be read - a CR read is a machine check - and DCR
;     shows MIC OK clear;
;   - the Unibus power fail sequence it starts: AC LO at once (CNFGR<17>,
;     UBIC cleared), DC LO and INIT 5 ms later (<18>), during which the
;     adapter cannot get the Unibus (Unibus select timeout), then UBIC
;     (clearing <18:17>) about 25 ms after the start; with CNFIE each step
;     is an adapter interrupt request;
;   - CR<1> (UPF): the same power fail, the Unibus staying down while it
;     is set, coming up when it is cleared;
;   - SBI UNJAM: CR's interrupt enables cleared (not IFS, not the map
;     register disable bits) and the power fail sequence.
;
; Expected values: tests/mmu/gen/mk_t58.py.
;@ noref
;@ rtl=18000:A0030080,18004:00000001,18008:00020028,1800C:00020028,18010:00000058,18014:0020C002
;@ rtl=18018:B8000000,1801C:00180004,18020:20006004,18024:00000000,18028:00000004,1802C:00000000
;@ rtl=18030:08020028,18034:00000000,18038:00000000,1803C:00000000,18040:00000000,18044:80000000
;@ rtl=18048:00020028,1804C:00060028,18050:FFFF0000,18054:00000002,18058:0000F800,1805C:00010028
;@ rtl=18060:80000000,18064:00000000,18068:00000028,1806C:00020028,18070:00060028,18074:00000002
;@ rtl=18078:00010028,1807C:0C000040,18080:00020028,18084:00010028,18088:00000000,1808C:00000000
;@ clocks=20000000
LOG	= ^x18000
SCBB	= ^x11
EHSR	= ^x4A
SBIA	= ^x20080000
ERRSUM	= SBIA+^x08
SBIER	= SBIA+^x34
UNJAM	= SBIA+^x48
UBA	= ^x20006000
CNFGR	= UBA
UACR	= UBA+^x04
UASR	= UBA+^x08
DCR	= UBA+^x0C
FUBAR	= UBA+^x14
BRSVR	= UBA+^x20
BRRVR	= UBA+^x30
DPR	= UBA+^x40
MAP	= UBA+^x800
UB	= ^x20100000
IOP	= UB+^x3E000
LOCK	= ^x00800000
TMO	= ^x1000

	.org	^x1000
start:	movl	#^xE000, sp
	clrl	r0
	movab	unexp+1, r1
scbfill:
	movl	r1, (r0)+
	cmpl	r0, #^x200
	blss	scbfill
	movab	mchk_h+1, @#^x04
	mtpr	#0, #SCBB
	movl	#LOG, r11
	clrl	r9
	movl	#1, @#UACR		; a clean start (the board suite)
	jsb	ubic

; ------------------------------------------------- something to clear
	movl	#^x80000100, @#MAP
	movl	#^x80200101, @#MAP+4
	movl	#^x1234, @#BRSVR
	movl	#^x80000000, @#DCR	; the spare bit
	movw	#1, @#UB+^x200		; BDP 1: a word in the buffer
	movw	@#IOP, r0		; UBSSYNTO
	movl	@#DPR+4, (r11)+		; A0030080
	movl	@#UASR, (r11)+		; 00000001
	movl	#^x0800007C, @#UACR	; MRD 2, all the enables but UPF

; ------------------------------------------------------ adapter init
	movl	#1, @#UACR
	movl	@#CNFGR, (r11)+		; 00020028: AC LO (UB PDN), UBIC clear
	movl	@#DCR, (r11)+		; 00020028: MIC OK clear, spare clear
	movab	f01, r7
	movab	n01, r8
	tstl	r8
f01:	movl	@#UACR, r0		; not during the initialization
	movl	#^x600D, (r11)+
n01:	movl	#TMO, @#SBIER
	movl	#LOCK, @#ERRSUM
	movl	#4, @#UACR		; CR can be written meanwhile: CNFIE
w01:	bitl	#^x08000000, @#DCR	; MIC OK: the routine done
	beql	w01
	movl	@#UACR, (r11)+		; 00000004
	movl	@#UASR, (r11)+		; 0
	movl	@#DCR, (r11)+		; 08020028
	movl	@#BRSVR, (r11)+		; 0
	movl	@#MAP, (r11)+		; 0
	movl	@#MAP+4, (r11)+		; 0
	movl	@#DPR+4, (r11)+		; 0
	movl	@#BRRVR, (r11)+		; 80000000: CNFIE and UB PDN
	movl	@#CNFGR, (r11)+		; 00020028: still before DC LO
w02:	bitl	#^x40000, @#CNFGR	; UB INIT: DC LO and INIT, 5 ms
	beql	w02
	movl	@#CNFGR, (r11)+		; 00060028
	movl	#-1, r0
	movw	@#IOP, r0		; INIT: the adapter cannot get the bus
	movl	r0, (r11)+		; FFFF0000
	movl	@#UASR, (r11)+		; 00000002: Unibus select timeout
	movl	@#FUBAR, (r11)+		; 0000F800
	movl	#2, @#UASR
	jsb	ubic
	movl	@#CNFGR, (r11)+		; 00010028: UBIC; UB INIT, UB PDN clear
	movl	@#BRRVR, (r11)+		; 80000000: CNFIE and UBIC
	movl	#^x00070000, @#CNFGR	; write 1 to clear
	movl	@#BRRVR, (r11)+		; 0
	movl	@#CNFGR, (r11)+		; 00000028

; --------------------------------------------------------------- UPF
	movl	#2, @#UACR
	movl	@#CNFGR, (r11)+		; 00020028
w03:	bitl	#^x40000, @#CNFGR	; DC LO, INIT
	beql	w03
	movl	#60000, r1		; the Unibus stays down (35 ms or so)
d01:	sobgtr	r1, d01
	movl	@#CNFGR, (r11)+		; 00060028: no UBIC
	movl	@#UACR, (r11)+		; 00000002
	clrl	@#UACR			; up it comes
	jsb	ubic
	movl	@#CNFGR, (r11)+		; 00010028

; ------------------------------------------------------------- UNJAM
	movl	#^x0C00007C, @#UACR	; MRD 3, IFS and the enables
	movl	#1, @#UNJAM
	movl	@#UACR, (r11)+		; 0C000040: IFS and MRD stay
	movl	@#CNFGR, (r11)+		; 00020028
	jsb	ubic
	movl	@#CNFGR, (r11)+		; 00010028
	clrl	@#UACR
	movl	@#UASR, (r11)+		; 0
	movl	r9, (r11)+		; nothing unexpected
	halt

; wait for the Unibus initialization complete (CNFGR<16>), 40 ms at most
ubic:	movl	#200000, r1
ubic1:	bitl	#^x10000, @#CNFGR
	bneq	ubic2
	sobgtr	r1, ubic1
	movl	#^xDEAD, r9
ubic2:	rsb

; machine check: byte count, EBCS, MSTAT1, MSTAT2, MEAR, PC - R7
	.align	4
mchk_h:	movl	(sp)+, r3
	movl	r3, (r11)+
	movl	8(sp), (r11)+		; EBCS
	movl	52(sp), (r11)+		; MSTAT1
	movl	56(sp), (r11)+		; MSTAT2
	movl	72(sp), (r11)+		; MEAR
	addl2	r3, sp
	subl3	r7, (sp), (r11)+	; PC - instruction
	mtpr	#0, #EHSR
	movl	r8, (sp)
	rei

	.align	4
unexp:	movl	#^xBAD, r9
	halt
