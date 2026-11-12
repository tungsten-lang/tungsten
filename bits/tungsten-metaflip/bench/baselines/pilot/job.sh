#!/bin/bash
# One pilot job:  job.sh ROOT ALGO TASK TARGET SEED BUDGET [VAR=VALUE ...]
# Runs bench/baselines/adapters/ALGO the way metabench does (contract: bench/README.md section 3) in ROOT/<label>/TASK/SEED
# and writes row.tsv next to the adapter's result.json. The label is ALGO plus the VAR=VALUE settings.
root=$1 algo=$2 task=$3 target=$4 seed=$5 budget=$6
shift 6
here=$(cd "$(dirname "$0")" && pwd)
bench=$(cd "$here/../.." && pwd)
adapters=${MB_ADAPTERS:-$bench/baselines/adapters}
label=$algo
for kv in "$@"; do label="$label,$kv"; done
d=$root/$label/$task/$seed
mkdir -p "$d"
shape=${task%%@*}
n=${shape%%x*}; rest=${shape#*x}; m=${rest%%x*}; p=${rest#*x}
LC_ALL=C awk -v n="$n" -v m="$m" -v p="$p" -f "$bench/baselines/adapters/mfw-lib.awk" -f "$bench/baselines/adapters/std2mfw.awk" > "$d/start.mfw"
export MB_BENCH=$bench MB_TASK=$task MB_N=$n MB_M=$m MB_P=$p MB_TARGET=$target MB_START=standard MB_START_FILE=$d/start.mfw \
  MB_SEED=$seed MB_BUDGET_CPU_S=$budget MB_OUT=$d OMP_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
read -r _ _ _ _ MB_START_RANK < "$d/start.mfw"
export MB_START_RANK
for kv in "$@"; do export "$kv"; done
rm -f "$d/result.json" "$d/scheme.mfw" "$d/tree.times"
load1=$(sysctl -n vm.loadavg 2> /dev/null | awk '{ print $2 }')
start=$SECONDS
# the shell that runs the adapter reports the CPU time of its whole process tree with `times`
bash -c 'cd "$4"; "$1" "$2" "$3" "$5" "$4" > "$4/stdout.log" 2> "$4/stderr.log"; s=$?; times > "$4/tree.times"; exit $s' _ \
  "$adapters/$algo" "$task" "$seed" "$d" "$budget"
status=$?
wall=$((SECONDS - start))
tree=$(awk 'NR == 2 { for (i = 1; i <= NF; i++) { t = $i; sub(/s$/, "", t); split(t, a, "m"); s += a[1] * 60 + a[2] } printf "%.3f", s }' "$d/tree.times" 2> /dev/null)
exact=null
if [ -r "$d/scheme.mfw" ]; then
  if ruby "$bench/../tools/verify_tensor.rb" --shape "${n}x${m}x${p}" "$d/scheme.mfw" > "$d/verify.json" 2> "$d/verify.err"; then
    exact=$(jq -r '.[0].exact' "$d/verify.json")
  else
    exact=false
  fi
fi
if [ "$status" = 0 ] && [ -r "$d/result.json" ]; then
  jq -r --arg label "$label" --arg task "$task" --arg seed "$seed" --arg budget "$budget" --arg target "$target" --arg tree "$tree" \
    --arg wall "$wall" --arg exact "$exact" --arg load1 "${load1:-NA}" \
    '[$label, $task, $seed, $budget, $target, "ok", (.hit | tostring), (.best_rank | tostring),
      (if .hit then (.trace[-1][0] | tostring) else "NA" end), (.flips_to_hit // "NA" | tostring), (.proposals_to_hit // "NA" | tostring),
      (.flips_total | tostring), ($tree), ($wall), ($exact), (.instr_retired // "NA" | tostring), (.notes | capture("Walks started: (?<w>[0-9]+)").w // "NA"), (.cycles // "NA" | tostring), $load1] | @tsv' \
    "$d/result.json" > "$d/row.tsv"
else
  printf '%s\t%s\t%s\t%s\t%s\terror(%s)\tNA\tNA\tNA\tNA\tNA\tNA\t%s\t%s\t%s\tNA\tNA\tNA\t%s\n' "$label" "$task" "$seed" "$budget" "$target" "$status" "$tree" "$wall" "$exact" "${load1:-NA}" > "$d/row.tsv"
fi
