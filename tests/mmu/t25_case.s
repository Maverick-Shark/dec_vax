; t25_case - CASEB, CASEW, CASEL: the selector minus the base is compared
; with the limit as an unsigned number of the operand's size (in range: the
; displacement from the table; out of range: past the table), and the
; condition codes are those of a compare of the two at that size. Found
; with the Diagnostic Supervisor, whose command interpreter uses CASEB with
; a limit above 7F. Each case logs the PSL and a marker.
;@ dump=18000:20
	.include "mmsetup.inc"
test:
	movl	#S0+LOG, r11
; CASEB, limit 8E (above 7F), selector 18: in range, entry 18
	movl	#^x18, r0
	caseb	r0, #0, #^x8E
tb1:	.blkw	^x18
	.word	tb1_y-tb1
	movl	#^xBAD0, (r11)+			; (not taken: out of range)
	brb	tb1_z
tb1_y:	movpsl	(r11)+
	movl	#^x1111, (r11)+
tb1_z:
; CASEB, selector 53 below base 80 (difference D3), limit 15: out of range
	movl	#^x53, r1
	caseb	r1, #^x80, #^x15
	.blkw	^x16
	movpsl	(r11)+
	movl	#^x2222, (r11)+
; CASEB, selector = base + limit: the last entry
	movl	#^x93, r1
	caseb	r1, #^x80, #^x13
tb3:	.blkw	^x13
	.word	tb3_y-tb3
	movl	#^xBAD1, (r11)+
	brb	tb3_z
tb3_y:	movpsl	(r11)+
	movl	#^x3333, (r11)+
tb3_z:
; CASEW, selector below base (difference FFF0), limit 3: out of range
	movl	#^x0010, r2
	casew	r2, #^x0020, #3
	.blkw	4
	movpsl	(r11)+
	movl	#^x4444, (r11)+
; CASEW, limit FFF0 (above 7FFF), selector base + 5: in range
	movl	#^x0105, r2
	casew	r2, #^x0100, #^xFFF0
tw2:	.blkw	5
	.word	tw2_y-tw2
	movl	#^xBAD2, (r11)+
	brb	tw2_z
tw2_y:	movpsl	(r11)+
	movl	#^x5555, (r11)+
tw2_z:
; CASEL, selector below base (difference FFFFFFFB), limit 2: out of range
	movl	#5, r3
	casel	r3, #10, #2
	.blkw	3
	movpsl	(r11)+
	movl	#^x6666, (r11)+
; CASEL, limit 80000000, selector base + 2: in range
	movl	#-2, r3
	casel	r3, #-4, #^x80000000
tl2:	.blkw	2
	.word	tl2_y-tl2
	movl	#^xBAD3, (r11)+
	brb	tl2_z
tl2_y:	movpsl	(r11)+
	movl	#^x7777, (r11)+
tl2_z:	halt
