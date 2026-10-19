; t22_chmis - a CHMx on the interrupt stack halts the processor (SRM chapter
; 5, CHM; 8600 halt code A), with PC at the CHMx and nothing changed. The
; reference simulator stops there as well.
;@ dump=18000:4 halt=A board=skip
	.include "mmsetup.inc"
test:
	movl	#S0+chmk_h, @#^x40
	movl	#5, r5
	movl	sp, r6
	chmk	#1				; still on the interrupt stack
	movl	#^xBAD, r9			; not reached
	halt
	.align	4
chmk_h:	movl	#^xBAD, r9
	halt
