#!/bin/sh
# usage: wtrace.sh <params> <seed> <ctl> <secs> <env> <set> [stride]
cd /Users/erik/tungsten/bits/tungsten-robolab
MYO_SOCCER_ENV=$5 TRACE_SET="$6" TRACE_STRIDE=1 TRACE_PRINT=0 TRACE_OUT=scratchpad/soccer4/wt.json .venv-myo/bin/python scratchpad/soccer4/trace.py $1 $2 $3 $4 2>&1 | grep '"time"' | cut -c1-100
python3 - ${7:-10} <<'PY'
import json, sys
d=json.load(open("/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4/wt.json"))
k=int(sys.argv[1])
for r in d["rows"][::k]:
    print(f'{r["t"]:5.2f} {r["lab"][:34]:34s} tp {r["tpitch"]:+.2f} pp {r["ppitch"]:+.2f} fe {r["fe"]:+.2f} hfL {r["l"]["hflex"]:+.2f} hfR {r["r"]["hflex"]:+.2f} pz {r["pz_h"]:.2f} yaw {r["yaw"]:+.2f} cx {r["comx_l"]:+.2f} L {r["l"]["load"]:.2f} R {r["r"]["load"]:.2f}')
PY
