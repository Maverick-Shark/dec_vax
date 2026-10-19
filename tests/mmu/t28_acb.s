; t28_acb - ACBB, ACBW, ACBL: the index is added to at the operand's size
; (N, Z, V from that add, C unchanged) and compared with the limit as signed
; numbers, the direction given by the sign of the addend. Then CVTLB, CVTWB,
; CVTBW, CVTLW (V when the value does not fit). ACBB is used by the
; Diagnostic Supervisor. For each case the log gets the PSL, A1 if the branch
; was taken (else A0) and the index; for the conversions the PSL and R0.
; Generated cases; the expected values come from the reference simulator.
;@ dump=8000:2 dump=18000:60
	.include "mmsetup.inc"
test:

; ACBL -1+1 = 0, limit 5: branch; V clear (no overflow, only a sign change)
	movl	#-1, r0
	bispsw	#1
	acbl	#5, #1, r0, c0
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	c0x
c0:	movpsl	(r11)+
	movl	#^xA1, (r11)+
c0x:	movl	r0, (r11)+
; ACBL 7FFFFFFF+1: overflow (V, N); 80000000 <= 7FFFFFFF: branch
	movl	#^x7FFFFFFF, r0
	bispsw	#1
	acbl	#^x7FFFFFFF, #1, r0, c1
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	c1x
c1:	movpsl	(r11)+
	movl	#^xA1, (r11)+
c1x:	movl	r0, (r11)+
; ACBL 5-2 = 3 >= 3: branch
	movl	#5, r0
	bispsw	#1
	acbl	#3, #-2, r0, c2
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	c2x
c2:	movpsl	(r11)+
	movl	#^xA1, (r11)+
c2x:	movl	r0, (r11)+
; ACBL 3-2 = 1 >= 3: no
	movl	#3, r0
	bispsw	#1
	acbl	#3, #-2, r0, c3
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	c3x
c3:	movpsl	(r11)+
	movl	#^xA1, (r11)+
c3x:	movl	r0, (r11)+
; ACBL 10+1 = 11 <= -5: no
	movl	#10, r0
	bispsw	#1
	acbl	#-5, #1, r0, c4
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	c4x
c4:	movpsl	(r11)+
	movl	#^xA1, (r11)+
c4x:	movl	r0, (r11)+
; ACBL -2+1 = -1 <= 7FFFFFFF: branch (limit - index overflows)
	movl	#-2, r0
	bispsw	#1
	acbl	#^x7FFFFFFF, #1, r0, c5
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	c5x
c5:	movpsl	(r11)+
	movl	#^xA1, (r11)+
c5x:	movl	r0, (r11)+
; ACBL 80000000-1: overflow; 7FFFFFFF >= 0: branch
	movl	#^x80000000, r0
	bispsw	#1
	acbl	#0, #-1, r0, c6
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	c6x
c6:	movpsl	(r11)+
	movl	#^xA1, (r11)+
c6x:	movl	r0, (r11)+
; ACBL -1-1 = -2 >= 80000000: branch (index - limit overflows)
	movl	#-1, r0
	bispsw	#1
	acbl	#^x80000000, #-1, r0, c7
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	c7x
c7:	movpsl	(r11)+
	movl	#^xA1, (r11)+
c7x:	movl	r0, (r11)+
; ACBB 7F+1: overflow (V, N); -128 <= 127: branch
	movl	#^x1234567F, r0
	bispsw	#1
	acbb	#^x7F, #1, r0, c8
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	c8x
c8:	movpsl	(r11)+
	movl	#^xA1, (r11)+
c8x:	movl	r0, (r11)+
; ACBB 80-1: overflow; 127 >= 0: branch
	movl	#^x12345680, r0
	bispsw	#1
	acbb	#0, #-1, r0, c9
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	c9x
c9:	movpsl	(r11)+
	movl	#^xA1, (r11)+
c9x:	movl	r0, (r11)+
; ACBB -100+0 <= 100: branch (the difference is not a byte)
	movl	#-100, r0
	bispsw	#1
	acbb	#100, #0, r0, c10
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	c10x
c10:	movpsl	(r11)+
	movl	#^xA1, (r11)+
c10x:	movl	r0, (r11)+
; ACBB 20-1 = 19 >= -100: branch
	movl	#20, r0
	bispsw	#1
	acbb	#-100, #-1, r0, c11
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	c11x
c11:	movpsl	(r11)+
	movl	#^xA1, (r11)+
c11x:	movl	r0, (r11)+
; ACBB 120+1 = 121 <= -100: no
	movl	#120, r0
	bispsw	#1
	acbb	#-100, #1, r0, c12
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	c12x
c12:	movpsl	(r11)+
	movl	#^xA1, (r11)+
c12x:	movl	r0, (r11)+
; ACBB on a byte in memory: 10+5 = 15 <= 20: branch, the bytes around it kept
	movl	#^xAA550AAA, @#S0+^x8000
	movl	#S0+^x8001, r1
	bispsw	#1
	acbb	#20, #5, (r1)+, c13
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	c13x
c13:	movpsl	(r11)+
	movl	#^xA1, (r11)+
c13x:	movl	r1, (r11)+
; ACBW 7FFF+1: overflow; -32768 <= 7FFF: branch
	movl	#^xABCD7FFF, r0
	bispsw	#1
	acbw	#^x7FFF, #1, r0, c14
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	c14x
c14:	movpsl	(r11)+
	movl	#^xA1, (r11)+
c14x:	movl	r0, (r11)+
; ACBW 5-10 = -5 >= 0: no; the upper word of the register kept
	movl	#^xABCD0005, r0
	bispsw	#1
	acbw	#0, #-10, r0, c15
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	c15x
c15:	movpsl	(r11)+
	movl	#^xA1, (r11)+
c15x:	movl	r0, (r11)+
; ACBW on a word in memory: 1000+1000 = 2000 <= 2000: branch
	movl	#^x555503E8, @#S0+^x8004
	movl	#S0+^x8004, r1
	bispsw	#1
	acbw	#2000, #1000, (r1), c16
	movpsl	(r11)+
	movl	#^xA0, (r11)+
	brb	c16x
c16:	movpsl	(r11)+
	movl	#^xA1, (r11)+
c16x:	movl	r1, (r11)+
; CVTLB 127: fits
	movl	#^x5A5A5A5A, r0
	bispsw	#^xF
	cvtlb	#127, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; CVTLB 128: V
	movl	#^x5A5A5A5A, r0
	bispsw	#^xF
	cvtlb	#128, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; CVTLB -129: V
	movl	#^x5A5A5A5A, r0
	bispsw	#^xF
	cvtlb	#-129, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; CVTLB -128: fits, N
	movl	#^x5A5A5A5A, r0
	bispsw	#^xF
	cvtlb	#-128, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; CVTWB 0080: V
	movl	#^x5A5A5A5A, r0
	bispsw	#^xF
	cvtwb	#^x80, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; CVTWB FF80: fits, N
	movl	#^x5A5A5A5A, r0
	bispsw	#^xF
	cvtwb	#^xFF80, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; CVTWB 0100: V, Z
	movl	#^x5A5A5A5A, r0
	bispsw	#^xF
	cvtwb	#^x100, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; CVTBW FF: FFFF, N
	movl	#^x5A5A5A5A, r0
	bispsw	#^xF
	cvtbw	#^xFF, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; CVTBW 00: Z
	movl	#^x5A5A5A5A, r0
	bispsw	#^xF
	cvtbw	#0, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; CVTLW 8000: V
	movl	#^x5A5A5A5A, r0
	bispsw	#^xF
	cvtlw	#^x8000, r0
	movpsl	(r11)+
	movl	r0, (r11)+
; CVTLW FFFF8000: fits, N
	movl	#^x5A5A5A5A, r0
	bispsw	#^xF
	cvtlw	#^xFFFF8000, r0
	movpsl	(r11)+
	movl	r0, (r11)+
	halt
