#!/usr/bin/env python3
"""run_vmb.py - start DEC's primary bootstrap, VMB.EXE, on the RTL as the
VAX 8600 console does for an RP07, and on the reference simulator with the
same disk, and compare what each prints on the console.

    python3 tests/boot/run_vmb.py [-r R5] [-u unit] [-c clocks] disk.dsk

The 8600 console loads VMB at 200 (the base of 64 KB of good memory plus
200) and starts it there with SP = 200 and, for a Massbus disk, R0 = 0
(device type), R1 = 8 (the TR of the RH780; <7:4> SBIA 0), R2 = R3 = the
drive's unit, R4 = 0 and R5 = the software boot flags (EK-V8600-OG chapter
3: the boot command procedures; VMB's register conventions). R5 bit 7
skips VMB's memory test, which otherwise takes some ten times longer.

On the RTL a small program at 18000 loads the registers and jumps to VMB
(the CPU bench starts at a PC with PSL 041F0000, as after initialization).

Needs: VMB.EXE (environment variable VMB; by default the reference
simulator's copy, ../open-simh/VAX/vmb.exe), the reference simulator
(REFSIM, as tests/mmu/run.py) unless -n, and the CPU bench (make -C sim
cputb).
"""
import argparse
import os
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
VASM = os.path.join(ROOT, 'tools', 'vasm.py')
RTL = os.environ.get('RTLBIN', os.path.join(ROOT, 'sim', 'obj_cpu', 'Vtb_cpu'))
REFSIM = os.environ.get('REFSIM', os.path.join(ROOT, '..', 'open-simh', 'BIN', 'vax8600'))
VMB = os.environ.get('VMB', os.path.join(ROOT, '..', 'open-simh', 'VAX', 'vmb.exe'))

GO = 0x18000


def rtl_run(disk, unit, r5, clocks, tmp):
    src = os.path.join(tmp, 'go.s')
    open(src, 'w').write('''	.org	^x%X
go:	clrl	r0			; Massbus disk
	movl	#8, r1			; TR 8, SBIA 0
	movl	#%d, r2
	movl	#%d, r3			; the drive's unit
	clrl	r4
	movl	#^x%X, r5		; boot flags
	movl	#^x200, sp
	jmp	@#^x200
''' % (GO, unit, unit, r5))
    gob = os.path.join(tmp, 'go.bin')
    subprocess.run([sys.executable, VASM, src, '-o', gob], check=True,
                   capture_output=True)
    vmb = open(VMB, 'rb').read()
    img = bytearray(GO - 0x200)
    img[:len(vmb)] = vmb
    img += open(gob, 'rb').read()
    imf = os.path.join(tmp, 'img.bin')
    open(imf, 'wb').write(img)
    env = dict(os.environ, TTO='1', **{'DISK%d' % unit: disk})
    p = subprocess.run([RTL, imf, '200', '%X' % GO, str(clocks)], env=env,
                       capture_output=True)
    out = p.stdout.decode('latin-1')
    halt = [l for l in out.splitlines() if l.startswith(('HALT', 'CLOCKS'))]
    return p.stderr.decode('latin-1'), halt


def ref_run(disk, unit, r5, tmp):
    log = os.path.join(tmp, 'ref.log')
    scr = os.path.join(tmp, 'ref.sim')
    open(scr, 'w').write('''set cpu 32m
set rp%d rp07
attach -r rp%d %s
set console log=%s
boot rp%d/R5:%X
''' % (unit, unit, disk, log, unit, r5))
    subprocess.run([REFSIM, scr], capture_output=True, stdin=subprocess.DEVNULL,
                   timeout=600)
    d = open(log, 'rb').read().decode('latin-1')
    i = d.find('Loading boot code')
    d = d[d.find('\n', i) + 1:] if i >= 0 else d
    j = d.find('HALT instruction')
    return d[:j] if j >= 0 else d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-r', '--r5', default='80', help='boot flags, hex (default 80)')
    ap.add_argument('-u', '--unit', type=int, default=0)
    ap.add_argument('-c', '--clocks', type=int, default=400000000)
    ap.add_argument('-n', '--noref', action='store_true')
    ap.add_argument('disk')
    a = ap.parse_args()
    r5 = int(a.r5, 16)
    disk = os.path.abspath(a.disk)
    with tempfile.TemporaryDirectory() as tmp:
        rtl, halt = rtl_run(disk, a.unit, r5, a.clocks, tmp)
        print('RTL:', repr(rtl))
        print('    ', ' / '.join(halt))
        if not a.noref:
            ref = ref_run(disk, a.unit, r5, tmp)
            print('REF:', repr(ref))
            norm = lambda t: t.replace('\r', '').strip()
            print('same' if norm(rtl) == norm(ref) else 'DIFFERENT')


if __name__ == '__main__':
    main()
