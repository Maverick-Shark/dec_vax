; t16_isnv - a fault while the frame is pushed on the interrupt stack halts
; the processor (SRM 5.6 note 6; 8600 halt code 4, "interrupt stack
; invalid"). simh stops with its own message; PC and PSL are compared.
;@ dump=18000:2
;@ board=halt halt=4
	.include "mmsetup.inc"
test:
	movl	#S0+^x9000, sp			; interrupt stack in page 48
	bicl2	#PTE_V, @#S0+SPT+<^x47*4>	; page 47 (below SP): invalid
	bicl2	#PTE_V, @#S0+SPT+<^x46*4>	; page 46: invalid
	mtpr	#0, #TBIA
	movl	#5, r1
	movl	@#S0+^x8C00, r2			; TNV, the frame goes below 9000
	halt					; not reached
