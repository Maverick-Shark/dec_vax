; t48_sbiaint - SBIA 0 interrupts (EK-DB86X-TD-002, 3.6 and 3.14), mapping
; off. With no device on the SBI yet, the requests come from the adapter's
; maintenance logic: MAINT<04> (force SBI interrupt request) lets the silo
; comparator's maintenance TR bits <07:04> drive SBI REQ7-REQ4 and <03> SBI
; ALERT; MAINT<01> (force ISR data) makes the adapter answer an interrupt
; summary read with its write data latch - the last longword the CPU wrote
; to it - as if the nexus with those TR bits had answered.
;
;   - the vector registers read by software: 2008 0090-009C (an interrupt
;     summary read on the SBI), 00A4, 00AC, 00B0, 00B8 (fixed vectors);
;     no answer is vector 0;
;   - an interrupt at IPL 15: SCB 154 (TR 5), taken at IPL 15;
;   - the requests are levels: taken again after REI until the handler
;     clears the cause;
;   - four levels at once: 17, 16, 15, 14 in that order, the lowest TR first;
;   - a passive release: nobody answers, SCB 00 at the request's IPL;
;   - SBI alert, IPL 1B, SCB 58; the silo comparator's lock, IPL 19, SCB 50;
;   - CSR<31> (master interrupt enable) clear: no request reaches the CPU;
;   - at IPL 14 the console (internal) goes before the SBIA (external).
;
; Each handler logs its vector, its own PSL and the interrupted PSL (both
; without the condition codes), drops the request and returns.
;@ noref
;@ rtl=18000:00000154,18004:00000114,18008:000001D4,1800C:00000050,18010:00000058,18014:0000005C
;@ rtl=18018:00000064,1801C:00000000
;@ rtl=18020:00000154,18024:04150000,18028:04140000,1802C:000000A2
;@ rtl=18030:00000001,18034:00000002,18038:00000003,1803C:00000003,18040:000000A3
;@ rtl=18044:000001D0,18048:04170000,1804C:04130000,18050:00000190,18054:04160000,18058:04130000
;@ rtl=1805C:00000150,18060:04150000,18064:04130000,18068:00000110,1806C:04140000,18070:04130000
;@ rtl=18074:000000A4
;@ rtl=18078:00000000,1807C:04150000,18080:04140000,18084:000000A5
;@ rtl=18088:00000058,1808C:041B0000,18090:041A0000,18094:000000A6
;@ rtl=18098:00000050,1809C:04190000,180A0:04180000,180A4:E00F0000,180A8:000000A7
;@ rtl=180AC:000000A8,180B0:00000000,180B4:04150000,180B8:04010000
;@ rtl=180BC:000000FC,180C0:04140000,180C4:04130000,180C8:00000110,180CC:04140000,180D0:04130000
;@ rtl=180D4:000000A9,180D8:000000AA,180DC:00000000
LOG	= ^x18000
SCBB	= ^x11
IPL	= ^x12
TXCS	= ^x22
SBIA	= ^x20080000
CSR	= SBIA+^x04
SC	= SBIA+^x40
MAINT	= SBIA+^x44

	.org	^x1000
start:	movl	#^xE000, sp		; interrupt stack (PSL<IS> is set)
	clrl	r0
	movab	unexp+1, r1
scbfill:
	movl	r1, (r0)+
	cmpl	r0, #^x200
	blss	scbfill
	movab	h000+1, @#^x00		; passive release
	movab	h050+1, @#^x50		; silo compare
	movab	h058+1, @#^x58		; SBI alert
	movab	h0FC+1, @#^xFC		; console transmit
	movab	h110+1, @#^x110		; BR4, TR 4
	movab	h150+1, @#^x150		; BR5, TR 4
	movab	h154+1, @#^x154		; BR5, TR 5
	movab	h190+1, @#^x190		; BR6, TR 4
	movab	h1D0+1, @#^x1D0		; BR7, TR 4
	movab	h1DC+1, @#^x1DC		; BR7, TR 7
	mtpr	#0, #SCBB
	movl	#LOG, r11
	clrl	r9
	clrl	r10

; the vector registers, at IPL 1F: REQ5 forced, the ISR answered with TR 5
; (the write data latch holds 20, the SC write)
	movl	#^x12, @#MAINT
	movl	#^x20, @#SC
	movl	@#SBIA+^x94, (r11)+	; IPL 15: 154
	movl	@#SBIA+^x90, (r11)+	; IPL 14: 114
	movl	@#SBIA+^x9C, (r11)+	; IPL 17: 1D4
	movl	@#SBIA+^xA4, (r11)+	; 50
	movl	@#SBIA+^xAC, (r11)+	; 58
	movl	@#SBIA+^xB0, (r11)+	; 5C (no adapter error)
	movl	@#SBIA+^xB8, (r11)+	; 64
	movl	#^x10, @#MAINT		; no forced ISR data: nobody answers
	movl	@#SBIA+^x94, (r11)+	; 0
	clrl	@#SC

; one interrupt
	movl	#^x12, @#MAINT
	movl	#^x20, @#SC
	mtpr	#^x14, #IPL		; taken here, SCB 154
	movl	#^xA2, (r11)+
	mtpr	#^x1F, #IPL

; a request stays until its cause is cleared: three times
	movl	#^x80, @#SC		; REQ7, TR 7
	mtpr	#^x16, #IPL
	movl	r10, (r11)+		; 3
	movl	#^xA3, (r11)+
	mtpr	#^x1F, #IPL

; REQ4-7 at once, TR 4-7: 17 first, then 16, 15, 14, TR 4 each time
	movl	#^xF0, @#SC
	mtpr	#^x13, #IPL
	movl	#^xA4, (r11)+
	mtpr	#^x1F, #IPL

; passive release: REQ5 with nobody to answer the interrupt summary read
	movl	#^x10, @#MAINT
	movl	#^x20, @#SC
	mtpr	#^x14, #IPL		; SCB 00 at IPL 15
	movl	#^xA5, (r11)+
	mtpr	#^x1F, #IPL

; SBI alert (maintenance TR <03>)
	movl	#^x08, @#SC
	mtpr	#^x1A, #IPL		; SCB 58 at IPL 1B
	movl	#^xA6, (r11)+
	mtpr	#^x1F, #IPL
	clrl	@#MAINT

; silo comparator: unconditional lock, interrupt enabled, count 0: locked
; after 16 SBI cycles
	movl	#^x60000000, @#SC
	mtpr	#^x18, #IPL
	movl	#200, r0
w1:	sobgtr	r0, w1			; SCB 50 at IPL 19 meanwhile
	movl	#^xA7, (r11)+
	mtpr	#^x1F, #IPL

; master interrupt enable off: nothing reaches the CPU, even at IPL 1 (the
; lowest on the interrupt stack). On again: the request is taken, but the
; CSR write is now in the write data latch, which answers the summary read
; with no TR: a passive release
	movl	#^x60000000, @#CSR
	movl	#^x12, @#MAINT
	movl	#^x20, @#SC
	mtpr	#1, #IPL
	movl	#^xA8, (r11)+
	movl	#^xE0000000, @#CSR	; SCB 00 at IPL 15
	mtpr	#^x1F, #IPL

; IPL 14: the console's transmit interrupt (internal) before BR4 (external)
	movl	#^x10, @#SC		; REQ4, TR 4
	mtpr	#^x40, #TXCS		; transmitter ready, interrupt enabled
	mtpr	#^x13, #IPL		; SCB FC, then SCB 110
	movl	#^xA9, (r11)+
	mtpr	#^x1F, #IPL
	clrl	@#MAINT
	movl	#^xAA, (r11)+
	movl	r9, (r11)+		; nothing unexpected
	halt

; the handlers: vector, own PSL, interrupted PSL without the condition codes
	.align	4
h154:	movl	#^x154, (r11)+
	brw	hlog_clr
	.align	4
h000:	clrl	(r11)+
	brw	hlog_clr
	.align	4
h058:	movl	#^x58, (r11)+
	brw	hlog_clr
	.align	4
h110:	movl	#^x110, (r11)+
	brw	hlog_clr
	.align	4
h0FC:	movl	#^xFC, (r11)+
	movpsl	r2
	bicl3	#^xF, r2, (r11)+
	bicl3	#^xF, 4(sp), (r11)+
	mtpr	#0, #TXCS		; the request goes with the enable
	rei
	.align	4
h050:	movl	#^x50, (r11)+
	movpsl	r2
	bicl3	#^xF, r2, (r11)+
	bicl3	#^xF, 4(sp), (r11)+
	movl	@#SC, (r11)+		; E00F0000: locked, count F
	clrl	@#SC			; a count other than F unlocks
	rei
	.align	4
h1DC:	incl	r10			; the third time only it is cleared
	movl	r10, (r11)+
	cmpl	r10, #3
	blss	h1DC_1
	clrl	@#SC
h1DC_1:	rei
	.align	4
h1D0:	movl	#^x1D0, (r11)+
	movpsl	r2
	bicl3	#^xF, r2, (r11)+
	bicl3	#^xF, 4(sp), (r11)+
	movl	#^x70, @#SC		; REQ7 off: TR 4-6 at 16, 15, 14
	rei
	.align	4
h190:	movl	#^x190, (r11)+
	movpsl	r2
	bicl3	#^xF, r2, (r11)+
	bicl3	#^xF, 4(sp), (r11)+
	movl	#^x30, @#SC
	rei
	.align	4
h150:	movl	#^x150, (r11)+
	movpsl	r2
	bicl3	#^xF, r2, (r11)+
	bicl3	#^xF, 4(sp), (r11)+
	movl	#^x10, @#SC
	rei
hlog_clr:
	movpsl	r2
	bicl3	#^xF, r2, (r11)+
	bicl3	#^xF, 4(sp), (r11)+
	clrl	@#SC			; the request goes
	rei

	.align	4
unexp:	movl	#^xBAD, r9
	halt
