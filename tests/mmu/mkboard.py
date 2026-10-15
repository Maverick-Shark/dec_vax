#!/usr/bin/env python3
"""mkboard.py - build software/mmutest.bin: the tests/mmu programs as one
self-checking program that runs on the core itself (on the board, or in the
full-system simulation) and prints PASS or FAIL for each test.

    python3 tests/mmu/mkboard.py [-o software/mmutest.bin] [-k]

    -k   keep the work directory (assembler listings, simh scripts)

For each test, the HALTs (in the test and in mmsetup.inc) become a branch to
"finish" (board.inc), and the program is assembled and run on simh vax8600
up to "finish". The registers, PSL and memory that run.py compares are
stored in the program as its table of expected values, with run.py's rules
(;@ ignore, rtl, mask, page). Then runner.s (the loop that resets the
machine, runs each test and compares) and boot.s (which moves the runner out
of the tests' way) are put in front.

A test with ";@ board=halt" (t16_isnv) ends in a processor halt; it runs
last and is checked by eye: the console must show the halt code.

Load the result at 1000 and start it there (the OSD defaults). Needs simh's
vax8600 (SIMH environment variable or ../open-simh/BIN/vax8600).
"""
import glob
import importlib.util
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
VASM = os.path.join(ROOT, 'tools', 'vasm.py')

spec = importlib.util.spec_from_file_location('mmurun', os.path.join(HERE, 'run.py'))
mmurun = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mmurun)

TBASE = 0x1000
REG = 0xFFFFFF00
PSL = 0xFFFFFF0F


def assemble(src, binf):
    lst = binf[:-4] + '.lst'
    out = subprocess.run([sys.executable, VASM, src, '-o', binf, '-l', lst],
                         capture_output=True, text=True)
    if out.returncode:
        raise SystemExit(out.stdout + out.stderr)
    syms = {}
    for line in open(lst):
        m = re.match(r'^([0-9A-F]{8})  (\S+)$', line.strip())
        if m:
            syms[m.group(2)] = int(m.group(1), 16)
    org = int(re.search(r'origin ([0-9A-F]+)', open(lst).readline()).group(1), 16)
    return open(binf, 'rb').read(), org, syms


HALT = re.compile(r'^(\s*(?:[A-Za-z_$.][\w$.]*:)?\s*)halt\b(.*)$', re.I)


def board_source(path):
    """The source with every HALT replaced by a branch to finish."""
    out = []
    for line in open(path).read().split('\n'):
        code, sep, comment = line.partition(';')
        m = HALT.match(code)
        if m:
            line = m.group(1) + 'brw\tfinish' + m.group(2) + sep + comment
        out.append(line)
    return '\n'.join(out)


def expected_entries(d):
    """(what, rtl key) for everything run.py compares, in table order."""
    ents = []
    for i in range(15):
        if 'R%d' % i not in d['ignore']:
            ents.append((REG + i, 'R%d' % i))
    if 'PSL' not in d['ignore']:
        ents.append((PSL, 'PSL'))
    for a, n in d['dump']:
        for k in range(n):
            key = 'M%08X' % (a + 4 * k)
            if key not in d['ignore']:
                ents.append((a + 4 * k, key))
    return ents


def run_simh(binf, finish, dumps, work):
    ini = os.path.join(work, 'board.ini')
    with open(ini, 'w') as f:
        f.write('set cpu 32m\n')
        f.write('load -o %s %X\n' % (binf, TBASE))
        f.write('dep pc %X\ndep psl 041F0000\n' % TBASE)
        f.write('break %X\nbreak %X\n' % (finish, finish | 0x80000000))
        f.write('go\n')
        f.write('ex r0-r14\nex psl\nex pc\n')
        for a, n in dumps:
            f.write('ex %X/%X\n' % (a, 4 * n))
        f.write('exit\n')
    out = subprocess.run([mmurun.SIMH, ini], capture_output=True, text=True,
                         stdin=subprocess.DEVNULL, timeout=120).stdout
    res = {}
    for line in out.splitlines():
        m = re.match(r'^(R\d+|PSL|PC):\s+([0-9A-F]{8})', line)
        if m:
            res[m.group(1)] = int(m.group(2), 16)
            continue
        m = re.match(r'^([0-9A-F]+):\s+([0-9A-F]{8})$', line)
        if m:
            res['M%08X' % int(m.group(1), 16)] = int(m.group(2), 16)
    if res.get('PC', 0) & 0x3FFFFFFF != finish:
        raise SystemExit('simh did not reach finish (%08X):\n%s' % (finish, out))
    return res


def main():
    args = sys.argv[1:]
    outf = os.path.join(ROOT, 'software', 'mmutest.bin')
    if '-o' in args:
        outf = args[args.index('-o') + 1]
    keep = '-k' in args
    work = tempfile.mkdtemp(prefix='mmuboard_')
    for f in ('board.inc', 'runner.s', 'boot.s'):
        shutil.copy(os.path.join(HERE, f), work)
    with open(os.path.join(work, 'mmsetup.inc'), 'w') as f:
        f.write(board_source(os.path.join(HERE, 'mmsetup.inc')))

    tests = []
    for src in sorted(glob.glob(os.path.join(HERE, 't*.s'))):
        name = os.path.basename(src)[:-2]
        d = mmurun.directives(src)
        halts = d.get('board') == 'halt'
        ents = [] if halts else expected_entries(d)
        s = os.path.join(work, name + '.s')
        with open(s, 'w') as f:
            f.write(board_source(src))
            f.write('\nNEXP = %d\n\t.include "board.inc"\n' % len(ents))
        binf = os.path.join(work, name + '.bin')
        img, org, syms = assemble(s, binf)
        if org != TBASE:
            raise SystemExit('%s: does not start at %X' % (name, TBASE))
        img = bytearray(img)
        if not halts:
            res = run_simh(binf, syms['finish'], d['dump'], work)
            table = [len(ents)]
            for what, key in ents:
                val = d['rtl'].get(key, res.get(key))
                if val is None:
                    raise SystemExit('%s: simh gave no value for %s' % (name, key))
                mask = 0xFFFFFFFF
                if key in d['page']:
                    mask = 0xFFFFFE00
                if key in d['mask']:
                    mask = d['mask'][key]
                table += [what, val, mask]
            off = syms['exptab'] - TBASE
            img[off:off + 4 * len(table)] = struct.pack('<%dI' % len(table), *table)
        tests.append((name, bytes(img), syms['sav'], syms['exptab'], 1 if halts else 0))
        print('%-16s %5d bytes, %3d values%s' % (name, len(img), len(ents),
              ', ends in a processor halt' if halts else ''))

    tests.sort(key=lambda t: t[4])          # halting tests last
    with open(os.path.join(work, 'suite.inc'), 'w') as f:
        f.write('; generated by mkboard.py\n')
        f.write('NTESTS = %d\n' % len(tests))
        f.write('ttab:\n')
        for i, (name, img, sav, exp, flg) in enumerate(tests):
            f.write('\t.long\tname%d, img%d, %d, ^x%X, ^x%X, %d\n'
                    % (i, i, len(img), sav, exp, flg))
        for i, (name, img, sav, exp, flg) in enumerate(tests):
            f.write('name%d:\t.asciz\t"%s"\n' % (i, name))
        for i, (name, img, sav, exp, flg) in enumerate(tests):
            f.write('\t.align\t4\nimg%d:\n' % i)
            for k in range(0, len(img), 16):
                f.write('\t.byte\t%s\n' % ', '.join('^x%02X' % b for b in img[k:k + 16]))
    runner, rorg, rsyms = assemble(os.path.join(work, 'runner.s'),
                                   os.path.join(work, 'runner.bin'))
    if rorg != 0x300000:
        raise SystemExit('runner.s does not start at 300000')
    with open(os.path.join(work, 'payload.inc'), 'w') as f:
        f.write('PLEN = %d\n' % len(runner))
    boot, borg, bsyms = assemble(os.path.join(work, 'boot.s'),
                                 os.path.join(work, 'boot.bin'))
    pad = bsyms['payload'] - borg
    if len(boot) > pad:
        raise SystemExit('boot.s: payload label before the end of the code')
    data = boot + bytes(pad - len(boot)) + runner
    open(outf, 'wb').write(data)
    print('%s: %d bytes, %d tests; load and start at 1000' % (outf, len(data), len(tests)))
    if keep:
        print('work directory:', work)
    else:
        shutil.rmtree(work)


if __name__ == '__main__':
    main()
