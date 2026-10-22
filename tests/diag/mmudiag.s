; mmudiag.s - memory management step by step on the core, for finding a
; problem on the board: software/mmudiag.bin (python3 tools/vasm.py
; tests/diag/mmudiag.s -o software/mmudiag.bin). Load it at 1000 and start
; it there (OSD: Load Address 0x00001000, Start Address = Load address,
; Autostart Yes), as mmutest.bin.
;
; Each step prints a line, so where the output stops shows where the
; machine went wrong. An exception that a step does not expect prints its
; SCB vector, the four longwords on top of the stack (for a translation
; fault: parameter, virtual address, PC, PSL) and the step, then halts. The
; same tables as tests/mmu/mmsetup.inc:
;
;   00000000  SCB          00010000  system page table, S0 page n -> page n
;   00001000  this code    00012000  P0 page table, P0 page n -> page n
;   00008000  test pages   00014000  P1 page table, the last 100 P1 pages
;   0000E000  interrupt stack top, 0000F000 kernel stack top
;
; Steps: tables written and read back; the registers; mapping on in P0,
; then in S0 (and from there on the kernel stack); writes and reads through S0 and P0; TBCHK and TBIS; 32
; pages written with mapping off and read back through S0, P0 and P1,
; twice, with the TB flushed in between; a translation not valid fault and
; an access violation (expected, with their frames printed); CHMK and a
; reserved operand fault; the kernel stack with interrupts from the
; interval timer, taken on the interrupt stack; then a summary.

S0	= ^x80000000
SPT	= ^x10000
P0PT	= ^x12000
P1PT	= ^x14000
PTE_V	= ^x80000000
PR_NA	= 0
PR_KW	= ^x10000000
PR_UW	= ^x20000000
KSP	= 0
ISP	= 4
P0BR	= 8
P0LR	= 9
P1BR	= ^xA
P1LR	= ^xB
SBR	= ^xC
SLR	= ^xD
SCBB	= ^x11
IPL	= ^x12
ICCS	= ^x18
NICR	= ^x19
TXCS	= ^x22
TXDB	= ^x23
MAPEN	= ^x38
TBIA	= ^x39
TBIS	= ^x3A
TBCHK	= ^x3F

	.org	^x1000
start:	mtpr	#^x1F, #IPL
	mtpr	#0, #MAPEN
	movl	#S0+^xE000, sp		; physical E000 until mapping is on
	mtpr	#S0+^xE000, #ISP
	mtpr	#S0+^xF000, #KSP
	movc3	#512, scbtab, @#0	; the SCB at 0: every vector to a stub
	mtpr	#0, #SCBB
	clrl	nerr
	movab	s_banner, r1
	jsb	puts

; ---------------------------------------------------------------- step 1
; the page tables, written and read back with mapping off
	movl	#1, step
	movab	s_t1, r1
	jsb	puts
	movl	#SPT, r0		; S0: page n -> n, KW
	movl	#PTE_V+PR_KW, r1
fill1:	movl	r1, (r0)+
	incl	r1
	cmpl	r0, #SPT+^x400
	blss	fill1
	movl	#P0PT, r0		; P0: page n -> n, UW
	movl	#PTE_V+PR_UW, r1
fill2:	movl	r1, (r0)+
	incl	r1
	cmpl	r0, #P0PT+^x400
	blss	fill2
	movl	#P1PT, r0		; P1: pages 1FFF00-1FFFFF -> 100-1FF, UW
	movl	#PTE_V+PR_UW+^x100, r1
fill3:	movl	r1, (r0)+
	incl	r1
	cmpl	r0, #P1PT+^x400
	blss	fill3
	clrl	r7			; read them back
	movl	#SPT, r0
	movl	#PTE_V+PR_KW, r1
chk1:	cmpl	(r0)+, r1
	beql	chk1b
	incl	r7
chk1b:	incl	r1
	cmpl	r0, #SPT+^x400
	blss	chk1
	movl	#P0PT, r0
	movl	#PTE_V+PR_UW, r1
chk2:	cmpl	(r0)+, r1
	beql	chk2b
	incl	r7
chk2b:	incl	r1
	cmpl	r0, #P0PT+^x400
	blss	chk2
	movab	s_bad, r1		; "  wrong entries: "
	jsb	puts
	movl	r7, r0
	jsb	puthex
	movab	s_spt, r1		; SPT[8], SPT[40], P0PT[40]
	jsb	puts
	movl	@#SPT+<8*4>, r0
	jsb	puthex
	jsb	space
	movl	@#SPT+<^x40*4>, r0
	jsb	puthex
	jsb	space
	movl	@#P0PT+<^x40*4>, r0
	jsb	puthex
	jsb	result			; ok if r7 = 0

; ---------------------------------------------------------------- step 2
; the memory management registers, written and read back
	movl	#2, step
	movab	s_t2, r1
	jsb	puts
	mtpr	#SPT, #SBR
	mtpr	#^x100, #SLR
	mtpr	#S0+P0PT, #P0BR
	mtpr	#^x100, #P0LR
	mtpr	#S0+P1PT-<^x1FFF00*4>, #P1BR
	mtpr	#^x1FFF00, #P1LR
	mtpr	#0, #TBIA
	clrl	r7
	mfpr	#SBR, r0
	cmpl	r0, #SPT
	beql	r2a
	incl	r7
r2a:	jsb	puthex
	jsb	space
	mfpr	#SLR, r0
	cmpl	r0, #^x100
	beql	r2b
	incl	r7
r2b:	jsb	puthex
	jsb	space
	mfpr	#P0BR, r0
	cmpl	r0, #S0+P0PT
	beql	r2c
	incl	r7
r2c:	jsb	puthex
	jsb	space
	mfpr	#P0LR, r0
	cmpl	r0, #^x100
	beql	r2d
	incl	r7
r2d:	jsb	puthex
	jsb	space
	mfpr	#P1BR, r0
	cmpl	r0, #S0+P1PT-<^x1FFF00*4>
	beql	r2e
	incl	r7
r2e:	jsb	puthex
	jsb	space
	mfpr	#P1LR, r0
	cmpl	r0, #^x1FFF00
	beql	r2f
	incl	r7
r2f:	jsb	puthex
	jsb	result

; ---------------------------------------------------------------- step 3
; mapping on: the code goes on at 0000xxxx, now P0 space
	movl	#3, step
	movab	s_t3, r1
	jsb	puts
	mtpr	#1, #MAPEN
	nop
	nop
	mfpr	#MAPEN, r0
	jsb	puthex
	movab	s_p0ok, r1
	jsb	puts

; ---------------------------------------------------------------- step 4
; into system space
	movl	#4, step
	movab	s_t4, r1
	jsb	puts
	jmp	@#S0+in_s0
in_s0:	movab	in_s0, r0		; the PC: 8000xxxx
	jsb	puthex
	movab	s_s0ok, r1
	jsb	puts
	pushl	#^x001F0000		; from here on the kernel stack (KSP),
	pushab	on_ks			; IPL 1F, kernel mode
	rei
on_ks:

; ---------------------------------------------------------------- step 5
; writes and reads through S0 and P0, as t01_xlate
	movl	#5, step
	movab	s_t5, r1
	jsb	puts
	clrl	r7
	movl	#^x11223344, @#S0+^x8000
	movl	@#^x8000, r0
	cmpl	r0, #^x11223344
	beql	r5a
	incl	r7
r5a:	jsb	puthex
	jsb	space
	movl	#^x55667788, @#^x8004
	movl	@#S0+^x8004, r0
	cmpl	r0, #^x55667788
	beql	r5b
	incl	r7
r5b:	jsb	puthex
	jsb	space
	mtpr	#0, #MAPEN		; the same longwords, physical
	movl	@#^x8000, r0
	mtpr	#1, #MAPEN
	cmpl	r0, #^x11223344
	beql	r5c
	incl	r7
r5c:	jsb	puthex
	jsb	result

; ---------------------------------------------------------------- step 6
; TBCHK (V set: the page is in the TB), TBIS, TBCHK again (V clear)
	movl	#6, step
	movab	s_t6, r1
	jsb	puts
	clrl	r7
	tstl	@#S0+^x8000		; make sure the page is in the TB
	mtpr	#S0+^x8000, #TBCHK
	movpsl	r6
	bicl3	#^xFFFFFFF0, r6, r0
	jsb	puthex
	jsb	space
	bitl	#2, r6
	bneq	r6a
	incl	r7			; V clear: not in the TB
r6a:	mtpr	#S0+^x8000, #TBIS
	mtpr	#S0+^x8000, #TBCHK
	movpsl	r6
	bicl3	#^xFFFFFFF0, r6, r0
	jsb	puthex
	bitl	#2, r6
	beql	r6b
	incl	r7			; V set: still there
r6b:	jsb	result

; ---------------------------------------------------------------- step 7
; 32 pages (40-5F): a pattern written with mapping off, read through S0,
; P0 and P1, twice, with TBIA in between; then a second pattern written
; through S0 and read through P0
	movl	#7, step
	movab	s_t7, r1
	jsb	puts
	mtpr	#0, #MAPEN
	movl	#^x8000, r0		; physical 8000 - BFFF
	movl	#^x40, r1
w7:	ashl	#16, r1, r2
	bisl3	#^xA5A5, r2, (r0)
	addl2	#^x200, r0
	aobleq	#^x5F, r1, w7
	mtpr	#1, #MAPEN
	clrl	r7
	movl	#2, r6			; two passes
p7:	mtpr	#0, #TBIA
	movl	#^x40, r1
r7a:	ashl	#16, r1, r2
	bisl2	#^xA5A5, r2		; expected
	ashl	#9, r1, r3		; byte offset of the page
	movl	S0(r3), r0		; through S0
	cmpl	r0, r2
	beql	r7b
	jsb	bad7
r7b:	movl	(r3), r0		; through P0
	cmpl	r0, r2
	beql	r7c
	jsb	bad7
r7c:	aobleq	#^x5F, r1, r7a
	sobgtr	r6, p7
	; P1: virtual 7FFE0000 + n*200 is P1 page 1FFF00+n -> physical 100+n
	mtpr	#0, #MAPEN
	movl	#^x20000, r0		; physical page 100
	movl	#^x77665544, (r0)
	movl	#^x33221100, ^x200(r0)
	mtpr	#1, #MAPEN
	movl	@#^x7FFE0000, r0
	cmpl	r0, #^x77665544
	beql	r7d
	movl	#^x7FFE0000, r3
	movl	#^x77665544, r2
	jsb	bad7
r7d:	movl	@#^x7FFE0200, r0
	cmpl	r0, #^x33221100
	beql	r7e
	movl	#^x7FFE0200, r3
	movl	#^x33221100, r2
	jsb	bad7
r7e:	movl	#^x40, r1		; a second pattern, written through S0
w7b:	ashl	#9, r1, r3
	mnegl	r1, r2
	movl	r2, S0+4(r3)
	aobleq	#^x5F, r1, w7b
	mtpr	#0, #TBIA
	movl	#^x40, r1
r7f:	ashl	#9, r1, r3
	mnegl	r1, r2
	movl	4(r3), r0		; through P0
	cmpl	r0, r2
	beql	r7g
	jsb	bad7
r7g:	aobleq	#^x5F, r1, r7f
	movab	s_bad, r1
	jsb	puts
	movl	r7, r0
	jsb	puthex
	jsb	result

; ---------------------------------------------------------------- step 8
; expected faults: translation not valid (page 60 made invalid) and access
; violation (page 61 made no-access); each prints its frame
	movl	#8, step
	movab	s_t8, r1
	jsb	puts
	clrl	r7
	bicl2	#PTE_V, @#S0+SPT+<^x60*4>
	mtpr	#S0+^xC000, #TBIS
	movab	r8a, r8			; where the handler goes on
	movl	#^x24, expvec
	tstl	@#S0+^xC000		; SCB 24, parameter 0
	incl	r7			; no fault: an error
r8a:	bisl2	#PTE_V, @#S0+SPT+<^x60*4>
	bicl2	#^x78000000, @#S0+SPT+<^x61*4>	; protection NA
	mtpr	#S0+^xC200, #TBIS
	movab	r8b, r8
	movl	#^x20, expvec
	movl	#1, @#S0+^xC204		; SCB 20, parameter 4 (write)
	incl	r7
r8b:	bisl2	#PR_KW, @#S0+SPT+<^x61*4>
	mtpr	#S0+^xC200, #TBIS
	clrl	expvec
	movab	s_t8b, r1
	jsb	puts
	movl	nexp, r0
	jsb	puthex
	cmpl	nexp, #2
	beql	r8c
	incl	r7
r8c:	jsb	result

; ---------------------------------------------------------------- step 9
; CHMK and a reserved operand fault, frames pushed through translated
; stack addresses
	movl	#9, step
	movab	s_t9, r1
	jsb	puts
	clrl	r7
	clrl	nexp
	movab	r9a, r8
	movl	#^x40, expvec
	chmk	#^x123			; SCB 40: code 123
	incl	r7
r9a:	movab	r9b, r8
	movl	#^x18, expvec
	bispsw	#^x100			; reserved operand: SCB 18
	incl	r7
r9b:	clrl	expvec
	movab	s_t8b, r1
	jsb	puts
	movl	nexp, r0
	jsb	puthex
	cmpl	nexp, #2
	beql	r9c
	incl	r7
r9c:	jsb	result

; ---------------------------------------------------------------- step 10
; IPL 0 on the kernel stack, and interval timer interrupts (SCB C0, taken
; on the interrupt stack): 20 of them, with memory being read meanwhile
	movl	#10, step
	movab	s_t10, r1
	jsb	puts
	clrl	r7
	clrl	ticks
	mtpr	#0, #IPL		; interrupts in
	movl	sp, r0
	jsb	puthex
	jsb	space
	mtpr	#-10000, #NICR		; every 10 ms
	mtpr	#^x51, #ICCS		; run, interrupt enable, transfer
	movl	#^x40, r1
k10a:	cmpl	ticks, #20
	bgeq	k10b
	ashl	#9, r1, r3		; meanwhile: reads through S0
	tstl	S0(r3)
	incl	r1
	cmpl	r1, #^x5F
	bleq	k10a
	movl	#^x40, r1
	brb	k10a
k10b:	mtpr	#0, #ICCS
	mtpr	#^x1F, #IPL
	movl	ticks, r0
	jsb	puthex
	jsb	result

; ---------------------------------------------------------------- the end
	movab	s_end, r1
	jsb	puts
	movl	nerr, r0
	jsb	puthex
	movab	s_crlf, r1
	jsb	puts
	tstl	nerr
	bneq	done1
	movab	s_allok, r1
	jsb	puts
done1:	halt

; ---------------------------------------------------------------- helpers
; result: "  ok" if r7 is 0, else "  ERROR"; counts the errors
result:	tstl	r7
	bneq	res1
	movab	s_ok, r1
	jsb	puts
	rsb
res1:	incl	nerr
	movab	s_err, r1
	jsb	puts
	rsb

; bad7: a wrong longword in step 7 (r3 the offset or address, r0 found,
; r2 expected); the first four are printed
bad7:	incl	r7
	cmpl	r7, #4
	bgtr	b7z
	pushl	r1
	pushl	r0
	movab	s_b7, r1
	jsb	puts
	movl	r3, r0
	jsb	puthex
	movab	s_b7b, r1
	jsb	puts
	movl	(sp), r0
	jsb	puthex
	movab	s_b7c, r1
	jsb	puts
	movl	r2, r0
	jsb	puthex
	movl	(sp)+, r0
	movl	(sp)+, r1
b7z:	rsb

space:	movl	#^x20, r0
	jsb	putc
	rsb

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
ph1:	rotl	#4, r2, r2
	extzv	#0, #4, r2, r4
	movb	hexdig[r4], r0
	jsb	putc
	sobgtr	r3, ph1
	popr	#^x1E
	rsb

; ---------------------------------------------------------------- exceptions
; Each vector's stub puts its offset in vec and comes here. If the step
; expects that vector (expvec), the frame is printed, the parameters are
; dropped and the handler goes on at R8; otherwise the frame is printed and
; the program halts.
	.align	4
exc:	movl	(sp), stk		; the top of the stack, before anything
	movl	4(sp), stk+4
	movl	8(sp), stk+8
	movl	12(sp), stk+12
	pushr	#^x3F			; r0-r5
	movab	s_exc, r1
	jsb	puts
	movl	vec, r0
	jsb	puthex
	movab	s_stk, r1
	jsb	puts
	movl	stk, r0
	jsb	puthex
	jsb	space
	movl	stk+4, r0
	jsb	puthex
	jsb	space
	movl	stk+8, r0
	jsb	puthex
	jsb	space
	movl	stk+12, r0
	jsb	puthex
	cmpl	vec, expvec
	beql	exc1
	movab	s_unexp, r1		; not expected: stop
	jsb	puts
	movl	step, r0
	jsb	puthex
	movab	s_crlf, r1
	jsb	puts
	halt
exc1:	popr	#^x3F
	incl	nexp
	cmpl	vec, #^x20		; access violation, translation not
	beql	exc2			; valid: two parameters
	cmpl	vec, #^x24
	beql	exc2
	cmpl	vec, #^x40		; CHMK: one parameter (the code)
	beql	exc3
	brb	exc4			; reserved operand: none
exc2:	addl2	#4, sp
exc3:	addl2	#4, sp
exc4:	movl	r8, (sp)		; go on at R8
	rei

; the interval timer: count, clear the request, back
	.align	4
tick:	incl	ticks
	mtpr	#^xC1, #ICCS		; run, interrupt enable, clear INT
	rei

; ---------------------------------------------------------------- data
hexdig:	.ascii	"0123456789ABCDEF"
s_banner:
	.ascii	"\r\nMemory management diagnostic (tests/diag/mmudiag.s)"
	.asciz	"\r\n"
s_t1:	.asciz	"1  page tables written, read back:"
s_bad:	.asciz	"  wrong: "
s_spt:	.asciz	"  SPT[8] SPT[40] P0PT[40] "
s_t2:	.asciz	"2  SBR SLR P0BR P0LR P1BR P1LR: "
s_t3:	.asciz	"3  MAPEN on, in P0: MAPEN "
s_p0ok:	.asciz	"  ok\r\n"
s_t4:	.asciz	"4  JMP to S0: PC "
s_s0ok:	.asciz	"  ok\r\n"
s_t5:	.asciz	"5  through S0 and P0: "
s_t6:	.asciz	"6  TBCHK, TBIS, TBCHK (NZVC): "
s_t7:	.asciz	"7  32 pages through S0, P0, P1:"
s_b7:	.asciz	"\r\n   at "
s_b7b:	.asciz	" found "
s_b7c:	.asciz	" expected "
s_t8:	.asciz	"8  expected faults: TNV, ACV"
s_t8b:	.asciz	"\r\n   taken: "
s_t9:	.asciz	"9  CHMK and a reserved operand"
s_t10:	.asciz	"10 IPL 0, timer interrupts: SP, ticks "
s_ok:	.asciz	"  ok\r\n"
s_err:	.asciz	"  ERROR\r\n"
s_exc:	.asciz	"\r\n   exception, SCB "
s_stk:	.asciz	", stack "
s_unexp:
	.asciz	"\r\nUNEXPECTED, stopped in step "
s_end:	.asciz	"End of the diagnostic, steps with errors: "
s_allok:
	.asciz	"Memory management works.\r\n"
s_crlf:	.asciz	"\r\n"

	.align	4
step:	.long	0
vec:	.long	0
expvec:	.long	0
nexp:	.long	0
nerr:	.long	0
ticks:	.long	0
stk:	.blkl	4

; the vector stubs (generated below by the assembler's include)
	.include "mmudiag_scb.inc"
