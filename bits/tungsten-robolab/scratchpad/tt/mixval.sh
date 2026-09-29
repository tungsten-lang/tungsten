#!/bin/sh
# mixval.sh TAG PARAMS [SEEDS]  : a candidate on the mixed serves (default 710000:710600, the champion's baseline is out/tt_r10/champ_710000.jsonl), r10-n, 3 workers
cd /Users/erik/tungsten/bits/tungsten-robolab
TAG=$1; PARAMS=$2; SEEDS=${3:-710000:710600}
TT_ENV=P2 .venv-myo/bin/python playground/tt_eval.py --params $PARAMS --controller bin/challengers/myo_tt_r10-n --seeds "$SEEDS" --out out/tt_r10/$TAG.jsonl --workers 3 > out/tt_r10/$TAG.log 2>&1
