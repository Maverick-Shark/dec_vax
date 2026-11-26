; t51_mba - the RH780 Massbus adapter at TR 8 (EK-RH780-TD-001 chapter 3;
; EK-VAXV2-HB-002, MBA registers and backpanel jumpers):
;
;   - its registers after processor initialization (as INIT leaves them)
;     and what each keeps: VAR <16:0>, BCR loading both counters, DR only
;     in maintenance mode, CR, CSR and SR write 1 to clear;
;   - the map registers (<31> valid, <20:0> PFN) and SMR;
;   - the drive register space, an RP07 at unit 0 with no image: DT, DS,
;     CS1, SN, what DA, DC, OF keep, a register the drive does not have
;     (ILR, ERR and ATA, the attention summary, SR<16>), drive clear;
;   - a drive that is not there (unit 2): NED, the data 0;
;   - references the adapter does not take: a word read and a byte write
;     get an error confirmation, addresses it does not decode (internal
;     register 8, map select 11, SBI address <10>) no response, an SBI
;     timeout - machine checks either way on the 8600 (SBIER<08>, <12>);
;   - the adapter's interrupt (BR5 for the first RH780: IPL 15, SCB 160),
;     with IE, while software has not cleared NED; INIT and UNJAM;
;   - INIT leaves maintenance mode when the bit is written 0 with it (the
;     8600 Diagnostic Supervisor's check of the adapter).
;
; Machine checks log the byte count, EBCS, MSTAT1, MSTAT2, MEAR and PC -
; R7, then EHSR is cleared and the program goes on at R8. DS is compared
; without MOL and VV, which depend on whether an image is mounted (on the
; board). Expected values: tests/mmu/gen/mk_t51.py.
;@ noref
;@ rtl=18000:00000020,18004:00000000,18008:00000000,1800C:00000000,18010:00000000,18014:00000000
;@ rtl=18018:0001FFFF,1801C:FFFFFFFF,18020:FE00FE00,18024:00000000,18028:00000006,1802C:00000008
;@ rtl=18030:FFF00000,18034:FFE00000,18038:00000000,1803C:00000000,18040:00000020,18044:00000000
;@ rtl=18048:80000123,1804C:801FFFFF,18050:001FFFFF,18054:801FFFFF,18058:001FFFFF,1805C:80000123
;@ rtl=18060:00002022,18064:00000180,18068:00000800,1806C:00001001,18070:00000000,18074:00003F7F
;@ rtl=18078:000003FF,1807C:0000DC00,18080:00002022,18084:00000000,18088:00010000,1808C:00010002
;@ rtl=18090:0001C180,18094:00010001,18098:00010000,1809C:00000000,180A0:00000000,180A4:00000180
;@ rtl=180A8:00040000,180AC:00040000,180B0:00040000,180B4:00000000,180B8:00000058,180BC:0020C002
;@ rtl=180C0:B8000000,180C4:00180004,180C8:20010000,180CC:00000000,180D0:00000100,180D4:14800000
;@ rtl=180D8:00000058,180DC:0020C004,180E0:B4000000,180E4:00180004,180E8:20010004,180EC:00000000
;@ rtl=180F0:00000100,180F4:D4800000,180F8:00000000,180FC:00000058,18100:0020C002,18104:B8000000
;@ rtl=18108:00180004,1810C:20010020,18110:00000000,18114:00001000,18118:00000058,1811C:0020C002
;@ rtl=18120:B8000000,18124:00180004,18128:20010C00,1812C:00000000,18130:00001000,18134:00000058
;@ rtl=18138:0020C004,1813C:B4000000,18140:00180004,18144:20011000,18148:00000000,1814C:00001000
;@ rtl=18150:000000A1,18154:00000160,18158:04150000,1815C:00040000,18160:000000A2,18164:00000000
;@ rtl=18168:00000002,1816C:00000000,18170:0000000C,18174:00000000,18178:00002022,1817C:00000000
;@ mask=18064:FFFFEFBF,18090:FFFFEFBF,180A4:FFFFEFBF
;@ clocks=4000000
LOG	= ^x18000
SCBB	= ^x11
IPL	= ^x12
EHSR	= ^x4A
SBIA	= ^x20080000
ERRSUM	= SBIA+^x08
SBIER	= SBIA+^x34
UNJAM	= SBIA+^x48
MBA	= ^x20010000
CSR	= MBA
CR	= MBA+^x04
SR	= MBA+^x08
VAR	= MBA+^x0C
BCR	= MBA+^x10
DR	= MBA+^x14
SMR	= MBA+^x18
DRV0	= MBA+^x400		; drive 0: register n at + 4 * n
DRV2	= MBA+^x500
MAP	= MBA+^x800
LOCK	= ^x00800000
TMO	= ^x1000

	.org	^x1000
start:	movl	#^xE000, sp		; interrupt stack (PSL<IS> is set)
	clrl	r0
	movab	unexp+1, r1
scbfill:
	movl	r1, (r0)+
	cmpl	r0, #^x200
	blss	scbfill
	movab	mchk_h+1, @#^x04
	movab	h160+1, @#^x160		; TR 8 at IPL 15
	mtpr	#0, #SCBB
	movl	#LOG, r11
	clrl	r9

; ------------------------------------------- after initialization
	movl	@#CSR, (r11)+		; 00000020: adapter code
	movl	@#CR, (r11)+		; 0
	movl	@#SR, (r11)+		; 0
	movl	@#VAR, (r11)+		; 0
	movl	@#BCR, (r11)+		; 0
	movl	@#DR, (r11)+		; 0

; --------------------------------------------------- what each keeps
	movl	#-1, @#VAR
	movl	@#VAR, (r11)+		; 0001FFFF
	clrl	@#VAR
	movl	#-1, @#BCR		; both counters
	movl	@#BCR, (r11)+		; FFFFFFFF
	movl	#^xABCDFE00, @#BCR
	movl	@#BCR, (r11)+		; FE00FE00
	clrl	@#BCR
	movl	#-1, @#DR		; not in maintenance mode: ignored
	movl	@#DR, (r11)+		; 0
	movl	#6, @#CR		; IE, ABORT
	movl	@#CR, (r11)+		; 00000006
	movl	#8, @#CR		; maintenance mode
	movl	@#CR, (r11)+		; 00000008
	movl	#-1, @#DR		; <31:21>; <20> FAIL with MM
	movl	@#DR, (r11)+		; FFF00000
	clrl	@#CR
	movl	@#DR, (r11)+		; FFE00000
	movl	#1, @#CR		; INIT
	movl	@#DR, (r11)+		; 0
	movl	@#CR, (r11)+		; 0
	movl	#-1, @#CSR		; PU: nothing to clear
	movl	@#CSR, (r11)+		; 00000020
	movl	#-1, @#SR
	movl	@#SR, (r11)+		; 0

; ---------------------------------------------------- map registers
	movl	#^x80000123, @#MAP
	movl	#-1, @#MAP+4
	movl	#^x7FFFFFFF, @#MAP+^x3FC
	movl	@#MAP, (r11)+		; 80000123
	movl	@#MAP+4, (r11)+		; 801FFFFF
	movl	@#MAP+^x3FC, (r11)+	; 001FFFFF
	movl	#^x200, @#VAR		; SMR: the map register VAR<16:9> selects
	movl	@#SMR, (r11)+		; 801FFFFF
	movl	#^x1FFFF, @#VAR
	movl	@#SMR, (r11)+		; 001FFFFF
	clrl	@#VAR
	movl	@#SMR, (r11)+		; 80000123

; ------------------------------- drive registers: unit 0, no image
	movl	@#DRV0+^x18, (r11)+	; DT 00002022 (020042)
	movl	@#DRV0+^x04, (r11)+	; DS 00000180: DPR, DRY
	movl	@#DRV0, (r11)+		; CS1 00000800: DVA
	movl	@#DRV0+^x20, (r11)+	; SN 00001001
	movl	@#DRV0+^x10, (r11)+	; AS 0
	movl	#^xFFFF, @#DRV0+^x14	; DA: <13:8> track, <6:0> sector
	movl	@#DRV0+^x14, (r11)+	; 00003F7F
	movl	#^xFFFF, @#DRV0+^x28	; DC <9:0>
	movl	@#DRV0+^x28, (r11)+	; 000003FF
	movl	#^xFFFF, @#DRV0+^x24	; OF <15,14,12:10>
	movl	@#DRV0+^x24, (r11)+	; 0000DC00
	movl	#^xFFFF, @#DRV0+^x18	; DT: read only, no error
	movl	@#DRV0+^x18, (r11)+	; 00002022
	movl	@#DRV0+^x08, (r11)+	; ER1 0
	clrl	@#DRV0+^x14
	clrl	@#DRV0+^x28
	clrl	@#DRV0+^x24
; a register the drive does not have: ILR, then ERR and ATA
	movl	@#DRV0+^x40, (r11)+	; 00010000: data 0, SR<16> attention
	movl	@#DRV0+^x08, (r11)+	; ER1 00010002: ILR
	movl	@#DRV0+^x04, (r11)+	; DS 0001C180: ATA ERR DPR DRY
	movl	@#DRV0+^x10, (r11)+	; AS 00010001
	movl	@#SR, (r11)+		; 00010000
	movl	#^x09, @#DRV0		; drive clear (011)
	movl	@#DRV0+^x08, (r11)+	; ER1 0: ATA cleared, SR<16> (ATTN) too
	movl	#^x10000, @#SR		; (writing SR<16> does nothing)
	movl	@#SR, (r11)+		; 0
	movl	@#DRV0+^x04, (r11)+	; DS 00000180

; ---------------------------------------- a drive that is not there
	movl	@#DRV2+^x18, (r11)+	; 00040000: NED, data 0
	movl	@#SR, (r11)+		; 00040000
	movl	#^x40000, @#SR
	movl	#1, @#DRV2		; a write: NED too
	movl	@#SR, (r11)+		; 00040000
	movl	#^x40000, @#SR
	movl	@#SR, (r11)+		; 0

; --------------------------------- references the adapter does not take
; a word read: error confirmation
	movab	f01, r7
	movab	n01, r8
	tstl	r8
f01:	movw	@#CSR, r0
	movl	#^x600D, (r11)+
n01:	movl	@#SBIER, (r11)+		; 00000100: error confirmation
	movl	@#ERRSUM, (r11)+	; 14800000: read, even word, lock
	movl	#TMO, @#SBIER
	movl	#LOCK, @#ERRSUM
; a byte write
	movab	f02, r7
	movab	n02, r8
	tstl	r8
f02:	movb	#1, @#CR
	movl	#^x600D, (r11)+
n02:	movl	@#SBIER, (r11)+		; 00000100
	movl	@#ERRSUM, (r11)+	; D4800000: write, mask 0001
	movl	#TMO, @#SBIER
	movl	#LOCK, @#ERRSUM
	movl	@#CR, (r11)+		; 0: not written
; internal register 8: no response
	movab	f03, r7
	movab	n03, r8
	tstl	r8
f03:	movl	@#MBA+^x20, r0
	movl	#^x600D, (r11)+
n03:	movl	@#SBIER, (r11)+		; 00001000: timeout, no response
	movl	#TMO, @#SBIER
	movl	#LOCK, @#ERRSUM
; register/map select 11
	movab	f04, r7
	movab	n04, r8
	tstl	r8
f04:	movl	@#MBA+^xC00, r0
	movl	#^x600D, (r11)+
n04:	movl	@#SBIER, (r11)+		; 00001000
	movl	#TMO, @#SBIER
	movl	#LOCK, @#ERRSUM
; SBI address <10> set
	movab	f05, r7
	movab	n05, r8
	tstl	r8
f05:	movl	#5, @#MBA+^x1000
	movl	#^x600D, (r11)+
n05:	movl	@#SBIER, (r11)+		; 00001000
	movl	#TMO, @#SBIER
	movl	#LOCK, @#ERRSUM

; ------------------------------------- the interrupt: BR5, SCB 160
	movl	@#DRV2+^x18, r0		; NED
	movl	#4, @#CR		; IE: the request is up
	mtpr	#^x15, #IPL		; not at 15
	movl	#^xA1, (r11)+
	mtpr	#^x14, #IPL		; taken
	movl	#^xA2, (r11)+
	mtpr	#^x1F, #IPL
; INIT clears IE, UNJAM clears ABORT
	movl	#4, @#CR
	movl	#1, @#CR
	movl	@#CR, (r11)+		; 0
	movl	#2, @#CR
	movl	@#CR, (r11)+		; 00000002
	movl	#1, @#UNJAM
	movl	@#CR, (r11)+		; 0
; maintenance mode left by INIT, as the 8600 Diagnostic Supervisor checks
; the adapter: INIT, MM and IE, simulate ATTN, INIT (CR = 1)
	movl	#1, @#CR
	movl	#^xC, @#CR
	movl	@#CR, (r11)+		; 0000000C
	bisl2	#^x1000000, @#DR
	movl	#1, @#CR		; INIT writes MM too: 0
	movl	@#CR, (r11)+		; 0
	movl	@#DRV0+^x18, (r11)+	; the drive answers again: DT 00002022
	movl	r9, (r11)+		; nothing unexpected
	halt

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

; the adapter's interrupt: log, clear NED, return
	.align	4
h160:	movl	#^x160, (r11)+
	movpsl	r2
	bicl3	#^xF, r2, (r11)+	; 04150000: IPL 15
	movl	@#SR, (r11)+		; 00040000
	movl	#^x40000, @#SR		; the request goes down
	rei

	.align	4
unexp:	movl	#^xBAD, r9
	halt
