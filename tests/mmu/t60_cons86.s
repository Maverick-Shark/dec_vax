; t60_cons86 - the VAX 8600 console registers (VAX Hardware Handbook,
; Volume 1, 1986, chapter 10; rtl/cons86.v):
;
;   - TXCS after initialization: the console terminal enabled (mask <16>),
;     line 0 ready;
;   - the transmit enable mask, written with <15> (write mask now): the
;     logical console alone (line 3 ready, as DIAGBOOT waits for it), the
;     logical console and the terminal (the logical console is offered
;     first), the EMM alone (line 2; its bytes go nowhere);
;   - the logical console's requests, answered in RXDB with ID 3 and the
;     carrier of the wired lines (<19,18,16>): 12, the microcode version
;     (12, then the version low byte first, as DIAGBOOT reads it), 30, the
;     snapshot files (30, 00), 11 and 10, the COLD and WARM flags (11 or
;     10, then the flag);
;   - TXCS<6> and RXCS<6> (interrupt enables) and RXCS<19:16> (data
;     terminal ready) read back.
;
; The reference simulator does not answer 10 and 11 (the test times out
; there and logs DEAD) and does not keep RXCS<19:16>: the RTL's values are
; DEC's.
;@ dump=18000:18
;@ rtl=18030:000D0311,18034:000D0300,18038:000D0310,1803C:000D0300,18040:000F0040
;@ clocks=6000000
LOG	= ^x18000
SCBB	= ^x11
RXCS	= ^x20
RXDB	= ^x21
TXCS	= ^x22
TXDB	= ^x23

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

; ------------------------------------------- after initialization
	movl	#^x0080, r2		; ready, line 0
	jsb	txwait
	mfpr	#TXCS, (r11)+		; 00010080
	mfpr	#RXCS, (r11)+		; 00000000

; ------------------------------------------- the logical console alone
	mtpr	#^x88000, #TXCS
	movl	#^x0380, r2		; ready, line 3
	jsb	txwait
	mfpr	#TXCS, (r11)+		; 00080380
	mtpr	#^x12, #TXDB		; microcode version
	jsb	rxget			; 000D0312
	jsb	rxget			; 000D0301
	jsb	rxget			; 000D0300
	jsb	txwait
	mtpr	#^x30, #TXDB		; snapshot files
	jsb	rxget			; 000D0330
	jsb	rxget			; 000D0300

; ------------------------------------------- logical console and terminal
	jsb	txwait
	mtpr	#^x98000, #TXCS
	jsb	txwait			; the logical console first
	mfpr	#TXCS, (r11)+		; 00090380

; ------------------------------------------- the EMM alone
	mtpr	#^x48000, #TXCS
	movl	#^x0280, r2		; ready, line 2
	jsb	txwait
	mfpr	#TXCS, (r11)+		; 00040280
	mtpr	#0, #TXDB		; "request EMM status": no EMM, no answer
	jsb	txwait
	mfpr	#TXCS, (r11)+		; 00040280
	mfpr	#RXCS, (r11)+		; 00000000: nothing came back

; ------------------------------------------- the COLD and WARM flags
	mtpr	#^x88000, #TXCS
	movl	#^x0380, r2
	jsb	txwait
	mtpr	#^x11, #TXDB		; COLD
	jsb	rxget			; 000D0311
	jsb	rxget			; 000D0300 (no bootstrap)
	jsb	txwait
	mtpr	#^x10, #TXDB		; WARM
	jsb	rxget			; 000D0310
	jsb	rxget			; 000D0300

; ------------------------------------------- the interrupt enables, DTR
	mtpr	#^xF0040, #RXCS
	mfpr	#RXCS, (r11)+		; 000F0040 (reference: 00000040)
	mtpr	#0, #RXCS
	mfpr	#RXCS, (r11)+		; 00000000

; ------------------------------------------- the terminal again
	mtpr	#^x18000, #TXCS
	movl	#^x0080, r2
	jsb	txwait
	mtpr	#^x40, #TXCS
	mfpr	#TXCS, (r11)+		; 000100C0: the mask stays
	mtpr	#0, #TXCS
	mfpr	#TXCS, (r11)+		; 00010080
	movl	r9, (r11)+		; 0: nothing unexpected
	halt

; wait until TXCS says the line in R2<11:8> is ready (<11:7> = R2<11:7>)
txwait:	movl	#20000, r1
txw1:	mfpr	#TXCS, r0
	bicl2	#^xFFFFF07F, r0
	cmpl	r0, r2
	beql	txw2
	sobgtr	r1, txw1
	movl	#^xDEAD, r9
txw2:	rsb

; one byte from RXDB into the log (DEAD if none comes)
rxget:	movl	#20000, r1
rxg1:	mfpr	#RXCS, r0
	bbs	#7, r0, rxg2
	sobgtr	r1, rxg1
	movl	#^xDEAD, (r11)+
	rsb
rxg2:	mfpr	#RXDB, (r11)+
	rsb

	.align	4
unexp:	movl	#^xBAD, r9
	halt
