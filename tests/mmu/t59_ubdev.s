; t59_ubdev - the DW780's device side, with the bench's Unibus test device
; (sim/cpu_tb/ubdev.v, registers at 777400; EK-DW780-TD-001 2.3, 2.6, 2.7,
; 2.9, 3.3):
;
;   - device registers through the adapter: DATI of a word (the low or the
;     high word of the SBI longword) or a byte, DATO, DATOB of either byte;
;   - Unibus interrupts: IFS clear - a BRRVR reads zero, nothing on the SBI;
;     IFS without BRIE - polled, the BRRVR read fetches the vector (bus
;     grant, INTR) and the device's request goes with the grant; DINTR - the
;     adapter does not see the request; IFS and BRIE - the SBI request, the
;     interrupt at IPL 15 through SCB 14C (100 + 40 * (level - 4) + 4 * TR),
;     the vector from the BRRVR; a passive release before the BRRVR read
;     reads zero; BR4 with the adapter's own request - one interrupt through
;     SCB 10C, the BRRVR negative; BR6 and BR7, SCB 18C and 1CC;
;   - the device as DMA master: DATO, DATI, DATOB and DATIP-DATO through the
;     direct data path (SBI write masked, read masked, interlock read and
;     write masked); through a buffered data path the quadword written on
;     its last byte, the word left purged, DATI from the buffer with the
;     prefetch, no DATIP (no slave sync); an invalid map register (IVMR,
;     FMER, no slave sync: the device's NXM); the I/O page (no slave sync,
;     nothing recorded); a device holding the bus for a long burst: the
;     adapter's own Unibus read ends in a Unibus select timeout; the
;     device's interrupt at the end of its DMA;
;   - adapter init: INIT on the Unibus clears the device.
;
; The device (bench only): CSR 777400 <15> GO, <14> NXM, <13:12> function
; (00 DATI, 01 DATIP-DATO of the word plus 1, 10 DATO, 11 DATOB), <7:6>
; level (BR4 + n), <5> request, <4> interrupt at the end, <0> DONE; VEC
; 777402; BA 777404, BAE 777406 (the DMA address); WC 777410; DAT 777412
; (DATI: the sum read; else the first word written, then plus 1 each);
; LAST 777414 (the last word read).
;
; Expected values: tests/mmu/gen/mk_t59.py.
;@ noref
;@ rtl=18000:00000000,18004:00000154,18008:00003412,1800C:00000034,18010:00000003,18014:00003000
;@ rtl=18018:00000000,1801C:00000000,18020:00000060,18024:000000A1,18028:000000A2,1802C:00000000
;@ rtl=18030:00000154,18034:00000040,18038:00000000,1803C:00000060,18040:000000A3,18044:00000000
;@ rtl=18048:00000060,1804C:48010028,18050:000000A4,18054:0000014C,18058:04150000,1805C:00000154
;@ rtl=18060:000000A5,18064:00000040,18068:0000014C,1806C:04150000,18070:00000000,18074:000000A6
;@ rtl=18078:0000010C,1807C:04140000,18080:800000F0,18084:00000001,18088:00000000,1808C:000000A7
;@ rtl=18090:00000000,18094:0000018C,18098:04160000,1809C:000001C8,180A0:000000A8,180A4:000001CC
;@ rtl=180A8:04170000,180AC:000001C8,180B0:000000A9,180B4:00002001,180B8:11121111,180BC:11141113
;@ rtl=180C0:EEEEEEEE,180C4:00000008,180C8:00000000,180CC:00000001,180D0:0000444A,180D4:00001114
;@ rtl=180D8:434241EE,180DC:EEEEEEEE,180E0:00001001,180E4:11131112,180E8:00001112,180EC:00000000
;@ rtl=180F0:20012000,180F4:20032002,180F8:EEEEEEEE,180FC:A0030082,18100:00000082,18104:EEEE2004
;@ rtl=18108:0000A00A,1810C:00002004,18110:80000082,18114:00000082,18118:00005001,1811C:00000000
;@ rtl=18120:00000082,18124:00006001,18128:00000010,1812C:00000002,18130:00004001,18134:00000000
;@ rtl=18138:FFFF0000,1813C:00000002,18140:0000FFC0,18144:00002001,18148:30013000,1814C:00000000
;@ rtl=18150:0000014C,18154:04150000,18158:00000154,1815C:00000051,18160:00000000,18164:00000000
;@ board=skip
;@ clocks=6000000
LOG	= ^x18000
SCBB	= ^x11
IPL	= ^x12
UBA	= ^x20006000
CNFGR	= UBA
UACR	= UBA+^x04
UASR	= UBA+^x08
DCR	= UBA+^x0C
FMER	= UBA+^x10
FUBAR	= UBA+^x14
BRRVR	= UBA+^x30
DPR	= UBA+^x40
MAP	= UBA+^x800
UB	= ^x20100000		; Unibus 0
IOP	= UB+^x3E000		; the I/O page, 760000
CSR	= UB+^x3FF00		; the test device, 777400
VEC	= CSR+2
BA	= CSR+4
BAE	= CSR+6
WC	= CSR+8
DAT	= CSR+^xA
LAST	= CSR+^xC
MEMA	= ^x20000		; map 0: the direct data path
MEMB	= ^x20200		; map 1: BDP 1

	.org	^x1000
start:	movl	#^xE000, sp		; interrupt stack (PSL<IS> is set)
	clrl	r0
	movab	unexp+1, r1
scbfill:
	movl	r1, (r0)+
	cmpl	r0, #^x200
	blss	scbfill
	movab	h10c+1, @#^x10C		; TR 3 at IPL 14: BR4, the adapter
	movab	h14c+1, @#^x14C		; IPL 15: BR5
	movab	h18c+1, @#^x18C		; IPL 16: BR6
	movab	h1cc+1, @#^x1CC		; IPL 17: BR7
	mtpr	#0, #SCBB
	movl	#LOG, r11
	clrl	r9
	clrl	r6
	clrl	r5
	movl	#MEMA, r0
fill:	movl	#^xEEEEEEEE, (r0)+
	cmpl	r0, #MEMA+^x400
	blss	fill
	movl	#^x80000100, @#MAP	; map 0: valid, DDP, MEMA
	movl	#^x80200101, @#MAP+4	; map 1: valid, BDP 1, MEMB

; ------------------------------------------- the device's registers
	movzwl	@#CSR, (r11)+		; 0: cleared by the processor's INIT
	movw	#^x0154, @#VEC		; DATO
	movzwl	@#VEC, (r11)+		; 00000154: DATI, the longword's high word
	movb	#^x12, @#BA		; DATOB, the low byte
	movb	#^x34, @#BA+1		; DATOB, the high byte
	movzwl	@#BA, (r11)+		; 00003412
	movzbl	@#BA+1, (r11)+		; 00000034: the high byte of the DATI
	movw	#^x5557, @#BAE
	movzwl	@#BAE, (r11)+		; 00000003: BAE<1:0>
	movb	#^x30, @#CSR+1		; DATOB of CSR<15:8>: function 11
	movzwl	@#CSR, (r11)+		; 00003000
	clrw	@#CSR
	clrw	@#BAE
	movl	@#UASR, (r11)+		; 0

; ------------------------------------------ Unibus interrupts (TD 2.7)
; IFS clear: the BRRVR reads zero (TD 2.9.8, case 5), no SBI request
	movw	#^x0060, @#CSR		; BR5
	movl	@#BRRVR+4, (r11)+	; 0
	movzwl	@#CSR, (r11)+		; 00000060: still requesting
	mtpr	#^x13, #IPL
	movl	#^xA1, (r11)+		; no interrupt
	mtpr	#^x1F, #IPL
; IFS without BRIE: polled
	movl	#^x40, @#UACR
	mtpr	#^x13, #IPL
	movl	#^xA2, (r11)+		; no interrupt
	mtpr	#^x1F, #IPL
	movl	@#BRRVR, (r11)+		; 0: nothing on BR4
	movl	@#BRRVR+4, (r11)+	; 00000154: the vector, through BG5
	movzwl	@#CSR, (r11)+		; 00000040: the request went with the grant
	movl	@#BRRVR+4, (r11)+	; 0
; DINTR: the adapter does not see the Unibus's requests
	movl	#^x40000000, @#DCR
	movl	#^x60, @#UACR		; IFS, BRIE
	movw	#^x0060, @#CSR		; BR5
	movzwl	@#CSR, (r11)+		; 00000060
	mtpr	#^x13, #IPL
	movl	#^xA3, (r11)+		; no interrupt
	mtpr	#^x1F, #IPL
	movl	@#BRRVR+4, (r11)+	; 0: as a passive release
	movzwl	@#CSR, (r11)+		; 00000060
	movl	@#DCR, (r11)+		; 48010028
; IFS and BRIE: the interrupt, IPL 15, SCB 14C
	clrl	@#DCR
	mtpr	#^x15, #IPL
	movl	#^xA4, (r11)+		; not at IPL 15
	mtpr	#^x14, #IPL		; taken
	movl	#^xA5, (r11)+
	mtpr	#^x1F, #IPL
	movzwl	@#CSR, (r11)+		; 00000040
; a passive release: the request taken back before the BRRVR read (TD
; 2.9.8, case 3)
	movl	#1, r6
	movw	#^x0060, @#CSR		; BR5
	movzwl	@#CSR, r0
	mtpr	#^x14, #IPL		; taken: the handler takes it back
	movl	#^xA6, (r11)+
	mtpr	#^x1F, #IPL
	clrl	r6
; BR4 and the adapter's own request: one interrupt through SCB 10C
	movw	#^xF0, @#VEC
	movw	#^x0020, @#CSR		; BR4
	movl	#^x68, @#UACR		; IFS, BRIE, SUEFIE
	movw	@#IOP, r0		; UBSSYNTO: the adapter's request, BR4
	mtpr	#^x13, #IPL		; taken
	movl	#^xA7, (r11)+
	mtpr	#^x1F, #IPL
	movl	#^x60, @#UACR
; BR6: SCB 18C, IPL 16; BR7: SCB 1CC, IPL 17
	movw	#^x01C8, @#VEC
	movw	#^x00A0, @#CSR		; BR6
	movl	@#BRRVR+12, (r11)+	; 0: nothing on BR7
	movzwl	@#CSR, r0
	mtpr	#^x13, #IPL		; taken
	movl	#^xA8, (r11)+
	mtpr	#^x1F, #IPL
	movw	#^x00E0, @#CSR		; BR7
	movzwl	@#CSR, r0
	mtpr	#^x16, #IPL		; above BR6: taken
	movl	#^xA9, (r11)+
	mtpr	#^x1F, #IPL

; ------------------------------------ the device as DMA master (TD 2.6)
; the direct data path (TD table 2-9)
	clrw	@#BA
	movw	#4, @#WC
	movw	#^x1111, @#DAT
	movw	#^xA000, @#CSR		; GO: DATO, 4 words from 0
	jsb	done
	movzwl	@#CSR, (r11)+		; 00002001: DONE
	movl	@#MEMA, (r11)+		; 11121111
	movl	@#MEMA+4, (r11)+	; 11141113
	movl	@#MEMA+8, (r11)+	; EEEEEEEE
	movzwl	@#BA, (r11)+		; 00000008
	movzwl	@#WC, (r11)+		; 0
	clrw	@#BA
	movw	#4, @#WC
	clrw	@#DAT
	movw	#^x8000, @#CSR		; GO: DATI, 4 words
	jsb	done
	movzwl	@#CSR, (r11)+		; 00000001
	movzwl	@#DAT, (r11)+		; 0000444A: the sum
	movzwl	@#LAST, (r11)+		; 00001114
	movw	#9, @#BA
	movw	#3, @#WC
	movw	#^x41, @#DAT
	movw	#^xB000, @#CSR		; GO: DATOB, 3 bytes from 11
	jsb	done
	movl	@#MEMA+8, (r11)+	; 434241EE
	movl	@#MEMA+12, (r11)+	; EEEEEEEE
	clrw	@#BA
	movw	#2, @#WC
	movw	#^x9000, @#CSR		; GO: DATIP-DATO, 2 words
	jsb	done
	movzwl	@#CSR, (r11)+		; 00001001
	movl	@#MEMA, (r11)+		; 11131112: each word plus 1
	movzwl	@#LAST, (r11)+		; 00001112
	movl	@#UASR, (r11)+		; 0
; a buffered data path (TD 2.6.2.2, 3.3.1.3, 3.3.1.4)
	movw	#^x200, @#BA
	movw	#5, @#WC
	movw	#^x2000, @#DAT
	movw	#^xA000, @#CSR		; GO: DATO, 5 words from 1000 (map 1)
	jsb	done
	movl	@#MEMB, (r11)+		; 20012000: the quadword, on its last byte
	movl	@#MEMB+4, (r11)+	; 20032002
	movl	@#MEMB+8, (r11)+	; EEEEEEEE: word 4 still in the buffer
	movl	@#DPR+4, (r11)+		; A0030082
	movl	#^x80000000, @#DPR+4	; purge
	movl	@#DPR+4, (r11)+		; 00000082
	movl	@#MEMB+8, (r11)+	; EEEE2004
	movw	#^x200, @#BA
	movw	#5, @#WC
	clrw	@#DAT
	movw	#^x8000, @#CSR		; GO: DATI, 5 words
	jsb	done
	movzwl	@#DAT, (r11)+		; 0000A00A
	movzwl	@#LAST, (r11)+		; 00002004
	movl	@#DPR+4, (r11)+		; 80000082: the prefetched quadword
	movl	#^x80000000, @#DPR+4	; purge: empty
	movl	@#DPR+4, (r11)+		; 00000082
	movw	#^x200, @#BA
	movw	#1, @#WC
	movw	#^x9000, @#CSR		; GO: DATIP through BDP 1
	jsb	done
	movzwl	@#CSR, (r11)+		; 00005001: NXM
	movl	@#UASR, (r11)+		; 0: nothing recorded
	movl	@#DPR+4, (r11)+		; 00000082
; no slave sync: an invalid map register, the I/O page
	movw	#^x400, @#BA
	movw	#1, @#WC
	movw	#^xA000, @#CSR		; GO: DATO to 2000, map 2 not valid
	jsb	done
	movzwl	@#CSR, (r11)+		; 00006001: NXM
	movl	@#UASR, (r11)+		; 00000010: IVMR
	movl	@#FMER, (r11)+		; 00000002
	movl	#^x10, @#UASR
	movw	#^xE000, @#BA
	movw	#3, @#BAE		; 760000
	movw	#1, @#WC
	movw	#^x8000, @#CSR		; GO: DATI in the I/O page
	jsb	done
	movzwl	@#CSR, (r11)+		; 00004001: NXM
	movl	@#UASR, (r11)+		; 0: not the adapter's
	clrw	@#BAE
; a device holding the bus: the adapter cannot get it (TD 2.9.3)
	movw	#^x100, @#BA
	movw	#128, @#WC
	movw	#^x3000, @#DAT
	movw	#^xA000, @#CSR		; GO: DATO, 128 words in one burst
	movl	#50, r1
dly1:	sobgtr	r1, dly1		; the device has the bus now
	movl	#-1, r0
	movw	@#VEC, r0
	movl	r0, (r11)+		; FFFF0000: zeros
	movl	@#UASR, (r11)+		; 00000002: UBSTO
	movl	@#FUBAR, (r11)+		; 0000FFC0: 777402
	movl	#2, @#UASR
	movl	#100000, r1
w10:	cmpl	@#MEMA+^x1FC, #^x307F307E	; the burst's last word
	beql	w10b
	sobgtr	r1, w10
	movl	#^xD10, r9
w10b:	movzwl	@#CSR, (r11)+		; 00002001
	movl	@#MEMA+^x100, (r11)+	; 30013000
	movl	@#UASR, (r11)+		; 0
; the interrupt at the end of the DMA: BR5, SCB 14C
	movw	#^x0154, @#VEC
	clrw	@#BA
	movw	#1, @#WC
	clrl	r5
	movw	#^x8050, @#CSR		; GO: DATI, BR5, interrupt at the end
	mtpr	#^x13, #IPL
	movl	#100000, r1
w11:	tstl	r5
	bneq	w11b
	sobgtr	r1, w11
	movl	#^xD11, r9
w11b:	mtpr	#^x1F, #IPL
	movzwl	@#CSR, (r11)+		; 00000051: DONE, the request gone

; ------------------------- adapter init: INIT clears the device (TD 2.9.2)
	movw	#^x1234, @#VEC
	movl	#1, @#UACR
	jsb	ubic
	movzwl	@#VEC, (r11)+		; 0
	movl	r9, (r11)+		; nothing unexpected
	halt

; wait for the device's DONE
done:	movl	#20000, r1
done1:	bitw	#1, @#CSR
	bneq	done2
	sobgtr	r1, done1
	movl	#^xD0, r9
done2:	rsb

; wait for the Unibus initialization complete (CNFGR<16>), 40 ms at most
ubic:	movl	#200000, r1
ubic1:	bitl	#^x10000, @#CNFGR
	bneq	ubic2
	sobgtr	r1, ubic1
	movl	#^xDEAD, r9
ubic2:	rsb

; BR4 (and the adapter): log, the BRRVR, the adapter's status cleared
	.align	4
h10c:	movl	#^x10C, (r11)+
	movpsl	r2
	bicl3	#^xF, r2, (r11)+	; 04140000: IPL 14
	movl	@#BRRVR, (r11)+		; 800000F0: the adapter too
	movl	@#UASR, (r11)+		; 00000001
	movl	#1, @#UASR
	movl	@#BRRVR, (r11)+		; 0
	rei

; BR5: with R6<0> the device takes its request back first
	.align	4
h14c:	movl	#^x14C, (r11)+
	movpsl	r2
	bicl3	#^xF, r2, (r11)+	; 04150000: IPL 15
	blbc	r6, h14c1
	movw	#^x0040, @#CSR
h14c1:	movl	@#BRRVR+4, (r11)+	; the vector (0: a passive release)
	incl	r5
	rei

	.align	4
h18c:	movl	#^x18C, (r11)+
	movpsl	r2
	bicl3	#^xF, r2, (r11)+	; 04160000: IPL 16
	movl	@#BRRVR+8, (r11)+	; 000001C8
	rei

	.align	4
h1cc:	movl	#^x1CC, (r11)+
	movpsl	r2
	bicl3	#^xF, r2, (r11)+	; 04170000: IPL 17
	movl	@#BRRVR+12, (r11)+	; 000001C8
	rei

	.align	4
unexp:	movl	#^xBAD, r9
	halt
