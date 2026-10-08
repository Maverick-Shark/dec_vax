#!/usr/bin/env python3
"""
hello.py - builds hello.bin, a small VAX test program for the MiSTer core.

Load it with OSD "Load Program" and "Load Address = 0x00001000" (default);
with "Autostart = Yes" the core types FR00001000<CR>G into the console
monitor and the program runs. It exercises CALLS/RET, JSB/RSB, AOBLEQ,
DIVL3/MULL3, MOVC3, MFPR/MTPR console I/O and the on-screen terminal (clear
screen, DEC line drawing, bold, reverse video). It ends with HALT, which
returns to the console monitor.

Usage:  python3 software/hello.py software/hello.bin
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


ESC = b'\x1b'
W = 40
SCREEN = (ESC + b'[2J' + ESC + b'[H' +
          ESC + b'(0l' + b'q' * W + b'k' + ESC + b'(B\r\n' +
          ESC + b'(0x' + ESC + b'(B' + ESC + b'[1m' + b'  DEC VAX (r-vax) on MiSTer'.ljust(W) +
          ESC + b'[0m' + ESC + b'(0x' + ESC + b'(B\r\n' +
          ESC + b'(0m' + b'q' * W + b'j' + ESC + b'(B\r\n\r\n')

a = Asm()
a.lab('start')
a.b(0xD0, 0x8F); a.raw(L4(0x800)); a.b(0x5E)          # MOVL  #^X800, SP
a.b(0x9E); a.rel32('screen'); a.b(0x51)               # MOVAB screen, R1
a.b(0xFB, 0x00); a.rel32('puts')                      # CALLS #0, puts
a.b(0x9E); a.rel32('msg1'); a.b(0x51)                 # MOVAB msg1, R1
a.b(0xFB, 0x00); a.rel32('puts')                      # CALLS #0, puts
a.b(0xD4, 0x52)                                       # CLRL  R2
a.b(0xD0, 0x01, 0x53)                                 # MOVL  #1, R3
a.lab('loop1')
a.b(0xC0, 0x53, 0x52)                                 # ADDL2 R3, R2
a.b(0xF3, 0x8F); a.raw(L4(100)); a.b(0x53); a.br8('loop1')  # AOBLEQ #100, R3, loop1
a.b(0xDD, 0x52)                                       # PUSHL R2
a.b(0xFB, 0x01); a.rel32('putnum')                    # CALLS #1, putnum
a.b(0x28, 0x0A); a.rel32('msg2'); a.rel32('buf')      # MOVC3 #10, msg2, buf
a.b(0x9E); a.rel32('buf'); a.b(0x51)                  # MOVAB buf, R1
a.b(0xFB, 0x00); a.rel32('puts')                      # CALLS #0, puts
a.b(0xC5, 0x07, 0x06, 0x54)                           # MULL3 #7, #6, R4
a.b(0xDD, 0x54)                                       # PUSHL R4
a.b(0xFB, 0x01); a.rel32('putnum')                    # CALLS #1, putnum
a.b(0x9E); a.rel32('msg3'); a.b(0x51)                 # MOVAB msg3, R1
a.b(0xFB, 0x00); a.rel32('puts')                      # CALLS #0, puts
a.b(0x00)                                             # HALT
# puts: R1 -> zero-terminated string
a.lab('puts'); a.raw(struct.pack('<H', 0x0004))       # entry mask: R2
a.lab('p1')
a.b(0x9A, 0x81, 0x50)                                 # MOVZBL (R1)+, R0
a.b(0x13); a.br8('p9')                                # BEQL  p9
a.b(0x16); a.rel32('putc')                            # JSB   putc
a.b(0x11); a.br8('p1')                                # BRB   p1
a.lab('p9'); a.b(0x04)                                # RET
# putc: R0 = character; wait for TXCS<7>, write TXDB
a.lab('putc')
a.lab('pc1')
a.b(0xDB, 0x22, 0x55)                                 # MFPR  #^X22, R5   (TXCS)
a.b(0xE1, 0x07, 0x55); a.br8('pc1')                   # BBC   #7, R5, pc1
a.b(0xDA, 0x50, 0x23)                                 # MTPR  R0, #^X23   (TXDB)
a.b(0x05)                                             # RSB
# putnum: print longword 4(AP) in decimal
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
a.b(0x9E); a.rel32('crlf'); a.b(0x51)                 # MOVAB crlf, R1
a.b(0xFB, 0x00); a.rel32('puts')                      # CALLS #0, puts
a.b(0x04)                                             # RET
a.lab('screen'); a.raw(SCREEN + b'\0')
a.lab('msg1'); a.raw(b'HOLA VAX (r-vax)\r\nSUM 1..100 = \0')
a.lab('msg2'); a.raw(b'MOVC3 OK\r\n')
a.lab('msg3'); a.raw(ESC + b'[7m REVERSE ' + ESC + b'[0m ' + ESC + b'[1mBOLD' + ESC + b'[0m DONE\r\n\0')
a.lab('buf'); a.raw(bytes(16))
a.lab('crlf'); a.raw(b'\r\n\0')
a.lab('numbuf'); a.raw(bytes(12)); a.lab('numend'); a.raw(bytes(4))

if __name__ == '__main__':
    img = a.build()
    out = sys.argv[1] if len(sys.argv) > 1 else 'hello.bin'
    open(out, 'wb').write(img)
    print('%s: %d bytes at 0x%X' % (out, len(img), BASE))
