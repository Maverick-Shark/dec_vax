; t64_cmmm - PDP-11 compatibility mode with memory management on: its
; references are made in user mode through the P0 page table, and a
; translation not valid or access-control violation in the middle of an
; instruction puts the instruction back (registers, PC, PSL) for the
; handler, which fixes the page; the instruction then runs again:
;   1  the instruction fetch from an invalid page
;   2  the index word on the next page, invalid (an instruction across a
;      page boundary)
;   3  MOV (R1)+,@#a, a on an invalid page: written at the end, R1 back
;   4  INC of a word on a user read-only page: ACV with write intent
;   5  a read from a kernel-write page: ACV, user mode
;   6  JSR's push on an invalid stack page: SP back
;   7  an odd word address on an invalid page: the odd address abort, not
;      a translation fault
; The memory management handler (mmsetup.inc) logs parameter, VA, PC, PSL
; and its PSL and calls fix_p0 (the page made valid, UW). The compatibility
; mode handler logs code, PC, PSL, R0-R6, steps over BPT and goes back to
; the driver (R8) at EMT 377 or the odd address abort.
;@ dump=18000:100 dump=9000:2 dump=9200:2 dump=9400:2 dump=9DFC:2
	.include "mmsetup.inc"
CMPSL	= ^x83C00000
test:
	movl	#S0+cmexc, @#^x30
	movl	#S0+fix_p0, r10
	clrl	r0
	clrl	r1
	clrl	r2
	clrl	r3
	clrl	r4
	clrl	r5
	movl	#^xA000, r6
; 1
	bicl2	#PTE_V, @#S0+P0PT+<^x40*4>
	mtpr	#^x8000, #TBIS
	movab	b2, r8
	pushl	#CMPSL
	pushl	#^x8000
	rei
; 2
b2:	bicl2	#PTE_V, @#S0+P0PT+<^x42*4>
	mtpr	#^x8400, #TBIS
	movab	b3, r8
	pushl	#CMPSL
	pushl	#^x83F8
	rei
; 3
b3:	bicl2	#PTE_V, @#S0+P0PT+<^x48*4>
	mtpr	#^x9000, #TBIS
	movab	b4, r8
	pushl	#CMPSL
	pushl	#^x8600
	rei
; 4
b4:	bicl2	#^x78000000, @#S0+P0PT+<^x4A*4>
	bisl2	#PR_UR, @#S0+P0PT+<^x4A*4>
	mtpr	#^x9400, #TBIS
	movab	b5, r8
	pushl	#CMPSL
	pushl	#^x8800
	rei
; 5
b5:	bicl2	#^x78000000, @#S0+P0PT+<^x4B*4>
	bisl2	#PR_KW, @#S0+P0PT+<^x4B*4>
	mtpr	#^x9600, #TBIS
	movab	b6, r8
	pushl	#CMPSL
	pushl	#^x8A00
	rei
; 6
b6:	bicl2	#PTE_V, @#S0+P0PT+<^x4F*4>
	mtpr	#^x9E00, #TBIS
	movab	b7, r8
	pushl	#CMPSL
	pushl	#^x8C00
	rei
; 7
b7:	bicl2	#PTE_V, @#S0+P0PT+<^x4C*4>
	mtpr	#^x9800, #TBIS
	movab	b8, r8
	pushl	#CMPSL
	pushl	#^x8E00
	rei
b8:	halt

; the compatibility mode exception handler
	.align	4
cmexc:	movl	(sp)+, r9		; the code
	movl	r9, (r11)+
	movl	(sp), (r11)+		; PC
	movl	4(sp), (r11)+		; PSL
	movl	r0, (r11)+
	movl	r1, (r11)+
	movl	r2, (r11)+
	movl	r3, (r11)+
	movl	r4, (r11)+
	movl	r5, (r11)+
	movl	r6, (r11)+
	cmpl	r9, #1			; BPT: on
	bneq	cm1
	addl2	#2, (sp)
	rei
cm1:	clrl	r9
	addl2	#8, sp			; EMT 377, odd address: the next part
	jmp	(r8)

; the P0 page of the logged fault address: valid, UW
fix_p0:	pushl	r0
	movl	-16(r11), r0
	extzv	#9, #21, r0, r0
	bicl2	#^x78000000, @#S0+P0PT[r0]
	bisl2	#PTE_V+PR_UW, @#S0+P0PT[r0]
	ashl	#9, r0, r0
	mtpr	r0, #TBIS
	movl	(sp)+, r0
	rsb

; ============================================================ compat code
	.org	^x8000
	.pdp11
	mov	#1, r0			; 1: fetched from an invalid page
	bpt
	emt	^o377

	.org	^x83F8
	mov	#^x9200, r1		; 2: the index word at 8400
	nop
	mov	^x10(r1), r0
	bpt
	emt	^o377

	.org	^x8600
	mov	#^x9200, r1		; 3: the destination on an invalid page
	mov	(r1)+, @#^x9000
	bpt
	emt	^o377

	.org	^x8800
	mov	#^x9400, r2		; 4: a user read-only page
	inc	(r2)
	bpt
	emt	^o377

	.org	^x8A00
	tst	@#^x9600		; 5: a kernel-write page
	bpt
	emt	^o377

	.org	^x8C00
	mov	#^x9E02, sp		; 6: the push at 9E00, an invalid page
	jsr	pc, sub6
	bpt
	emt	^o377
sub6:	mov	sp, r3
	rts	pc

	.org	^x8E00
	mov	#^x9801, r4		; 7: odd, and the page is invalid
	tst	(r4)
	bpt
	emt	^o377

	.vax
	.org	^x9000
	.word	^x1111, ^x2222
	.org	^x9200
	.word	^x5555, ^x6666, ^x7777, ^x8888, ^x9999, ^xAAAA, ^xBBBB, ^xCCCC
	.word	^xDDDD, ^xEEEE
	.org	^x9400
	.word	^x7FFF
	.org	^x9600
	.word	^x8000

; mkboard.py (software/mmutest.bin) appends its code and table: out of the
; test's way, mapped in S0 (where the test ends), near its HALTs
	.org	^x4000
