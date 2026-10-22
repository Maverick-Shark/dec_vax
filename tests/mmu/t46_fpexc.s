; t46_fpexc - floating point exceptions in detail. Faults (SRM 6.4):
; floating overflow (type 8), divide by zero (9), underflow with PSL<FU> set
; (A) and the reserved operand (SCB 18) push the PC of the instruction, and
; the registers changed by its operand specifiers ((Rn)+, -(Rn)) are put
; back; with PSL<FU> clear an underflow stores 0. With PSL<T> set the fault
; frame has PSL<TP> clear. A D, G or H destination running into an invalid
; page faults before anything is stored; so does EMOD's fraction
; destination, before the integer is stored. POLY with a coefficient on an
; invalid page faults with R0-R5 as they were and runs again once the page
; is valid. CVTRFL rounds halves away from zero; MOVF of a "dirty" zero (sign
; 0, exponent 0, fraction bits set) stores 0. Compared with the reference
; simulator.
;@ dump=8000:80 dump=8DF0:10 dump=18000:100 page=180B8,180D4
	.include "mmsetup.inc"
D	= S0+^x8000
test:
	movl	#S0+arith_h, @#^x34
	movl	#S0+trace_h, @#^x28
	movl	#S0+fix_skip, r10
; floating overflow: (R1)+ and (R2)+ put back
	movab	big, r1
	movab	@#D, r2
	movab	ov1, r8
	mulf3	(r1)+, (r1)+, (r2)+
ov1:	movl	r1, (r11)+
	movl	r2, (r11)+
	movab	ov2, r8
	muld3	(r1)+, I^#^x0000FFFF, -(r2)
ov2:	movl	r1, (r11)+
	movl	r2, (r11)+
; divide by zero, G and H
	movab	dz1, r8
	divg3	#0, S^#0.5, @#D
dz1:	movab	dz2, r8
	clro	r4
	divh2	r4, @#D+^x10
dz2:
; underflow: FU set faults, FU clear stores 0
	movab	small, r1
	bispsw	#^x40
	movab	un1, r8
	mulf3	(r1), (r1)+, @#D+^x20
un1:	movl	r1, (r11)+
	bicpsw	#^x40
	movl	#-1, @#D+^x20
	mulf3	(r1), (r1)+, @#D+^x20
	movpsl	(r11)+
	movl	r1, (r11)+
; reserved operand: SCB 18, PC at the instruction, (R1)+ put back
	movab	rsv, r1
	movab	ro1, r8
	addf3	(r1)+, (r1)+, @#D+^x24
ro1:	movl	r1, (r11)+
	movab	ro2, r8
	cvthf	(r1)+, @#D+^x24
ro2:	movl	r1, (r11)+
; trace: the fault frame has TP clear; the trace handler logs too
	movab	tr1, r8
	movab	big, r1
	bispsw	#^x10
	mulf2	(r1), (r1)
tr1:	bicpsw	#^x10
	movl	#^x7777, (r11)+
; CVTRFL: halves away from zero
	cvtrfl	#2.5, (r11)+
	cvtrfl	#-2.5, (r11)+
	cvtrfl	#0.5, (r11)+
	cvtfl	#-2.5, (r11)+
	cvtrdl	#-1.5, (r11)+
; a dirty zero
	movf	I^#^x12340070, @#D+^x28
	movpsl	(r11)+
	movd	I^#^x0000123400000070, @#D+^x2C
; destinations running into an invalid page (47): nothing stored
	movq	#-1, @#S0+^x8DF8
	movq	#-1, @#S0+^x8E00
	bicl2	#PTE_V, @#S0+SPT+<^x47*4>
	mtpr	#S0+^x8E00, #TBIS
	movl	#S0+fix_peek, r10
	addd3	#1.0, #2.0, @#S0+^x8DFC		; D across the boundary
	addg3	#1.0, #2.0, @#S0+^x8DF8		; G on page 46: no fault
	bicl2	#PTE_V, @#S0+SPT+<^x47*4>
	mtpr	#S0+^x8E00, #TBIS
	addh3	#1.0, #2.0, @#S0+^x8DF8		; H across
	movq	#-1, @#S0+^x8DF8
	bicl2	#PTE_V, @#S0+SPT+<^x47*4>
	mtpr	#S0+^x8E00, #TBIS
	emodd	#1.5, #0, #3.0, @#S0+^x8DF8, @#S0+^x8DFC	; fraction across
; POLY with its third coefficient on an invalid page (47)
	movab	pt, r6
	movc3	#24, (r6), @#S0+^x8DF0		; the table, the third on page 47
	bicl2	#PTE_V, @#S0+SPT+<^x47*4>
	mtpr	#S0+^x8E00, #TBIS
	movl	#S0+fix_valid, r10
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#^x55555555, r4
	movl	#^x66666666, r5
	polyd	#2.0, #2, @#S0+^x8DF0
	movpsl	(r11)+
	movl	r0, (r11)+
	movl	r1, (r11)+
	movl	r2, (r11)+
	movl	r3, (r11)+
	movl	r4, (r11)+
	movl	r5, (r11)+
	clrl	r10
	halt

; arithmetic exception: type code, PC, PSL; go on at R8
	.align	4
arith_h:
	movl	(sp)+, (r11)+
	movl	(sp), (r11)+
	movl	4(sp), (r11)+
	movl	r8, (sp)
	rei
; trace fault: marker, PC, PSL
	.align	4
trace_h:
	movl	#^x7E7E0028, (r11)+
	movl	(sp), (r11)+
	movl	4(sp), (r11)+
	rei
; fix-up: log the destination's first longwords, make page 47 valid
fix_peek:
	movl	@#S0+^x8DF8, (r11)+
	movl	@#S0+^x8DFC, (r11)+
	bisl2	#PTE_V, @#S0+SPT+<^x47*4>
	rsb

	.align	4
big:	.f_floating	1.0E38, 1.0E38
	.d_floating	1.0E38
small:	.f_floating	1.0E-30, 1.0E-30
rsv:	.long	^x00008000, ^x00004080
	.long	^x00008000, 0, 0, 0
pt:	.d_floating	1.0, -3.0, 0.25
