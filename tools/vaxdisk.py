#!/usr/bin/env python3
"""vaxdisk.py - list or extract the files of a DEC disk or floppy image.

    python3 tools/vaxdisk.py list    IMAGE
    python3 tools/vaxdisk.py extract IMAGE [OUTDIR] [--raw]

Two file structures are read, told apart by their home block:

  Files-11 ODS-2 (VAX/VMS disks, "DECFILE11B" in the home block, LBN 1):
      every directory from the master file directory [000000] down, each
      file into OUTDIR/<directory path>/NAME.TYP (NAME.TYP;n for a version
      that is not the highest). Files with
      variable length records (text: command procedures, help and
      listing files) are written as lines ending in a newline; everything
      else - images, fixed length records, the directories themselves - as
      its blocks up to the end of file. --raw writes every file as blocks.

  RT-11 (console and diagnostic floppies, also as written by VMS EXCHANGE;
      the directory starts at block 6): each permanent file as its blocks
      (RT-11 files have no record structure), into OUTDIR/<NAME.TYP>.

OUTDIR defaults to the image's name without its extension, beside it. A
listing of what was extracted goes into OUTDIR/CONTENTS.txt, and each file
gets the date the volume records for it.

An image is the volume's logical blocks in order, 512 bytes each (an RX01
floppy image of 494 blocks, for instance, without its track 0).
"""
import datetime
import os
import struct
import sys

BLK = 512

# ---------------------------------------------------------------- helpers

R50 = ' ABCDEFGHIJKLMNOPQRSTUVWXYZ$.%0123456789'


def rad50(w):
    return R50[(w // 1600) % 40] + R50[(w // 40) % 40] + R50[w % 40]


def safe(name):
    """A file name that Windows accepts too: no trailing dot (an RT-11 or
    VMS file with no type), only letters, digits and . _ - $ ;"""
    s = ''.join(ch if ch.isalnum() or ch in '._-$;' else '_' for ch in name)
    return s.rstrip('.') or '_'


class Image:
    def __init__(self, path):
        self.path = path
        self.data = open(path, 'rb').read()
        self.nblk = len(self.data) // BLK

    def block(self, lbn, count=1):
        if lbn + count > self.nblk:
            raise ValueError('block %d past the end of the image (%d blocks)'
                             % (lbn + count - 1, self.nblk))
        return self.data[lbn * BLK:(lbn + count) * BLK]


# ---------------------------------------------------------------- ODS-2

VMS_EPOCH = datetime.datetime(1858, 11, 17)


def vms_time(q):
    if q == 0:
        return None
    try:
        return VMS_EPOCH + datetime.timedelta(microseconds=q // 10)
    except OverflowError:
        return None


class ODS2:
    """Files-11 structure level 2 (DEC's on-disk structure 2)."""

    def __init__(self, img):
        self.img = img
        hb = img.block(1)
        if hb[0x1F0:0x1FC] != b'DECFILE11B  ':
            raise ValueError('not an ODS-2 volume')
        # the home block (HM2$): cluster factor, index file bitmap
        self.cluster = struct.unpack_from('<H', hb, 0x0E)[0]
        self.ibmapvbn = struct.unpack_from('<H', hb, 0x16)[0]
        self.ibmaplbn = struct.unpack_from('<I', hb, 0x18)[0]
        self.maxfiles = struct.unpack_from('<I', hb, 0x1C)[0]
        self.ibmapsize = struct.unpack_from('<H', hb, 0x20)[0]
        self.volname = hb[0x1D8:0x1E4].decode('ascii', 'replace').rstrip()
        # INDEXF.SYS (file 1): its header is the first after the bitmap
        self.indexf = self.parse_header(img.block(self.ibmaplbn + self.ibmapsize))
        self.indexf_map = self.indexf['map']

    # retrieval pointers -> list of (lbn, count)
    @staticmethod
    def parse_map(h, off, inuse):
        runs = []
        end = off + inuse * 2
        while off < end:
            w0 = struct.unpack_from('<H', h, off)[0]
            fmt = w0 >> 14
            if fmt == 0:                        # placement control
                off += 2
                continue
            if fmt == 1:
                count = (w0 & 0xFF) + 1
                lbn = ((w0 >> 8) & 0x3F) << 16 | struct.unpack_from('<H', h, off + 2)[0]
                off += 4
            elif fmt == 2:
                count = (w0 & 0x3FFF) + 1
                lbn = struct.unpack_from('<I', h, off + 2)[0]
                off += 6
            else:
                count = ((w0 & 0x3FFF) << 16 | struct.unpack_from('<H', h, off + 2)[0]) + 1
                lbn = struct.unpack_from('<I', h, off + 4)[0]
                off += 8
            runs.append((lbn, count))
        return runs

    def parse_header(self, h):
        idoff, mpoff = h[0], h[1]
        fid = struct.unpack_from('<HHBB', h, 8)
        ext = struct.unpack_from('<HHBB', h, 14)
        ra = h[0x14:0x34]
        rtype, rattr, rsize = ra[0], ra[1], struct.unpack_from('<H', ra, 2)[0]
        hiblk = struct.unpack_from('<HH', ra, 4)
        efblk = struct.unpack_from('<HH', ra, 8)
        ffbyte = struct.unpack_from('<H', ra, 12)[0]
        vfcsize = ra[15]
        filechar = struct.unpack_from('<I', h, 0x34)[0]
        inuse = h[0x3A]
        ident = h[idoff * 2:]
        name = ident[0:20].decode('ascii', 'replace').rstrip()
        if len(ident) >= 0x58:
            name = (name + ident[0x36:0x36 + 66].decode('ascii', 'replace')).rstrip() \
                if ident[0x36:0x37] not in (b'\0', b' ', b'') else name
        cre = struct.unpack_from('<Q', ident, 0x16)[0] if len(ident) >= 0x1E else 0
        rev = struct.unpack_from('<Q', ident, 0x1E)[0] if len(ident) >= 0x26 else 0
        return {
            'fid': fid[0] | (fid[3] << 16), 'seq': fid[1],
            'ext': ext[0] | (ext[3] << 16),
            'rtype': rtype & 0x0F, 'rattr': rattr, 'rsize': rsize,
            'efblk': efblk[0] << 16 | efblk[1], 'hiblk': hiblk[0] << 16 | hiblk[1],
            'ffbyte': ffbyte, 'vfcsize': vfcsize, 'filechar': filechar,
            'name': name, 'created': vms_time(cre), 'revised': vms_time(rev),
            'map': self.parse_map(h, mpoff * 2, inuse),
        }

    @staticmethod
    def vbn_to_lbn(runs, vbn):
        v = 1
        for lbn, count in runs:
            if vbn < v + count:
                return lbn + vbn - v
            v += count
        return None

    def header(self, fnum):
        """The header block of file number fnum (and its extensions)."""
        vbn = self.ibmapvbn + self.ibmapsize + fnum - 1
        lbn = self.vbn_to_lbn(self.indexf_map, vbn)
        if lbn is None:
            return None
        h = self.parse_header(self.img.block(lbn))
        if h['fid'] != fnum:
            return None
        ext = h['ext']
        seen = 0
        while ext and seen < 64:                 # extension headers
            vbn = self.ibmapvbn + self.ibmapsize + ext - 1
            lbn = self.vbn_to_lbn(self.indexf_map, vbn)
            if lbn is None:
                break
            eh = self.parse_header(self.img.block(lbn))
            h['map'] += eh['map']
            ext = eh['ext']
            seen += 1
        return h

    def read_file(self, h):
        """The file's bytes up to its end of file."""
        out = bytearray()
        for lbn, count in h['map']:
            out += self.img.block(lbn, count)
        eof = h['efblk']
        if eof:
            size = (eof - 1) * BLK + h['ffbyte']
            if h['ffbyte'] == 0 and eof > 0:
                size = (eof - 1) * BLK
            out = out[:size]
        return bytes(out)

    @staticmethod
    def records(h, data):
        """Text lines of a file with variable length (or VFC) records."""
        lines = []
        rtype = h['rtype']
        off = 0
        n = len(data)
        if rtype == 1:                           # fixed length records
            rs = h['rsize'] or BLK
            while off + rs <= n:
                lines.append(data[off:off + rs])
                off += rs
            return lines
        while off + 2 <= n:
            ln = struct.unpack_from('<H', data, off)[0]
            if ln == 0xFFFF:                     # rest of the block unused
                off = (off // BLK + 1) * BLK
                continue
            off += 2
            rec = data[off:off + ln]
            if rtype == 3:                       # VFC: control bytes first
                rec = rec[h['vfcsize'] or 2:]
            lines.append(rec)
            off += ln + (ln & 1)
        return lines

    def directory(self, h):
        """[(name, version, fid)] of a directory file."""
        data = self.read_file(h)
        ents = []
        for b in range(0, len(data), BLK):
            blk = data[b:b + BLK]
            off = 0
            while off + 2 <= len(blk):
                rsize = struct.unpack_from('<H', blk, off)[0]
                if rsize == 0xFFFF or rsize == 0:
                    break
                rec = blk[off + 2:off + 2 + rsize]
                flags, namecount = rec[2], rec[3]
                name = rec[4:4 + namecount].decode('ascii', 'replace')
                p = 4 + namecount + (namecount & 1)
                while p + 8 <= len(rec):
                    ver, fnum, fseq, rvn, nmx = struct.unpack_from('<HHHBB', rec, p)
                    ents.append((name, ver, fnum | (nmx << 16)))
                    p += 8
                off += 2 + rsize
        return ents

    def walk(self):
        """(path parts, name, version, header) for every file, depth first."""
        seen = set()

        def rec(fnum, path):
            if fnum in seen:
                return
            seen.add(fnum)
            h = self.header(fnum)
            if h is None:
                return
            for name, ver, f in sorted(self.directory(h)):
                fh = self.header(f)
                if fh is None:
                    continue
                yield path, name, ver, fh
                if name.upper().endswith('.DIR') and ver == 1 and f != fnum and \
                        (fh['filechar'] & 0x2000):   # FCH$M_DIRECTORY
                    sub = name[:-4]
                    if not (fnum == 4 and sub == '000000'):
                        yield from rec(f, path + [sub])

        yield from rec(4, [])                    # 000000.DIR, the MFD


# ---------------------------------------------------------------- RT-11

class RT11:
    """RT-11 file structure (a directory of contiguous files)."""

    def __init__(self, img):
        self.img = img
        hdr = struct.unpack_from('<5H', img.block(6), 0)
        total, nxt, high, extra, start = hdr
        if not (1 <= total <= 31 and high <= total and extra < 64 and extra % 2 == 0
                and 6 < start < img.nblk):
            raise ValueError('not an RT-11 volume')
        self.extra = extra
        vid = img.block(1)[0x1F0:0x1FC]
        self.volid = vid.decode('ascii').strip() \
            if all(32 <= c < 127 for c in vid) else '(none)'

    def files(self):
        seg = 1
        seen = set()
        while seg and seg not in seen:
            seen.add(seg)
            d = self.img.block(6 + (seg - 1) * 2, 2)
            total, nxt, high, extra, start = struct.unpack_from('<5H', d, 0)
            off = 10
            blk = start
            esize = 14 + extra
            while off + esize <= len(d):
                status, n1, n2, n3, length, job, date = struct.unpack_from('<7H', d, off)
                if status & 0x0800:              # end of segment
                    break
                if status & 0x0400:              # permanent file
                    name = (rad50(n1) + rad50(n2)).strip() + '.' + rad50(n3).strip()
                    yield name, blk, length, self.date(date), bool(status & 0x8000)
                blk += length
                off += esize
            seg = nxt

    @staticmethod
    def date(w):
        if w == 0:
            return None
        age = (w >> 14) & 3
        month = (w >> 10) & 0xF
        day = (w >> 5) & 0x1F
        year = 1972 + (w & 0x1F) + 32 * age
        try:
            return datetime.datetime(year, month, day)
        except ValueError:
            return None


# ---------------------------------------------------------------- main

def open_volume(img):
    for cls in (ODS2, RT11):
        try:
            return cls(img)
        except ValueError:
            continue
    raise SystemExit('%s: neither ODS-2 nor RT-11' % img.path)


def stamp(path, when):
    if when is None:
        return
    try:
        t = (when - datetime.datetime(1970, 1, 1)).total_seconds()
        os.utime(path, (t, t))
    except (OverflowError, OSError, ValueError):
        pass


def fmt_date(when):
    return when.strftime('%d-%b-%Y').upper() if when else ''


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    raw = '--raw' in sys.argv
    if len(args) < 2 or args[0] not in ('list', 'extract'):
        sys.exit(__doc__)
    img = Image(args[1])
    vol = open_volume(img)
    out = None
    if args[0] == 'extract':
        out = args[2] if len(args) > 2 else os.path.splitext(args[1])[0]
        os.makedirs(out, exist_ok=True)
    lines = []
    total = 0
    if isinstance(vol, ODS2):
        lines.append('%s: Files-11 ODS-2, volume %s, %d blocks'
                     % (os.path.basename(args[1]), vol.volname, img.nblk))
        lines.append('')
        lines.append('%-44s %8s  %-6s %s' % ('File', 'Bytes', 'Format', 'Created'))
        files = list(vol.walk())
        top = {}                                 # highest version of each name
        for path, name, ver, h in files:
            k = (tuple(path), name)
            top[k] = max(top.get(k, 0), ver)
        for path, name, ver, h in files:
            full = '[%s]%s;%d' % ('.'.join(path) or '000000', name, ver)
            data = vol.read_file(h)
            text = (not raw and h['rtype'] in (2, 3)
                    and not name.upper().endswith('.DIR'))
            if text:
                data = b''.join(r + b'\n' for r in vol.records(h, data))
            kind = {1: 'FIX', 2: 'VAR', 3: 'VFC', 4: 'STM', 5: 'STMLF',
                    6: 'STMCR'}.get(h['rtype'], 'UDF')
            lines.append('%-44s %8d  %-6s %s' % (full, len(data), kind + ('/T' if text else ''),
                                                fmt_date(h['created'])))
            total += 1
            if out:
                d = os.path.join(out, *path)
                os.makedirs(d, exist_ok=True)
                # NAME.TYP for the highest version, NAME.TYP;n for older ones
                host = name if ver == top[(tuple(path), name)] else '%s;%d' % (name, ver)
                fn = os.path.join(d, safe(host))
                with open(fn, 'wb') as f:
                    f.write(data)
                stamp(fn, h['revised'] or h['created'])
    else:
        lines.append('%s: RT-11, volume id "%s", %d blocks'
                     % (os.path.basename(args[1]), vol.volid, img.nblk))
        lines.append('')
        lines.append('%-14s %6s %8s  %s' % ('File', 'Blocks', 'Start', 'Date'))
        for name, start, length, when, prot in vol.files():
            lines.append('%-14s %6d %8d  %s%s' % (name, length, start, fmt_date(when),
                                                 '  protected' if prot else ''))
            total += 1
            if out:
                fn = os.path.join(out, safe(name))
                with open(fn, 'wb') as f:
                    f.write(img.block(start, length))
                stamp(fn, when)
    lines.append('')
    lines.append('%d files' % total)
    text = '\n'.join(lines) + '\n'
    sys.stdout.write(text)
    if out:
        with open(os.path.join(out, 'CONTENTS.txt'), 'w') as f:
            f.write(text)


if __name__ == '__main__':
    main()
