#!/bin/bash
# Seed the new 512-seed trial with F1, then challenge it with S6a (the arena's own paired test; --promote installs S6a only if it WINS).
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
T=sprint_top_speed_v4_beyond_fresh512
mkdir -p out/sprint6
{
echo "$(date '+%H:%M:%S') seed F1"
nice -n 5 .venv/bin/python playground/arena.py seed $T --params params/run_geary_v4_beyond_s5b.txt --controller bin/challengers/run_geary-s5-final --task run_v4 \
  --note "S5 chain F1 (RunGearYSkill; labelled BEYOND-HUMAN body variant, not a human profile): the baseline S6's rear-step gear is tested against; seeded by the main session 3 Oct 2026" --workers 6
echo "$(date '+%H:%M:%S') eval S6a"
nice -n 5 .venv/bin/python playground/arena.py eval $T --params params/run_gearz_v4_beyond_s6a.txt --controller bin/challengers/run_gearz-s6-final --task run_v4 \
  --note "S6a = F1 + a rear step for starts whose COM begins over the heel (RunGearZSkill, agent S6; labelled BEYOND-HUMAN body variant, not a human profile); every other start bit-identical to F1; selection 73 -> 51 falls of 1000" --workers 6 --promote
echo "$(date '+%H:%M:%S') DONE"
} 2>&1 | grep -v -i "warn\|logger" > out/sprint6/arena_s6.log
