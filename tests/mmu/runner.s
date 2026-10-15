; runner.s - runs the tests/mmu programs on the core itself and prints
; PASS or FAIL for each one on the console. Built into software/mmutest.bin
; by tests/mmu/mkboard.py, which also generates suite.inc (the test table
; and the test images, each with its table of expected values from simh).
;
; Memory:
;   00001000            each test is copied here and runs as in run.py
;   00000000-00047FFF   cleared before each test (simh starts from zeros)
;   002FC000            the runner's SCB
;   002FE800, 002FF000  the runner's kernel and interrupt stacks (tops)
;   00300000            the runner (boot.s copies it here)
;
; Before each test the runner puts the machine back in the state simh starts
; in: mapping off, timer stopped, ASTLVL 4, no software interrupt pending,
; R0-R13 zero, PSL 041F0000 (kernel mode, interrupt stack, IPL 1F). The test
; ends in "finish" (board.inc), which comes back to RUN+8 with mapping off.

RUN	= ^x300000
RSTK	= ^x2FF000
RKSTK	= ^x2FE800
RSCB	= ^x2FC000
TBASE	= ^x1000
ZTOP	= ^x48000

KSP	= 0
ESP	= 1
SSP	= 2
USP	= 3
ISP	= 4
PCBB	= ^x10
SCBB	= ^x11
IPL	= ^x12
ASTLVL	= ^x13
SIRR	= ^x14
ICCS	= ^x18
RXCS	= ^x20
TXCS	= ^x22
TXDB	= ^x23
MAPEN	= ^x38
TBIA	= ^x39

; test table entry (suite.inc): name, image, length, sav, exptab, flags
TE_NAME	= 0
TE_IMG	= 4
TE_LEN	= 8
TE_SAV	= 12
TE_EXP	= 16
TE_FLG	= 20
TENT	= 24

	.org	RUN
	brw	rstart
	.org	RUN+8
	brw	test_done

rstart:	mtpr	#^x1F, #IPL
	mtpr	#0, #MAPEN
	mtpr	#RSTK, #ISP
	mtpr	#RKSTK, #KSP
	movl	#RSTK, sp
; the runner's SCB: exceptions are fatal, interrupts are dismissed, and
; software interrupt level 1 is how a test gets started (see reset)
	movl	#RSCB, r0
	movab	rfatal+1, r1
scb1:	movl	r1, (r0)+
	cmpl	r0, #RSCB+^x80
	blssu	scb1
	movab	rdismiss+1, r1
scb2:	movl	r1, (r0)+
	cmpl	r0, #RSCB+^x200
	blssu	scb2
	movab	fresh+1, @#RSCB+^x84
	mtpr	#RSCB, #SCBB
	movab	s_banner, r1
	jsb	puts
	clrl	tidx
	clrl	npass
	clrl	nfail

; ------------------------------------------------------------ next test
next:	movl	tidx, r2
	cmpl	r2, #NTESTS
	blssu	next1
	brw	alldone
next1:	mull3	#TENT, r2, r3
	movab	ttab, r4
	addl2	r3, r4
	movl	r4, tent
	bitl	#1, TE_FLG(r4)		; a test that ends in a processor halt
	beql	reset			; runs last, after the summary
	brw	alldone

; Put the machine back to its power-up state and start the test from a
; software interrupt, which leaves the CPU on the interrupt stack in kernel
; mode with PRV_MOD kernel: the PSL a VAX has after power-up.
reset:	mtpr	#^x1F, #IPL
	mtpr	#0, #MAPEN
	mtpr	#0, #TBIA
	mtpr	#^x80000080, #ICCS	; timer stopped, request and error cleared
	mtpr	#0, #RXCS
	mtpr	#0, #TXCS
	mtpr	#0, #ESP
	mtpr	#0, #SSP
	mtpr	#0, #USP
	mtpr	#4, #ASTLVL
	mtpr	#0, #PCBB
	mtpr	#RSCB, #SCBB
	mtpr	#RKSTK, #KSP
	mtpr	#RSTK, #ISP
	pushl	#^x001F0000		; to the kernel stack (REI cannot lower
	pushab	reset2			; IPL to 0 on the interrupt stack)
	rei
reset2:	mtpr	#0, #IPL		; anything pending comes in and is dismissed
	mtpr	#1, #SIRR		; then level 1, which lands on "fresh"
rwait:	brb	rwait

	.align	4
fresh:	mtpr	#^x1F, #IPL		; PSL: IS, kernel, kernel, IPL 1F
	movl	#RSTK, sp
	movl	tent, r4
	movl	TE_NAME(r4), r1
	jsb	puts
	jsb	dots
	clrl	r3			; clear 0 .. ZTOP-1
clr1:	movc5	#0, (r3), #0, #^x8000, (r3)
	cmpl	r3, #ZTOP
	blssu	clr1
	movl	tent, r4
	movc3	TE_LEN(r4), @TE_IMG(r4), @#TBASE
	clrq	r0
	clrq	r2
	clrq	r4
	clrq	r6
	clrq	r8
	clrq	r10
	clrq	ap			; AP, FP
	bicpsw	#^xF			; PSL 041F0000 exactly
	jmp	@#TBASE

; ------------------------------------------------------------ test done
; From finish (board.inc): kernel mode, IPL 1F, mapping off, any stack.
test_done:
	mtpr	#^x1F, #IPL
	mtpr	#0, #MAPEN
	movl	#RSTK, sp
	movl	tent, r4
	movl	TE_SAV(r4), r6		; saved R0-R14, PSL
	movl	TE_EXP(r4), r7		; expected values
	movl	(r7)+, r8		; how many
	clrl	r9			; mismatches
cmp1:	decl	r8
	blss	cmpend
	movl	(r7)+, r10		; what
	movl	(r7)+, r11		; expected value
	movl	(r7)+, r5		; mask
	cmpl	r10, #^xFFFFFF00
	blssu	cmpmem
	extzv	#0, #4, r10, r0
	movl	(r6)[r0], r3		; a register or the PSL
	brb	cmpv
cmpmem:	movl	(r10), r3		; a memory longword
cmpv:	xorl3	r3, r11, r0
	bitl	r5, r0
	beql	cmp1
	incl	r9
	cmpl	r9, #1
	bneq	cmp2
	movab	s_fail, r1		; first mismatch: FAIL, then the details
	jsb	puts
cmp2:	cmpl	r9, #6
	bgtr	cmp1			; details of the first six only
	jsb	report
	brb	cmp1
cmpend:	tstl	r9
	bneq	tfail
	movab	s_pass, r1
	jsb	puts
	incl	npass
	brb	tnext
tfail:	incl	nfail
tnext:	incl	tidx
	brw	next

; one mismatch: what in r10, value found in r3, expected in r11
report:	movab	s_ind, r1
	jsb	puts
	cmpl	r10, #^xFFFFFF0F
	bneq	rep1
	movab	s_psl, r1
	jsb	puts
	brb	rep3
rep1:	cmpl	r10, #^xFFFFFF00
	blssu	rep2
	movl	#^x52, r0		; 'R'
	jsb	putc
	extzv	#0, #4, r10, r0
	jsb	putdec2
	movab	s_sp3, r1
	jsb	puts
	brb	rep3
rep2:	movl	#^x5B, r0		; '['
	jsb	putc
	movl	r10, r0
	jsb	puthex
	movl	#^x5D, r0		; ']'
	jsb	putc
rep3:	movab	s_got, r1
	jsb	puts
	movl	r3, r0
	jsb	puthex
	movab	s_exp, r1
	jsb	puts
	movl	r11, r0
	jsb	puthex
	movab	s_crlf, r1
	jsb	puts
	rsb

; ------------------------------------------------------------ all done
alldone:
	movab	s_sum1, r1
	jsb	puts
	movl	npass, r0
	jsb	putdec2
	movab	s_sum2, r1
	jsb	puts
	movl	nfail, r0
	jsb	putdec2
	movab	s_sum3, r1
	jsb	puts
	tstl	nfail
	bneq	alld1
	movab	s_allok, r1
	jsb	puts
alld1:	movl	tidx, r2		; a halting test left?
	cmpl	r2, #NTESTS
	bgequ	alld2
	movab	s_halt, r1
	jsb	puts
	incl	tidx
	brw	reset			; tent already points at it
alld2:	movab	s_end, r1
	jsb	puts
	halt

; ------------------------------------------------------------ handlers
	.align	4
rdismiss:
	rei

	.align	4
rfatal:	mtpr	#^x1F, #IPL
	mtpr	#0, #MAPEN
	movl	#RSTK, sp
	movab	s_fatal, r1
	jsb	puts
	halt

; ------------------------------------------------------------ console output
; putc: the character in r0. Uses nothing else.
putc:	pushl	r1
putc1:	mfpr	#TXCS, r1
	bbc	#7, r1, putc1
	mtpr	r0, #TXDB
	movl	(sp)+, r1
	rsb

; puts: the string at r1 (r1 advances). Uses r0.
puts:	movzbl	(r1)+, r0
	beql	puts9
	jsb	putc
	brb	puts
puts9:	rsb

; puthex: r0 as eight hex digits. Uses r0.
puthex:	pushr	#^x1E			; r1-r4
	movl	r0, r2
	movl	#8, r3
puth1:	rotl	#4, r2, r2
	extzv	#0, #4, r2, r4
	movb	hexdig[r4], r0
	jsb	putc
	sobgtr	r3, puth1
	popr	#^x1E
	rsb

; putdec2: r0 (0-99) as two decimal digits. Uses r0.
putdec2:
	pushr	#^x06			; r1, r2
	divl3	#10, r0, r1		; tens
	mull3	#10, r1, r2
	subl3	r2, r0, r2		; units
	addl3	#^x30, r1, r0
	jsb	putc
	addl3	#^x30, r2, r0
	jsb	putc
	popr	#^x06
	rsb

; dots: pad the test name with dots up to column 18. Uses r0.
dots:	pushr	#^x06			; r1, r2
	movl	tent, r1
	movl	TE_NAME(r1), r1
	clrl	r2
dots0:	tstb	(r1)+
	beql	dots1
	incl	r2
	brb	dots0
dots1:	cmpl	r2, #18
	bgequ	dots2
	movl	#^x2E, r0		; '.'
	jsb	putc
	incl	r2
	brb	dots1
dots2:	movl	#^x20, r0
	jsb	putc
	popr	#^x06
	rsb

; ------------------------------------------------------------ data
tidx:	.long	0
tent:	.long	0
npass:	.long	0
nfail:	.long	0
hexdig:	.ascii	"0123456789ABCDEF"
s_banner:
	.ascii	"\r\nTest suite: the tests/mmu programs (memory management and"
	.ascii	" privileged\r\narchitecture), checked against simh vax8600"
	.asciz	"\r\n\r\n"
s_pass:	.asciz	"PASS\r\n"
s_fail:	.asciz	"FAIL\r\n"
s_ind:	.asciz	"    "
s_psl:	.asciz	"PSL  "
s_sp3:	.asciz	"  "
s_got:	.asciz	" is "
s_exp:	.asciz	", expected "
s_crlf:	.asciz	"\r\n"
s_sum1:	.asciz	"\r\nPassed: "
s_sum2:	.asciz	"   Failed: "
s_sum3:	.asciz	"\r\n"
s_allok:
	.asciz	"All tests passed.\r\n"
s_halt:	.ascii	"\r\nLast, t16_isnv: the CPU must halt here with code"
	.asciz	" 00000004.\r\n"
s_end:	.asciz	"End of the test suite.\r\n"
s_fatal:
	.asciz	"\r\nRunner: unexpected exception, stopped.\r\n"

	.align	4
	.include "suite.inc"
