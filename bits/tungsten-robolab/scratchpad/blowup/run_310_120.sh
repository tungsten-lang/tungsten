#!/bin/zsh
# The five-minute hold of the brake (champion of the 40-start _ng trial) on 120 fresh starts: soccer_single_leg_310_120_ng, seeds 96000-96119, 310 s, guarded.
# Waits for full310 shc (pid $1), then prefills the rollout cache in two halves at once (2 workers each = the 4-worker budget while the 5-min load average is < 30);
# then the arena `seed` (all rollouts cached) installs the brake as the trial's champion.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
PY=.venv-myo/bin/python
step() { echo "=== $(date '+%m/%d %H:%M:%S') $*"; }
while kill -0 $1 2>/dev/null; do sleep 5; done
L5=$(uptime | sed 's/.*load averages: //' | awk '{print $2}' | sed 's/,//')
W=2; (( L5 >= 30 )) && W=1     # coordinator's rule: 4 rollout workers in total while the 5-min load average is < 30, else 2
step "start (5-min load average $L5): $W workers per half"
$PY scratchpad/blowup/prefill_310_120.py shc --seeds 96000:96060 --workers $W > out/blowup/prefill_96000_96060.log 2>&1 &
$PY scratchpad/blowup/prefill_310_120.py shc --seeds 96060:96120 --workers $W > out/blowup/prefill_96060_96120.log 2>&1 &
wait
step seed
$PY scratchpad/blowup/arena_ng.py seed soccer_single_leg_310_120_ng --params params/myo_soccer_single_leg_310_shc.txt --controller bin/challengers/soccer6-p --workers 2 --note "ramp + shift capture-point brake (the soccer_single_leg_310_40_ng champion): the five-minute hold on 120 fresh starts, MuJoCo wrap-NaN nudged"
step done
