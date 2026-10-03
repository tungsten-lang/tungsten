#!/bin/sh
# landing table for a robust take-off program: hand-overs of the training captures (+ execution-noise variants), the recorded chunk landing of one start,
# then the landing search (il_*). usage: land.sh <tag> <program.txt> <train-list-file> <rec-seed> <evals> <variants> [extra landing args...]   (6 workers; L3)
cd /Users/erik/tungsten/bits/tungsten-robolab
. scratchpad/lj3/env.sh
export ROBOLAB_LJ_APPROACH=151.025 ROBOLAB_LJ_MARGIN=0.03
tag=$1; prog=$2; list=$3; recseed=$4; ev=$5; var=$6; shift 6
CTL=${CTL:-bin/challengers/long_jump_run_x-l3b}
first=$(cut -d, -f1 $list)
.venv/bin/python scratchpad/lj2/assemble.py out/lj3/par_${tag}_chunk.txt scratchpad/lj3/SB1.txt $prog > /dev/null
nice -n 10 .venv/bin/python playground/long_jump_limits.py handover $prog --captures "$(cat $list)" --name h$tag --variants $var > out/lj3/handover_$tag.log 2>&1
nice -n 10 .venv/bin/python playground/long_jump_limits.py record long_jump_v4_beyond_a --params out/lj3/par_${tag}_chunk.txt --controller $CTL --seed $recseed --name rec$tag > out/lj3/record_$tag.log 2>&1
tland=$(.venv/bin/python -c "import numpy as np; print(round(float(np.load('out/long_jump_limits/rec${tag}_landrec.npz')['t_land']),3))")
tg=$(python3 -c "print(round($tland + 0.013, 3))")
echo "land $tag: recorded sand at $tland s after the handover, tg $tg" | tee out/lj3/land_$tag.head
rm -f out/lj3/land_$tag.done
nice -n 10 .venv/bin/python playground/long_jump_limits.py landing --handover h$tag --capture $first --rec rec$tag --tg $tg --h 0.08 --nk 34 --lz 0.8 --evals $ev --workers 6 --sigma 0.06 --risk 0.5 --g0 0.3 --out out/lj3/land_$tag.txt "$@" > out/lj3/land_$tag.log 2>&1
echo done > out/lj3/land_$tag.done
