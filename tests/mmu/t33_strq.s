; t33_strq - INDEX (subscript range trap, type 7), SKPC, LOCC with a length
; above 7FFF (unsigned), SCANC, SPANC, ADAWI (register, memory, odd address:
; reserved operand), and the interlocked queue instructions INSQHI, INSQTI,
; REMQHI, REMQTI: inserts and removes at both ends, the empty queue, a queue
; of one entry, the interlock bit set (busy), and the reserved operand
; faults for unaligned entries, links and headers, entry = header and
; destination = header. Each case logs its results and PSL; the trap
; handler logs 34, the type code, PC and PSL. Compared with the reference
; simulator.
;@ dump=8000:50 dump=8400:4 dump=18000:100
	.include "mmsetup.inc"
H	= S0+^x8000			; queue header
E1	= S0+^x8010			; entries
E2	= S0+^x8020
E3	= S0+^x8030
STR	= S0+^x8100			; "   ABC1 " then zeros
TBL	= S0+^x8200			; SCANC/SPANC table
W	= S0+^x8400			; ADAWI words
test:
	movl	#S0+arith_h, @#^x34
; INDEX
	clrl	r0
	index	#5, #0, #9, #4, #0, r0		; 20
	movpsl	(r11)+
	movl	r0, (r11)+
	index	#10, #0, #9, #4, #0, r0		; > high: trap 7, 40 stored
	movpsl	(r11)+
	movl	r0, (r11)+
	index	#-1, #0, #9, #4, #0, r0		; < low: trap 7, -4
	movpsl	(r11)+
	movl	r0, (r11)+
	index	#-5, #-10, #-1, #2, #100, r0	; 190
	movpsl	(r11)+
	movl	r0, (r11)+
	index	#^x7FFFFFFF, #^x80000000, #^x7FFFFFFF, #1, #0, r0
	movpsl	(r11)+
	movl	r0, (r11)+
	index	#^x80000000, #-1, #^x7FFFFFFF, #1, #0, r0	; < low
	movpsl	(r11)+
	movl	r0, (r11)+
	index	#0, #1, #0, #3, #0, r0		; low > high: < low, Z
	movpsl	(r11)+
	movl	r0, (r11)+
	index	#3, #0, #9, #8, #16, @#W+8	; to memory: 152
	movpsl	(r11)+
; the string and the table
	movl	#^x41202020, @#STR		; "   A"
	movl	#^x20314342, @#STR+4		; "BC1 "
	movc5	#0, @#STR, #0, #256, @#TBL
	movl	#^x41, r1			; A-Z: 1
q_az:	movb	#1, @#TBL[r1]
	aoblss	#^x5B, r1, q_az
	movl	#^x30, r1			; 0-9: 2
q_09:	movb	#2, @#TBL[r1]
	aoblss	#^x3A, r1, q_09
	movb	#4, @#TBL+^x20			; space: 4
; SKPC, LOCC
	skpc	#^x20, #8, @#STR		; "ABC1 ": R0 = 5, R1 = STR+3
	movpsl	(r11)+
	movq	r0, (r11)+
	skpc	#^x20, #3, @#STR		; all blanks: R0 = 0, Z
	movpsl	(r11)+
	movq	r0, (r11)+
	skpc	#^x20, #0, @#STR		; length 0
	movpsl	(r11)+
	movq	r0, (r11)+
	locc	#^x43, #8, @#STR		; "C": R0 = 3
	movpsl	(r11)+
	movq	r0, (r11)+
	locc	#0, #^x9000, @#STR		; the first zero, length unsigned
	movpsl	(r11)+
	movq	r0, (r11)+
	locc	#^x5A, #8, @#STR		; not there: R0 = 0, R1 = the end
	movpsl	(r11)+
	movq	r0, (r11)+
; SCANC, SPANC
	movl	#-1, r2
	scanc	#8, @#STR, @#TBL, #1		; the first letter
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	scanc	#8, @#STR, @#TBL, #^x80		; none
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	spanc	#8, @#STR, @#TBL, #4		; over the blanks
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	spanc	#7, @#STR, @#TBL, #7		; all of them
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	spanc	#4, @#STR+3, @#TBL, #3		; "ABC1": letters and digits
	movpsl	(r11)+
	movq	r0, (r11)+
; ADAWI
	movl	#^x12347FFF, r0
	bispsw	#^x20
	adawi	#1, r0				; V N, trap 1
	bicpsw	#^x20
	movpsl	(r11)+
	movl	r0, (r11)+
	clrl	@#W
	adawi	#-1, @#W			; FFFF, N
	movpsl	(r11)+
	movl	#^xFFFF, @#W+4
	adawi	#1, @#W+4			; 0, Z C
	movpsl	(r11)+
	movl	#^x8000, r0
	adawi	#^x8000, r0			; 0, Z V C
	movpsl	(r11)+
	movl	r0, (r11)+
	movab	adawi_back, r8
	movl	#S0+fix_skip, r10
	adawi	#1, @#W+1			; odd: reserved operand
adawi_back:
	clrl	r10
; queues
	clrq	@#H
	movl	#^x11111111, r1
	remqhi	@#H, r1				; empty: R1 = H, Z V
	movpsl	(r11)+
	movl	r1, (r11)+
	insqhi	@#E1, @#H			; was empty: Z
	movpsl	(r11)+
	insqti	@#E2, @#H			; H E1 E2
	movpsl	(r11)+
	insqhi	@#E3, @#H			; H E3 E1 E2
	movpsl	(r11)+
	movq	@#H, (r11)+
	movq	@#E1, (r11)+
	movq	@#E2, (r11)+
	movq	@#E3, (r11)+
	remqti	@#H, r2				; E2; H E3 E1
	movpsl	(r11)+
	remqhi	@#H, r3				; E3; H E1
	movpsl	(r11)+
	remqti	@#H, r4				; one entry: E1, empty now: Z
	movpsl	(r11)+
	remqti	@#H, r5				; empty: R5 = H, Z V
	movpsl	(r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
	movq	@#H, (r11)+
	insqti	@#E2, @#H			; into an empty queue: as INSQHI, Z
	movpsl	(r11)+
	remqhi	@#H, @#W+12			; to memory; empty now: Z
	movpsl	(r11)+
	movl	@#W+12, (r11)+
; busy: the interlock bit set, nothing done
	movl	#1, @#H
	movl	#^x22222222, r6
	insqhi	@#E1, @#H			; C
	movpsl	(r11)+
	insqti	@#E1, @#H			; C
	movpsl	(r11)+
	remqhi	@#H, r6				; V C, R6 unchanged
	movpsl	(r11)+
	remqti	@#H, r6
	movpsl	(r11)+
	movl	r6, (r11)+
	movq	@#H, (r11)+
	clrq	@#H
; reserved operands
	movl	#S0+fix_skip, r10
	movab	ro1, r8
	insqhi	@#E1+4, @#H			; entry not quadword aligned
ro1:	movab	ro2, r8
	remqhi	@#H+4, r1			; header not aligned
ro2:	movab	ro3, r8
	insqhi	@#H, @#H			; entry = header
ro3:	movab	ro4, r8
	remqhi	@#H, @#H			; destination = header
ro4:	movl	#^xC, @#H			; a link not aligned
	movab	ro5, r8
	remqhi	@#H, r1
ro5:	movab	ro6, r8
	insqhi	@#E1, @#H
ro6:	clrl	r10
	movq	@#H, (r11)+
	halt

	.align	4
arith_h:
	movl	#^x34, (r11)+
	movl	(sp)+, (r11)+			; type code
	movl	(sp), (r11)+
	movl	4(sp), (r11)+
	rei
