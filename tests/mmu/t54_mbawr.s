; t54_mbawr - writes, write checks and the RH780's errors (EK-RH780-TD-001
; 3.3, 3.5, 3.6.2-3.6.5, 4.4.8, 4.5.2, 4.5.4; EK-RP056-MM-01 2.3.2, 2.4.4,
; 3.12.1). Unit 0 has the bench's generated disk, unit 1 the same read
; only:
;
;   - two sectors written from memory, read back elsewhere and compared;
;   - write check of them: no error; one byte changed in memory, in the
;     upper byte of a Massbus word, then in a lower one: WCK UP / WCK LWR,
;     the transfer aborted;
;   - three bytes written: the sector completed with zeros; five bytes from
;     memory byte 6 (unaligned): the right bytes;
;   - write header and data: the four header words are not kept, the data
;     is; write check header and data against memory holding the header
;     the drive gives (cylinder with FMT, sector/track, two zeros);
;   - VAR, BCR and a map register written during a transfer, and a second
;     data transfer command: program error, nothing written or sent;
;   - a data transfer command to a drive that is not there: NED, then no
;     OCC: missed transfer; one the drive rejects (function 075, illegal):
;     ILF and ATA, missed transfer;
;   - a write to the read only unit 1: WLE, WRL, missed transfer;
;   - CR<1> (abort) during a transfer: DT ABORTED.
;
; Expected values: tests/mmu/gen/mk_t54.py.
;@ noref
;@ board=skip
;@ rtl=18000:00002000,18004:00000400,18008:00000000,1800C:00000202,18010:00002000,18014:5A000000
;@ rtl=18018:5AFFFFFF,1801C:00000000,18020:00002000,18024:00003400,18028:00003200,1802C:000011C0
;@ rtl=18030:00002000,18034:00332211,18038:00000000,1803C:00000000,18040:00002000,18044:00000013
;@ rtl=18048:02025A01,1804C:00000002,18050:00002000,18054:5A020202,18058:5A818181,1805C:00002000
;@ rtl=18060:00082000,18064:00001C00,18068:00000000,1806C:8000010C,18070:00010000,18074:01010100
;@ rtl=18078:00043100,1807C:00013100,18080:00010001,18084:00013100,18088:00010800,1808C:0001D9C0
;@ rtl=18090:00003000,18094:000011C0,18098:00000000
;@ disk0=pattern
;@ disk1=pattern:ro
;@ clocks=16000000
LOG	= ^x18000
SCBB	= ^x11
MBA	= ^x20010000
CR	= MBA+^x04
SR	= MBA+^x08
VAR	= MBA+^x0C
BCR	= MBA+^x10
MAP	= MBA+^x800
D0	= MBA+^x400
D1	= MBA+^x480
D3	= MBA+^x580
CS1	= ^x00
DS	= ^x04
ER1	= ^x08
AS	= ^x10
DA	= ^x14
OF	= ^x24
DC	= ^x28
FMT	= ^x1000
RD	= ^x39			; read data (071)
WR	= ^x31			; write data (061)
WRH	= ^x33			; write header and data (063)
WCK	= ^x29			; write check data (051)
WCKH	= ^x2B			; write check header and data (053)
MARK	= ^xEEEEEEEE

	.org	^x1000
start:	movl	#^xE000, sp
	clrl	r0
	movab	unexp+1, r1
scbfill:
	movl	r1, (r0)+
	cmpl	r0, #^x200
	blss	scbfill
	mtpr	#0, #SCBB
	movl	#LOG, r11
	clrl	r9
	movl	#D0, r10
; 20000-203FF: 5A000000 + j * 00010101; 20400-2FFFF: the mark
	movl	#^x20000, r0
	movl	#^x5A000000, r1
fill1:	movl	r1, (r0)+
	addl2	#^x00010101, r1
	cmpl	r0, #^x20400
	blss	fill1
fill2:	movl	#MARK, (r0)+
	cmpl	r0, #^x30000
	blss	fill2
; map registers 0-15: pages 100-10F (20000-21FFF)
	clrl	r0
	movl	#^x80000100, r1
mfill:	movl	r1, @#MAP[r0]
	incl	r1
	aoblss	#16, r0, mfill
	movl	#^x13, CS1(r10)		; pack acknowledge
	movl	#FMT, OF(r10)
	movl	#^x13, @#D1		; unit 1 too
	movl	#FMT, @#D1+OF

; ---------------------------------- two sectors written, read back
	clrl	DC(r10)
	movl	#^x0200, DA(r10)	; track 2, sector 0: LBA 100
	clrl	@#VAR
	movl	#-1024, @#BCR
	movl	#WR, CS1(r10)
	jsb	wdt
	movl	@#SR, (r11)+		; 00002000
	movl	@#VAR, (r11)+		; 00000400
	movl	@#BCR, (r11)+		; 0
	movl	DA(r10), (r11)+		; 00000202
	movl	#^x2000, @#SR
	movl	#^x0200, DA(r10)
	movl	#^x800, @#VAR		; pages 4, 5: 20800
	movl	#-1024, @#BCR
	movl	#RD, CS1(r10)
	jsb	wdt
	movl	@#SR, (r11)+		; 00002000
	movl	#^x2000, @#SR
	movl	@#^x20800, (r11)+	; 5A000000
	movl	@#^x20BFC, (r11)+	; 5AFFFFFF
	clrl	r5			; differences
	clrl	r0
cmp1:	cmpl	@#^x20000[r0], @#^x20800[r0]
	beql	cmp2
	incl	r5
cmp2:	aoblss	#256, r0, cmp1
	movl	r5, (r11)+		; 0

; ---------------------------------------------------- write checks
	movl	#^x0200, DA(r10)
	clrl	@#VAR
	movl	#-1024, @#BCR
	movl	#WCK, CS1(r10)
	jsb	wdt
	movl	@#SR, (r11)+		; 00002000: they match
	movl	#^x2000, @#SR
	xorb2	#1, @#^x20211		; sector 101, word 8, upper byte
	movl	#^x0200, DA(r10)
	clrl	@#VAR
	movl	#-1024, @#BCR
	movl	#WCK, CS1(r10)
	jsb	wdt
	movl	@#SR, (r11)+		; 00003400: WCK UP, aborted
	movl	#^x3400, @#SR
	xorb2	#1, @#^x20211
	xorb2	#1, @#^x20010		; sector 100, word 8, lower byte
	movl	#^x0200, DA(r10)
	clrl	@#VAR
	movl	#-1024, @#BCR
	movl	#WCK, CS1(r10)
	jsb	wdt
	movl	@#SR, (r11)+		; 00003200: WCK LWR
	movl	#^x3200, @#SR
	xorb2	#1, @#^x20010
	movl	DS(r10), (r11)+		; 000011C0: no drive error

; ---------------------------- three bytes; five from memory byte 6
	movl	#^x44332211, @#^x21000	; page 8
	movl	#^x0202, DA(r10)	; LBA 102
	movl	#^x1000, @#VAR
	movl	#-3, @#BCR
	movl	#WR, CS1(r10)
	jsb	wdt
	movl	@#SR, (r11)+		; 00002000
	movl	#^x2000, @#SR
	movl	#^x0202, DA(r10)
	movl	#^x1200, @#VAR		; page 9: 21200
	movl	#-512, @#BCR
	movl	#RD, CS1(r10)
	jsb	wdt
	movl	#^x2000, @#SR
	movl	@#^x21200, (r11)+	; 00332211: then zeros
	movl	@#^x21204, (r11)+	; 0
	movl	@#^x213FC, (r11)+	; 0
	movl	#^x0203, DA(r10)	; LBA 103
	movl	#^x6, @#VAR		; bytes 20006-2000A
	movl	#-5, @#BCR
	movl	#WR, CS1(r10)
	jsb	wdt
	movl	@#SR, (r11)+		; 00002000
	movl	@#VAR, (r11)+		; 00000013
	movl	#^x2000, @#SR
	movl	#^x0203, DA(r10)
	movl	#^x1200, @#VAR
	movl	#-512, @#BCR
	movl	#RD, CS1(r10)
	jsb	wdt
	movl	#^x2000, @#SR
	movl	@#^x21200, (r11)+	; 02025A01: bytes 20006-2000A
	movl	@#^x21204, (r11)+	; 00000002

; ------------------------------------------ the header commands
	movl	#^x0204, DA(r10)	; LBA 104
	clrl	@#VAR			; 8 header bytes, then 512 of data
	movl	#-520, @#BCR
	movl	#WRH, CS1(r10)
	jsb	wdt
	movl	@#SR, (r11)+		; 00002000
	movl	#^x2000, @#SR
	movl	#^x0204, DA(r10)
	movl	#^x1200, @#VAR
	movl	#-512, @#BCR
	movl	#RD, CS1(r10)
	jsb	wdt
	movl	#^x2000, @#SR
	movl	@#^x21200, (r11)+	; 5A020202: memory from byte 8
	movl	@#^x213FC, (r11)+	; 5A818181
; memory with the header the drive gives, then the data
	movl	#^x02041000, @#^x21400	; page 10: cylinder 0 FMT; track 2 sector 4
	clrl	@#^x21404		; key words
	movc3	#512, @#^x21200, @#^x21408
	movl	#^x0204, DA(r10)
	movl	#^x1400, @#VAR
	movl	#-520, @#BCR
	movl	#WCKH, CS1(r10)
	jsb	wdt
	movl	@#SR, (r11)+		; 00002000: header and data match
	movl	#^x2000, @#SR

; ------------------------------------- program errors in a transfer
	clrl	DA(r10)
	movl	#^x1800, @#VAR		; pages 12, 13: 21800
	movl	#-1024, @#BCR
	movl	#RD, CS1(r10)
	movl	#^x1234, @#VAR		; refused
	movl	#-4, @#BCR		; refused
	movl	#^x80000001, @#MAP+^x30	; refused
	movl	#RD, CS1(r10)		; refused, not sent
	jsb	wdt
	movl	@#SR, (r11)+		; 00082000: PGE, DT COMP
	movl	@#VAR, (r11)+		; 00001C00
	movl	@#BCR, (r11)+		; 0
	movl	@#MAP+^x30, (r11)+	; 8000010C
	movl	@#^x21800, (r11)+	; 00010000: LBA 0
	movl	@#^x21A00, (r11)+	; 01010100: LBA 1
	movl	#^x82000, @#SR

; ------------------------------------------------ missed transfers
	clrl	@#VAR
	movl	#-512, @#BCR
	movl	#RD, @#D3		; unit 3: not there
	jsb	wdt
	movl	@#SR, (r11)+		; 00043100: NED, DT COMP, ABORT, MXF
	movl	#^x43100, @#SR
	clrl	@#VAR
	movl	#-512, @#BCR
	movl	#^x3D, CS1(r10)		; function 075: illegal
	jsb	wdt
	movl	@#SR, (r11)+		; 00013100: ATTN, MXF
	movl	ER1(r10), (r11)+	; 00010001: ILF
	movl	#^x09, CS1(r10)
	movl	#1, AS(r10)
	movl	#^x13100, @#SR
	clrl	@#D1+DA			; unit 1: read only
	clrl	@#D1+DC
	clrl	@#VAR
	movl	#-512, @#BCR
	movl	#WR, @#D1
	jsb	wdt
	movl	@#SR, (r11)+		; 00013100
	movl	@#D1+ER1, (r11)+	; 00010800: WLE
	movl	@#D1+DS, (r11)+		; 0001D9C0: WRL
	movl	#^x09, @#D1
	movl	#2, @#D1+AS
	movl	#^x13100, @#SR

; ---------------------------------------------------- CR<1> abort
	clrl	DA(r10)
	movl	#600, DC(r10)		; a long seek first
	clrl	@#VAR
	movl	#-2048, @#BCR
	movl	#RD, CS1(r10)
	movl	#2, @#CR		; abort
	jsb	wdt
	movl	@#SR, (r11)+		; 00003000: DT COMP, DT ABORTED
	clrl	@#CR
	movl	#^x3000, @#SR
	movl	DS(r10), (r11)+		; 000011C0
	movl	r9, (r11)+
	halt

; wait for the end of the data transfer (SR<31>)
wdt:	movl	#60000, r1
wdt1:	tstl	@#SR
	bgeq	wdt2
	sobgtr	r1, wdt1
	movl	#^xDEAD, r9
	halt
wdt2:	rsb

	.align	4
unexp:	movl	#^xBAD, r9
	halt
