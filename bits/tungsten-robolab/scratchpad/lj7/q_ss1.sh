#!/bin/sh
# L7 steering scan batch 1: one-at-a-time variants of runner H011 + SB2 on seeds 65001-65128 (same seeds as base0)
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
S=65001-65128
rm -f out/lj7/q_ss1.done
for v in "rnd55:j_st_rnd=0.55" "rnd62:j_st_rnd=0.62" "rnd70:j_st_rnd=0.7" "up25:j_st_up=0.25" "up50:j_st_up=0.5" "max50:j_st_max=0.5" "n9:j_st_n=9" "n10:j_st_n=10" "w09:j_st_w=0.9" "w10:j_st_w=1.0" "kd1:j_st_kdrv=1.0" "kd2:j_st_kdrv=2.0" "zk1:j_st_zk=1.0" "zk2:j_st_zk=2.0" "win35:j_win=0.35" "win55:j_win=0.55"; do
  name=${v%%:*}; over=${v#*:}
  scratchpad/lj7/ss.sh $name $S "$over" 6
done
echo done > out/lj7/q_ss1.done
