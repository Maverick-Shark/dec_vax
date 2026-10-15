; t30_intsize - interval timer interrupts taken right after byte and word
; instructions. The microcode that starts an interrupt used to run with the
; byte or word ALU size of the instruction just finished, read the level
; wrong and dispatch a timer interrupt through SCB E0 (found with EVKAE
; tests 2, 6 and 7, after INCB and DECW). The handler counts in R7 and stops
; the clock after the fifth interrupt; any other vector ends in "unexp"
; (R9 = 0BAD).
;@ dump=18000:4
	.include "mmsetup.inc"
IPL	= ^x12
ICCS	= ^x18
NICR	= ^x19
test:
	movl	#S0+tmr_h, @#^xC0
	clrl	r7
	mtpr	#-10, #NICR			; 10 microseconds
	mtpr	#^x51, #ICCS			; RUN, IE, ICR <- NICR
	pushl	#0				; to IPL 0 on the kernel stack (REI
	pushab	loop				; does not return to the interrupt
	rei					; stack at IPL 0)
loop:	incb	r0
	decw	r1
	addb2	#1, r2
	movw	r1, r3
	cmpl	r7, #5
	blss	loop
	mtpr	#^x1F, #IPL
	clrq	r0				; (depend on the timing)
	clrq	r2
	halt
	.align	4
tmr_h:	incl	r7
	cmpl	r7, #5
	blss	tmr_1
	mtpr	#^x80, #ICCS			; the fifth: clear the request, stop
	rei
tmr_1:	mtpr	#^xC1, #ICCS			; clear the request, keep running
	rei
