; t39_strfpd - MOVTUC, MATCHC and CRC stopped part way by a translation not
; valid fault (A-D) and by interval timer interrupts with trace on (E): the
; frame has PSL<FPD> and the PC of the instruction, and after the REI the
; instruction goes on from where it stopped. A: a MOVTUC in place (source
; and destination at the same address, which the SRM defines) across an
; invalid page - started again from the beginning, it would translate the
; first 16 bytes twice. B: a MOVTUC that meets the escape character after
; the fault. C: MATCHC, the object found on the page after the fault. D:
; CRC. E: the three on 8 KB with the timer interrupting every 1000 us and
; PSL<T> set: each traced once, when it completes (the trace handler logs
; the PC and PSL). The reference simulator keeps the same instructions'
; progress in R0-R5 with PSL<FPD> too; the interrupt counts (R7: with FPD,
; R9: all) are not compared, nor the condition codes in the fault frames
; (UNPREDICTABLE).
;@ dump=8BF0:8 dump=93F0:6 dump=9800:4 dump=18000:30 dump=180C0:40
;@ dump=1A000:4 dump=1BFF0:4 ignore=R7,R9
;@ mask=1800C:FFFFFFF0,1803C:FFFFFFF0,1806C:FFFFFFF0,18094:FFFFFFF0
;@ page=18004,18034,18064,1808C
	.include "mmsetup.inc"
ICCS	= ^x18
NICR	= ^x19
IPL	= ^x12
T1	= S0+^x9000			; i + 30
T2	= S0+^x9100			; i AND 7F
OBJ	= S0+^x9600			; MATCHC objects
CRCT	= S0+^x9A00			; CRC-32 table
test:
	clrl	r0
tbl_l:	addb3	r0, #^x30, @#T1[r0]
	bicb3	#^x80, r0, @#T2[r0]
	aoblss	#256, r0, tbl_l
	movc3	#64, @#S0+crc_t, @#CRCT
	movl	#^x5A595841, @#OBJ		; "AXYZ"
	movl	#^x83828180, @#OBJ+4
	movl	#S0+fix_valid, r10
; A: MOVTUC in place, 8BF0..8C0F = 1..20, page 46 (8C00) invalid
	movl	#S0+^x8BF0, r1
	movl	#1, r0
a_fill:	movb	r0, (r1)+
	aobleq	#^x20, r0, a_fill
	bicl2	#PTE_V, @#S0+SPT+<^x46*4>
	mtpr	#S0+^x8C00, #TBIS
	movtuc	#^x20, @#S0+^x8BF0, #^xFF, @#T1, #^x20, @#S0+^x8BF0
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
; B: MOVTUC 93F8..9407 -> 9800, page 4A (9400) invalid; the 12th byte (0C)
; translates to the escape character 3C
	movl	#^x04030201, @#S0+^x93F8
	movl	#^x08070605, @#S0+^x93FC
	movl	#^x0C0B0A09, @#S0+^x9400
	movl	#^x100F0E0D, @#S0+^x9404
	bicl2	#PTE_V, @#S0+SPT+<^x4A*4>
	mtpr	#S0+^x9400, #TBIS
	movtuc	#^x10, @#S0+^x93F8, #^x3C, @#T1, #^x18, @#S0+^x9800
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
; C: MATCHC "AXYZ" in 9DF0..9E0F (zeros, the object at 9E03), page 4F
; (9E00) invalid
	movc5	#0, (r0), #0, #^x20, @#S0+^x9DF0
	movl	@#OBJ, @#S0+^x9E03
	bicl2	#PTE_V, @#S0+SPT+<^x4F*4>
	mtpr	#S0+^x9E00, #TBIS
	matchc	#4, @#OBJ, #^x20, @#S0+^x9DF0
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
; D: CRC-32 of A7F0..A80F (bytes 0..1F), page 54 (A800) invalid
	movl	#S0+^xA7F0, r1
	clrl	r0
d_fill:	movb	r0, (r1)+
	aoblss	#^x20, r0, d_fill
	bicl2	#PTE_V, @#S0+SPT+<^x54*4>
	mtpr	#S0+^xA800, #TBIS
	crc	@#CRCT, #-1, #^x20, @#S0+^xA7F0
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
; E: interrupts and trace, on 8 KB of data at 1C000 (made here, so that it
; does not depend on the code; the board's runner puts its table of results
; into the test's image)
	movl	#S0+^x1C000, r1
	clrl	r0
e_fill:	mulb3	#37, r0, (r1)+
	aoblss	#^x2000, r0, e_fill
	clrl	r10
	movl	#S0+^x180C0, r11		; a log of its own
	movl	#S0+clk_h, @#^xC0
	movl	#S0+trace_h, @#^x28
	clrl	r7
	clrl	r9
	mtpr	#-1000, #NICR			; every 1000 us (50000 clocks)
	mtpr	#^x51, #ICCS			; run, transfer, interrupt enable
	pushl	#^x10				; kernel stack, IPL 0, PSL<T>
	pushl	#S0+e_go
	rei
e_go:	movtuc	#^x2000, @#S0+^x1C000, #^x80, @#T2, #^x2000, @#S0+^x1A000
	movq	r0, (r11)+
	movl	@#OBJ+4, @#S0+^x1BFFC		; 80 81 82 83 at the end
	matchc	#4, @#OBJ+4, #^x2000, @#S0+^x1A000
	movq	r0, (r11)+
	movq	r2, (r11)+
	crc	@#CRCT, #-1, #^x2000, @#S0+^x1A000
	movq	r0, (r11)+
	bicpsw	#^x10
	mtpr	#^x1F, #IPL
	mtpr	#0, #ICCS
	halt
	.align	4
trace_h:
	movl	(sp), (r11)+			; PC: the next instruction
	movl	4(sp), (r11)+			; PSL: T set, TP and FPD clear
	rei
clk_h:	incl	r9
	bbc	#27, 4(sp), clk_1		; PSL<FPD> in the frame?
	incl	r7
clk_1:	mtpr	#^xC1, #ICCS			; clear the interrupt
	rei
; CRC-32 (AUTODIN-II), four bits at a time
crc_t:
	.long	^x00000000
	.long	^x1DB71064
	.long	^x3B6E20C8
	.long	^x26D930AC
	.long	^x76DC4190
	.long	^x6B6B51F4
	.long	^x4DB26158
	.long	^x5005713C
	.long	^xEDB88320
	.long	^xF00F9344
	.long	^xD6D6A3E8
	.long	^xCB61B38C
	.long	^x9B64C2B0
	.long	^x86D3D2D4
	.long	^xA00AE278
	.long	^xBDBDF21C
