; t08_autoinc - a fault undoes the register changes of the faulting
; instruction's operand specifiers: (Rn)+, -(Rn), @(Rn)+; after the fix-up
; each is done once. (SP: see t09_user, the stack must stay valid here.)
;@ dump=18000:14 dump=8800:4 dump=8C00:4
	.include "mmsetup.inc"
test:
	movl	#S0+fix_valid, r10
	movl	#S0+^x8000, r1
	movl	#^x1234, (r1)
	movl	#S0+^x8800, r2
	bicl2	#PTE_V, @#S0+SPT+<^x44*4>
	mtpr	#S0+^x8800, #TBIS
	movl	(r1)+, (r2)+			; fault on the destination
	movl	#S0+^x8C08, r3
	bicl2	#PTE_V, @#S0+SPT+<^x46*4>
	mtpr	#S0+^x8C00, #TBIS
	addl3	#5, -(r1), -(r3)		; fault on the destination
	movl	#S0+^x8008, r4
	movl	#S0+^x8C04, (r4)
	bicl2	#PTE_V, @#S0+SPT+<^x46*4>
	mtpr	#S0+^x8C00, #TBIS
	movl	#^x77, @(r4)+			; fault on the deferred address
	halt
