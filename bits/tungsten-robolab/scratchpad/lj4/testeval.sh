#!/bin/sh
# FINAL evaluation of a fixed candidate on L3's two TEST sets (16 perturbed starts 901-916, 96 fresh starts 10001-10096), task long_jump_v4_beyond_a (check mark 151.025 m),
# LABELLED BEYOND-HUMAN BODY, UNLIMITED RUN-UP, through long_jump_eval.py (it does not touch the arena files). L4
# usage: testeval.sh <tag> <params.txt> <controller> [workers]
cd /Users/erik/tungsten/bits/tungsten-robolab
tag=$1; P=$2; C=$3; W=${4:-6}
nice -n 10 .venv/bin/python playground/long_jump_eval.py long_jump_v4_beyond_robust --params $P --controller $C --task long_jump_v4_beyond_a --seeds 901-916 --workers $W --out out/lj4/test_${tag}_901.json > out/lj4/test_${tag}_901.txt 2>&1
nice -n 10 .venv/bin/python playground/long_jump_eval.py long_jump_v4_beyond_robust96 --params $P --controller $C --task long_jump_v4_beyond_a --seeds 10001-10096 --workers $W --out out/lj4/test_${tag}_10001.json > out/lj4/test_${tag}_10001.txt 2>&1
echo done > out/lj4/test_${tag}.done
