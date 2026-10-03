#!/bin/bash
# One line per grip variant: the paddle's swivel in the hand (forehand / backhand, last 200 and 100 ms) and the solved count, on serves 98000-98099.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
row() { # name logdir rowsfile
  out=$(PROBE_SEEDS=98000:98100 .venv-myo/bin/python scratchpad/tt4/plane_probe.py $2 2>&1 | grep -E "^   (forehand|backhand) t_contact - (200|100) ms")
  f200=$(echo "$out" | grep "forehand t_contact - 200" | sed 's/.*turns median *\([0-9.]*\).*/\1/'); f100=$(echo "$out" | grep "forehand t_contact - 100" | sed 's/.*turns median *\([0-9.]*\).*/\1/')
  b200=$(echo "$out" | grep "backhand t_contact - 200" | sed 's/.*turns median *\([0-9.]*\).*/\1/'); b100=$(echo "$out" | grep "backhand t_contact - 100" | sed 's/.*turns median *\([0-9.]*\).*/\1/')
  sol=$(python3 -c "
import json
r=[json.loads(l) for l in open('$3')]
r=[x for x in r if 98000<=x.get('seed',0)<98100]
print(int(sum(1 for x in r if x.get('solved',0)>0)), int(sum(1 for x in r if x.get('hit',0)>0)), len(r))")
  printf "%-26s fore %5s / %5s   back %5s / %5s   solved %s (solved hit serves)\n" "$1" "$f200" "$f100" "$b200" "$b100" "$sol"
}
echo "swivel of the paddle in the hand, median deg over the last 200 ms / 100 ms before contact"
row "champion (grip_drive .12)" out/tt3/logs_o0 out/tt3/o0_A.jsonl
for v in gd04 gd08 gd15 gfull bhmax gmax gmaxbh; do [ -f out/tt4/grip_$v.jsonl ] && [ "$(wc -l < out/tt4/grip_$v.jsonl)" -ge 100 ] && row "$v" out/tt4/logs_grip_$v out/tt4/grip_$v.jsonl; done
