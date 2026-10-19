; t24_chmvec - a CHMx whose SCB vector has bits 1:0 set halts the processor
; (8600 halt code B, DEC STD 032 table B-24), with PC at the CHMx and
; nothing changed. The reference simulator ignores the bits and goes to the
; handler, so this test runs on the RTL only.
;@ dump=18000:4 halt=B board=skip noref expect=R5:5,R6:0,R9:0
	.include "mmsetup.inc"
test:
	movl	#S0+chmk_h+1, @#^x40
	movl	#5, r5
	clrl	r6
	pushl	#^x001F0000			; to the kernel stack
	pushab	kern
	rei
kern:	chmk	#1
	movl	#^xBAD, r9			; not reached
	halt
	.align	4
chmk_h:	movl	#^xBAD, r6
	halt
