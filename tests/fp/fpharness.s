; fpharness.s - the fixed part of software/fptest.bin, the floating point
; test that tests/fp/mkfptest.py builds. mkfptest.py adds the part it
; generates after this file: the header text (hdr), the number of
; instructions (NBLK), their descriptors (desc), the code that runs one
; case of each instruction (its "stub"), the instruction names and the
; table of exception vectors (scbtab). It puts the cases themselves after
; the program and fills in where each instruction's cases are.
;
; Load at 1000 and start there (the OSD defaults, as for mmutest.bin).
; Mapping off, kernel mode, IPL 1F; the SCB is at 0 and the stack ends at
; 1000.
;
; For each instruction (descriptor in R9) and each of its cases (record in
; R6, counter in R7), the driver
;   1. copies the case's initial destination contents into dstbuf (and,
;      for POLY, into R0-R5),
;   2. sets PSL<FU>, PSL<IV> and the condition codes from the case,
;   3. jumps to the stub, which executes the instruction with its source
;      operands in the record (displacement mode off R6) and its
;      destination in dstbuf, and comes back to "after" (or "after2"
;      when it has already saved the PSL),
;   4. compares the exception taken (none, reserved operand, or the type
;      code of an arithmetic exception), the condition codes (those the
;      case checks: none after a fault, where the SRM leaves them
;      UNPREDICTABLE) and the destination bytes with the case's expected
;      values.
; An exception handler records what happened and resumes at R8 ("after").
; Anything else that traps or faults is unexpected: the program stops and
; says where.
;
; Record (mkfptest.py writes them):
;   +0   PSW bits to set: N Z V C (3:0), IV (5), FU (6)
;   +4   expected exception: 0 none, 18 reserved operand, 100 + the type
;        code of an arithmetic exception (101 integer overflow trap, 108
;        floating overflow, 109 floating divide by zero, 10A floating
;        underflow)
;   +8   condition codes to check (mask), +12 their expected values
;   +16  source operands (the layout is the stub's)
;   D_INIT, D_EXP (from the descriptor): the destination before and after

IPL	= ^x12
SCBB	= ^x11
MAPEN	= ^x38
TXCS	= ^x22
TXDB	= ^x23
KSP	= 0
ISP	= 4

; descriptor fields (DSIZE bytes; mkfptest.py writes them)
D_NAME	= 0			; name, 7 characters and a NUL
D_STUB	= 4			; the stub
D_TAB	= 8			; first case
D_CNT	= 12			; number of cases
D_STRIDE = 16			; bytes per case
D_INIT	= 20			; offset of the initial destination
D_EXP	= 24			; offset of the expected destination
D_DLEN	= 28			; destination bytes compared
D_FLAGS	= 32			; <0>: POLY (the destination is R0-R5)
D_OPSL	= 36			; bytes of source operands (from +16)
D_FAIL	= 40			; failed cases (counted here)
DSIZE	= 44

R_PSW	= 0
R_EXC	= 4
R_MASK	= 8
R_CC	= 12
R_OPS	= 16

MAXLOG	= 4			; failures shown in detail
L_DESC	= 0			; failure log entry
L_CASE	= 4
L_REC	= 8
L_EXC	= 12
L_PSL	= 16
L_DST	= 20			; 24 bytes
LSIZE	= 44

	.org	^x1000
start:	mtpr	#^x1F, #IPL
	mtpr	#0, #MAPEN
	movl	#^x1000, sp
	mtpr	#^x1000, #KSP
	mtpr	#^x1000, #ISP
	movc3	#512, scbtab, @#0	; the SCB at 0
	mtpr	#0, #SCBB
	movab	hdr, r1
	jsb	puts
	movab	desc, r9
	movl	#NBLK, nleft
	clrl	tcases
	clrl	tfail
	clrl	nlog
	clrl	col

; ------------------------------------------------------------ one instruction
blkloop:
	movl	D_TAB(r9), r6
	movl	D_CNT(r9), r7
	clrl	D_FAIL(r9)
	addl2	r7, tcases
	tstl	r7
	bneq	caseloop
	brw	blkend

; ------------------------------------------------------------ one case
caseloop:
	addl3	r6, D_INIT(r9), r1
	movc3	D_DLEN(r9), (r1), dstbuf
	bbc	#0, D_FLAGS(r9), noregs
	movq	dstbuf, r0		; POLY: R0-R5 as the case gives them
	movq	dstbuf+8, r2
	movq	dstbuf+16, r4
noregs:	clrl	exc
	movab	after, r8		; where a handler resumes
	bicpsw	#^x6F			; N Z V C, IV, FU
	bispsw	R_PSW(r6)		; the case's
	jmp	@D_STUB(r9)		; (JMP leaves the condition codes alone)
after:	movpsl	pslaft
after2:	bicpsw	#^x60			; no integer overflow traps in the driver
	cmpl	exc, R_EXC(r6)
	bneq	bad
	xorl3	pslaft, R_CC(r6), r0
	bitl	R_MASK(r6), r0
	bneq	bad
	addl3	r6, D_EXP(r9), r1
	cmpc3	D_DLEN(r9), dstbuf, (r1)
	beql	good
bad:	jsb	logfail
good:	addl2	D_STRIDE(r9), r6
	decl	r7
	beql	blkend
	brw	caseloop

blkend:	jsb	cell
	addl2	#DSIZE, r9
	decl	nleft
	beql	alldone
	brw	blkloop

; ------------------------------------------------------------ the end
alldone:
	tstl	col
	beql	ad1
	movab	s_crlf, r1
	jsb	puts
ad1:	movab	s_cases, r1
	jsb	puts
	movl	tcases, r0
	jsb	putdec
	movab	s_failed, r1
	jsb	puts
	movl	tfail, r0
	jsb	putdec
	movab	s_crlf, r1
	jsb	puts
	tstl	tfail
	bneq	ad2
	movab	s_allok, r1
	jsb	puts
	brw	fin
ad2:	movab	s_byins, r1		; failed cases by instruction
	jsb	puts
	movab	desc, r9
	movl	#NBLK, nleft
ad3:	tstl	D_FAIL(r9)
	beql	ad4
	movl	#^x20, r0
	jsb	putc
	movl	D_NAME(r9), r1
	jsb	putname
	movl	#^x20, r0
	jsb	putc
	movl	D_FAIL(r9), r0
	jsb	putdec
ad4:	addl2	#DSIZE, r9
	decl	nleft
	bneq	ad3
	movab	s_crlf, r1
	jsb	puts
	movab	s_first, r1
	jsb	puts
	movab	flog, r10
	movl	nlog, r11
ad5:	jsb	detail
	addl2	#LSIZE, r10
	decl	r11
	bneq	ad5
fin:	movab	s_end, r1
	jsb	puts
	halt

; ------------------------------------------------------------ a failure
; Count it, and keep the first MAXLOG for the details at the end.
logfail:
	incl	D_FAIL(r9)
	incl	tfail
	cmpl	nlog, #MAXLOG
	bgeq	lf9
	mull3	#LSIZE, nlog, r0
	movab	flog, r1
	addl2	r0, r1
	movl	r9, (r1)+		; L_DESC
	subl3	r7, D_CNT(r9), (r1)+	; L_CASE: counted from 0
	movl	r6, (r1)+		; L_REC
	movl	exc, (r1)+		; L_EXC
	movl	pslaft, (r1)+		; L_PSL
	movc3	#24, dstbuf, (r1)	; L_DST
	incl	nlog
lf9:	rsb

; One failure in detail (entry at R10):
;   ADDF3   case 17   PSW 41
;     sources  40800000 00004100
;     found    exception fltovf  cc -  destination 12345678
;     expected exception none    cc 8  destination 00000000
detail:	movl	L_DESC(r10), r9
	movl	L_REC(r10), r6
	movl	D_NAME(r9), r1
	jsb	putname
	movab	s_case, r1
	jsb	puts
	movl	L_CASE(r10), r0
	jsb	putdec
	movab	s_psw, r1
	jsb	puts
	movl	R_PSW(r6), r0
	movl	#2, r3
	jsb	puthexn
	movab	s_srcs, r1
	jsb	puts
	movab	R_OPS(r6), r1
	movl	D_OPSL(r9), r2
	jsb	putmem
	movab	s_found, r1		; found
	jsb	puts
	movl	L_EXC(r10), r0
	jsb	putexc
	movab	s_cc, r1
	jsb	puts
	extzv	#0, #4, L_PSL(r10), r0
	movl	#1, r3
	jsb	puthexn
	movab	s_dst, r1
	jsb	puts
	movab	L_DST(r10), r1
	movl	D_DLEN(r9), r2
	jsb	putmem
	movab	s_expect, r1		; expected
	jsb	puts
	movl	R_EXC(r6), r0
	jsb	putexc
	movab	s_cc, r1
	jsb	puts
	tstl	R_MASK(r6)
	bneq	dt1
	movl	#^x2D, r0		; '-': not checked
	jsb	putc
	brb	dt2
dt1:	movl	R_CC(r6), r0
	movl	#1, r3
	jsb	puthexn
dt2:	movab	s_dst, r1
	jsb	puts
	addl3	r6, D_EXP(r9), r1
	movl	D_DLEN(r9), r2
	jsb	putmem
	movab	s_crlf, r1
	jsb	puts
	rsb

; One cell of the table: the name and ok or ERR, seven to a line.
cell:	movl	D_NAME(r9), r1
	jsb	putname
	tstl	D_FAIL(r9)
	bneq	ce1
	movab	s_ok, r1
	brb	ce2
ce1:	movab	s_err, r1
ce2:	jsb	puts
	incl	col
	cmpl	col, #7
	blss	ce9
	clrl	col
	movab	s_crlf, r1
	jsb	puts
ce9:	rsb

; ------------------------------------------------------------ exceptions
	.align	4
h_rsv:	movl	#^x18, exc		; reserved operand fault: PC, PSL
	movl	r8, (sp)
	rei

	.align	4
h_arith:
	addl3	#^x100, (sp)+, exc	; arithmetic: type code, PC, PSL
	movl	r8, (sp)
	rei

	.align	4
h_dismiss:
	rei

; Anything else: say which vector, where, and stop.
ufatal:	movl	(sp), ustk
	movl	4(sp), ustk+4
	movl	8(sp), ustk+8
	movab	s_unexp, r1
	jsb	puts
	movl	uvec, r0
	movl	#3, r3
	jsb	puthexn
	movab	s_stack, r1
	jsb	puts
	movab	ustk, r1
	movl	#12, r2
	jsb	putmem
	movab	s_while, r1
	jsb	puts
	movl	D_NAME(r9), r1
	jsb	putname
	movab	s_case, r1
	jsb	puts
	subl3	r7, D_CNT(r9), r0
	jsb	putdec
	movab	s_crlf, r1
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

; putname: an instruction name (7 characters, padded). Uses r0, r1.
putname:
	jsb	puts
	rsb

; puthexn: the low r3 hex digits of r0 (r3 1-8). Uses r0.
puthexn:
	pushr	#^x1C			; r2-r4
	movl	r0, r2
	ashl	#2, r3, r4		; bits shown
	subl3	r4, #32, r4
	rotl	r4, r2, r2		; first digit to the top
phx1:	rotl	#4, r2, r2
	extzv	#0, #4, r2, r4
	movb	hexdig[r4], r0
	jsb	putc
	sobgtr	r3, phx1
	popr	#^x1C
	rsb

; putmem: r2 bytes at r1, as longwords in memory order (a last word or
; byte as 4 or 2 digits), with a space after each. Uses r0-r3.
putmem:	tstl	r2
	bleq	pm9
	cmpl	r2, #4
	blss	pm2
	movl	(r1)+, r0
	movl	#8, r3
	subl2	#4, r2
	brb	pm4
pm2:	cmpl	r2, #2
	blss	pm3
	movzwl	(r1)+, r0
	movl	#4, r3
	subl2	#2, r2
	brb	pm4
pm3:	movzbl	(r1)+, r0
	movl	#2, r3
	decl	r2
pm4:	jsb	puthexn
	movl	#^x20, r0
	jsb	putc
	brb	putmem
pm9:	rsb

; putdec: r0 (unsigned) in decimal. Uses r0.
putdec:	pushr	#^x1E			; r1-r4
	movab	decbuf+11, r1
	clrb	(r1)
pd1:	divl3	#10, r0, r2
	mull3	#10, r2, r3
	subl3	r3, r0, r3
	addb3	#^x30, r3, -(r1)
	movl	r2, r0
	bneq	pd1
	jsb	puts
	popr	#^x1E
	rsb

; putexc: the exception code in r0, as a word. Uses r0, r1.
putexc:	movab	s_none, r1
	tstl	r0
	beql	px9
	movab	s_resop, r1
	cmpl	r0, #^x18
	beql	px9
	movab	s_intovf, r1
	cmpl	r0, #^x101
	beql	px9
	movab	s_fltovf, r1
	cmpl	r0, #^x108
	beql	px9
	movab	s_fltdiv, r1
	cmpl	r0, #^x109
	beql	px9
	movab	s_fltund, r1
	cmpl	r0, #^x10A
	beql	px9
	movl	#3, r3			; something else: its code
	jsb	puthexn
	movab	s_sp4, r1
px9:	jsb	puts
	rsb

; ------------------------------------------------------------ data
hexdig:	.ascii	"0123456789ABCDEF"
s_crlf:	.asciz	"\r\n"
s_ok:	.asciz	"ok  "
s_err:	.asciz	"ERR "
s_cases:
	.asciz	"\r\nCases: "
s_failed:
	.asciz	"   Failed: "
s_allok:
	.asciz	"All tests passed.\r\n"
s_byins:
	.asciz	"Failed cases by instruction:"
s_first:
	.asciz	"First failures (cases count from 0):\r\n"
s_case:	.asciz	" case "
s_psw:	.asciz	"   PSW "
s_srcs:	.asciz	"\r\n  sources  "
s_found:
	.asciz	"\r\n  found    exception "
s_expect:
	.asciz	"\r\n  expected exception "
s_cc:	.asciz	" cc "
s_dst:	.asciz	"  destination "
s_none:	.asciz	"none  "
s_resop:
	.asciz	"resop "
s_intovf:
	.asciz	"intovf"
s_fltovf:
	.asciz	"fltovf"
s_fltdiv:
	.asciz	"fltdiv"
s_fltund:
	.asciz	"fltund"
s_sp4:	.asciz	"   "
s_end:	.asciz	"End of the floating point test.\r\n"
s_unexp:
	.asciz	"\r\nUnexpected exception, SCB vector "
s_stack:
	.asciz	", stack "
s_while:
	.asciz	"\r\nwhile running "

	.align	4
exc:	.long	0			; exception code of this case
pslaft:	.long	0			; PSL after the instruction
nleft:	.long	0
tcases:	.long	0
tfail:	.long	0
nlog:	.long	0
col:	.long	0
uvec:	.long	0
ustk:	.blkl	3
decbuf:	.blkb	12
	.align	16
dstbuf:	.blkb	32			; the destination
flog:	.blkb	MAXLOG*LSIZE		; the failures shown in detail
