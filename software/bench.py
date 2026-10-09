#!/usr/bin/env python3
"""
bench.py - builds bench.bin, a fixed-work loop that measures the core's speed
and prints the result on the console. Load at 0x00001000 with autostart.

The loop body is four instructions: one register add, one longword store, one
longword load and the loop control, N times. The VAX interval clock (ICR,
microseconds) is started just before the loop and read just after it, so the
program can print how long it took, the speed in MIPS and the average number
of 50 MHz clocks per instruction. It also checks that the last value stored
to memory reads back correctly. Then it HALTs, back to the console monitor.

  BENCH: 1000000 x (ADDL2, MOVL store, MOVL load, SOBGTR)
  elapsed: 3329874 us
  speed: 1.201 MIPS = 41.6 clocks per instruction
  data check: OK

Usage:  python3 software/bench.py software/bench.bin [N]
        (N = 1000000 by default, about 3 seconds on the core; the simulation
        uses a small N)
"""
import struct
import sys

BASE = 0x1000


def L4(v):
    return struct.pack('<i', v) if v < 0 else struct.pack('<I', v)


class Asm:
    """Tiny two-pass helper: raw bytes, labels, PC-relative longword
    operands (mode EF) and byte branch displacements."""

    def __init__(self):
        self.items, self.labels = [], {}

    def lab(self, n): self.items.append(('lab', n))
    def b(self, *bs): self.items.append(('raw', bytes(bs)))
    def raw(self, bs): self.items.append(('raw', bs))
    def rel32(self, lbl): self.items.append(('rel32', lbl))
    def br8(self, lbl): self.items.append(('br8', lbl))

    @staticmethod
    def size(it):
        return {'lab': 0, 'rel32': 5, 'br8': 1}.get(it[0], len(it[1]) if it[0] == 'raw' else 0)

    def build(self):
        pc = BASE
        for it in self.items:
            if it[0] == 'lab':
                self.labels[it[1]] = pc
            else:
                pc += self.size(it)
        out, pc = bytearray(), BASE
        for it in self.items:
            if it[0] == 'lab':
                continue
            if it[0] == 'raw':
                out += it[1]
                pc += len(it[1])
            elif it[0] == 'rel32':
                d = self.labels[it[1]] - (pc + 5)
                out += bytes([0xEF]) + L4(d)
                pc += 5
            elif it[0] == 'br8':
                d = self.labels[it[1]] - (pc + 1)
                assert -128 <= d <= 127, it
                out += struct.pack('<b', d)
                pc += 1
        return bytes(out)


def build(n):
    instr = 4 * n + 3        # CLRL, MOVL, 4 per pass, MFPR: ICR start to read
    imm = lambda v: bytes([0x8F]) + L4(v)
    a = Asm()
    a.lab('start')
    a.b(0xD0); a.raw(imm(0x800)); a.b(0x5E)               # MOVL  #^X800, SP
    a.b(0x9E); a.rel32('hdr'); a.b(0x51)                  # MOVAB hdr, R1
    a.b(0xFB, 0x00); a.rel32('puts')                      # CALLS #0, puts
    a.b(0xDD); a.raw(imm(n))                              # PUSHL #N
    a.b(0xFB, 0x01); a.rel32('putnum')                    # CALLS #1, putnum
    a.b(0x9E); a.rel32('hdr2'); a.b(0x51)                 # MOVAB hdr2, R1
    a.b(0xFB, 0x00); a.rel32('puts')                      # CALLS #0, puts
    # interval clock: NICR = 0, ICCS = XFR | RUN (ICR <- 0, count microseconds)
    a.b(0xDA, 0x00, 0x19)                                 # MTPR  #0, #NICR
    a.b(0xDA, 0x11, 0x18)                                 # MTPR  #^X11, #ICCS
    a.b(0xD4, 0x52)                                       # CLRL  R2
    a.b(0xD0); a.raw(imm(n)); a.b(0x53)                   # MOVL  #N, R3
    a.lab('loop')
    a.b(0xC0, 0x01, 0x52)                                 # ADDL2 #1, R2
    a.b(0xD0, 0x52); a.rel32('cell')                      # MOVL  R2, cell
    a.b(0xD0); a.rel32('cell'); a.b(0x54)                 # MOVL  cell, R4
    a.b(0xF5, 0x53); a.br8('loop')                        # SOBGTR R3, loop
    a.b(0xDB, 0x1A, 0x56)                                 # MFPR  #ICR, R6  (elapsed us)
    a.b(0xDA, 0x00, 0x18)                                 # MTPR  #0, #ICCS (stop)
    a.b(0xD0, 0x54, 0x58)                                 # MOVL  R4, R8    (keep for check)
    # elapsed
    a.b(0x9E); a.rel32('m_el'); a.b(0x51)                 # MOVAB m_el, R1
    a.b(0xFB, 0x00); a.rel32('puts')
    a.b(0xDD, 0x56)                                       # PUSHL R6
    a.b(0xFB, 0x01); a.rel32('putnum')
    a.b(0x9E); a.rel32('m_us'); a.b(0x51)
    a.b(0xFB, 0x00); a.rel32('puts')
    # kIPS = instr * 1000 / us   (64-bit product)
    a.b(0x7A); a.raw(imm(1000)); a.raw(imm(instr)); a.b(0x00, 0x5A)   # EMUL #1000, #instr, #0, R10/R11
    a.b(0x7B, 0x56, 0x5A, 0x57, 0x59)                     # EDIV  R6, R10, R7, R9   R7 = kIPS
    a.b(0x9E); a.rel32('m_sp'); a.b(0x51)
    a.b(0xFB, 0x00); a.rel32('puts')
    a.b(0xC7); a.raw(imm(1000)); a.b(0x57, 0x52)          # DIVL3 #1000, R7, R2  (whole MIPS)
    a.b(0xDD, 0x52)
    a.b(0xFB, 0x01); a.rel32('putnum')
    a.b(0x9A, 0x2E, 0x50); a.b(0x16); a.rel32('putc')     # MOVZBL #'.', R0; JSB putc
    a.b(0xC5); a.raw(imm(1000)); a.b(0x52, 0x53)          # MULL3 #1000, R2, R3
    a.b(0xC3, 0x53, 0x57, 0x53)                           # SUBL3 R3, R7, R3     (fraction)
    a.b(0xDD, 0x53)
    a.b(0xFB, 0x01); a.rel32('put3')
    # CPI x 10 = us * 500 / instr
    a.b(0x7A); a.raw(imm(500)); a.b(0x56, 0x00, 0x5A)     # EMUL #500, R6, #0, R10/R11
    a.b(0x7B); a.raw(imm(instr)); a.b(0x5A, 0x57, 0x59)   # EDIV #instr, R10, R7, R9  R7 = CPI x 10
    a.b(0x9E); a.rel32('m_cpi'); a.b(0x51)
    a.b(0xFB, 0x00); a.rel32('puts')
    a.b(0xC7, 0x0A, 0x57, 0x52)                           # DIVL3 #10, R7, R2
    a.b(0xDD, 0x52)
    a.b(0xFB, 0x01); a.rel32('putnum')
    a.b(0x9A, 0x2E, 0x50); a.b(0x16); a.rel32('putc')     # MOVZBL #'.', R0; JSB putc
    a.b(0xC5, 0x0A, 0x52, 0x53)                           # MULL3 #10, R2, R3
    a.b(0xC3, 0x53, 0x57, 0x53)                           # SUBL3 R3, R7, R3
    a.b(0xC1, 0x30, 0x53, 0x50)                           # ADDL3 #^X30, R3, R0
    a.b(0x16); a.rel32('putc')
    a.b(0x9E); a.rel32('m_cpi2'); a.b(0x51)
    a.b(0xFB, 0x00); a.rel32('puts')
    # data check: the last value stored and loaded back must be N
    a.b(0x9E); a.rel32('m_ok'); a.b(0x51)                 # MOVAB m_ok, R1
    a.b(0xD1, 0x58); a.raw(imm(n))                        # CMPL  R8, #N
    a.b(0x13); a.br8('chk')                               # BEQL  chk
    a.b(0x9E); a.rel32('m_bad'); a.b(0x51)                # MOVAB m_bad, R1
    a.lab('chk')
    a.b(0xFB, 0x00); a.rel32('puts')
    a.b(0x00)                                             # HALT
    # puts: R1 -> zero-terminated string
    a.lab('puts'); a.raw(struct.pack('<H', 0x0004))       # entry mask: R2
    a.lab('p1')
    a.b(0x9A, 0x81, 0x50)                                 # MOVZBL (R1)+, R0
    a.b(0x13); a.br8('p9')                                # BEQL  p9
    a.b(0x16); a.rel32('putc')                            # JSB   putc
    a.b(0x11); a.br8('p1')                                # BRB   p1
    a.lab('p9'); a.b(0x04)                                # RET
    # putc: R0 = character; wait for TXCS<7>, write TXDB (uses R5)
    a.lab('putc')
    a.lab('pc1')
    a.b(0xDB, 0x22, 0x55)                                 # MFPR  #TXCS, R5
    a.b(0xE1, 0x07, 0x55); a.br8('pc1')                   # BBC   #7, R5, pc1
    a.b(0xDA, 0x50, 0x23)                                 # MTPR  R0, #TXDB
    a.b(0x05)                                             # RSB
    # putnum: print longword 4(AP) in decimal, no newline
    a.lab('putnum'); a.raw(struct.pack('<H', 0x003C))     # entry mask: R2-R5
    a.b(0xD0, 0xAC, 0x04, 0x52)                           # MOVL  4(AP), R2
    a.b(0x9E); a.rel32('numend'); a.b(0x53)               # MOVAB numend, R3
    a.b(0x94, 0x63)                                       # CLRB  (R3)
    a.lab('nl')
    a.b(0xC7, 0x0A, 0x52, 0x54)                           # DIVL3 #10, R2, R4
    a.b(0xC5, 0x0A, 0x54, 0x55)                           # MULL3 #10, R4, R5
    a.b(0xC3, 0x55, 0x52, 0x55)                           # SUBL3 R5, R2, R5
    a.b(0x80, 0x30, 0x55)                                 # ADDB2 #^X30, R5
    a.b(0x90, 0x55, 0x73)                                 # MOVB  R5, -(R3)
    a.b(0xD0, 0x54, 0x52)                                 # MOVL  R4, R2
    a.b(0x12); a.br8('nl')                                # BNEQ  nl
    a.b(0xD0, 0x53, 0x51)                                 # MOVL  R3, R1
    a.b(0xFB, 0x00); a.rel32('puts')                      # CALLS #0, puts
    a.b(0x04)                                             # RET
    # put3: print longword 4(AP) (0..999) as exactly three digits
    a.lab('put3'); a.raw(struct.pack('<H', 0x003C))       # entry mask: R2-R5
    a.b(0xD0, 0xAC, 0x04, 0x52)                           # MOVL  4(AP), R2
    a.b(0xC7); a.raw(imm(100)); a.b(0x52, 0x53)           # DIVL3 #100, R2, R3
    a.b(0xC1, 0x30, 0x53, 0x50)                           # ADDL3 #^X30, R3, R0
    a.b(0x16); a.rel32('putc')
    a.b(0xC5); a.raw(imm(100)); a.b(0x53, 0x54)           # MULL3 #100, R3, R4
    a.b(0xC2, 0x54, 0x52)                                 # SUBL2 R4, R2
    a.b(0xC7, 0x0A, 0x52, 0x53)                           # DIVL3 #10, R2, R3
    a.b(0xC1, 0x30, 0x53, 0x50)                           # ADDL3 #^X30, R3, R0
    a.b(0x16); a.rel32('putc')
    a.b(0xC5, 0x0A, 0x53, 0x54)                           # MULL3 #10, R3, R4
    a.b(0xC2, 0x54, 0x52)                                 # SUBL2 R4, R2
    a.b(0xC1, 0x30, 0x52, 0x50)                           # ADDL3 #^X30, R2, R0
    a.b(0x16); a.rel32('putc')
    a.b(0x04)                                             # RET
    a.lab('hdr'); a.raw(b'\r\nBENCH: \0')
    a.lab('hdr2'); a.raw(b' x (ADDL2, MOVL store, MOVL load, SOBGTR)\r\n\0')
    a.lab('m_el'); a.raw(b'elapsed: \0')
    a.lab('m_us'); a.raw(b' us\r\n\0')
    a.lab('m_sp'); a.raw(b'speed: \0')
    a.lab('m_cpi'); a.raw(b' MIPS = \0')
    a.lab('m_cpi2'); a.raw(b' clocks per instruction\r\n\0')
    a.lab('m_ok'); a.raw(b'data check: OK\r\n\0')
    a.lab('m_bad'); a.raw(b'data check: FAILED\r\n\0')
    a.lab('numbuf'); a.raw(bytes(12)); a.lab('numend'); a.raw(bytes(4))
    a.lab('cell'); a.raw(bytes(4))
    return a.build(), instr


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else 'bench.bin'
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 1000000
    img, instr = build(n)
    open(out, 'wb').write(img)
    print('%s: %d bytes at 0x%X, %d passes, %d timed instructions'
          % (out, len(img), BASE, n, instr))
