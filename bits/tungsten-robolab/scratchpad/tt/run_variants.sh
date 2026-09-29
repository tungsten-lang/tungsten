#!/bin/sh
# usage: run_variants.sh <tag> <controller> <params> <seeds> <set> [extra env]
cd /Users/erik/tungsten/bits/tungsten-robolab
tag=$1; ctl=$2; par=$3; seeds=$4; set=$5
TT_ENV=P2 TT_SAVE_LOG=$PWD/out/tt_r10/${tag}_logs .venv-myo/bin/python playground/tt_eval.py --params $par --controller $ctl --set "$set" --seeds $seeds --out out/tt_r10/${tag}.jsonl --workers 3 > out/tt_r10/${tag}.log 2>&1
grep '^{' out/tt_r10/${tag}.log
