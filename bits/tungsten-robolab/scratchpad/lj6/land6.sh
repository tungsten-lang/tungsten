#!/bin/sh
# L6: landing table for a take-off program: hand-overs (harness), the recorded chunk landing of one start (the landing search's clock reference), then the landing search.
# LABELLED beyond-human body, unlimited run-up. Adapted from scratchpad/lj4/land2.sh (L4). Output out/lj6/land_<tag>.{txt,log,head,done}.
# env: APP (approach file, default the H011 runner + SB2), CTL (controller), WORKERS, INIT (a landing table to start from, default L4's land_C2), MARGIN, STAGES (1 = hand-overs + record only)
# usage: land6.sh <tag> <program.txt> <handover-list-file> <rec-seed> <evals> <variants> [extra landing args...]
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/lj6/env6.sh
export ROBOLAB_LJ_APPROACH=151.025 ROBOLAB_LJ_MARGIN=${MARGIN:-0.03}
tag=$1; prog=$2; list=$3; recseed=$4; ev=$5; var=$6; shift 6
CTL=${CTL:-bin/challengers/long_jump_run_y-l4b}
APP=${APP:-out/lj6/A2h_011.txt}
INIT=${INIT:-out/lj4/land_C2.txt}
first=$(cut -d, -f1 $list)
.venv/bin/python scratchpad/lj2/assemble.py out/lj6/par_${tag}_chunk.txt $APP $prog > /dev/null
nice -n 10 .venv/bin/python playground/long_jump_limits.py handover $prog --captures "$(cat $list)" --name h$tag --variants $var > out/lj6/handover_$tag.log 2>&1
nice -n 10 .venv/bin/python playground/long_jump_limits.py record long_jump_v4_beyond_a --params out/lj6/par_${tag}_chunk.txt --controller $CTL --seed $recseed --name rec$tag > out/lj6/record_$tag.log 2>&1
tland=$(.venv/bin/python -c "import numpy as np; print(round(float(np.load('out/long_jump_limits/rec${tag}_landrec.npz')['t_land']),3))")
tg=$(python3 -c "print(round($tland + 0.013, 3))")
echo "land $tag: recorded sand at $tland s after the handover, tg $tg" | tee out/lj6/land_$tag.head
[ "${STAGES:-2}" = "1" ] && exit 0
rm -f out/lj6/land_$tag.done
nice -n 10 .venv/bin/python playground/long_jump_limits.py landing --handover h$tag --capture $first --rec rec$tag --tg $tg --h 0.08 --nk 34 --lz 0.8 --evals $ev --workers ${WORKERS:-6} --sigma 0.06 --risk 0.5 --g0 0.3 --init $INIT --out out/lj6/land_$tag.txt "$@" > out/lj6/land_$tag.log 2>&1
echo done > out/lj6/land_$tag.done
