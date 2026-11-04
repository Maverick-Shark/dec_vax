; t50_dma - SBIA 0's DMA side and the MBox's byte masks, mapping off
; (EK-DB86X-TD-002 3.7, 3.14; EK-8600S-MM-004 M-03, appendix A):
;
;   - CPU reads of I/O space are a word or a longword (ABus length even word
;     01, odd word 10, longword 11), writes carry their byte mask: seen in
;     ERRSUM<27:26>, with a register read, address errors and an SBI timeout;
;   - quadclear (2008 004C): the adapter's own DMA side takes the command and
;     clears the quadword in memory; the transaction buffers A, B, C in turn
;     record each command in their command/address and ID registers;
;   - quadclear nobody takes: beyond the memory separator, with CSR<29> (SBI
;     cycles in) clear, with every buffer forced busy (DCR<19:17>: busy, SBIER
;     timeout status 01) - an SBI timeout and a machine check;
;   - a DMA the MBox aborts (the PAMM says the megabyte is not memory): the
;     buffer's "MBox detected error" bit in ERRSUM, which locks its registers
;     and requests the adapter error interrupt, IPL 1C, SCB 60;
;   - CPU references to SBI memory space (a megabyte mapped to SBIA 0): the
;     adapter's DMA side takes them, and the MBox aborts the DMA, since that
;     megabyte goes to the adapter: a read comes back marked bad (machine
;     check, MSTAT2<14> ABus bad data), a write completes.
;
; Machine checks log the byte count, EBCS, MSTAT1, MSTAT2, MEAR and PC - R7
; (the instruction expected to fail), then EHSR is cleared and the program
; goes on at R8.
;@ noref
;@ rtl=18000:00001800,18004:00000018,18008:00000058,1800C:0020C002,18010:B8000000,18014:00180004
;@ rtl=18018:20080050,1801C:00000000,18020:18980000,18024:08020014,18028:00000058,1802C:0020C002
;@ rtl=18030:B8000000,18034:00180004,18038:20080050,1803C:00000000,18040:14980000,18044:00000058
;@ rtl=18048:0020C004,1804C:B4000000,18050:00180004,18054:20080054,18058:00000000,1805C:D8980000
;@ rtl=18060:00000058,18064:0020C004,18068:B4000000,1806C:00180004,18070:20080054,18074:00000000
;@ rtl=18078:D4980000,1807C:00000058,18080:0020C002,18084:B8000000,18088:00180004,1808C:2000A000
;@ rtl=18090:00000000,18094:18800000,18098:00001000,1809C:00000000,180A0:00000000,180A4:33333333
;@ rtl=180A8:B0040000,180AC:00000010,180B0:1C000000,180B4:B0040004,180B8:B0040008,180BC:B004000C
;@ rtl=180C0:00000058,180C4:0020C004,180C8:B4000000,180CC:00180004,180D0:2008004C,180D4:00000000
;@ rtl=180D8:00001000,180DC:08020013,180E0:DC800000,180E4:00000058,180E8:0020C004,180EC:B4000000
;@ rtl=180F0:00180004,180F4:2008004C,180F8:00000000,180FC:00001000,18100:00000058,18104:0020C004
;@ rtl=18108:B4000000,1810C:00180004,18110:2008004C,18114:00000000,18118:00001400,1811C:1C000100
;@ rtl=18120:B0400000,18124:00000010,18128:B0400000,1812C:B0040010,18130:B0040014,18134:00000000
;@ rtl=18138:00000060,1813C:041C0000,18140:041B0000,18144:1C000100,18148:000000A1,1814C:1C000000
;@ rtl=18150:00000058,18154:0020C002,18158:B8000000,1815C:00184000,18160:01000000,18164:00000000
;@ rtl=18168:1C001000,1816C:10400000,18170:1C000010,18174:20400001,18178:1C000000,1817C:00000000
LOG	= ^x18000
SCBB	= ^x11
IPL	= ^x12
PAMACC	= ^x40
PAMLOC	= ^x41
EHSR	= ^x4A
SBIA	= ^x20080000
CSR	= SBIA+^x04
ERRSUM	= SBIA+^x08
DCR	= SBIA+^x0C
SBIER	= SBIA+^x34
TOADR	= SBIA+^x38
QCLR	= SBIA+^x4C
LOCK	= ^x00800000
TMO	= ^x1000
BUF	= ^x00100000		; memory the quadclears work on

	.org	^x1000
start:	movl	#^xE000, sp		; interrupt stack (PSL<IS> is set)
	clrl	r0
	movab	unexp+1, r1
scbfill:
	movl	r1, (r0)+
	cmpl	r0, #^x200
	blss	scbfill
	movab	mchk_h+1, @#^x04
	movab	h060+1, @#^x60		; SBIA error
	mtpr	#0, #SCBB
	movl	#LOG, r11
	clrl	r9

; ---------------------------------------------- read lengths and masks
	movzwl	@#ERRSUM+2, (r11)+	; odd word read: 1800 (0001, 10)
	movzbl	@#ERRSUM+3, (r11)+	; a byte of the odd word: 18
	movab	f01, r7
	movab	n01, r8
	tstl	r8
f01:	movw	@#SBIA+^x52, r0		; odd word, no such register
	movl	#^x600D, (r11)+
n01:	movl	@#ERRSUM, (r11)+	; 18980000
	movl	@#TOADR, (r11)+		; 08020014
	movl	#LOCK, @#ERRSUM
	movab	f02, r7
	movab	n02, r8
	tstl	r8
f02:	movb	@#SBIA+^x50, r0		; even word
	movl	#^x600D, (r11)+
n02:	movl	@#ERRSUM, (r11)+	; 14980000
	movl	#LOCK, @#ERRSUM
	movab	f03, r7
	movab	n03, r8
	tstl	r8
f03:	movb	#1, @#SBIA+^x56		; a byte write, in the odd word
	movl	#^x600D, (r11)+
n03:	movl	@#ERRSUM, (r11)+	; D8980000
	movl	#LOCK, @#ERRSUM
	movab	f04, r7
	movab	n04, r8
	tstl	r8
f04:	movw	#1, @#SBIA+^x54		; a word write, the even word
	movl	#^x600D, (r11)+
n04:	movl	@#ERRSUM, (r11)+	; D4980000
	movl	#LOCK, @#ERRSUM
	movab	f05, r7
	movab	n05, r8
	tstl	r8
f05:	movw	@#^x2000A002, r0	; TR 5: an SBI timeout, odd word
	movl	#^x600D, (r11)+
n05:	movl	@#ERRSUM, (r11)+	; 18800000
	movl	@#SBIER, (r11)+		; 00001000
	movl	#TMO, @#SBIER
	movl	#LOCK, @#ERRSUM

; --------------------------------------------------------------- quadclear
	movl	#^x11111111, @#BUF
	movl	#^x22222222, @#BUF+4
	movl	#^x33333333, @#BUF+8
	movl	#^xB0040000, @#QCLR	; extended write masked, BUF
	movl	@#BUF, (r11)+		; 0
	movl	@#BUF+4, (r11)+		; 0
	movl	@#BUF+8, (r11)+		; 33333333
	movl	@#SBIA+^x18, (r11)+	; buffer A: B0040000
	movl	@#SBIA+^x1C, (r11)+	; ID 10, the CPU
	movl	@#ERRSUM, (r11)+	; 1C000000
	movl	#^xB0040004, @#QCLR	; buffer B
	movl	#^xB0040008, @#QCLR	; buffer C
	movl	#^xB004000C, @#QCLR	; A again
	movl	@#SBIA+^x20, (r11)+	; B0040004
	movl	@#SBIA+^x28, (r11)+	; B0040008
	movl	@#SBIA+^x18, (r11)+	; B004000C
; nobody takes it beyond the memory separator (32 MB)
	movab	f06, r7
	movab	n06, r8
	tstl	r8
f06:	movl	#^xB0800000, @#QCLR
	movl	#^x600D, (r11)+
n06:	movl	@#SBIER, (r11)+		; 00001000
	movl	@#TOADR, (r11)+		; 08020013: the CPU's write
	movl	@#ERRSUM, (r11)+	; DC800000
	movl	#TMO, @#SBIER
	movl	#LOCK, @#ERRSUM
; nor with SBI cycles in disabled
	movl	#^xC0000000, @#CSR
	movab	f07, r7
	movab	n07, r8
	tstl	r8
f07:	movl	#^xB0040000, @#QCLR
	movl	#^x600D, (r11)+
n07:	movl	#^xE0000000, @#CSR
	movl	@#SBIER, (r11)+		; 00001000
	movl	#TMO, @#SBIER
	movl	#LOCK, @#ERRSUM
; every buffer forced busy: the adapter answers busy until the timeout
	movl	#^x000E0000, @#DCR	; A, B, C busy
	movab	f08, r7
	movab	n08, r8
	tstl	r8
f08:	movl	#^xB0040000, @#QCLR
	movl	#^x600D, (r11)+
n08:	clrl	@#DCR
	movl	@#SBIER, (r11)+		; 00001400: timeout, busy
	movl	#TMO, @#SBIER
	movl	#LOCK, @#ERRSUM

; ------------------------------------------------- a DMA the MBox aborts
	mtpr	#^x01000000, #PAMLOC	; megabyte 10 (1000000): nothing
	mtpr	#^x1F, #PAMACC
	movl	#^xB0400000, @#QCLR	; buffer B; the CPU's write completes
	movl	@#ERRSUM, (r11)+	; 1C000100: B, MBox detected error
	movl	@#SBIA+^x20, (r11)+	; B0400000
	movl	@#SBIA+^x24, (r11)+	; 10
	movl	#^x44444444, @#BUF+^x60
	movl	#^xB0040010, @#QCLR	; C
	movl	#^xB0040014, @#QCLR	; A
	movl	#^xB0040018, @#QCLR	; B: its registers stay
	movl	@#SBIA+^x20, (r11)+	; B0400000
	movl	@#SBIA+^x28, (r11)+	; B0040010
	movl	@#SBIA+^x18, (r11)+	; B0040014
	movl	@#BUF+^x60, (r11)+	; 0: cleared all the same
; the adapter error interrupt
	mtpr	#^x1B, #IPL		; SCB 60 at IPL 1C
	movl	#^xA1, (r11)+
	mtpr	#^x1F, #IPL
	movl	@#ERRSUM, (r11)+	; 1C000000

; ---------------------------------------------------- SBI memory space
	mtpr	#^x18, #PAMACC		; megabyte 10 to SBIA 0
	movab	f09, r7
	movab	n09, r8
	tstl	r8
f09:	movl	@#^x01000000, r0	; buffer C; the DMA is aborted
	movl	#^x600D, (r11)+
n09:	movl	@#ERRSUM, (r11)+	; 1C001000: C, not locked
	movl	@#SBIA+^x28, (r11)+	; 10400000: read masked
	movl	#^x1000, @#ERRSUM
	movl	#^x55, @#^x01000004	; A; the write completes
	movl	@#ERRSUM, (r11)+	; 1C000010
	movl	@#SBIA+^x18, (r11)+	; 20400001: write masked
	movl	#^x10, @#ERRSUM
	mtpr	#4, #PAMACC		; megabyte 10 back to array 4
	movl	@#ERRSUM, (r11)+	; 1C000000
	movl	r9, (r11)+		; nothing unexpected
	halt

; machine check: byte count, EBCS, MSTAT1, MSTAT2, MEAR, PC - R7
	.align	4
mchk_h:	movl	(sp)+, r3
	movl	r3, (r11)+
	movl	8(sp), (r11)+		; EBCS
	movl	52(sp), (r11)+		; MSTAT1
	movl	56(sp), (r11)+		; MSTAT2
	movl	72(sp), (r11)+		; MEAR
	addl2	r3, sp
	subl3	r7, (sp), (r11)+	; PC - instruction
	mtpr	#0, #EHSR
	movl	r8, (sp)
	rei

; the adapter error: log, clear the error, return
	.align	4
h060:	movl	#^x60, (r11)+
	movpsl	r2
	bicl3	#^xF, r2, (r11)+
	bicl3	#^xF, 4(sp), (r11)+
	movl	@#ERRSUM, (r11)+	; 1C000100
	movl	#^x100, @#ERRSUM	; write 1 to clear
	rei

	.align	4
unexp:	movl	#^xBAD, r9
	halt
