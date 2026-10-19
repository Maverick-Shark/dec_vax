; t37_negbase - bit field instructions whose base address has bits 31:30
; set (FFFF0000) and whose position takes the field back into P0 space
; (base + pos/8 wraps around to 8000): the microcode must not take such a
; base for a register (EVKAB test 3 does this with BBC). BBS, BBC, BBSS,
; BBCC, INSV, EXTV, EXTZV, CMPV, FFS on the field; each logs the PSL and a
; marker for the branches; the data longword is dumped. Then FFC and FFS
; with a field of size 0 (EVKAB test 93), the reserved operand and reserved
; addressing mode cases of the bit fields, and fields at the end of a page
; that is followed by an invalid one.
;@ dump=8000:2 dump=18000:40
	.include "mmsetup.inc"
test:
	movl	#^x12345678, @#^x8000		; P0 page 40 = physical 8000
	movl	#^xFFFF0000, r3
	bbs	#^xC0003, (r3), b1		; bit 3 of 78: set
	movl	#^xA0, (r11)+
	brb	b1x
b1:	movl	#^xA1, (r11)+
b1x:	bbc	#^xC0002, (r3), b2		; bit 2 of 78: clear
	movl	#^xA0, (r11)+
	brb	b2x
b2:	movl	#^xA1, (r11)+
b2x:	bbss	#^xC0000, (r3), b3		; bit 0: clear, set it
	movl	#^xA0, (r11)+
	brb	b3x
b3:	movl	#^xA1, (r11)+
b3x:	bbcc	#^xC0006, (r3), b4		; bit 6: set, clear it
	movl	#^xA0, (r11)+
	brb	b4x
b4:	movl	#^xA1, (r11)+
b4x:	insv	#^x5A, #^xC000C, #8, (r3)	; bits 12-19
	movpsl	(r11)+
	extv	#^xC0008, #12, (r3), r0
	movl	r0, (r11)+
	movpsl	(r11)+
	extzv	#^xC0010, #16, (r3), r0
	movl	r0, (r11)+
	cmpv	#^xC0004, #4, (r3), #7
	movpsl	(r11)+
	ffs	#^xC0001, #20, (r3), r0
	movl	r0, (r11)+
	movpsl	(r11)+
; a field of size 0: nothing found (Z, not N), findpos = startpos
	bicpsw	#^xF
	ffc	#-1, #0, (r3), r1
	movl	r1, (r11)+
	movpsl	(r11)+
	bispsw	#^xB
	ffs	#5, #0, @#^x8000, r1
	movl	r1, (r11)+
	movpsl	(r11)+
; reserved operands and addressing modes of the bit fields (EVKAB tests
; 94-98): a size above 32, a position above 31 (unsigned) in a register, a
; field from R14 that would go on into PC; size 0 checks nothing
	movl	#S0+resad_h, @#^x1C
	movl	#S0+fix_skip, r10
	movl	#-1, r2
	movab	f1, r8
	ffs	r2, #32, r4, r1			; position -1 in a register
f1:	movab	f2, r8
	extzv	#0, #33, @#^x8000, r1		; size 33
f2:	movab	f3, r8
	insv	#7, #0, #^x81, @#^x8000		; size 129 (as a byte: unsigned)
f3:	movab	f4, r8
	extv	#28, #8, sp, r1			; R14 and on: reserved addressing
f4:	movab	f5, r8
	insv	#7, #30, #4, sp
f5:	movab	f6, r8
	insv	#7, #40, #0, r4			; size 0: nothing, no check
	movl	#^x600D, (r11)+
f6:	movab	f7, r8
	extzv	#-1, #0, r4, r1			; nor here
	movl	r1, (r11)+
f7:	clrl	r10
; a field in the last longword of a page that is followed by an invalid
; page: only that longword is read (and written)
	bicl2	#PTE_V, @#S0+SPT+<^x41*4>
	mtpr	#S0+^x8200, #TBIS
	movl	#^x89ABCDEF, @#S0+^x81FC
	extzv	#4, #24, @#S0+^x81FC, r1
	movl	r1, (r11)+
	insv	#^x55, #24, #8, @#S0+^x81FC
	movl	@#S0+^x81FC, (r11)+
	bisl2	#PTE_V, @#S0+SPT+<^x41*4>
	halt
	.align	4
resad_h:
	movl	#^x1C1C1C1C, (r11)+
	movl	(sp), (r11)+			; PC: the faulting instruction
	movl	r8, (sp)			; resume after it
	rei
