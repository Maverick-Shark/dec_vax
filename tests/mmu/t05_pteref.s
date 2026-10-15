; t05_pteref - faults on the reference to a process page table: the system
; page that holds the P0 page table is invalid (TNV, parameter bit 1); a P0
; address whose PTE lies beyond SLR (ACV, parameter bits 1 and 0).
;@ dump=18000:A dump=10120:1
	.include "mmsetup.inc"
test:
	bicl2	#PTE_V, @#S0+SPT+<^x90*4>	; S0 page 90 holds the P0 page table
	mtpr	#0, #TBIA
	movl	#S0+fix_p0pt, r10
	movl	@#^x8000, r3		; P0 page 40: its PTE is in S0 page 90
	mtpr	#^x4000, #P0LR
	movl	#S0+fix_skip, r10
	movab	pr2, r8
	movl	@#^x700000, r4		; P0 page 3800: PTE at S0+20000, beyond SLR
pr2:	halt
fix_p0pt:
	bisl2	#PTE_V, @#S0+SPT+<^x90*4>
	rsb
