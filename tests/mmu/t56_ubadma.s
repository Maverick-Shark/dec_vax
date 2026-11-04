; t56_ubadma - the DW780's DMA side, reached by the CPU through the Unibus
; (wraparound: a reference to Unibus space below the I/O page goes out on
; the Unibus as DATI, DATO or DATOB and comes back through the adapter's
; own map; EK-DW780-TD-001 1.9.2, 2.6, 3.3, appendix A):
;
;   - the direct data path: words and bytes to and from memory (TD table
;     2-9);
;   - an invalid map register: IVMR, FMER, no slave sync (so UBSSYNTO and
;     FUBAR too); a second one while the field is locked: the lost error
;     bit; map registers disabled by CR<30:26>: no response, no IVMR;
;   - a buffered data path written: the bytes collect, the last byte of the
;     quadword sends them (extended write masked), DPR's buffer state and
;     Unibus address; a purge of what is left (write masked); byte by byte;
;   - with byte offset: the bytes one place up, the one past the quadword
;     kept for the next (DPR's address one longword on), purged;
;   - a buffered data path read: the quadword (or from byte 4 the
;     longword), the next words from the buffer even after memory changes,
;     the prefetch of the next quadword after the last word, a purge; a
;     prefetch into an invalid map register: nothing recorded, the buffer
;     empty;
;   - with byte offset: bytes 1-2, 3-4, 5-6, then byte 7 and byte 0 of the
;     next quadword, from empty buffers at word 3 (two reads) and word 2;
;   - the longword access mode: longword reads, a write when the high word
;     or byte 3 is written.
;
; A write to the Unibus is acknowledged at once; "fence" (a Unibus read,
; busy until the write is over) waits for it. Expected values:
; tests/mmu/gen/mk_t56.py.
;@ noref
;@ rtl=18000:00001111,18004:00002222,18008:00003300,1800C:00000044,18010:00001111,18014:22220000
;@ rtl=18018:00443300,1801C:0000CAFE,18020:000000BE,18024:00000000,18028:FFFF0000,1802C:00000011
;@ rtl=18030:00000001,18034:00000080,18038:00000015,1803C:00000001,18040:00000080,18044:00000000
;@ rtl=18048:00000001,1804C:00000011,18050:00000010,18054:A0030100,18058:A03F0101,1805C:00000000
;@ rtl=18060:20000101,18064:A2A3A0A1,18068:A6A7A4A5,1806C:A0070102,18070:00000102,18074:00B2B0B1
;@ rtl=18078:00000000,1807C:20000105,18080:C3C2C1C0,18084:C7C6C5C4,18088:A07E0181,1808C:D2D1D0EE
;@ rtl=18090:D6D5D4D3,18094:EEEEEEEE,18098:A0010182,1809C:EEEEEED7,180A0:00000182,180A4:00000100
;@ rtl=180A8:80000000,180AC:00000302,180B0:00000504,180B4:00000706,180B8:00000908,180BC:00000B0A
;@ rtl=180C0:00000D0C,180C4:00000F0E,180C8:00000000,180CC:0000AAAA,180D0:0000BBBB,180D4:80000000
;@ rtl=180D8:00006666,180DC:00000000,180E0:00001122,180E4:00000000,180E8:00000000,180EC:00001122
;@ rtl=180F0:80000000,180F4:00005544,180F8:00000201,180FC:00000403,18100:00000605,18104:00000807
;@ rtl=18108:00000A09,1810C:00000C0B,18110:00000E0D,18114:0000100F,18118:00000807,1811C:00000A09
;@ rtl=18120:00000605,18124:00000807,18128:00000000,1812C:00002211,18130:00004433,18134:00006655
;@ rtl=18138:00008877,1813C:00000000,18140:56781234,18144:20000382,18148:BC00009A,1814C:00000000
;@ rtl=18150:00000000
;@ clocks=8000000
LOG	= ^x18000
SCBB	= ^x11
UBA	= ^x20006000
UACR	= UBA+^x04
UASR	= UBA+^x08
FMER	= UBA+^x10
FUBAR	= UBA+^x14
DPR	= UBA+^x40
MAP	= UBA+^x800
UB	= ^x20100000		; Unibus 0
MEMA	= ^x20000		; map 0: direct data path
MEMB	= ^x20200		; map 2: BDP 1
MEMC	= ^x20400		; map 3: BDP 2, byte offset
MEMD	= ^x20600		; map 4: BDP 3
MEME	= ^x20800		; map 5: BDP 3 (valid later)
MEMF	= ^x20A00		; map 6: BDP 4, byte offset
MEMG	= ^x20C00		; map 7: BDP 5, longword access

	.org	^x1000
start:	movl	#^xE000, sp
	clrl	r0
	movab	unexp+1, r1
scbfill:
	movl	r1, (r0)+
	cmpl	r0, #^x200
	blss	scbfill
	mtpr	#0, #SCBB
	movl	#LOG, r11
	clrl	r9
; an adapter init first, whatever ran before (the board suite): 25 ms
	movl	#1, @#UBA+^x04
uw1:	bitl	#^x10000, @#UBA		; CNFGR<16>: the Unibus initialized
	beql	uw1
; memory: zeros, then the patterns
	movl	#MEMA, r0
clr1:	clrl	(r0)+
	cmpl	r0, #MEMG+^x200
	blss	clr1
	movl	#^xEEEEEEEE, r1
	movl	r1, @#MEMC
	movl	r1, @#MEMC+4
	movl	r1, @#MEMC+8
	movl	r1, @#MEMC+12
	movl	#MEMD, r0
	bsbw	pat
	movl	#MEMF, r0
	bsbw	pat
; the map registers
	movl	#^x80000100, @#MAP	; 0: valid, DDP, page 100
	clrl	@#MAP+4			; 1: invalid
	movl	#^x80200101, @#MAP+8	; 2: BDP 1
	movl	#^x82400102, @#MAP+12	; 3: BDP 2, byte offset
	movl	#^x80600103, @#MAP+16	; 4: BDP 3
	clrl	@#MAP+20		; 5: invalid for now
	movl	#^x82800105, @#MAP+24	; 6: BDP 4, byte offset
	movl	#^x84A00106, @#MAP+28	; 7: BDP 5, longword access

; ------------------------------------------------ direct data path
	movw	#^x1111, @#UB
	movw	#^x2222, @#UB+6
	movb	#^x33, @#UB+9
	movb	#^x44, @#UB+^xA
	movw	@#UB, r0
	movzwl	r0, (r11)+		; 1111
	movw	@#UB+6, r0
	movzwl	r0, (r11)+		; 2222
	movw	@#UB+8, r0
	movzwl	r0, (r11)+		; 3300
	movw	@#UB+^xA, r0
	movzwl	r0, (r11)+		; 0044
	movl	@#MEMA, (r11)+		; 00001111
	movl	@#MEMA+4, (r11)+	; 22220000
	movl	@#MEMA+8, (r11)+	; 00443300
	movl	#^xCAFEBABE, @#MEMA+12
	movw	@#UB+^xE, r0
	movzwl	r0, (r11)+		; CAFE
	movb	@#UB+^xC, r0
	movzbl	r0, (r11)+		; BE
	movl	@#UASR, (r11)+		; 0

; ------------------------------------------- invalid and disabled maps
	movl	#-1, r0
	movw	@#UB+^x200, r0		; map 1
	movl	r0, (r11)+		; FFFF0000
	movl	@#UASR, (r11)+		; 00000011: IVMR, UBSSYNTO
	movl	@#FMER, (r11)+		; 00000001
	movl	@#FUBAR, (r11)+		; 00000080
	movw	#1, @#UB+^x204		; again, a write
	jsb	fence
	movl	@#UASR, (r11)+		; 00000015: the lost error bit
	movl	@#FMER, (r11)+		; 00000001
	movl	@#FUBAR, (r11)+		; 00000080
	movl	#^x7FF, @#UASR
	movl	@#UASR, (r11)+		; 0
	movl	#^x04000000, @#UACR	; maps 0-15 disabled
	movw	@#UB, r0		; nothing answers
	movl	@#UASR, (r11)+		; 00000001: no IVMR
	movw	@#UB+^x2000, r0		; map 16, invalid
	movl	@#UASR, (r11)+		; 00000011
	movl	@#FMER, (r11)+		; 00000010
	clrl	@#UACR
	movl	#^x7FF, @#UASR

; --------------------------------------- a buffered data path written
	movw	#^xA0A1, @#UB+^x400
	jsb	fence
	movl	@#DPR+4, (r11)+		; A0030100
	movw	#^xA2A3, @#UB+^x402
	movw	#^xA4A5, @#UB+^x404
	jsb	fence
	movl	@#DPR+4, (r11)+		; A03F0101
	movl	@#MEMB, (r11)+		; 0: nothing in memory yet
	movw	#^xA6A7, @#UB+^x406	; the last word: the quadword goes
	jsb	fence
	movl	@#DPR+4, (r11)+		; 20000101
	movl	@#MEMB, (r11)+		; A2A3A0A1
	movl	@#MEMB+4, (r11)+	; A6A7A4A5
	movw	#^xB0B1, @#UB+^x408
	movb	#^xB2, @#UB+^x40A
	jsb	fence
	movl	@#DPR+4, (r11)+		; A0070102
	movl	#^x80000000, @#DPR+4	; purge
	movl	@#DPR+4, (r11)+		; 00000102
	movl	@#MEMB+8, (r11)+	; 00B2B0B1
	movl	@#MEMB+12, (r11)+	; 0
; byte by byte
	movl	#^xC0, r1
	movl	#UB+^x410, r2
c01:	movb	r1, (r2)+
	incl	r1
	cmpl	r1, #^xC8
	blss	c01
	jsb	fence
	movl	@#DPR+4, (r11)+		; 20000105
	movl	@#MEMB+^x10, (r11)+	; C3C2C1C0
	movl	@#MEMB+^x14, (r11)+	; C7C6C5C4

; --------------------------------------------------- with byte offset
	movw	#^xD1D0, @#UB+^x600
	movw	#^xD3D2, @#UB+^x602
	movw	#^xD5D4, @#UB+^x604
	jsb	fence
	movl	@#DPR+8, (r11)+		; A07E0181: bytes 1-6
	movw	#^xD7D6, @#UB+^x606	; byte 7, and byte 0 of the next
	jsb	fence
	movl	@#MEMC, (r11)+		; D2D1D0EE
	movl	@#MEMC+4, (r11)+	; D6D5D4D3
	movl	@#MEMC+8, (r11)+	; EEEEEEEE
	movl	@#DPR+8, (r11)+		; A0010182: byte 0, one longword on
	movl	#^x80000000, @#DPR+8	; purge
	movl	@#MEMC+8, (r11)+	; EEEEEED7
	movl	@#DPR+8, (r11)+		; 00000182

; ---------------------------------------- a buffered data path read
	movw	@#UB+^x800, r0
	movzwl	r0, (r11)+		; 0100: the quadword
	movl	@#DPR+12, (r11)+	; 80000000
	movl	#^x5555AAAA, @#MEMD
	movl	#^x6666BBBB, @#MEMD+4
	movw	@#UB+^x802, r0
	movzwl	r0, (r11)+		; 0302: the buffer
	movw	@#UB+^x804, r0
	movzwl	r0, (r11)+		; 0504
	movw	@#UB+^x806, r0
	movzwl	r0, (r11)+		; 0706, then the prefetch
	movl	#^x99999999, @#MEMD+8
	movw	@#UB+^x808, r0
	movzwl	r0, (r11)+		; 0908: prefetched
	movw	@#UB+^x80A, r0
	movzwl	r0, (r11)+		; 0B0A
	movw	@#UB+^x80C, r0
	movzwl	r0, (r11)+		; 0D0C
	movw	@#UB+^x80E, r0
	movzwl	r0, (r11)+		; 0F0E
	movl	#^x80000000, @#DPR+12	; purge: the buffer empty
	movl	@#DPR+12, (r11)+	; 0
	movw	@#UB+^x800, r0
	movzwl	r0, (r11)+		; AAAA: from memory
	movl	#^x80000000, @#DPR+12
	movw	@#UB+^x804, r0
	movzwl	r0, (r11)+		; BBBB: the longword
	movl	@#DPR+12, (r11)+	; 80000000
	movw	@#UB+^x806, r0
	movzwl	r0, (r11)+		; 6666
	movl	@#UASR, (r11)+		; 0
; the prefetch into map 5, invalid: nothing recorded
	movl	#^x80000000, @#DPR+12
	movl	#^x11223344, @#MEMD+^x1FC
	movw	@#UB+^x9FE, r0
	movzwl	r0, (r11)+		; 1122
	movl	@#UASR, (r11)+		; 0
	movl	@#DPR+12, (r11)+	; 0: the buffer stays empty
	movl	#^x80600104, @#MAP+20	; map 5 valid, BDP 3
	movl	#^x77665544, @#MEME
	movw	@#UB+^x9FE, r0
	movzwl	r0, (r11)+		; 1122, prefetched from MEME
	movl	@#DPR+12, (r11)+	; 80000000
	clrl	@#MEME
	movw	@#UB+^xA00, r0
	movzwl	r0, (r11)+		; 5544: the prefetched data

; ---------------------------------------- reads with byte offset
	movl	#UB+^xC00, r2
	movl	#8, r3
f01:	movw	(r2)+, r0
	movzwl	r0, (r11)+		; 0201 0403 0605 0807 0A09 0C0B 0E0D 100F
	sobgtr	r3, f01
	movl	#^x80000000, @#DPR+16	; purge
	movw	@#UB+^xC06, r0
	movzwl	r0, (r11)+		; 0807: word 3 empty, two reads
	movw	@#UB+^xC08, r0
	movzwl	r0, (r11)+		; 0A09
	movl	#^x80000000, @#DPR+16
	movw	@#UB+^xC04, r0
	movzwl	r0, (r11)+		; 0605: word 2 empty, the longword
	movw	@#UB+^xC06, r0
	movzwl	r0, (r11)+		; 0807
	movl	@#UASR, (r11)+		; 0

; ----------------------------------------------- longword access mode
	movl	#^x44332211, @#MEMG
	movw	@#UB+^xE00, r0
	movzwl	r0, (r11)+		; 2211: the longword read
	movl	#^x88776655, @#MEMG
	movw	@#UB+^xE02, r0
	movzwl	r0, (r11)+		; 4433: the buffer
	movw	@#UB+^xE00, r0
	movzwl	r0, (r11)+		; 6655: read again
	movw	@#UB+^xE02, r0
	movzwl	r0, (r11)+		; 8877
	movw	#^x1234, @#UB+^xE08
	jsb	fence
	movl	@#MEMG+8, (r11)+	; 0: not yet
	movw	#^x5678, @#UB+^xE0A	; the high word: the longword goes
	jsb	fence
	movl	@#MEMG+8, (r11)+	; 56781234
	movl	@#DPR+20, (r11)+	; 20000382
	movb	#^x9A, @#UB+^xE0C
	movb	#^xBC, @#UB+^xE0F	; byte 3
	jsb	fence
	movl	@#MEMG+12, (r11)+	; BC00009A
	movl	@#UASR, (r11)+		; 0
	movl	r9, (r11)+		; nothing unexpected
	halt

; wait for a Unibus write to be over: a Unibus read is busy until then
fence:	movw	@#UB, r0
	rsb

; 24 bytes 00 01 02 ... at R0
pat:	clrl	r1
pat1:	movb	r1, (r0)+
	incl	r1
	cmpl	r1, #24
	blss	pat1
	rsb

	.align	4
unexp:	movl	#^xBAD, r9
	halt
