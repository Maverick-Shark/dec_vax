#!/usr/bin/env python3
"""
term_test.py - compares vt_term (Verilator, obj_unit/Vunit_top) against the
pyte VT100 emulator on deterministic and random byte streams.
Run from sim/:  python3 term_test.py [n_random]
Requires: pip install pyte
"""
import random
import subprocess
import sys
import tempfile

import copy

import pyte
from pyte import charsets as cs

ESC = '\x1b'
COLS, ROWS = 80, 30


# genuine VT100 DEC Special Graphics: only 5Fh-7Eh are replaced (pyte adds
# xterm extras such as '+' ',' '-' '.' '0')
_GFX = [0x00A0, 0x25C6, 0x2592, 0x2409, 0x240C, 0x240D, 0x240A, 0x00B0,
        0x00B1, 0x2424, 0x240B, 0x2518, 0x2510, 0x250C, 0x2514, 0x253C,
        0x23BA, 0x23BB, 0x2500, 0x23BC, 0x23BD, 0x251C, 0x2524, 0x2534,
        0x252C, 0x2502, 0x2264, 0x2265, 0x03C0, 0x2260, 0x00A3, 0x00B7]
pyte.charsets.MAPS['0'] = ''.join(chr(_GFX[i - 0x5F]) if 0x5F <= i <= 0x7E else chr(i)
                                  for i in range(256))


class VT100Screen(pyte.Screen):
    """pyte with genuine VT100 details: the pending-wrap cursor sits on the
    last column for movements and erases, DECRC does not pop the saved state
    and, with nothing saved, homes the cursor with normal rendition."""

    def _unwrap(self):
        if self.cursor.x == self.columns:
            self.cursor.x = self.columns - 1

    def cursor_up(self, count=None):
        self._unwrap(); super().cursor_up(count)

    def cursor_down(self, count=None):
        self._unwrap(); super().cursor_down(count)

    def cursor_forward(self, count=None):
        self._unwrap(); super().cursor_forward(count)

    def index(self):
        self._unwrap(); super().index()

    def reverse_index(self):
        self._unwrap(); super().reverse_index()

    def erase_in_line(self, how=0, private=False):
        x = self.cursor.x
        self._unwrap(); super().erase_in_line(how, private); self.cursor.x = x

    def erase_in_display(self, how=0, *args, **kwargs):
        x = self.cursor.x
        self._unwrap(); super().erase_in_display(how, *args, **kwargs); self.cursor.x = x

    def restore_cursor(self):
        if self.savepoints:
            sp = self.savepoints[-1]
            self.savepoints.append(sp._replace(cursor=copy.copy(sp.cursor)))
        else:
            self.cursor.attrs = self.default_char
            self.g0_charset = self.g1_charset = cs.LAT1_MAP
            self.charset = 0
        super().restore_cursor()


def reference(data):
    # pyte treats NEL (ESC E) as a bare LF; a VT100 does CR+LF
    data = data.replace(ESC + 'E', '\r' + ESC + 'D')
    scr = VT100Screen(COLS, ROWS)
    st = pyte.Stream(scr)
    st.use_utf8 = False        # so ESC ( 0 / SO / SI take effect (VT100 behaviour)
    st.feed(data)
    text = [''.join(scr.buffer[r][c].data for c in range(COLS)) for r in range(ROWS)]
    # attributes of blank cells are not compared: pyte erases with the current
    # rendition (xterm BCE), a VT100 erases to normal rendition
    attr = [''.join('.' if scr.buffer[r][c].data in ' \xa0' else
                    '.rbx'[(scr.buffer[r][c].bold << 1) | scr.buffer[r][c].reverse]
                    for c in range(COLS)) for r in range(ROWS)]
    return text, attr, (scr.cursor.y, scr.cursor.x)


def dut(data):
    with tempfile.NamedTemporaryFile(suffix='.bin', delete=False) as f:
        f.write(data.encode('latin-1'))
        fn = f.name
    out = subprocess.run(['obj_unit/Vunit_top', 'term', fn], capture_output=True).stdout.decode('utf-8')
    lines = out.split('\n')
    text, attr = lines[:ROWS], lines[ROWS:2 * ROWS]
    cur = lines[2 * ROWS].split()
    return text, attr, (int(cur[1]), int(cur[2]), int(cur[4]))


def compare(name, data):
    rt, ra, rc = reference(data)
    # pyte uses ' ' for erased cells and '\xa0'-like for DEC blank; normalise
    norm = lambda s: s.replace('\xa0', ' ')
    dt, da, dc = dut(data)
    da = [''.join('.' if dt[r][c] in ' \xa0' else da[r][c] for c in range(COLS)) for r in range(ROWS)]
    ok = True
    for r in range(ROWS):
        if norm(rt[r]) != norm(dt[r]) or ra[r] != da[r]:
            if ok:
                print('--- %s: first mismatch at row %d' % (name, r))
            print('ref |%s|\n    |%s|\ndut |%s|\n    |%s|' % (rt[r], ra[r], dt[r], da[r]))
            ok = False
            break
    # pyte keeps x == COLS while a wrap is pending; ours keeps col 79 + flag
    ry, rx = rc
    dy, dx, wrap = dc
    if ok and not (ry == dy and (rx == dx or (rx == COLS and dx == COLS - 1 and wrap))):
        print('--- %s: cursor ref %s dut %s' % (name, rc, dc))
        ok = False
    print('%-28s %s' % (name, 'OK' if ok else 'FAIL'))
    return ok


def deterministic():
    tests = {}
    tests['scroll 45 lines'] = ''.join('LINE %02d\r\n' % i for i in range(45))
    tests['autowrap'] = 'A' * 79 + 'B' + 'C' + '\r\n' + 'x' * 200
    tests['wrap at bottom'] = '\r\n' * 29 + 'W' * 85
    tests['cursor moves'] = (ESC + '[10;20HX' + ESC + '[3AU' + ESC + '[2BD' + ESC + '[5CR' +
                             ESC + '[7DL' + ESC + '[HH' + ESC + '[99;99HZ')
    tests['erase display'] = ('#' * 2400 + ESC + '[15;40H' + ESC + '[0J' + ESC + '[5;10H' +
                              ESC + '[1J' + ESC + '[20;1HZ')
    tests['erase line'] = ('-' * 2400 + ESC + '[3;10H' + ESC + '[K' + ESC + '[4;10H' + ESC + '[1K' +
                           ESC + '[5;10H' + ESC + '[2K')
    tests['clear screen'] = 'junk\r\nmore' + ESC + '[2J' + ESC + '[Hclean'
    tests['tabs bs'] = 'a\tb\tc\x08\x08X\r\n' + 'z' * 70 + '\t\tE'
    tests['index rev index'] = ('top\r\n' + ESC + 'M' + ESC + 'Mabove' + ESC + '[30;1H' +
                                ESC + 'Dbelow' + ESC + 'Enext')
    tests['save restore'] = 'hello' + ESC + '7' + ESC + '[10;10Hfar' + ESC + '8' + 'back'
    tests['sgr'] = (ESC + '[1mBOLD' + ESC + '[0m ' + ESC + '[7mREV' + ESC + '[m ' +
                    ESC + '[1;7mBOTH' + ESC + '[22mrev' + ESC + '[27mnone')
    tests['dec graphics'] = (ESC + '(0lqqk\r\nx  x\r\nmqqj' + ESC + '(B abc' +
                             ESC + ')0\x0eaf`\x0f ok')
    tests['latin1'] = 'Espa\xf1a \xbfqu\xe9? \xa1s\xed! \xe7\xc7\xba\xaa'
    tests['bel and nul'] = 'a\x07b\x00c\x7fd'
    return tests


def random_stream(seed, n=3000):
    rnd = random.Random(seed)
    parts = []
    seqs = [lambda: ESC + '[%d;%dH' % (rnd.randint(0, 35), rnd.randint(0, 90)),
            lambda: ESC + '[%dA' % rnd.randint(0, 40), lambda: ESC + '[%dB' % rnd.randint(0, 40),
            lambda: ESC + '[%dC' % rnd.randint(0, 90), lambda: ESC + '[%dD' % rnd.randint(0, 90),
            lambda: ESC + '[%dJ' % rnd.randint(0, 2), lambda: ESC + '[%dK' % rnd.randint(0, 2),
            lambda: ESC + '[%dm' % rnd.choice([0, 1, 7, 22, 27]),
            lambda: ESC + rnd.choice('DEM78'), lambda: rnd.choice(['\r', '\n', '\t', '\x08', '\r\n']),
            lambda: ESC + '(' + rnd.choice('0B')]
    total = 0
    while total < n:
        if rnd.random() < 0.25:
            s = rnd.choice(seqs)()
        else:
            s = ''.join(chr(rnd.randint(0x20, 0x7E)) for _ in range(rnd.randint(1, 120)))
        parts.append(s)
        total += len(s)
    return ''.join(parts)


def main():
    nrand = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    ok = True
    for name, data in deterministic().items():
        ok &= compare(name, data)
    for i in range(nrand):
        ok &= compare('random seed %d' % i, random_stream(i))
    print('ALL PASS' if ok else 'SOME FAILURES')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
