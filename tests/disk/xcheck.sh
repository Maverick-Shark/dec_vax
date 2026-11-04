#!/bin/sh
# xcheck.sh - the RP07 image exchange test: an image the core writes reads
# back the same on the reference simulator, and the other way round.
#
#     make -C sim cputb && sh tests/disk/xcheck.sh      (from the project root)
#
# xwr.s writes four sectors of generated data at LBA 1000 of RP07 unit 0,
# xrd.s reads them and counts the longwords that differ. Each machine writes
# an image of zeros the size of an RP07, the other one reads it. Needs the
# reference simulator (REFSIM, default ../open-simh/BIN/vax8600) and the CPU
# bench (sim/obj_cpu/Vtb_cpu). Prints PASS or FAIL for each direction.
REFSIM=${REFSIM:-../open-simh/BIN/vax8600}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
python3 tools/vasm.py tests/disk/xwr.s -o "$W/xwr.bin" > /dev/null || exit 1
python3 tools/vasm.py tests/disk/xrd.s -o "$W/xrd.bin" > /dev/null || exit 1
ini() {     # ini prog image: a reference simulator script
	printf 'set cpu 32m\nset rp0 rp07\nattach rp0 %s\nload -o %s 1000\n' "$2" "$1"
	printf 'dep pc 1000\ndep psl 041F0000\ngo\nex 18000/C\nexit\n'
}
rc=0
# the core writes, the reference simulator reads
truncate -s 516096000 "$W/a.img"
DISK0="$W/a.img" sim/obj_cpu/Vtb_cpu "$W/xwr.bin" 1000 1000 20000000 18000:1 \
	| grep -q "^M 00018000 00002000" || { echo "core write: FAIL"; rc=1; }
ini "$W/xrd.bin" "$W/a.img" > "$W/rd.ini"
out=$("$REFSIM" "$W/rd.ini" 2>&1)
if echo "$out" | grep -q "^18000:	00002000" && echo "$out" | grep -q "^18004:	00000000"; then
	echo "core -> reference simulator: PASS"
else
	echo "core -> reference simulator: FAIL"; echo "$out" | grep "^180"; rc=1
fi
# the reference simulator writes, the core reads
truncate -s 516096000 "$W/b.img"
ini "$W/xwr.bin" "$W/b.img" > "$W/wr.ini"
"$REFSIM" "$W/wr.ini" 2>&1 | grep -q "^18000:	00002000" || { echo "reference write: FAIL"; rc=1; }
out=$(DISK0="$W/b.img" sim/obj_cpu/Vtb_cpu "$W/xrd.bin" 1000 1000 20000000 18000:3)
if echo "$out" | grep -q "^M 00018000 00002000" && echo "$out" | grep -q "^M 00018004 00000000"; then
	echo "reference simulator -> core: PASS"
else
	echo "reference simulator -> core: FAIL"; echo "$out" | grep "^M"; rc=1
fi
exit $rc
