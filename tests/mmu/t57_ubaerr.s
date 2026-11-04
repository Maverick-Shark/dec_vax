; t57_ubaerr - DMA errors of the DW780 (EK-DW780-TD-001 2.9.3, 2.9.4,
; 2.9.9, 3.3), through wraparound as in t56:
;
;   - a page the PAMM does not give to memory (megabyte 30 set to 1F): the
;     MBox aborts the SBI read, which comes back as read data substitute -
;     RDS, FMER, no slave sync; a write completes (the SBIA records the MBox
;     error, the adapter error interrupt it requests is not taken here);
;   - a page beyond the memory separator: the SBIA does not answer; the
;     direct data path tries until the master gives up (no UBA error but
;     the master's slave sync timeout), a buffered data path's quadword
;     write tries for 100 us: CXTMO and the DPR's buffer transfer error,
;     after which that buffer takes nothing until BTE is cleared;
;   - defeat map parity (DCR<29>): a map register byte with an even number
;     of ones fails - the high half at the start of every DMA, the low half
;     only when an SBI transfer is needed: MRPF, and BTE for a buffer write;
;   - defeat data path parity (DCR<28>): a data byte with an even number of
;     ones fails when the buffer sends it to memory (DPPE, BTE) or to the
;     Unibus: the word goes out with PB, which the adapter's master returns
;     to the CPU as read data substitute - a machine check, ABus bad data;
;   - USEFIE: the adapter's request for these errors.
;
; Expected values: tests/mmu/gen/mk_t57.py.
;@ noref
;@ rtl=18000:FFFF0000,18004:00000201,18008:00000001,1800C:00000000,18010:00000201,18014:00000002
;@ rtl=18018:00000000,1801C:00000001,18020:00000000,18024:00000041,18028:00000003,1802C:E0FF0181
;@ rtl=18030:00000001,18034:E0FF0181,18038:A0FF0181,1803C:00000010,18040:00000003,18044:E0FF0181
;@ rtl=18048:00000181,1804C:22221111,18050:44443333,18054:00000000,18058:00000009,1805C:00000000
;@ rtl=18060:00000001,18064:A07F0281,18068:00000009,1806C:00000005,18070:E0FF0281,18074:07070707
;@ rtl=18078:07070707,1807C:00000000,18080:00000021,18084:E0FF0283,18088:00000000,1808C:01010101
;@ rtl=18090:03000101,18094:00000101,18098:00000000,1809C:00000058,180A0:0020C002,180A4:B8000000
;@ rtl=180A8:00184000,180AC:20100A10,180B0:00000000,180B4:00000020,180B8:C0000283,180BC:00000000
;@ rtl=180C0:80000000,180C4:80000000,180C8:00000000,180CC:00000000,180D0:00000000
;@ clocks=8000000
LOG	= ^x18000
SCBB	= ^x11
EHSR	= ^x4A
PAMACC	= ^x40
PAMLOC	= ^x41
SBIA	= ^x20080000
ERRSUM	= SBIA+^x08
SBIER	= SBIA+^x34
UBA	= ^x20006000
UACR	= UBA+^x04
UASR	= UBA+^x08
DCR	= UBA+^x0C
FMER	= UBA+^x10
FUBAR	= UBA+^x14
BRRVR	= UBA+^x30
DPR	= UBA+^x40
MAP	= UBA+^x800
UB	= ^x20100000
IOP	= UB+^x3E000		; the I/O page: nothing there
MEMA	= ^x20000
MEMD	= ^x20600
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
; an adapter init first, whatever ran before (the board suite): 25 ms
	movl	#1, @#UBA+^x04
uw1:	bitl	#^x10000, @#UBA		; CNFGR<16>: the Unibus initialized
	beql	uw1
	movl	#MEMA, r0
clr1:	clrl	(r0)+
	cmpl	r0, #MEMD+^x200
	blss	clr1
	movl	#^x80000100, @#MAP	; 0: DDP, page 100 (the fence)
	movl	#^x8000F000, @#MAP+4	; 1: DDP, megabyte 30
	movl	#^x8020F000, @#MAP+8	; 2: BDP 1, megabyte 30
	movl	#^x80414000, @#MAP+12	; 3: BDP 2, 40 MB: beyond the separator
	movl	#^x80014000, @#MAP+16	; 4: DDP, 40 MB
	movl	#^x80800103, @#MAP+20	; 5: BDP 4, page 103

; ----------------------------- megabyte 30 is not memory: the MBox aborts
	mtpr	#^x01E00000, #PAMLOC
	mtpr	#^x1F, #PAMACC
	movl	#-1, r0
	movw	@#UB+^x200, r0		; DDP read
	movl	r0, (r11)+		; FFFF0000
	movl	@#UASR, (r11)+		; 00000201: RDS, UBSSYNTO
	movl	@#FMER, (r11)+		; 00000001
	movl	#^x7FF, @#UASR
	movw	#1, @#UB+^x202		; DDP write: completes
	jsb	fence
	movl	@#UASR, (r11)+		; 0
	movw	@#UB+^x400, r0		; BDP read, empty: the quadword
	movl	@#UASR, (r11)+		; 00000201
	movl	@#FMER, (r11)+		; 00000002
	movl	@#DPR+4, (r11)+		; 0: no BTE for a read
	movl	#^x7FF, @#UASR
	mtpr	#^x07, #PAMACC		; megabyte 30 is memory again
	movl	#^x7FFF, @#ERRSUM	; the SBIA's MBox errors

; ------------------------------------------- beyond the memory separator
	movw	@#UB+^x800, r0		; DDP: tries until the master gives up
	movl	@#UASR, (r11)+		; 00000001
	movl	#^x7FF, @#UASR
	movw	#^x1111, @#UB+^x600	; BDP 2: three words, no SBI transfer
	movw	#^x2222, @#UB+^x602
	movw	#^x3333, @#UB+^x604
	jsb	fence
	movl	@#UASR, (r11)+		; 0
	movw	#^x4444, @#UB+^x606	; the quadword: 100 us of no response
	jsb	fence			; (the master times out first)
	movl	#500, r1
d01:	sobgtr	r1, d01
	movl	@#UASR, (r11)+		; 00000041: CXTMO, UBSSYNTO
	movl	@#FMER, (r11)+		; 00000003
	movl	@#DPR+8, (r11)+		; E0FF0181: BNE, BTE, DPF, the bytes kept
	movl	#^x7FF, @#UASR
	movw	#^x5555, @#UB+^x600	; BTE: the buffer takes nothing
	jsb	fence
	movl	@#UASR, (r11)+		; 00000001: UBSSYNTO only
	movl	@#DPR+8, (r11)+		; E0FF0181
	movl	#^x7FF, @#UASR
	movl	#^x40000000, @#DPR+8	; clear BTE
	movl	@#DPR+8, (r11)+		; A0FF0181
	movl	#^x40000000, @#MAP+12	; map 3 invalid, then a purge: IVMR
	movl	#^x80000000, @#DPR+8
	movl	@#UASR, (r11)+		; 00000010
	movl	@#FMER, (r11)+		; 00000003
	movl	@#DPR+8, (r11)+		; E0FF0181
	movl	#^x7FF, @#UASR
	movl	#^x80400100, @#MAP+12	; map 3 valid, page 100
	movl	#^x40000000, @#DPR+8
	movl	#^x80000000, @#DPR+8	; the purge writes the quadword
	movl	@#DPR+8, (r11)+		; 00000181
	movl	@#MEMA, (r11)+		; 22221111: UA 600, page 3's quadword 0
	movl	@#MEMA+4, (r11)+	; 44443333
	movl	@#UASR, (r11)+		; 0

; ------------------------------------------------ defeat map parity
	movl	#^x20000000, @#DCR
	movw	@#UB+^x80, r0		; map 0 = 80000100: byte 2 has no ones
	movl	@#UASR, (r11)+		; 00000009: MRPF, UBSSYNTO
	movl	@#FMER, (r11)+		; 0
	movl	#^x7FF, @#UASR
	movw	#^x0707, @#UB+^xA00	; map 5 = 80800103: the high half
	movw	#^x0707, @#UB+^xA02	; passes, byte 0 has two ones: the
	movw	#^x0707, @#UB+^xA04	; words go in
	movb	#7, @#UB+^xA06
	movw	@#IOP, r0		; (the fence for these: no DMA)
	movl	@#UASR, (r11)+		; 00000001: its timeout only
	movl	#^x7FF, @#UASR
	movl	@#DPR+16, (r11)+	; A07F0281: BNE, DPF, 7 bytes, UA A06
	movb	#7, @#UB+^xA07		; the quadword's last byte: the map
	movw	@#IOP, r0		; register's low half for the SBI
	movl	@#UASR, (r11)+		; 00000009: MRPF, UBSSYNTO
	movl	@#FMER, (r11)+		; 00000005
	movl	@#DPR+16, (r11)+	; E0FF0281: BTE, the bytes kept
	movl	#^x7FF, @#UASR
	clrl	@#DCR
	movl	#^x40000000, @#DPR+16
	movl	#^x80000000, @#DPR+16	; purge: written now
	movl	@#MEMD, (r11)+		; 07070707
	movl	@#MEMD+4, (r11)+	; 07070707
	movl	@#UASR, (r11)+		; 0

; ------------------------------------------- defeat data path parity
	movl	#^x10000000, @#DCR
	movw	#^x0101, @#UB+^xA08	; bytes with one 1 each
	movw	#^x0101, @#UB+^xA0A
	movw	#^x0101, @#UB+^xA0C
	movw	#^x0300, @#UB+^xA0E	; 00 no ones, 03 two
	movw	@#IOP, r0
	movl	@#UASR, (r11)+		; 00000021: DPPE, UBSSYNTO
	movl	@#DPR+16, (r11)+	; E0FF0283
	movl	@#MEMD+8, (r11)+	; 0: not written
	movl	#^x7FF, @#UASR
	clrl	@#DCR
	movl	#^x40000000, @#DPR+16
	movl	#^x80000000, @#DPR+16
	movl	@#MEMD+8, (r11)+	; 01010101
	movl	@#MEMD+12, (r11)+	; 03000101
; a read: the word from the buffer with PB, read data substitute
	movl	#^x00FF0101, @#MEMD+^x10
	movl	#^x10000000, @#DCR
	movw	@#UB+^xA10, r0		; from memory: no data path check
	movzwl	r0, (r11)+		; 0101
	movl	@#UASR, (r11)+		; 0
	movab	f01, r7
	movab	n01, r8
	tstl	r8
f01:	movw	@#UB+^xA12, r0		; from the buffer: 00 has no ones
	movl	#^x600D, (r11)+
n01:	movl	@#UASR, (r11)+		; 00000020: DPPE
	movl	@#DPR+16, (r11)+	; C0000283: BNE, BTE, a read
	movl	#^x7FF, @#UASR
	movl	#LOCK, @#ERRSUM
	clrl	@#DCR
	movl	#^x40000000, @#DPR+16
	movl	#^x80000000, @#DPR+16

; --------------------------------------------------- USEFIE
	movl	#^x10, @#UACR
	movl	@#BRRVR, (r11)+		; 0
	movw	@#UB+^x2000, r0		; map 16: invalid
	movl	@#BRRVR, (r11)+		; 80000000
	movl	#8, @#UACR		; SUEFIE alone: the timeout
	movl	@#BRRVR, (r11)+		; 80000000
	movl	#1, @#UASR
	movl	@#BRRVR, (r11)+		; 0: IVMR needs USEFIE
	clrl	@#UACR
	movl	#^x7FF, @#UASR
	movl	@#UASR, (r11)+		; 0
	movl	r9, (r11)+		; nothing unexpected
	halt

; wait for a Unibus write to be over: a Unibus read is busy until then
fence:	movw	@#UB, r0
	rsb

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
