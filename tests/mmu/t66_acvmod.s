; t66_acvmod - access-control violation on a modify operand: ADDL2 R2,(R1)
; on a page the current mode may read but not write is a fault on the
; operand's access, with "intended access: write" in the parameter, the
; operand's address and the PC of the ADDL2 (SRM 4.9, 4.8: a modify operand
; is checked for write access when it is read). Also INCL, BISL2 and ADDL3
; with a destination on the page. Then from user mode, the loop with which
; NetBSD's ld.elf_so relocates a shared library (ADDL3 R2,(R0),R1; ADDL2
; R2,(R1); ADDL2 #12,R0; CMPL R0,R3; BLSSU) on a UR page, as a page that is
; still copy-on-write is mapped.
;@ dump=18000:40 dump=8A00:4 dump=8C00:2 dump=8E00:4
	.include "mmsetup.inc"
test:
	movl	#S0+chmk_h, @#^x40
	movl	#S0+fix_prot, r10
	movl	#S0+^x8A00, r1
	movl	#5, r2
	jsb	@#S0+protect
	addl2	r2, (r1)			; ACV, parameter 4, VA 8A00
	jsb	@#S0+protect
	incl	(r1)
	jsb	@#S0+protect
	bisl2	#^x100, (r1)
	jsb	@#S0+protect
	addl3	r2, (r1), 4(r1)		; the source reads, the destination faults
	jsb	@#S0+protect
	movl	(r1), r3			; a read: no fault
	movl	4(r1), r4
; user mode: P0 pages 46 (8C00) and 47 (8E00) UR
	bicl2	#^x78000000, @#S0+P0PT+<^x46*4>
	bisl2	#PR_UR, @#S0+P0PT+<^x46*4>
	bicl2	#^x78000000, @#S0+P0PT+<^x47*4>
	bisl2	#PR_UR, @#S0+P0PT+<^x47*4>
	mtpr	#^x8C00, #TBIS
	mtpr	#^x8E00, #TBIS
	bicl2	#^x78000000, @#S0+P0PT+<9*4>	; the user code's page (9): UR, as
	bisl2	#PR_UR, @#S0+P0PT+<9*4>		; a program's text is
	mtpr	#^x1200, #TBIS
	mtpr	#^x80000000, #USP
	pushl	#^x03C00000			; PSL: user mode, previous user
	pushl	#user				; P0 address = physical address
	rei
user:	movl	#S0+fix_p46, r10
	movl	#^x11, @#^x8C00			; ACV: a plain write first
	movl	@#^x8C00, r5
	movl	#S0+fix_p47, r10
	movab	rtab, r0
	addl3	#36, r0, r3
	movl	#^x8E00, r2			; "relocbase"
rloop:	addl3	r2, (r0), r1
	addl2	r2, (r1)			; the first one: ACV, parameter 4
	addl2	#12, r0
	cmpl	r0, r3
	blssu	rloop
	movl	@#^x8E04, r6
	chmk	#7
	halt					; not reached
	.align	2
rtab:	.long	0, 0, 0, 4, 0, 0, 8, 0, 0
protect:				; page 45: KR
	bicl2	#^x78000000, @#S0+SPT+<^x45*4>
	bisl2	#PR_KR, @#S0+SPT+<^x45*4>
	mtpr	#S0+^x8A00, #TBIS
	rsb
fix_prot:				; page 45: KW
	bicl2	#^x78000000, @#S0+SPT+<^x45*4>
	bisl2	#PR_KW, @#S0+SPT+<^x45*4>
	mtpr	#S0+^x8A00, #TBIS
	rsb
fix_p46:				; P0 page 46: UW
	bicl2	#^x78000000, @#S0+P0PT+<^x46*4>
	bisl2	#PR_UW, @#S0+P0PT+<^x46*4>
	mtpr	#^x8C00, #TBIS
	rsb
fix_p47:				; P0 page 47: UW
	bicl2	#^x78000000, @#S0+P0PT+<^x47*4>
	bisl2	#PR_UW, @#S0+P0PT+<^x47*4>
	mtpr	#^x8E00, #TBIS
	rsb
	.align	4
chmk_h:	movl	#^x5E5E0040, (r11)+
	movl	(sp), (r11)+			; code
	movl	4(sp), (r11)+			; PC
	movl	8(sp), (r11)+			; PSL
	halt
