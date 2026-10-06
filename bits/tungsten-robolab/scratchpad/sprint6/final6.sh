#!/bin/sh
# final6.sh CHAIN CTL TAG [WORKERS] -- TEST A (22001-22128) and TEST B (22129-22256), 30 s, labelled beyond-human body (fr6.py), ONCE per chain; logs out/sprint6/final_TAG.log
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
CH=$1; CTL=$2; TAG=$3; W=${4:-6}
nice -n 10 .venv/bin/python scratchpad/sprint6/fr6.py $CH $CTL 22001-22128 out/sprint6/final_${TAG}_A.jsonl --workers $W --tag "$TAG TEST A 22001-22128" >> out/sprint6/final_$TAG.log 2>&1
nice -n 10 .venv/bin/python scratchpad/sprint6/fr6.py $CH $CTL 22129-22256 out/sprint6/final_${TAG}_B.jsonl --workers $W --tag "$TAG TEST B 22129-22256" >> out/sprint6/final_$TAG.log 2>&1
echo "==> Done final $TAG" >> out/sprint6/final_$TAG.log
