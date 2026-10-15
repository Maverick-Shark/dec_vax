; t11_mbit - PTE<M>: set by a write that hits a TB entry loaded by a read,
; by a modify operand, by an unaligned write; not by reads.
;@ dump=10130:5
	.include "mmsetup.inc"
test:
	movl	#S0+SPT+<^x4C*4>, r0
	bicl2	#PTE_M, (r0)			; pages 4C..50: M clear
	bicl2	#PTE_M, 4(r0)
	bicl2	#PTE_M, 8(r0)
	bicl2	#PTE_M, 12(r0)
	bicl2	#PTE_M, 16(r0)
	mtpr	#0, #TBIA
	movl	@#S0+^x9800, r1			; page 4C: read, TB loaded with M clear
	movl	r1, @#S0+^x9800			; write: M set in the PTE
	incl	@#S0+^x9A00			; page 4D: modify
	movl	@#S0+^x9C00, r2			; page 4E: read only
	movl	r2, @#S0+^x9FFE			; pages 4F and 50: unaligned write
	halt
