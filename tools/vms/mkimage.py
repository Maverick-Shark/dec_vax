#!/usr/bin/env python3
"""mkimage.py - make an RP07 disk image with OpenVMS VAX 7.3 that boots on
the core (the OSD's Boot with Boot Flags 0), from the OpenVMS VAX V7.3
CD-ROM image, with the reference simulator's VAX 8600 doing the work:

    python3 tools/vms/mkimage.py OpenVMS-VAX-7.3.iso vms73-rp07.dsk

V7.3 is the last version of VMS for the 8600 and 8650. The installation is
the one an 8600 with a CD-ROM drive on a UDA50 would go through:

1. The CD boots (VMB from the UDA50, unit 0) into standalone BACKUP, which
   restores the save set VMS073.B onto the RP07 (DRA0: to VMS, the Massbus
   drive type of an RP07).
2. The RP07 boots into the installation procedure, which takes the other
   save sets from the CD: the OpenVMS library, optional and help message
   files, without DECwindows, DECnet or the Management Station; asks for
   the passwords of SYSTEM, SYSTEST and FIELD (all --password), the node
   name and number (VAX860, 1025) and the time zone (--tz, the number in
   its menu: 3 is CET); runs AUTOGEN and reboots.
3. Once the system is up, SYSTEM logs in and the system is shut down, so
   that the image is left clean.

Then the image boots on the reference simulator again with only what the
core has - the RH780 with two RP07s, the DW780 with nothing on its Unibus
- to the login prompt (--no-check leaves that out).

Needs the reference simulator's VAX 8600 (REFSIM; by default
../open-simh/BIN/vax8600 next to this repository) and pexpect. About ten
minutes. VMS has no hobbyist licences any more: it boots and lets you log
in on the console without them, with %LICENSE warnings. The image holds
VMS: it is for whoever owns the CD, not for passing around.
"""
import argparse
import importlib.util
import os
import re
import shutil
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
REFSIM = os.environ.get('REFSIM', os.path.join(ROOT, '..', 'open-simh', 'BIN', 'vax8600'))

# the console handling of tools/netbsd/mkimage.py
_spec = importlib.util.spec_from_file_location(
    'nbmkimage', os.path.join(HERE, '..', 'netbsd', 'mkimage.py'))
_nb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_nb)
Console = _nb.Console

OFF = ('dz', 'rl', 'hk', 'ry', 'lpt', 'ts', 'tq')
DCL = r'\n\r?\s?\$ '            # the DCL prompt (VMS pads it with a NUL)


def vmsdate():
    return time.strftime('%d-%b-%Y %H:%M').upper()


def answer(s, prompt, text, timeout=600):
    s.wait(prompt, timeout)
    time.sleep(0.5)
    s.send(text + '\r')


def install(iso, dsk, work, pw, tz):
    ini = os.path.join(work, 'install.ini')
    with open(ini, 'w') as f:
        f.write('set cpu 32m\nset rp0 noautosize\nset rp0 rp07\nattach -n rp0 %s\n'
                'set rq0 rrd40\nattach -r rq0 %s\nset rq1 disable\nset rq2 disable\n'
                'set rq3 disable\n' % (dsk, iso))
        for dev in OFF:
            f.write('set %s disable\n' % dev)
        f.write('set console notelnet\nboot rq0\n')
    s = Console(REFSIM, ini, work, os.path.join(work, 'install.log'))
    try:
        # standalone BACKUP from the CD
        answer(s, r'PLEASE ENTER DATE AND TIME', vmsdate(), 600)
        answer(s, r'Enter "YES" when all needed devices are available:', 'YES')
        answer(s, r'Stand-alone BACKUP.*\n\$ ', 'BACKUP DUA0:VMS073.B/SAVE_SET DRA0:')
        s.wait(r'Enter "YES" to continue:', 1800)
        if 'PROCDONE' not in s.before:
            raise SystemExit('BACKUP failed:\n' + s.before[-1500:])
        s.send('\x05')
        answer(s, r'sim> ', 'boot rp0', 60)
        # the installation procedure on the RP07
        answer(s, r'Please enter the date and time', vmsdate(), 900)
        answer(s, r'volume label for this system disk \[OVMSVAXSYS\]:', '')
        answer(s, r'drive holding the OpenVMS distribution media:', 'DUA0')
        answer(s, r'media ready to be mounted\? \[N\]', 'Y')
        answer(s, r'install the OpenVMS library files\? \(Y/N\)', 'Y')
        answer(s, r'install the OpenVMS optional files\? \(Y/N\)', 'Y')
        answer(s, r'install the MSGHLP database\? \(Y/N\)', 'Y')
        answer(s, r'Where do you want to install the MSGHLP database\?', '')
        answer(s, r'Management Station files\? \(Y/N\)', 'N')
        answer(s, r'DECwindows base support\? \(Y/N\)', 'N')
        answer(s, r'install DECnet-Plus\? \(Y/N\)', 'N')
        answer(s, r'install DECnet Phase IV\? \(Y/N\)', 'N')
        answer(s, r'Is this correct\? \(Y/N\)', 'Y')
        for acct in ('SYSTEM', 'SYSTEST', 'FIELD'):
            answer(s, r'Enter password for %s:' % acct, pw, 1800)
            answer(s, r'Re-enter for verification:', pw)
        answer(s, r'enter the SCSNODE name:', 'VAX860')
        answer(s, r'enter the SCSSYSTEMID:', '1025')
        answer(s, r'register any Product Authorization Keys\? \(Y/N\):', 'N', 1800)
        answer(s, r'best describes your location:', str(tz), 900)
        answer(s, r'Is this correct\? \(Yes/No\) \[YES\]:', '')
        answer(s, r'Is Daylight Savings time in effect\? \(Yes/No\):',
               'YES' if time.localtime().tm_isdst > 0 else 'NO')
        answer(s, r'Enter the Time Differential Factor \[[-0-9:]+\]:', '')
        answer(s, r'Is this correct\? \[Y\]:', '')
        # AUTOGEN, a reboot, the startup procedure
        s.wait(r'Rebooting', 3600)
        login_shutdown(s, pw)
    finally:
        s.close()


def login_shutdown(s, pw, show=False):
    s.wait(r'SYSTEM\s+job terminated', 3600)
    time.sleep(3)
    s.send('\r')
    answer(s, r'Username:', 'SYSTEM', 120)
    answer(s, r'Password:', pw, 120)
    s.wait(DCL, 600)
    if show:
        s.send('SHOW SYSTEM\r')
        s.wait(DCL, 600)
        print(s.before.replace('\r', '').strip(), flush=True)
    s.send('@SYS$SYSTEM:SHUTDOWN\r')
    for prompt in (r'minutes until final shutdown \[0\]:', r'Reason for shutdown',
                   r'spin down the disk volumes \[NO\]\?',
                   r'site-specific shutdown procedure \[YES\]\?',
                   r'automatic system reboot be performed \[NO\]\?',
                   r'When will the system be rebooted', r'Shutdown options \[NONE\]:'):
        answer(s, prompt, '', 300)
    s.wait(r'SYSTEM SHUTDOWN COMPLETE', 900)
    time.sleep(2)


def check(dsk, work, pw):
    ini = os.path.join(work, 'check.ini')
    with open(ini, 'w') as f:
        f.write('set cpu 32m\nset rp0 noautosize\nset rp0 rp07\nattach rp0 %s\n'
                'set rp1 noautosize\nset rp1 rp07\n' % dsk)
        for u in range(2, 8):
            f.write('set rp%d disable\n' % u)
        f.write('set tu disable\nset rq disable\n')
        for dev in OFF:
            f.write('set %s disable\n' % dev)
        f.write('set console notelnet\nboot rp0\n')
    s = Console(REFSIM, ini, work, os.path.join(work, 'check.log'))
    try:
        login_shutdown(s, pw, show=True)
    finally:
        s.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('iso')
    ap.add_argument('out')
    ap.add_argument('--password', default='VAXMISTER',
                    help='for SYSTEM, SYSTEST and FIELD (8 characters or more)')
    ap.add_argument('--tz', type=int, default=3,
                    help='time zone: its number in the installation menu (3 = CET)')
    ap.add_argument('--no-check', action='store_true')
    ap.add_argument('-k', '--keep', action='store_true', help='keep the work directory')
    a = ap.parse_args()
    work = tempfile.mkdtemp(prefix='vmsimage_')
    dsk = os.path.join(work, 'rp07.dsk')
    print('installing on the VAX 8600 model (%s)' % work, flush=True)
    install(os.path.abspath(a.iso), dsk, work, a.password, a.tz)
    if not a.no_check:
        print('booting it as the core is made', flush=True)
        check(dsk, work, a.password)
    shutil.copyfile(dsk, a.out)
    print('RP07 image: %s' % a.out)
    if a.keep:
        print('work directory:', work)
    else:
        shutil.rmtree(work)


if __name__ == '__main__':
    main()
