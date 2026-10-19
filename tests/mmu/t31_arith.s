; t31_arith - arithmetic traps (SCB 34, SRM 5.x): integer overflow (type 1,
; when PSL<IV> is set), integer divide by zero (2, always), taken after the
; instruction has stored its results, PC of the next instruction (the branch
; target for AOBxxx, SOBxxx, ACBx). The results and condition codes of the
; overflowing instructions (DIVx and EDIV by zero, ASHL and ASHQ, ADWC and
; SBWC, AOBxxx, SOBxxx). Then PSL<IV> through the CALLx entry mask and RET,
; and the reserved operand faults of CALLx (mask<13:12>) and RET (saved
; PSW<15:8>). The trap handler logs 34, the type code, PC, PSL; each case
; logs the PSL and its results. Generated; the expected values come from
; the reference simulator.
;@ dump=8000:2 dump=18000:180
	.include "mmsetup.inc"
test:
	movl	#S0+arith_h, @#^x34

; ADDL2 7FFFFFFF+1, IV: trap 1, after the sum is stored
	movl	#^x7FFFFFFF, r0
	bicpsw	#^xFF
	bispsw	#^x20
	addl2	#1, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; ADDL2 7FFFFFFF+1, IV clear: V, no trap
	movl	#^x7FFFFFFF, r0
	bicpsw	#^xFF
	addl2	#1, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; ADDB3 7F+1 to memory, IV: the byte is stored, then the trap
	movl	#^xAAAAAAAA, @#S0+^x8000
	bicpsw	#^xFF
	bispsw	#^x20
	addb3	#^x7F, #1, @#S0+^x8000
	movpsl	(r11)+
	movl	@#S0+^x8000, (r11)+
; ADDW2 7FFF+1, IV
	movl	#^x12347FFF, r0
	bicpsw	#^xFF
	bispsw	#^x20
	addw2	#1, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; SUBL3 80000000-1, IV
	bicpsw	#^xFF
	bispsw	#^x20
	subl3	#1, #^x80000000, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; MNEGL 80000000, IV
	bicpsw	#^xFF
	bispsw	#^x20
	mnegl	#^x80000000, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; MNEGB 80, IV
	movl	#-1, r0
	bicpsw	#^xFF
	bispsw	#^x20
	mnegb	#^x80, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; INCL 7FFFFFFF, IV
	movl	#^x7FFFFFFF, r0
	bicpsw	#^xFF
	bispsw	#^x20
	incl	r0
	movpsl	(r11)+
	movl	r0, (r11)+
; DECW 8000, IV
	movl	#^x00008000, r0
	bicpsw	#^xFF
	bispsw	#^x20
	decw	r0
	movpsl	(r11)+
	movl	r0, (r11)+
; MULL3 10000*10000, IV
	bicpsw	#^xFF
	bispsw	#^x20
	mull3	#^x10000, #^x10000, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; MULB2 40*4, IV
	movl	#^x40, r0
	bicpsw	#^xFF
	bispsw	#^x20
	mulb2	#4, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; MULW3 -2*3FFF: fits, IV
	bicpsw	#^xFF
	bispsw	#^x20
	mulw3	#-2, #^x3FFF, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; DIVL3 by zero, IV clear: trap 2 anyway, quotient = dividend, V
	movl	#-1, r0
	bicpsw	#^xFF
	divl3	#0, #1234, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; DIVB2 by zero, IV: trap 2
	movl	#^x12345678, r0
	bicpsw	#^xFF
	bispsw	#^x20
	divb2	#0, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; DIVW3 by zero to memory
	movl	#^x55555555, @#S0+^x8004
	bicpsw	#^xFF
	divw3	#0, #-5, @#S0+^x8004
	movpsl	(r11)+
	movl	@#S0+^x8004, (r11)+
; DIVL3 80000000/-1, IV: trap 1, quotient = dividend
	bicpsw	#^xFF
	bispsw	#^x20
	divl3	#-1, #^x80000000, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; DIVB3 80/-1, IV clear: V, no trap
	clrl	r0
	bicpsw	#^xFF
	divb3	#-1, #^x80, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; DIVL3 -7/2 = -3, IV
	bicpsw	#^xFF
	bispsw	#^x20
	divl3	#2, #-7, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; EDIV by zero, IV clear: trap 2, quotient = low dividend, remainder 0
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#-1, r2
	movl	#-1, r3
	bicpsw	#^xFF
	ediv	#0, r0, r2, r3
	movpsl	(r11)+
	movl	r2, (r11)+
	movl	r3, (r11)+
; EDIV overflow, IV: trap 1
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	bicpsw	#^xFF
	bispsw	#^x20
	ediv	#2, r0, r2, r3
	movpsl	(r11)+
	movl	r2, (r11)+
	movl	r3, (r11)+
; EDIV -100/7, IV
	movl	#-100, r0
	movl	#-1, r1
	bicpsw	#^xFF
	bispsw	#^x20
	ediv	#7, r0, r2, r3
	movpsl	(r11)+
	movl	r2, (r11)+
	movl	r3, (r11)+
; ASHL 1 of 40000000: V (the sign changes in the last shift), IV
	bicpsw	#^xFF
	bispsw	#^x20
	ashl	#1, #^x40000000, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; ASHL 2 of 3FFFFFFF: V
	bicpsw	#^xFF
	ashl	#2, #^x3FFFFFFF, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; ASHL 31 of -1: no V, IV
	bicpsw	#^xFF
	bispsw	#^x20
	ashl	#31, #-1, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; ASHL 32 of 1: 0, V
	bicpsw	#^xFF
	ashl	#32, #1, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; ASHL 100 of 0: no V, IV
	bicpsw	#^xFF
	bispsw	#^x20
	ashl	#100, #0, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; ASHL 127 of -1: V, IV
	bicpsw	#^xFF
	bispsw	#^x20
	ashl	#127, #-1, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; ASHL -1 of -5: -3
	bicpsw	#^xFF
	bispsw	#^x20
	ashl	#-1, #-5, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; ASHL -40 of -5: -1
	bicpsw	#^xFF
	bispsw	#^x20
	ashl	#-40, #-5, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; ASHL -128 of 7FFFFFFF: 0
	bicpsw	#^xFF
	bispsw	#^x20
	ashl	#-128, #^x7FFFFFFF, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; ASHQ 1 of 40000000'00000000: V, IV
	clrl	r2
	movl	#^x40000000, r3
	bicpsw	#^xFF
	bispsw	#^x20
	ashq	#1, r2, r0
	movpsl	(r11)+
	movl	r0, (r11)+
	movl	r1, (r11)+
; ASHQ 63 of 1: V
	movl	#1, r2
	clrl	r3
	bicpsw	#^xFF
	ashq	#63, r2, r0
	movpsl	(r11)+
	movl	r0, (r11)+
	movl	r1, (r11)+
; ASHQ 3 of FFFFFFFF'F0000000: no V, IV
	movl	#^xF0000000, r2
	movl	#-1, r3
	bicpsw	#^xFF
	bispsw	#^x20
	ashq	#3, r2, r0
	movpsl	(r11)+
	movl	r0, (r11)+
	movl	r1, (r11)+
; ASHQ -63 of 80000000'00000000: -1
	clrl	r2
	movl	#^x80000000, r3
	bicpsw	#^xFF
	ashq	#-63, r2, r0
	movpsl	(r11)+
	movl	r0, (r11)+
	movl	r1, (r11)+
; CVTLB 128, IV: trap 1
	bicpsw	#^xFF
	bispsw	#^x20
	cvtlb	#128, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; CVTLW -32769, IV
	bicpsw	#^xFF
	bispsw	#^x20
	cvtlw	#-32769, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; CVTWB 100, IV
	bicpsw	#^xFF
	bispsw	#^x20
	cvtwb	#^x100, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; ADWC 80000000+FFFFFFFF+C: no overflow (the first add's is undone), IV
	movl	#^x80000000, r0
	bicpsw	#^xFF
	bispsw	#^x21
	adwc	#^xFFFFFFFF, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; ADWC 7FFFFFFF+0+C: V, IV
	movl	#^x7FFFFFFF, r0
	bicpsw	#^xFF
	bispsw	#^x21
	adwc	#0, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; ADWC 1+FFFFFFFF: C, Z, no V
	movl	#1, r0
	bicpsw	#^xFF
	bispsw	#^x20
	adwc	#-1, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; SBWC 80000000-0-C: V, IV
	movl	#^x80000000, r0
	bicpsw	#^xFF
	bispsw	#^x21
	sbwc	#0, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; SBWC 7FFFFFFF-FFFFFFFF-C: no overflow, IV
	movl	#^x7FFFFFFF, r0
	bicpsw	#^xFF
	bispsw	#^x21
	sbwc	#-1, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; SBWC 0-0-C: -1, C, N
	clrl	r0
	bicpsw	#^xFF
	bispsw	#^x21
	sbwc	#0, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; AOBLSS 7FFFFFFF+1 < 5: V, IV: trap 1 after the branch (PC = target)
	movl	#^x7FFFFFFF, r0
	bicpsw	#^xFF
	bispsw	#^x20
	aoblss	#5, r0, b43
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	b43x
b43:	movpsl	(r11)+
	movl	#^xA1, (r11)+
b43x:	movl	r0, (r11)+
; AOBLEQ -1+1 = 0 <= 0: branch, no V
	movl	#-1, r0
	bicpsw	#^xFF
	bispsw	#^x20
	aobleq	#0, r0, b44
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	b44x
b44:	movpsl	(r11)+
	movl	#^xA1, (r11)+
b44x:	movl	r0, (r11)+
; AOBLEQ 7FFFFFFF+1 <= 7FFFFFFF: branch, V (IV clear)
	movl	#^x7FFFFFFF, r0
	bicpsw	#^xFF
	aobleq	#^x7FFFFFFF, r0, b45
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	b45x
b45:	movpsl	(r11)+
	movl	#^xA1, (r11)+
b45x:	movl	r0, (r11)+
; AOBLSS 5+1 < 80000000: no
	movl	#5, r0
	bicpsw	#^xFF
	aoblss	#^x80000000, r0, b46
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	b46x
b46:	movpsl	(r11)+
	movl	#^xA1, (r11)+
b46x:	movl	r0, (r11)+
; SOBGTR 80000001-1 = 80000000: not > 0, no branch
	movl	#^x80000001, r0
	bicpsw	#^xFF
	bispsw	#^x20
	sobgtr	r0, b47
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	b47x
b47:	movpsl	(r11)+
	movl	#^xA1, (r11)+
b47x:	movl	r0, (r11)+
; SOBGTR 80000000-1: V, IV, branch
	movl	#^x80000000, r0
	bicpsw	#^xFF
	bispsw	#^x20
	sobgtr	r0, b48
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	b48x
b48:	movpsl	(r11)+
	movl	#^xA1, (r11)+
b48x:	movl	r0, (r11)+
; SOBGEQ 0-1: no branch
	clrl	r0
	bicpsw	#^xFF
	bispsw	#^x20
	sobgeq	r0, b49
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	b49x
b49:	movpsl	(r11)+
	movl	#^xA1, (r11)+
b49x:	movl	r0, (r11)+
; SOBGEQ 80000000-1: V, IV, branch
	movl	#^x80000000, r0
	bicpsw	#^xFF
	bispsw	#^x20
	sobgeq	r0, b50
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	b50x
b50:	movpsl	(r11)+
	movl	#^xA1, (r11)+
b50x:	movl	r0, (r11)+
; ACBL 7FFFFFFF+1, IV: trap after the branch
	movl	#^x7FFFFFFF, r0
	bicpsw	#^xFF
	bispsw	#^x20
	acbl	#^x7FFFFFFF, #1, r0, b51
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	b51x
b51:	movpsl	(r11)+
	movl	#^xA1, (r11)+
b51x:	movl	r0, (r11)+
; ACBB 7F+1, IV
	movl	#^x7F, r0
	bicpsw	#^xFF
	bispsw	#^x20
	acbb	#^x7F, #1, r0, b52
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	b52x
b52:	movpsl	(r11)+
	movl	#^xA1, (r11)+
b52x:	movl	r0, (r11)+
; CALLS to a procedure whose entry mask sets IV: its overflow traps; RET
; gives the caller its PSW back (DV and IV clear): no trap after it
	bicpsw	#^xFF
	calls	#0, proc_iv
	movpsl	(r11)+
	movl	#^x7FFFFFFF, r0
	incl	r0
	movpsl	(r11)+
; and the other way round: IV and DV set, a procedure with neither
	bispsw	#^xA0
	calls	#0, proc_noiv
	movpsl	(r11)+
	movl	#^x7FFFFFFF, r0
	incl	r0
	movpsl	(r11)+
	bicpsw	#^xFF
; CALLG with entry mask bit 12 set: reserved operand fault, nothing pushed
	movl	sp, r6
	movab	callg_back, r8
	movl	#S0+fix_skip, r10
	callg	@#S0+^x8000, proc_mbz
callg_back:
	clrl	r10
	subl3	sp, r6, (r11)+			; 0: the stack is as before
; RET with saved PSW<8> set: reserved operand fault at the RET
	movab	ret_fix, r8
	movl	#S0+fix_skip, r10
	calls	#0, proc_badret
	clrl	r10
	movpsl	(r11)+
	subl3	sp, r6, (r11)+
	halt

	.align	4
arith_h:
	movl	#^x34, (r11)+
	movl	(sp)+, (r11)+			; type code
	movl	(sp), (r11)+			; PC
	movl	4(sp), (r11)+			; PSL
	rei

proc_iv:
	.word	^x4000				; IV
	movpsl	(r11)+
	movl	#^x7FFFFFFF, r0
	incl	r0				; trap 1
	ret
proc_noiv:
	.word	0
	movpsl	(r11)+
	movl	#^x7FFFFFFF, r0
	incl	r0				; V, no trap
	ret
proc_mbz:
	.word	^x1000
	halt
proc_badret:
	.word	^x0004				; saves R2
	bisl2	#^x100, 4(fp)			; saved PSW<8>
	ret					; reserved operand
ret_fix:
	bicl2	#^x100, 4(fp)
	ret

