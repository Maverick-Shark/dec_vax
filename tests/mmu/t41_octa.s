; t41_octa - the two-byte opcodes (FD xx) and the octaword operands: CLRO,
; MOVO, MOVAO and PUSHAO in register, register deferred, autoincrement and
; autodecrement (by 16), displacement, index (times 16), immediate (16
; bytes of the instruction stream) and short literal modes, unaligned; the
; condition codes (N from bit 127, Z, V cleared, C unchanged); a destination
; that runs into an invalid page (nothing is stored before the fault, whose
; PC is the FD byte); a two-byte opcode split across a page boundary (the
; translation-not-valid fault on its second byte has the PC of the FD
; byte); octaword register operands in R12 (reserved addressing mode,
; SCB 1C); undefined FD opcodes (reserved instruction, SCB 10, PC at the FD
; byte). Compared with the reference simulator, which reports the fault on
; the destination with parameter 0, a read; the RTL with 4, write intent
; (SRM 4.9: the access was a write).
;@ dump=8000:60 dump=8DF0:8 dump=18000:40 page=18074 rtl=18070:00000004
	.include "mmsetup.inc"
D	= S0+^x8000
SPLIT	= S0+^x91FF			; FD as the last byte of page 48
test:
	movl	#S0+resad_h, @#^x1C
	movl	#S0+resin_h, @#^x10
; register to register; N from bit 127
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x84444444, r3
	movo	r0, r4
	movpsl	(r11)+
	movl	r4, (r11)+
	movl	r5, (r11)+
	movl	r6, (r11)+
	movl	r7, (r11)+
; immediate and short literal sources
	movo	#^x0123456789ABCDEFFEDCBA9876543210, r4
	movpsl	(r11)+
	movo	r4, @#D
	movo	S^#7, r4
	movpsl	(r11)+
	movo	r4, @#D+^x10
; zero: Z, and C is left alone
	bispsw	#1
	movo	S^#0, r4
	movpsl	(r11)+
	bispsw	#^xF
	clro	r4
	movpsl	(r11)+
	movl	r4, (r11)+
	movl	r7, (r11)+
	bicpsw	#^xF
	clro	@#D+^x20
	movpsl	(r11)+
; memory to memory: register deferred, autoincrement, autodecrement
	movab	@#D, r1
	movab	@#D+^x30, r2
	movo	(r1)+, (r2)+			; D -> D+30
	movo	(r1)+, (r2)+			; D+10 -> D+40
	movl	r1, (r11)+
	movl	r2, (r11)+
	movo	-(r1), -(r2)			; D+10 -> D+40 again
	movl	r1, (r11)+
	movl	r2, (r11)+
	movo	(r1), @#D+^x50
; displacement and index (times 16), unaligned
	movl	#3, r3
	movo	-^x30(r2)[r3], 3(r2)		; D+30 -> D+43
	movo	@#D+^x43, @#D+^x55		; unaligned both
	movab	@#D, r5
	movl	#5, r6
	movo	(r5)[r6], r0			; D+50
	movl	r0, (r11)+
	movl	r1, (r11)+
	movl	r2, (r11)+
	movl	r3, (r11)+
; MOVAO and PUSHAO: the address, the index times 16
	movao	@#D, r0
	movl	r0, (r11)+
	movao	4(r5)[r6], r0			; D + 4 + 50
	movpsl	(r11)+
	movl	r0, (r11)+
	movl	sp, r7
	pushao	(r5)[r6]
	movl	(sp)+, (r11)+
	subl3	sp, r7, (r11)+			; 0: SP back where it was
	movl	#S0+^x8F00, r0
	movao	-(r0), r1			; R0 down by 16
	movl	r0, (r11)+
	movl	r1, (r11)+
; a destination running into an invalid page (47): nothing is stored, the
; fault has the PC of the FD byte; the fix-up logs the first half and makes
; the page valid, the instruction runs again
	movq	#-1, @#S0+^x8DF8
	movq	#-1, @#S0+^x8E00
	bicl2	#PTE_V, @#S0+SPT+<^x47*4>
	mtpr	#S0+^x8E00, #TBIS
	movl	#S0+fix_peek, r10
	movab	split1, (r11)+
split1:	movo	@#D, @#S0+^x8DF8
	clrl	r10
	movl	#^xAAAA, (r11)+
; a two-byte opcode with its second byte on an invalid page (49): the fault
; PC is the FD byte
	movab	@#SPLIT, r1
	movb	#^xFD, (r1)+
	movb	#^x7D, (r1)+			; MOVO R0, R4
	movb	#^x50, (r1)+
	movb	#^x54, (r1)+
	movb	#^x17, (r1)+			; JMP @#back
	movb	#^x9F, (r1)+
	movab	back, (r1)+
	movo	#^x99999999888888887777777766666666, r0
	clro	r4
	bicl2	#PTE_V, @#S0+SPT+<^x49*4>
	mtpr	#S0+^x9200, #TBIS
	movl	#S0+fix_valid, r10
	jmp	@#SPLIT
back:	clrl	r10
	movl	r4, (r11)+
	movl	r7, (r11)+
; octaword register operands in AP, FP, SP: reserved addressing mode; the
; handler resumes at R8
	movab	ra1, r8
	movo	ap, r0
ra1:	movab	ra2, r8
	clro	fp
ra2:	movab	ra3, r8
	movo	r0, sp
ra3:	movl	#^xBBBB, (r11)+
; undefined two-byte opcodes: reserved instruction at the FD byte
	movab	ri1, r8
	.byte	^xFD, ^x00			; not HALT
ri1:	movab	ri2, r8
	.byte	^xFD, ^x31
ri2:	movab	ri3, r8
	.byte	^xFD, ^xFD
ri3:	movl	#^xCCCC, (r11)+
	halt

; reserved addressing mode (SCB 1C) and reserved instruction (SCB 10):
; marker, PC, PSL; resume at R8
	.align	4
resad_h:
	movl	#^x5E5E001C, (r11)+
	brb	ri_log
	.align	4
resin_h:
	movl	#^x5E5E0010, (r11)+
ri_log:	movl	(sp), (r11)+
	movl	4(sp), (r11)+
	movl	r8, (sp)
	rei

; fix-up: log the first half of the destination, then make page 47 valid
fix_peek:
	movl	@#S0+^x8DF8, (r11)+
	movl	@#S0+^x8DFC, (r11)+
	bisl2	#PTE_V, @#S0+SPT+<^x47*4>
	rsb
