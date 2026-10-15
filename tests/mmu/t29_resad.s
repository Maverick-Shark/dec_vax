; t29_resad - reserved addressing mode faults (SCB 1C), with the cases
; the SRM leaves UNPREDICTABLE as simh decides them for the 8600: a literal
; for anything but a read operand, a register for an address operand, PC as
; a register or with register deferred, autodecrement or as an index
; register, a literal, register or index base for index mode, a quadword in
; SP. A fault leaves the PC at the instruction and undoes the autoincrement
; of an earlier operand. Found with EVKAE test 2. The instructions are given
; as bytes (the assembler would not make most of them). For each case the
; log gets 1C1C1C1C and the PC if it faulted, else 600D.
;@ dump=18000:40
	.include "mmsetup.inc"
test:
	movl	#S0+resad_h, @#^x1C
	clrl	r7
	movl	#S0+^x8000, r1
	movl	#4, r2
	movl	#^x5555AAAA, @#S0+^x8000
	movl	#^x12345678, @#S0+^x8010
	movl	#2, r4

; MOVL R0, S^#3: literal destination
	movab	z0, r8
c0:	.byte	^xD0, ^x50, ^x03
	movl	#^x600D, (r11)+
z0:
; INCL S^#1: literal modify operand
	movab	z1, r8
c1:	.byte	^xD6, ^x01
	movl	#^x600D, (r11)+
z1:
; ADDL3 R0, R1, S^#2: literal destination
	movab	z2, r8
c2:	.byte	^xC1, ^x50, ^x51, ^x02
	movl	#^x600D, (r11)+
z2:
; MOVAB S^#1, R1: literal address operand
	movab	z3, r8
c3:	.byte	^x9E, ^x01, ^x51
	movl	#^x600D, (r11)+
z3:
; EXTZV #0, #4, S^#5, R0: literal field base
	movab	z4, r8
c4:	.byte	^xEF, ^x00, ^x04, ^x05, ^x50
	movl	#^x600D, (r11)+
z4:
; MOVAB R0, R1: register address operand
	movab	z5, r8
c5:	.byte	^x9E, ^x50, ^x51
	movl	#^x600D, (r11)+
z5:
; JMP R0: register address operand
	movab	z6, r8
c6:	.byte	^x17, ^x50
	movl	#^x600D, (r11)+
z6:
; MOVL PC, R0: PC as a register
	movab	z7, r8
c7:	.byte	^xD0, ^x5F, ^x50
	movl	#^x600D, (r11)+
z7:
; MOVL R0, PC: PC as a register destination
	movab	z8, r8
c8:	.byte	^xD0, ^x50, ^x5F
	movl	#^x600D, (r11)+
z8:
; MOVL (PC), R0: register deferred PC
	movab	z9, r8
c9:	.byte	^xD0, ^x6F, ^x50
	movl	#^x600D, (r11)+
z9:
; MOVL -(PC), R0: autodecrement PC
	movab	z10, r8
c10:	.byte	^xD0, ^x7F, ^x50
	movl	#^x600D, (r11)+
z10:
; MOVL (R1)+, (PC): the (R1)+ is undone
	movab	z11, r8
c11:	.byte	^xD0, ^x81, ^x6F
	movl	#^x600D, (r11)+
z11:
; MOVL R1[PC], R0: PC as the index register
	movab	z12, r8
c12:	.byte	^xD0, ^x4F, ^x51, ^x50
	movl	#^x600D, (r11)+
z12:
; MOVL R1[R2], R0: register base
	movab	z13, r8
c13:	.byte	^xD0, ^x42, ^x51, ^x50
	movl	#^x600D, (r11)+
z13:
; MOVL S^#1[R2], R0: literal base
	movab	z14, r8
c14:	.byte	^xD0, ^x42, ^x01, ^x50
	movl	#^x600D, (r11)+
z14:
; MOVL [R3][R2], R0: index base
	movab	z15, r8
c15:	.byte	^xD0, ^x42, ^x43, ^x61, ^x50
	movl	#^x600D, (r11)+
z15:
; MOVL (PC)[R2], R0: register deferred PC base
	movab	z16, r8
c16:	.byte	^xD0, ^x42, ^x6F, ^x50
	movl	#^x600D, (r11)+
z16:
; MOVQ R0, SP: quadword in SP
	movab	z17, r8
c17:	.byte	^x7D, ^x50, ^x5E
	movl	#^x600D, (r11)+
z17:
; CLRQ SP
	movab	z18, r8
c18:	.byte	^x7C, ^x5E
	movl	#^x600D, (r11)+
z18:
; MOVL (R1)[R2], R0: legal
	movab	z19, r8
c19:	.byte	^xD0, ^x42, ^x61, ^x50
	movl	#^x600D, (r11)+
z19:
; BBS #1, R4, .+3: register field base, legal
	movab	z20, r8
c20:	.byte	^xE0, ^x01, ^x54, ^x00
	movl	#^x600D, (r11)+
z20:
; MOVZBL #^x7F[R2], R0: immediate base, legal on the 8600
	movab	z21, r8
c21:	.byte	^x9A, ^x42, ^x8F, ^x7F, ^x50
	movl	#^x600D, (r11)+
z21:
	movl	r0, (r11)+
	movl	r1, (r11)+
	halt
	.align	4
resad_h:
	incl	r7
	movl	#^x1C1C1C1C, (r11)+
	movl	(sp), (r11)+			; PC: the faulting instruction
	movl	r8, (sp)			; resume after it
	rei
