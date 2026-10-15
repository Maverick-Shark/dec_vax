; t26_bbx - branch on bit (BBS, BBC, BBSS, BBCS, BBSC, BBCC, BBSSI, BBCCI)
; with a variable bit field base: in memory the bit is in the byte at
; base + pos/8 (pos signed, so it can be before the base, or many longwords
; after it); in a register pos must be 0-31, else a reserved operand fault.
; Found with the Diagnostic Supervisor (BBC with pos 20 into a table).
; Each branch taken adds a different bit to R6; R7 counts reserved operand
; faults.
;@ dump=8000:8
	.include "mmsetup.inc"
test:
	movl	#S0+resop_h2, @#^x18
	clrl	r6
	clrl	r7
	movl	#S0+^x8010, r2			; the base, in the middle of the data
	movl	#^x00000001, @#S0+^x8014	; bit 32 of the field set
	movl	#^x80000000, @#S0+^x800C	; bit -1 set
	movl	#^x00000100, @#S0+^x8030	; bit 0x108 set (byte 0x21 from base)
	movl	#32, r0
	bbc	r0, (r2), b1			; bit 32 set: no branch
	bisl2	#1, r6
b1:	bbs	r0, (r2), b2			; branch
	bisl2	#2, r6
b2:	movl	#-1, r0
	bbs	r0, (r2), b3			; bit -1: branch
	bisl2	#4, r6
b3:	movl	#^x108, r0
	bbc	r0, (r2), b4			; set: no branch
	bisl2	#8, r6
b4:	movl	#33, r0
	bbss	r0, (r2), b5			; was clear: no branch; set it
	bisl2	#^x10, r6
b5:	bbcc	r0, (r2), b6			; now set: no branch; clear it
	bisl2	#^x20, r6
b6:	bbcs	r0, (r2), b7			; clear: branch; set it
	bisl2	#^x40, r6
b7:	bbsc	r0, (r2), b8			; set: branch; clear it
	bisl2	#^x80, r6
b8:	movl	#-9, r0				; bit 7 of the byte before the base
	bbssi	r0, (r2), b9			; clear: no branch; set it
	bisl2	#^x100, r6
b9:	bbcci	r0, (r2), b10			; set: no branch; clear it
	bisl2	#^x200, r6
; register base
b10:	movl	#^x00010000, r3
	movl	#16, r0
	bbs	r0, r3, b11			; branch
	bisl2	#^x400, r6
b11:	bbcc	r0, r3, b12			; set: no branch, clear it
	bisl2	#^x800, r6
b12:	movl	#31, r0
	bbss	r0, r3, b13			; set bit 31
	bisl2	#^x1000, r6
b13:	movl	#32, r0
	movab	b14, r8
	bbs	r0, r3, b14			; pos 32 in a register: reserved operand
	bisl2	#^x2000, r6			; (not reached: resumed at b14)
b14:	movl	r3, r4
	halt
	.align	4
resop_h2:
	incl	r7
	movl	r8, (sp)			; resume after the faulting BBS
	rei
