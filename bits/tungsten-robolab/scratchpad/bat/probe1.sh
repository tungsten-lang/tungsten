#!/bin/sh
# sensitivity probes of the taim correction (seeds 3000-3047): unit gain on the k_z_u / k_x_u vectors
cd /Users/erik/tungsten/bits/tungsten-robolab
for s in "taim_z=1" "taim_x=1"; do
  name=probe1_$(echo $s | tr '=' '_')
  .venv/bin/python playground/bat_rep.py eval --params params/bat_v6_knots.txt --controller bin/challengers/bat_r2-t1 --seeds 3000:3048 --set "$s" --workers 2 --name $name --quiet
done
