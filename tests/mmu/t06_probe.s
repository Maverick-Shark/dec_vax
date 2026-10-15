; t06_probe - PROBER/PROBEW: mode is the larger of the operand and
; PSL<PRV_MOD>, first and last byte checked, valid bit ignored, length
; violation is "not accessible".
;@ dump=18000:5
	.include "mmsetup.inc"
test:
	bicl2	#^x78000000, @#S0+SPT+<^x46*4>	; page 46: UR
	bisl2	#PR_UR, @#S0+SPT+<^x46*4>
	bicl2	#^x78000000, @#S0+SPT+<^x47*4>	; page 47: NA
	bicl2	#^x78000000+PTE_V, @#S0+SPT+<^x48*4> ; page 48: UW, invalid
	bisl2	#PR_UW, @#S0+SPT+<^x48*4>
	mtpr	#0, #TBIA
	prober	#3, #4, @#S0+^x8C00	; UR page, user read: yes
	movpsl	r1
	probew	#3, #4, @#S0+^x8C00	; UR page, user write: no
	movpsl	r2
	prober	#3, #4, @#S0+^x8000	; KW page, user: no
	movpsl	r3
	prober	#0, #4, @#S0+^x8000	; KW page, mode 0 (PRV_MOD kernel): yes
	movpsl	r4
	prober	#0, #^x200, @#S0+^x8DFF	; UR page 46 + NA page 47: no
	movpsl	r5
	probew	#3, #8, @#S0+^x9000	; UW page 48, not valid: yes
	movpsl	r6
	prober	#0, #0, @#S0+^x8C01	; length 0: bytes 8C01 and 8C00
	movpsl	r7
	prober	#0, #4, @#S0+^x20000	; beyond SLR: no
	movpsl	r8
	prober	#0, #4, @#^x40000000	; P1 below P1LR: no
	movpsl	r9
	halt
