#!/usr/bin/env python3
"""run_sys.py - run "noref" tests (those checked against ;@ rtl= values) on
the full-system simulation (sim/obj_fast/Vtb_top: the cache, the SDRAM
controller and its model, the HPS loader) instead of the CPU bench, with
the disks their ;@ disk0= / disk1= directives give, and compare memory.

    python3 tests/mmu/run_sys.py [-v] test.s ...

Each program is downloaded at 1000 like the OSD loader does and started
there; the simulation stops when the CPU halts (HALT=1), then the longwords
the test checks are read from the SDRAM model (MEMDUMP).
"""
import importlib.util
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
SYS = os.environ.get('SYSBIN', os.path.join(ROOT, 'sim', 'obj_fast', 'Vtb_top'))

spec = importlib.util.spec_from_file_location('mmurun', os.path.join(HERE, 'run.py'))
mmurun = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mmurun)


def main():
    verbose = '-v' in sys.argv
    tests = [a for a in sys.argv[1:] if a != '-v']
    fails = 0
    for src in tests:
        name = os.path.basename(src)
        d = mmurun.directives(src)
        keys = sorted(set(d['rtl']) | set(d['mask']))
        with tempfile.TemporaryDirectory() as tmp:
            binf = os.path.join(tmp, 'prog.bin')
            load = mmurun.assemble(src, binf)
            if load != 0x1000:
                print('%-24s SKIP (loads at %X)' % (name, load))
                continue
            env = dict(os.environ)
            for k in ('DISK0', 'DISK1'):
                env.pop(k, None)
            for k in ('disk0', 'disk1'):
                if k in d:
                    env[k.upper()] = d[k]
            env.update(NOTEST='1', HALT='1', NOHPSRST='1',
                       BUDGET=str(int(d['clocks']) * 3),
                       MEMDUMP=','.join('%X:1' % int(k[1:], 16) for k in keys))
            out = subprocess.run([SYS, binf, '0', '', os.path.join(tmp, 'f.ppm')],
                                 capture_output=True, text=True, cwd=ROOT, env=env,
                                 timeout=3600).stdout
        got = {}
        for line in out.splitlines():
            m = re.match(r'^M ([0-9A-F]{8}) ([0-9A-F]{8})$', line)
            if m:
                got['M%08X' % int(m.group(1), 16)] = int(m.group(2), 16)
        diffs = []
        for k in keys:
            want, rv = d['rtl'].get(k), got.get(k)
            if want is None:
                continue
            if k in d['mask'] and rv is not None:
                want, rv = want & d['mask'][k], rv & d['mask'][k]
            if want != rv:
                diffs.append('  %-10s want %08X  got %s' % (
                    k, want, '%08X' % rv if rv is not None else '--------'))
        ok = not diffs and got
        print('%-24s %s' % (name, 'PASS' if ok else 'FAIL'))
        if not ok:
            fails += 1
            print('\n'.join(diffs[:40]))
        if verbose or not ok:
            tail = [l for l in out.splitlines() if l.startswith('cpu:') or 'halt' in l.lower()]
            print('\n'.join(tail[-3:]))
    print('%d test(s), %d failed' % (len(tests), fails))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
