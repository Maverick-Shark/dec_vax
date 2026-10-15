; t04_lnv - length violations: S0 beyond SLR, P0 beyond P0LR, P1 below
; P1LR, S1 (always). Access-control violation with parameter bit 0.
;@ dump=18000:14
	.include "mmsetup.inc"
test:
	movl	#S0+fix_skip, r10
	movab	lnv1, r8
	movl	@#S0+^x20000, r3	; S0 page 100: SLR is 100
lnv1:	movab	lnv2, r8
	movl	@#^x20000, r3		; P0 page 100: P0LR is 100
lnv2:	movab	lnv3, r8
	movl	@#^x40000000, r3	; P1 page 0: below P1LR
lnv3:	movab	lnv4, r8
	movl	r3, @#^xC0000000	; S1, write
lnv4:	halt
