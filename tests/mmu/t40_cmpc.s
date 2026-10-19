; t40_cmpc - CMPC3 and CMPC5: equal and unequal strings, empty ones, the
; fill against the rest of the longer string on either side, and bytes that
; compare differently signed and unsigned (N is a signed comparison of the
; last two bytes, C an unsigned one, as CMPB). Then both across an invalid
; page (the fault is taken, the instruction done again). Found with EVKAB
; test 139: CMPC5 compared the fill with string 1 instead of string 2, and
; gave the condition codes of a stale register for two empty strings. Each
; case logs the PSL and R0-R3. The reference simulator keeps the progress
; of a CMPC that
; faults in R0-R3 with PSL<FPD>; the core does it again from the start (it
; only reads), so PSL<FPD> and the condition codes of the fault frames are
; not compared.
;@ dump=18000:80
;@ mask=18160:F7FFFFF0,18174:F7FFFFF0,1819C:F7FFFFF0,181B0:F7FFFFF0
	.include "mmsetup.inc"
S1	= S0+^x8000
S2	= S0+^x8100
test:
	movl	#S0+fix_valid, r10

; CMPC3, length 0
	movb	#^x5A, @#S1+0
	movb	#^x5A, @#S2+0
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#0, r5
	bispsw	#^xF
	cmpc3	#0, @#S1, @#S2
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
; CMPC3, equal
	movb	#^x41, @#S1+0
	movb	#^x42, @#S1+1
	movb	#^x43, @#S1+2
	movb	#^x44, @#S1+3
	movb	#^x5A, @#S1+4
	movb	#^x41, @#S2+0
	movb	#^x42, @#S2+1
	movb	#^x43, @#S2+2
	movb	#^x44, @#S2+3
	movb	#^x5A, @#S2+4
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#1, r5
	bispsw	#^xF
	cmpc3	#4, @#S1, @#S2
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
; CMPC3, C < D at the third byte
	movb	#^x41, @#S1+0
	movb	#^x42, @#S1+1
	movb	#^x43, @#S1+2
	movb	#^x44, @#S1+3
	movb	#^x5A, @#S1+4
	movb	#^x41, @#S2+0
	movb	#^x42, @#S2+1
	movb	#^x44, @#S2+2
	movb	#^x44, @#S2+3
	movb	#^x5A, @#S2+4
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#2, r5
	bispsw	#^xF
	cmpc3	#4, @#S1, @#S2
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
; CMPC3, 80 : 01 (signed less, unsigned greater)
	movb	#^x80, @#S1+0
	movb	#^x5A, @#S1+1
	movb	#^x01, @#S2+0
	movb	#^x5A, @#S2+1
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#3, r5
	bispsw	#^xF
	cmpc3	#1, @#S1, @#S2
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
; CMPC3, 01 : FF (signed greater, unsigned less)
	movb	#^x01, @#S1+0
	movb	#^x5A, @#S1+1
	movb	#^xFF, @#S2+0
	movb	#^x5A, @#S2+1
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#4, r5
	bispsw	#^xF
	cmpc3	#1, @#S1, @#S2
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
; CMPC3, 7F : 80
	movb	#^x10, @#S1+0
	movb	#^x7F, @#S1+1
	movb	#^x5A, @#S1+2
	movb	#^x10, @#S2+0
	movb	#^x80, @#S2+1
	movb	#^x5A, @#S2+2
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#5, r5
	bispsw	#^xF
	cmpc3	#2, @#S1, @#S2
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
; CMPC5, both empty
	movb	#^x5A, @#S1+0
	movb	#^x5A, @#S2+0
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#6, r5
	bispsw	#^xF
	cmpc5	#0, @#S1, #^x2B, #0, @#S2
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
; CMPC5, string 1 empty, string 2 all fill
	movb	#^x5A, @#S1+0
	movb	#^x2B, @#S2+0
	movb	#^x2B, @#S2+1
	movb	#^x2B, @#S2+2
	movb	#^x5A, @#S2+3
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#7, r5
	bispsw	#^xF
	cmpc5	#0, @#S1, #^x2B, #3, @#S2
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
; CMPC5, string 1 empty, fill 2B : 41
	movb	#^x5A, @#S1+0
	movb	#^x2B, @#S2+0
	movb	#^x41, @#S2+1
	movb	#^x5A, @#S2+2
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#8, r5
	bispsw	#^xF
	cmpc5	#0, @#S1, #^x2B, #2, @#S2
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
; CMPC5, string 2 empty, 42 : fill 41
	movb	#^x41, @#S1+0
	movb	#^x42, @#S1+1
	movb	#^x43, @#S1+2
	movb	#^x5A, @#S1+3
	movb	#^x5A, @#S2+0
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#9, r5
	bispsw	#^xF
	cmpc5	#3, @#S1, #^x41, #0, @#S2
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
; CMPC5, A : A++ with fill + (EVKAB test 139)
	movb	#^x41, @#S1+0
	movb	#^x5A, @#S1+1
	movb	#^x41, @#S2+0
	movb	#^x2B, @#S2+1
	movb	#^x2B, @#S2+2
	movb	#^x5A, @#S2+3
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#10, r5
	bispsw	#^xF
	cmpc5	#1, @#S1, #^x2B, #3, @#S2
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
; CMPC5, A++ : A with fill +
	movb	#^x41, @#S1+0
	movb	#^x2B, @#S1+1
	movb	#^x2B, @#S1+2
	movb	#^x5A, @#S1+3
	movb	#^x41, @#S2+0
	movb	#^x5A, @#S2+1
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#11, r5
	bispsw	#^xF
	cmpc5	#3, @#S1, #^x2B, #1, @#S2
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
; CMPC5, fill 01 : 80
	movb	#^x5A, @#S1+0
	movb	#^x80, @#S2+0
	movb	#^x5A, @#S2+1
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#12, r5
	bispsw	#^xF
	cmpc5	#0, @#S1, #^x01, #1, @#S2
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
; CMPC5, 90 : fill 10
	movb	#^x41, @#S1+0
	movb	#^x90, @#S1+1
	movb	#^x5A, @#S1+2
	movb	#^x41, @#S2+0
	movb	#^x5A, @#S2+1
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#13, r5
	bispsw	#^xF
	cmpc5	#2, @#S1, #^x10, #1, @#S2
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
; CMPC5, fill FF : 7F
	movb	#^x41, @#S1+0
	movb	#^x5A, @#S1+1
	movb	#^x41, @#S2+0
	movb	#^x7F, @#S2+1
	movb	#^x5A, @#S2+2
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#14, r5
	bispsw	#^xF
	cmpc5	#1, @#S1, #^xFF, #2, @#S2
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
; CMPC5, differ in the common part
	movb	#^x41, @#S1+0
	movb	#^x42, @#S1+1
	movb	#^x43, @#S1+2
	movb	#^x5A, @#S1+3
	movb	#^x41, @#S2+0
	movb	#^x58, @#S2+1
	movb	#^x5A, @#S2+2
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#15, r5
	bispsw	#^xF
	cmpc5	#3, @#S1, #^x20, #2, @#S2
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
; CMPC5, longer string 1, equal with the fill
	movb	#^x31, @#S1+0
	movb	#^x32, @#S1+1
	movb	#^x20, @#S1+2
	movb	#^x20, @#S1+3
	movb	#^x5A, @#S1+4
	movb	#^x31, @#S2+0
	movb	#^x32, @#S2+1
	movb	#^x5A, @#S2+2
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#16, r5
	bispsw	#^xF
	cmpc5	#4, @#S1, #^x20, #2, @#S2
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
; across an invalid page: 8DFC..8E03 against 8FFC..9003, pages 47 and 48
; invalid (the second operand of each faults part way)
	movl	#^x44434241, @#S0+^x8DFC
	movl	#^x48474645, @#S0+^x8E00
	movl	#^x44434241, @#S0+^x8FFC
	movl	#^x48474646, @#S0+^x9000
	bicl2	#PTE_V, @#S0+SPT+<^x47*4>
	bicl2	#PTE_V, @#S0+SPT+<^x48*4>
	mtpr	#S0+^x8E00, #TBIS
	mtpr	#S0+^x9000, #TBIS
	cmpc3	#8, @#S0+^x8DFC, @#S0+^x8FFC
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	bicl2	#PTE_V, @#S0+SPT+<^x47*4>
	bicl2	#PTE_V, @#S0+SPT+<^x48*4>
	mtpr	#S0+^x8E00, #TBIS
	mtpr	#S0+^x9000, #TBIS
	cmpc5	#8, @#S0+^x8DFC, #^x46, #6, @#S0+^x8FFC
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	halt
