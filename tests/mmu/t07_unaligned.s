; t07_unaligned - accesses that cross a page boundary: the fault is
; reported for the second page, and a write writes nothing until both pages
; are known to be writable.
;@ dump=18000:A dump=18F00:2 dump=93F8:4 dump=10124:3 page=18004,18018
	.include "mmsetup.inc"
test:
	movl	#^x11111111, @#S0+^x93FC	; page 49, last longword
	movl	#^x22222222, @#S0+^x9400	; page 4A, first longword
	bicl2	#^x78000000, @#S0+SPT+<^x4A*4>	; page 4A: KR
	bisl2	#PR_KR, @#S0+SPT+<^x4A*4>
	mtpr	#S0+^x9400, #TBIS
	movl	#S0+fix_look, r10
	movl	@#S0+^x93FE, r2			; read across: fine
	movl	#^xAABBCCDD, @#S0+^x93FE	; write across: ACV on page 4A
	movl	@#S0+^x93FE, r3
	bicl2	#PTE_V, @#S0+SPT+<^x4B*4>	; page 4B invalid
	mtpr	#S0+^x9600, #TBIS
	movl	#S0+fix_valid, r10
	movw	@#S0+^x95FF, r4			; word across 4A/4B: TNV on 4B
	movw	#^x5566, @#S0+^x95FF
	movl	@#S0+^x95FC, r5
	halt
; log what the faulting write left in memory (nothing yet), then make it KW
fix_look:
	movl	@#S0+^x93FC, @#S0+LOG+^xF00
	movl	@#S0+^x9400, @#S0+LOG+^xF04
	jmp	fix_kw

