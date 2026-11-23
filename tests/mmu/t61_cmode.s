; t61_cmode - PDP-11 compatibility mode (VAX ARM chapter 9), memory
; management off: entering it with REI and leaving it by exceptions.
;
;   A  REI to compatibility mode with a PSL it does not allow: FPD, IS,
;      DV, FU, IV set, CUR_MOD or PRV_MOD not user, IPL not 0 - reserved
;      operand fault (logged: 18, the PC of the REI, the PSL)
;   B  REI with a PC whose upper half is not zero: it is ignored; the
;      registers' upper halves are ignored too (MOV (R1) with R1 = 1234xxxx)
;   C  the compatibility mode exceptions (SCB 30, code after PC and PSL):
;      BPT (1), IOT (2), EMT (3), TRAP (4), reserved instructions (0: HALT,
;      WAIT, RESET, MFPT, SPL, MARK, 000210, 0070xx, 075xxx, 076xxx, MTPS,
;      MFPS, 17xxxx), JMP and JSR to a register (5); PC at the instruction
;   D  odd address abort (6): the instruction fetch after a JMP to an odd
;      address, a word read, a word written by MOV and by JSR's push, with
;      the autoincrement of the instruction undone; a byte reference at an
;      odd address is fine
;   E  an interrupt pending at the REI is taken before the first compat
;      instruction: the frame has PSL<CM> and the 16-bit PC
;
; The compatibility mode exception handler logs the code, PC, PSL and
; R0-R6 (ten longwords), then steps over the instruction (BPT and the
; faults) or goes on at the next address of the list at R8 (odd address).
; EMT 377 ends the test. VAX R7-R13 are not touched in compatibility mode
; (R11 is the log pointer).
;@ dump=18000:200
;@ clocks=3000000
LOG	= ^x18000
KSP	= 0
USP	= 3
SCBB	= ^x11
SIRR	= ^x14
CMPSL	= ^x83C00000		; CM, user mode, previous user mode, IPL 0

	.org	^x1000
start:	movl	#^xE000, sp		; the interrupt stack
	clrl	r0
	movab	unexp+1, r1
scbfill: movl	r1, (r0)+
	cmpl	r0, #^x200
	blss	scbfill
	movab	resop, @#^x18
	movab	cmexc, @#^x30		; on the kernel stack
	movab	swi+1, @#^x90		; software interrupt 4
	mtpr	#0, #SCBB
	mtpr	#^xD000, #KSP
	mtpr	#^xB000, #USP
	movl	#LOG, r11
	clrl	ap

; ------------------------------------------- A: REI's checks
	movl	#^x8BC00000, r2		; FPD
	jsb	reibad
	movl	#^x87C00000, r2		; IS
	jsb	reibad
	movl	#^x83C00080, r2		; DV
	jsb	reibad
	movl	#^x83C00040, r2		; FU
	jsb	reibad
	movl	#^x83C00020, r2		; IV
	jsb	reibad
	movl	#^x82C00000, r2		; CUR_MOD supervisor
	jsb	reibad
	movl	#^x83800000, r2		; PRV_MOD supervisor
	jsb	reibad
	movl	#^x83C10000, r2		; IPL 1
	jsb	reibad
	movl	#^x80000000, r2		; kernel mode
	jsb	reibad

; ------------------------------------------- B, C, D: compat code
	movab	oddlist, r8
	movl	#^x00000101, r0
	movl	#^x12345000, r1		; upper half ignored: (R1) is 5000
	movl	#^x00000202, r2
	movl	#^x00000303, r3
	movl	#^x00000404, r4
	movl	#^x00005100, r5
	movl	#^x00006000, r6		; the compatibility mode SP
	movl	#^xABCD0007, r7		; VAX R7: not touched
	pushl	#CMPSL
	pushl	#^x55554000		; PC 4000
	rei

; the compatibility mode exception handler (kernel stack)
	.align	4
cmexc:	movl	(sp)+, r10		; the code
	movl	r10, (r11)+
	movl	(sp), (r11)+		; PC
	movl	4(sp), (r11)+		; PSL
	movl	r0, (r11)+
	movl	r1, (r11)+
	movl	r2, (r11)+
	movl	r3, (r11)+
	movl	r4, (r11)+
	movl	r5, (r11)+
	movl	r6, (r11)+
	cmpl	r10, #6			; odd address: the next restart point
	bneq	cm1
	movl	(r8)+, (sp)
	rei
cm1:	movzwl	@(sp), r9		; the instruction
	cmpl	r9, #^o104377		; EMT 377: the end of a part
	beql	cm2
	addl2	#2, (sp)		; step over it
	rei
cm2:	tstl	ap
	beql	part_e
	halt				; the end

; ------------------------------------------- E: an interrupt at once
part_e:	addl2	#8, sp			; drop the frame
	movl	#1, ap
	mtpr	#^x1F, #^x12		; IPL 1F
	mtpr	#4, #SIRR		; software interrupt 4 pending
	movl	#^x0000ABCD, r0
	pushl	#CMPSL
	pushl	#cmend
	rei				; to IPL 0: the interrupt first

	.align	4
swi:	movl	#^x90, (r11)+
	movl	(sp), (r11)+		; PC
	movl	4(sp), (r11)+		; PSL
	movl	r0, (r11)+
	rei

; REI with the PSL in R2: reserved operand fault, logged
reibad:	movab	rb_back, r9
	pushl	r2
	pushl	#^x4000
	rei
rb_back: rsb

	.align	4
resop:	movl	#^x18, (r11)+
	movl	(sp), (r11)+		; PC: the REI
	movl	4(sp), (r11)+		; PSL
	addl2	#16, sp			; the frame and REI's operands
	jmp	(r9)

	.align	4
unexp:	movl	#^xBAD, (r11)+
	movl	(sp), (r11)+
	movl	4(sp), (r11)+
	halt

; restart points after the odd address aborts (compat addresses)
oddlist: .long	odd1, odd2, odd3, odd4, odd5

; ======================================================== compat code
	.org	^x4000
	.pdp11
	mov	(r1), r0		; B: R1's upper half ignored: 5000
	bpt
	mov	#^o123456, r2
	bpt
; C: the exceptions
	iot
	emt	1
	trap	^o377
	.word	^o000000		; HALT (a .word: mkboard.py turns
					; HALT into the test's exit)
	wait
	reset
	.word	^o000007		; MFPT
	.word	^o000210
	.word	^o000227
	spl	3
	mark	2
	.word	^o007012		; CSM
	.word	^o007700
	.word	^o075004		; FADD
	.word	^o076020		; CIS
	.word	^o106412		; MTPS
	.word	^o106712		; MFPS
	.word	^o107000
	.word	^o170000		; FP11
	.word	^o177777
	jmp	r3			; illegal (5)
	jsr	pc, r1			; illegal
	.word	^o000100		; JMP R0
; D: odd addresses
	mov	#^x5001, r1
	jmp	(r1)			; the fetch at 5001 aborts
odd1:	mov	(r1)+, r2		; abort, R1 not incremented
odd2:	movb	(r1)+, r2		; a byte: fine, R1 5002
	bpt
	mov	#^x5004, r3
	mov	r2, -(r3)		; 5002: a word at an even address, fine
	bpt
	mov	#^x5003, r3
	mov	r2, (r3)+		; abort, R3 not incremented
odd3:	mov	sp, r4
	mov	#^x6001, sp
	jsr	pc, sub1		; the push at 5FFF aborts
odd4:	mov	r4, sp
	tst	@#^x5007		; abort
odd5:	bpt
	emt	^o377

	.org	^x4800
sub1:	rts	pc
cmend:	mov	#1, r1
	bpt
	emt	^o377

	.vax
	.org	^x5000
	.word	^x8001, ^x7F80, ^x1234, ^x5678

; mkboard.py (software/mmutest.bin) appends its code and table: out of the
; test's way
	.org	^x7000
