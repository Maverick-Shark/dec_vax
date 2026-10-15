; t03_acv - access-control violation: write to a kernel read-only page,
; read and write with the protection "no access"; ACV wins over TNV.
;@ dump=18000:14 dump=8A00:2 dump=10114:2
	.include "mmsetup.inc"
test:
	bicl2	#^x78000000, @#S0+SPT+<^x45*4>	; page 45: KR
	bisl2	#PR_KR, @#S0+SPT+<^x45*4>
	bicl2	#^x78000000+PTE_V, @#S0+SPT+<^x46*4>	; page 46: NA and invalid
	mtpr	#S0+^x8A00, #TBIS
	mtpr	#S0+^x8C00, #TBIS
	movl	#S0+fix_prot, r10
	movl	@#S0+^x8A00, r3		; read KR page: fine
	movl	#^x1234, @#S0+^x8A00	; write: ACV, parameter 4
	movl	@#S0+^x8C00, r4		; NA and invalid: ACV, parameter 0
	halt
fix_prot:				; both pages KW and valid
	bicl2	#^x78000000, @#S0+SPT+<^x45*4>
	bisl2	#PR_KW, @#S0+SPT+<^x45*4>
	bisl2	#PR_KW+PTE_V, @#S0+SPT+<^x46*4>
	mtpr	#S0+^x8A00, #TBIS
	mtpr	#S0+^x8C00, #TBIS
	rsb
