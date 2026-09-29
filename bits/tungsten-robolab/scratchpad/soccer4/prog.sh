#!/bin/sh
grep "^{" "$1" | python3 -c "
import sys,json
for l in sys.stdin:
    d=json.loads(l); s=d['summ']; print(d['gen'], d['t'], d['best'], d['gen_best'], d['gen_mean'], d['sigma'], {k: s.get(k) for k in ('bal_s','bal_l','bal_r','stand_time','goal','goal_inside','n_steps','ap_best_stand','ball_speed') if k in s}, s.get('zones') if any(s.get('zones') or []) else '')
"
