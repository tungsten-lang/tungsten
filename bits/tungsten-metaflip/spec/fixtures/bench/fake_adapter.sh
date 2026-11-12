#!/bin/sh
# Adapter stand-in for spec/bench_runner_test.w: fake_adapter.sh MODE TASK SEED BUDGET OUTDIR
#   coin       hits on the seeds divisible by 3 with the rank-7 scheme of 2x2x2, else reports rank 8
#   liar-wrong claims a hit with a scheme that is not the matrix-multiplication tensor
#   liar-big   claims a hit with the rank-8 start scheme
#   late       finds the target only after the CPU budget is spent
#   spin       never stops (CPU bound)
#   hang       never stops (sleeping)
#   crash      exits with status 3
#
# `late` is calibrated in CPU time, not in loop iterations: it burns until this
# shell has itself used 0.3 CPU-seconds more than the budget (rounded up to a
# whole second), so it is over the budget and 1.7 CPU-seconds short of the
# runner's `ulimit -t` (budget rounded up, plus 2) on a machine of any speed
# and under any load.
mode=$1
seed=$3
budget=$4
out=$5
here=$(cd "$(dirname "$0")" && pwd)
cd "$out" || exit 97

# Sets CPU_CS to the CPU time (user + system) this shell has used, in
# centiseconds. `times` has to run in this shell (a $(...) subshell would
# report its own, fresh counters), so its output goes through a file. The
# first line is `<min>m<sec>.<frac>s <min>m<sec>.<frac>s` in bash, dash, zsh
# and busybox ash; anything else (ksh prints one labelled time per line) ends
# the adapter with status 96 rather than with a wrong burn.
cpu_cs() {
  times > .fake_adapter_times || exit 96
  read -r cpu_user cpu_sys < .fake_adapter_times || exit 96
  CPU_CS=0
  for cpu_word in "$cpu_user" "$cpu_sys"; do
    case $cpu_word in
      *[0-9]m[0-9]*s) ;;
      *) exit 96 ;;
    esac
    cpu_min=${cpu_word%%m*}
    cpu_rest=${cpu_word#*m}
    cpu_rest=${cpu_rest%s}
    cpu_sec=${cpu_rest%%[.,]*}
    cpu_frac=00
    case $cpu_rest in
      *[.,]*) cpu_frac=${cpu_rest#*[.,]}00 ;;
    esac
    cpu_frac=${cpu_frac%"${cpu_frac#??}"}
    # A leading zero would make the shell read the number as octal.
    while [ "${#cpu_min}" -gt 1 ] && [ "${cpu_min#0}" != "$cpu_min" ]; do cpu_min=${cpu_min#0}; done
    while [ "${#cpu_sec}" -gt 1 ] && [ "${cpu_sec#0}" != "$cpu_sec" ]; do cpu_sec=${cpu_sec#0}; done
    CPU_CS=$((CPU_CS + cpu_min * 6000 + cpu_sec * 100 + 1$cpu_frac - 100))
  done
}

# Burns CPU in this shell until it has used $1 centiseconds in total.
burn_cpu() {
  cpu_cs
  while [ "$CPU_CS" -lt "$1" ]; do
    i=0
    while [ $i -lt 2000 ]; do i=$((i + 1)); done
    cpu_cs
  done
  rm -f .fake_adapter_times
}

# A fixed, short loop: enough for a run to report a nonzero CPU time.
burn() {
  i=0
  while [ $i -lt "$1" ]; do i=$((i + 1)); done
}

# Sets BUDGET_CS to the budget in centiseconds, rounded up to a whole second.
budget_cs() {
  BUDGET_CS=${budget%%.*}
  case $budget in
    *.*[1-9]*) BUDGET_CS=$((BUDGET_CS + 1)) ;;
  esac
  BUDGET_CS=$((BUDGET_CS * 100))
}
hit_json='{"hit": true, "best_rank": 7, "proposals_total": 100, "proposals_to_hit": 100, "flips_total": 60, "flips_to_hit": 60, "trace": [[0.001, 10, 8, 7]], "tool": "fake"}'
case $mode in
  coin)
    burn 3000
    if [ $((seed % 3)) -eq 0 ]; then
      cp "$here/rank7_2x2x2.mfw" scheme.mfw
      echo "$hit_json" > result.json
    else
      echo '{"hit": false, "best_rank": 8, "proposals_total": 500, "flips_total": 300, "trace": [], "tool": "fake"}' > result.json
    fi ;;
  liar-wrong)
    sed 's/^1 f 2$/1 f 3/' "$here/rank7_2x2x2.mfw" > scheme.mfw
    echo "$hit_json" > result.json ;;
  liar-big)
    cp start.mfw scheme.mfw
    echo "$hit_json" > result.json ;;
  late)
    budget_cs
    burn_cpu $((BUDGET_CS + 30))
    cp "$here/rank7_2x2x2.mfw" scheme.mfw
    echo "$hit_json" > result.json ;;
  spin)
    while :; do :; done ;;
  hang)
    sleep 1000 ;;
  crash)
    exit 3 ;;
esac
