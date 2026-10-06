#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
export OMP_NUM_THREADS=1
C=bin/challengers/btl4-final
P=scratchpad/btl4/params/final_f.txt
E=scratchpad/btl3/params/final_e.txt
run() { nice -n 10 .venv/bin/python scratchpad/btl2/chain.py "$@"; }
# 1 selection, candidate
run $C $P 10001 10129 15 "" 6 > out/btl4/fin_sel_cand.log 2>&1
grep -E "^[0-9]+ streak" out/btl4/fin_sel_cand.log | awk '{print $1, $3}' > out/btl4/fin_sel_cand.streaks
# 2 confirmation, candidate
run $C $P 12001 12129 15 "" 6 > out/btl4/fin_conf_cand.log 2>&1
grep -E "^[0-9]+ streak" out/btl4/fin_conf_cand.log | awk '{print $1, $3}' > out/btl4/fin_conf_cand.streaks
# 3 identity chain 901-932 (15 s): btl3-e and the final build, both with final_e.txt
run bin/challengers/btl3-e $E 901 933 15 "" 6 > out/btl4/fin_id_old.log 2>&1
run $C $E 901 933 15 "" 6 > out/btl4/fin_id_new.log 2>&1
grep -E "^[0-9]+ streak" out/btl4/fin_id_old.log | awk '{print $1, $3}' > out/btl4/fin_id_old.streaks
grep -E "^[0-9]+ streak" out/btl4/fin_id_new.log | awk '{print $1, $3}' > out/btl4/fin_id_new.streaks
echo done > out/btl4/fin_battery.done
