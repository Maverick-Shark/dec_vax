#!/usr/bin/env python3
"""mkdsimage.py - build software/evkae_ds.bin, the VAX 8600 Diagnostic
Supervisor with EVKAE loaded, as a memory image the core can load and run
without a disk controller.

    python3 tests/evkae/mkdsimage.py [-p EVKAE] [-d VAX_MINIMUM_DIAGS.dsk]
                                     [-o out.bin] [-k]

    -p   the diagnostic to load (default EVKAE; the disk also has EVKAB,
         basic instructions, EVKAC, floating point, and EVKAD, compatibility
         mode); the output is then software/<name>_ds.bin
    -k   keep the work directory

A VAX 8600 simulator on the PC (REFSIM) boots the supervisor (ZZ-EDSAA)
from the diagnostic disk, attaches the CPU and loads the diagnostic (LOAD,
not RUN). At the DS> prompt the supervisor runs with memory management off,
so its whole state is: physical memory up to the end of what it uses, the
general registers, PC, PSL, and the internal registers. This script dumps
them, replaces the first bytes at 200 with a jump to dsrestore.s, which is
put after the memory, and writes the result.

On the core: OSD Load Address 0x00000000, Start Address 0x00000200 (the
EVKAA settings), Load Program -> evkae_ds.bin. The banner tells what to type.

The file is DEC software (the supervisor and EVKAE) in another form: like
the diagnostic disk itself it is not part of the repository.

Needs the simulator (environment variable REFSIM; by default the open-simh
vax8600 binary in ../open-simh/BIN), DEC's vmb.exe (VMB; by default next to
the simulator's sources, VAX/vmb.exe) and the disk
(software/VAX_MINIMUM_DIAGS.dsk by default).
"""
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
REFSIM = os.environ.get('REFSIM', os.environ.get('SIMH',
                        os.path.join(ROOT, '..', 'open-simh', 'BIN', 'vax8600')))
VMB = os.environ.get('VMB', os.path.join(ROOT, '..', 'open-simh', 'VAX', 'vmb.exe'))
STUB = 0x200            # where the console starts the image
SCAN = 0x100000         # memory looked at for the end of the supervisor's data
PATTERN = 0xAAAAAAAA    # what the supervisor leaves in the memory it does not use

SIM_SCRIPT = r'''
set on
on error ignore
set console notelnet
attach -rq rq0 %(disk)s
expect "DS> " send "ATTACH KA780 ABUS KA0 yes yes 0 0\r"; go -q
expect "DS> " send "ATTACH DW780 ABUS DW0 3 5\r"; go -q
expect "DS> " send "ATTACH UDA50 DW0 DUA 772150 154 5 10\r"; go -q
expect "DS> " send "ATTACH RA81 DUA DUA0\r"; go -q
expect "DS> " send "SET LOAD DUA0:[SYSMAINT]\r"; go -q
expect "DS> " send "SELECT KA0\r"; go -q
expect "DS> " send "LOAD %(prog)s\r"; go -q
expect "DS> " echof "\n*** AT PROMPT ***\n"
boot -q RQ0 /R5:10
ex state
ex tti state
ex tto state
ex tmr state
ex 0-%(top)X
exit
'''


def run_ref(disk, prog, work):
    shutil.copy(VMB, os.path.join(work, 'vmb.exe'))
    ini = os.path.join(work, 'ds.ini')
    with open(ini, 'w') as f:
        f.write(SIM_SCRIPT % {'disk': os.path.abspath(disk), 'top': SCAN - 4,
                               'prog': prog})
    out = subprocess.run([REFSIM, ini], capture_output=True, text=True, cwd=work,
                         stdin=subprocess.DEVNULL, timeout=1200).stdout
    if '*** AT PROMPT ***' not in out:
        raise SystemExit('the simulator did not reach the DS> prompt:\n' + out[-3000:])
    out = out[out.index('*** AT PROMPT ***'):]
    regs, mem = {}, {}
    for line in out.splitlines():
        m = re.match(r'^([0-9A-F]+):\s+([0-9A-F]{8})$', line.strip())
        if m:
            mem[int(m.group(1), 16)] = int(m.group(2), 16)
            continue
        m = re.match(r'^([A-Z][A-Z0-9]*):\s+([0-9A-F]+)\b', line.strip())
        if m and m.group(1) not in regs:
            regs[m.group(1)] = int(m.group(2), 16)
    # every longword must have come out in hex (the -p switch, for one,
    # prints memory as PDP-11 instructions, which would be lost here)
    missing = [a for a in range(0, SCAN, 4) if a not in mem]
    if missing:
        raise SystemExit('the simulator printed %d longwords in another format, first at %X'
                         % (len(missing), missing[0]))
    return regs, mem


def assemble(src, binf):
    lst = binf[:-4] + '.lst'
    out = subprocess.run([sys.executable, VASM, src, '-o', binf, '-l', lst],
                         capture_output=True, text=True)
    if out.returncode:
        raise SystemExit(out.stdout + out.stderr)
    return open(binf, 'rb').read()


def main():
    args = sys.argv[1:]
    prog = args[args.index('-p') + 1].upper() if '-p' in args else 'EVKAE'
    if not re.match(r'^[A-Z0-9]{1,9}$', prog):
        raise SystemExit('-p: a program name such as EVKAE')
    disk = args[args.index('-d') + 1] if '-d' in args else \
        os.path.join(ROOT, 'software', 'VAX_MINIMUM_DIAGS.dsk')
    outf = args[args.index('-o') + 1] if '-o' in args else \
        os.path.join(ROOT, 'software', prog.lower() + '_ds.bin')
    work = tempfile.mkdtemp(prefix='dsimage_')
    regs, mem = run_ref(disk, prog, work)
    if regs.get('MAPEN', 1) != 0:
        raise SystemExit('memory management is on at the prompt: not supported')

    # the end of the supervisor's data: the last longword that is neither
    # the free-memory pattern nor zero, rounded up to a page
    used = [a for a, v in mem.items() if v not in (0, PATTERN)]
    top = (max(used) + 4 + 0x1FF) & ~0x1FF
    finish = top + 0x200
    image = bytearray(top)
    for a in range(0, top, 4):
        image[a:a + 4] = struct.pack('<I', mem.get(a, 0))
    orig = bytes(image[STUB:STUB + 0x100])
    jump = bytes([0x17, 0x9F]) + struct.pack('<I', finish)   # JMP @#finish
    image[STUB:STUB + len(jump)] = jump

    s = {
        'FINISH': finish,
        'S_R0': regs['R0'], 'S_R1': regs['R1'], 'S_R2': regs['R2'],
        'S_R3': regs['R3'], 'S_R4': regs['R4'], 'S_R5': regs['R5'],
        'S_R6': regs['R6'], 'S_R7': regs['R7'], 'S_R8': regs['R8'],
        'S_R9': regs['R9'], 'S_R10': regs['R10'], 'S_R11': regs['R11'],
        'S_AP': regs['AP'], 'S_FP': regs['FP'],
        'S_PC': regs['PC'], 'S_PSL': regs['PSL'],
        'S_KSP': regs['KSP'], 'S_ESP': regs['ESP'], 'S_SSP': regs['SSP'],
        'S_USP': regs['USP'], 'S_ISP': regs['IS'],
        'S_SBR': regs['SBR'], 'S_SLR': regs['SLR'],
        'S_P0BR': regs['P0BR'], 'S_P0LR': regs['P0LR'],
        'S_P1BR': regs['P1BR'], 'S_P1LR': regs['P1LR'],
        'S_SCBB': regs['SCBB'], 'S_PCBB': regs['PCBB'],
        'S_ASTLVL': regs['ASTLVL'], 'S_SISR': regs['SISR'],
        'S_NICR': regs['NICR'],
        # run and interrupt enable as they were; load ICR from NICR,
        # clear any pending request and error
        'S_ICCS': (regs['ICCS'] & 0x41) | 0x80000090,
        'S_RXCS': regs['RXCS'] & 0x40,
        'S_TXCS': regs['TXCS'] & 0x40,
    }
    if regs['PSL'] & 0x04000000:
        raise SystemExit('the supervisor is on the interrupt stack: not supported')
    with open(os.path.join(work, 'dsstate.inc'), 'w') as f:
        f.write('; generated by mkdsimage.py: the supervisor at its DS> prompt\n')
        for k, v in s.items():
            f.write('%s\t= ^x%X\n' % (k, v))
    with open(os.path.join(work, 'orig200.inc'), 'w') as f:
        for k in range(0, len(orig), 16):
            f.write('\t.byte\t%s\n' % ', '.join('^x%02X' % b for b in orig[k:k + 16]))
    with open(os.path.join(work, 'dsmsg.inc'), 'w') as f:
        f.write('\t.ascii\t"\\r\\n\\r\\nVAX 8600 Diagnostic Supervisor at its prompt, with"\n')
        f.write('\t.ascii\t"\\r\\n%s loaded. Type START, START/TEST:n or"\n' % prog)
        f.write('\t.ascii\t" START/TEST:first:last.\\r\\n\\r\\n"\n')
        f.write('\t.asciz\t"DS> "\n')
    shutil.copy(os.path.join(HERE, 'dsrestore.s'), work)
    fin = assemble(os.path.join(work, 'dsrestore.s'), os.path.join(work, 'fin.bin'))
    data = bytes(image) + bytes(finish - top) + fin
    open(outf, 'wb').write(data)
    print('%s: %d bytes; supervisor data up to %X, restore code at %X'
          % (outf, len(data), top, finish))
    print('PC %08X  PSL %08X  SP %08X  SCBB %08X  ICCS %08X'
          % (regs['PC'], regs['PSL'], regs['SP'], regs['SCBB'], regs['ICCS']))
    if '-k' in args:
        print('work directory:', work)
    else:
        shutil.rmtree(work)


if __name__ == '__main__':
    main()
