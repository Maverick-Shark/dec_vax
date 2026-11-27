; t67_txidle - the VAX 8600 console transmitter with no line enabled
; (VAX Hardware Handbook, Volume 1, 1986, chapter 10, TXCS: ID F, "no lines
; currently enabled"; rtl/cons86.v):
;
;   - a mask of 0 written with <15> (write mask now): TXCS<11:8> is F and
;     <7> (ready) is set, and with <6> set a transmit interrupt (SCB FC)
;     comes, once: VMS's console port driver stops the console line this way
;     and, when it has output again, writes the new mask only while <7> is
;     set; when <7> is clear it leaves the mask for its interrupt routine,
;     so that interrupt has to come;
;   - a byte written to TXDB for ID F goes nowhere and changes nothing;
;   - the line started again as VMS starts it (<7> set: interrupts off,
;     then the mask with the interrupt enable): line 0 ready, one
;     interrupt.
;@ dump=18000:8
;@ clocks=6000000
LOG	= ^x18000
SCBB	= ^x11
IPL	= ^x12
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
	movab	txint+1, @#^xFC		; console transmit
	mtpr	#0, #SCBB
	movl	#LOG, r11
	clrl	r9			; unexpected events
	clrl	r8			; transmit interrupts
	clrl	r6			; TXCS in the last one

; ------------------------------------------- after initialization
	movl	#^x0080, r2		; ready, line 0
	jsb	txwait

; ------------------------------------------- the line stopped: mask 0
	mtpr	#^x8040, #TXCS		; interrupts on, at IPL 1F not yet taken
	movl	#^x0F80, r2		; ready, ID F
	jsb	txwait
	mfpr	#TXCS, (r11)+		; 00000FC0
	mtpr	#^x41, #TXDB		; a byte for no line
	mfpr	#TXCS, (r11)+		; 00000FC0: nothing changed
	mtpr	#^x13, #IPL		; below the console's 14
	jsb	delay
	mtpr	#^x1F, #IPL
	movl	r8, (r11)+		; 1: one interrupt
	movl	r6, (r11)+		; 00000FC0

; ------------------------------------------- started again, as VMS does it
	mfpr	#TXCS, r0
	bbs	#7, r0, go
	movl	#^xDEAD, r9
go:	mtpr	#0, #TXCS		; interrupts off
	movl	#^x0F80, r2
	jsb	txwait
	mtpr	#^x18040, #TXCS		; the terminal, interrupts on
	mtpr	#^x13, #IPL
	jsb	delay
	mtpr	#^x1F, #IPL
	movl	r8, (r11)+		; 2
	movl	r6, (r11)+		; 000100C0: line 0, ready
	mfpr	#TXCS, (r11)+		; 00010080 (the routine turned them off)
	movl	r9, (r11)+		; 0: nothing unexpected
	halt

; the transmit interrupt: count it, keep TXCS, interrupts off
	.align	4
txint:	incl	r8
	mfpr	#TXCS, r6
	mtpr	#0, #TXCS
	rei

; wait until TXCS says the line in R2<11:8> is ready (<11:7> = R2<11:7>)
txwait:	movl	#20000, r1
txw1:	mfpr	#TXCS, r0
	bicl2	#^xFFFFF07F, r0
	cmpl	r0, r2
	beql	txw2
	sobgtr	r1, txw1
	movl	#^xDEAD, r9
txw2:	rsb

delay:	movl	#3000, r1
dly1:	sobgtr	r1, dly1
	rsb

	.align	4
unexp:	movl	#^xBAD, r9
	halt
