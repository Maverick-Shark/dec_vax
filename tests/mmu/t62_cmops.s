; t62_cmops - PDP-11 compatibility mode instructions with random
; operands against the reference simulator; written by
; tests/mmu/gen/mk_t62.py (which see). Each instruction is followed by
; BPT; the handler logs code, PC, PSL, R0-R6.
;@ dump=18000:1774
;@ dump=5000:A00
;@ clocks=6000000
LOG	= ^x18000
KSP	= 0
USP	= 3
SCBB	= ^x11
CMPSL	= ^x83C00000

	.org	^x1000
start:	movl	#^x17800, sp		; above 64K: the compat code is
					; up to FFFF
	clrl	r0
	movab	unexp+1, r1
scbfill: movl	r1, (r0)+
	cmpl	r0, #^x200
	blss	scbfill
	movab	cmexc, @#^x30
	mtpr	#0, #SCBB
	mtpr	#^x17000, #KSP
	mtpr	#^x16800, #USP
	movl	#LOG, r11
	pushl	#CMPSL
	pushl	#^x8000
	rei

	.org	^x8000
	.pdp11
; 0
	mov	#^x60CC, r0
	mov	#^x8000, r1
	mov	#^x8001, r2
	mov	#^xEC7C, r3
	mov	#^x144C, r4
	mov	#^x7FFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	bisb (sp), @(r0)+
	bpt
; 1
	mov	#^x7485, r0
	mov	#^x86D, r1
	mov	#^x6068, r2
	mov	#^x33F0, r3
	mov	#^x3C20, r4
	mov	#^x7FFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	asl @-(r2)
	bpt
; 2
	mov	#^x9265, r0
	mov	#^x8001, r1
	mov	#^x8C42, r2
	mov	#^x12A2, r3
	mov	#^x7C4E, r4
	mov	#^xF601, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	sxt ^xc21d(r0)
	bpt
; 3
	mov	#^x112, r0
	mov	#^xDCF9, r1
	mov	#^xC465, r2
	mov	#^xFF80, r3
	mov	#^x6034, r4
	mov	#^xB708, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	sxt @-(r4)
	bpt
; 4
	mov	#^x270E, r0
	mov	#^xF933, r1
	mov	#^x60EE, r2
	mov	#^xFAFA, r3
	mov	#^x557C, r4
	mov	#^xFFFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	bis -(sp), @(r2)+
	bpt
; 5
	mov	#^x80, r0
	mov	#^x1234, r1
	mov	#^x7F, r2
	mov	#^x2155, r3
	mov	#^x8F27, r4
	mov	#^x56B0, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	cmpb @^x6057(r2), (r5)
	bpt
; 6
	mov	#^x1, r0
	mov	#^x41E0, r1
	mov	#^xE7F4, r2
	mov	#^xE875, r3
	mov	#^x80, r4
	mov	#^x6F50, r5
	mov	#^x7000, sp
	ccc
	asrb @^x5fa0(r4)
	bpt
; 7
	mov	#^x6070, r0
	mov	#^xA4B5, r1
	mov	#^x0, r2
	mov	#^x5608, r3
	mov	#^xC4B, r4
	mov	#^xED31, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	tst @-(r0)
	bpt
; 8
	mov	#^x554D, r0
	mov	#^x795D, r1
	mov	#^xFF7F, r2
	mov	#^x1D25, r3
	mov	#^x74BF, r4
	mov	#^xA1AF, r5
	mov	#^x7000, sp
	ccc
	bicb (r0), (sp)+
	bpt
; 9
	mov	#^x7FFE, r0
	mov	#^xFFFE, r1
	mov	#^xB939, r2
	mov	#^xA86, r3
	mov	#^x16CD, r4
	mov	#^x27B4, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	clc
	bpt
; 10
	mov	#^xDBF, r0
	mov	#^x60C4, r1
	mov	#^x80, r2
	mov	#^xFFB6, r3
	mov	#^x7FFF, r4
	mov	#^x9E4D, r5
	mov	#^x7000, sp
	ccc
	bic #^x1, @(r1)+
	bpt
; 11
	mov	#^x7FFE, r0
	mov	#^x6084, r1
	mov	#^x5E3B, r2
	mov	#^xE09B, r3
	mov	#^x5D0C, r4
	mov	#^x2E39, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	bit -(r4), @-(r1)
	bpt
; 12
	mov	#^xA612, r0
	mov	#^x7F, r1
	mov	#^x2AC6, r2
	mov	#^x7F, r3
	mov	#^xFF7D, r4
	mov	#^x5D26, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	mtpd r1
	bpt
; 13
	mov	#^xFFFF, r0
	mov	#^x2, r1
	mov	#^xFF7F, r2
	mov	#^x2B23, r3
	mov	#^x45F9, r4
	mov	#^x79DF, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	cmp r1, r4
	bpt
; 14
	mov	#^xA895, r0
	mov	#^xF042, r1
	mov	#^x901B, r2
	mov	#^x825D, r3
	mov	#^x7FFF, r4
	mov	#^x8F5E, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	neg @^x7078(r1)
	bpt
; 15
	mov	#^xFF, r0
	mov	#^x1, r1
	mov	#^x4A33, r2
	mov	#^x1DAD, r3
	mov	#^x401E, r4
	mov	#^xBF99, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	mfpi ^x5509(r1)
	bpt
; 16
	mov	#^xFF7F, r0
	mov	#^xFF7F, r1
	mov	#^x5E5E, r2
	mov	#^x174F, r3
	mov	#^x10FF, r4
	mov	#^x48CC, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	ash (r2)+, r0
	bpt
; 17
	mov	#^x5294, r0
	mov	#^xDD0, r1
	mov	#^x3EA4, r2
	mov	#^x8001, r3
	mov	#^x8001, r4
	mov	#^x5A18, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	sub (r5), @^x5fc(r5)
	bpt
; 18
	mov	#^x563A, r0
	mov	#^xEED5, r1
	mov	#^x55E4, r2
	mov	#^x2, r3
	mov	#^x3EA7, r4
	mov	#^x3A84, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	sub -(r2), -(r0)
	bpt
; 19
	mov	#^x2, r0
	mov	#^xC11C, r1
	mov	#^x7FFE, r2
	mov	#^x36AB, r3
	mov	#^x5652, r4
	mov	#^x5053, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	ashc -(r4), r2
	bpt
; 20
	mov	#^xEA29, r0
	mov	#^x100, r1
	mov	#^x7F, r2
	mov	#^x6094, r3
	mov	#^x796, r4
	mov	#^x4581, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	tst @-(r3)
	bpt
; 21
	mov	#^xF55, r0
	mov	#^x1, r1
	mov	#^x64CB, r2
	mov	#^x100, r3
	mov	#^xFFFF, r4
	mov	#^x7856, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	com @#^x5814
	bpt
; 22
	mov	#^x2F66, r0
	mov	#^x5170, r1
	mov	#^x63E, r2
	mov	#^x64F5, r3
	mov	#^x1, r4
	mov	#^x8001, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	asr (r1)
	bpt
; 23
	mov	#^x60AC, r0
	mov	#^x67A6, r1
	mov	#^xD460, r2
	mov	#^x8404, r3
	mov	#^x100, r4
	mov	#^x3607, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	ash @(r0)+, r2
	bpt
; 24
	mov	#^x6014, r0
	mov	#^xA8B3, r1
	mov	#^x100, r2
	mov	#^x16E1, r3
	mov	#^xA8D6, r4
	mov	#^x80, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	ashc @(r0)+, r4
	bpt
; 25
	mov	#^x5CBE, r0
	mov	#^x8FE8, r1
	mov	#^xEFB, r2
	mov	#^x24A2, r3
	mov	#^x45CB, r4
	mov	#^x1A68, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	bicb ^x4ff2(r2), -(r0)
	bpt
; 26
	mov	#^x2, r0
	mov	#^x5946, r1
	mov	#^xD80C, r2
	mov	#^xFF80, r3
	mov	#^x566B, r4
	mov	#^x3EFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	mfpd -(r1)
	bpt
; 27
	mov	#^xCA42, r0
	mov	#^xDB1E, r1
	mov	#^xF850, r2
	mov	#^x7989, r3
	mov	#^xD526, r4
	mov	#^x6E59, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	mul ^xe195(r3), r5
	bpt
; 28
	mov	#^x1, r0
	mov	#^x55FC, r1
	mov	#^x2, r2
	mov	#^x0, r3
	mov	#^x2, r4
	mov	#^xB276, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	clr (r1)
	bpt
; 29
	mov	#^xF5B3, r0
	mov	#^x4A22, r1
	mov	#^x7BDC, r2
	mov	#^x54B0, r3
	mov	#^xFF7F, r4
	mov	#^x3CB6, r5
	mov	#^x7000, sp
	ccc
	comb (r3)+
	bpt
; 30
	mov	#^x5DF9, r0
	mov	#^x4C5A, r1
	mov	#^x1, r2
	mov	#^xFF7F, r3
	mov	#^x4572, r4
	mov	#^x608E, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	bitb ^x53ee(r3), @-(r5)
	bpt
; 31
	mov	#^xFF7F, r0
	mov	#^x0, r1
	mov	#^x4E45, r2
	mov	#^x1, r3
	mov	#^xAF, r4
	mov	#^x8000, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	comb ^x579e(r1)
	bpt
; 32
	mov	#^xFF, r0
	mov	#^x4CAF, r1
	mov	#^xC24F, r2
	mov	#^x4487, r3
	mov	#^x8000, r4
	mov	#^x6D3C, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	tst ^xd9d6(r4)
	bpt
; 33
	mov	#^xFF7F, r0
	mov	#^x5202, r1
	mov	#^x581C, r2
	mov	#^x77F4, r3
	mov	#^x1DE5, r4
	mov	#^xFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	cmp (r1), (r2)
	bpt
; 34
	mov	#^x80, r0
	mov	#^x859F, r1
	mov	#^x8FBE, r2
	mov	#^x4D46, r3
	mov	#^x7FFF, r4
	mov	#^x6251, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	mtpd @^x1372(r3)
	bpt
; 35
	mov	#^x65DE, r0
	mov	#^x8CC1, r1
	mov	#^x95A6, r2
	mov	#^x7F, r3
	mov	#^x60B4, r4
	mov	#^x5954, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	cmp -(r5), @(r4)+
	bpt
; 36
	mov	#^x9AB6, r0
	mov	#^x8000, r1
	mov	#^xFF, r2
	mov	#^xD32, r3
	mov	#^x8AEB, r4
	mov	#^x562C, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	bisb (r5)+, @^x5f91(r2)
	bpt
; 37
	mov	#^xACE2, r0
	mov	#^xB34D, r1
	mov	#^x23C, r2
	mov	#^xD400, r3
	mov	#^x80, r4
	mov	#^x60DE, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	mtpd @(r5)+
	bpt
; 38
	mov	#^x0, r0
	mov	#^x2F06, r1
	mov	#^x6EDF, r2
	mov	#^x5280, r3
	mov	#^xBADD, r4
	mov	#^xFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	com (r3)
	bpt
; 39
	mov	#^x7FFF, r0
	mov	#^x2, r1
	mov	#^x70C7, r2
	mov	#^x60B6, r3
	mov	#^x2, r4
	mov	#^x100, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	cmpb @-(r3), @^x60aa
	bpt
; 40
	mov	#^x887B, r0
	mov	#^x1A3D, r1
	mov	#^x1, r2
	mov	#^x8000, r3
	mov	#^x1, r4
	mov	#^x28E6, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	neg @^x4621(r1)
	bpt
; 41
	mov	#^x608E, r0
	mov	#^xF927, r1
	mov	#^x5BF8, r2
	mov	#^x8001, r3
	mov	#^x2, r4
	mov	#^x5453, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	mov @(r0)+, (r2)+
	bpt
; 42
	mov	#^x3275, r0
	mov	#^xBE5E, r1
	mov	#^x5BF9, r2
	mov	#^xFF80, r3
	mov	#^x5958, r4
	mov	#^x80, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	mul (r4), r2
	bpt
; 43
	mov	#^x3537, r0
	mov	#^xA1D, r1
	mov	#^x8ADD, r2
	mov	#^x7A99, r3
	mov	#^x9C0C, r4
	mov	#^x3BE8, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	ash ^x2a21(r0), r4
	bpt
; 44
	mov	#^x1, r0
	mov	#^x60AC, r1
	mov	#^x1221, r2
	mov	#^xB2BD, r3
	mov	#^x31A6, r4
	mov	#^x42AA, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	bit @-(r1), (sp)+
	bpt
; 45
	mov	#^xFF7F, r0
	mov	#^x8EE8, r1
	mov	#^x2, r2
	mov	#^x3BE6, r3
	mov	#^x6040, r4
	mov	#^x0, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	adc @(r4)+
	bpt
; 46
	mov	#^xFF7F, r0
	mov	#^x6257, r1
	mov	#^x7FFE, r2
	mov	#^x7FFF, r3
	mov	#^x80, r4
	mov	#^x0, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	ashc ^x5680(r4), r1
	bpt
; 47
	mov	#^x3B8D, r0
	mov	#^x8001, r1
	mov	#^xE7F6, r2
	mov	#^x8001, r3
	mov	#^x1397, r4
	mov	#^xA17B, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	movb r3, r5
	bpt
; 48
	mov	#^xFF80, r0
	mov	#^xF3D9, r1
	mov	#^x8001, r2
	mov	#^x2408, r3
	mov	#^x5186, r4
	mov	#^xE8A1, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	asl -(r4)
	bpt
; 49
	mov	#^x7AE8, r0
	mov	#^xA96E, r1
	mov	#^x5DE5, r2
	mov	#^x0, r3
	mov	#^xC760, r4
	mov	#^xC742, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	decb (r2)
	bpt
; 50
	mov	#^x97B3, r0
	mov	#^x7F, r1
	mov	#^x7F, r2
	mov	#^x2, r3
	mov	#^x8000, r4
	mov	#^xD6AB, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	asr (sp)+
	bpt
; 51
	mov	#^x1, r0
	mov	#^xF556, r1
	mov	#^xB82, r2
	mov	#^x8000, r3
	mov	#^x36E1, r4
	mov	#^x7FFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	decb -(sp)
	bpt
; 52
	mov	#^xC96C, r0
	mov	#^x4327, r1
	mov	#^x601A, r2
	mov	#^x626, r3
	mov	#^x0, r4
	mov	#^x60B6, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	bic @-(r2), @-(r5)
	bpt
; 53
	mov	#^xD35C, r0
	mov	#^x6092, r1
	mov	#^xEC14, r2
	mov	#^x30E, r3
	mov	#^x3BC6, r4
	mov	#^xFFFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	dec @(r1)+
	bpt
; 54
	mov	#^x97F, r0
	mov	#^xAD98, r1
	mov	#^x5436, r2
	mov	#^xFFFE, r3
	mov	#^xFF, r4
	mov	#^x0, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	sub ^x4c1b(r0), ^xaa6c(r1)
	bpt
; 55
	mov	#^xBD69, r0
	mov	#^xB501, r1
	mov	#^xA547, r2
	mov	#^xD39F, r3
	mov	#^xF286, r4
	mov	#^x8000, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	asl -98(sp)
	bpt
; 56
	mov	#^x7FFE, r0
	mov	#^xD05, r1
	mov	#^x3D63, r2
	mov	#^xFC3E, r3
	mov	#^x4873, r4
	mov	#^xDE6B, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	cln
	bpt
; 57
	mov	#^xB949, r0
	mov	#^x4F50, r1
	mov	#^x13FD, r2
	mov	#^x8001, r3
	mov	#^x6060, r4
	mov	#^x283F, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	ash @(r4)+, r2
	bpt
; 58
	mov	#^x7F, r0
	mov	#^x7FFE, r1
	mov	#^x5626, r2
	mov	#^x8001, r3
	mov	#^x700F, r4
	mov	#^xB6C3, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	add ^x561a, -(r2)
	bpt
; 59
	mov	#^xF4F8, r0
	mov	#^x2, r1
	mov	#^x60E0, r2
	mov	#^x5AA9, r3
	mov	#^x7F, r4
	mov	#^x1CAE, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	xor r3, ^x5f28(r1)
	bpt
; 60
	mov	#^x585B, r0
	mov	#^xE68E, r1
	mov	#^x5E88, r2
	mov	#^x7FFF, r3
	mov	#^x0, r4
	mov	#^xCECA, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	cmpb (r2), ^x86f5(r5)
	bpt
; 61
	mov	#^xFF, r0
	mov	#^x491E, r1
	mov	#^x5616, r2
	mov	#^x39BF, r3
	mov	#^x8000, r4
	mov	#^x100, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	mfpi -(r2)
	bpt
; 62
	mov	#^x3875, r0
	mov	#^x6194, r1
	mov	#^x60FA, r2
	mov	#^x72ED, r3
	mov	#^x6074, r4
	mov	#^x2978, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	div @(r4)+, r2
	bpt
; 63
	mov	#^x7FFF, r0
	mov	#^x7FFE, r1
	mov	#^xD1A, r2
	mov	#^x777, r3
	mov	#^x3BD6, r4
	mov	#^xFF80, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	comb -(sp)
	bpt
; 64
	mov	#^x5B2A, r0
	mov	#^x2, r1
	mov	#^x1DEA, r2
	mov	#^xE9F5, r3
	mov	#^x2, r4
	mov	#^x7FFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	mtpd (r0)
	bpt
; 65
	mov	#^xB52F, r0
	mov	#^xFFFF, r1
	mov	#^x2, r2
	mov	#^x100, r3
	mov	#^x1, r4
	mov	#^x6094, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	asrb @(r5)+
	bpt
; 66
	mov	#^xDD4A, r0
	mov	#^x7F, r1
	mov	#^xFF, r2
	mov	#^x8001, r3
	mov	#^x9BF2, r4
	mov	#^x7FFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	sbcb @^x5fcb(r2)
	bpt
; 67
	mov	#^x602F, r0
	mov	#^xFF80, r1
	mov	#^x5F22, r2
	mov	#^x587C, r3
	mov	#^xD60C, r4
	mov	#^x5E23, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	adcb (r3)+
	bpt
; 68
	mov	#^x851E, r0
	mov	#^x34AE, r1
	mov	#^xC2A4, r2
	mov	#^xAA26, r3
	mov	#^x2, r4
	mov	#^xF636, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	comb ^x5390(r4)
	bpt
; 69
	mov	#^x542D, r0
	mov	#^xFFFE, r1
	mov	#^xA04E, r2
	mov	#^x7B1B, r3
	mov	#^x602E, r4
	mov	#^x100, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	sbc @-(r4)
	bpt
; 70
	mov	#^x2, r0
	mov	#^xFFFF, r1
	mov	#^x4D8E, r2
	mov	#^x8001, r3
	mov	#^x8001, r4
	mov	#^x4D32, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	xor r5, ^x11e4(r2)
	bpt
; 71
	mov	#^x2E8, r0
	mov	#^x7F, r1
	mov	#^x8001, r2
	mov	#^x5E44, r3
	mov	#^xBE2C, r4
	mov	#^x8000, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	com (r3)
	bpt
; 72
	mov	#^xA665, r0
	mov	#^xFF, r1
	mov	#^x58B6, r2
	mov	#^x8000, r3
	mov	#^x187B, r4
	mov	#^x830E, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	mov ^xaf13(r0), (r2)
	bpt
; 73
	mov	#^x8000, r0
	mov	#^x6050, r1
	mov	#^xFF17, r2
	mov	#^x9BBB, r3
	mov	#^x8001, r4
	mov	#^x6B7D, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	neg @-(r1)
	bpt
; 74
	mov	#^xFFFE, r0
	mov	#^x4756, r1
	mov	#^x2D26, r2
	mov	#^x7F, r3
	mov	#^xB5EF, r4
	mov	#^xA6F0, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	comb (sp)
	bpt
; 75
	mov	#^x7CB7, r0
	mov	#^x7FFF, r1
	mov	#^x8000, r2
	mov	#^xFF80, r3
	mov	#^xBDC3, r4
	mov	#^x16C7, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	mov #^x1ee2, @^xe0ed(r1)
	bpt
; 76
	mov	#^xFF80, r0
	mov	#^x7774, r1
	mov	#^xE27, r2
	mov	#^x18A, r3
	mov	#^x14C2, r4
	mov	#^xD636, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	ashc ^x47f6(r4), r1
	bpt
; 77
	mov	#^xFFFF, r0
	mov	#^x608A, r1
	mov	#^xFF, r2
	mov	#^xE920, r3
	mov	#^xFCEE, r4
	mov	#^x75F3, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	cmpb @(r1)+, ^x5f61(r0)
	bpt
; 78
	mov	#^x1521, r0
	mov	#^x80, r1
	mov	#^x7482, r2
	mov	#^x2, r3
	mov	#^xFF, r4
	mov	#^x5B45, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	ash @^x4b03(r0), r4
	bpt
; 79
	mov	#^xDE80, r0
	mov	#^x1804, r1
	mov	#^xD2E2, r2
	mov	#^x7FFE, r3
	mov	#^x1F73, r4
	mov	#^x5756, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	sub ^xd512(r3), (r5)+
	bpt
; 80
	mov	#^x8001, r0
	mov	#^x348, r1
	mov	#^x5520, r2
	mov	#^x1CC8, r3
	mov	#^xB76F, r4
	mov	#^x2F07, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	movb (r2)+, ^x215e(r5)
	bpt
; 81
	mov	#^x100, r0
	mov	#^xA5C, r1
	mov	#^x371D, r2
	mov	#^x9731, r3
	mov	#^x1756, r4
	mov	#^x61D7, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	ashc ^xbcfb(r3), r3
	bpt
; 82
	mov	#^x300A, r0
	mov	#^x6D3E, r1
	mov	#^x1383, r2
	mov	#^xFF, r3
	mov	#^x5820, r4
	mov	#^xE1B9, r5
	mov	#^x7000, sp
	ccc
	cmp @^x4d1d(r2), (r4)
	bpt
; 83
	mov	#^x11C3, r0
	mov	#^xDCE5, r1
	mov	#^x8000, r2
	mov	#^xFF80, r3
	mov	#^x8000, r4
	mov	#^x514C, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	rolb 90(sp)
	bpt
; 84
	mov	#^x646F, r0
	mov	#^x60AC, r1
	mov	#^xC5A2, r2
	mov	#^x8001, r3
	mov	#^xFFFF, r4
	mov	#^xFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	bisb @^x5fdd(r5), @(r1)+
	bpt
; 85
	mov	#^x7FFF, r0
	mov	#^x6694, r1
	mov	#^x7F, r2
	mov	#^x1, r3
	mov	#^x54D1, r4
	mov	#^x5762, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	rolb (r5)+
	bpt
; 86
	mov	#^x6024, r0
	mov	#^xA626, r1
	mov	#^x7FFE, r2
	mov	#^x9C62, r3
	mov	#^x1, r4
	mov	#^x309F, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	sbc @(r0)+
	bpt
; 87
	mov	#^x590B, r0
	mov	#^x28CA, r1
	mov	#^x2, r2
	mov	#^x60B4, r3
	mov	#^x518C, r4
	mov	#^xFFFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	cmpb @-(r3), -(r0)
	bpt
; 88
	mov	#^xFF80, r0
	mov	#^xED6E, r1
	mov	#^x1, r2
	mov	#^x80, r3
	mov	#^x7FFE, r4
	mov	#^x601C, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	mul @(r5)+, r2
	bpt
; 89
	mov	#^xFC4D, r0
	mov	#^x0, r1
	mov	#^x58EA, r2
	mov	#^xB369, r3
	mov	#^x42EF, r4
	mov	#^x0, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	mfpd (r2)+
	bpt
; 90
	mov	#^x0, r0
	mov	#^x1, r1
	mov	#^xFF, r2
	mov	#^x23DF, r3
	mov	#^x9B2F, r4
	mov	#^x7FFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	asrb @^x601b(r1)
	bpt
; 91
	mov	#^xF50D, r0
	mov	#^x16C6, r1
	mov	#^xDFA8, r2
	mov	#^x8000, r3
	mov	#^xD404, r4
	mov	#^x1559, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	bicb r2, ^x5d6d
	bpt
; 92
	mov	#^x2199, r0
	mov	#^x8001, r1
	mov	#^xFF80, r2
	mov	#^x7F, r3
	mov	#^xACD9, r4
	mov	#^xF5A2, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	ashc r1, r2
	bpt
; 93
	mov	#^xD9EC, r0
	mov	#^x7FFE, r1
	mov	#^x8EAC, r2
	mov	#^xFF, r3
	mov	#^xFF80, r4
	mov	#^x4E4C, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	aslb (sp)
	bpt
; 94
	mov	#^x9D07, r0
	mov	#^xFFFE, r1
	mov	#^xFF, r2
	mov	#^x52C4, r3
	mov	#^x422F, r4
	mov	#^x3351, r5
	mov	#^x7000, sp
	ccc
	aslb (sp)
	bpt
; 95
	mov	#^x1, r0
	mov	#^xFF7F, r1
	mov	#^xF7D3, r2
	mov	#^x6094, r3
	mov	#^x6C31, r4
	mov	#^x7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	div @(r3)+, r2
	bpt
; 96
	mov	#^x7FFF, r0
	mov	#^x8001, r1
	mov	#^xE362, r2
	mov	#^x5A96, r3
	mov	#^x100, r4
	mov	#^xFFFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	sxt (r3)+
	bpt
; 97
	mov	#^xFFFE, r0
	mov	#^x4509, r1
	mov	#^xFF, r2
	mov	#^xB3E9, r3
	mov	#^x89B7, r4
	mov	#^x526C, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	mfpd r1
	bpt
; 98
	mov	#^xAA21, r0
	mov	#^xB936, r1
	mov	#^xC937, r2
	mov	#^x51F0, r3
	mov	#^x9BB6, r4
	mov	#^x6691, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	div (r3), r2
	bpt
; 99
	mov	#^x9D64, r0
	mov	#^xDCED, r1
	mov	#^x594C, r2
	mov	#^x100, r3
	mov	#^x2, r4
	mov	#^xBB34, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	mul r0, r1
	bpt
; 100
	mov	#^x917F, r0
	mov	#^x58B6, r1
	mov	#^xA8A5, r2
	mov	#^x8001, r3
	mov	#^x1, r4
	mov	#^x565C, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	bisb (r5)+, (sp)
	bpt
; 101
	mov	#^xD6D1, r0
	mov	#^x80, r1
	mov	#^x7FFF, r2
	mov	#^x20A6, r3
	mov	#^xDD20, r4
	mov	#^xE056, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	mfpi r3
	bpt
; 102
	mov	#^x1, r0
	mov	#^xA595, r1
	mov	#^x5AF, r2
	mov	#^x7F, r3
	mov	#^x1, r4
	mov	#^x2, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	tstb @^x6037(r3)
	bpt
; 103
	mov	#^xFFFF, r0
	mov	#^x8001, r1
	mov	#^x80, r2
	mov	#^x80, r3
	mov	#^x60E0, r4
	mov	#^x80A0, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	add r2, @(r4)+
	bpt
; 104
	mov	#^x2, r0
	mov	#^xBAE9, r1
	mov	#^x566E, r2
	mov	#^xEBA6, r3
	mov	#^xAF1E, r4
	mov	#^x0, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	ash (r2)+, r1
	bpt
; 105
	mov	#^x5504, r0
	mov	#^xDC76, r1
	mov	#^x1, r2
	mov	#^xACB2, r3
	mov	#^x435F, r4
	mov	#^x7FFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	aslb (r0)
	bpt
; 106
	mov	#^xFF80, r0
	mov	#^x4A94, r1
	mov	#^x7D5C, r2
	mov	#^x80, r3
	mov	#^x8098, r4
	mov	#^x6363, r5
	mov	#^x7000, sp
	ccc
	com ^xf145(r5)
	bpt
; 107
	mov	#^x60BC, r0
	mov	#^xFF, r1
	mov	#^x1B71, r2
	mov	#^xFF, r3
	mov	#^x3F3D, r4
	mov	#^xCB6, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	bis @-(r0), @^x606a
	bpt
; 108
	mov	#^x8B39, r0
	mov	#^x470, r1
	mov	#^x7431, r2
	mov	#^xFFFF, r3
	mov	#^x7F, r4
	mov	#^x4221, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	mfpd @^x1df9(r5)
	bpt
; 109
	mov	#^x80, r0
	mov	#^x2, r1
	mov	#^x60EC, r2
	mov	#^x0, r3
	mov	#^x9C7D, r4
	mov	#^x57A9, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	bicb @(r2)+, (r5)
	bpt
; 110
	mov	#^xFFFF, r0
	mov	#^x570D, r1
	mov	#^x9470, r2
	mov	#^x1891, r3
	mov	#^x52BE, r4
	mov	#^x7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	ash -(r4), r3
	bpt
; 111
	mov	#^x7827, r0
	mov	#^x1, r1
	mov	#^x100, r2
	mov	#^x92BB, r3
	mov	#^xDF5D, r4
	mov	#^xF8DC, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	decb (sp)+
	bpt
; 112
	mov	#^xEDB7, r0
	mov	#^x44FE, r1
	mov	#^x601E, r2
	mov	#^x8000, r3
	mov	#^x6082, r4
	mov	#^x5C64, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	bit @(r2)+, @(r4)+
	bpt
; 113
	mov	#^x99D1, r0
	mov	#^xFF, r1
	mov	#^x7F, r2
	mov	#^x1, r3
	mov	#^xADD1, r4
	mov	#^x684D, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	sub ^x579e, @^x604f(r2)
	bpt
; 114
	mov	#^x8001, r0
	mov	#^xB883, r1
	mov	#^x40D5, r2
	mov	#^xFF80, r3
	mov	#^xCA3B, r4
	mov	#^x5B90, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	bitb -(r5), ^xa625(r1)
	bpt
; 115
	mov	#^xF0F1, r0
	mov	#^x2, r1
	mov	#^x8D37, r2
	mov	#^x572E, r3
	mov	#^x0, r4
	mov	#^xA50, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	adc -(r3)
	bpt
; 116
	mov	#^x9FD, r0
	mov	#^x8000, r1
	mov	#^x645D, r2
	mov	#^xFFFE, r3
	mov	#^x7EEF, r4
	mov	#^xB6D, r5
	mov	#^x7000, sp
	ccc
	tst @^x607e
	bpt
; 117
	mov	#^xFFFE, r0
	mov	#^x5A62, r1
	mov	#^x0, r2
	mov	#^xFF, r3
	mov	#^x1, r4
	mov	#^x1, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	bic (r1), ^x578b(r4)
	bpt
; 118
	mov	#^x55E4, r0
	mov	#^x605C, r1
	mov	#^xE6BB, r2
	mov	#^xBF8E, r3
	mov	#^x80, r4
	mov	#^x80, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	bic (r0)+, @(r1)+
	bpt
; 119
	mov	#^x16BB, r0
	mov	#^xFF, r1
	mov	#^x674C, r2
	mov	#^x7D9F, r3
	mov	#^xFB74, r4
	mov	#^xFF80, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	sev
	bpt
; 120
	mov	#^x9442, r0
	mov	#^xA0B, r1
	mov	#^xA769, r2
	mov	#^xB3F, r3
	mov	#^x2, r4
	mov	#^xA31B, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	bisb ^x5472(r1), (sp)+
	bpt
; 121
	mov	#^x7F, r0
	mov	#^x6040, r1
	mov	#^xEA42, r2
	mov	#^xDCD0, r3
	mov	#^x33CF, r4
	mov	#^xD847, r5
	mov	#^x7000, sp
	ccc
	ror @(r1)+
	bpt
; 122
	mov	#^xA18D, r0
	mov	#^xA0BD, r1
	mov	#^x7FFE, r2
	mov	#^xFF7F, r3
	mov	#^x73C2, r4
	mov	#^xBFD2, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	aslb r5
	bpt
; 123
	mov	#^xE120, r0
	mov	#^x33D4, r1
	mov	#^x1999, r2
	mov	#^x247B, r3
	mov	#^x29FB, r4
	mov	#^xB850, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	clz
	bpt
; 124
	mov	#^xFF7F, r0
	mov	#^x9453, r1
	mov	#^xFF80, r2
	mov	#^xFFFF, r3
	mov	#^xFF, r4
	mov	#^xFF80, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	xor r1, ^x5436(r5)
	bpt
; 125
	mov	#^x100, r0
	mov	#^x248A, r1
	mov	#^x30E0, r2
	mov	#^x74DE, r3
	mov	#^x2B18, r4
	mov	#^x5840, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	bis -(sp), -(r5)
	bpt
; 126
	mov	#^x60B2, r0
	mov	#^xAF81, r1
	mov	#^x8515, r2
	mov	#^xFF7F, r3
	mov	#^x100, r4
	mov	#^x7FFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	mtpd @(r0)+
	bpt
; 127
	mov	#^x80, r0
	mov	#^xFFFF, r1
	mov	#^xD445, r2
	mov	#^x130D, r3
	mov	#^xC194, r4
	mov	#^x75C, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	cmpb ^x5eee(r0), ^x5015(r1)
	bpt
; 128
	mov	#^x11C5, r0
	mov	#^x63E0, r1
	mov	#^x3882, r2
	mov	#^x100, r3
	mov	#^xEC42, r4
	mov	#^x100, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	ash r4, r4
	bpt
; 129
	mov	#^xA3D2, r0
	mov	#^x8D48, r1
	mov	#^xFFFF, r2
	mov	#^x86B3, r3
	mov	#^x5297, r4
	mov	#^xDFC7, r5
	mov	#^x7000, sp
	ccc
	bicb @^xd332(r1), -(r4)
	bpt
; 130
	mov	#^x735E, r0
	mov	#^x7099, r1
	mov	#^x7F, r2
	mov	#^x5170, r3
	mov	#^x53F8, r4
	mov	#^x2, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	cmp -(r4), -(r3)
	bpt
; 131
	mov	#^x56F9, r0
	mov	#^xFFFF, r1
	mov	#^x80, r2
	mov	#^x25FD, r3
	mov	#^x1343, r4
	mov	#^x677C, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	sbc @^xf894(r5)
	bpt
; 132
	mov	#^x6CF2, r0
	mov	#^x3425, r1
	mov	#^xFF80, r2
	mov	#^xC636, r3
	mov	#^x6056, r4
	mov	#^x5170, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	cmp @-(r4), (r5)
	bpt
; 133
	mov	#^x7FFE, r0
	mov	#^x3E65, r1
	mov	#^xD3EB, r2
	mov	#^xC358, r3
	mov	#^xAD8F, r4
	mov	#^x1, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	scc
	bpt
; 134
	mov	#^x59AB, r0
	mov	#^xE2D, r1
	mov	#^x81B5, r2
	mov	#^x7FF1, r3
	mov	#^xFFFE, r4
	mov	#^xDE67, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	mfpi @^xde75(r2)
	bpt
; 135
	mov	#^xFE76, r0
	mov	#^xFBDA, r1
	mov	#^xBA15, r2
	mov	#^x7FFF, r3
	mov	#^x5A5E, r4
	mov	#^xFFFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	rorb -(r4)
	bpt
; 136
	mov	#^x7FFE, r0
	mov	#^xA28, r1
	mov	#^x2B1E, r2
	mov	#^x7FFE, r3
	mov	#^x553, r4
	mov	#^x9E21, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	sbc r1
	bpt
; 137
	mov	#^xCE50, r0
	mov	#^xA050, r1
	mov	#^x1FE4, r2
	mov	#^x6D9C, r3
	mov	#^x1, r4
	mov	#^x20FD, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	tst (sp)+
	bpt
; 138
	mov	#^x24C, r0
	mov	#^xE6A7, r1
	mov	#^x8001, r2
	mov	#^x916B, r3
	mov	#^x8000, r4
	mov	#^x6018, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	bicb @-(r5), ^xdf99(r4)
	bpt
; 139
	mov	#^x80, r0
	mov	#^xF18, r1
	mov	#^x6042, r2
	mov	#^x5D24, r3
	mov	#^xFF80, r4
	mov	#^x7FFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	dec @-(r2)
	bpt
; 140
	mov	#^x537E, r0
	mov	#^x5D89, r1
	mov	#^x8B05, r2
	mov	#^x7225, r3
	mov	#^x80, r4
	mov	#^x6050, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	bisb -(r1), @-(r5)
	bpt
; 141
	mov	#^xFF, r0
	mov	#^x517C, r1
	mov	#^xFF, r2
	mov	#^x7FFE, r3
	mov	#^x7FFE, r4
	mov	#^x3FD0, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	div ^x1d26(r5), r4
	bpt
; 142
	mov	#^x8605, r0
	mov	#^x1135, r1
	mov	#^xD0B6, r2
	mov	#^x7FFF, r3
	mov	#^x60E8, r4
	mov	#^xFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	ashc @(r4)+, r0
	bpt
; 143
	mov	#^xAC1C, r0
	mov	#^x1, r1
	mov	#^x80EA, r2
	mov	#^x8001, r3
	mov	#^x7F, r4
	mov	#^xD47D, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	xor r0, r4
	bpt
; 144
	mov	#^x9C03, r0
	mov	#^xAD97, r1
	mov	#^x5E68, r2
	mov	#^xE394, r3
	mov	#^x60CC, r4
	mov	#^x7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	sub @(r4)+, ^xfa26(r2)
	bpt
; 145
	mov	#^x8001, r0
	mov	#^x7156, r1
	mov	#^x7F, r2
	mov	#^x7FFF, r3
	mov	#^x6062, r4
	mov	#^x4BA5, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	aslb @(r4)+
	bpt
; 146
	mov	#^x7F, r0
	mov	#^x0, r1
	mov	#^x7781, r2
	mov	#^xFF7F, r3
	mov	#^xFF, r4
	mov	#^x7B39, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	movb r3, r0
	bpt
; 147
	mov	#^x8001, r0
	mov	#^x1, r1
	mov	#^xB30C, r2
	mov	#^x8001, r3
	mov	#^x573E, r4
	mov	#^x9C9, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	mov ^xd5d7(r0), @^xad7a(r2)
	bpt
; 148
	mov	#^x7FFE, r0
	mov	#^xD885, r1
	mov	#^xAC33, r2
	mov	#^x5A81, r3
	mov	#^xCCC6, r4
	mov	#^xA9BF, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	negb (r3)+
	bpt
; 149
	mov	#^x8941, r0
	mov	#^xFF7F, r1
	mov	#^x60C6, r2
	mov	#^x80, r3
	mov	#^xB21E, r4
	mov	#^x6070, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	bicb @(r5)+, @(r2)+
	bpt
; 150
	mov	#^x2, r0
	mov	#^x4547, r1
	mov	#^x6B46, r2
	mov	#^xB262, r3
	mov	#^x2462, r4
	mov	#^xCEC1, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	negb ^xa8b5(r3)
	bpt
; 151
	mov	#^xAABA, r0
	mov	#^x6088, r1
	mov	#^x210B, r2
	mov	#^x4ACC, r3
	mov	#^x6098, r4
	mov	#^xC536, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	mov @-(r4), @-(r1)
	bpt
; 152
	mov	#^x5C5E, r0
	mov	#^x6058, r1
	mov	#^xADF8, r2
	mov	#^x0, r3
	mov	#^x1, r4
	mov	#^x8EFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	sub (r0)+, @-(r1)
	bpt
; 153
	mov	#^x845D, r0
	mov	#^x3224, r1
	mov	#^x7FFE, r2
	mov	#^x2AF5, r3
	mov	#^xB43E, r4
	mov	#^x3A1B, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	bicb @^x2e36(r1), @^xe020(r2)
	bpt
; 154
	mov	#^x6BE5, r0
	mov	#^xEB5A, r1
	mov	#^xFFFF, r2
	mov	#^x8001, r3
	mov	#^x8D3F, r4
	mov	#^xFF7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	clr ^xf305(r0)
	bpt
; 155
	mov	#^x8000, r0
	mov	#^xEEA6, r1
	mov	#^x2, r2
	mov	#^xFB46, r3
	mov	#^x9351, r4
	mov	#^x5344, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	asl -(r5)
	bpt
; 156
	mov	#^x890A, r0
	mov	#^x4052, r1
	mov	#^xFFFE, r2
	mov	#^xF4EC, r3
	mov	#^x481E, r4
	mov	#^x6072, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	xor r4, @(r5)+
	bpt
; 157
	mov	#^x5646, r0
	mov	#^x5DBC, r1
	mov	#^x0, r2
	mov	#^x10ED, r3
	mov	#^x5916, r4
	mov	#^x8001, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	bitb -(r4), -(r0)
	bpt
; 158
	mov	#^x8000, r0
	mov	#^xFF7F, r1
	mov	#^x7F, r2
	mov	#^x1EDF, r3
	mov	#^xFF7F, r4
	mov	#^xFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	clv
	bpt
; 159
	mov	#^x80, r0
	mov	#^x8001, r1
	mov	#^x7FFE, r2
	mov	#^x5995, r3
	mov	#^x7F, r4
	mov	#^xFE48, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	mfpd ^x5b9(r3)
	bpt
; 160
	mov	#^xFF7F, r0
	mov	#^x2851, r1
	mov	#^x8DE9, r2
	mov	#^x8001, r3
	mov	#^x1070, r4
	mov	#^x459A, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	ashc r3, r5
	bpt
; 161
	mov	#^x7FFF, r0
	mov	#^x7F, r1
	mov	#^x2FCF, r2
	mov	#^x0, r3
	mov	#^x80, r4
	mov	#^x7FFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	clv
	bpt
; 162
	mov	#^x1, r0
	mov	#^x601C, r1
	mov	#^x61E3, r2
	mov	#^x8000, r3
	mov	#^x80, r4
	mov	#^x8A05, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	cmp @(r1)+, ^xfd01(r2)
	bpt
; 163
	mov	#^x7FFF, r0
	mov	#^x2, r1
	mov	#^x7FFF, r2
	mov	#^x8000, r3
	mov	#^xE27, r4
	mov	#^xFF, r5
	mov	#^x7000, sp
	ccc
	com @^x6092
	bpt
; 164
	mov	#^xFF80, r0
	mov	#^x100, r1
	mov	#^x80, r2
	mov	#^x4737, r3
	mov	#^x1, r4
	mov	#^x0, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	cmpb ^xf72(r3), r3
	bpt
; 165
	mov	#^x809C, r0
	mov	#^x7F, r1
	mov	#^xE52E, r2
	mov	#^xDC43, r3
	mov	#^x8B1E, r4
	mov	#^x8CF4, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	asl @^x6080
	bpt
; 166
	mov	#^x449B, r0
	mov	#^x8001, r1
	mov	#^xFAE4, r2
	mov	#^x3BC2, r3
	mov	#^x95D0, r4
	mov	#^xFF7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	mfpi @^x654c(r2)
	bpt
; 167
	mov	#^xFF7F, r0
	mov	#^xA101, r1
	mov	#^xFFFF, r2
	mov	#^x4C0D, r3
	mov	#^x5EA4, r4
	mov	#^x278D, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	mfpd (r4)
	bpt
; 168
	mov	#^xFFFE, r0
	mov	#^x9586, r1
	mov	#^x52E6, r2
	mov	#^xFF7F, r3
	mov	#^x100, r4
	mov	#^x8000, r5
	mov	#^x7000, sp
	ccc
	neg (r2)+
	bpt
; 169
	mov	#^xC932, r0
	mov	#^x100, r1
	mov	#^x2, r2
	mov	#^x0, r3
	mov	#^xFF80, r4
	mov	#^x1D4D, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	mtpd ^x5c6a(r1)
	bpt
; 170
	mov	#^xFFFE, r0
	mov	#^x8001, r1
	mov	#^x4A47, r2
	mov	#^x5F1C, r3
	mov	#^x7FFF, r4
	mov	#^xFF7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	rolb @#^x5a5d
	bpt
; 171
	mov	#^x100, r0
	mov	#^xFF, r1
	mov	#^xBF30, r2
	mov	#^x3D8F, r3
	mov	#^x8001, r4
	mov	#^x87CD, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	asl @^xa148(r2)
	bpt
; 172
	mov	#^x69C9, r0
	mov	#^x70F6, r1
	mov	#^x609A, r2
	mov	#^x6079, r3
	mov	#^x35E9, r4
	mov	#^xFFFB, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	xor r2, @(r2)+
	bpt
; 173
	mov	#^x0, r0
	mov	#^x7FFE, r1
	mov	#^x60E8, r2
	mov	#^xE4A1, r3
	mov	#^x91BC, r4
	mov	#^x5DC7, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	add @^x7b8b(r3), @(r2)+
	bpt
; 174
	mov	#^x675C, r0
	mov	#^xCE19, r1
	mov	#^x9BC9, r2
	mov	#^xA5C7, r3
	mov	#^x472A, r4
	mov	#^x2, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	ash r2, r1
	bpt
; 175
	mov	#^x7A26, r0
	mov	#^xFF7F, r1
	mov	#^xF492, r2
	mov	#^x515E, r3
	mov	#^x6333, r4
	mov	#^xFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	swab (r3)+
	bpt
; 176
	mov	#^xC425, r0
	mov	#^x20DB, r1
	mov	#^xFF80, r2
	mov	#^xFFFF, r3
	mov	#^xC91C, r4
	mov	#^xFF7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	asr -(sp)
	bpt
; 177
	mov	#^xFFFF, r0
	mov	#^xF7F2, r1
	mov	#^xFF80, r2
	mov	#^xFFFE, r3
	mov	#^x33C9, r4
	mov	#^x7FFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	sev
	bpt
; 178
	mov	#^x8A74, r0
	mov	#^x3ED4, r1
	mov	#^xD06D, r2
	mov	#^xBCD2, r3
	mov	#^xA785, r4
	mov	#^x8001, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	adcb @^x8fd5(r2)
	bpt
; 179
	mov	#^x2, r0
	mov	#^x8001, r1
	mov	#^x5101, r2
	mov	#^x28F8, r3
	mov	#^x80, r4
	mov	#^x759F, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	mtpi ^x40f(r2)
	bpt
; 180
	mov	#^x7F, r0
	mov	#^x100, r1
	mov	#^x7C84, r2
	mov	#^xDB71, r3
	mov	#^x7F, r4
	mov	#^x5414, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	mul -(r5), r1
	bpt
; 181
	mov	#^xFF, r0
	mov	#^x92FE, r1
	mov	#^x66CD, r2
	mov	#^x4AE1, r3
	mov	#^xF049, r4
	mov	#^x1E0D, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	clv
	bpt
; 182
	mov	#^x5BD6, r0
	mov	#^x7F, r1
	mov	#^x6072, r2
	mov	#^x9155, r3
	mov	#^xC615, r4
	mov	#^xB0CA, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	bicb (r0), @(r2)+
	bpt
; 183
	mov	#^xC903, r0
	mov	#^x8001, r1
	mov	#^x4BD7, r2
	mov	#^x65FE, r3
	mov	#^x80, r4
	mov	#^xEFB6, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	mul @^x5ff0(r4), r0
	bpt
; 184
	mov	#^xFF7F, r0
	mov	#^x7F, r1
	mov	#^xB097, r2
	mov	#^x21A7, r3
	mov	#^xFF80, r4
	mov	#^x0, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	clc
	bpt
; 185
	mov	#^x4AAE, r0
	mov	#^xCE3B, r1
	mov	#^x8000, r2
	mov	#^x1121, r3
	mov	#^xFF80, r4
	mov	#^xFF85, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	asrb @^x4f39(r3)
	bpt
; 186
	mov	#^xFF7F, r0
	mov	#^x5CB6, r1
	mov	#^x9CEC, r2
	mov	#^x92D3, r3
	mov	#^xFFFF, r4
	mov	#^x7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	mul (r1)+, r0
	bpt
; 187
	mov	#^x0, r0
	mov	#^x80, r1
	mov	#^xF0E0, r2
	mov	#^x7FFE, r3
	mov	#^xB644, r4
	mov	#^x6010, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	add @-(r5), @(r5)+
	bpt
; 188
	mov	#^x803B, r0
	mov	#^xA15F, r1
	mov	#^x8001, r2
	mov	#^xD260, r3
	mov	#^x1DBE, r4
	mov	#^x7FFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	clv
	bpt
; 189
	mov	#^x993C, r0
	mov	#^xC512, r1
	mov	#^x1, r2
	mov	#^x8000, r3
	mov	#^x9512, r4
	mov	#^x3DCD, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	bic r1, ^xdbc6(r3)
	bpt
; 190
	mov	#^x10EC, r0
	mov	#^x100, r1
	mov	#^x2, r2
	mov	#^xFF7F, r3
	mov	#^x3D85, r4
	mov	#^x9DF1, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	comb @^x5f2c(r1)
	bpt
; 191
	mov	#^xFF80, r0
	mov	#^x481D, r1
	mov	#^x7F, r2
	mov	#^xE6E7, r3
	mov	#^x5360, r4
	mov	#^xFF7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	swab -(r4)
	bpt
; 192
	mov	#^x7FFF, r0
	mov	#^xC43C, r1
	mov	#^xFF, r2
	mov	#^xFFFE, r3
	mov	#^x95F1, r4
	mov	#^xAA93, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	inc ^xa949(r5)
	bpt
; 193
	mov	#^x3280, r0
	mov	#^xD564, r1
	mov	#^x5882, r2
	mov	#^x9520, r3
	mov	#^x7FFF, r4
	mov	#^x182F, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	mtpd r3
	bpt
; 194
	mov	#^x55DE, r0
	mov	#^x161F, r1
	mov	#^xFFFE, r2
	mov	#^xFBEF, r3
	mov	#^x100, r4
	mov	#^x5811, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	movb (r5)+, (r0)
	bpt
; 195
	mov	#^x96ED, r0
	mov	#^x55AC, r1
	mov	#^x7F, r2
	mov	#^x6FD7, r3
	mov	#^xD8BE, r4
	mov	#^x34A9, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	incb (r1)+
	bpt
; 196
	mov	#^xED37, r0
	mov	#^xFFFF, r1
	mov	#^x51D0, r2
	mov	#^x78DE, r3
	mov	#^x2CE9, r4
	mov	#^x263F, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	mfpi ^x312d(r4)
	bpt
; 197
	mov	#^x59A5, r0
	mov	#^x99AD, r1
	mov	#^x100, r2
	mov	#^x6C06, r3
	mov	#^xCD22, r4
	mov	#^xFFFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	comb -(r0)
	bpt
; 198
	mov	#^x0, r0
	mov	#^x4E4F, r1
	mov	#^x53D2, r2
	mov	#^xFFFF, r3
	mov	#^xCD56, r4
	mov	#^x6046, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	cmp (r2), @-(r5)
	bpt
; 199
	mov	#^x7E6D, r0
	mov	#^xFF, r1
	mov	#^xCDE2, r2
	mov	#^x34E8, r3
	mov	#^x5A7D, r4
	mov	#^x605A, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	bicb @-(r5), @^x2bb0(r3)
	bpt
; 200
	mov	#^xFFFE, r0
	mov	#^x7F, r1
	mov	#^x6038, r2
	mov	#^x8001, r3
	mov	#^xB85E, r4
	mov	#^x907B, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	bit -(sp), @(r2)+
	bpt
; 201
	mov	#^x7F, r0
	mov	#^x73B8, r1
	mov	#^x6D7A, r2
	mov	#^x8C9C, r3
	mov	#^x868A, r4
	mov	#^x7FFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	mfpi ^xd8fe(r4)
	bpt
; 202
	mov	#^xFF80, r0
	mov	#^xFFFF, r1
	mov	#^x5AFE, r2
	mov	#^xFF, r3
	mov	#^x8000, r4
	mov	#^x7FFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	bit @^x60c2, (r2)+
	bpt
; 203
	mov	#^x6287, r0
	mov	#^xC7E8, r1
	mov	#^xA26, r2
	mov	#^x43DD, r3
	mov	#^xBFE1, r4
	mov	#^xE1CC, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	bic r4, 32(sp)
	bpt
; 204
	mov	#^x633B, r0
	mov	#^x5ECE, r1
	mov	#^x100, r2
	mov	#^xCB0F, r3
	mov	#^xFF, r4
	mov	#^xA944, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	ashc (r1), r2
	bpt
; 205
	mov	#^x29BC, r0
	mov	#^xA638, r1
	mov	#^x2, r2
	mov	#^xFF80, r3
	mov	#^xFFFF, r4
	mov	#^x1, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	dec r1
	bpt
; 206
	mov	#^xFFFF, r0
	mov	#^xFFFE, r1
	mov	#^x53FD, r2
	mov	#^x1E8, r3
	mov	#^x149, r4
	mov	#^x8131, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	bisb -(r2), (r2)
	bpt
; 207
	mov	#^xF95D, r0
	mov	#^x84C5, r1
	mov	#^x1, r2
	mov	#^x7FFE, r3
	mov	#^xA37, r4
	mov	#^x6024, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	cmpb -24(sp), @(r5)+
	bpt
; 208
	mov	#^x1D6C, r0
	mov	#^x115C, r1
	mov	#^x8EB1, r2
	mov	#^xFFFF, r3
	mov	#^x58B0, r4
	mov	#^x7FFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	bit @^x6074, -(r4)
	bpt
; 209
	mov	#^x6B24, r0
	mov	#^x699E, r1
	mov	#^xFF, r2
	mov	#^x100, r3
	mov	#^x546C, r4
	mov	#^xFF7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	ror (r4)+
	bpt
; 210
	mov	#^xFF80, r0
	mov	#^x80, r1
	mov	#^x9B42, r2
	mov	#^xD157, r3
	mov	#^x5342, r4
	mov	#^xFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	ashc (r4)+, r4
	bpt
; 211
	mov	#^x0, r0
	mov	#^x4C03, r1
	mov	#^xEA82, r2
	mov	#^x609A, r3
	mov	#^x7F, r4
	mov	#^xFFFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	cmp @-(r3), @^x14d7(r1)
	bpt
; 212
	mov	#^x602E, r0
	mov	#^x431D, r1
	mov	#^xA648, r2
	mov	#^x60CA, r3
	mov	#^xA8B9, r4
	mov	#^xC6A7, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	bicb @-(r0), @-(r3)
	bpt
; 213
	mov	#^xFF, r0
	mov	#^x2, r1
	mov	#^xA39F, r2
	mov	#^x606E, r3
	mov	#^x7FFE, r4
	mov	#^x7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	div @(r3)+, r0
	bpt
; 214
	mov	#^xC97, r0
	mov	#^xF845, r1
	mov	#^x2, r2
	mov	#^xE3A9, r3
	mov	#^xFF7F, r4
	mov	#^x7FFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	mfpd @#^x5db6
	bpt
; 215
	mov	#^x7FFF, r0
	mov	#^xCFE9, r1
	mov	#^x1, r2
	mov	#^xC0DC, r3
	mov	#^x9B16, r4
	mov	#^x602A, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	tst @(r5)+
	bpt
; 216
	mov	#^x6C5B, r0
	mov	#^x7F, r1
	mov	#^xD0B, r2
	mov	#^x4536, r3
	mov	#^x594D, r4
	mov	#^x7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	bitb r0, ^x4aa(r4)
	bpt
; 217
	mov	#^x53BC, r0
	mov	#^xF60B, r1
	mov	#^xCE12, r2
	mov	#^x7FFE, r3
	mov	#^x51A7, r4
	mov	#^x1AED, r5
	mov	#^x7000, sp
	ccc
	bisb (r0)+, -(r4)
	bpt
; 218
	mov	#^x9AA5, r0
	mov	#^x786A, r1
	mov	#^xC23F, r2
	mov	#^xFFFF, r3
	mov	#^x256A, r4
	mov	#^x8000, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	neg @#^x5bc2
	bpt
; 219
	mov	#^x100, r0
	mov	#^x919C, r1
	mov	#^x582E, r2
	mov	#^xEFBB, r3
	mov	#^x7FFF, r4
	mov	#^x60D4, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	asr @-(r5)
	bpt
; 220
	mov	#^x9043, r0
	mov	#^x4D7F, r1
	mov	#^x5B0D, r2
	mov	#^x41FE, r3
	mov	#^x48AD, r4
	mov	#^x605A, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	mov @-(r5), @^x600c
	bpt
; 221
	mov	#^x7FFF, r0
	mov	#^x6971, r1
	mov	#^x7905, r2
	mov	#^x8001, r3
	mov	#^xB071, r4
	mov	#^xFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	com ^xa8fb(r4)
	bpt
; 222
	mov	#^x3D6C, r0
	mov	#^xFF80, r1
	mov	#^x6568, r2
	mov	#^x4786, r3
	mov	#^x0, r4
	mov	#^x7628, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	mtpi r2
	bpt
; 223
	mov	#^xE3E8, r0
	mov	#^xFFFE, r1
	mov	#^x3AAD, r2
	mov	#^x80, r3
	mov	#^xEA58, r4
	mov	#^x8000, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	sen
	bpt
; 224
	mov	#^x37D5, r0
	mov	#^x609C, r1
	mov	#^x0, r2
	mov	#^x60CE, r3
	mov	#^x2F60, r4
	mov	#^x7FCE, r5
	mov	#^x7000, sp
	ccc
	bit @(r3)+, @(r1)+
	bpt
; 225
	mov	#^x3C7F, r0
	mov	#^x97F8, r1
	mov	#^x2, r2
	mov	#^xBB8D, r3
	mov	#^x4869, r4
	mov	#^x0, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	swab r4
	bpt
; 226
	mov	#^xFD43, r0
	mov	#^x8000, r1
	mov	#^xFFFE, r2
	mov	#^xC03F, r3
	mov	#^x3098, r4
	mov	#^x5525, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	bisb (sp), (r5)+
	bpt
; 227
	mov	#^xDFEA, r0
	mov	#^xFFFF, r1
	mov	#^x60AC, r2
	mov	#^x8000, r3
	mov	#^x90D3, r4
	mov	#^xBD9D, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	bit @^xcfdd(r4), @(r2)+
	bpt
; 228
	mov	#^xFF80, r0
	mov	#^x80, r1
	mov	#^xFF7F, r2
	mov	#^x5BE9, r3
	mov	#^x6546, r4
	mov	#^x7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	rolb (r3)
	bpt
; 229
	mov	#^x7FFE, r0
	mov	#^xFF, r1
	mov	#^x6054, r2
	mov	#^x0, r3
	mov	#^x8000, r4
	mov	#^x60C0, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	bit @-(r5), @-(r2)
	bpt
; 230
	mov	#^xFF80, r0
	mov	#^xFF7F, r1
	mov	#^x3215, r2
	mov	#^x8FF5, r3
	mov	#^x8001, r4
	mov	#^x2, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	ash -122(sp), r1
	bpt
; 231
	mov	#^x7D3B, r0
	mov	#^x76C3, r1
	mov	#^x8000, r2
	mov	#^x60DC, r3
	mov	#^x2100, r4
	mov	#^x445B, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	tst @-(r3)
	bpt
; 232
	mov	#^x7F, r0
	mov	#^x44BE, r1
	mov	#^x98B7, r2
	mov	#^x1C7D, r3
	mov	#^x2121, r4
	mov	#^x6096, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	sub @-(r5), -(sp)
	bpt
; 233
	mov	#^x2, r0
	mov	#^x8B5, r1
	mov	#^x100, r2
	mov	#^xD320, r3
	mov	#^xFFFF, r4
	mov	#^x7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	aslb ^x5d21(r0)
	bpt
; 234
	mov	#^x5872, r0
	mov	#^x41C3, r1
	mov	#^x6A87, r2
	mov	#^x6038, r3
	mov	#^xFF, r4
	mov	#^xC68A, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	bis @-(r3), (r0)
	bpt
; 235
	mov	#^xA723, r0
	mov	#^x443C, r1
	mov	#^x8A8, r2
	mov	#^xFF80, r3
	mov	#^xFF, r4
	mov	#^xDA39, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	cln
	bpt
; 236
	mov	#^x2, r0
	mov	#^x0, r1
	mov	#^x348A, r2
	mov	#^x100, r3
	mov	#^x80, r4
	mov	#^xB4F1, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	asr ^x5802(r0)
	bpt
; 237
	mov	#^x5648, r0
	mov	#^xFF80, r1
	mov	#^xFF80, r2
	mov	#^x8000, r3
	mov	#^x100, r4
	mov	#^x60AE, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	bis (r0)+, @-(r5)
	bpt
; 238
	mov	#^x46E7, r0
	mov	#^xB258, r1
	mov	#^x7FFE, r2
	mov	#^x777D, r3
	mov	#^x7FFF, r4
	mov	#^x8001, r5
	mov	#^x7000, sp
	ccc
	bic r3, @^xe0d1(r4)
	bpt
; 239
	mov	#^xC053, r0
	mov	#^x0, r1
	mov	#^xCD1E, r2
	mov	#^x7F, r3
	mov	#^x1, r4
	mov	#^xFF7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	bic r2, @^x93b0(r2)
	bpt
; 240
	mov	#^x4693, r0
	mov	#^xFB59, r1
	mov	#^x2, r2
	mov	#^x8000, r3
	mov	#^x89A7, r4
	mov	#^xFFFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	sub ^x58a6(r5), ^xa59(r0)
	bpt
; 241
	mov	#^xFFFE, r0
	mov	#^x2, r1
	mov	#^xA1A5, r2
	mov	#^x100, r3
	mov	#^x1D45, r4
	mov	#^xCC4B, r5
	mov	#^x7000, sp
	ccc
	sev
	bpt
; 242
	mov	#^x1, r0
	mov	#^x93D7, r1
	mov	#^x7FFF, r2
	mov	#^x6026, r3
	mov	#^x8000, r4
	mov	#^xFF7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	div @-(r3), r4
	bpt
; 243
	mov	#^x7FFE, r0
	mov	#^x3BBE, r1
	mov	#^x6C11, r2
	mov	#^x7FFF, r3
	mov	#^x51A4, r4
	mov	#^x1440, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	mfpd (r4)+
	bpt
; 244
	mov	#^xEC72, r0
	mov	#^x73F7, r1
	mov	#^xFF7F, r2
	mov	#^xEB5D, r3
	mov	#^x59FF, r4
	mov	#^x41E, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	bis r4, r1
	bpt
; 245
	mov	#^xFF80, r0
	mov	#^xFF80, r1
	mov	#^x8000, r2
	mov	#^xC9D7, r3
	mov	#^xFF7F, r4
	mov	#^x8DD, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	sev
	bpt
; 246
	mov	#^x8B18, r0
	mov	#^x2C2F, r1
	mov	#^x8E9B, r2
	mov	#^x0, r3
	mov	#^x8000, r4
	mov	#^xFFFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	asrb -(sp)
	bpt
; 247
	mov	#^x0, r0
	mov	#^x8F9F, r1
	mov	#^xBBCA, r2
	mov	#^xDF6, r3
	mov	#^x1FEA, r4
	mov	#^x576A, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	ashc (r5), r1
	bpt
; 248
	mov	#^xB3E9, r0
	mov	#^x8000, r1
	mov	#^x6086, r2
	mov	#^xEDA8, r3
	mov	#^x8AFB, r4
	mov	#^x5A7D, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	add (sp)+, @-(r2)
	bpt
; 249
	mov	#^xFF80, r0
	mov	#^x1, r1
	mov	#^x1B6A, r2
	mov	#^xD2EA, r3
	mov	#^x62A, r4
	mov	#^x1163, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	cln
	bpt
; 250
	mov	#^xCBE1, r0
	mov	#^xFFFE, r1
	mov	#^xFF7F, r2
	mov	#^x80, r3
	mov	#^x6020, r4
	mov	#^xA39E, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	bitb @(r4)+, (sp)+
	bpt
; 251
	mov	#^x6C40, r0
	mov	#^x100, r1
	mov	#^x9528, r2
	mov	#^xBEAA, r3
	mov	#^x1EDB, r4
	mov	#^x5ABE, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	add ^x951c(r3), (r5)+
	bpt
; 252
	mov	#^x80, r0
	mov	#^xFF, r1
	mov	#^x33B1, r2
	mov	#^x7F, r3
	mov	#^xB7F8, r4
	mov	#^x231C, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	add ^x59e6(r0), r1
	bpt
; 253
	mov	#^xF1C2, r0
	mov	#^xFB10, r1
	mov	#^x8001, r2
	mov	#^xD6B7, r3
	mov	#^x57BC, r4
	mov	#^x1FDD, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	sxt -(r4)
	bpt
; 254
	mov	#^x4D0B, r0
	mov	#^x5DB4, r1
	mov	#^xFF80, r2
	mov	#^x6028, r3
	mov	#^x7F, r4
	mov	#^x686A, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	bic -(r1), @(r3)+
	bpt
; 255
	mov	#^xA00B, r0
	mov	#^x0, r1
	mov	#^x9C24, r2
	mov	#^x80, r3
	mov	#^xC880, r4
	mov	#^x7FFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	xor r4, ^xb165(r0)
	bpt
; 256
	mov	#^x91E5, r0
	mov	#^x5892, r1
	mov	#^xFF, r2
	mov	#^xDDC6, r3
	mov	#^x100, r4
	mov	#^xFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	com -(r1)
	bpt
; 257
	mov	#^x7189, r0
	mov	#^x9D76, r1
	mov	#^x8001, r2
	mov	#^x0, r3
	mov	#^xDA75, r4
	mov	#^xDD86, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	asr @^xe081(r2)
	bpt
; 258
	mov	#^x17, r0
	mov	#^x600D, r1
	mov	#^x2C04, r2
	mov	#^x2, r3
	mov	#^x8001, r4
	mov	#^x8001, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	movb r2, @^x60ba(r3)
	bpt
; 259
	mov	#^xFF, r0
	mov	#^x7F, r1
	mov	#^x6358, r2
	mov	#^x8001, r3
	mov	#^xFFFE, r4
	mov	#^x609E, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	dec @-(r5)
	bpt
; 260
	mov	#^x1A25, r0
	mov	#^x9481, r1
	mov	#^xA1E4, r2
	mov	#^xFFFE, r3
	mov	#^x35D3, r4
	mov	#^xFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	sxt ^xb140(r2)
	bpt
; 261
	mov	#^xFFFF, r0
	mov	#^x7FFE, r1
	mov	#^x7BA2, r2
	mov	#^xC705, r3
	mov	#^xF2B4, r4
	mov	#^xFFFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	dec r3
	bpt
; 262
	mov	#^xCD05, r0
	mov	#^x8000, r1
	mov	#^x5A8C, r2
	mov	#^x714A, r3
	mov	#^x7353, r4
	mov	#^xE94, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	clr (r2)+
	bpt
; 263
	mov	#^xB0FC, r0
	mov	#^x80, r1
	mov	#^x575C, r2
	mov	#^xCF46, r3
	mov	#^x71C5, r4
	mov	#^x830B, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	bis (r2)+, r2
	bpt
; 264
	mov	#^x0, r0
	mov	#^x7785, r1
	mov	#^xFFFE, r2
	mov	#^xE3EA, r3
	mov	#^xFF80, r4
	mov	#^x9B28, r5
	mov	#^x7000, sp
	ccc
	xor r2, @^xc5bc(r5)
	bpt
; 265
	mov	#^x100, r0
	mov	#^xC654, r1
	mov	#^xD110, r2
	mov	#^xFF, r3
	mov	#^x7CD6, r4
	mov	#^x5A2A, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	div (r5), r2
	bpt
; 266
	mov	#^x3B8E, r0
	mov	#^x80, r1
	mov	#^x80, r2
	mov	#^x5573, r3
	mov	#^x6068, r4
	mov	#^x6568, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	sub @(r4)+, r5
	bpt
; 267
	mov	#^xC108, r0
	mov	#^x9BE9, r1
	mov	#^xA7BA, r2
	mov	#^x8202, r3
	mov	#^x7DDE, r4
	mov	#^xD882, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	scc
	bpt
; 268
	mov	#^x1, r0
	mov	#^x5358, r1
	mov	#^x84E8, r2
	mov	#^x7948, r3
	mov	#^xA504, r4
	mov	#^x97C4, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	cmp (r1), r1
	bpt
; 269
	mov	#^x7FFE, r0
	mov	#^x603C, r1
	mov	#^xA4FA, r2
	mov	#^x1, r3
	mov	#^x2, r4
	mov	#^x9653, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	bit @(r1)+, ^x5a36
	bpt
; 270
	mov	#^x5E66, r0
	mov	#^x8001, r1
	mov	#^x342B, r2
	mov	#^xB551, r3
	mov	#^x9E69, r4
	mov	#^x2, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	bit (r0)+, @^xe0b7(r1)
	bpt
; 271
	mov	#^xC365, r0
	mov	#^xD347, r1
	mov	#^xFF, r2
	mov	#^xB9D, r3
	mov	#^xFEF6, r4
	mov	#^xFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	swab ^x5df6(r4)
	bpt
; 272
	mov	#^xFFFE, r0
	mov	#^xFF80, r1
	mov	#^x60D2, r2
	mov	#^x3F9D, r3
	mov	#^xD9E2, r4
	mov	#^x100, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	negb @-(r2)
	bpt
; 273
	mov	#^xBC7D, r0
	mov	#^x5EB4, r1
	mov	#^xDD7B, r2
	mov	#^x5ED8, r3
	mov	#^xFFFF, r4
	mov	#^x58AE, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	sub (r5)+, (r3)
	bpt
; 274
	mov	#^x8F59, r0
	mov	#^x50F, r1
	mov	#^xFFFE, r2
	mov	#^xF7C3, r3
	mov	#^xB62D, r4
	mov	#^xE91F, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	ccc
	bpt
; 275
	mov	#^x2E31, r0
	mov	#^x605E, r1
	mov	#^xFBB1, r2
	mov	#^x6DD0, r3
	mov	#^xD21F, r4
	mov	#^x963C, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	mov ^x52f2, @(r1)+
	bpt
; 276
	mov	#^xF5AE, r0
	mov	#^xFF, r1
	mov	#^x2, r2
	mov	#^x6BA0, r3
	mov	#^x8000, r4
	mov	#^x1A76, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	add #^x4de6, r0
	bpt
; 277
	mov	#^x9915, r0
	mov	#^xAE92, r1
	mov	#^x606E, r2
	mov	#^xD408, r3
	mov	#^x80, r4
	mov	#^x5A3C, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	cmpb @-(r2), -(r5)
	bpt
; 278
	mov	#^x5120, r0
	mov	#^xFFFE, r1
	mov	#^x726, r2
	mov	#^xA250, r3
	mov	#^xC2E5, r4
	mov	#^xEF7D, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	mtpd -(r0)
	bpt
; 279
	mov	#^x80, r0
	mov	#^x5662, r1
	mov	#^x2, r2
	mov	#^xEE7, r3
	mov	#^x7FFE, r4
	mov	#^xF939, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	xor r3, (r1)+
	bpt
; 280
	mov	#^x7FFF, r0
	mov	#^x4C38, r1
	mov	#^xFF, r2
	mov	#^xFF80, r3
	mov	#^x6C0E, r4
	mov	#^xFF80, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	mtpd ^x5d6e(r3)
	bpt
; 281
	mov	#^x4D8, r0
	mov	#^xFFFE, r1
	mov	#^xAFFF, r2
	mov	#^x60BA, r3
	mov	#^xFF80, r4
	mov	#^x6052, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	bisb @(r5)+, @(r3)+
	bpt
; 282
	mov	#^x5BDA, r0
	mov	#^x3FB8, r1
	mov	#^x7756, r2
	mov	#^x65BE, r3
	mov	#^x9B81, r4
	mov	#^x8001, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	add @^xe08f(r5), (r0)
	bpt
; 283
	mov	#^xFF, r0
	mov	#^x5142, r1
	mov	#^x5E8C, r2
	mov	#^xFF7F, r3
	mov	#^x80, r4
	mov	#^xEE29, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	cmp (r2)+, (r1)
	bpt
; 284
	mov	#^x5512, r0
	mov	#^x5ADC, r1
	mov	#^x8000, r2
	mov	#^xFFFF, r3
	mov	#^x2ADE, r4
	mov	#^x0, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	bisb (r1)+, @#^x5ba2
	bpt
; 285
	mov	#^x100, r0
	mov	#^x7FFF, r1
	mov	#^x2E92, r2
	mov	#^x5C42, r3
	mov	#^x80, r4
	mov	#^x77FC, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	bis (sp), @^xe041(r1)
	bpt
; 286
	mov	#^x6FA8, r0
	mov	#^xE0C3, r1
	mov	#^x7E99, r2
	mov	#^x2, r3
	mov	#^x60B6, r4
	mov	#^x3269, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	movb r3, @-(r4)
	bpt
; 287
	mov	#^x100, r0
	mov	#^xC503, r1
	mov	#^x1, r2
	mov	#^xAD03, r3
	mov	#^x0, r4
	mov	#^xBDC6, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	sub r5, r3
	bpt
; 288
	mov	#^x1C8F, r0
	mov	#^x355E, r1
	mov	#^xB91E, r2
	mov	#^x80, r3
	mov	#^xCD9A, r4
	mov	#^x57A1, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	cmpb @^x43f7(r0), (r5)+
	bpt
; 289
	mov	#^xA65D, r0
	mov	#^xD0B6, r1
	mov	#^x8C93, r2
	mov	#^x93E0, r3
	mov	#^xFF, r4
	mov	#^x5B38, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	mov -(r5), @^xd403(r2)
	bpt
; 290
	mov	#^x6171, r0
	mov	#^x7DFF, r1
	mov	#^x5D03, r2
	mov	#^x7FFF, r3
	mov	#^x7FFF, r4
	mov	#^x1, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	incb (r2)+
	bpt
; 291
	mov	#^x6778, r0
	mov	#^x100, r1
	mov	#^x100, r2
	mov	#^xFF, r3
	mov	#^xB493, r4
	mov	#^x3DB3, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	sev
	bpt
; 292
	mov	#^x84AA, r0
	mov	#^x7B73, r1
	mov	#^x2E0D, r2
	mov	#^x2141, r3
	mov	#^xFF80, r4
	mov	#^x9EDB, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	mfpi @#^x5218
	bpt
; 293
	mov	#^xD01E, r0
	mov	#^xC772, r1
	mov	#^x581A, r2
	mov	#^x22EB, r3
	mov	#^x1, r4
	mov	#^xCF79, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	adc (r2)
	bpt
; 294
	mov	#^x54D7, r0
	mov	#^x6495, r1
	mov	#^x8000, r2
	mov	#^x90A2, r3
	mov	#^x8000, r4
	mov	#^x1590, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	tstb (r0)+
	bpt
; 295
	mov	#^x6034, r0
	mov	#^xFF80, r1
	mov	#^x7FFF, r2
	mov	#^x2, r3
	mov	#^xFFFE, r4
	mov	#^x299D, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	cmp -(sp), @(r0)+
	bpt
; 296
	mov	#^xA3B0, r0
	mov	#^xCA44, r1
	mov	#^xD439, r2
	mov	#^x7FFE, r3
	mov	#^x607A, r4
	mov	#^x8000, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	bicb @(r4)+, @^xe026(r3)
	bpt
; 297
	mov	#^x3880, r0
	mov	#^xB086, r1
	mov	#^xFFFE, r2
	mov	#^x35B3, r3
	mov	#^xE17B, r4
	mov	#^x9DFB, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	neg @^x2aa1(r3)
	bpt
; 298
	mov	#^xD44C, r0
	mov	#^xAE16, r1
	mov	#^xFF, r2
	mov	#^x7F, r3
	mov	#^x1AE2, r4
	mov	#^xD43D, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	sbcb -90(sp)
	bpt
; 299
	mov	#^x80, r0
	mov	#^x5291, r1
	mov	#^x5186, r2
	mov	#^x52A0, r3
	mov	#^x8000, r4
	mov	#^xC38C, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	bic (r3)+, (r2)+
	bpt
; 300
	mov	#^xFF80, r0
	mov	#^xFFFF, r1
	mov	#^x88EB, r2
	mov	#^x4E18, r3
	mov	#^x953F, r4
	mov	#^x8000, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	sen
	bpt
; 301
	mov	#^x100, r0
	mov	#^x1872, r1
	mov	#^xFFFF, r2
	mov	#^x6060, r3
	mov	#^x7FC1, r4
	mov	#^xE7F8, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	mov @-(r3), -128(sp)
	bpt
; 302
	mov	#^xFF80, r0
	mov	#^x2, r1
	mov	#^x5438, r2
	mov	#^xB5C0, r3
	mov	#^xFF, r4
	mov	#^x2E77, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	tst (r2)+
	bpt
; 303
	mov	#^xCEA2, r0
	mov	#^xC4BD, r1
	mov	#^x8791, r2
	mov	#^x69F9, r3
	mov	#^xFFA3, r4
	mov	#^x2CE9, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	bic ^xd657(r2), @#^x565c
	bpt
; 304
	mov	#^xCFAB, r0
	mov	#^x7F, r1
	mov	#^x944B, r2
	mov	#^x7FFE, r3
	mov	#^xE3D7, r4
	mov	#^x2AC, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	bitb r5, r5
	bpt
; 305
	mov	#^xD8E9, r0
	mov	#^x60CC, r1
	mov	#^x8C4A, r2
	mov	#^x7F, r3
	mov	#^x674B, r4
	mov	#^x5538, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	sub (r5), @(r1)+
	bpt
; 306
	mov	#^x4FC4, r0
	mov	#^x100, r1
	mov	#^x2, r2
	mov	#^xE5CD, r3
	mov	#^x8001, r4
	mov	#^x494E, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	clv
	bpt
; 307
	mov	#^x6EE6, r0
	mov	#^x4741, r1
	mov	#^x7FFE, r2
	mov	#^x7FFE, r3
	mov	#^x4BB0, r4
	mov	#^x7FFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	sub ^xdf74(r3), (sp)+
	bpt
; 308
	mov	#^xC8BF, r0
	mov	#^x5017, r1
	mov	#^xFF80, r2
	mov	#^x159F, r3
	mov	#^x2, r4
	mov	#^x1, r5
	mov	#^x7000, sp
	ccc
	sub ^x8bc9(r0), (sp)+
	bpt
; 309
	mov	#^x511B, r0
	mov	#^x100, r1
	mov	#^x1E2, r2
	mov	#^x81E9, r3
	mov	#^x2555, r4
	mov	#^xC40F, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	bicb (r0)+, (r0)+
	bpt
; 310
	mov	#^x4690, r0
	mov	#^x2, r1
	mov	#^x7F, r2
	mov	#^x7FFE, r3
	mov	#^xD449, r4
	mov	#^x2A10, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	adc @^x19c6(r0)
	bpt
; 311
	mov	#^x602A, r0
	mov	#^x7FFE, r1
	mov	#^xF80C, r2
	mov	#^x2, r3
	mov	#^xD84B, r4
	mov	#^xEC0A, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	bicb @(r0)+, @^x60ae
	bpt
; 312
	mov	#^x80, r0
	mov	#^x325F, r1
	mov	#^x9E96, r2
	mov	#^x56F6, r3
	mov	#^x8000, r4
	mov	#^x7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	mul (r3)+, r0
	bpt
; 313
	mov	#^x5D78, r0
	mov	#^x8001, r1
	mov	#^x5A62, r2
	mov	#^x54CC, r3
	mov	#^x2A9B, r4
	mov	#^xD4C7, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	sxt (r3)+
	bpt
; 314
	mov	#^xDA88, r0
	mov	#^x54A1, r1
	mov	#^xD161, r2
	mov	#^x5810, r3
	mov	#^x7FFF, r4
	mov	#^x80, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	bitb (r3)+, r4
	bpt
; 315
	mov	#^x5306, r0
	mov	#^xE37F, r1
	mov	#^x7F93, r2
	mov	#^xFFFE, r3
	mov	#^x0, r4
	mov	#^xFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	ash -(r0), r0
	bpt
; 316
	mov	#^x5A7C, r0
	mov	#^x611B, r1
	mov	#^xFF80, r2
	mov	#^x8606, r3
	mov	#^x8010, r4
	mov	#^x8001, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	bisb ^xf123(r1), @^x6102(r2)
	bpt
; 317
	mov	#^x7FFF, r0
	mov	#^x78EC, r1
	mov	#^x7FFF, r2
	mov	#^xFD7B, r3
	mov	#^xACE6, r4
	mov	#^x601C, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	sxt @-(r5)
	bpt
; 318
	mov	#^xDC5A, r0
	mov	#^x2966, r1
	mov	#^x7FFE, r2
	mov	#^x58A0, r3
	mov	#^x7FFF, r4
	mov	#^xFF80, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	ash -(r3), r3
	bpt
; 319
	mov	#^x7FFF, r0
	mov	#^x141C, r1
	mov	#^xF4B0, r2
	mov	#^xD96C, r3
	mov	#^x8001, r4
	mov	#^x2, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	mtpd r0
	bpt
; 320
	mov	#^x100, r0
	mov	#^xDEB3, r1
	mov	#^x8000, r2
	mov	#^xC188, r3
	mov	#^xFD81, r4
	mov	#^xA3C4, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	adcb ^x7a21(r1)
	bpt
; 321
	mov	#^xCCF4, r0
	mov	#^x7FFE, r1
	mov	#^x0, r2
	mov	#^x55C5, r3
	mov	#^xB744, r4
	mov	#^x60BA, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	movb @(r5)+, (r3)+
	bpt
; 322
	mov	#^x6038, r0
	mov	#^xFFFF, r1
	mov	#^x0, r2
	mov	#^x1, r3
	mov	#^xB046, r4
	mov	#^xC331, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	bic @(r0)+, ^x5227(r1)
	bpt
; 323
	mov	#^x7F, r0
	mov	#^xCBC4, r1
	mov	#^xC295, r2
	mov	#^xC8, r3
	mov	#^xFF7F, r4
	mov	#^xCB07, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	bic @^x9def(r2), ^x9b7d(r2)
	bpt
; 324
	mov	#^x60BC, r0
	mov	#^x32EF, r1
	mov	#^xD840, r2
	mov	#^xA182, r3
	mov	#^xFFFE, r4
	mov	#^xF395, r5
	mov	#^x7000, sp
	ccc
	bic @(r0)+, 38(sp)
	bpt
; 325
	mov	#^x7F, r0
	mov	#^xFFFE, r1
	mov	#^x9B73, r2
	mov	#^x7D71, r3
	mov	#^x66B9, r4
	mov	#^x8001, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	ror ^x5923(r0)
	bpt
; 326
	mov	#^x7FFE, r0
	mov	#^x574C, r1
	mov	#^x781B, r2
	mov	#^x8001, r3
	mov	#^x7F, r4
	mov	#^x592C, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	mfpd (r5)+
	bpt
; 327
	mov	#^xF3AF, r0
	mov	#^x604C, r1
	mov	#^x7059, r2
	mov	#^x71E9, r3
	mov	#^x9AD2, r4
	mov	#^x136C, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	cmpb @-(r1), r4
	bpt
; 328
	mov	#^x5565, r0
	mov	#^x7220, r1
	mov	#^xF859, r2
	mov	#^x7FFF, r3
	mov	#^x6472, r4
	mov	#^x47C6, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	cmpb @^x18e4(r5), (r0)+
	bpt
; 329
	mov	#^xBF28, r0
	mov	#^x3F9E, r1
	mov	#^x4446, r2
	mov	#^x8235, r3
	mov	#^xFF7F, r4
	mov	#^xFF7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	negb @^x606c
	bpt
; 330
	mov	#^x9BA5, r0
	mov	#^x8000, r1
	mov	#^xF2FF, r2
	mov	#^xFFFE, r3
	mov	#^x8000, r4
	mov	#^x14E0, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	sxt ^xdd8c(r4)
	bpt
; 331
	mov	#^xA012, r0
	mov	#^xFF, r1
	mov	#^xFFFE, r2
	mov	#^x100, r3
	mov	#^xC30D, r4
	mov	#^x5AD9, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	adcb (r5)
	bpt
; 332
	mov	#^x5910, r0
	mov	#^x2CD6, r1
	mov	#^xCBD5, r2
	mov	#^xFF80, r3
	mov	#^x8584, r4
	mov	#^x9AA0, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	cmp (r0)+, r0
	bpt
; 333
	mov	#^x605A, r0
	mov	#^x7F, r1
	mov	#^x7FFF, r2
	mov	#^xC3CA, r3
	mov	#^x6012, r4
	mov	#^xC89B, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	mov @-(r0), @-(r4)
	bpt
; 334
	mov	#^x7F98, r0
	mov	#^xABA4, r1
	mov	#^x2A10, r2
	mov	#^x3E82, r3
	mov	#^x7DD5, r4
	mov	#^x4A8C, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	ror r3
	bpt
; 335
	mov	#^xFFFE, r0
	mov	#^x53CA, r1
	mov	#^x1034, r2
	mov	#^xEFFC, r3
	mov	#^xFF7F, r4
	mov	#^xB363, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	dec (r1)
	bpt
; 336
	mov	#^x5ED2, r0
	mov	#^x7F, r1
	mov	#^x9E32, r2
	mov	#^x8000, r3
	mov	#^x100, r4
	mov	#^xCD8F, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	comb (r0)+
	bpt
; 337
	mov	#^x3596, r0
	mov	#^x8000, r1
	mov	#^x100, r2
	mov	#^x100, r3
	mov	#^x6096, r4
	mov	#^x38E0, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	sub @#^x572a, @-(r4)
	bpt
; 338
	mov	#^x6E0A, r0
	mov	#^xB673, r1
	mov	#^x8000, r2
	mov	#^x7FFE, r3
	mov	#^x60EA, r4
	mov	#^x7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	mtpi @(r4)+
	bpt
; 339
	mov	#^xEBA3, r0
	mov	#^x6098, r1
	mov	#^x40F3, r2
	mov	#^xEAA6, r3
	mov	#^x375B, r4
	mov	#^x0, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	cmp @(r1)+, r5
	bpt
; 340
	mov	#^x7F, r0
	mov	#^x59E5, r1
	mov	#^xFF80, r2
	mov	#^x1, r3
	mov	#^x1560, r4
	mov	#^xEAE1, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	ash ^x56ff(r3), r1
	bpt
; 341
	mov	#^x5E38, r0
	mov	#^xA48A, r1
	mov	#^xC39C, r2
	mov	#^x80, r3
	mov	#^xFFFE, r4
	mov	#^x651A, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	mfpd 22(sp)
	bpt
; 342
	mov	#^x8001, r0
	mov	#^x1830, r1
	mov	#^x4FEE, r2
	mov	#^x604C, r3
	mov	#^xC71D, r4
	mov	#^xA9D1, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	clrb @(r3)+
	bpt
; 343
	mov	#^x1D97, r0
	mov	#^x916C, r1
	mov	#^xFCFF, r2
	mov	#^x4C35, r3
	mov	#^x2, r4
	mov	#^x4AAE, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	bit @^x637f(r2), r5
	bpt
; 344
	mov	#^x550C, r0
	mov	#^x100, r1
	mov	#^x7C3A, r2
	mov	#^x3A77, r3
	mov	#^x8699, r4
	mov	#^xDFCA, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	mul -(r0), r0
	bpt
; 345
	mov	#^xC1F, r0
	mov	#^xBF92, r1
	mov	#^x8001, r2
	mov	#^xA3AF, r3
	mov	#^xD41C, r4
	mov	#^x8667, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	bis ^xd021(r5), (sp)+
	bpt
; 346
	mov	#^xFF80, r0
	mov	#^xFF7F, r1
	mov	#^x2, r2
	mov	#^x7FFF, r3
	mov	#^x5ED3, r4
	mov	#^x6010, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	aslb @(r5)+
	bpt
; 347
	mov	#^x100, r0
	mov	#^x5AA2, r1
	mov	#^xD647, r2
	mov	#^x1EE0, r3
	mov	#^x7B76, r4
	mov	#^xAE7B, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	negb -(r1)
	bpt
; 348
	mov	#^xFF, r0
	mov	#^x4340, r1
	mov	#^x3020, r2
	mov	#^x5A52, r3
	mov	#^x8001, r4
	mov	#^x7FFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	cmp (r3)+, r4
	bpt
; 349
	mov	#^x91F, r0
	mov	#^x6072, r1
	mov	#^xE7B, r2
	mov	#^xA953, r3
	mov	#^xAF03, r4
	mov	#^x2DAA, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	bitb r1, @-(r1)
	bpt
; 350
	mov	#^x0, r0
	mov	#^x60E4, r1
	mov	#^x7952, r2
	mov	#^x7C3E, r3
	mov	#^x7FFF, r4
	mov	#^x7FFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	mtpi @-(r1)
	bpt
; 351
	mov	#^x8BDA, r0
	mov	#^xE3A3, r1
	mov	#^x6068, r2
	mov	#^xFFFF, r3
	mov	#^xB4C5, r4
	mov	#^xE046, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	cmpb @-(r2), @^xabef(r4)
	bpt
; 352
	mov	#^x629, r0
	mov	#^x62EE, r1
	mov	#^x8000, r2
	mov	#^xACF, r3
	mov	#^x5D68, r4
	mov	#^xA06E, r5
	mov	#^x7000, sp
	ccc
	bis @^x55e1(r3), (r4)
	bpt
; 353
	mov	#^x6C5C, r0
	mov	#^x36AA, r1
	mov	#^xFF, r2
	mov	#^x8000, r3
	mov	#^xFF, r4
	mov	#^xB088, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	asrb r2
	bpt
; 354
	mov	#^x815, r0
	mov	#^x8000, r1
	mov	#^x5DA8, r2
	mov	#^x7F, r3
	mov	#^x7FFE, r4
	mov	#^xEC56, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	clrb @^x742e(r5)
	bpt
; 355
	mov	#^x8001, r0
	mov	#^x8000, r1
	mov	#^x226B, r2
	mov	#^x2C0E, r3
	mov	#^xBBB4, r4
	mov	#^x2, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	bitb @^xe0c1(r0), r3
	bpt
; 356
	mov	#^x4EB5, r0
	mov	#^x7FFF, r1
	mov	#^x100, r2
	mov	#^xBE6F, r3
	mov	#^x5142, r4
	mov	#^x1AF6, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	xor r0, -(r4)
	bpt
; 357
	mov	#^x7FFF, r0
	mov	#^x2, r1
	mov	#^x7FFF, r2
	mov	#^x5A42, r3
	mov	#^x60A2, r4
	mov	#^x2, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	sub -(r3), @-(r4)
	bpt
; 358
	mov	#^x3A44, r0
	mov	#^x3416, r1
	mov	#^x53E4, r2
	mov	#^xAC5C, r3
	mov	#^x2, r4
	mov	#^x3BC5, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	bitb -(r2), (sp)+
	bpt
; 359
	mov	#^xFFFF, r0
	mov	#^x6D9F, r1
	mov	#^x33CA, r2
	mov	#^xA3B2, r3
	mov	#^x986C, r4
	mov	#^x0, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	bitb r4, ^x5c84
	bpt
; 360
	mov	#^x51F2, r0
	mov	#^x8000, r1
	mov	#^x77B9, r2
	mov	#^x2, r3
	mov	#^xCDB1, r4
	mov	#^x7FFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	bic -(r0), r5
	bpt
; 361
	mov	#^x21F6, r0
	mov	#^x8001, r1
	mov	#^x6064, r2
	mov	#^x8001, r3
	mov	#^x5348, r4
	mov	#^x7FFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	bis (r4), @-(r2)
	bpt
; 362
	mov	#^x8000, r0
	mov	#^x393D, r1
	mov	#^x80, r2
	mov	#^xFF80, r3
	mov	#^xB147, r4
	mov	#^x538E, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	sen
	bpt
; 363
	mov	#^x8DFC, r0
	mov	#^xD41B, r1
	mov	#^xF411, r2
	mov	#^x6070, r3
	mov	#^x9669, r4
	mov	#^x623D, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	movb r0, @(r3)+
	bpt
; 364
	mov	#^x8ED7, r0
	mov	#^x4080, r1
	mov	#^xCE00, r2
	mov	#^xFFFE, r3
	mov	#^xFFFF, r4
	mov	#^x7F0, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	dec r3
	bpt
; 365
	mov	#^x4E1A, r0
	mov	#^x100, r1
	mov	#^xFFFF, r2
	mov	#^x3DFB, r3
	mov	#^x7FFF, r4
	mov	#^x8000, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	clr r1
	bpt
; 366
	mov	#^xFF, r0
	mov	#^x84B0, r1
	mov	#^xFF, r2
	mov	#^x4, r3
	mov	#^x3B37, r4
	mov	#^xFF7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	mtpi ^xd2d8(r1)
	bpt
; 367
	mov	#^x6038, r0
	mov	#^xB8E6, r1
	mov	#^xFF, r2
	mov	#^xFFFE, r3
	mov	#^xC009, r4
	mov	#^x55FB, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	rol @(r0)+
	bpt
; 368
	mov	#^xFF80, r0
	mov	#^x100, r1
	mov	#^xE029, r2
	mov	#^x83AF, r3
	mov	#^x6FB8, r4
	mov	#^xFFFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	adcb (sp)+
	bpt
; 369
	mov	#^x8A1, r0
	mov	#^x5C98, r1
	mov	#^x607C, r2
	mov	#^xFFFF, r3
	mov	#^x1BFB, r4
	mov	#^x5C1B, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	cmpb @(r2)+, (r1)+
	bpt
; 370
	mov	#^x8001, r0
	mov	#^xFF7F, r1
	mov	#^x4ED0, r2
	mov	#^x4E30, r3
	mov	#^xF708, r4
	mov	#^x1AF4, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	sen
	bpt
; 371
	mov	#^x9984, r0
	mov	#^x91E0, r1
	mov	#^x1, r2
	mov	#^xFF, r3
	mov	#^x69EB, r4
	mov	#^x5B04, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	bis (r5)+, r2
	bpt
; 372
	mov	#^xAFF2, r0
	mov	#^xFF, r1
	mov	#^x7FFE, r2
	mov	#^x5AE5, r3
	mov	#^x60D0, r4
	mov	#^xCA28, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	mul @(r4)+, r0
	bpt
; 373
	mov	#^x59C3, r0
	mov	#^x5B04, r1
	mov	#^x100, r2
	mov	#^x5AD, r3
	mov	#^x609E, r4
	mov	#^xFFFF, r5
	mov	#^x7000, sp
	ccc
	bicb @-(r4), (r1)+
	bpt
; 374
	mov	#^x112B, r0
	mov	#^xAB50, r1
	mov	#^xFF80, r2
	mov	#^x3C7F, r3
	mov	#^x274E, r4
	mov	#^x2, r5
	mov	#^x7000, sp
	ccc
	clr @^x6168(r2)
	bpt
; 375
	mov	#^x5D2A, r0
	mov	#^xFF80, r1
	mov	#^x7F, r2
	mov	#^xB249, r3
	mov	#^x7F, r4
	mov	#^x2, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	mtpd @^xae67(r3)
	bpt
; 376
	mov	#^x7F, r0
	mov	#^x8001, r1
	mov	#^xFF, r2
	mov	#^xB1F8, r3
	mov	#^xE9C, r4
	mov	#^x7FFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	ccc
	bpt
; 377
	mov	#^xFFFE, r0
	mov	#^xFF, r1
	mov	#^x8000, r2
	mov	#^xFDD, r3
	mov	#^xFF, r4
	mov	#^x80, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	ror @^x60d2(r0)
	bpt
; 378
	mov	#^x89F, r0
	mov	#^xDDB4, r1
	mov	#^x1, r2
	mov	#^x71FE, r3
	mov	#^xFF, r4
	mov	#^x455D, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	ashc @^x1ad1(r5), r4
	bpt
; 379
	mov	#^x15D0, r0
	mov	#^x8000, r1
	mov	#^x7F, r2
	mov	#^xF09F, r3
	mov	#^xE6C0, r4
	mov	#^xB578, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	ashc r5, r5
	bpt
; 380
	mov	#^x60C8, r0
	mov	#^xB9CE, r1
	mov	#^xF62, r2
	mov	#^x14EB, r3
	mov	#^x5E69, r4
	mov	#^x6367, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	swab @-(r0)
	bpt
; 381
	mov	#^x6094, r0
	mov	#^xA5EF, r1
	mov	#^x421E, r2
	mov	#^x10EC, r3
	mov	#^xFF7F, r4
	mov	#^xF320, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	mov @(r0)+, ^xfc52(r0)
	bpt
; 382
	mov	#^xFFFE, r0
	mov	#^x5466, r1
	mov	#^x7ABB, r2
	mov	#^x5C9F, r3
	mov	#^x7FFF, r4
	mov	#^x2, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	div (r1)+, r0
	bpt
; 383
	mov	#^x8001, r0
	mov	#^x7FFE, r1
	mov	#^x8ECB, r2
	mov	#^x1C36, r3
	mov	#^x2, r4
	mov	#^x5371, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	rolb -(r5)
	bpt
; 384
	mov	#^xD5B2, r0
	mov	#^x8000, r1
	mov	#^x1, r2
	mov	#^xCA4A, r3
	mov	#^x3FB5, r4
	mov	#^x8B0E, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	bisb (sp)+, @^x60e9(r2)
	bpt
; 385
	mov	#^x1, r0
	mov	#^x7F, r1
	mov	#^x8353, r2
	mov	#^x8001, r3
	mov	#^x95ED, r4
	mov	#^x7FFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	bicb @^x60b3(r0), r0
	bpt
; 386
	mov	#^xFF80, r0
	mov	#^xA760, r1
	mov	#^xFFFF, r2
	mov	#^x7FFF, r3
	mov	#^x5B0C, r4
	mov	#^x5A9B, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	bit (r4)+, @^x56a(r4)
	bpt
; 387
	mov	#^x6B97, r0
	mov	#^x34B9, r1
	mov	#^x57B4, r2
	mov	#^xA960, r3
	mov	#^xED37, r4
	mov	#^xFF80, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	rol -(r2)
	bpt
; 388
	mov	#^x3235, r0
	mov	#^x60B2, r1
	mov	#^xA0CD, r2
	mov	#^x5833, r3
	mov	#^x2, r4
	mov	#^xFFFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	add r2, @#^x5970
	bpt
; 389
	mov	#^x7F, r0
	mov	#^xB7BE, r1
	mov	#^x6032, r2
	mov	#^x7F, r3
	mov	#^x3A68, r4
	mov	#^x7715, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	neg @-(r2)
	bpt
; 390
	mov	#^xFFFE, r0
	mov	#^x13FF, r1
	mov	#^x397F, r2
	mov	#^xB31, r3
	mov	#^xA962, r4
	mov	#^x8001, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	mfpi @^xb772(r4)
	bpt
; 391
	mov	#^xFFFF, r0
	mov	#^x5D62, r1
	mov	#^x7FFE, r2
	mov	#^xAF, r3
	mov	#^x34DF, r4
	mov	#^x5ACA, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	mov (r1)+, (r5)
	bpt
; 392
	mov	#^x6B61, r0
	mov	#^xCC8A, r1
	mov	#^x542A, r2
	mov	#^xD98C, r3
	mov	#^xFC91, r4
	mov	#^x186D, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	sub ^xff6c(r2), (r2)
	bpt
; 393
	mov	#^xFFFF, r0
	mov	#^x5666, r1
	mov	#^x8000, r2
	mov	#^x3F01, r3
	mov	#^xFFFF, r4
	mov	#^xFF, r5
	mov	#^x7000, sp
	ccc
	div @^x602f(r0), r0
	bpt
; 394
	mov	#^x2D47, r0
	mov	#^x7F, r1
	mov	#^xF4C8, r2
	mov	#^x91, r3
	mov	#^x8000, r4
	mov	#^x5D70, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	rol (r5)
	bpt
; 395
	mov	#^x80, r0
	mov	#^x9CF0, r1
	mov	#^xF6FC, r2
	mov	#^xEDAA, r3
	mov	#^xCA62, r4
	mov	#^xFF80, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	movb (sp), r2
	bpt
; 396
	mov	#^x5C08, r0
	mov	#^xFC7F, r1
	mov	#^xFF7F, r2
	mov	#^x7F, r3
	mov	#^xCEC5, r4
	mov	#^x7167, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	tst -(r0)
	bpt
; 397
	mov	#^xB322, r0
	mov	#^x7F, r1
	mov	#^xFF80, r2
	mov	#^xEA12, r3
	mov	#^xFF, r4
	mov	#^x7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	sbcb r1
	bpt
; 398
	mov	#^x8001, r0
	mov	#^x5964, r1
	mov	#^xE85C, r2
	mov	#^x7FFF, r3
	mov	#^xFFFE, r4
	mov	#^x7FFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	bit (r1)+, ^xfe82(r1)
	bpt
; 399
	mov	#^x4821, r0
	mov	#^x54F8, r1
	mov	#^x6072, r2
	mov	#^xD94E, r3
	mov	#^x8E03, r4
	mov	#^x76C5, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	cmp (r1)+, @-(r2)
	bpt
; 400
	mov	#^x42C6, r0
	mov	#^x1A39, r1
	mov	#^x0, r2
	mov	#^x2AC1, r3
	mov	#^xFF, r4
	mov	#^x8000, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	sxt r1
	bpt
; 401
	mov	#^x8FB3, r0
	mov	#^x5697, r1
	mov	#^x1FD5, r2
	mov	#^x9313, r3
	mov	#^xFF, r4
	mov	#^x80, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	sez
	bpt
; 402
	mov	#^xBAEF, r0
	mov	#^x8000, r1
	mov	#^x5951, r2
	mov	#^xC25F, r3
	mov	#^x6080, r4
	mov	#^xFF7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	bisb -(r2), @-(r4)
	bpt
; 403
	mov	#^x361F, r0
	mov	#^xD3CE, r1
	mov	#^x0, r2
	mov	#^x6259, r3
	mov	#^x514C, r4
	mov	#^xE20F, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	ror -(r4)
	bpt
; 404
	mov	#^x607C, r0
	mov	#^xFF80, r1
	mov	#^x7F, r2
	mov	#^x2, r3
	mov	#^x2C32, r4
	mov	#^x128B, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	sbc @(r0)+
	bpt
; 405
	mov	#^x5820, r0
	mov	#^xFFFF, r1
	mov	#^x1, r2
	mov	#^xFF, r3
	mov	#^xC5D3, r4
	mov	#^x80EA, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	mtpi (r0)
	bpt
; 406
	mov	#^x588E, r0
	mov	#^x9F48, r1
	mov	#^x2, r2
	mov	#^x51EE, r3
	mov	#^x2F3A, r4
	mov	#^x7FFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	bic (r0)+, -(r3)
	bpt
; 407
	mov	#^xAED, r0
	mov	#^x3572, r1
	mov	#^xCDD6, r2
	mov	#^x501C, r3
	mov	#^x8033, r4
	mov	#^x100, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	sec
	bpt
; 408
	mov	#^x0, r0
	mov	#^x5D4E, r1
	mov	#^xDE42, r2
	mov	#^x1, r3
	mov	#^xFBAE, r4
	mov	#^x2, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	mov -(r1), @^x6536(r4)
	bpt
; 409
	mov	#^xE867, r0
	mov	#^x584E, r1
	mov	#^xFFFE, r2
	mov	#^x2, r3
	mov	#^x6094, r4
	mov	#^xC461, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	add -(r1), @(r4)+
	bpt
; 410
	mov	#^xDC01, r0
	mov	#^x7F, r1
	mov	#^x6038, r2
	mov	#^xF5EB, r3
	mov	#^xFF7F, r4
	mov	#^xFFFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	sxt @-(r2)
	bpt
; 411
	mov	#^x3597, r0
	mov	#^x9B4A, r1
	mov	#^x5270, r2
	mov	#^xD307, r3
	mov	#^x1, r4
	mov	#^x7170, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	ashc -(r2), r3
	bpt
; 412
	mov	#^x5CA5, r0
	mov	#^x34D6, r1
	mov	#^xFF7F, r2
	mov	#^x5D7E, r3
	mov	#^xE8D9, r4
	mov	#^x8001, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	bisb (r0), r3
	bpt
; 413
	mov	#^x100, r0
	mov	#^xB705, r1
	mov	#^xACA4, r2
	mov	#^xCC13, r3
	mov	#^xD29E, r4
	mov	#^x8000, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	swab @^xa937(r1)
	bpt
; 414
	mov	#^x7FA8, r0
	mov	#^x60EA, r1
	mov	#^x45FE, r2
	mov	#^xDA29, r3
	mov	#^x7F, r4
	mov	#^x4CD, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	mtpd @-(r1)
	bpt
; 415
	mov	#^x602E, r0
	mov	#^xFF, r1
	mov	#^x4B09, r2
	mov	#^xFFFE, r3
	mov	#^x2, r4
	mov	#^x8000, r5
	mov	#^x7000, sp
	ccc
	cmpb ^x5328(r3), @(r0)+
	bpt
; 416
	mov	#^x9FD2, r0
	mov	#^x53D8, r1
	mov	#^x6C3C, r2
	mov	#^xCA14, r3
	mov	#^x6468, r4
	mov	#^x2, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	xor r3, -(r1)
	bpt
; 417
	mov	#^xF023, r0
	mov	#^xE9A7, r1
	mov	#^x2, r2
	mov	#^x7F8B, r3
	mov	#^x87C7, r4
	mov	#^x1, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	clv
	bpt
; 418
	mov	#^x5334, r0
	mov	#^xF022, r1
	mov	#^xF014, r2
	mov	#^x131F, r3
	mov	#^x0, r4
	mov	#^x4D02, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	clr (r0)
	bpt
; 419
	mov	#^x5924, r0
	mov	#^x5302, r1
	mov	#^x76DD, r2
	mov	#^x6066, r3
	mov	#^xBBAD, r4
	mov	#^x83E7, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	bic @-(r3), @^xe9df(r2)
	bpt
; 420
	mov	#^x7F, r0
	mov	#^x56CD, r1
	mov	#^x2BEA, r2
	mov	#^x60AA, r3
	mov	#^xB952, r4
	mov	#^x8001, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	bisb (r1)+, @-(r3)
	bpt
; 421
	mov	#^x332C, r0
	mov	#^x100, r1
	mov	#^xFE58, r2
	mov	#^x55B0, r3
	mov	#^x4477, r4
	mov	#^xC8AD, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	mfpi (r3)+
	bpt
; 422
	mov	#^x6048, r0
	mov	#^x958D, r1
	mov	#^x5A5D, r2
	mov	#^xF747, r3
	mov	#^xDBC5, r4
	mov	#^x35C3, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	mul @(r0)+, r4
	bpt
; 423
	mov	#^x516D, r0
	mov	#^xFF48, r1
	mov	#^x100, r2
	mov	#^x699B, r3
	mov	#^xC25F, r4
	mov	#^x5132, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	ash -(r5), r4
	bpt
; 424
	mov	#^xE64A, r0
	mov	#^x8001, r1
	mov	#^xF94D, r2
	mov	#^x100, r3
	mov	#^x529C, r4
	mov	#^xFF80, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	sxt (r4)
	bpt
; 425
	mov	#^xFFFE, r0
	mov	#^xF81F, r1
	mov	#^x604A, r2
	mov	#^x7D91, r3
	mov	#^x4842, r4
	mov	#^x2, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	asl @(r2)+
	bpt
; 426
	mov	#^xFFFF, r0
	mov	#^x7F, r1
	mov	#^x321A, r2
	mov	#^x7FFE, r3
	mov	#^x95F7, r4
	mov	#^xFD69, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	mtpi @#^x5514
	bpt
; 427
	mov	#^x7122, r0
	mov	#^xF9EB, r1
	mov	#^x5360, r2
	mov	#^xFF80, r3
	mov	#^x6080, r4
	mov	#^x80, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	movb @(r4)+, -(r2)
	bpt
; 428
	mov	#^x95DE, r0
	mov	#^x7B84, r1
	mov	#^xFFFE, r2
	mov	#^xFFFF, r3
	mov	#^x1ECB, r4
	mov	#^x100, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	xor r0, r0
	bpt
; 429
	mov	#^x80, r0
	mov	#^x79F9, r1
	mov	#^x8CD9, r2
	mov	#^x80, r3
	mov	#^x2016, r4
	mov	#^x66F1, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	inc #^xff
	bpt
; 430
	mov	#^x52EA, r0
	mov	#^x85E1, r1
	mov	#^xE7CE, r2
	mov	#^x5BFC, r3
	mov	#^x567E, r4
	mov	#^x8000, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	bis (r0), @^x426(r3)
	bpt
; 431
	mov	#^x8497, r0
	mov	#^x606A, r1
	mov	#^x7662, r2
	mov	#^x6683, r3
	mov	#^xC4A3, r4
	mov	#^x2DC3, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	add @-(r1), r1
	bpt
; 432
	mov	#^xD07A, r0
	mov	#^x1, r1
	mov	#^x7FFE, r2
	mov	#^xFF80, r3
	mov	#^x8000, r4
	mov	#^xE399, r5
	mov	#^x7000, sp
	ccc
	bisb ^x7c0a(r5), r5
	bpt
; 433
	mov	#^xFFFF, r0
	mov	#^x50AF, r1
	mov	#^xFFFE, r2
	mov	#^x8000, r3
	mov	#^x7FFE, r4
	mov	#^xFFFE, r5
	mov	#^x7000, sp
	ccc
	ror (sp)
	bpt
; 434
	mov	#^x0, r0
	mov	#^xFF7F, r1
	mov	#^xB359, r2
	mov	#^x5818, r3
	mov	#^xFF7F, r4
	mov	#^x609C, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	bisb 84(sp), @-(r5)
	bpt
; 435
	mov	#^x7FFE, r0
	mov	#^x0, r1
	mov	#^x602E, r2
	mov	#^x60A4, r3
	mov	#^xF8CE, r4
	mov	#^x21CF, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	bic @(r3)+, @-(r2)
	bpt
; 436
	mov	#^x9C32, r0
	mov	#^x2, r1
	mov	#^x877B, r2
	mov	#^xF4DD, r3
	mov	#^x9E39, r4
	mov	#^x728B, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	clv
	bpt
; 437
	mov	#^x60CE, r0
	mov	#^x9FDB, r1
	mov	#^x7FFE, r2
	mov	#^x7F, r3
	mov	#^x81A5, r4
	mov	#^xD3D1, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	mfpd @-(r0)
	bpt
; 438
	mov	#^x6014, r0
	mov	#^x0, r1
	mov	#^xAB01, r2
	mov	#^x1, r3
	mov	#^x1, r4
	mov	#^x95C1, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	cmpb @(r0)+, #^x100
	bpt
; 439
	mov	#^x5293, r0
	mov	#^xFFFE, r1
	mov	#^x554C, r2
	mov	#^xB59A, r3
	mov	#^x8932, r4
	mov	#^xC07C, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	movb (r0), (r2)+
	bpt
; 440
	mov	#^xEDA9, r0
	mov	#^x0, r1
	mov	#^xA530, r2
	mov	#^x12F7, r3
	mov	#^xF082, r4
	mov	#^xFF7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	clv
	bpt
; 441
	mov	#^x3A00, r0
	mov	#^xFF7F, r1
	mov	#^x427E, r2
	mov	#^x1, r3
	mov	#^x8001, r4
	mov	#^x2727, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	clr r1
	bpt
; 442
	mov	#^x9666, r0
	mov	#^x7172, r1
	mov	#^x7FFE, r2
	mov	#^x7EAB, r3
	mov	#^x7F, r4
	mov	#^x0, r5
	mov	#^x7000, sp
	ccc
	dec ^xd3bf(r3)
	bpt
; 443
	mov	#^x78B0, r0
	mov	#^xC80C, r1
	mov	#^x0, r2
	mov	#^x7FFE, r3
	mov	#^x5882, r4
	mov	#^xD519, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	sub @^x84c(r4), (r4)+
	bpt
; 444
	mov	#^xDFC, r0
	mov	#^x7FFE, r1
	mov	#^xB26E, r2
	mov	#^x8000, r3
	mov	#^x51A3, r4
	mov	#^x970C, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	asrb -(r4)
	bpt
; 445
	mov	#^x609E, r0
	mov	#^xB53F, r1
	mov	#^xE30F, r2
	mov	#^x5784, r3
	mov	#^x7931, r4
	mov	#^x7FFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	bit @^x90a(r3), @-(r0)
	bpt
; 446
	mov	#^x5726, r0
	mov	#^x4C2B, r1
	mov	#^xF8CF, r2
	mov	#^xB041, r3
	mov	#^x8000, r4
	mov	#^xD3C6, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	ror -(r0)
	bpt
; 447
	mov	#^x21C0, r0
	mov	#^x51D8, r1
	mov	#^x7162, r2
	mov	#^x41CE, r3
	mov	#^x8000, r4
	mov	#^xCF56, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	bicb -(r1), @^x3f18(r0)
	bpt
; 448
	mov	#^x2, r0
	mov	#^x72F5, r1
	mov	#^x0, r2
	mov	#^x58C8, r3
	mov	#^x5690, r4
	mov	#^xA60F, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	bis @^xa04(r4), -(r4)
	bpt
; 449
	mov	#^x53ED, r0
	mov	#^x1F06, r1
	mov	#^xE1BB, r2
	mov	#^xDAC3, r3
	mov	#^x1, r4
	mov	#^x2E2E, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	movb (r0)+, @^x60c3(r4)
	bpt
; 450
	mov	#^x1, r0
	mov	#^x54B8, r1
	mov	#^x57FA, r2
	mov	#^x2E1A, r3
	mov	#^x6B8A, r4
	mov	#^x6D23, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	add (r1), (r2)
	bpt
; 451
	mov	#^x7FFF, r0
	mov	#^xB103, r1
	mov	#^xFFFE, r2
	mov	#^x55A7, r3
	mov	#^xFFFF, r4
	mov	#^x549D, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	adcb -(r5)
	bpt
; 452
	mov	#^xB877, r0
	mov	#^x100, r1
	mov	#^x328E, r2
	mov	#^xFF, r3
	mov	#^x80, r4
	mov	#^x604C, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	ashc @(r5)+, r3
	bpt
; 453
	mov	#^x6C76, r0
	mov	#^x5828, r1
	mov	#^x1, r2
	mov	#^xD86A, r3
	mov	#^x8000, r4
	mov	#^x2FFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	cmp r0, r2
	bpt
; 454
	mov	#^xE8D5, r0
	mov	#^x3, r1
	mov	#^x5498, r2
	mov	#^x67E4, r3
	mov	#^x8000, r4
	mov	#^xF9B9, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	mul (r2)+, r3
	bpt
; 455
	mov	#^x8001, r0
	mov	#^x7FFF, r1
	mov	#^xFFFE, r2
	mov	#^x6042, r3
	mov	#^x52BC, r4
	mov	#^x7FFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	swab @-(r3)
	bpt
; 456
	mov	#^x7D9D, r0
	mov	#^xE0EF, r1
	mov	#^xFF80, r2
	mov	#^xE09D, r3
	mov	#^x5C7C, r4
	mov	#^xA3BA, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	ashc (r4)+, r3
	bpt
; 457
	mov	#^xFF7F, r0
	mov	#^x6090, r1
	mov	#^x562A, r2
	mov	#^xE66F, r3
	mov	#^x1D87, r4
	mov	#^x32D8, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	bit (r2), @-(r1)
	bpt
; 458
	mov	#^x4D87, r0
	mov	#^xFFFF, r1
	mov	#^x8000, r2
	mov	#^x14BE, r3
	mov	#^x6641, r4
	mov	#^xA7BF, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	swab r2
	bpt
; 459
	mov	#^xF3F9, r0
	mov	#^xFF7F, r1
	mov	#^x7FFE, r2
	mov	#^x5356, r3
	mov	#^x24EB, r4
	mov	#^xC4B4, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	bit r1, (r3)
	bpt
; 460
	mov	#^x594D, r0
	mov	#^x7FFE, r1
	mov	#^x57CC, r2
	mov	#^x7FFF, r3
	mov	#^x5987, r4
	mov	#^x14FB, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	ror (r2)+
	bpt
; 461
	mov	#^x8001, r0
	mov	#^x7D4F, r1
	mov	#^x55CC, r2
	mov	#^xFFFE, r3
	mov	#^x2, r4
	mov	#^xFF80, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	mul -(r2), r1
	bpt
; 462
	mov	#^x589A, r0
	mov	#^xFF, r1
	mov	#^x8836, r2
	mov	#^xFF80, r3
	mov	#^x7F, r4
	mov	#^x7F42, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	bic ^x55a3(r1), -(r0)
	bpt
; 463
	mov	#^x8446, r0
	mov	#^xAA8C, r1
	mov	#^xBAB8, r2
	mov	#^xFFFE, r3
	mov	#^x3816, r4
	mov	#^xFF7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	clv
	bpt
; 464
	mov	#^x7FFE, r0
	mov	#^x5209, r1
	mov	#^x100, r2
	mov	#^xEAC, r3
	mov	#^x30CF, r4
	mov	#^x7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	bitb -(r1), 66(sp)
	bpt
; 465
	mov	#^x4C13, r0
	mov	#^x8000, r1
	mov	#^x823E, r2
	mov	#^x8D68, r3
	mov	#^x7FC2, r4
	mov	#^xA4B3, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	tstb ^x5c18
	bpt
; 466
	mov	#^xF208, r0
	mov	#^x18EE, r1
	mov	#^x21FB, r2
	mov	#^x8F0A, r3
	mov	#^x5348, r4
	mov	#^x8646, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	ash (r4)+, r3
	bpt
; 467
	mov	#^xAE24, r0
	mov	#^x60A4, r1
	mov	#^x544B, r2
	mov	#^xBA5D, r3
	mov	#^x7372, r4
	mov	#^x1, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	bicb (r2)+, @(r1)+
	bpt
; 468
	mov	#^x9D3A, r0
	mov	#^x9FCF, r1
	mov	#^x8000, r2
	mov	#^xC32, r3
	mov	#^x80, r4
	mov	#^x6AD5, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	cmpb @^x606e(r4), ^xe9e1(r5)
	bpt
; 469
	mov	#^x80, r0
	mov	#^xFFFE, r1
	mov	#^xD729, r2
	mov	#^xFF7F, r3
	mov	#^x609C, r4
	mov	#^xCFE1, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	ashc @-(r4), r1
	bpt
; 470
	mov	#^xAA25, r0
	mov	#^x8000, r1
	mov	#^xFF7F, r2
	mov	#^x6A64, r3
	mov	#^x3E7D, r4
	mov	#^x1C4D, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	nop
	bpt
; 471
	mov	#^x100, r0
	mov	#^x5CFC, r1
	mov	#^x413C, r2
	mov	#^x7FFF, r3
	mov	#^xFFBD, r4
	mov	#^x5443, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	bic -(r1), r5
	bpt
; 472
	mov	#^xEB31, r0
	mov	#^x1C3F, r1
	mov	#^xBA7D, r2
	mov	#^xC2A0, r3
	mov	#^x6042, r4
	mov	#^xF9E3, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	cmpb ^x424e(r1), @-(r4)
	bpt
; 473
	mov	#^xCC55, r0
	mov	#^xFFFF, r1
	mov	#^xFFFF, r2
	mov	#^x60D6, r3
	mov	#^x96B3, r4
	mov	#^x59E5, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	tst @-(r3)
	bpt
; 474
	mov	#^x4335, r0
	mov	#^x3F98, r1
	mov	#^x3DE6, r2
	mov	#^x2571, r3
	mov	#^x6F5A, r4
	mov	#^xFFFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	bit ^x1388(r2), ^x1930(r1)
	bpt
; 475
	mov	#^x1, r0
	mov	#^xB2AA, r1
	mov	#^xC056, r2
	mov	#^x5353, r3
	mov	#^x7FFE, r4
	mov	#^x9B59, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	tstb -(r3)
	bpt
; 476
	mov	#^x64C2, r0
	mov	#^xEDE5, r1
	mov	#^x8001, r2
	mov	#^x14CF, r3
	mov	#^x1, r4
	mov	#^x52DA, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	asl (r5)+
	bpt
; 477
	mov	#^x8001, r0
	mov	#^x605A, r1
	mov	#^x8001, r2
	mov	#^xD5BB, r3
	mov	#^x964F, r4
	mov	#^x5882, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	sub (r5)+, @-(r1)
	bpt
; 478
	mov	#^x3546, r0
	mov	#^x8000, r1
	mov	#^x5192, r2
	mov	#^x605A, r3
	mov	#^xFEA7, r4
	mov	#^xFF80, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	bic @-(r3), @(r3)+
	bpt
; 479
	mov	#^x48A5, r0
	mov	#^x9FED, r1
	mov	#^x38F, r2
	mov	#^x3D10, r3
	mov	#^xFFFE, r4
	mov	#^x7FFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	bisb (sp)+, ^x54f3
	bpt
; 480
	mov	#^xE8A0, r0
	mov	#^xFE50, r1
	mov	#^x347B, r2
	mov	#^x6080, r3
	mov	#^x5AE2, r4
	mov	#^xC513, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	sub -(r4), @-(r3)
	bpt
; 481
	mov	#^xCA14, r0
	mov	#^x1, r1
	mov	#^xFFFE, r2
	mov	#^xA306, r3
	mov	#^x6068, r4
	mov	#^x9E6A, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	cmp @-(r4), ^xf068(r4)
	bpt
; 482
	mov	#^xE649, r0
	mov	#^xF10E, r1
	mov	#^x7F, r2
	mov	#^xACC2, r3
	mov	#^x1013, r4
	mov	#^xFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	bit ^x6dc6(r1), @^xb37a(r3)
	bpt
; 483
	mov	#^x2B40, r0
	mov	#^x60DC, r1
	mov	#^x2, r2
	mov	#^x7FFF, r3
	mov	#^x7FFF, r4
	mov	#^x8A65, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	mov ^xc7cd(r5), @-(r1)
	bpt
; 484
	mov	#^x5EEF, r0
	mov	#^x80, r1
	mov	#^xA9CF, r2
	mov	#^xFFFF, r3
	mov	#^x834, r4
	mov	#^x6022, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	div @(r5)+, r2
	bpt
; 485
	mov	#^x0, r0
	mov	#^x80, r1
	mov	#^x458, r2
	mov	#^xFFFF, r3
	mov	#^x49D0, r4
	mov	#^x60B4, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	bit #^xda01, @(r5)+
	bpt
; 486
	mov	#^xBEA7, r0
	mov	#^x51A0, r1
	mov	#^x9C1B, r2
	mov	#^x5666, r3
	mov	#^x7F, r4
	mov	#^xFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	add (r1), (r3)+
	bpt
; 487
	mov	#^xA393, r0
	mov	#^x100, r1
	mov	#^xB331, r2
	mov	#^x3286, r3
	mov	#^xE251, r4
	mov	#^x9921, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	mfpd @^x7de9(r4)
	bpt
; 488
	mov	#^x7FFE, r0
	mov	#^x80, r1
	mov	#^x4D56, r2
	mov	#^x1, r3
	mov	#^x5B98, r4
	mov	#^x7100, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	bis (r4), r5
	bpt
; 489
	mov	#^xAF3C, r0
	mov	#^x5EA0, r1
	mov	#^xFF, r2
	mov	#^x5321, r3
	mov	#^x84AC, r4
	mov	#^x7FFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	bitb -(r1), @^xe0dc(r5)
	bpt
; 490
	mov	#^x2854, r0
	mov	#^x1, r1
	mov	#^xF6AD, r2
	mov	#^xA72F, r3
	mov	#^x7FFE, r4
	mov	#^x6B9F, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	sub @^x37fe(r0), @^x6979(r2)
	bpt
; 491
	mov	#^xAD6D, r0
	mov	#^x8E6C, r1
	mov	#^x7C1B, r2
	mov	#^xA68E, r3
	mov	#^xAF35, r4
	mov	#^xFF7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	sen
	bpt
; 492
	mov	#^xCBBF, r0
	mov	#^x7F, r1
	mov	#^x7F, r2
	mov	#^x3373, r3
	mov	#^x584E, r4
	mov	#^x51E6, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	comb -(r4)
	bpt
; 493
	mov	#^x60D2, r0
	mov	#^xEB2, r1
	mov	#^x7F, r2
	mov	#^x7FFE, r3
	mov	#^x74CF, r4
	mov	#^x55E3, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	bisb @-(r0), (r5)
	bpt
; 494
	mov	#^x7F, r0
	mov	#^x8B0B, r1
	mov	#^xFF, r2
	mov	#^x2A31, r3
	mov	#^x606E, r4
	mov	#^x9F36, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	bitb @(r4)+, r4
	bpt
; 495
	mov	#^x7FFE, r0
	mov	#^x6567, r1
	mov	#^x52C4, r2
	mov	#^x9450, r3
	mov	#^xFFFE, r4
	mov	#^x57FE, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	sub -(r2), (r5)+
	bpt
; 496
	mov	#^x4049, r0
	mov	#^x1, r1
	mov	#^x7FFE, r2
	mov	#^x829D, r3
	mov	#^xFF80, r4
	mov	#^xD7A9, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	dec @^x1fdd(r0)
	bpt
; 497
	mov	#^x18FB, r0
	mov	#^xFF80, r1
	mov	#^x6B4C, r2
	mov	#^x6AED, r3
	mov	#^x9E55, r4
	mov	#^x7FFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	mfpi ^xbe4f(r4)
	bpt
; 498
	mov	#^xFFFF, r0
	mov	#^x8900, r1
	mov	#^x60C4, r2
	mov	#^x2DF8, r3
	mov	#^x5D61, r4
	mov	#^x46C2, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	swab @(r2)+
	bpt
; 499
	mov	#^x93BB, r0
	mov	#^x3013, r1
	mov	#^x59D, r2
	mov	#^x33C6, r3
	mov	#^x2EC5, r4
	mov	#^x35F, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	sxt r0
	bpt
; 500
	mov	#^x6867, r0
	mov	#^x7101, r1
	mov	#^xFF7F, r2
	mov	#^xFFFF, r3
	mov	#^x4317, r4
	mov	#^x8001, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	movb @^xef93(r1), (sp)
	bpt
; 501
	mov	#^x60EE, r0
	mov	#^x9275, r1
	mov	#^x7FFF, r2
	mov	#^xCA55, r3
	mov	#^x7F, r4
	mov	#^xC109, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	swab @-(r0)
	bpt
; 502
	mov	#^xF284, r0
	mov	#^x1, r1
	mov	#^xCB1B, r2
	mov	#^x3EF6, r3
	mov	#^xADBA, r4
	mov	#^x2948, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	asl ^x2fc2(r5)
	bpt
; 503
	mov	#^xC530, r0
	mov	#^x97A7, r1
	mov	#^x8D47, r2
	mov	#^xD750, r3
	mov	#^xD494, r4
	mov	#^xFFFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	tst @^x60e0
	bpt
; 504
	mov	#^x60A0, r0
	mov	#^x80, r1
	mov	#^x65B4, r2
	mov	#^x2614, r3
	mov	#^xEF64, r4
	mov	#^xA3E9, r5
	mov	#^x7000, sp
	ccc
	mtpi @(r0)+
	bpt
; 505
	mov	#^x7E22, r0
	mov	#^xA7BF, r1
	mov	#^xFECF, r2
	mov	#^x3BC4, r3
	mov	#^xFF80, r4
	mov	#^xC27C, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	sbcb ^x5d46
	bpt
; 506
	mov	#^xE356, r0
	mov	#^xD1FC, r1
	mov	#^x1B9A, r2
	mov	#^x0, r3
	mov	#^xC0BE, r4
	mov	#^x56B6, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	bic @^x44e2(r2), (r5)+
	bpt
; 507
	mov	#^x6024, r0
	mov	#^x21DA, r1
	mov	#^x3427, r2
	mov	#^x18ED, r3
	mov	#^xF3D1, r4
	mov	#^x6B0A, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	div @-(r0), r2
	bpt
; 508
	mov	#^xA02A, r0
	mov	#^x2C4D, r1
	mov	#^x80C2, r2
	mov	#^x1A8A, r3
	mov	#^x80, r4
	mov	#^xFF7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	mul ^x5b76, r0
	bpt
; 509
	mov	#^xFFFF, r0
	mov	#^xFFFE, r1
	mov	#^x7F, r2
	mov	#^x873A, r3
	mov	#^x1, r4
	mov	#^xFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	mul @^x5f49(r5), r5
	bpt
; 510
	mov	#^xF06F, r0
	mov	#^x7033, r1
	mov	#^x8000, r2
	mov	#^x80, r3
	mov	#^x6020, r4
	mov	#^x9268, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	mfpd @-(r4)
	bpt
; 511
	mov	#^x55C5, r0
	mov	#^x782E, r1
	mov	#^xFF4F, r2
	mov	#^x4AFB, r3
	mov	#^xC2F6, r4
	mov	#^x7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	div @^x6039(r5), r0
	bpt
; 512
	mov	#^x6026, r0
	mov	#^x60DE, r1
	mov	#^x3633, r2
	mov	#^x7FFE, r3
	mov	#^x2, r4
	mov	#^x46EC, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	incb @-(r0)
	bpt
; 513
	mov	#^xEA42, r0
	mov	#^x1627, r1
	mov	#^xFF7F, r2
	mov	#^x7FFF, r3
	mov	#^xFFFE, r4
	mov	#^x100, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	movb @^x6074, r3
	bpt
; 514
	mov	#^x52E0, r0
	mov	#^x25F4, r1
	mov	#^x56D1, r2
	mov	#^x7C53, r3
	mov	#^xDAD7, r4
	mov	#^xE017, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	bis @^x8093(r5), (r0)+
	bpt
; 515
	mov	#^x55E8, r0
	mov	#^x9E1E, r1
	mov	#^xAC53, r2
	mov	#^xFFFF, r3
	mov	#^x4AFE, r4
	mov	#^x8DAB, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	comb (sp)
	bpt
; 516
	mov	#^xF521, r0
	mov	#^xFFFF, r1
	mov	#^x0, r2
	mov	#^x100, r3
	mov	#^x7F, r4
	mov	#^xE7DB, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	mfpi ^x5c5d(r4)
	bpt
; 517
	mov	#^xFA1, r0
	mov	#^xA992, r1
	mov	#^x7303, r2
	mov	#^xB5DC, r3
	mov	#^xF5A2, r4
	mov	#^x2, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	bicb (sp), r3
	bpt
; 518
	mov	#^x8000, r0
	mov	#^xFF, r1
	mov	#^xFF, r2
	mov	#^x1BAA, r3
	mov	#^xF412, r4
	mov	#^xA6A, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	sxt r0
	bpt
; 519
	mov	#^x6575, r0
	mov	#^x7FFF, r1
	mov	#^x7FFF, r2
	mov	#^xD82C, r3
	mov	#^xFF7F, r4
	mov	#^xECE7, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	rolb ^x8576(r3)
	bpt
; 520
	mov	#^x0, r0
	mov	#^xF501, r1
	mov	#^x2DB9, r2
	mov	#^x3504, r3
	mov	#^x7F, r4
	mov	#^x3675, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	mtpd ^x528e(r0)
	bpt
; 521
	mov	#^x31CD, r0
	mov	#^x2E5, r1
	mov	#^xCCCA, r2
	mov	#^x7F, r3
	mov	#^x9978, r4
	mov	#^x7FFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	movb ^x57a0, ^xd102(r5)
	bpt
; 522
	mov	#^x7130, r0
	mov	#^x5854, r1
	mov	#^xD4FF, r2
	mov	#^xFF7F, r3
	mov	#^x7F, r4
	mov	#^x3432, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	sub -(r1), (r1)+
	bpt
; 523
	mov	#^xB0D6, r0
	mov	#^x7FFF, r1
	mov	#^xA69, r2
	mov	#^xBB22, r3
	mov	#^x1909, r4
	mov	#^x4B6A, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	asr ^x5e5c
	bpt
; 524
	mov	#^xB38A, r0
	mov	#^x8325, r1
	mov	#^x50EE, r2
	mov	#^xFF80, r3
	mov	#^xAEDC, r4
	mov	#^xE0EA, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	sxt @^xdd8b(r1)
	bpt
; 525
	mov	#^xFF, r0
	mov	#^x2, r1
	mov	#^x22F2, r2
	mov	#^xFD7, r3
	mov	#^x60DA, r4
	mov	#^xFF7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	sub @(r4)+, (sp)
	bpt
; 526
	mov	#^x881A, r0
	mov	#^x5BAA, r1
	mov	#^xEC26, r2
	mov	#^xBD94, r3
	mov	#^x60E2, r4
	mov	#^x9411, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	bic r2, @-(r4)
	bpt
; 527
	mov	#^x100, r0
	mov	#^x513E, r1
	mov	#^xE018, r2
	mov	#^x792F, r3
	mov	#^xFF7F, r4
	mov	#^x44D5, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	com -(r1)
	bpt
; 528
	mov	#^x1, r0
	mov	#^x5C20, r1
	mov	#^x80, r2
	mov	#^x0, r3
	mov	#^x7FFF, r4
	mov	#^xE439, r5
	mov	#^x7000, sp
	ccc
	cmp ^x5bb2, (r1)+
	bpt
; 529
	mov	#^x1, r0
	mov	#^xFF80, r1
	mov	#^x5DF6, r2
	mov	#^x2, r3
	mov	#^xE612, r4
	mov	#^xFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	sub (r2)+, @^x60ce(r1)
	bpt
; 530
	mov	#^xFF7F, r0
	mov	#^xFFFF, r1
	mov	#^x5E46, r2
	mov	#^x8000, r3
	mov	#^xDD9B, r4
	mov	#^xFDCB, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	sbcb (r2)
	bpt
; 531
	mov	#^x2, r0
	mov	#^xBD3E, r1
	mov	#^x100, r2
	mov	#^x7FFF, r3
	mov	#^x80, r4
	mov	#^x682F, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	rol -(sp)
	bpt
; 532
	mov	#^xA943, r0
	mov	#^xAB0C, r1
	mov	#^x82E6, r2
	mov	#^x5B40, r3
	mov	#^x8001, r4
	mov	#^xFFFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	sbc (r3)
	bpt
; 533
	mov	#^x52D4, r0
	mov	#^xFFFF, r1
	mov	#^x8BF9, r2
	mov	#^x487A, r3
	mov	#^x6624, r4
	mov	#^xFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	bic -(r0), ^x780(r0)
	bpt
; 534
	mov	#^x6459, r0
	mov	#^x5AB0, r1
	mov	#^x7A29, r2
	mov	#^xFF80, r3
	mov	#^xFFFF, r4
	mov	#^x62E9, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	cmp (r1), r3
	bpt
; 535
	mov	#^x8001, r0
	mov	#^x27EA, r1
	mov	#^x56FC, r2
	mov	#^x3DC2, r3
	mov	#^x8000, r4
	mov	#^x1EA9, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	mul (r2), r0
	bpt
; 536
	mov	#^x53F8, r0
	mov	#^xFF, r1
	mov	#^xE80, r2
	mov	#^xC01B, r3
	mov	#^x2809, r4
	mov	#^x0, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	mov ^x7ee(r0), -(r0)
	bpt
; 537
	mov	#^x1, r0
	mov	#^xEC27, r1
	mov	#^xB61E, r2
	mov	#^xFF, r3
	mov	#^x60BA, r4
	mov	#^x8BC1, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	decb @(r4)+
	bpt
; 538
	mov	#^xD9F1, r0
	mov	#^x2702, r1
	mov	#^xE927, r2
	mov	#^x6B1C, r3
	mov	#^xC21B, r4
	mov	#^x6032, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	mul @-(r5), r2
	bpt
; 539
	mov	#^x5A50, r0
	mov	#^x9841, r1
	mov	#^xFF7F, r2
	mov	#^x4A2E, r3
	mov	#^xB981, r4
	mov	#^x4CFC, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	adcb -(r0)
	bpt
; 540
	mov	#^xA5C1, r0
	mov	#^x8EF, r1
	mov	#^xAD92, r2
	mov	#^xB780, r3
	mov	#^x605C, r4
	mov	#^x60B6, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	bitb @(r5)+, @(r4)+
	bpt
; 541
	mov	#^x9066, r0
	mov	#^x4C10, r1
	mov	#^x8001, r2
	mov	#^xE06F, r3
	mov	#^x80, r4
	mov	#^x6F73, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	movb ^xc380(r0), r4
	bpt
; 542
	mov	#^x165F, r0
	mov	#^x100, r1
	mov	#^xC7E4, r2
	mov	#^x62F, r3
	mov	#^xABD7, r4
	mov	#^x7FFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	bis ^x9398(r2), -108(sp)
	bpt
; 543
	mov	#^x111F, r0
	mov	#^x26BE, r1
	mov	#^x1296, r2
	mov	#^x53BE, r3
	mov	#^xE1BF, r4
	mov	#^x515F, r5
	mov	#^x7000, sp
	ccc
	.word	^o275		; set 0b1101
	bis @#^x545a, (r3)
	bpt
; 544
	mov	#^x100, r0
	mov	#^xFFFF, r1
	mov	#^x51D2, r2
	mov	#^xF9A2, r3
	mov	#^x5826, r4
	mov	#^x6966, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	sub (r2), (r4)+
	bpt
; 545
	mov	#^x80, r0
	mov	#^xFFFF, r1
	mov	#^x68F4, r2
	mov	#^x8001, r3
	mov	#^x6016, r4
	mov	#^x88F0, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	bis ^x5602, @-(r4)
	bpt
; 546
	mov	#^x7FFF, r0
	mov	#^xAD7C, r1
	mov	#^x6076, r2
	mov	#^x56F4, r3
	mov	#^x7F, r4
	mov	#^x310, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	add (r3)+, @-(r2)
	bpt
; 547
	mov	#^xE5DF, r0
	mov	#^x7F, r1
	mov	#^xEE20, r2
	mov	#^x100, r3
	mov	#^xC7F7, r4
	mov	#^x8000, r5
	mov	#^x7000, sp
	ccc
	swab @^x60fe
	bpt
; 548
	mov	#^x631, r0
	mov	#^x7F, r1
	mov	#^x1777, r2
	mov	#^x2D99, r3
	mov	#^x7FFF, r4
	mov	#^x5C40, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	mul (r5)+, r2
	bpt
; 549
	mov	#^xFFFE, r0
	mov	#^x7FFE, r1
	mov	#^x416A, r2
	mov	#^xA791, r3
	mov	#^x572A, r4
	mov	#^xE5D7, r5
	mov	#^x7000, sp
	ccc
	swab -(r4)
	bpt
; 550
	mov	#^x9DC6, r0
	mov	#^xFCC6, r1
	mov	#^x7D3C, r2
	mov	#^x7FFE, r3
	mov	#^x5177, r4
	mov	#^x3106, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	movb (r4), r2
	bpt
; 551
	mov	#^xE1DA, r0
	mov	#^xFFFF, r1
	mov	#^xFF7F, r2
	mov	#^x491C, r3
	mov	#^xB16F, r4
	mov	#^x100, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	tst r4
	bpt
; 552
	mov	#^x8BAE, r0
	mov	#^x3EC2, r1
	mov	#^xA78E, r2
	mov	#^xD01E, r3
	mov	#^x7FFE, r4
	mov	#^xB375, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	tst @^xe0c6(r4)
	bpt
; 553
	mov	#^x4769, r0
	mov	#^x94E8, r1
	mov	#^x6096, r2
	mov	#^xB769, r3
	mov	#^x536D, r4
	mov	#^x7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	dec @-(r2)
	bpt
; 554
	mov	#^xFFFF, r0
	mov	#^xF860, r1
	mov	#^x2455, r2
	mov	#^xBF43, r3
	mov	#^x8B3C, r4
	mov	#^x12D, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	sen
	bpt
; 555
	mov	#^x2632, r0
	mov	#^x3604, r1
	mov	#^x1EA4, r2
	mov	#^x100, r3
	mov	#^x7FFE, r4
	mov	#^x5549, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	movb r0, (r5)+
	bpt
; 556
	mov	#^xFF7F, r0
	mov	#^x571C, r1
	mov	#^x542C, r2
	mov	#^xFFFE, r3
	mov	#^x2, r4
	mov	#^x3D0C, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	cmpb (r1), (r2)
	bpt
; 557
	mov	#^xBBE, r0
	mov	#^xFFFF, r1
	mov	#^x100, r2
	mov	#^x8919, r3
	mov	#^x100, r4
	mov	#^xA282, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	comb @^x5f96(r4)
	bpt
; 558
	mov	#^x7FFE, r0
	mov	#^x79A0, r1
	mov	#^x60CC, r2
	mov	#^x2, r3
	mov	#^x8001, r4
	mov	#^x1, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	cmp @-(r2), r1
	bpt
; 559
	mov	#^xA41C, r0
	mov	#^xDA81, r1
	mov	#^xCB53, r2
	mov	#^x5589, r3
	mov	#^x691B, r4
	mov	#^x80, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	movb (sp), ^x5c03
	bpt
; 560
	mov	#^x937D, r0
	mov	#^x7F, r1
	mov	#^x4495, r2
	mov	#^x6044, r3
	mov	#^x8BEB, r4
	mov	#^xFA19, r5
	mov	#^x7000, sp
	ccc
	cmpb @(r3)+, r3
	bpt
; 561
	mov	#^xFF, r0
	mov	#^xFF80, r1
	mov	#^x7F5D, r2
	mov	#^x7F, r3
	mov	#^x517E, r4
	mov	#^x472B, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	com -(r4)
	bpt
; 562
	mov	#^x8000, r0
	mov	#^x2AB1, r1
	mov	#^x8669, r2
	mov	#^x490B, r3
	mov	#^x2, r4
	mov	#^xFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	ash -8(sp), r1
	bpt
; 563
	mov	#^x319D, r0
	mov	#^x601A, r1
	mov	#^x7F, r2
	mov	#^xE208, r3
	mov	#^x8000, r4
	mov	#^x58B8, r5
	mov	#^x7000, sp
	ccc
	cmp (r5), @(r1)+
	bpt
; 564
	mov	#^xF585, r0
	mov	#^xFF7F, r1
	mov	#^x605C, r2
	mov	#^x7FFE, r3
	mov	#^xFF7F, r4
	mov	#^x6012, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	bisb @-(r2), @(r5)+
	bpt
; 565
	mov	#^x124A, r0
	mov	#^x71D0, r1
	mov	#^xDD6, r2
	mov	#^x628C, r3
	mov	#^xFFFE, r4
	mov	#^x4D88, r5
	mov	#^x7000, sp
	ccc
	clr ^x54fe(r4)
	bpt
; 566
	mov	#^xD4C5, r0
	mov	#^x55F0, r1
	mov	#^x1D59, r2
	mov	#^x9326, r3
	mov	#^xB877, r4
	mov	#^x264B, r5
	mov	#^x7000, sp
	ccc
	.word	^o262		; set 0b10
	sub @^xae4(r1), (r1)
	bpt
; 567
	mov	#^x552E, r0
	mov	#^x8709, r1
	mov	#^x80, r2
	mov	#^x8A66, r3
	mov	#^x72E6, r4
	mov	#^x2D2C, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	xor r2, (r0)
	bpt
; 568
	mov	#^x9949, r0
	mov	#^xA5C2, r1
	mov	#^xC522, r2
	mov	#^x6090, r3
	mov	#^x1, r4
	mov	#^x5935, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	cmp @-(r3), ^x5fd9(r4)
	bpt
; 569
	mov	#^xFF80, r0
	mov	#^xF022, r1
	mov	#^x8000, r2
	mov	#^xFF7F, r3
	mov	#^x96D2, r4
	mov	#^x594D, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	cmpb (r5)+, ^xde10(r2)
	bpt
; 570
	mov	#^x55EA, r0
	mov	#^x29E9, r1
	mov	#^xE96, r2
	mov	#^x1F67, r3
	mov	#^x2, r4
	mov	#^x7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o265		; set 0b101
	ash ^x4250(r2), r2
	bpt
; 571
	mov	#^x6036, r0
	mov	#^x5438, r1
	mov	#^x8001, r2
	mov	#^xD7C2, r3
	mov	#^x8E0B, r4
	mov	#^xF65A, r5
	mov	#^x7000, sp
	ccc
	add @-(r0), (r1)
	bpt
; 572
	mov	#^xFFFF, r0
	mov	#^x8000, r1
	mov	#^x3F1, r2
	mov	#^xE2B2, r3
	mov	#^x7F, r4
	mov	#^x18B, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	sec
	bpt
; 573
	mov	#^xFF, r0
	mov	#^x0, r1
	mov	#^xD43, r2
	mov	#^x7E9D, r3
	mov	#^x53C9, r4
	mov	#^x3D1, r5
	mov	#^x7000, sp
	ccc
	.word	^o272		; set 0b1010
	negb -(r4)
	bpt
; 574
	mov	#^xFFFE, r0
	mov	#^xEDE2, r1
	mov	#^x997E, r2
	mov	#^xDC8, r3
	mov	#^xFFFF, r4
	mov	#^x60E0, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	adcb @-(r5)
	bpt
; 575
	mov	#^x6028, r0
	mov	#^xC46D, r1
	mov	#^xEF26, r2
	mov	#^x100, r3
	mov	#^x633, r4
	mov	#^xFF7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	dec @(r0)+
	bpt
; 576
	mov	#^xF35A, r0
	mov	#^x9F50, r1
	mov	#^x7FFF, r2
	mov	#^x8A15, r3
	mov	#^x4C5F, r4
	mov	#^xFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	bicb @^xe08d(r2), #^xb169
	bpt
; 577
	mov	#^x5173, r0
	mov	#^x25B3, r1
	mov	#^xB5AA, r2
	mov	#^x69E9, r3
	mov	#^x258B, r4
	mov	#^x58DF, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	bicb (r0)+, (r5)+
	bpt
; 578
	mov	#^xFFFE, r0
	mov	#^x2F66, r1
	mov	#^x5D6C, r2
	mov	#^x32A2, r3
	mov	#^xE934, r4
	mov	#^x1, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	incb -(r2)
	bpt
; 579
	mov	#^x6994, r0
	mov	#^x5368, r1
	mov	#^x8BB5, r2
	mov	#^x8001, r3
	mov	#^x100, r4
	mov	#^x60EA, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	bit @(r5)+, (r1)
	bpt
; 580
	mov	#^x2B9D, r0
	mov	#^x1601, r1
	mov	#^x5E8F, r2
	mov	#^xAA71, r3
	mov	#^xAD4E, r4
	mov	#^xB966, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	bisb (r2), @^x60aa
	bpt
; 581
	mov	#^xB4AB, r0
	mov	#^x50C4, r1
	mov	#^xCCBC, r2
	mov	#^x97B6, r3
	mov	#^x100, r4
	mov	#^x52CA, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	dec (r5)
	bpt
; 582
	mov	#^x4DB0, r0
	mov	#^xBA16, r1
	mov	#^xBA15, r2
	mov	#^x9369, r3
	mov	#^xCA6E, r4
	mov	#^xFF80, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	inc ^x5d48
	bpt
; 583
	mov	#^x8001, r0
	mov	#^x19F0, r1
	mov	#^x373C, r2
	mov	#^x994D, r3
	mov	#^x1D8B, r4
	mov	#^x703A, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	mfpi (sp)
	bpt
; 584
	mov	#^x9D61, r0
	mov	#^x554C, r1
	mov	#^xDD51, r2
	mov	#^x3477, r3
	mov	#^x3F3C, r4
	mov	#^x7FFE, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	bit @#^x596a, (r1)+
	bpt
; 585
	mov	#^x7FFF, r0
	mov	#^x60E6, r1
	mov	#^x7FFE, r2
	mov	#^x970B, r3
	mov	#^xA03E, r4
	mov	#^x7FFF, r5
	mov	#^x7000, sp
	ccc
	mfpi @-(r1)
	bpt
; 586
	mov	#^x60AC, r0
	mov	#^x6973, r1
	mov	#^xFF80, r2
	mov	#^x4F31, r3
	mov	#^x418A, r4
	mov	#^x7F3D, r5
	mov	#^x7000, sp
	ccc
	.word	^o271		; set 0b1001
	mov r0, @(r0)+
	bpt
; 587
	mov	#^x6DC6, r0
	mov	#^x457B, r1
	mov	#^x602A, r2
	mov	#^x0, r3
	mov	#^xFF, r4
	mov	#^x568E, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	swab @(r2)+
	bpt
; 588
	mov	#^xEEB, r0
	mov	#^x7F15, r1
	mov	#^xF864, r2
	mov	#^x7F, r3
	mov	#^x77B7, r4
	mov	#^x8BA7, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	ash r4, r4
	bpt
; 589
	mov	#^x7F, r0
	mov	#^x9220, r1
	mov	#^x60D0, r2
	mov	#^x7FFF, r3
	mov	#^x8B82, r4
	mov	#^x807E, r5
	mov	#^x7000, sp
	ccc
	.word	^o273		; set 0b1011
	sub @(r2)+, r1
	bpt
; 590
	mov	#^xC29D, r0
	mov	#^xC80A, r1
	mov	#^xFF80, r2
	mov	#^x8001, r3
	mov	#^x6072, r4
	mov	#^x695E, r5
	mov	#^x7000, sp
	ccc
	.word	^o267		; set 0b111
	ash @-(r4), r3
	bpt
; 591
	mov	#^xFBAD, r0
	mov	#^x94A9, r1
	mov	#^x3B41, r2
	mov	#^x34ED, r3
	mov	#^x603E, r4
	mov	#^xB35C, r5
	mov	#^x7000, sp
	ccc
	.word	^o276		; set 0b1110
	cmpb @^x64f5(r0), @(r4)+
	bpt
; 592
	mov	#^xF5C0, r0
	mov	#^x1, r1
	mov	#^x5F36, r2
	mov	#^xD664, r3
	mov	#^xAB74, r4
	mov	#^x3EAD, r5
	mov	#^x7000, sp
	ccc
	.word	^o277		; set 0b1111
	negb r2
	bpt
; 593
	mov	#^x7FFE, r0
	mov	#^x100, r1
	mov	#^xFF80, r2
	mov	#^xF8A9, r3
	mov	#^xC2A9, r4
	mov	#^xFF80, r5
	mov	#^x7000, sp
	ccc
	.word	^o270		; set 0b1000
	cmp r0, ^x5b1a(r2)
	bpt
; 594
	mov	#^x1, r0
	mov	#^x5BF6, r1
	mov	#^xF157, r2
	mov	#^xA7D6, r3
	mov	#^x1, r4
	mov	#^xFFFF, r5
	mov	#^x7000, sp
	ccc
	.word	^o274		; set 0b1100
	bitb (r1), (r1)+
	bpt
; 595
	mov	#^x8000, r0
	mov	#^x9AB9, r1
	mov	#^x7F, r2
	mov	#^xDBD0, r3
	mov	#^xF26, r4
	mov	#^x4F8F, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	sub ^x7492(r3), r4
	bpt
; 596
	mov	#^x8D90, r0
	mov	#^xD013, r1
	mov	#^xFF, r2
	mov	#^x528A, r3
	mov	#^xE2F2, r4
	mov	#^x524B, r5
	mov	#^x7000, sp
	ccc
	.word	^o264		; set 0b100
	bit ^xc5b4(r0), -(r3)
	bpt
; 597
	mov	#^x572B, r0
	mov	#^x85E8, r1
	mov	#^xCFC7, r2
	mov	#^x537C, r3
	mov	#^xD351, r4
	mov	#^x898D, r5
	mov	#^x7000, sp
	ccc
	.word	^o261		; set 0b1
	rolb (r0)
	bpt
; 598
	mov	#^xDCD6, r0
	mov	#^x100, r1
	mov	#^x52E2, r2
	mov	#^xAC39, r3
	mov	#^xFF80, r4
	mov	#^xFF7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o263		; set 0b11
	mtpi -(r2)
	bpt
; 599
	mov	#^xC565, r0
	mov	#^xCD36, r1
	mov	#^x4405, r2
	mov	#^x7F, r3
	mov	#^x2796, r4
	mov	#^xFF7F, r5
	mov	#^x7000, sp
	ccc
	.word	^o266		; set 0b110
	sez
	bpt
	emt	^o377
	.vax
; the data area, the pointer table (into the data area), the stack
	.org	^x5000
	.word	^x67B2, ^xD128, ^xAB72, ^x34EC, ^xBEB8, ^x0E2A, ^x27A8, ^xE220
	.word	^xBD08, ^x9419, ^x43AD, ^x4572, ^x618D, ^x7B43, ^x3617, ^xB1FE
	.word	^x8EF4, ^xB6FF, ^x0064, ^x7AC7, ^xB1C7, ^xA056, ^xBC40, ^x62B7
	.word	^x1714, ^x8BD6, ^xCDA5, ^x0055, ^xBF1D, ^x4667, ^x9395, ^x5719
	.word	^xFE14, ^xB3B7, ^xAA01, ^xC4E5, ^x78F7, ^x32ED, ^x2923, ^x7B0B
	.word	^x198F, ^xE533, ^x0E83, ^x52CD, ^x363A, ^xB050, ^xB7AE, ^x885E
	.word	^xB275, ^x3EE3, ^xEFD2, ^x7D4D, ^xCAFB, ^x2251, ^x06DD, ^x818E
	.word	^x8FE5, ^x262F, ^x0B90, ^xB961, ^x0B2E, ^x6D92, ^x37CF, ^xE510
	.word	^x27D4, ^xFDF5, ^xF3C6, ^xE7CD, ^x2642, ^x2FAC, ^xFA0D, ^x73A4
	.word	^xDEED, ^xF3CA, ^xCD1F, ^xF99C, ^x5FD6, ^x6C24, ^x2CAA, ^xF0BB
	.word	^x33A1, ^x08B3, ^x201F, ^xBDBC, ^x986B, ^x6E65, ^x10D0, ^xCBF1
	.word	^x34F7, ^xF004, ^xE46F, ^x5BCD, ^x9271, ^x7DE5, ^x889F, ^x69AA
	.word	^xAF58, ^x6D3F, ^x59B5, ^x55C1, ^x8992, ^x037A, ^x37C0, ^xF3D8
	.word	^x5551, ^x5F13, ^x9F50, ^xF37A, ^x2A70, ^xE290, ^xCB17, ^x47E2
	.word	^xAEA1, ^x43B8, ^x2201, ^xE461, ^x9B3A, ^x91F1, ^xB35B, ^x330B
	.word	^x3490, ^x9E94, ^x250A, ^xC809, ^xA97B, ^xDE58, ^x9FDA, ^xFADD
	.word	^x41A7, ^x1D57, ^x1FD7, ^x2DC7, ^x7E0C, ^xB313, ^xB457, ^x0B6D
	.word	^x5920, ^xC0EC, ^xB06A, ^x45BF, ^x4D49, ^x65B3, ^x3D0A, ^xEBED
	.word	^xA45F, ^x71A9, ^x93E5, ^xCD22, ^x3F68, ^x76ED, ^xFF3B, ^xEE96
	.word	^x16C4, ^x26CC, ^xE820, ^xDA6B, ^x428C, ^x28DE, ^xC763, ^x3B1B
	.word	^xC37A, ^xA962, ^xE537, ^x15A6, ^x5641, ^x6E3B, ^xDD2C, ^xD1F9
	.word	^xD92C, ^x4EEA, ^xE102, ^x064B, ^xEBBD, ^x6679, ^x037C, ^xA1F2
	.word	^x8525, ^x8B09, ^xB630, ^xF2F8, ^xFE2B, ^x8ED2, ^x6A35, ^x2105
	.word	^xC0A7, ^x6227, ^x5042, ^x7C57, ^xEB59, ^x3332, ^x6FB9, ^x7588
	.word	^xFC15, ^xEBCE, ^xA592, ^x5640, ^xBDA1, ^xD8EA, ^x3CE4, ^xF844
	.word	^x5625, ^x4F6B, ^x05A6, ^x519B, ^x8520, ^x099F, ^xA3E5, ^xD466
	.word	^x84CF, ^x27B0, ^x41BD, ^xE1FE, ^x3449, ^xDB36, ^x06E4, ^xC6F0
	.word	^x6A3C, ^xE7C5, ^x2B37, ^x84E2, ^xEE2D, ^x6D7B, ^x84E2, ^x8B5E
	.word	^x31E9, ^xB147, ^xDFDA, ^x09C3, ^x6D53, ^x4100, ^xF3EA, ^xD2AD
	.word	^x3BB0, ^x6E61, ^xF7D3, ^x43C5, ^x57E1, ^xEC1F, ^x40DA, ^x8928
	.word	^x6176, ^x9395, ^xF0F5, ^x3701, ^x7657, ^x06A6, ^x99D7, ^xE045
	.word	^x3548, ^x1757, ^x579B, ^x655C, ^x7688, ^x3BA7, ^x8DFD, ^x2EB9
	.word	^x2891, ^xB164, ^x18C0, ^x5331, ^xA943, ^xCAB8, ^x37AE, ^xE37D
	.word	^xDD27, ^xAD11, ^x6A3B, ^x2402, ^x8B02, ^x4F66, ^x6B1D, ^x25C9
	.word	^x5E28, ^x0AF9, ^x033C, ^x3C1A, ^xA31D, ^x5E28, ^x2446, ^x5AE5
	.word	^x885D, ^xB57A, ^xCFAC, ^xB945, ^x5A4A, ^xCF1A, ^x206D, ^x774B
	.word	^x2FC4, ^xDB7D, ^x0DA5, ^xE399, ^x3B89, ^x4CC2, ^x35B9, ^x2AC0
	.word	^x2CB8, ^x2789, ^x320B, ^x7B46, ^x1819, ^xE591, ^x6B46, ^x0B89
	.word	^x2109, ^x0F31, ^xFC27, ^x91DD, ^xF764, ^xA49B, ^x92F7, ^xF935
	.word	^x100A, ^x011C, ^xF1C7, ^x2889, ^x0E48, ^x57B0, ^x107C, ^x944B
	.word	^xEC69, ^x1404, ^x4EC5, ^xE7C1, ^x61BA, ^xB477, ^x7591, ^xD9A8
	.word	^x5A54, ^xC07C, ^xD0F3, ^x3451, ^xE83F, ^xA77C, ^x22CE, ^x650F
	.word	^x39A9, ^x6E6A, ^x1FA7, ^x33E7, ^x826F, ^xC6BC, ^x9B98, ^xFBF5
	.word	^x6FF3, ^xBB26, ^x5973, ^x8A3D, ^x0E49, ^x8166, ^xF07B, ^x6E97
	.word	^xA544, ^xB497, ^x5642, ^x454E, ^xE90D, ^x733A, ^x815D, ^x2CCB
	.word	^x395B, ^xB7A0, ^x110C, ^xA0AB, ^x923E, ^xCAC7, ^x04A6, ^xB335
	.word	^xB62F, ^xA9C0, ^x97B7, ^x412F, ^x60F7, ^x64B0, ^xFDC5, ^xA5BA
	.word	^x2196, ^x2B36, ^xC1B2, ^x4477, ^x7531, ^x8933, ^x3900, ^x8313
	.word	^x50C7, ^x5D4B, ^xED50, ^xEA83, ^x54DC, ^x39D1, ^x11FF, ^xADDA
	.word	^xE783, ^x3A80, ^xBF11, ^xF7B8, ^xCD99, ^x2FAA, ^x247A, ^x384D
	.word	^x048E, ^xB6A1, ^x0CAE, ^xD220, ^xC7A1, ^x21D6, ^xE2BB, ^x74E8
	.word	^xD271, ^xD1AE, ^xD148, ^x62B6, ^x2934, ^xE547, ^x86C6, ^x5D58
	.word	^x4A49, ^x8A1B, ^x30DB, ^x3B69, ^x8614, ^xB3CA, ^x8F8B, ^x7856
	.word	^x1E79, ^x5639, ^xDC56, ^x5CCA, ^x8F66, ^xB10D, ^x39A4, ^x96E8
	.word	^xB65B, ^x18E8, ^xA110, ^xA95F, ^x5504, ^xED40, ^x8BB0, ^x3517
	.word	^x5F9B, ^xCAE6, ^x550F, ^x9046, ^x71E4, ^xA2F3, ^x9EF2, ^x7EC3
	.word	^x0966, ^x2F41, ^x3A66, ^xF349, ^x6621, ^xC10B, ^x1601, ^x6B43
	.word	^xB17B, ^x7666, ^xD58A, ^x791E, ^x5E79, ^xE4E1, ^x3EC9, ^xFDF4
	.word	^xDBD4, ^xF95A, ^x6583, ^x34AE, ^xE6D4, ^x9C55, ^x90C5, ^x3174
	.word	^x1384, ^x9B83, ^xA6FD, ^xE97F, ^xFE99, ^xF76D, ^x2FC3, ^xBBCE
	.word	^xE1E4, ^x9AB4, ^x0DB2, ^x404C, ^xF405, ^xAB1D, ^x5836, ^xC026
	.word	^x7671, ^x19F2, ^xF979, ^x4466, ^x96D0, ^x5AF8, ^x0A0A, ^x1713
	.word	^x8693, ^xB1DF, ^x51FF, ^x7967, ^x1418, ^x9837, ^x947C, ^x5C42
	.word	^x89C5, ^xEE23, ^xE2F0, ^x2D31, ^x8997, ^x1CC7, ^x738B, ^xC11F
	.word	^xD117, ^x8A1C, ^x658F, ^x8AD4, ^x3087, ^x2EC6, ^x1C93, ^x811A
	.word	^xC2E0, ^x1121, ^x3AE3, ^xB984, ^xAC81, ^xD843, ^xEC11, ^x8B35
	.word	^xE3EC, ^x3FC0, ^xD328, ^x4AE2, ^x619E, ^xA1E4, ^xC35B, ^x742C
	.word	^x3204, ^xE783, ^xA842, ^xF164, ^x170B, ^x7416, ^x6AE6, ^xB18C
	.word	^xF0BC, ^xE23B, ^xC41D, ^x84F3, ^xB847, ^x525C, ^x5A7A, ^x1CEA
	.word	^xDDB0, ^x4D92, ^xBBF2, ^xFAF7, ^x88FC, ^x8673, ^x71D7, ^x2FD5
	.word	^xFBF0, ^x725D, ^xDF15, ^xDCEB, ^x0365, ^x42FC, ^x7B3B, ^xD911
	.word	^xF24B, ^x9223, ^x92AD, ^x26CB, ^x6C28, ^xF700, ^x94B1, ^x4D7A
	.word	^xAFF5, ^x5006, ^x4431, ^xBA71, ^xF1C7, ^x32BA, ^x362C, ^x8014
	.word	^xA821, ^xE56B, ^x47B1, ^x048D, ^xBF75, ^xD377, ^xA259, ^x7EA2
	.word	^x50AE, ^xFC67, ^x8549, ^xE350, ^xE7FB, ^x7CFC, ^xC557, ^xB451
	.word	^x0AA2, ^xB4AC, ^x543E, ^x950F, ^x8335, ^xD882, ^xB057, ^x8504
	.word	^x2663, ^x4C2B, ^xD677, ^x7489, ^xDB80, ^x8F97, ^x6BF8, ^x9BC7
	.word	^xB72C, ^xF7C3, ^x3322, ^x3E90, ^x51E6, ^xEC7F, ^xC819, ^x65E9
	.word	^x8BFC, ^x15CB, ^x5FAE, ^x27BD, ^x0F67, ^xFD8A, ^x6D33, ^xD41F
	.word	^x15FA, ^x37EC, ^x8054, ^xADFF, ^x1706, ^xE650, ^xC29A, ^x2D18
	.word	^x6629, ^x041D, ^x1968, ^xCF9A, ^x9548, ^xA4A6, ^x7DDA, ^x3345
	.word	^x835B, ^x7904, ^xA3D2, ^xCB61, ^x4713, ^x4C0D, ^x7E50, ^x0489
	.word	^xEE15, ^x1152, ^x1CF2, ^x4D60, ^x12BF, ^x7496, ^x7B10, ^xEC83
	.word	^x447E, ^x9BBC, ^x7CAD, ^xA95C, ^x0B13, ^xC44A, ^xD79A, ^xBE9C
	.word	^xE025, ^x950A, ^xE3BF, ^xB585, ^x006F, ^x39F7, ^xFB5A, ^xFE30
	.word	^x7CD0, ^x8DDE, ^xC9A6, ^x8D75, ^xB003, ^xBB8E, ^x66C1, ^xA31C
	.word	^x650A, ^x7386, ^x3B0A, ^x3BDF, ^x15BF, ^x2694, ^x3AA1, ^x0DCB
	.word	^x90A6, ^x3E3A, ^xBC06, ^x343B, ^x87CE, ^x5AD5, ^x3948, ^x025E
	.word	^xFCDF, ^xC36C, ^x503F, ^xC896, ^x71A1, ^x05AC, ^x8765, ^xD8D4
	.word	^xED8E, ^xF84E, ^x287A, ^xA1B8, ^xC695, ^x44B5, ^xF73C, ^x7593
	.word	^x4E5D, ^xA039, ^x4A86, ^x4FD0, ^xB350, ^x3FE5, ^xE1ED, ^xBA6D
	.word	^x29BB, ^xA396, ^xF48B, ^x829D, ^xF6A4, ^x2F07, ^xCBF4, ^x981A
	.word	^x3A3B, ^x5187, ^xDCDF, ^xB197, ^x5759, ^x5739, ^xD4C3, ^x9ACA
	.word	^x8059, ^x406A, ^x4EFB, ^xF056, ^x0EF8, ^x4CF1, ^x68A1, ^x44C2
	.word	^xF4AD, ^xCD08, ^x867C, ^x0460, ^xFEAC, ^x9F7E, ^xCD5C, ^x87C8
	.word	^x2CC0, ^x306F, ^x98CF, ^xD2CC, ^x758A, ^x85B9, ^xDEB6, ^x71A0
	.word	^x6D8F, ^xD2EA, ^x6452, ^x5A25, ^xE3B1, ^x50B1, ^xC1ED, ^x7698
	.word	^xFD3E, ^xF4AA, ^x6638, ^xFD3E, ^x3FB8, ^x537D, ^xEF1C, ^x45BC
	.word	^xD1C5, ^xCE27, ^x586C, ^x4302, ^xEAB7, ^x0C4E, ^x06A1, ^x5770
	.word	^xF080, ^x6BB4, ^x7803, ^x7B27, ^xAD34, ^x77B9, ^x0E4D, ^x263E
	.word	^x1770, ^xDCC3, ^xB5EC, ^x4EFB, ^x3F08, ^x5B69, ^x5FC8, ^xDFC1
	.word	^xBE09, ^x545E, ^x9A9D, ^xC0DC, ^xE674, ^xEB90, ^xFFA6, ^x7A2C
	.word	^xB801, ^xDFEF, ^x7E4C, ^x10AF, ^x0AA6, ^x4948, ^xD413, ^xEA10
	.word	^x275F, ^x3788, ^xC7D9, ^x4967, ^xC4C1, ^x9E9F, ^xFCBD, ^x6F17
	.word	^x6C83, ^xA89E, ^xFB1B, ^x9F5D, ^x135E, ^x137D, ^xC224, ^xC2BF
	.word	^x3C85, ^x19BC, ^x4696, ^x3F5C, ^x6435, ^xA963, ^xEF00, ^x4721
	.word	^xB25E, ^xA992, ^xBF5D, ^x1FFD, ^xB3A3, ^x5D8B, ^xA628, ^x69C3
	.word	^x5496, ^x6FA4, ^x4B31, ^x9BE3, ^x0B1F, ^xE1E3, ^x8251, ^x3E39
	.word	^x425C, ^x4FB8, ^x479B, ^xFEF1, ^xF40C, ^x4B4E, ^x7562, ^xF545
	.word	^x5387, ^xF733, ^x24F4, ^xA261, ^xD826, ^x5B9C, ^xDFEC, ^x77D9
	.word	^x2735, ^x8A51, ^xD44C, ^xC809, ^x40F2, ^x5971, ^x910B, ^xC49F
	.word	^x356A, ^xEADF, ^xA7B8, ^x2807, ^x4355, ^xE069, ^x442B, ^x116F
	.word	^x7888, ^xA9FC, ^x6E26, ^x28CF, ^x6928, ^xE8B8, ^x400A, ^xF894
	.word	^xA86D, ^x1CA4, ^x1A2C, ^x9750, ^xA123, ^xCD19, ^xAE19, ^x7027
	.word	^x9EDC, ^xD5D1, ^xA392, ^x5317, ^x4412, ^xBB2F, ^x76E2, ^xCB31
	.word	^x8C52, ^x8C7C, ^x75DE, ^x2A1F, ^x6D08, ^x77E1, ^xFD19, ^x696F
	.word	^xB620, ^xD518, ^x6889, ^x01D6, ^x5693, ^x5D97, ^x3346, ^xC28D
	.word	^x4DFC, ^xF759, ^xC7F8, ^x396B, ^x92B5, ^xF961, ^xBCDA, ^x2856
	.word	^x2519, ^x8FC8, ^xDBA9, ^x17E7, ^x81A9, ^xD999, ^x279E, ^x0232
	.word	^x3F04, ^xD2EB, ^x6AC7, ^xC1BC, ^xEB29, ^xC535, ^xB1A2, ^x0139
	.word	^x9069, ^x7779, ^x09B2, ^x7AEB, ^x8C71, ^x3357, ^x34ED, ^x0ADF
	.word	^xD441, ^x7DBB, ^x7633, ^x20DA, ^x4F8D, ^xE8E6, ^x4317, ^xC6AE
	.word	^x63B4, ^xDAA9, ^x4038, ^x4FD8, ^x9505, ^xD5C7, ^xAFBA, ^xF786
	.word	^xE4CF, ^x7658, ^x1A4A, ^xE43C, ^x214F, ^xA639, ^x1646, ^x2CF4
	.word	^x8688, ^xC5B6, ^x35CB, ^xCB99, ^xA650, ^x02B8, ^x3369, ^x1CCE
	.word	^x5A6B, ^x95FC, ^x7BD0, ^x9A88, ^x2964, ^x70E1, ^x7301, ^x2DE0
	.word	^x4D5F, ^x54EA, ^xB918, ^x8E84, ^xB33B, ^x6858, ^x900F, ^x8694
	.word	^x6D3B, ^x4DEF, ^x3DF0, ^x0601, ^x65ED, ^x96B8, ^xD3A7, ^xF339
	.word	^xECFE, ^xEB93, ^x84F0, ^xEF37, ^x8308, ^xCFED, ^x9AB7, ^xF67D
	.word	^x679E, ^x9156, ^xC0E7, ^x822F, ^x7829, ^xBC26, ^x370E, ^x224D
	.word	^xF768, ^xA816, ^x64C9, ^x3E9A, ^x15C1, ^xE759, ^xFBA0, ^x5437
	.word	^x5E5F, ^xE91F, ^x78E3, ^x25AF, ^x508D, ^x19C9, ^x90A2, ^x7920
	.word	^x8747, ^xEC55, ^xDA03, ^x140E, ^x8CDC, ^xFD4A, ^xFB4F, ^xCEAF
	.word	^xC203, ^x8DA7, ^x179A, ^x7953, ^x1D5B, ^xB4E5, ^x384D, ^x71B0
	.word	^x7419, ^xD664, ^xE5F9, ^xB1E6, ^x082E, ^x2D9F, ^xAE2B, ^x6C8C
	.word	^xBE59, ^x44E9, ^x13CA, ^x7A4E, ^x92CD, ^x661C, ^x3781, ^xD025
	.word	^x2B27, ^x574B, ^xE58D, ^x6EC9, ^xCB80, ^xADA2, ^x5A06, ^x02DC
	.word	^xB5CC, ^x320C, ^x54B7, ^xBB11, ^x9ACD, ^x1176, ^x304C, ^x091F
	.word	^x741D, ^x55A8, ^x8107, ^x25BB, ^x8F1D, ^x3906, ^xA55B, ^x0961
	.word	^x6DA8, ^x4981, ^x7F90, ^xF57B, ^x3E0F, ^x8002, ^x1441, ^x1F55
	.word	^x2B0B, ^xD555, ^xC759, ^x5E1A, ^xCA72, ^xD40D, ^x1602, ^xF28E
	.word	^xEDF5, ^x2354, ^x650A, ^xD849, ^xA4A0, ^xF9BE, ^x8505, ^x1EF7
	.word	^x95CD, ^x9F63, ^x759F, ^x9E1F, ^x523D, ^xE632, ^xC362, ^x3DC4
	.word	^x48D6, ^x9934, ^xD3EC, ^x978D, ^xA7ED, ^x4335, ^x383A, ^xABAF
	.word	^x2394, ^x5E16, ^x82EE, ^xD12F, ^x24C5, ^x92EB, ^xEDA7, ^x0097
	.word	^xA57D, ^xFEAA, ^x2422, ^x3F6C, ^x0918, ^x1B95, ^x4743, ^x8DB7
	.word	^xE205, ^xC057, ^xA466, ^x9A62, ^xE798, ^x48DF, ^xC34A, ^x79DF
	.word	^xE68D, ^xBEBB, ^xFEE2, ^xDE53, ^x8D33, ^xD7C0, ^x3511, ^x7092
	.word	^xFA30, ^x0888, ^x9164, ^xAE52, ^x0B24, ^x04DF, ^x9464, ^xB531
	.word	^xEBEE, ^xC5D8, ^x2CE5, ^x716C, ^x30CD, ^x8994, ^x9383, ^x102C
	.word	^x40D6, ^xFA75, ^xFAEE, ^x541B, ^x2F1F, ^x4CCF, ^x0F76, ^x6A8E
	.word	^xBE3D, ^x4168, ^x367C, ^x676F, ^x9A92, ^x47DE, ^x0066, ^x1D61
	.word	^xD0D1, ^xCC5D, ^x611B, ^xB761, ^x752E, ^x5821, ^xFA3D, ^xD95A
	.word	^x499C, ^xAE56, ^xD324, ^x6790, ^xAFC5, ^x0FFC, ^x79AB, ^xB203
	.word	^xFB7F, ^x656D, ^xB517, ^x474C, ^xFD59, ^x9426, ^xA815, ^x787A
	.word	^xCD41, ^x1108, ^x7284, ^x67C0, ^xCD55, ^x4FC1, ^xF97C, ^x97D6
	.word	^x308B, ^x3D56, ^x1314, ^x5674, ^xBF46, ^x7584, ^xE96A, ^x6660
	.word	^x9F05, ^xDE5F, ^xB3C4, ^xC0F5, ^x2193, ^xE128, ^x8096, ^x2738
	.word	^x0F3A, ^x0A6F, ^xDFA8, ^x5E75, ^xC1B6, ^x271F, ^x0BBD, ^x4AC4
	.word	^xF2B7, ^x9A70, ^x939D, ^xEEDB, ^xF1ED, ^x4E04, ^x7327, ^xFCD7
	.word	^x9576, ^x5930, ^xB7F5, ^x8DB9, ^x7D88, ^x090E, ^x5FC7, ^x13AF
	.word	^xE6CF, ^x3EF9, ^x44BD, ^x1929, ^x79B6, ^xFC67, ^x437A, ^x3096
	.word	^x1C3C, ^x8780, ^x8639, ^xC226, ^xE17B, ^x8B0B, ^x951B, ^xF174
	.word	^x6D6B, ^xD64C, ^x0CD5, ^xD6E1, ^x0573, ^x4E81, ^x043E, ^x053F
	.word	^x0A21, ^x899F, ^xF032, ^x47D6, ^x5F6B, ^x9AF2, ^x0D4A, ^x7421
	.word	^x5477, ^x5975, ^x21FA, ^x6E73, ^x8265, ^xD095, ^x5917, ^x752B
	.word	^x5F2D, ^xFB09, ^x6D98, ^xAC70, ^x890F, ^x51E0, ^x1EED, ^x410A
	.word	^xAB3D, ^xB327, ^x4ADD, ^x6813, ^xCD38, ^xCA25, ^x68E2, ^x8C6C
	.word	^x1B29, ^x64B5, ^xB25A, ^x7A83, ^xF151, ^xA715, ^x20A1, ^x00FC
	.word	^x445A, ^x2EB4, ^xEEEB, ^x08B5, ^x79CD, ^x00A3, ^x9D92, ^x4477
	.word	^x365D, ^xEC83, ^x71DE, ^x1C12, ^xFB3A, ^xC9FC, ^x2065, ^x4356
	.word	^x51F0, ^xA4DD, ^x93EF, ^x9400, ^x6A39, ^xCB04, ^x2131, ^x5722
	.word	^xC8CF, ^x2EE9, ^x5AB5, ^x85C2, ^x30BF, ^x08BD, ^xB30B, ^x790F
	.word	^x0375, ^x1770, ^xD835, ^x657B, ^x713E, ^x00DD, ^x376D, ^x0ED3
	.word	^xC64F, ^xD396, ^x3B10, ^x517F, ^xACAD, ^xAC46, ^xA47B, ^xE5AE
	.word	^xD865, ^x5584, ^x7B5E, ^x5477, ^x30CF, ^xAC10, ^xE218, ^xE27F
	.word	^x4439, ^xE521, ^x71B7, ^x2AAD, ^x821A, ^xBC4A, ^x61FA, ^x55F2
	.word	^x853A, ^xFE06, ^x479F, ^xBBE7, ^xE1E7, ^x6C0F, ^x4CCF, ^x356D
	.word	^x2E9A, ^xCE61, ^x6413, ^xB64A, ^xFF98, ^x4BCE, ^x25F3, ^xA610
	.word	^x786E, ^xBFDA, ^xCDF4, ^x221D, ^x35B7, ^x8BFD, ^x1AD0, ^x611B
	.word	^x0EB2, ^x86C8, ^x52E2, ^xD5AA, ^xECF1, ^x3305, ^x5854, ^x2DB0
	.word	^xB48F, ^xA519, ^x1AC3, ^xB381, ^x43AD, ^x9735, ^x6A2C, ^x6340
	.word	^x14BC, ^x4704, ^xD56F, ^x8960, ^xAAF6, ^x0242, ^x0C38, ^x3D2C
	.word	^x6F62, ^xD345, ^xBBD2, ^xE03F, ^x71DE, ^xF60F, ^x3AAE, ^x6ACB
	.word	^x9E6D, ^x6E56, ^xC5CB, ^x6F4B, ^xEDCA, ^xD756, ^xB52B, ^xC05E
	.word	^xA278, ^xDB98, ^xBE80, ^x46E9, ^x7972, ^xDB80, ^xF7C7, ^xE358
	.word	^x5D90, ^x78BA, ^x6544, ^x4A80, ^x1822, ^x97A4, ^xE550, ^x120C
	.word	^x71BD, ^x3A3D, ^xA998, ^x1E4B, ^xAC9C, ^x9A30, ^x7BA9, ^x3C29
	.word	^xEE23, ^x8A9A, ^x7EA2, ^x3B16, ^xAD33, ^x5F51, ^x2A33, ^x78D0
	.word	^xCFE5, ^x9F41, ^xC167, ^x4947, ^xF4BF, ^xBC91, ^xD657, ^x2C1D
	.word	^xEF1D, ^x41B1, ^x414B, ^xD742, ^xD7AE, ^xEFA5, ^x9884, ^xDD4F
	.word	^x5B83, ^x364E, ^xDD2E, ^x309A, ^x5217, ^xDD6E, ^x9F2A, ^xC94B
	.word	^xF62A, ^x4751, ^xE200, ^x15F0, ^xE5C2, ^x4F0A, ^x4A81, ^x8CC3
	.word	^xF011, ^x8565, ^x17AC, ^xE1C0, ^x59EC, ^xB624, ^x14B7, ^x9815
	.word	^x6A62, ^x41F8, ^xF3CF, ^x6328, ^x33AA, ^xCCF3, ^x7B56, ^x67D9
	.word	^xDE7B, ^x5414, ^x2276, ^x6A81, ^x080F, ^xDF2A, ^x7110, ^x3BBB
	.word	^xCC2C, ^xFACD, ^x93A1, ^x14EA, ^x281A, ^x6502, ^x9C5F, ^xA225
	.word	^x4015, ^x4B80, ^xEA07, ^x3085, ^xABEB, ^xFB29, ^xB5CA, ^x6D49
	.word	^x49FA, ^xC1DF, ^xD1E0, ^x1B29, ^x1A30, ^xC0A5, ^x6667, ^xADA8
	.word	^xE2A3, ^xF7B2, ^x92BD, ^x5228, ^xD873, ^x88C7, ^xCD4A, ^x6896
	.word	^xC4D2, ^x5FE4, ^x8ADE, ^x3BD2, ^xDCDE, ^x6005, ^xA9E2, ^x06EA
	.word	^x0FB1, ^xEB1A, ^xBFCE, ^x3DEA, ^xFB98, ^x21F2, ^x7587, ^x5CB2
	.word	^xD2D2, ^x5F61, ^x0C0D, ^xAB9C, ^x2E7C, ^x3F6B, ^x8FF4, ^xB822
	.word	^xDB15, ^x7000, ^xDF47, ^x0093, ^x153C, ^x4C26, ^xC6E1, ^xE8FE
	.word	^xEDBA, ^x0B63, ^x3D2B, ^xED44, ^x5ABE, ^x4C37, ^xAAD4, ^x5CBF
	.word	^x9D08, ^xC123, ^x9568, ^xF46B, ^x94F1, ^x220D, ^xE02E, ^xF33E
	.word	^xF6EE, ^xA151, ^x7296, ^x7B68, ^x878D, ^x66C9, ^x763F, ^x2A74
	.word	^xBEC3, ^xDC56, ^xE912, ^xE9ED, ^xD22F, ^xEA01, ^x6611, ^x0195
	.word	^xDF47, ^x0659, ^xD7EB, ^xEA7D, ^xC3C0, ^x561E, ^x13C8, ^x921E
	.word	^x30A2, ^xC82B, ^x952C, ^x8985, ^xCCE1, ^x29CA, ^xB7A6, ^x6056
	.word	^xB24A, ^x4AC6, ^x0229, ^xFEBF, ^x5D72, ^xBF91, ^x2BE1, ^x5A63
	.word	^xD5FB, ^x9AC2, ^xCF4E, ^xF2CB, ^x7C33, ^x8BC1, ^xFC6E, ^x3F21
	.word	^xC503, ^xF7D9, ^xDEBC, ^xEBB3, ^xD796, ^xDAB5, ^x7B66, ^x37FD
	.word	^xCEA7, ^xB137, ^xEF58, ^xC363, ^x79D0, ^x3A91, ^x6149, ^xD327
	.word	^xA5A7, ^x879E, ^xC96C, ^x9BBF, ^x7B3A, ^xA4BC, ^x73AE, ^x6501
	.word	^xA155, ^xFEBA, ^x9468, ^x4E7E, ^x78BE, ^xF9E1, ^x0ECE, ^x6890
	.word	^xAFF8, ^x5F10, ^xE001, ^x638B, ^x2155, ^x1783, ^xDEC0, ^x2473
	.word	^x27FC, ^x50CD, ^x8013, ^x9BB4, ^x9776, ^x319A, ^xA30F, ^xC880
	.word	^x0FFF, ^x83B4, ^x76CA, ^x44AD, ^x7168, ^xA62C, ^x3321, ^xB094
	.word	^x17FB, ^x80A2, ^x4078, ^xA786, ^x5BEC, ^x984E, ^x7874, ^x6077
	.word	^x46A8, ^x6607, ^x170F, ^x5CE3, ^xC7D1, ^x1A20, ^x7BD6, ^x94F0
	.word	^x1EA6, ^xA4FB, ^xE2D8, ^xF903, ^x0F68, ^x4DAA, ^x23B5, ^x6BB0
	.word	^x5C63, ^x734C, ^xF59F, ^x469E, ^x1E6B, ^x50B2, ^x36C1, ^xA37A
	.word	^x53A6, ^x6623, ^xED77, ^x2B14, ^xEC2F, ^x91A2, ^xF1FF, ^xE5EB
	.word	^x466C, ^xCAE2, ^x3C23, ^x57DC, ^x56D8, ^x5FDF, ^xE7C0, ^xFCBA
	.word	^x5F3D, ^x23A7, ^x8C10, ^xD043, ^x0C89, ^x2DB8, ^x868D, ^x796C
	.word	^x891C, ^xC747, ^xC27E, ^xD632, ^xA626, ^x3673, ^x27D0, ^x9CF8
	.word	^xA1B4, ^x171F, ^xC357, ^x3711, ^xB7F5, ^x8FD3, ^xA29A, ^xC3E5
	.word	^x1CB8, ^x8636, ^x39D2, ^xB75B, ^x2FB2, ^xFA6D, ^x3F9E, ^x922D
	.word	^xCCE6, ^xE304, ^x5EC3, ^x3311, ^x2052, ^xF4E2, ^xDE02, ^xDB6F
	.word	^x3D1D, ^x007E, ^x913B, ^x1F98, ^x3D4E, ^xD5A3, ^x2A4A, ^xA691
	.word	^xEA28, ^xC577, ^xB341, ^x751B, ^x7FDF, ^xA16C, ^xE486, ^x7472
	.word	^xB917, ^xE8A9, ^xE6CC, ^xDA3E, ^xC811, ^xAFD2, ^xE91F, ^x4F54
	.word	^x3FDD, ^x8A81, ^x885A, ^x51FA, ^x09B0, ^xC112, ^x709C, ^xB3AB
	.word	^x957E, ^xA618, ^x3ADD, ^x91B7, ^xE195, ^x03EE, ^xC241, ^x4B09
	.word	^xEA0D, ^xE4DC, ^xDD5A, ^xD0A1, ^x45BF, ^xA4C4, ^x7566, ^x1186
	.word	^x6802, ^x9AF3, ^xD227, ^x36B9, ^xA1F4, ^x6529, ^x91FC, ^xA42F
	.word	^xC396, ^x3121, ^x27E7, ^x73D9, ^x5D78, ^x9E82, ^x3FAB, ^xAEF1
	.word	^x385D, ^xDAA5, ^x4FFF, ^x2F7D, ^x44E2, ^x37BA, ^x5523, ^x1559
	.word	^x483D, ^x485F, ^xBE7A, ^x9032, ^x4643, ^xF97E, ^x49BE, ^xEAEC
	.word	^xD8F7, ^x6603, ^x1F09, ^x247B, ^xC4FC, ^x7DD3, ^x166F, ^x7839
	.word	^xDB42, ^xD407, ^x9B61, ^xADF3, ^x805C, ^x0BBB, ^x7D4A, ^x72C7
	.word	^xBB84, ^x202B, ^x6D1F, ^xD813, ^x4B9F, ^x8B16, ^x3380, ^x6A10
	.word	^x9087, ^x6600, ^xB5CC, ^xADAD, ^x1FA9, ^x08DE, ^xFE44, ^xEA56
	.word	^x2E53, ^x01AE, ^xDD02, ^xE1EC, ^x4B36, ^xE4A6, ^x64B2, ^x82A4
	.word	^x5B23, ^xA77C, ^x91B4, ^x5DF4, ^x0791, ^xAE18, ^xC1A2, ^x3140
	.word	^xEEBC, ^xEE07, ^x978B, ^xD3CA, ^xDEE8, ^x1ED2, ^x71E7, ^x710F
	.word	^xF257, ^xC2EC, ^x5FDC, ^x0E2B, ^xEFC1, ^x9FC4, ^x3B0D, ^xAA41
	.word	^xF698, ^x03D7, ^x0277, ^x95F5, ^x516C, ^x872D, ^x45F0, ^x0DFF
	.word	^x8DCD, ^x3AFA, ^x804F, ^x6EA0, ^x7936, ^xDEB2, ^xB7D7, ^xDA38
	.word	^xEA4F, ^x35F3, ^x1352, ^x9C9F, ^x1F20, ^x6451, ^x374C, ^xCC50
	.word	^x6BDF, ^x57B7, ^x8191, ^xF228, ^x3F00, ^xB828, ^x8D00, ^xFC18
	.word	^xA4C8, ^xB05A, ^x761E, ^xC3DE, ^x825D, ^xA936, ^x07DE, ^x94D9
	.word	^x96E4, ^x9782, ^xE25E, ^xCFC2, ^x82AF, ^x845E, ^xA40E, ^xC6FB
	.word	^xB908, ^x4D27, ^xE618, ^x83F9, ^x2348, ^xBD01, ^xE7CE, ^xB20E
	.word	^xED82, ^xA9B3, ^x03F7, ^xA05B, ^xBEB8, ^xC3B6, ^x387F, ^x91D6
	.org	^x6000
	.word	^x5D3A, ^x53DC, ^x53FE, ^x5D44, ^x5874, ^x57B0, ^x5512, ^x5380
	.word	^x56C0, ^x5428, ^x5334, ^x57F4, ^x5AB8, ^x518C, ^x56F2, ^x591A
	.word	^x5EF0, ^x5EBC, ^x52C0, ^x5B72, ^x5152, ^x59FE, ^x5CEC, ^x5CBC
	.word	^x55A6, ^x58D4, ^x5BD6, ^x5C3C, ^x55EC, ^x5788, ^x5D74, ^x5748
	.word	^x5858, ^x5C98, ^x5AFC, ^x51D4, ^x5876, ^x5B40, ^x5B80, ^x5A8A
	.word	^x5352, ^x53E2, ^x5858, ^x5CD6, ^x5C56, ^x5778, ^x5688, ^x54EE
	.word	^x557C, ^x5CAE, ^x51F4, ^x5E8A, ^x5674, ^x5156, ^x5818, ^x5DE4
	.word	^x5ACA, ^x595C, ^x5C82, ^x515C, ^x5AC8, ^x52B2, ^x5ECE, ^x530A
	.word	^x5606, ^x58CE, ^x5952, ^x5A46, ^x516E, ^x5990, ^x52B0, ^x5E0E
	.word	^x55EC, ^x594A, ^x5BE2, ^x5EAE, ^x5D8A, ^x5856, ^x563E, ^x59BA
	.word	^x5A86, ^x5A76, ^x5D8C, ^x5254, ^x58E4, ^x5C92, ^x5172, ^x5DE2
	.word	^x5ACA, ^x5160, ^x59EE, ^x554E, ^x510E, ^x5C5A, ^x5D7A, ^x577C
	.word	^x5570, ^x5AB2, ^x5E36, ^x53BC, ^x5BE4, ^x5578, ^x5C1C, ^x587C
	.word	^x59C4, ^x5CBC, ^x5BC0, ^x5C22, ^x51CC, ^x54EE, ^x518C, ^x593A
	.word	^x5EB4, ^x5C1C, ^x51D0, ^x53CE, ^x5200, ^x57DC, ^x5DE2, ^x57DE
	.word	^x5A4C, ^x5DF2, ^x52C0, ^x554C, ^x5B86, ^x547C, ^x5DFA, ^x55EC
	.org	^x6800
	.word	^x674B, ^xDF42, ^xAFD5, ^xEE78, ^x213F, ^xA63A, ^x24BC, ^x06AC
	.word	^xE7EB, ^x2834, ^xAF84, ^xE695, ^x8B28, ^x9A21, ^xC6B0, ^x3693
	.word	^x1643, ^x122D, ^xC73C, ^x5FC8, ^xCFFA, ^x8D24, ^x3078, ^x0A0D
	.word	^x904F, ^x5690, ^xEB64, ^xD350, ^xE187, ^x95D8, ^xEB89, ^xCB46
	.word	^xBE3E, ^x2C22, ^xC51F, ^x4375, ^x835B, ^x6DD9, ^x991B, ^x2C90
	.word	^xCF82, ^xD455, ^xD0B4, ^xE211, ^x2F66, ^x8144, ^xC78C, ^x0A51
	.word	^x0357, ^xD721, ^x48C6, ^xDC16, ^xDB55, ^xD995, ^x2D98, ^x225A
	.word	^x1510, ^xFDCA, ^xC00C, ^xEF4D, ^x8ED9, ^x69AA, ^x840C, ^x2DD8
	.word	^xF844, ^xF188, ^x70A4, ^x02FB, ^x85F8, ^xCE1D, ^xC8DF, ^x2E1D
	.word	^x2681, ^xDD87, ^xF1FB, ^xBFE9, ^x5DD1, ^x227F, ^x9A86, ^x9BBE
	.word	^xC420, ^xD867, ^xBCFF, ^x0327, ^xCE1A, ^xB20D, ^x8352, ^x037F
	.word	^x7245, ^xE7BB, ^x2B0D, ^xE754, ^x4FAB, ^x0146, ^x65A3, ^x2549
	.word	^xD7D9, ^xB903, ^x5EF2, ^x549A, ^x6710, ^x4834, ^xF423, ^xA628
	.word	^x275D, ^xB483, ^x1C26, ^xD3B2, ^x4691, ^x9E4D, ^x0071, ^x4FAF
	.word	^x72C8, ^x1423, ^x58F2, ^xFB4F, ^x6155, ^xADA4, ^x8BB8, ^xCD49
	.word	^xD8D2, ^xB5A6, ^xC339, ^xC126, ^xAAF7, ^xAF81, ^x90D7, ^xAD78
	.word	^x0234, ^xF6E9, ^x7FB5, ^x46FA, ^x16FB, ^xA8F1, ^x86B4, ^x6344
	.word	^xF79E, ^x0DBB, ^xC8AE, ^x9F40, ^xD7A3, ^x6C3A, ^x141A, ^x8DBC
	.word	^x44D1, ^x13B7, ^xDCFC, ^x241C, ^x1FA2, ^x43C8, ^xBB44, ^x4595
	.word	^x7902, ^x8931, ^x8662, ^x2B1B, ^x4D1B, ^x25BE, ^x8582, ^x3458
	.word	^xB1E8, ^xD4B3, ^xDE77, ^x526E, ^xF4A2, ^x08D0, ^xB77F, ^xCFE7
	.word	^x4BBC, ^x8BF2, ^xC8DA, ^x1E51, ^x7E72, ^xD976, ^x9395, ^x8079
	.word	^x8F04, ^xDCB2, ^x174E, ^x074A, ^x2916, ^x8F3B, ^xB50D, ^x7EC1
	.word	^x8FFE, ^x680F, ^xACE8, ^x2384, ^x4AC8, ^x0657, ^x957C, ^x89E6
	.word	^x8571, ^x61FF, ^x75C9, ^x9CC7, ^x5345, ^x500A, ^x96A2, ^x0DB1
	.word	^x0663, ^x76C2, ^x5D4A, ^x304C, ^x6D6A, ^x7548, ^xDCFA, ^x1D57
	.word	^xDB30, ^xE16F, ^x6FB7, ^x517E, ^x7FE9, ^x85F1, ^x9CB4, ^xF5C0
	.word	^x09B7, ^x2BA0, ^x2C53, ^x7B8D, ^x43C9, ^x4E82, ^x6999, ^x3F95
	.word	^x06A9, ^x90F3, ^xDF84, ^x312C, ^xA50D, ^x9C30, ^x2473, ^x808D
	.word	^x567A, ^xEF42, ^xFCC1, ^x7AE3, ^x1833, ^xB8BD, ^xEC1D, ^x19F9
	.word	^x719B, ^x2B8A, ^x0238, ^xFA53, ^xF7A4, ^x8271, ^xD66F, ^x6421
	.word	^x4F1C, ^xD10C, ^xD4EA, ^x64F1, ^x4D17, ^xF06A, ^x3BFD, ^x6923
	.word	^x8879, ^x2D71, ^x4A0A, ^x3A6E, ^x611C, ^xFF4B, ^x7A99, ^x1A31
	.word	^x5635, ^xAE0E, ^x46D8, ^xE247, ^xEE5A, ^x3AAA, ^x18DC, ^x8630
	.word	^x5302, ^xD849, ^x13EE, ^x5994, ^xD2F8, ^x6380, ^x15E7, ^xF3A1
	.word	^x79AA, ^x8D92, ^x466C, ^xFEE9, ^xB425, ^xA071, ^x14D6, ^xB722
	.word	^x0759, ^xEB02, ^x0373, ^xD698, ^xFDB9, ^x1661, ^xDD65, ^x45EC
	.word	^x658C, ^xF5A2, ^x386B, ^x0836, ^xC630, ^x8E9E, ^x2B3A, ^x99B0
	.word	^xED26, ^x238D, ^x0CEA, ^x39F3, ^x5EB7, ^xFA0D, ^x2DE7, ^xD471
	.word	^xD66B, ^x35DC, ^x0DF8, ^xCC5E, ^xECFD, ^x5351, ^x0644, ^x8089
	.word	^x1A7D, ^x2A49, ^x4031, ^x5920, ^x1DC7, ^x08CE, ^xA36F, ^x31A3
	.word	^xA440, ^xE2BC, ^x35DB, ^xD1B2, ^xA6F5, ^x3265, ^x3C49, ^x7DB8
	.word	^x7830, ^x47B6, ^x95A9, ^x1EE4, ^x8D57, ^x1219, ^xB02D, ^x5D44
	.word	^xD712, ^xC245, ^xA712, ^xF1DF, ^xABD6, ^xCE0A, ^x2B9C, ^x29B4
	.word	^x2791, ^xE8A8, ^x8D4C, ^x6E06, ^x2EC5, ^x3824, ^xF62C, ^xCC21
	.word	^x8C99, ^x2B6B, ^xBD87, ^x8EF9, ^xC7E5, ^xF9FC, ^x1D67, ^xEBC9
	.word	^x2AF7, ^xD331, ^xFE8B, ^x7B6E, ^x7F77, ^xF445, ^x8FE6, ^x87A4
	.word	^xAAA9, ^xD10F, ^x5423, ^x5CB3, ^x63C0, ^xD529, ^xD13E, ^x8271
	.word	^x0E63, ^xC02E, ^x24A6, ^xB0C8, ^x6875, ^xE3EE, ^x4761, ^x33F7
	.word	^xFD87, ^x3AED, ^xF4A3, ^xD1DD, ^xFD8D, ^x1F23, ^x44B1, ^x337F
	.word	^xCBF8, ^x9601, ^xEDBD, ^x8541, ^xBA89, ^x3CD1, ^x206E, ^x823A
	.word	^x4CF7, ^xCF3A, ^xF56E, ^x9847, ^x1DCE, ^x92EA, ^xC5E7, ^x8FB7
	.word	^x0AB3, ^xF4AA, ^xE1D9, ^xCECF, ^x7C88, ^x2FA9, ^x2B57, ^x123B
	.word	^x80F9, ^x3756, ^xEECD, ^x769D, ^x4E8E, ^x3CA6, ^x9ED5, ^x7801
	.word	^x3C69, ^x353B, ^xAB3B, ^xC549, ^xFCB0, ^x257E, ^x9CF1, ^x7688
	.word	^x92B9, ^x7928, ^x28FC, ^x1039, ^x1680, ^xD937, ^x07DF, ^x3600
	.word	^x23C3, ^x479A, ^x4A60, ^x4BE7, ^xA050, ^x71DC, ^x38C5, ^xC98C
	.word	^x5425, ^x4684, ^x6961, ^x6AA1, ^x2094, ^x3E36, ^x5775, ^xC2A4
	.word	^x03F2, ^xAE95, ^xB8CE, ^x9F4D, ^x9E25, ^x9E7A, ^xBDED, ^x77D2
	.word	^x53DA, ^x8220, ^x70D8, ^xB450, ^x302B, ^x60D9, ^x1243, ^x2CE0
	.word	^xF7F3, ^x2580, ^x769D, ^xBD1D, ^x2E40, ^xE65E, ^x7609, ^x404A
	.word	^xC636, ^xBC4D, ^x5F03, ^x0AB6, ^xB8CE, ^x9D72, ^x3A51, ^xCDF6
	.word	^x5B68, ^xD6C5, ^xF4D2, ^xC2B2, ^x8F40, ^x4F17, ^x923D, ^xBA72
	.word	^xBA9F, ^x273F, ^x2011, ^x82A0, ^x7CB9, ^x0DA9, ^xECAC, ^x3756
	.word	^x864D, ^x5AF6, ^xC813, ^xE990, ^xDFA4, ^x111F, ^x0F60, ^xECF7
	.word	^x2024, ^x0979, ^xADAD, ^x3202, ^x5C0D, ^x6F52, ^xEBB7, ^x6987
	.word	^x4A33, ^x1DC7, ^x1654, ^x925F, ^xED21, ^x9B9A, ^xB842, ^xB8EE
	.word	^xB9AD, ^x842B, ^x1F93, ^x8AE9, ^x6E2C, ^x513E, ^x5686, ^x2D79
	.word	^xCF8D, ^xAB28, ^xB372, ^xCC10, ^x43B9, ^x6837, ^xEE4F, ^xA609
	.word	^xF7BE, ^xF0DC, ^xC243, ^xEC8B, ^x41BF, ^x799A, ^xCD7B, ^xF91E
	.word	^x0BC5, ^x6B43, ^xECCA, ^xA726, ^x51CF, ^x5548, ^x443C, ^xB283
	.word	^x140C, ^x1CD3, ^xF1FA, ^x4DFD, ^xB65C, ^x6BC0, ^x81BF, ^x6836
	.word	^x479B, ^xC262, ^x703A, ^x3191, ^xB7A1, ^xDBF4, ^xC087, ^x4FB0
	.word	^xC1D7, ^x9A67, ^x8F7A, ^xFBAD, ^x9892, ^x5A1F, ^x4638, ^x7202
	.word	^xE30C, ^x46EE, ^xE5D2, ^x075A, ^xCE37, ^x92DB, ^x074A, ^x049C
	.word	^x3705, ^x0B7E, ^x17A7, ^xA78F, ^x177A, ^x86D4, ^x5D98, ^x3311
	.word	^xB83B, ^xF2B1, ^xDC9F, ^xD572, ^xD3F1, ^x6AB4, ^xFD79, ^xA4E3
	.word	^x768A, ^xA8C9, ^xE8A0, ^x81AF, ^x1DF0, ^x15B9, ^x5981, ^xBF93
	.word	^x6A15, ^x7FDB, ^x67F3, ^xFDC4, ^x2A71, ^x3787, ^xDDCC, ^xFCC8
	.word	^xC64A, ^xA8DD, ^x1A2C, ^x5372, ^x58E9, ^xB29F, ^xF1AC, ^xBFF1
	.word	^x4947, ^xF344, ^x749E, ^xF1C9, ^xDE3C, ^xED8E, ^xD55C, ^x44D5
	.word	^x8897, ^x25CF, ^xF277, ^x6360, ^xB768, ^xDD5E, ^xEF3B, ^x975F
	.word	^x1EEB, ^x7A61, ^x0FE2, ^x9767, ^xF1BF, ^xE8FE, ^xD997, ^x8C3A
	.word	^x3E7B, ^xDA52, ^xD05D, ^x8335, ^x05CB, ^xAB47, ^x0863, ^xF2C4
	.word	^x713A, ^x2756, ^xF55F, ^xBAFC, ^xCA75, ^x19D2, ^xEDE7, ^xC130
	.word	^x3092, ^xE80E, ^x55B6, ^xEC4F, ^x809C, ^x0552, ^x5528, ^x1258
	.word	^x98D3, ^x53C6, ^x07EC, ^x5886, ^x843B, ^xEB85, ^xA9CD, ^x6DE6
	.word	^x5A8B, ^xA977, ^x79DD, ^x4CDC, ^xF699, ^x8131, ^xD4BC, ^xC11C
	.word	^x0ED2, ^x1644, ^x4C1F, ^x75C7, ^xD1DD, ^x5253, ^x2095, ^x6669
	.word	^x9F16, ^x483C, ^xC6DF, ^x1748, ^x4D56, ^x046D, ^xD8BA, ^x225A
	.word	^x7201, ^x43B2, ^x4D7C, ^x66C4, ^x57CB, ^x0B23, ^xC28F, ^x3DFA
	.word	^x0163, ^xF29A, ^xE9FD, ^xDA5A, ^x46A0, ^xE742, ^x6F72, ^xA01F
	.word	^xA08A, ^xDA94, ^xEB4C, ^xB265, ^xE05F, ^xED58, ^x0FDC, ^x2023
	.word	^x507E, ^xFC0A, ^x5DC7, ^xDE61, ^x723B, ^xA448, ^xE24C, ^x1BE8
	.word	^xFC9C, ^x67B9, ^x615A, ^xF683, ^x8272, ^x3363, ^x6ECA, ^xB260
	.word	^xD4CA, ^xDD72, ^x8830, ^x8AA2, ^x38DD, ^xAB49, ^x6492, ^x0579
	.word	^xD376, ^x22E0, ^xBF9D, ^x49A7, ^xDCA9, ^x2BD3, ^xE0DD, ^x7FC1
	.word	^x497A, ^xC77E, ^x450A, ^xFF5C, ^xE5D5, ^x97C9, ^x619C, ^xE2A3
	.word	^x78AD, ^xC57A, ^xE531, ^xB04B, ^x5564, ^x0ABB, ^x7BCD, ^xDF88
	.word	^x798D, ^xC175, ^x6557, ^xD653, ^x13F2, ^xCA72, ^x69E1, ^xF994
	.word	^x2D76, ^xC37C, ^x3703, ^xB789, ^xB4BD, ^xB990, ^x392A, ^x2A98
	.word	^xFCDD, ^x8E97, ^xBFDE, ^x4FC4, ^xD050, ^x018B, ^x4F27, ^x1BA5
	.word	^x1B78, ^xDA4E, ^x905F, ^x0F7F, ^x448A, ^x4554, ^x6BCB, ^x922C
	.word	^xA193, ^xB611, ^x00B1, ^xA0D5, ^x885A, ^x4B3A, ^xDC3E, ^xCA97
	.word	^xD6AE, ^x86A0, ^xA9EE, ^x9E4C, ^x9291, ^x7E54, ^xBAC0, ^x48A6
	.word	^x208F, ^xA98E, ^x56EF, ^xC8EC, ^x966E, ^xC4C9, ^x0561, ^x2CF1
	.word	^xA56A, ^xE801, ^x35D9, ^x5D31, ^x5855, ^x5259, ^x423B, ^x262A
	.word	^x0FFD, ^x0D34, ^x1BE5, ^xB1A8, ^x7184, ^x8BCD, ^x38DB, ^x9C23
	.word	^xA692, ^xD1CC, ^x49A7, ^x9A76, ^x7119, ^x3FED, ^x9E5B, ^x0B59
	.word	^x2065, ^xACA4, ^x9036, ^xC5C3, ^xAB98, ^x3328, ^xB72C, ^xF128
	.word	^x05E3, ^x6887, ^xBB1F, ^x7ECB, ^xC981, ^xD80F, ^x196A, ^x82B7
	.word	^xAB8B, ^xC15F, ^x16B5, ^xFA4A, ^xE9E6, ^x44C3, ^xEA9A, ^x0A2F
	.word	^xA410, ^xFB35, ^x3C41, ^xBA72, ^xC2CF, ^x69A4, ^x857E, ^xEB6A
	.word	^x1940, ^xD216, ^xC013, ^xB1AF, ^x66FD, ^x8934, ^xA8E7, ^x80EE
	.word	^x1B95, ^xAF22, ^x96DE, ^xB82B, ^xF518, ^x1FEE, ^xAAC2, ^xF631
	.word	^x5E3D, ^xC4F4, ^x3AC6, ^x5A82, ^x50B7, ^x2020, ^xE4B1, ^x5F72
	.word	^x476A, ^x71C5, ^x6499, ^xC121, ^xDE0D, ^x8E02, ^x9EF7, ^xC8FE
	.word	^xD143, ^x79A6, ^xFCF2, ^x667F, ^xE3AC, ^x6859, ^xF440, ^x59A5
	.word	^x12C0, ^x4561, ^x48E2, ^x82B4, ^x3F43, ^x0D34, ^x0821, ^x55E6
	.word	^x1105, ^x8A7A, ^xC22D, ^x786A, ^xCEA3, ^x5E82, ^xFB64, ^x8748
	.word	^x93E6, ^xDEF5, ^x225C, ^xB2F0, ^x2DAB, ^x8E0F, ^xFE82, ^x1F12
	.word	^xC3C6, ^x1ED2, ^x2C35, ^x76BE, ^xCFF3, ^x29DB, ^xB888, ^xC2B1
	.word	^x1967, ^xCA48, ^x982D, ^x88F0, ^xA993, ^x4D32, ^x3F7A, ^x622B
	.word	^x4F96, ^x1DE1, ^xAFEC, ^x75F0, ^x810E, ^x82E5, ^xAD09, ^xC55F
	.word	^xD4E5, ^x2079, ^xC741, ^x8005, ^xE489, ^x9641, ^xE425, ^x6BA2
	.word	^x2565, ^x619D, ^xD75D, ^x9F43, ^xF6BA, ^x6891, ^x36B7, ^xEC73
	.word	^x1F27, ^xAE98, ^xD1F8, ^xFAFD, ^xD967, ^xB94E, ^xB510, ^xD1FD
	.word	^x3315, ^x37A4, ^x3DF9, ^xE81E, ^xB895, ^x8580, ^xD64E, ^x9D59
	.word	^xA15F, ^xB381, ^xE45B, ^xB190, ^xF076, ^x6FF9, ^x26A1, ^x978F
	.word	^xC2F7, ^x75A8, ^x5E5A, ^x369A, ^x1DAF, ^x31E7, ^xCB96, ^xD1B9
	.word	^x125D, ^x1DC8, ^xBBD6, ^x5118, ^x4000, ^x307E, ^xE683, ^x043F
	.word	^xA829, ^xF23A, ^xA422, ^x9101, ^x71BF, ^x925C, ^x21F2, ^x56E2
	.word	^x5F4F, ^x9E9B, ^x5B0A, ^x3DEA, ^xFB51, ^xA984, ^xAABB, ^x6ECB
	.word	^x56BD, ^x5BA0, ^xF62F, ^xF697, ^xEF63, ^x137A, ^x150A, ^x8423
	.word	^x4EDC, ^x9279, ^x5003, ^x1CA9, ^xFA70, ^xFBA0, ^x35E0, ^x2A33
	.word	^x24D4, ^xD545, ^x2FD5, ^x1941, ^xE92D, ^x3D1E, ^x04AF, ^xD211
	.word	^x9D1B, ^x44BE, ^x2ED9, ^x97C8, ^xD24F, ^x23C9, ^x92E5, ^x6CA2
	.word	^xE709, ^x7DFD, ^xD260, ^x7DD5, ^xCBBB, ^x37DF, ^xDD98, ^x359A
	.word	^x178A, ^x25CB, ^x827F, ^xE1B2, ^x1B36, ^x2258, ^x6D5D, ^xBC9B
	.word	^x1A92, ^x4760, ^x0985, ^x2567, ^xA8DD, ^x8D1C, ^xDD5C, ^xDB49
	.word	^xF9D0, ^x6E1E, ^xB3EA, ^x6774, ^x9E86, ^x1238, ^xA393, ^x6EA7
	.word	^x04DF, ^x8D93, ^x7EAE, ^x9DB2, ^xA1A6, ^xB5A9, ^xDD4E, ^x5C23
	.word	^x4BA2, ^xB703, ^x7EF5, ^xCD56, ^x472F, ^x23C0, ^x8769, ^x8DCB
	.word	^x1D81, ^xD0B2, ^x35DB, ^xACA3, ^x63FB, ^xD053, ^x378A, ^xD541
	.word	^x1EB0, ^x2083, ^xB850, ^x87E3, ^x11A1, ^x2170, ^xA346, ^xEE53
	.word	^xDCAB, ^xBC81, ^xE01E, ^xD949, ^x3796, ^x5B0D, ^x2FFA, ^xF224
	.word	^xD7A7, ^x14C9, ^x60CE, ^x456B, ^x0DAB, ^x639F, ^xCAAC, ^xB5C8
	.word	^x412E, ^xDC32, ^xA5D6, ^x3B37, ^xE638, ^x2211, ^x6A08, ^x85B0
	.word	^x4EC5, ^x351E, ^xAC98, ^x1C7E, ^x0193, ^x428D, ^xA711, ^x1A3C
	.word	^xBA80, ^x5592, ^xC59F, ^x29DA, ^xC5C0, ^x310A, ^x6944, ^x1A06
	.word	^xFDC1, ^x9E5A, ^x45BF, ^x03C3, ^x0A11, ^x8835, ^x5EFD, ^x03CA
	.word	^x1BB7, ^x2FD5, ^x78CA, ^xB330, ^x75F5, ^x5468, ^x24F8, ^x9365
	.word	^x1486, ^x6CC2, ^x8B5F, ^x2387, ^xACE3, ^x3CA5, ^x3D0B, ^x1077
	.word	^x2C7A, ^x5FE2, ^x7C71, ^x9C3A, ^x2EC7, ^xD1F5, ^x1074, ^xBCE8
	.word	^x3FE0, ^x4229, ^x66B3, ^x28AE, ^xBDF3, ^x18B4, ^xC0D4, ^xB5F7
	.word	^x753E, ^xCA4D, ^x932C, ^x528C, ^x4FAC, ^x3672, ^xBCA5, ^x6887
	.word	^x7EE1, ^x8156, ^x59B4, ^x35AF, ^x8B95, ^xB61F, ^x77BF, ^xA59E
	.word	^x5514, ^xEB10, ^x2C4C, ^x0933, ^xCE9B, ^x1BB5, ^x6E7B, ^xE4BD
	.word	^x27B0, ^xE98E, ^x343C, ^x4B76, ^x43C2, ^xE238, ^x642B, ^x741F
	.word	^xD3D8, ^x8AC6, ^x9A74, ^xDEC0, ^xB214, ^x2D00, ^x8E83, ^xA84D
	.word	^x04BF, ^x9019, ^x889A, ^x141C, ^x64D4, ^x46C2, ^x03C4, ^xB0DC
	.word	^x1BC1, ^x495C, ^xEF01, ^x04F8, ^x9069, ^x2B5D, ^x6341, ^x19AC
	.word	^x3D6B, ^xCA37, ^x1885, ^x420C, ^xB46F, ^x2BBE, ^x4A82, ^x8891
	.word	^x3E5E, ^x54B2, ^x9747, ^x3385, ^x11A6, ^xAB12, ^xBE52, ^x2F9D
	.word	^xD680, ^xB63A, ^x1E97, ^x6AFD, ^x7A4A, ^x0C46, ^x2904, ^xD451
	.word	^x945A, ^x09FA, ^x587B, ^x5F47, ^x362E, ^xE692, ^x1D20, ^xD698
	.word	^x19C0, ^xADB1, ^x6A1D, ^x55B3, ^x9AD3, ^x808B, ^xDB30, ^xC7CB
	.word	^x26FC, ^x403A, ^x8996, ^x1331, ^x6E1C, ^x0DD2, ^x6111, ^xB250
	.word	^x87B1, ^xA606, ^x58FF, ^xF5E8, ^x49A2, ^xA174, ^xCC90, ^xA556
	.word	^x21FB, ^x309C, ^x30BF, ^xA6D4, ^xC237, ^x22FE, ^x6708, ^xBFE1
	.word	^x3693, ^x39CC, ^x81F0, ^xCA84, ^x016F, ^xD78F, ^xAC90, ^x54BE
	.word	^xD359, ^x1D46, ^x96D0, ^xEC7A, ^x6E6A, ^xEC86, ^x7B1A, ^xA000
	.word	^xAFF8, ^x9B63, ^xAE01, ^xC4DF, ^xD5D5, ^x8CF8, ^x1DF7, ^xF521
	.word	^x2273, ^x23C9, ^x1325, ^x1709, ^xC674, ^xC6B2, ^x3E85, ^x07C5
	.word	^x5F75, ^x7905, ^xCBFE, ^x7D3E, ^xA5AA, ^xD620, ^xA1CA, ^x9C27
	.word	^x041B, ^xE560, ^x1F04, ^xD1C4, ^x1413, ^x8201, ^x4D08, ^xF8E6
	.word	^x676D, ^xC98C, ^x68A0, ^x4313, ^x9DD5, ^x55D2, ^x0AC1, ^x9012
	.word	^x2E4D, ^x74E3, ^x09E8, ^x52B6, ^xB992, ^x1A73, ^x0ACF, ^x0470
	.word	^x6312, ^x9BA2, ^x5123, ^xA6C5, ^x7777, ^x70AE, ^xCDDF, ^xA971
	.word	^xE66B, ^x8E08, ^xF434, ^xDD71, ^x9565, ^x0994, ^x99A7, ^x3F60
	.word	^xD188, ^xC852, ^x455C, ^x69E3, ^xAC20, ^x6914, ^x21D4, ^x75D3
	.word	^x8847, ^xFB7F, ^x7B3F, ^x5F6E, ^x98AA, ^xEDDF, ^x5AF0, ^x3F57
	.word	^x1D5C, ^x235A, ^x9A11, ^x44FD, ^x77F0, ^x6B56, ^x6934, ^x9CC7
	.word	^xE40F, ^x83AB, ^x4857, ^x1DCD, ^xBA0C, ^xD6FC, ^x393E, ^xCF57
	.word	^x3C79, ^x024D, ^x029F, ^x93FA, ^xD8B4, ^xC9DC, ^x95CA, ^xB11E
	.word	^x14C4, ^x849A, ^x00C6, ^x97F4, ^x196F, ^x1501, ^x50DC, ^x5291
	.word	^x2648, ^x1C90, ^x3191, ^x3FC3, ^x4AEB, ^xF5FB, ^xC1C1, ^xA35A
	.word	^x4B82, ^x3F3B, ^x9658, ^xEDFB, ^x4B79, ^x89F3, ^xD86C, ^xE7BC
	.word	^x8267, ^xA15C, ^x5971, ^xD92E, ^x911D, ^x6EF5, ^x4722, ^xA8AD
	.word	^x249D, ^xAB7D, ^xD60E, ^x4549, ^xED35, ^xF600, ^x0935, ^x1B2F
	.word	^xD051, ^xF6B8, ^x706B, ^xE3F9, ^x5CE4, ^xB108, ^x8042, ^xF5F2
	.word	^x785F, ^x6186, ^x950C, ^x1497, ^x4F2D, ^x6C97, ^x8794, ^xD3C8
	.word	^x4D1F, ^xED72, ^x16A8, ^x1CBA, ^x7555, ^x4436, ^xB770, ^x26FC
	.word	^x722B, ^x01B7, ^x99FE, ^x24A3, ^x6DBD, ^x5C4A, ^x05D2, ^xCA20
	.word	^x4277, ^xAE9A, ^x8087, ^x882A, ^x833F, ^xD608, ^x403F, ^xE50F
	.word	^x64C0, ^x8B5C, ^xD5C1, ^x2988, ^x182B, ^x5F49, ^xA85B, ^x95F1
	.word	^x8412, ^x26E2, ^x5335, ^xD3E4, ^xAD73, ^x789A, ^x2CA8, ^x8706
	.word	^x76EA, ^x2428, ^x2517, ^xD398, ^x1E0D, ^xF297, ^x7987, ^x80CA
	.word	^xB161, ^xA86E, ^x1E33, ^xFD54, ^xA617, ^x6701, ^xC235, ^xB818
	.word	^x79BF, ^x50D0, ^xBCBC, ^xF343, ^x6F45, ^x931A, ^xE3F9, ^x1587
	.word	^x0C4D, ^xD525, ^x54A1, ^xB03B, ^xD73B, ^x2712, ^xE73E, ^xC4CE
	.word	^x107C, ^x4EC1, ^x2D6B, ^xA5E8, ^x41F9, ^x5E80, ^xC81B, ^x4BC1
	.word	^x8CFE, ^x0D33, ^x59C3, ^x429C, ^xA812, ^x95C5, ^xC85B, ^x3B83
	.word	^x8C8E, ^x68A3, ^xDB7E, ^x98DA, ^xF24A, ^x31BF, ^x99EA, ^x3FFC
	.word	^x13D2, ^x4900, ^xA106, ^xD43B, ^xB0A3, ^xD901, ^x7263, ^x242C
	.word	^x25BF, ^xF2EC, ^xB7A4, ^x3AC8, ^x8660, ^x84BE, ^xF73B, ^x2B08
	.word	^x6AA5, ^x8E62, ^x7120, ^x6DDA, ^xD776, ^x07DD, ^xC0EA, ^xAF35
	.word	^x107B, ^x1BED, ^x5BD2, ^x9E25, ^x5FBB, ^x3DEA, ^x5DA3, ^x3BFD
	.word	^x65BF, ^x3CD9, ^x8F4D, ^x26FB, ^xC7C5, ^xDD18, ^xF762, ^xD761
	.word	^x8C29, ^xC77A, ^x406D, ^x5030, ^x2CE7, ^xDE1D, ^x10C2, ^xF7EA
	.word	^x05A8, ^x6D17, ^x7862, ^xE9B9, ^x4609, ^x5CD8, ^x5149, ^xBE8F
	.word	^x77C3, ^x9005, ^xB480, ^xD7C2, ^xA290, ^xC9BE, ^xD854, ^x862C
	.word	^x77B5, ^xDA24, ^x314E, ^xD50A, ^xD9CA, ^x34C9, ^xC17A, ^x0E10
	.word	^xD335, ^xF20F, ^xB51F, ^x40EB, ^x31F1, ^x820F, ^x8D55, ^x22B3
	.word	^x27EA, ^x9D44, ^xAF41, ^x85A7, ^x456B, ^x7A80, ^x677C, ^x798D
	.word	^xF93D, ^xEB5E, ^x4AB3, ^xF278, ^x8E81, ^xF3C2, ^xCC85, ^x0F70
	.word	^xEC99, ^x87F6, ^x793F, ^x4F05, ^x6C8D, ^x8E65, ^x5A5E, ^x7DF6
	.word	^x18F8, ^x5CF3, ^xA81F, ^xA41D, ^x60AB, ^x47D1, ^xDB0C, ^x1D45
	.word	^x1421, ^x782A, ^x4C31, ^x8F02, ^xF85F, ^x2467, ^x53B1, ^xF800
	.word	^x34A8, ^x69C1, ^xDA69, ^x7A44, ^x8BBB, ^x78DD, ^x0F1F, ^x7964
	.word	^xE3E7, ^xE10E, ^x4099, ^xA6F9, ^xBA9E, ^x2F86, ^xF4FC, ^x0FE2
	.word	^x5BFE, ^xB323, ^xAE18, ^x689B, ^x3B0B, ^x45E7, ^xBB6A, ^x3F01
	.word	^x3AF3, ^x4DE6, ^x1BDF, ^x9F67, ^x21A1, ^x4E57, ^xCE53, ^x3690
	.word	^x3167, ^xCB12, ^x0CD1, ^x0A07, ^xE8DD, ^x0D79, ^xC276, ^x4279
	.word	^x5661, ^x7573, ^xD9B9, ^xC9A6, ^x3E8D, ^xEE6C, ^xA430, ^x663A
	.word	^x7C51, ^x8D1A, ^xD486, ^xCA03, ^xDBC8, ^x78DC, ^xB1D0, ^xDEF3
	.word	^x7BF4, ^xEA1C, ^x0CDB, ^xF176, ^x8279, ^x5A6D, ^x4D85, ^x782E
	.word	^x4E1A, ^x1F7D, ^x8D40, ^x7669, ^x7CC1, ^xCC35, ^xE7F7, ^x840E
	.word	^x1DF4, ^x7363, ^x32C8, ^xE299, ^x42DC, ^x32A8, ^x851E, ^x4267
	.word	^x4A97, ^x35F8, ^x67F0, ^x8E0B, ^xF73A, ^xB5D5, ^x06E8, ^x2297
	.word	^xACD6, ^xFAB7, ^x88F8, ^x281A, ^x424D, ^x1B73, ^x1CFA, ^x9D9D
	.word	^xC564, ^x3438, ^x9CE5, ^x4B2D, ^xDEF3, ^x6506, ^x9908, ^xFE8B
	.word	^xD9E6, ^x5AEE, ^x7E05, ^x1CDC, ^x62E7, ^x4A62, ^xC00B, ^xA15A
	.word	^x77E7, ^x2B24, ^x6864, ^xFEB5, ^xA6B9, ^x2BF8, ^xB1F5, ^xBA86
	.word	^x7675, ^xCD66, ^xB846, ^x94FC, ^xD056, ^x2610, ^xD58F, ^xE1BF
	.word	^x465E, ^x4CA3, ^xD170, ^xDB9F, ^x3E67, ^xC5D6, ^xAE23, ^x3F92
	.word	^x7561, ^x57D7, ^xB91B, ^xB70D, ^x4551, ^x5AE0, ^xA434, ^x8647
	.word	^x2ABF, ^xEAA9, ^xB879, ^x3937, ^x37FE, ^x47B4, ^x8C7A, ^x5C13
	.word	^x57A6, ^x6D98, ^x0BC7, ^x035F, ^xAE51, ^xF86F, ^x0E4A, ^x4EE7
	.word	^x289B, ^xA783, ^x6E3E, ^x7E45, ^x12A1, ^x0630, ^xEEE1, ^xEA4A
	.word	^x2D21, ^x85EA, ^x7D66, ^x793B, ^x3D21, ^x9C69, ^xA8F4, ^x11AB
	.word	^xE32F, ^x72F0, ^x22B5, ^x3ABC, ^xA9C5, ^x8069, ^x43CE, ^xE5FE
	.word	^x420C, ^x6882, ^x003D, ^xBC5E, ^x50A6, ^x0E84, ^x12F8, ^x106D
	.word	^x7499, ^x0A43, ^xF52C, ^xE492, ^x159D, ^x93E8, ^x41AE, ^xEA4A
	.word	^x5248, ^x55D8, ^x18D5, ^xF5B7, ^x0617, ^xCF07, ^xB873, ^x11AB
	.word	^xE161, ^x40BA, ^x4F18, ^x6E5B, ^x9CFB, ^xBC23, ^xBD38, ^xE263
	.word	^x689C, ^xDCC7, ^xD8B7, ^xA34D, ^x5CB1, ^x8839, ^xC9DA, ^x8847
	.word	^x85AE, ^x6CBD, ^x1E2A, ^x8196, ^xFE45, ^xC8F3, ^xA2B1, ^x40B5
	.word	^x24F6, ^xB2D3, ^xB996, ^x03A7, ^xEE48, ^x286D, ^xF0E4, ^x708C
	.word	^x7EAD, ^x0659, ^xC382, ^x5AA3, ^x4161, ^x4836, ^xF675, ^x19EA
	.word	^x305E, ^x47AF, ^x5BD2, ^x6724, ^xF182, ^x11E1, ^x5198, ^x885D
	.word	^xCACC, ^x8222, ^x4154, ^x5EB4, ^xCFCE, ^xC957, ^x9123, ^x3306
	.word	^x98EA, ^x7E31, ^x077C, ^xA8B6, ^xD170, ^x0482, ^x2D47, ^x6CF7
	.word	^x6607, ^x9FC3, ^x085A, ^xA5B2, ^x6EEF, ^x8D3A, ^xD8B9, ^xEF9F
	.word	^x56CD, ^x3F66, ^x0FC6, ^xD40C, ^xB90B, ^xF367, ^x4F17, ^x22DC
	.word	^xB2B5, ^x8831, ^x268A, ^xE085, ^x9B3F, ^x8B57, ^x2928, ^xD842
; the handlers, after the log; mkboard.py (software/mmutest.bin) appends
; its code and table after them, out of the way of the test
	.org	^x1F000
	.align	4
cmexc:	movl	(sp)+, r10		; the code
	movl	r10, (r11)+
	movl	(sp), (r11)+		; PC
	movl	4(sp), (r11)+		; PSL
	movl	r0, (r11)+
	movl	r1, (r11)+
	movl	r2, (r11)+
	movl	r3, (r11)+
	movl	r4, (r11)+
	movl	r5, (r11)+
	movl	r6, (r11)+
	cmpl	r10, #1			; BPT: on
	bneq	cmx
	addl2	#2, (sp)
	rei
cmx:	movzwl	@(sp), r9
	cmpl	r9, #^o104377		; EMT 377: the end
	beql	done
	addl2	#2, (sp)		; anything else: logged, stepped over
	rei
done:	halt

	.align	4
unexp:	movl	#^xBAD, (r11)+
	movl	(sp), (r11)+
	movl	4(sp), (r11)+
	halt
