; t55_uba - the DW780 Unibus adapter at TR 3 (EK-DW780-TD-001 2.5, 2.7,
; 2.9, 3.4.7.2, 3.6; EK-VAXV2-HB-002, UBA registers and backpanel jumpers):
;
;   - its registers after processor initialization (an adapter init long
;     finished: CNFGR 00010028, DCR with MIC OK) and what each keeps: CR
;     <30:26,6:2>, DCR <31:28> (<23:0> is CNFGR), BRSVR <15:0>, the map
;     registers' 32 bits, DPR (purge and BTE of an idle buffer);
;   - references the adapter does not take: a write to FMER, FUBAR or a
;     BRRVR and a longword or an odd word in Unibus space get an error
;     confirmation; reserved offsets (080, map register 496, 1000) no
;     response - machine checks on the 8600 (SBIER<08>, <12>);
;   - the Unibus I/O page with nothing on the Unibus: a read returns 0
;     after the slave sync timeout (UBSSYNTO, FUBAR the address <17:2>,
;     locked), a write is acknowledged at once and times out afterwards;
;   - the adapter's own interrupt request on BR4: BRRVR4 <31> with SUEFIE
;     or CNFIE, the interrupt at IPL 14 through SCB 10C (100 + 4 * TR).
;
; Machine checks log the byte count, EBCS, MSTAT1, MSTAT2, MEAR and PC -
; R7, then EHSR is cleared and the program goes on at R8. Expected values:
; tests/mmu/gen/mk_t55.py.
;@ noref
;@ rtl=18000:00010028,18004:00000000,18008:00000000,1800C:08010028,18010:00000000,18014:00000000
;@ rtl=18018:00000000,1801C:00000000,18020:00000000,18024:00000000,18028:00000000,1802C:00000000
;@ rtl=18030:00000000,18034:00000000,18038:00000000,1803C:00000000,18040:00000000,18044:00000000
;@ rtl=18048:7C00007C,1804C:80000000,18050:00000000,18054:00000000,18058:00000000,1805C:F8010028
;@ rtl=18060:08010028,18064:0000ABCD,18068:00005555,1806C:FFFFFFFF,18070:12345678,18074:00000000
;@ rtl=18078:00000000,1807C:00000000,18080:00000028,18084:00000001,18088:00000058,1808C:0020C004
;@ rtl=18090:B4000000,18094:00180004,18098:20006010,1809C:00000000,180A0:00000100,180A4:00000058
;@ rtl=180A8:0020C004,180AC:B4000000,180B0:00180004,180B4:2000601C,180B8:00000000,180BC:00000100
;@ rtl=180C0:00000058,180C4:0020C004,180C8:B4000000,180CC:00180004,180D0:20006034,180D4:00000000
;@ rtl=180D8:00000100,180DC:00000058,180E0:0020C002,180E4:B8000000,180E8:00180004,180EC:20006080
;@ rtl=180F0:00000000,180F4:00001000,180F8:00000058,180FC:0020C002,18100:B8000000,18104:00180004
;@ rtl=18108:20006FC0,1810C:00000000,18110:00001000,18114:00000058,18118:0020C004,1811C:B4000000
;@ rtl=18120:00180004,18124:20007000,18128:00000000,1812C:00001000,18130:00000058,18134:0020C002
;@ rtl=18138:B8000000,1813C:00180004,18140:2013E000,18144:00000000,18148:00000100,1814C:00000058
;@ rtl=18150:0020C004,18154:B4000000,18158:00180004,1815C:2013E000,18160:00000000,18164:00000100
;@ rtl=18168:00000000,1816C:FFFF0000,18170:00000001,18174:0000F800,18178:0000F800,1817C:00000000
;@ rtl=18180:0000F800,18184:00000000,18188:00000001,1818C:0000FFFF,18190:00000000,18194:0000F800
;@ rtl=18198:00000000,1819C:80000000,181A0:00000000,181A4:00000000,181A8:000000A1,181AC:0000010C
;@ rtl=181B0:04140000,181B4:80000000,181B8:00000001,181BC:000000A2,181C0:80000000,181C4:00000028
;@ rtl=181C8:00000000,181CC:08000028,181D0:00000000
;@ clocks=6000000
LOG	= ^x18000
SCBB	= ^x11
IPL	= ^x12
EHSR	= ^x4A
SBIA	= ^x20080000
ERRSUM	= SBIA+^x08
SBIER	= SBIA+^x34
UBA	= ^x20006000
CNFGR	= UBA
UACR	= UBA+^x04
UASR	= UBA+^x08
DCR	= UBA+^x0C
FMER	= UBA+^x10
FUBAR	= UBA+^x14
BRSVR	= UBA+^x20
BRRVR	= UBA+^x30
DPR	= UBA+^x40
MAP	= UBA+^x800
UB	= ^x20100000		; Unibus 0
IOP	= UB+^x3E000		; the I/O page, 760000
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
	movab	h10c+1, @#^x10C		; TR 3 at IPL 14
	mtpr	#0, #SCBB
	movl	#LOG, r11
	clrl	r9

; ------------------------------------------- after initialization
	movl	@#CNFGR, (r11)+		; 00010028: UBIC, adapter code 28
	movl	@#UACR, (r11)+		; 0
	movl	@#UASR, (r11)+		; 0
	movl	@#DCR, (r11)+		; 08010028: MIC OK, CNFGR<23:0>
	movl	@#FMER, (r11)+		; 0
	movl	@#FUBAR, (r11)+		; 0
	movl	@#UBA+^x18, (r11)+	; FMER again
	movl	@#UBA+^x1C, (r11)+	; FUBAR again
	movl	@#BRSVR, (r11)+		; 0
	movl	@#BRRVR, (r11)+		; BRRVR4-7: 0
	movl	@#BRRVR+4, (r11)+
	movl	@#BRRVR+8, (r11)+
	movl	@#BRRVR+12, (r11)+
	movl	@#DPR, (r11)+		; DPR0, 1, 15: 0
	movl	@#DPR+4, (r11)+
	movl	@#DPR+60, (r11)+
	movl	@#MAP, (r11)+		; map registers 0, 495: 0
	movl	@#MAP+^x7BC, (r11)+

; --------------------------------------------------- what each keeps
	movl	#^xFFFFFFFC, @#UACR	; everything but UPF and adapter init
	movl	@#UACR, (r11)+		; 7C00007C
	movl	@#BRRVR, (r11)+		; 80000000: CNFIE and UBIC, on BR4 only
	movl	@#BRRVR+4, (r11)+	; 0
	clrl	@#UACR
	movl	@#BRRVR, (r11)+		; 0
	movl	#-1, @#UASR		; nothing to clear
	movl	@#UASR, (r11)+		; 0
	movl	#-1, @#DCR
	movl	@#DCR, (r11)+		; F8010028
	clrl	@#DCR
	movl	@#DCR, (r11)+		; 08010028
	movl	#^x1234ABCD, @#BRSVR
	movl	#^xFFFF5555, @#BRSVR+12
	movl	@#BRSVR, (r11)+		; 0000ABCD
	movl	@#BRSVR+12, (r11)+	; 00005555
	movl	#-1, @#MAP
	movl	#^x12345678, @#MAP+^x7BC
	movl	@#MAP, (r11)+		; FFFFFFFF
	movl	@#MAP+^x7BC, (r11)+	; 12345678
	clrl	@#MAP
	clrl	@#MAP+^x7BC
	movl	#^x40000000, @#DPR+4	; BTE: nothing to clear
	movl	@#DPR+4, (r11)+		; 0
	movl	#^x80000000, @#DPR+4	; purge an empty buffer
	movl	@#DPR+4, (r11)+		; 0
	movl	#-1, @#DPR		; DPR0: the direct data path
	movl	@#DPR, (r11)+		; 0
	movw	@#CNFGR, r0		; a word read: the longword
	movzwl	r0, (r11)+		; 00000028
	movw	@#CNFGR+2, r0
	movzwl	r0, (r11)+		; 00000001

; --------------------------------- references the adapter does not take
; a write to FMER: error confirmation
	movab	f01, r7
	movab	n01, r8
	tstl	r8
f01:	movl	#5, @#FMER
	movl	#^x600D, (r11)+
n01:	movl	@#SBIER, (r11)+		; 00000100: error confirmation
	movl	#TMO, @#SBIER
	movl	#LOCK, @#ERRSUM
; FUBAR (the second address)
	movab	f02, r7
	movab	n02, r8
	tstl	r8
f02:	movl	#5, @#UBA+^x1C
	movl	#^x600D, (r11)+
n02:	movl	@#SBIER, (r11)+		; 00000100
	movl	#TMO, @#SBIER
	movl	#LOCK, @#ERRSUM
; BRRVR5
	movab	f03, r7
	movab	n03, r8
	tstl	r8
f03:	movl	#5, @#BRRVR+4
	movl	#^x600D, (r11)+
n03:	movl	@#SBIER, (r11)+		; 00000100
	movl	#TMO, @#SBIER
	movl	#LOCK, @#ERRSUM
; offset 080, reserved: no response
	movab	f04, r7
	movab	n04, r8
	tstl	r8
f04:	movl	@#UBA+^x80, r0
	movl	#^x600D, (r11)+
n04:	movl	@#SBIER, (r11)+		; 00001000: timeout, no response
	movl	#TMO, @#SBIER
	movl	#LOCK, @#ERRSUM
; map register 496 (FC0), reserved
	movab	f05, r7
	movab	n05, r8
	tstl	r8
f05:	movl	@#MAP+^x7C0, r0
	movl	#^x600D, (r11)+
n05:	movl	@#SBIER, (r11)+		; 00001000
	movl	#TMO, @#SBIER
	movl	#LOCK, @#ERRSUM
; the upper half of the nexus space (1000)
	movab	f06, r7
	movab	n06, r8
	tstl	r8
f06:	movl	#5, @#UBA+^x1000
	movl	#^x600D, (r11)+
n06:	movl	@#SBIER, (r11)+		; 00001000
	movl	#TMO, @#SBIER
	movl	#LOCK, @#ERRSUM
; a longword in Unibus space
	movab	f07, r7
	movab	n07, r8
	tstl	r8
f07:	movl	@#IOP, r0
	movl	#^x600D, (r11)+
n07:	movl	@#SBIER, (r11)+		; 00000100
	movl	#TMO, @#SBIER
	movl	#LOCK, @#ERRSUM
; a word at an odd address: mask 0110
	movab	f08, r7
	movab	n08, r8
	tstl	r8
f08:	movw	#5, @#IOP+1
	movl	#^x600D, (r11)+
n08:	movl	@#SBIER, (r11)+		; 00000100
	movl	#TMO, @#SBIER
	movl	#LOCK, @#ERRSUM
	movl	@#UASR, (r11)+		; 0: none of these reached the Unibus

; ------------------------------- the I/O page with no device on it
	movl	#-1, r0
	movw	@#IOP, r0		; 760000: the slave sync timeout
	movl	r0, (r11)+		; FFFF0000: the word read is 0
	movl	@#UASR, (r11)+		; 00000001: UBSSYNTO
	movl	@#FUBAR, (r11)+		; 0000F800: UA<17:2>
	movw	@#IOP+^x100, r0		; another one: FUBAR stays
	movl	@#FUBAR, (r11)+		; 0000F800
	movl	#1, @#UASR
	movl	@#UASR, (r11)+		; 0
	movl	@#FUBAR, (r11)+		; 0000F800: nothing clears it
; a write is acknowledged at once, times out on the Unibus afterwards
	movw	#^x1234, @#IOP+^x1FFE	; 777776
	movl	@#UASR, (r11)+		; 0: not yet
	movw	@#IOP+4, r0		; busy until the write is over, then
	movl	@#UASR, (r11)+		; 00000001: the write's timeout
	movl	@#FUBAR, (r11)+		; 0000FFFF: the write's address
	movl	#1, @#UASR
; a byte read: the word, the high byte
	movb	#-1, r0
	movb	@#IOP+3, r0
	movzbl	r0, (r11)+		; 0
	movl	@#FUBAR, (r11)+		; 0000F800: UA 760002
	movl	#1, @#UASR

; ------------------------------------ the adapter's interrupt request
	movl	#8, @#UACR		; SUEFIE
	movl	@#BRRVR, (r11)+		; 0: no error
	movw	@#IOP, r0
	movl	@#BRRVR, (r11)+		; 80000000
	movl	@#BRRVR+12, (r11)+	; 0: BR4 only
	movl	#1, @#UASR		; the request goes down
	movl	@#BRRVR, (r11)+		; 0
; the interrupt itself: BR4, IPL 14, SCB 10C
	movw	@#IOP, r0
	mtpr	#^x14, #IPL		; not at 14
	movl	#^xA1, (r11)+
	mtpr	#^x13, #IPL		; taken
	movl	#^xA2, (r11)+
	mtpr	#^x1F, #IPL
; CNFIE: the configuration register's UBIC
	movl	#4, @#UACR
	movl	@#BRRVR, (r11)+		; 80000000
	movl	#^x10000, @#CNFGR	; clear UBIC
	movl	@#CNFGR, (r11)+		; 00000028
	movl	@#BRRVR, (r11)+		; 0
	movl	@#DCR, (r11)+		; 08000028
	clrl	@#UACR
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

; the adapter's interrupt: log, clear the timeout, return
	.align	4
h10c:	movl	#^x10C, (r11)+
	movpsl	r2
	bicl3	#^xF, r2, (r11)+	; 04140000: IPL 14
	movl	@#BRRVR, (r11)+		; 80000000: the adapter's request
	movl	@#UASR, (r11)+		; 00000001
	movl	#1, @#UASR		; the request goes down
	rei

	.align	4
unexp:	movl	#^xBAD, r9
	halt
