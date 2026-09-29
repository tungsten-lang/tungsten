#!/bin/sh
# Forehand arm gain scan (r10-p fh_gain) on 200 forehand serves nobody has used (fh750[0:200]); champion baseline first. Waits for the forehand stage B. Workers from the load.
cd /Users/erik/tungsten/bits/tungsten-robolab
while pgrep -f "[r]sm_run8.sh" > /dev/null; do sleep 10; done
W=3; L=$(uptime | sed 's/.*load averages*: //' | awk '{print $2}' | tr -d ','); if [ "$(echo "$L > 30" | bc)" = "1" ]; then W=2; fi
P=bin/challengers/myo_tt_r10-p; C3=params/myo_tt_p2_r10_c3.txt
scratchpad/tt/ev1.sh f2_fh_champ $C3 $P scratchpad/tt/fh750_a.txt "" $W
for g in 0.97 1.03 1.06 1.10; do
  scratchpad/tt/ev1.sh f2_fh_g$g $C3 $P scratchpad/tt/fh750_a.txt "fh_gain=$g" $W
done
