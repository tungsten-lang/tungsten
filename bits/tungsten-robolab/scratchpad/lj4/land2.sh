#!/bin/sh
# landing table for a take-off program (+ optional regime tails): hand-overs (the harness, RegimeIK when TAILS_NPZ is set), the recorded chunk landing of one start, then the landing search.
# LABELLED BEYOND-HUMAN BODY, UNLIMITED RUN-UP. L4 (adapted from scratchpad/lj3/land.sh and lj4/land.sh).
# env: APP (approach file), CTL (controller), WORKERS, TAILS_FILE (params file with the ik_rg keys), TAILS_NPZ (trained tails, comma list), T1, T2, MARGIN
# usage: land2.sh <tag> <program.txt> <train-list-file> <rec-seed> <evals> <variants> [extra landing args...]
cd /Users/erik/tungsten/bits/tungsten-robolab
. scratchpad/lj4/env.sh
export ROBOLAB_LJ_APPROACH=151.025 ROBOLAB_LJ_MARGIN=${MARGIN:-0.03}
tag=$1; prog=$2; list=$3; recseed=$4; ev=$5; var=$6; shift 6
CTL=${CTL:-bin/challengers/long_jump_run_y-l4b}
APP=${APP:-scratchpad/lj4/A2.txt}
first=$(cut -d, -f1 $list)
.venv/bin/python scratchpad/lj2/assemble.py out/lj4/par_${tag}_chunk.txt $APP $prog $TAILS_FILE > /dev/null
if [ -n "$TAILS_NPZ" ]; then
  nice -n 10 .venv/bin/python scratchpad/lj4/ho_tail.py $prog --captures "$(cat $list)" --name h$tag --variants $var --tails $TAILS_NPZ --t1 ${T1:-0.20} --t2 ${T2:-0.26} > out/lj4/handover_$tag.log 2>&1
else
  nice -n 10 .venv/bin/python playground/long_jump_limits.py handover $prog --captures "$(cat $list)" --name h$tag --variants $var > out/lj4/handover_$tag.log 2>&1
fi
nice -n 10 .venv/bin/python playground/long_jump_limits.py record long_jump_v4_beyond_a --params out/lj4/par_${tag}_chunk.txt --controller $CTL --seed $recseed --name rec$tag > out/lj4/record_$tag.log 2>&1
tland=$(.venv/bin/python -c "import numpy as np; print(round(float(np.load('out/long_jump_limits/rec${tag}_landrec.npz')['t_land']),3))")
tg=$(python3 -c "print(round($tland + 0.013, 3))")
echo "land $tag: recorded sand at $tland s after the handover, tg $tg" | tee out/lj4/land_$tag.head
rm -f out/lj4/land_$tag.done
nice -n 10 .venv/bin/python playground/long_jump_limits.py landing --handover h$tag --capture $first --rec rec$tag --tg $tg --h 0.08 --nk 34 --lz 0.8 --evals $ev --workers ${WORKERS:-6} --sigma 0.06 --risk 0.5 --g0 0.3 --out out/lj4/land_$tag.txt "$@" > out/lj4/land_$tag.log 2>&1
echo done > out/lj4/land_$tag.done
