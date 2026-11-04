"""explog.py - helpers for the generators that write a test's expected log
(the ';@ rtl=' lines) from the DEC documents: a list of longwords in the
order the test program stores them at LOG, put into the test source."""
import re

LOG = 0x18000


class Log:
    def __init__(self, base=LOG):
        self.base = base
        self.v = []

    def put(self, *vals):
        """longwords the program logs; None: not checked"""
        self.v.extend(vals)

    def mchk(self, pa, we=False, io=True, bad=False):
        """what the tests' machine check handler logs: the byte count,
        EBCS, MSTAT1, MSTAT2, MEAR and PC - (the failing instruction):
        EK-8600S-MM-004 appendix K, M-04 (CP I/O buffer error; with bad,
        read data that came back marked bad: MSTAT2<14>, ABus bad data)"""
        ebcs = 0x0020C000 | (4 if we else 0) | (2 if (io and not we) else 0)
        mstat1 = 0x80000000 | (0x34000000 if we else 0x38000000)
        mstat2 = 0x00184000 if bad else 0x00180004 if io else 0x001F0008
        self.put(0x58, ebcs, mstat1, mstat2, pa & ~3, 0)

    def lines(self):
        pairs = ['%X:%08X' % (self.base + 4 * i, x)
                 for i, x in enumerate(self.v) if x is not None]
        return [';@ rtl=' + ','.join(pairs[i:i + 6])
                for i in range(0, len(pairs), 6)]

    def write_into(self, src):
        out = self.lines()
        s = open(src).read()
        s = re.sub(r'(;@ rtl=[^\n]*\n)+', '', s)
        s = s.replace(';@ noref\n', ';@ noref\n' + '\n'.join(out) + '\n', 1)
        open(src, 'w').write(s)
        print('%s: %d longwords expected' % (src, sum(l.count(':') for l in out)))
