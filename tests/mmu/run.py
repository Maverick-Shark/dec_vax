#!/usr/bin/env python3
"""run.py - run VAX test programs on simh's vax8600 and on the RTL, compare.

Usage (from the project root):

    python3 tests/mmu/run.py [-v] [test.s ...]      (default: tests/mmu/t*.s)

Each test is a VAX MACRO-subset source for tools/vasm.py. Lines starting with
';@' in it are directives for this script:

    ;@ start=1000            start PC (hex; default: lowest address in the image)
    ;@ dump=8000:10          longwords to compare, addr:count in hex (repeatable)
    ;@ clocks=2000000        clock budget for the RTL
    ;@ ignore=R12,R13        registers/PSL not to compare
    ;@ rtl=18008:03C00000     the RTL value is checked against this instead of
                             simh's (a documented difference)
    ;@ mask=1800C:FFFFFFF0     longwords compared under a mask (e.g. condition
                             codes that the SRM leaves UNPREDICTABLE)
    ;@ page=18004             longwords compared only for the page (VA<31:9>):
                             the fault VA is "some address in the faulting
                             page" (SRM 4.9), simh and the RTL may differ

The program runs from PSL 041F0000 (kernel mode, interrupt stack, IPL 1F) and
must end in HALT. Both machines are compared on R0..R14, PSL, the PC after the
HALT and the dumped memory.

Needs: simh vax8600 (SIMH env var or ../open-simh/BIN/vax8600) and the RTL
bench (make -C sim cputb).
"""
import glob
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
VASM = os.path.join(ROOT, 'tools', 'vasm.py')
RTL = os.path.join(ROOT, 'sim', 'obj_cpu', 'Vtb_cpu')
SIMH = os.environ.get('SIMH', os.path.join(ROOT, '..', 'open-simh', 'BIN', 'vax8600'))


def directives(src):
    d = {'dump': [], 'ignore': set(), 'page': set(), 'rtl': {}, 'mask': {},
         'clocks': '4000000', 'start': None}
    for line in open(src):
        if not line.startswith(';@'):
            continue
        for item in line[2:].split():
            k, _, v = item.partition('=')
            if k == 'dump':
                a, _, n = v.partition(':')
                d['dump'].append((int(a, 16), int(n or '1', 16)))
            elif k == 'ignore':
                d['ignore'].update(x.strip().upper() for x in v.split(','))
            elif k == 'rtl':
                for x in v.split(','):
                    a, _, val = x.partition(':')
                    d['rtl']['M%08X' % int(a, 16)] = int(val, 16)
            elif k == 'mask':
                for x in v.split(','):
                    a, _, m = x.partition(':')
                    d['mask']['M%08X' % int(a, 16)] = int(m, 16)
            elif k == 'page':
                d['page'].update('M%08X' % int(x, 16) for x in v.split(','))
            else:
                d[k] = v
    return d


def assemble(src, binf):
    out = subprocess.run([sys.executable, VASM, src, '-o', binf],
                         capture_output=True, text=True)
    if out.returncode:
        raise RuntimeError(out.stdout + out.stderr)
    m = re.search(r'bytes at ([0-9A-Fa-f]+)', out.stdout)
    return int(m.group(1), 16)


def run_simh(binf, load, start, dumps, tmp):
    ini = os.path.join(tmp, 'run.ini')
    with open(ini, 'w') as f:
        f.write('set cpu 32m\n')
        f.write('load -o %s %X\n' % (binf, load))
        f.write('dep pc %X\ndep psl 041F0000\ngo\n' % start)
        f.write('ex r0-r14\nex psl\nex pc\n')
        for a, n in dumps:
            f.write('ex %X/%X\n' % (a, 4 * n))
        f.write('exit\n')
    out = subprocess.run([SIMH, ini], capture_output=True, text=True,
                         stdin=subprocess.DEVNULL, timeout=60).stdout
    res = {'stop': ''}
    for line in out.splitlines():
        m = re.match(r'^(R\d+|PSL|PC):\s+([0-9A-F]{8})', line)
        if m:
            res[m.group(1)] = int(m.group(2), 16)
            continue
        m = re.match(r'^([0-9A-F]+):\s+([0-9A-F]{8})$', line)
        if m:
            res['M%08X' % int(m.group(1), 16)] = int(m.group(2), 16)
            continue
        if 'PC:' in line and not line.startswith('PC'):
            res['stop'] = line.strip()
    return res, out


def run_rtl(binf, load, start, dumps, clocks):
    args = [RTL, binf, '%X' % load, '%X' % start, clocks]
    args += ['%X:%X' % (a, n) for a, n in dumps]
    out = subprocess.run(args, capture_output=True, text=True, cwd=ROOT,
                         timeout=600).stdout
    res = {'stop': ''}
    for line in out.splitlines():
        f = line.split()
        if not f:
            continue
        if f[0] == 'HALT':
            res['stop'] = line
            res['PC'] = int(f[2], 16)
        elif re.match(r'^(R\d+|PSL)$', f[0]):
            res[f[0]] = int(f[1], 16)
        elif f[0] == 'M':
            res['M%08X' % int(f[1], 16)] = int(f[2], 16)
        elif f[0] == 'CLOCKS':
            res['clocks'] = int(f[1])
    return res, out


def main():
    verbose = '-v' in sys.argv
    tests = [a for a in sys.argv[1:] if a != '-v']
    if not tests:
        tests = sorted(glob.glob(os.path.join(ROOT, 'tests', 'mmu', 't*.s')))
    fails = 0
    for src in tests:
        name = os.path.basename(src)
        d = directives(src)
        with tempfile.TemporaryDirectory() as tmp:
            binf = os.path.join(tmp, 'prog.bin')
            try:
                load = assemble(src, binf)
            except RuntimeError as e:
                print('%-24s ASM ERROR\n%s' % (name, e))
                fails += 1
                continue
            start = int(d['start'], 16) if d['start'] else load
            s, sout = run_simh(binf, load, start, d['dump'], tmp)
            r, rout = run_rtl(binf, load, start, d['dump'], d['clocks'])
        keys = ['R%d' % i for i in range(15)] + ['PSL', 'PC']
        keys += ['M%08X' % (a + 4 * k) for a, n in d['dump'] for k in range(n)]
        diffs = []
        for k in keys:
            if k in d['ignore']:
                continue
            sv, rv = s.get(k), r.get(k)
            if k in d['rtl']:
                sv = d['rtl'][k]
            if k in d['page'] and sv is not None and rv is not None:
                sv, rv = sv & ~0x1FF, rv & ~0x1FF
            if k in d['mask'] and sv is not None and rv is not None:
                sv, rv = sv & d['mask'][k], rv & d['mask'][k]
            if sv != rv:
                diffs.append('  %-10s simh %s  rtl %s' % (
                    k, '%08X' % sv if sv is not None else '--------',
                    '%08X' % rv if rv is not None else '--------'))
        ok = not diffs and 'TIMEOUT' not in r['stop']
        print('%-24s %s  (%s clocks)' % (name, 'PASS' if ok else 'FAIL', r.get('clocks', '?')))
        if not ok:
            fails += 1
            print('  simh: %s' % s['stop'])
            print('  rtl:  %s' % r['stop'])
            print('\n'.join(diffs))
        if verbose:
            print(sout)
            print(rout)
    print('%d test(s), %d failed' % (len(tests), fails))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
