#!/bin/sh
# Main-arena cross-evaluation of Codex's newer frozen contenders (approved by Erik 9/29).
cd /Users/erik/tungsten/bits/tungsten-robolab
J=bin/challengers/codex-jump_mean_refine_tcn; JP=params/codex/search_jump_robust_legal_r7.txt
D=bin/challengers/codex-dribble_catch_tcn;   DP=params/codex/dribble_crossover_25_r9.txt
NJ="gpt: jump mean-refine tcn, round 7 robustness champion (Codex, worktree robolab-challengers; approved by Erik 9/29)"
ND="gpt: dribble catch tcn, round 9 crossover champion (Codex, worktree robolab-challengers; approved by Erik 9/29)"
run() {
  echo "== $1 $(date)"
  .venv/bin/python playground/arena.py eval "$1" --params "$2" --controller "$3" --note "$4" --workers 3 --promote
  echo "== done $1 rc=$? $(date)"
}
run search_jump_robust_legal "$JP" "$J" "$NJ"
run search_jump_legal        "$JP" "$J" "$NJ (on the legal-distance trial)"
run dribble_crossover_25     "$DP" "$D" "$ND"
run dribble_crossover        "$DP" "$D" "$ND (10-start trial)"
run dribble_arms_only        "$DP" "$D" "$ND (trunk-share trial)"
echo "ALL DONE $(date)"
