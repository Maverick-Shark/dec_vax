; t53_mbard - data transfers from an RP07 to memory through the RH780 and
; SBIA 0 (EK-RH780-TD-001 3.5, 3.6.3-3.6.9, 4.4, 4.5.4; EK-RP056-MM-01
; 2.3.2, 2.4.4, 3.4.1.3, 3.9). The disk is the bench's generated image:
; byte 2k of the sector at LBA L is k, byte 2k+1 L ^ L>>8 ^ L>>16 (low
; bytes). A transfer is started by writing the read function to CS1 and
; waited for on SR<31> (DT busy); then SR, VAR, BCR, the drive's registers
; and the memory show what happened:
;
;   - one sector (LBA 0): DT COMP, VAR at the end of the data, both byte
;     counters 0, DA at the next sector, the longword after the buffer
;     untouched;
;   - three sectors from sector 49 of track 0 (a head switch), in three
;     pages mapped apart; DA at track 1 sector 2;
;   - seven bytes to memory byte 3: masked quadword writes, VAR eight
;     bytes past the last byte (TD 3.6.4, note), the Massbus byte counter
;     one past 0 (four words), the SBI byte counter 0;
;   - read header and data: four header words (cylinder with the format
;     bit, sector/track, two key words) before the data;
;   - two sectors from cylinder 1, track 31, sector 49: a mid-transfer
;     seek, DC 2, DA 1;
;   - the disk's last sector with two sectors asked for: AOE, the drive's
;     EXC, DT ABORTED, LST; DC 630;
;   - a page whose map register is not valid: INVMAP, the transfer aborted;
;   - OF<12> (FMT) clear: FER, the transfer aborted with MBEXC;
;   - with CR<2>: the interrupt at the end of the transfer (SCB 160, IPL
;     15), not before.
;
; Expected values: tests/mmu/gen/mk_t53.py.
;@ noref
;@ board=skip
;@ rtl=18000:00002000,18004:00000200,18008:00000000,1800C:00000001,18010:000011C0,18014:00010000
;@ rtl=18018:00030002,1801C:00FF00FE,18020:EEEEEEEE,18024:00002000,18028:00000A00,1802C:00000102
;@ rtl=18030:31013100,18034:31FF31FE,18038:32013200,1803C:33013300,18040:EEEEEEEE,18044:00002000
;@ rtl=18048:00000A12,1804C:00010000,18050:00EEEEEE,18054:02000100,18058:EEEE0300,1805C:EEEEEEEE
;@ rtl=18060:00002000,18064:00001000,18068:00000000,1806C:00010000,18070:00FF00FE,18074:EEEEEEEE
;@ rtl=18078:00002000,1807C:00000002,18080:00000001,18084:00000002,18088:73017300,1808C:8C018C00
;@ rtl=18090:00013080,18094:00010200,18098:0001D5C0,1809C:00010276,180A0:00010000,180A4:11011100
;@ rtl=180A8:00003010,180AC:000015C0,180B0:00013080,180B4:00010010,180B8:80000000,180BC:00002000
;@ rtl=180C0:04150000,180C4:00000160,180C8:00000000
;@ disk0=pattern
;@ clocks=12000000
LOG	= ^x18000
SCBB	= ^x11
IPL	= ^x12
MBA	= ^x20010000
CR	= MBA+^x04
SR	= MBA+^x08
VAR	= MBA+^x0C
BCR	= MBA+^x10
MAP	= MBA+^x800
D0	= MBA+^x400
CS1	= ^x00
DS	= ^x04
ER1	= ^x08
AS	= ^x10
DA	= ^x14
OF	= ^x24
DC	= ^x28
CC	= ^x2C
FMT	= ^x1000
RD	= ^x39			; read data (071)
RDH	= ^x3B			; read header and data (073)
MARK	= ^xEEEEEEEE

	.org	^x1000
start:	movl	#^xE000, sp
	clrl	r0
	movab	unexp+1, r1
scbfill:
	movl	r1, (r0)+
	cmpl	r0, #^x200
	blss	scbfill
	movab	h160+1, @#^x160
	mtpr	#0, #SCBB
	movl	#LOG, r11
	clrl	r9
	movl	#D0, r10
; memory 20000-2FFFF filled with the mark
	movl	#^x20000, r0
fill:	movl	#MARK, (r0)+
	cmpl	r0, #^x30000
	blss	fill
; map registers 0-7: pages 100-107 (20000-20FFF); 8 not valid
	clrl	r0
	movl	#^x80000100, r1
mfill:	movl	r1, @#MAP[r0]
	incl	r1
	aoblss	#8, r0, mfill
	clrl	@#MAP+^x20
	movl	#^x13, CS1(r10)		; pack acknowledge
	movl	#FMT, OF(r10)		; 16-bit format

; --------------------------------------------------- one sector
	clrl	DC(r10)
	clrl	DA(r10)
	clrl	@#VAR
	movl	#-512, @#BCR
	movl	#RD, CS1(r10)
	jsb	wdt
	movl	@#SR, (r11)+		; 00002000: DT COMP
	movl	@#VAR, (r11)+		; 00000200
	movl	@#BCR, (r11)+		; 0
	movl	DA(r10), (r11)+		; 00000001
	movl	DS(r10), (r11)+		; 000011C0
	movl	@#^x20000, (r11)+	; 00010000
	movl	@#^x20004, (r11)+	; 00030002
	movl	@#^x201FC, (r11)+	; 00FF00FE
	movl	@#^x20200, (r11)+	; EEEEEEEE
	movl	#^x2000, @#SR

; ----------------------- three sectors, a head switch, three pages
	movl	#^x80000110, @#MAP+^x08	; page 2: 22000
	movl	#^x80000120, @#MAP+^x0C	; page 3: 24000
	movl	#^x80000130, @#MAP+^x10	; page 4: 26000
	movl	#49, DA(r10)
	movl	#^x400, @#VAR
	movl	#-1536, @#BCR
	movl	#RD, CS1(r10)
	jsb	wdt
	movl	@#SR, (r11)+		; 00002000
	movl	@#VAR, (r11)+		; 00000A00
	movl	DA(r10), (r11)+		; 00000102: track 1, sector 2
	movl	@#^x22000, (r11)+	; 31013100: LBA 49
	movl	@#^x221FC, (r11)+	; 31FF31FE
	movl	@#^x24000, (r11)+	; 32013200: LBA 50
	movl	@#^x26000, (r11)+	; 33013300: LBA 51
	movl	@#^x26200, (r11)+	; EEEEEEEE
	movl	#^x2000, @#SR

; --------------------------- seven bytes to memory byte 3 (page 5)
	movl	#^x80000140, @#MAP+^x14	; 28000
	clrl	DA(r10)
	movl	#^xA03, @#VAR
	movl	#-7, @#BCR
	movl	#RD, CS1(r10)
	jsb	wdt
	movl	@#SR, (r11)+		; 00002000
	movl	@#VAR, (r11)+		; 00000A12
	movl	@#BCR, (r11)+		; 00010000
	movl	@#^x28000, (r11)+	; 00EEEEEE
	movl	@#^x28004, (r11)+	; 02000100
	movl	@#^x28008, (r11)+	; EEEE0300
	movl	@#^x2800C, (r11)+	; EEEEEEEE
	movl	#^x2000, @#SR

; ----------------------------------------- read header and data
	movl	#^x80000150, @#MAP+^x18	; page 6: 2A000
	movl	#^x80000151, @#MAP+^x1C	; page 7: 2A200
	clrl	DA(r10)
	movl	#^xC00, @#VAR
	movl	#-520, @#BCR
	movl	#RDH, CS1(r10)
	jsb	wdt
	movl	@#SR, (r11)+		; 00002000
	movl	@#^x2A000, (r11)+	; 00001000: cylinder 0, FMT
	movl	@#^x2A004, (r11)+	; 0: sector/track 0, key word
	movl	@#^x2A008, (r11)+	; 00010000: the data
	movl	@#^x2A204, (r11)+	; 00FF00FE
	movl	@#^x2A208, (r11)+	; EEEEEEEE
	movl	#^x2000, @#SR

; ------------------------------------------ a mid-transfer seek
	movl	#^x80000160, @#MAP+^x1C	; page 7: 2C000
	movl	#^x80000161, @#MAP+^x20	; page 8: 2C200
	movl	#1, DC(r10)
	movl	#^x1F31, DA(r10)	; track 31, sector 49: LBA 3199
	movl	#^xE00, @#VAR
	movl	#-1024, @#BCR
	movl	#RD, CS1(r10)
	jsb	wdt
	movl	@#SR, (r11)+		; 00002000
	movl	DC(r10), (r11)+		; 00000002
	movl	DA(r10), (r11)+		; 00000001
	movl	CC(r10), (r11)+		; 00000002
	movl	@#^x2C000, (r11)+	; 73017300: LBA 3199
	movl	@#^x2C200, (r11)+	; 8C018C00: LBA 3200
	movl	#^x2000, @#SR

; ------------------------------------------------- the last sector
	movl	#629, DC(r10)
	movl	#^x1F31, DA(r10)	; LBA 1007999
	clrl	@#VAR
	movl	#-1024, @#BCR
	movl	#RD, CS1(r10)
	jsb	wdt
	movl	@#SR, (r11)+		; 00013080: ATTN, DT COMP, ABORT, MBEXC
	movl	ER1(r10), (r11)+	; 00010200: AOE
	movl	DS(r10), (r11)+		; 0001D5C0: ATA ERR LST
	movl	DC(r10), (r11)+		; 00010276: 630
	movl	DA(r10), (r11)+		; 00010000
	movl	@#^x20000, (r11)+	; 11011100: the last sector read
	movl	#^x09, CS1(r10)		; drive clear
	movl	#1, AS(r10)
	movl	#^x13080, @#SR

; --------------------------------------------- a page not valid
	clrl	@#MAP+^x20		; map register 8
	clrl	DC(r10)
	clrl	DA(r10)
	movl	#^x1000, @#VAR
	movl	#-512, @#BCR
	movl	#RD, CS1(r10)
	jsb	wdt
	movl	@#SR, (r11)+		; 00003010: DT COMP, ABORT, INVMAP
	movl	DS(r10), (r11)+		; 000015C0: no drive error (LST
					; stays until INIT)
	movl	#^x3010, @#SR

; --------------------------------------------------- FMT clear: FER
	clrl	OF(r10)
	clrl	@#VAR
	movl	#-512, @#BCR
	movl	#RD, CS1(r10)
	jsb	wdt
	movl	@#SR, (r11)+		; 00013080
	movl	ER1(r10), (r11)+	; 00010010: FER
	movl	#^x09, CS1(r10)
	movl	#1, AS(r10)
	movl	#^x13080, @#SR
	movl	#FMT, OF(r10)

; ------------------------------ the interrupt at the end: SCB 160
	clrl	r6
	movl	#4, @#CR		; IE
	mtpr	#^x14, #IPL
	clrl	@#VAR
	movl	#-512, @#BCR
	movl	#RD, CS1(r10)
	movl	@#SR, (r11)+		; 80000000: busy, no interrupt yet
	movl	#20000, r1
wint:	tstl	r6
	bneq	wint2
	sobgtr	r1, wint
	movl	#^xDEAD, r9
wint2:	mtpr	#^x1F, #IPL
	clrl	@#CR
	movl	r6, (r11)+		; 00000160
	movl	r9, (r11)+		; nothing unexpected
	halt

; wait for the end of the data transfer (SR<31>)
wdt:	movl	#40000, r1
wdt1:	tstl	@#SR
	bgeq	wdt2
	sobgtr	r1, wdt1
	movl	#^xDEAD, r9
	halt
wdt2:	rsb

; the adapter's interrupt: log SR and PSL, clear DT COMP
	.align	4
h160:	movl	@#SR, (r11)+		; 00002000
	movpsl	r2
	bicl3	#^xF, r2, (r11)+	; 04150000
	movl	#^x2000, @#SR
	movl	#^x160, r6
	rei

	.align	4
unexp:	movl	#^xBAD, r9
	halt
