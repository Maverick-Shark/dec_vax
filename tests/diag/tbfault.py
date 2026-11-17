#!/usr/bin/env python3
"""tbfault.py - check that software/mmudiag.bin finds a fault in the
translation buffer's RAM and names it.

    make -C sim cputbf
    python3 tests/diag/tbfault.py [-j jobs] [-b software/mmudiag.bin] [bits]

Runs the diagnostic on the CPU bench built with the RAM as Quartus builds it
(sim/obj_cpuf/Vtb_cpu, see sim/Makefile) once with no fault and then with
each bit of the RAM's write data stuck at 1 (+TBFAULT=100+k) and at 0
(+TBFAULT=200+k), k = 0..39 or the bits given. The word is
{tag<13:0>, pfn<20:0>, prot<3:0>, m}: k = 0 is M, 1-4 the protection code,
5-25 the PFN, 26-39 the tag.

What must happen:
  - no fault: "Memory management works."
  - PFN bits 0-15 (k = 5-20), stuck either way: step T names the bit and
    how it is stuck ("PFN bit 0000000n STUCK AT x") and the diagnostic stops.
  - PFN bits 16-20 stuck at 1 (k = 21-25): the processor halts in step T
    with code 5: the fetch goes beyond the 32 MB, a machine check, and the
    machine check frame goes there too, a double error. Stuck at 0 they
    change nothing (the pages of a 32 MB machine have those bits 0) and
    the diagnostic passes.
The other bits are run too and what the diagnostic says is listed; they
must not be taken for a PFN bit.
"""
import concurrent.futures
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
BENCH = os.path.join(ROOT, 'sim', 'obj_cpuf', 'Vtb_cpu')
MAXCLK = 40000000


def run(binf, fault):
    env = dict(os.environ, TTO='1')
    args = [BENCH, binf, '1000', '1000', str(MAXCLK)]
    if fault:
        args.append('+TBFAULT=%d' % fault)
    p = subprocess.run(args, capture_output=True, text=True, env=env, timeout=1800)
    return p.stdout, p.stderr


def verdict(out, tto):
    """A short summary of what the diagnostic said."""
    if 'Memory management works.' in tto:
        return 'works'
    m = re.search(r'PFN bit ([0-9A-F]{8}) STUCK AT ([01])', tto)
    if m:
        return 'PFN bit %d stuck at %s' % (int(m.group(1), 16), m.group(2))
    m = re.search(r'came back with ([0-9A-F]{8})', tto)
    if m:
        return 'step T: came back with %s' % m.group(1)
    m = re.search(r'exception, SCB ([0-9A-F]{8})[^\n]*\n(?:.*\n)*?UNEXPECTED, stopped in step (\S+)', tto)
    if m:
        return 'exception SCB %s in step %s' % (m.group(1)[-2:], m.group(2).lstrip('0') or '0')
    m = re.search(r'steps with errors: ([0-9A-F]{8})', tto)
    if m:
        bad = re.findall(r'^(\d+|T) .*ERROR', tto, re.M)
        return 'errors in step(s) %s' % ','.join(bad) if bad else \
            'errors: %d' % int(m.group(1), 16)
    last = tto.strip().split('\n')[-1] if tto.strip() else ''
    m = re.match(r'^(\d+|T) ', last)
    h = re.search(r'^HALT (-?\d+)', out, re.M)
    if m and h:
        return 'halt %s in step %s' % (h.group(1), m.group(1))
    return 'stopped (%s)' % (last[:60] or 'no output')


def expected(fault):
    """What must be said for this fault, or None (anything but a PFN bit)."""
    if fault == 0:
        return 'works'
    k = fault % 100
    one = fault < 200
    if 5 <= k <= 20:
        return 'PFN bit %d stuck at %d' % (k - 5, 1 if one else 0)
    if 21 <= k <= 25:
        return 'halt 5 in step T' if one else 'works'
    return None


def what(k):
    if k == 0:
        return 'M'
    if k <= 4:
        return 'prot<%d>' % (k - 1)
    if k <= 25:
        return 'pfn<%d>' % (k - 5)
    return 'tag<%d>' % (k - 26)


def main():
    args = sys.argv[1:]
    jobs = 2
    binf = os.path.join(ROOT, 'software', 'mmudiag.bin')
    if '-j' in args:
        i = args.index('-j')
        jobs = int(args[i + 1])
        del args[i:i + 2]
    if '-b' in args:
        i = args.index('-b')
        binf = args[i + 1]
        del args[i:i + 2]
    bits = [int(a) for a in args] if args else list(range(40))
    if not os.path.exists(BENCH):
        raise SystemExit('%s not found: make -C sim cputbf' % BENCH)
    faults = [0] + [100 + k for k in bits] + [200 + k for k in bits]
    res = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as ex:
        futs = {ex.submit(run, binf, f): f for f in faults}
        for fu in concurrent.futures.as_completed(futs):
            f = futs[fu]
            out, tto = fu.result()
            res[f] = verdict(out, tto)
    nbad = 0
    for f in faults:
        exp = expected(f)
        got = res[f]
        if exp is None:
            ok = not got.startswith('PFN bit')
        else:
            ok = got == exp
        if not ok:
            nbad += 1
        if f == 0:
            name = 'no fault'
        else:
            name = 'bit %2d %-8s stuck at %d' % (f % 100, what(f % 100), 1 if f < 200 else 0)
        print('%-28s %-40s %s' % (name, got, 'ok' if ok else 'WRONG (expected: %s)' %
                                  (exp or 'not a PFN bit')))
    print('%d run(s), %d wrong' % (len(faults), nbad))
    sys.exit(1 if nbad else 0)


if __name__ == '__main__':
    main()
