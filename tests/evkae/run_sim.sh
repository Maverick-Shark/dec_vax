#!/bin/sh
# run_sim.sh - run EVKAE (or another exerciser) on the full-system
# simulation, from the Diagnostic Supervisor image built by mkdsimage.py.
#
#     make -C sim fast
#     tests/evkae/run_sim.sh 1:2 4:11          (from the project root)
#     IMAGE=software/evkab_ds.bin TRACE=1 tests/evkae/run_sim.sh 1:161
#
# Each argument is a test range for START/TEST:first:last, run one after the
# other at the DS> prompt; with no argument, tests 1 to 11 one at a time
# (EVKAE's). Everything the VAX prints goes to evkae_sim.txt. An EVKAE test
# takes between 50 and 300 million clocks (one to six seconds of the real
# core); an EVKAB test about 2 million, after some 45 million that each
# START spends building the supervisor's page tables. The simulation runs
# about half a million clocks a second.
#
# Environment: IMAGE (default software/evkae_ds.bin), OUT (evkae_sim.txt),
# BUDGET (clocks allowed for each range, default 800000000), TRACE=1 (type
# SET FLAGS TRACE first: each test prints its name as it starts).
IMAGE=${IMAGE:-software/evkae_ds.bin}
OUT=${OUT:-evkae_sim.txt}
BUDGET=${BUDGET:-800000000}
[ $# -eq 0 ] && set -- 1:1 2:2 3:3 4:4 5:5 6:6 7:7 8:8 9:9 10:10 11:11
SESSION=""
[ -n "$TRACE" ] && SESSION="SET FLAGS TRACE~"	# answered at once
for r in "$@"; do
	SESSION="$SESSION${SESSION:+|}START/TEST:$r~|@DS> "
done
NOTEST=1 START200=1 UNTIL="DS> " SESSION="$SESSION" BUDGET=$BUDGET \
TTOLOG="$OUT" sim/obj_fast/Vtb_top "$IMAGE" 1 "" evkae_sim.ppm > evkae_sim.log
grep -a -E "Program:|Testing|^Test [0-9]+:|errors? detected|Hard error|SCB vector|PC at error" \
    "$OUT" | tr -d '\r'
