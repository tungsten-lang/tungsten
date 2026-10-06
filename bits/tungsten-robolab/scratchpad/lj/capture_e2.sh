#!/bin/sh
# capture the plant-flight states of 160 mining starts for the elite2 body (seeds 8001-8160), 2 processes
cd /Users/erik/tungsten/bits/tungsten-robolab
mk() { python3 -c "print(','.join(str(i) for i in range($1, $2+1)))"; }
for r in "8001 8080" "8081 8160"; do
  set -- $r
  S=$(mk $1 $2)
  nohup .venv/bin/python playground/long_jump_limits.py capture long_jump_elite2 --params out/long_jump_run/e2r_approach_cap.txt --controller bin/challengers/long_jump_run-b18 --seeds $S --name e2m > out/long_jump_limits/cap_e2m_$1.log 2>&1 &
done
wait
echo done > out/long_jump_limits/cap_e2m.done
