; t15_movcint - interval-timer interrupts while a long MOVC3 runs: the
; RTL takes them in the middle of the move (PSL<FPD> set in the frame,
; the instruction resumes after the REI); the move must still be exact.
; simh does not interrupt inside MOVC3, so the interrupt count (R9) and
; the count of interrupts that saw PSL<FPD> (LOG longword 0) are not
; compared.
;@ dump=1A000:4 dump=1C000:4 dump=1FFF0:4 ignore=R9,R10,PSL
	.include "mmsetup.inc"
ICCS	= ^x18
NICR	= ^x19
IPL	= ^x12
test:
	movl	#S0+clk_h, @#^xC0
	clrl	r9
	clrl	@#S0+LOG
	mtpr	#-1000, #NICR			; every 1000 us (50000 clocks)
	mtpr	#^x51, #ICCS			; run, transfer, interrupt enable
	pushl	#0				; to the kernel stack at IPL 0
	pushl	#S0+t15k			; (IPL 0 is not allowed on the
	rei					; interrupt stack)
t15k:	movc3	#^x6000, @#S0+^x0000, @#S0+^x1A000
	mtpr	#^x1F, #IPL
	mtpr	#0, #ICCS
	movl	@#S0+LOG, r10			; interrupts that hit the MOVC3
	halt
	.align	4
clk_h:	incl	r9
	bbc	#27, 4(sp), clk_1		; PSL<FPD> in the frame?
	incl	@#S0+LOG
clk_1:	mtpr	#^xC1, #ICCS			; clear the interrupt
	rei
