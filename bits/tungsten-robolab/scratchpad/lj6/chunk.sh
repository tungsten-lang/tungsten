#!/bin/sh
# L6: a take-off program with the stock CHUNK landing (no j_il) on training seeds, to pick the landing search's record seed (a clean, legal, not flipped long jump).
# usage: chunk.sh <tag> <approach.txt> <program.txt> <seeds> [controller]   -> out/lj6/par_<tag>_chunk.txt, out/lj6/ev_chunk_<tag>.json/.txt
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/lj6/env6.sh
tag=$1; app=$2; prog=$3; seeds=$4; ctl=${5:-bin/challengers/long_jump_run_y-l4b}
.venv/bin/python scratchpad/lj2/assemble.py out/lj6/par_${tag}_chunk.txt $app $prog > /dev/null
nice -n 10 .venv/bin/python playground/long_jump_eval.py long_jump_v4_beyond_robust96 --params out/lj6/par_${tag}_chunk.txt --controller $ctl --task long_jump_v4_beyond_a \
  --seeds $seeds --workers 6 --out out/lj6/ev_chunk_${tag}.json > out/lj6/ev_chunk_${tag}.txt 2>&1
