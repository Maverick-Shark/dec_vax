; t10_ksnv - a fault in user mode while the kernel stack is not valid: the
; frame push fails, kernel stack not valid (SCB 08) on the interrupt stack.
; SRM 5.6 note 5: the PSL and PC pushed are the ones the original exception
; would have pushed: the user PSL 03C00000, and the new PSL takes PRV_MOD
; from it (04DF0000). simh pushes the kernel PSL it had already loaded
; (00C00000) and so ends with PRV_MOD = kernel (041F0000); the RTL values
; are checked against the SRM instead.
;@ dump=18000:4 dump=DFF0:4 ignore=PSL
;@ rtl=18008:03C00000,1800C:04DF0000,DFFC:03C00000
	.include "mmsetup.inc"
test:
	bicl2	#PTE_V, @#S0+SPT+<^x77*4>	; kernel stack page (KSP = F000)
	mtpr	#0, #TBIA
	mtpr	#^x7FFFFE00, #USP
	pushl	#^x03C00000
	pushl	#user
	rei
user:	movl	#1, r1
	movl	@#S0+^x8000, r2			; KW page: ACV, frame on the kernel stack
	halt					; not reached
