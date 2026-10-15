; t13_movc - MOVC3 and MOVC5 without faults (the rewritten engine):
; forward, backward with overlap, fill, source longer, destination longer,
; zero lengths; registers R0-R5 and condition codes after each.
;@ dump=8000:20 dump=18000:30
	.include "mmsetup.inc"
test:
	movl	#S0+^x8000, r6
	movl	#^x03020100, (r6)
	movl	#^x07060504, 4(r6)
	movl	#^x0B0A0908, 8(r6)
	movl	#^x0F0E0D0C, 12(r6)
	movl	#S0+LOG, r7
	movc3	#16, (r6), 16(r6)		; forward
	bsbb	regs
	movc3	#12, (r6), 2(r6)		; backward, overlapping
	bsbb	regs
	movc3	#12, 2(r6), (r6)		; forward, overlapping
	bsbb	regs
	movc5	#3, (r6), #^xEE, #9, 32(r6)	; fill
	bsbb	regs
	movc5	#9, (r6), #^xEE, #3, 48(r6)	; source longer
	bsbb	regs
	movc5	#4, 8(r6), #^x55, #10, 4(r6)	; backward with fill
	bsbb	regs
	movc5	#0, (r6), #^x77, #5, 64(r6)	; no source
	bsbb	regs
	movc3	#0, (r6), 80(r6)		; nothing
	bsbb	regs
	halt
; log R0-R5 and the PSL
regs:	movpsl	(r7)+
	movl	r0, (r7)+
	movl	r1, (r7)+
	movl	r2, (r7)+
	movl	r3, (r7)+
	movl	r4, (r7)+
	rsb
