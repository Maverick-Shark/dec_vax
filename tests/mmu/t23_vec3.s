; t23_vec3 - an exception through an SCB vector with bits 1:0 = 3 halts the
; processor (8600 halt code 7; the reference simulator stops too). Here a
; reserved operand
; fault (BISPSW with must-be-zero bits) through vector 18.
;@ dump=18000:4 halt=7 board=skip
	.include "mmsetup.inc"
test:
	movl	#S0+resop_h+3, @#^x18
	movl	#5, r5
	bispsw	#^x100				; reserved operand fault
	movl	#^xBAD, r9			; not reached
	halt
