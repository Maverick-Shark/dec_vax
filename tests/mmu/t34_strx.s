; t34_strx - MOVTC (forward, backward with overlapping strings, truncated,
; all fill, empty), MOVTUC (stopped by the escape character, by either
; length), MATCHC (found, not found, empty object, object longer than the
; string, found at the end), CRC (CRC-16 and CRC-32 tables, empty string).
; Each case logs the PSL and R0-R5; the strings are dumped. Compared with
; the reference simulator.
;@ dump=8000:C0 dump=18000:140
	.include "mmsetup.inc"
STR	= S0+^x8000			; strings
TBL	= S0+^x8200			; translation table: 255 - i
CT16	= S0+^x8300			; CRC tables
CT32	= S0+^x8340
test:
	clrl	r0
tbl_l:	subb3	r0, #^xFF, @#TBL[r0]
	aoblss	#256, r0, tbl_l
	movc3	#64, @#S0+crc_t, @#CT16

; MOVTC 5 bytes into 8, forward, fill *
	movc5	#0, @#STR, #0, #64, @#STR
	movl	#^x44434241, @#STR+^x40
	movl	#^x48474645, @#STR+^x44
	movl	#^x4C4B4A49, @#STR+^x48
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#^x55555555, r4
	movl	#^x66666666, r5
	bicpsw	#^xF
	movtc	#5, @#STR+^x40, #^x2A, @#TBL, #8, @#STR
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
	movc3	#32, @#STR, (r11)
	movl	r3, r11
; MOVTC 8 bytes into 3: truncated
	movc5	#0, @#STR, #0, #64, @#STR
	movl	#^x44434241, @#STR+^x40
	movl	#^x48474645, @#STR+^x44
	movl	#^x4C4B4A49, @#STR+^x48
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#^x55555555, r4
	movl	#^x66666666, r5
	bicpsw	#^xF
	movtc	#8, @#STR+^x40, #^x2A, @#TBL, #3, @#STR+^x10
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
	movc3	#32, @#STR, (r11)
	movl	r3, r11
; MOVTC overlapping, source below: backward
	movc5	#0, @#STR, #0, #64, @#STR
	movl	#^x44434241, @#STR+^x40
	movl	#^x48474645, @#STR+^x44
	movl	#^x4C4B4A49, @#STR+^x48
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#^x55555555, r4
	movl	#^x66666666, r5
	bicpsw	#^xF
	movtc	#6, @#STR+^x40, #^x2A, @#TBL, #9, @#STR+^x42
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
	movc3	#32, @#STR, (r11)
	movl	r3, r11
; MOVTC overlapping, source above: forward
	movc5	#0, @#STR, #0, #64, @#STR
	movl	#^x44434241, @#STR+^x40
	movl	#^x48474645, @#STR+^x44
	movl	#^x4C4B4A49, @#STR+^x48
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#^x55555555, r4
	movl	#^x66666666, r5
	bicpsw	#^xF
	movtc	#6, @#STR+^x42, #^x2A, @#TBL, #6, @#STR+^x40
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
	movc3	#32, @#STR, (r11)
	movl	r3, r11
; MOVTC nothing to move: all fill
	movc5	#0, @#STR, #0, #64, @#STR
	movl	#^x44434241, @#STR+^x40
	movl	#^x48474645, @#STR+^x44
	movl	#^x4C4B4A49, @#STR+^x48
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#^x55555555, r4
	movl	#^x66666666, r5
	bicpsw	#^xF
	movtc	#0, @#STR+^x40, #^x2E, @#TBL, #5, @#STR+^x20
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
	movc3	#32, @#STR, (r11)
	movl	r3, r11
; MOVTC nothing at all
	movc5	#0, @#STR, #0, #64, @#STR
	movl	#^x44434241, @#STR+^x40
	movl	#^x48474645, @#STR+^x44
	movl	#^x4C4B4A49, @#STR+^x48
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#^x55555555, r4
	movl	#^x66666666, r5
	bicpsw	#^xF
	movtc	#0, @#STR+^x40, #^x2E, @#TBL, #0, @#STR+^x20
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
	movc3	#32, @#STR, (r11)
	movl	r3, r11
; MOVTC srclen 8000 (negative as a word) : 1
	movc5	#0, @#STR, #0, #64, @#STR
	movl	#^x44434241, @#STR+^x40
	movl	#^x48474645, @#STR+^x44
	movl	#^x4C4B4A49, @#STR+^x48
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#^x55555555, r4
	movl	#^x66666666, r5
	bicpsw	#^xF
	movtc	#^x8000, @#STR+^x40, #^x2E, @#TBL, #1, @#STR+^x28
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
	movc3	#32, @#STR, (r11)
	movl	r3, r11
; MOVTUC stopped by the escape (B translates to BD)
	movc5	#0, @#STR, #0, #64, @#STR
	movl	#^x44434241, @#STR+^x40
	movl	#^x48474645, @#STR+^x44
	movl	#^x4C4B4A49, @#STR+^x48
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#^x55555555, r4
	movl	#^x66666666, r5
	bicpsw	#^xF
	movtuc	#8, @#STR+^x40, #^xBD, @#TBL, #10, @#STR
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
	movc3	#32, @#STR, (r11)
	movl	r3, r11
; MOVTUC the source ends
	movc5	#0, @#STR, #0, #64, @#STR
	movl	#^x44434241, @#STR+^x40
	movl	#^x48474645, @#STR+^x44
	movl	#^x4C4B4A49, @#STR+^x48
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#^x55555555, r4
	movl	#^x66666666, r5
	bicpsw	#^xF
	movtuc	#4, @#STR+^x44, #^x01, @#TBL, #10, @#STR+^x10
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
	movc3	#32, @#STR, (r11)
	movl	r3, r11
; MOVTUC the destination ends
	movc5	#0, @#STR, #0, #64, @#STR
	movl	#^x44434241, @#STR+^x40
	movl	#^x48474645, @#STR+^x44
	movl	#^x4C4B4A49, @#STR+^x48
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#^x55555555, r4
	movl	#^x66666666, r5
	bicpsw	#^xF
	movtuc	#8, @#STR+^x40, #^x01, @#TBL, #3, @#STR+^x18
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
	movc3	#32, @#STR, (r11)
	movl	r3, r11
; MATCHC found in the middle
	movc5	#0, @#STR, #0, #64, @#STR
	movl	#^x44434241, @#STR+^x40
	movl	#^x48474645, @#STR+^x44
	movl	#^x4C4B4A49, @#STR+^x48
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#^x55555555, r4
	movl	#^x66666666, r5
	bicpsw	#^xF
	matchc	#3, @#STR+^x43, #12, @#STR+^x40
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
	movc3	#32, @#STR, (r11)
	movl	r3, r11
; MATCHC not found
	movc5	#0, @#STR, #0, #64, @#STR
	movl	#^x44434241, @#STR+^x40
	movl	#^x48474645, @#STR+^x44
	movl	#^x4C4B4A49, @#STR+^x48
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#^x55555555, r4
	movl	#^x66666666, r5
	bicpsw	#^xF
	matchc	#2, @#STR+^x41, #12, @#STR+^x44
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
	movc3	#32, @#STR, (r11)
	movl	r3, r11
; MATCHC empty object
	movc5	#0, @#STR, #0, #64, @#STR
	movl	#^x44434241, @#STR+^x40
	movl	#^x48474645, @#STR+^x44
	movl	#^x4C4B4A49, @#STR+^x48
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#^x55555555, r4
	movl	#^x66666666, r5
	bicpsw	#^xF
	matchc	#0, @#STR+^x41, #12, @#STR+^x44
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
	movc3	#32, @#STR, (r11)
	movl	r3, r11
; MATCHC object longer than the string
	movc5	#0, @#STR, #0, #64, @#STR
	movl	#^x44434241, @#STR+^x40
	movl	#^x48474645, @#STR+^x44
	movl	#^x4C4B4A49, @#STR+^x48
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#^x55555555, r4
	movl	#^x66666666, r5
	bicpsw	#^xF
	matchc	#5, @#STR+^x40, #3, @#STR+^x40
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
	movc3	#32, @#STR, (r11)
	movl	r3, r11
; MATCHC found at the end
	movc5	#0, @#STR, #0, #64, @#STR
	movl	#^x44434241, @#STR+^x40
	movl	#^x48474645, @#STR+^x44
	movl	#^x4C4B4A49, @#STR+^x48
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#^x55555555, r4
	movl	#^x66666666, r5
	bicpsw	#^xF
	matchc	#2, @#STR+^x4A, #12, @#STR+^x40
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
	movc3	#32, @#STR, (r11)
	movl	r3, r11
; MATCHC empty string, empty object
	movc5	#0, @#STR, #0, #64, @#STR
	movl	#^x44434241, @#STR+^x40
	movl	#^x48474645, @#STR+^x44
	movl	#^x4C4B4A49, @#STR+^x48
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#^x55555555, r4
	movl	#^x66666666, r5
	bicpsw	#^xF
	matchc	#0, @#STR+^x40, #0, @#STR+^x44
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
	movc3	#32, @#STR, (r11)
	movl	r3, r11
; CRC-16 of ABCDEFGHIJKL, initial 0
	movc5	#0, @#STR, #0, #64, @#STR
	movl	#^x44434241, @#STR+^x40
	movl	#^x48474645, @#STR+^x44
	movl	#^x4C4B4A49, @#STR+^x48
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#^x55555555, r4
	movl	#^x66666666, r5
	bicpsw	#^xF
	crc	@#CT16, #0, #12, @#STR+^x40
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
	movc3	#32, @#STR, (r11)
	movl	r3, r11
; CRC-16, initial FFFF
	movc5	#0, @#STR, #0, #64, @#STR
	movl	#^x44434241, @#STR+^x40
	movl	#^x48474645, @#STR+^x44
	movl	#^x4C4B4A49, @#STR+^x48
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#^x55555555, r4
	movl	#^x66666666, r5
	bicpsw	#^xF
	crc	@#CT16, #^xFFFF, #12, @#STR+^x40
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
	movc3	#32, @#STR, (r11)
	movl	r3, r11
; CRC-32 of ABCDEFGHIJKL, initial FFFFFFFF
	movc5	#0, @#STR, #0, #64, @#STR
	movl	#^x44434241, @#STR+^x40
	movl	#^x48474645, @#STR+^x44
	movl	#^x4C4B4A49, @#STR+^x48
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#^x55555555, r4
	movl	#^x66666666, r5
	bicpsw	#^xF
	crc	@#CT32, #-1, #12, @#STR+^x40
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
	movc3	#32, @#STR, (r11)
	movl	r3, r11
; CRC of nothing: the initial value
	movc5	#0, @#STR, #0, #64, @#STR
	movl	#^x44434241, @#STR+^x40
	movl	#^x48474645, @#STR+^x44
	movl	#^x4C4B4A49, @#STR+^x48
	movl	#^x11111111, r0
	movl	#^x22222222, r1
	movl	#^x33333333, r2
	movl	#^x44444444, r3
	movl	#^x55555555, r4
	movl	#^x66666666, r5
	bicpsw	#^xF
	crc	@#CT32, #^x12345678, #0, @#STR+^x40
	movpsl	(r11)+
	movq	r0, (r11)+
	movq	r2, (r11)+
	movq	r4, (r11)+
	movc3	#32, @#STR, (r11)
	movl	r3, r11
	halt
	.align	2
crc_t:
	.long	^x00000000
	.long	^x0000CC01
	.long	^x0000D801
	.long	^x00001400
	.long	^x0000F001
	.long	^x00003C00
	.long	^x00002800
	.long	^x0000E401
	.long	^x0000A001
	.long	^x00006C00
	.long	^x00007800
	.long	^x0000B401
	.long	^x00005000
	.long	^x00009C01
	.long	^x00008801
	.long	^x00004400
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
