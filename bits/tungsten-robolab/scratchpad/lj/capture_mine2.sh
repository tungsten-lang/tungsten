#!/bin/sh
# capture the pen-touchdown states of 160 more mining starts (seeds 8163-8322) with b18, 2 processes
cd /Users/erik/tungsten/bits/tungsten-robolab
mk() { python3 -c "print(','.join(str(i) for i in range($1, $2+1)))"; }
for r in "8163 8242" "8243 8322"; do
  set -- $r
  S=$(mk $1 $2)
  nohup .venv/bin/python playground/long_jump_limits.py capture long_jump_p95e --params out/long_jump_run/p95pn_approach.txt --controller bin/challengers/long_jump_run-b18 --seeds $S --name p95mn --from pen > out/long_jump_limits/cap_p95mn_$1.log 2>&1 &
done
wait
echo done > out/long_jump_limits/cap_p95mn2.done
