#!/usr/bin/env python3
"""mkimage.py - make an RP07 disk image with NetBSD/vax 11.0 that boots on
the core (the OSD's Boot with Boot Flags "8 Boot block"), from NetBSD's
install ISO, with the reference simulator doing the work:

    python3 tools/netbsd/mkimage.py NetBSD-11.0-vax.iso netbsd-rp07.dsk

1. The simulator's MicroVAX 3900 boots the ISO (NetBSD's install ISO does
   not boot on the 11/780 and 8600 models) with an empty RA92 next to it;
   from the installer's shell the RA92 gets a disk label with the RP07's
   geometry (50 sectors, 32 tracks, 630 cylinders: 1 008 000 sectors;
   a = root, b = swap 32 MB, c = all), an FFS (newfs -O 1), the sets
   (base, etc, kern-GENERIC, man, misc, text by default), /dev, an fstab
   for hp0 and an rc.conf, and NetBSD's boot block (installboot, xxboot).
   An MSCP disk is addressed by block number, so its first 1 008 000
   blocks are then an RP07 image as they are.
2. The image is cut to the RP07's size and nbpatch.py puts its two fixes
   into the kernel (the label of a Massbus disk, raw I/O to it).
3. The simulator's VAX 8600 boots it from an RP07 through VMB with R5 = 8
   (boot block), with its Unibus devices off as on the core, to the login
   prompt; root logs in, and shutdown -h leaves the file systems clean and
   the random seed written (the first boot waits a minute for it).

Needs the reference simulator's MicroVAX 3900 and VAX 8600 models
(REFSIM_UVAX, REFSIM; by default ../open-simh/BIN/microvax3900 and
../open-simh/BIN/vax8600 next to this repository) and pexpect. About
five minutes. The image holds NetBSD (BSD licence), not DEC software.
"""
import argparse
import os
import re
import shutil
import sys
import tempfile
import time

import pexpect

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
import nbpatch                                              # noqa: E402

UVAX = os.environ.get('REFSIM_UVAX', os.path.join(ROOT, '..', 'open-simh', 'BIN', 'microvax3900'))
V8600 = os.environ.get('REFSIM', os.path.join(ROOT, '..', 'open-simh', 'BIN', 'vax8600'))

RP07_SECTORS = 1008000
PROTO = '''# /dev/rhp0:
type: SMD
disk: rp07
label: netbsd-rp07
flags:
bytes/sector: 512
sectors/track: 50
tracks/cylinder: 32
sectors/cylinder: 1600
cylinders: 630
total sectors: 1008000
rpm: 3600
interleave: 1
trackskew: 0
cylinderskew: 0
headswitch: 0
track-to-track seek: 0
drivedata: 0

3 partitions:
#        size    offset     fstype [fsize bsize cpg/sgs]
 a:    942400         0     4.2BSD   2048 16384     0
 b:     65600    942400       swap
 c:   1008000         0     unused      0     0'''
FSTAB = ['/dev/hp0a / ffs rw 1 1', '/dev/hp0b none swap sw 0 0',
         'kernfs /kern kernfs rw', 'ptyfs /dev/pts ptyfs rw',
         'procfs /proc procfs rw']
RCCONF = ['rc_configured=YES', 'hostname=vax8600', 'sshd=NO', 'postfix=NO',
          'inetd=NO', 'ntpd=NO', 'savecore=NO', 'wscons=NO', 'dhcpcd=NO',
          'virecover=NO', 'makemandb=NO']

ANSI = re.compile(r'\x1b\[[0-9;?]*[A-Za-z]|\x1b[()][0-9A-Za-z]|\x1b[=>]|[\x00\x0e\x0f]')
PROMPT = 'ZZQQ> '


class Console:
    """A simulator run whose console is driven like a terminal."""

    def __init__(self, binary, ini, cwd, log):
        self.c = pexpect.spawn(binary, [ini], cwd=cwd, encoding='latin-1',
                               timeout=600, maxread=65536)
        self.log = open(log, 'w')
        self.text = ''
        self.before = ''

    def pump(self, t):
        try:
            d = self.c.read_nonblocking(65536, timeout=t)
        except pexpect.TIMEOUT:
            return
        self.log.write(d)
        self.log.flush()
        self.text += ANSI.sub('', d)

    def wait(self, pattern, timeout=600):
        end = time.time() + timeout
        rx = re.compile(pattern)
        while True:
            m = rx.search(self.text)
            if m:
                self.before = self.text[:m.start()]
                self.text = self.text[m.end():]
                return m
            if time.time() > end:
                raise SystemExit('timed out waiting for %r; console: %r'
                                 % (pattern, self.text[-800:]))
            self.pump(1)

    def send(self, s):
        self.c.send(s)

    def shell(self):
        self.send('PS1="ZZ""QQ> "; export PS1\r')
        self.wait(re.escape(PROMPT), 60)

    def run(self, cmd, timeout=900, check=True):
        self.send(cmd + '; echo rc=$?\r')
        self.wait(re.escape(PROMPT), timeout)
        out = self.before.replace('\r', '')
        m = re.search(r'rc=(\d+)\s*$', out)
        if check and (not m or m.group(1) != '0'):
            raise SystemExit('failed: %s\n%s' % (cmd, out[-1500:]))
        return out

    def close(self):
        self.c.kill(9)


def install(iso, ra, sets, work):
    ini = os.path.join(work, 'uvax.ini')
    with open(ini, 'w') as f:
        f.write('set cpu 64m\nset rq0 ra92\nattach -n rq0 %s\nset rq1 rrd40\n'
                'attach -r rq1 %s\nset rq2 disable\nset rq3 disable\n'
                'set xq disable\nset console notelnet\nboot cpu\n' % (ra, iso))
    s = Console(UVAX, ini, work, os.path.join(work, 'install.log'))
    try:
        s.wait('>>>', 120)
        s.send('boot dua1\r')
        s.wait('Terminal type', 900)
        s.send('vt100\r')
        m = s.wait(r'([a-z]): Installation messages in English', 300)
        time.sleep(2); s.send(m.group(1)); time.sleep(1); s.send('\r')
        m = s.wait(r'([a-z]): Exit Install System', 300)
        time.sleep(2); s.send(m.group(1)); time.sleep(1); s.send('\r')
        s.wait('quit this shell', 120)
        time.sleep(2)
        s.shell()
        s.run('rm -f /tmp/rp07.proto')
        for line in PROTO.split('\n'):
            s.run("echo '%s' >> /tmp/rp07.proto" % line)
        s.run('disklabel -R -r ra0 /tmp/rp07.proto')
        s.run('newfs -O 1 /dev/rra0a > /dev/null', 1800)
        s.run('mount /dev/ra0a /targetroot')
        for st in sets:
            print('  extracting', st, flush=True)
            s.run('(cd /targetroot && tar -xpzf /vax/binary/sets/%s.tgz)' % st, 7200)
        s.run('cd /targetroot/dev && sh ./MAKEDEV all; cd /', 3600)
        s.run('rm -f /targetroot/etc/fstab')
        for line in FSTAB:
            s.run("echo '%s' >> /targetroot/etc/fstab" % line)
        for line in RCCONF:
            s.run("echo '%s' >> /targetroot/etc/rc.conf" % line)
        s.run('mkdir -p /targetroot/kern /targetroot/proc')
        s.run('test -f /targetroot/boot && test -f /targetroot/netbsd')
        s.run('sync; umount /targetroot', 600)
        # the boot block goes over the label's sector: allow that first
        s.run('disklabel -W ra0 && installboot /dev/rra0c /usr/mdec/xxboot && disklabel -N ra0')
        s.run('fsck -f -p /dev/rra0a', 1800)
        s.send('halt -q\r')
        time.sleep(5)
    finally:
        s.close()


def firstboot(img, work):
    ini = os.path.join(work, 'v8600.ini')
    with open(ini, 'w') as f:
        f.write('set cpu 32m\nset rp0 noautosize\nset rp0 rp07\nattach rp0 %s\n'
                % img)
        for dev in ('dz', 'rl', 'hk', 'ry', 'lpt', 'ts', 'tq', 'rq'):
            f.write('set %s disable\n' % dev)
        f.write('set console notelnet\nboot rp0 /R5:8\n')
    s = Console(V8600, ini, work, os.path.join(work, 'firstboot.log'))
    try:
        m = s.wait(r'login:|(?<!on)panic: |HALT instruction', 1800)
        if m.group(0) != 'login:':
            raise SystemExit('the first boot stopped:\n%s%s'
                             % (s.before[-1500:], m.group(0)))
        s.send('root\r')
        s.wait('# ', 120)
        s.send('uname -a; df -k /\r')
        s.wait('# ', 300)
        print(s.before.replace('\r', '').strip())
        s.send('shutdown -h now\r')
        s.wait(r'halting', 900)
        time.sleep(3)
    finally:
        s.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('iso')
    ap.add_argument('out')
    ap.add_argument('--sets', default='base,etc,kern-GENERIC,man,misc,text')
    ap.add_argument('--no-firstboot', action='store_true')
    ap.add_argument('-k', '--keep', action='store_true', help='keep the work directory')
    a = ap.parse_args()
    work = tempfile.mkdtemp(prefix='nbimage_')
    ra = os.path.join(work, 'ra92.dsk')
    print('installing on the MicroVAX 3900 model (%s)' % work, flush=True)
    install(os.path.abspath(a.iso), ra, a.sets.split(','), work)
    shutil.copyfile(ra, a.out)
    with open(a.out, 'r+b') as f:
        f.truncate(RP07_SECTORS * 512)
    print('RP07 image: %s' % a.out)
    nbpatch.patch(a.out)
    if not a.no_firstboot:
        print('first boot on the VAX 8600 model', flush=True)
        firstboot(os.path.abspath(a.out), work)
    if a.keep:
        print('work directory:', work)
    else:
        shutil.rmtree(work)


if __name__ == '__main__':
    main()
