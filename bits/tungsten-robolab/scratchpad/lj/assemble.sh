#!/bin/sh
# assemble a full params file: <take-off program+feedback file> <landing file> <out> [tg] [delta]
# (the overlay last: il_tg/il_zl and the check-mark shift j_board_shift - delta, ik_gap0 + delta)
cd /Users/erik/tungsten/bits/tungsten-robolab
IK=$1; LAND=$2; OUT=$3; TG=${4:-0.61}; DELTA=${5:-0.05}
BS=$(python3 - <<PY
import re
t=open("$IK").read()
bs=float(re.search(r"^j_board_shift (\S+)", t, re.M).group(1)); g0=float(re.search(r"^ik_gap0 (\S+)", t, re.M).group(1))
print(repr(bs-$DELTA), repr(g0+$DELTA))
PY
)
set -- $BS
cat $IK $LAND > $OUT
echo "il_tg $TG" >> $OUT
echo "il_zl 0.44387629375771404" >> $OUT
echo "j_board_shift $1" >> $OUT
echo "ik_gap0 $2" >> $OUT
echo "assembled $OUT (tg $TG delta $DELTA board_shift $1 gap0 $2)"
