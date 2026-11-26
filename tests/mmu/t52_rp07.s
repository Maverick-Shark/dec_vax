; t52_rp07 - an RP07 on the RH780 (unit 0 with an image, unit 1 without),
; its registers and positioning commands (EK-RP056-MM-01 2.3, 2.4.1.3,
; table 2-1; the RP07's register fields from DEC's TOPS-20 RP07 support):
;
;   - DS after processor initialization: MOL, DPR, DRY (no VV: the pack
;     has not been acknowledged); pack acknowledge sets VV;
;   - read-in preset: VV, DA and DC 0, OF<12:10> (FMT, ECI, HCI) cleared;
;   - a seek: PIP while it runs, CS1<GO>; ATA (and the adapter's SR<16>)
;     when it is over, CC the new cylinder; AS clears ATA;
;   - a register written while the drive positions: RMR, ERR, ATA at once,
;     the seek goes on; a command while ERR is set is ignored; drive clear;
;   - invalid addresses (cylinder 630, sector 50): IAE; an illegal function
;     (041): ILF;
;   - search: ATA when the sector comes under the heads (LA shows it);
;     recalibrate (cylinder 0), offset (OM) and return to centerline, a
;     seek in offset mode returns to centerline;
;   - a seek to the cylinder the heads are on ends at once;
;   - a drive with no image: UNS; unload: off line (MOL clear), PIP until
;     an image is mounted again, which INIT does not change.
;
; Drive register reads return SR<31:16> too: SR<16> (attention) is the
; Massbus ATTN line, there while a drive's ATA is set. Expected values:
; tests/mmu/gen/mk_t52.py.
;@ noref
;@ rtl=18000:00001180,18004:000011C0,18008:00009C00,1800C:00008000,18010:00000000,18014:00000000
;@ rtl=18018:000011C0,1801C:00003140,18020:00000805,18024:000191C0,18028:00010064,1802C:00010001
;@ rtl=18030:000011C0,18034:00000000,18038:0001F140,1803C:00010004,18040:00010000,18044:00010258
;@ rtl=18048:0001D1C0,1804C:0001D1C0,18050:00010258,18054:00000000,18058:000011C0,1805C:0001D1C0
;@ rtl=18060:00010400,18064:00010258,18068:00010400,1806C:00010001,18070:0001D1C0,18074:00010640
;@ rtl=18078:000191C0,1807C:00010000,18080:000191C0,18084:000191C1,18088:000191C0,1808C:000191C0
;@ rtl=18090:0001000A,18094:000191C0,18098:00000180,1809C:00014000,180A0:0001C180,180A4:00010002
;@ rtl=180A8:00000000,180AC:00002100,180B0:00000803,180B4:00002100,180B8:00000000,180BC:00000000
;@ board=skip
;@ disk0=pattern
;@ clocks=8000000
LOG	= ^x18000
SCBB	= ^x11
MBA	= ^x20010000
CR	= MBA+^x04
SR	= MBA+^x08
D0	= MBA+^x400		; unit 0: register n at + 4 * n
D1	= MBA+^x480
CS1	= ^x00
DS	= ^x04
ER1	= ^x08
AS	= ^x10
DA	= ^x14
LA	= ^x1C
OF	= ^x24
DC	= ^x28
CC	= ^x2C

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

; ---------------------------------------- after initialization
	movl	DS(r10), (r11)+		; 00001180: MOL DPR DRY
	movl	#^x13, CS1(r10)		; pack acknowledge (023)
	movl	DS(r10), (r11)+		; 000011C0: VV
	movl	#^x9C00, OF(r10)	; CMO FMT ECI HCI
	movl	OF(r10), (r11)+		; 00009C00
	movl	#^x0101, DA(r10)
	movl	#5, DC(r10)
	movl	#^x11, CS1(r10)		; read-in preset (021)
	movl	OF(r10), (r11)+		; 00008000
	movl	DA(r10), (r11)+		; 0
	movl	DC(r10), (r11)+		; 0
	movl	DS(r10), (r11)+		; 000011C0

; --------------------------------------------------------- a seek
	movl	#100, DC(r10)
	movl	#^x05, CS1(r10)		; seek (05)
	movl	DS(r10), (r11)+		; 00003140: PIP, not DRY
	movl	CS1(r10), (r11)+	; 00000805: DVA, seek, GO
	jsb	wrdy
	movl	DS(r10), (r11)+		; 000191C0: ATA, SR<16>
	movl	CC(r10), (r11)+		; 00010064
	movl	AS(r10), (r11)+		; 00010001
	jsb	clra
	movl	DS(r10), (r11)+		; 000011C0
	movl	@#SR, (r11)+		; 0

; ------------------------- a register written during a seek: RMR
	movl	#600, DC(r10)
	movl	#^x05, CS1(r10)
	movl	#^x0101, DA(r10)	; refused
	movl	DS(r10), (r11)+		; 0001F140: ATA ERR PIP
	movl	ER1(r10), (r11)+	; 00010004: RMR
	movl	DA(r10), (r11)+		; 00010000: not written
	jsb	wrdy			; the seek goes on
	movl	CC(r10), (r11)+		; 00010258
	movl	DS(r10), (r11)+		; 0001D1C0
	clrl	DC(r10)
	movl	#^x05, CS1(r10)		; ERR: ignored
	movl	DS(r10), (r11)+		; 0001D1C0: no PIP
	movl	CC(r10), (r11)+		; 00010258
	movl	#^x09, CS1(r10)		; drive clear (011)
	movl	ER1(r10), (r11)+	; 0: ATA and SR<16> cleared
	movl	#^x10000, @#SR
	movl	DS(r10), (r11)+		; 000011C0

; ------------------------------------------ invalid address, function
	movl	#630, DC(r10)
	movl	#^x05, CS1(r10)
	movl	DS(r10), (r11)+		; 0001D1C0: ATA ERR
	movl	ER1(r10), (r11)+	; 00010400: IAE
	movl	CC(r10), (r11)+		; 00010258: no motion
	movl	#^x09, CS1(r10)
	movl	#^x10000, @#SR
	movl	#600, DC(r10)
	movl	#50, DA(r10)		; sector 50
	movl	#^x05, CS1(r10)
	movl	ER1(r10), (r11)+	; 00010400
	movl	#^x09, CS1(r10)
	movl	#^x10000, @#SR
	movl	#^x21, CS1(r10)		; function 041
	movl	ER1(r10), (r11)+	; 00010001: ILF
	movl	DS(r10), (r11)+		; 0001D1C0
	movl	#^x09, CS1(r10)
	movl	#^x10000, @#SR

; ---------------------------------------------------------- search
	movl	#25, DA(r10)		; DC = CC: no seek
	movl	#^x19, CS1(r10)		; search (031)
	jsb	wrdy
	movl	LA(r10), (r11)+		; 00010640: sector 25 under the heads
	movl	DS(r10), (r11)+		; 000191C0
	jsb	clra
	clrl	DA(r10)

; ---------------------- recalibrate, offset, return to centerline
	movl	#^x07, CS1(r10)		; recalibrate (07)
	jsb	wrdy
	movl	CC(r10), (r11)+		; 00010000
	movl	DS(r10), (r11)+		; 000191C0
	jsb	clra
	movl	#^x0D, CS1(r10)		; offset (015)
	jsb	wrdy
	movl	DS(r10), (r11)+		; 000191C1: OM
	jsb	clra
	movl	#^x0F, CS1(r10)		; return to centerline (017)
	jsb	wrdy
	movl	DS(r10), (r11)+		; 000191C0
	jsb	clra
	movl	#^x0D, CS1(r10)
	jsb	wrdy
	jsb	clra
	movl	#10, DC(r10)
	movl	#^x05, CS1(r10)		; a seek in offset mode
	jsb	wrdy
	movl	DS(r10), (r11)+		; 000191C0: back on centerline
	movl	CC(r10), (r11)+		; 0001000A
	jsb	clra
	movl	#^x05, CS1(r10)		; where the heads are: at once
	jsb	wrdy
	movl	DS(r10), (r11)+		; 000191C0
	jsb	clra

; ----------------------------------------- unit 1: no image
	movl	#D1, r10
	movl	DS(r10), (r11)+		; 00000180
	movl	#^x05, CS1(r10)
	movl	ER1(r10), (r11)+	; 00014000: UNS
	movl	DS(r10), (r11)+		; 0001C180
	movl	AS(r10), (r11)+		; 00010002: unit 1's bit
	movl	#^x09, CS1(r10)
	movl	#^x10000, @#SR
	movl	AS(r10), (r11)+		; 0

; ---------------------------------------------------------- unload
	movl	#D0, r10
	movl	#^x03, CS1(r10)		; unload (03)
	movl	DS(r10), (r11)+		; 00002100: PIP DPR, off line
	movl	CS1(r10), (r11)+	; 00000803: GO
	movl	#1, @#CR		; INIT: still unloaded
	movl	DS(r10), (r11)+		; 00002100
	movl	@#SR, (r11)+		; 0
	movl	r9, (r11)+
	halt

; wait for the drive at R10 to be ready (DRY), at most 10000 polls
wrdy:	movl	#10000, r1
wrdy1:	movl	DS(r10), r0
	bitl	#^x80, r0
	bneq	wrdy2
	sobgtr	r1, wrdy1
	movl	#^xDEAD, r9
	halt
wrdy2:	rsb

; clear the drive's attention (AS; SR<16> goes with it, the SR write
; does nothing)
clra:	movl	#1, AS(r10)
	movl	#^x10000, @#SR
	rsb

	.align	4
unexp:	movl	#^xBAD, r9
	halt
