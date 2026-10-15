; t01_xlate - translation through S0 and P0, M bits, TBCHK, TBIS
;@ dump=8000:2 dump=10100:1 dump=12100:1 dump=18000:4
	.include "mmsetup.inc"
test:
	movl	#^x11223344, @#S0+^x8000	; write through S0 page 40
	movl	@#^x8000, r2			; read it through P0 page 40
	movl	@#S0+^x8004, r3			; read through S0
	movl	#^x55667788, @#^x8004		; write through P0
	movl	@#S0+^x8004, r4
	mtpr	#S0+^x8000, #TBCHK		; in the TB: V set
	movpsl	r5
	mtpr	#S0+^x8000, #TBIS
	mtpr	#S0+^x8000, #TBCHK		; flushed: V clear
	movpsl	r6
	mfpr	#MAPEN, r7
	mfpr	#P0LR, r8
	mfpr	#SLR, r9
	halt
