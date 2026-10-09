#!/usr/bin/env python3
"""
mkmsg.py - generate rtl/mister/vax_msg.v, the text ROM the power-on self test
prints on the console terminal.

Each message lives in its own 64-character slot; address = {msg[3:0], idx[5:0]}.
Byte 0 ends a message. Bytes 80h-97h are placeholders expanded by
vax_selftest.v into hexadecimal digits - they sit above the control codes so
that CR, LF and the rest stay ordinary characters:

    0x80..0x87  digits of value A (longword address), most significant first
    0x88..0x8F  digits of value B (data read)
    0x90..0x97  digits of value C (data expected)
    0x98..0x9F  digits of value D (read-phase map)

Usage:  python3 tools/mkmsg.py rtl/mister/vax_msg.v
"""
import sys

A = bytes(range(0x80, 0x88))
B = bytes(range(0x88, 0x90))
C = bytes(range(0x90, 0x98))
D = bytes(range(0x98, 0xA0))

MESSAGES = [
    b"\r\n== r-vax / MiSTer   cache 16 KB   clock 50 MHz\r\n",   # 0
    b"== SDRAM module: not reported by the HPS\r\n",             # 1
    b"== SDRAM module: 32 MB\r\n",                               # 2
    b"== SDRAM module: 64 MB\r\n",                               # 3
    b"== SDRAM module: 128 MB\r\n",                              # 4
    b"== memory test: PASS\r\n",                                 # 5
    b"== memory test: FAIL lw=" + A + b" got=" + B + b" exp=" + C + b"\r\n",  # 6
    b"== memory test: skipped\r\n",                              # 7
    # d4..d7 = result of read phase 0..3, d3 = the phase now in use
    b"== read phase 0123 = " + D[4:8] + b"  using " + D[3:4] + b"\r\n",       # 8
]

SLOT = 64


def main():
    dst = sys.argv[1] if len(sys.argv) > 1 else "rtl/mister/vax_msg.v"
    rom = {}
    for n, m in enumerate(MESSAGES):
        if len(m) >= SLOT:
            sys.exit("message %d is %d bytes, slot is %d" % (n, len(m), SLOT))
        for i, ch in enumerate(m):
            rom[n * SLOT + i] = ch

    with open(dst, "w") as f:
        f.write("// vax_msg.v - console text for the power-on self test.\n")
        f.write("// DO NOT EDIT - regenerate with tools/mkmsg.py\n")
        f.write("// Bytes 80h-97h are hex-digit placeholders, 00h ends a message.\n\n")
        f.write("`default_nettype none\n\n")
        f.write("module vax_msg (\n\tinput            clk,\n"
                "\tinput      [9:0] addr,\n\toutput reg [7:0] q\n);\n\n")
        f.write("\talways @(posedge clk)\n\t\tcase (addr)\n")
        for a in sorted(rom):
            ch = rom[a]
            note = chr(ch) if 0x20 <= ch < 0x7F else ""
            note = ("  // " + note) if note not in ("", " ") else ""
            f.write("\t\t10'h%03X: q <= 8'h%02X;%s\n" % (a, ch, note))
        f.write("\t\tdefault: q <= 8'h00;\n\t\tendcase\n\nendmodule\n\n"
                "`default_nettype wire\n")
    print("%s: %d messages, %d characters" % (dst, len(MESSAGES), len(rom)))


if __name__ == "__main__":
    main()
