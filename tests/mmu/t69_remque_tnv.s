; t69_remque_tnv - REMQUE whose successor's page is not valid: the write of
; succ.blink takes translation not valid, the handler makes the page valid
; and REI restarts the REMQUE. Nothing may have been written before the
; fault (SRM: the instruction is restartable), or the restart takes the
; entry after the one it should (VMS 7.3 STARTUP hung on this).
; Queue H (S0 page 40) -> E1 (page 41) -> E2 (page 42) -> H; page 42 invalid.
;@ dump=8000:2
;@ dump=8200:2
;@ dump=8400:2
;@ dump=18000:5
	.include "mmsetup.inc"
test:
	moval	@#S0+^x8000, r1		; H
	moval	@#S0+^x8200, r2		; E1
	moval	@#S0+^x8400, r3		; E2
	movl	r2, (r1)		; H:  flink E1, blink E2
	movl	r3, 4(r1)
	movl	r3, (r2)		; E1: flink E2, blink H
	movl	r1, 4(r2)
	movl	r1, (r3)		; E2: flink H,  blink E1
	movl	r2, 4(r3)
	bicl2	#PTE_V, @#S0+SPT+<^x42*4>
	mtpr	#S0+^x8400, #TBIS
	movl	#S0+fix_valid, r10
	clrl	r0
	remque	@0(r1), r0
	movl	r0, r4			; the entry removed: E1
	clrl	r0
	halt
