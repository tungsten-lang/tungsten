#!/bin/sh
grep '^{' "$1" | python3 -c "
import sys,json
for l in sys.stdin:
    d=json.loads(l); s=d['summ']; print(d['gen'], d['t'], d['best'], d['gen_best'], d['gen_mean'], 'closed', s.get('walk_closed'), 'arr', s.get('walk_t_arrive'), 'stand', s.get('stand_time'), 'goal', s.get('goal'), d.get('x0_score',''))"
