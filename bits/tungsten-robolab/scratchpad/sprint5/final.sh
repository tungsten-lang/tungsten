#!/bin/sh
# final.sh CHAIN CTL TAG [WORKERS] -- the headline (12001-12128) and the confirmation (13001-13128) measurements of ONE chain, 30 s, beyond body (fr.py); logs out/sprint5/final_TAG.log
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
CH=$1; CTL=$2; TAG=$3; W=${4:-6}
nice -n 10 .venv/bin/python scratchpad/sprint5/fr.py $CH $CTL 12001-12128 out/sprint5/final_${TAG}_head.jsonl --workers $W --tag "$TAG HEADLINE 12001-12128" >> out/sprint5/final_$TAG.log 2>&1
nice -n 10 .venv/bin/python scratchpad/sprint5/fr.py $CH $CTL 13001-13128 out/sprint5/final_${TAG}_conf.jsonl --workers $W --tag "$TAG CONFIRMATION 13001-13128" >> out/sprint5/final_$TAG.log 2>&1
echo "==> Done final $TAG" >> out/sprint5/final_$TAG.log
