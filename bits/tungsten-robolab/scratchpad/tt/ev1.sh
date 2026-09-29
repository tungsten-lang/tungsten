#!/bin/sh
# ev1.sh TAG PARAMS CTL SEEDSFILE "k=v,..." [WORKERS]  : one-worker tt_eval with logs (round 10 side runs)
cd /Users/erik/tungsten/bits/tungsten-robolab
TAG=$1; PARAMS=$2; CTL=$3; SEEDS=$(cat $4); SET=$5; W=${6:-1}
TT_ENV=P2 TT_SAVE_LOG=$PWD/out/tt_r10/${TAG}_logs .venv-myo/bin/python playground/tt_eval.py --params $PARAMS --controller $CTL --seeds "$SEEDS" --out out/tt_r10/${TAG}.jsonl --workers $W ${SET:+--set "$SET"} > out/tt_r10/${TAG}.log 2>&1
