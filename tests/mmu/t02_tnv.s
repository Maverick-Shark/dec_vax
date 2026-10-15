; t02_tnv - translation not valid on a write and on a read: the frame
; (parameter, VA, PC, PSL), and the restart after the fix-up, with the
; auto-increment of the faulting instruction undone and done once.
;@ dump=18000:A dump=8800:2 dump=10110:2
	.include "mmsetup.inc"
test:
	bicl2	#PTE_V, @#S0+SPT+<^x44*4>	; S0 page 44 (physical 8800): invalid
	bicl2	#PTE_V, @#S0+SPT+<^x45*4>	; S0 page 45 (physical 8A00): invalid
	mtpr	#S0+^x8800, #TBIS
	mtpr	#S0+^x8A00, #TBIS
	movl	#S0+fix_valid, r10
	movl	#S0+^x8800, r1
	movl	#^xCAFE, r2
	movl	r2, (r1)+		; TNV on the write, page 44
	movl	#S0+^x8A00, r4
	movl	(r4)+, r3		; TNV on the read, page 45
	halt
