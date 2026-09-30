#!/bin/sh
# Adapter stand-in for spec/bench_runner_test.w: fake_adapter.sh MODE TASK SEED BUDGET OUTDIR
#   coin       hits on the seeds divisible by 3 with the rank-7 scheme of 2x2x2, else reports rank 8
#   liar-wrong claims a hit with a scheme that is not the matrix-multiplication tensor
#   liar-big   claims a hit with the rank-8 start scheme
#   late       finds the target only after the CPU budget is spent
#   spin       never stops (CPU bound)
#   hang       never stops (sleeping)
#   crash      exits with status 3
mode=$1
seed=$3
out=$5
here=$(cd "$(dirname "$0")" && pwd)
cd "$out" || exit 97
burn() {
  i=0
  while [ $i -lt "$1" ]; do i=$((i + 1)); done
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
    burn 600000
    cp "$here/rank7_2x2x2.mfw" scheme.mfw
    echo "$hit_json" > result.json ;;
  spin)
    while :; do :; done ;;
  hang)
    sleep 1000 ;;
  crash)
    exit 3 ;;
esac
