#!/bin/sh
# nextgear.sh CHAIN_FILE K OUT_FLY  -- from a chain file with K-1 gears (g<K-1>_v_on set) build the FLYING practice file for gear K:
# gear K = an explicit copy of gear K-1's values (freeze_twins on `gears K`), practice switches gear0 K + fly_entry 2 (mkgear --fly). Also writes OUT_FLY.chain (the same with gears K and no practice switches; set g<K>_v_on by hand).
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/sprint4/env.sh
CH=$1; K=$2; OUT=$3
.venv/bin/python scratchpad/sprint2/mkgear.py $CH $OUT.tmp1 --gears $K --note "(next gear, before freeze)" > /dev/null
.venv/bin/python scratchpad/sprint4/freeze_twins.py $OUT.tmp1 $OUT.chain --note "(gear $K = copy of gear $((K-1)))"
.venv/bin/python scratchpad/sprint2/mkgear.py $OUT.chain $OUT --gears $K --fly --note "flying practice for gear $K"
rm -f $OUT.tmp1
