#!/usr/bin/env bash
# gpu_sweep.sh — grid-sweep the GPU relay's hyperparameters via `flipfleet --gpu-only`.
#
# Each grid point runs the GPU (no CPU walkers) for $DUR seconds and records the best
# rank it reached. flipfleet writes flipfleet_status.txt every tick; we append the final
# line (which carries every hyperparameter + gpu_best + elapsed) to the results file.
#
# Customise the grids and duration via env vars, e.g.:
#   DUR=90 STEPS_GRID="200000 1000000" WTHR_GRID="5 7 9" ./gpu_sweep.sh
#
# Then inspect the winners:  sort -t= -k3 -n gpu_sweep_results.txt | head
set -u
cd "$(dirname "$0")"

DUR=${DUR:-60}                                    # seconds per grid point
OUT=${OUT:-gpu_sweep_results.txt}
STEPS_GRID=(${STEPS_GRID:-200000 500000 1000000}) # --gpu-steps
WTHR_GRID=(${WTHR_GRID:-5 7 9})                   # --gpu-wthr
MARGIN_GRID=(${MARGIN_GRID:-2 4 6})               # --gpu-margin
# (reseed / workq / wanderq / nw stay at defaults here; add loops to sweep them too)

: > "$OUT"
n=0
total=$(( ${#STEPS_GRID[@]} * ${#WTHR_GRID[@]} * ${#MARGIN_GRID[@]} ))
echo "sweeping $total points x ${DUR}s each (~$(( total * DUR / 60 )) min) -> $OUT"

for steps in "${STEPS_GRID[@]}"; do
  for wthr in "${WTHR_GRID[@]}"; do
    for margin in "${MARGIN_GRID[@]}"; do
      n=$((n + 1))
      pkill -x gpu_relay 2>/dev/null; sleep 0.4
      rm -f ff_gpu_seed.txt ff_gpu_best.txt ff_gpu_log.txt flipfleet_status.txt
      printf "[%d/%d] steps=%s wthr=%s margin=%s ... " "$n" "$total" "$steps" "$wthr" "$margin"
      timeout "$DUR" ./flipfleet --gpu-only \
        --gpu-steps "$steps" --gpu-wthr "$wthr" --gpu-margin "$margin" >/dev/null 2>&1
      line=$(cat flipfleet_status.txt 2>/dev/null || echo "gpu_best=NA")
      echo "$line" >> "$OUT"
      echo "$line" | grep -oE 'gpu_best=[0-9]+'
    done
  done
done

pkill -x gpu_relay 2>/dev/null
echo "=== done. best points (lowest gpu_best; 0/NA = no descent in ${DUR}s, excluded): ==="
grep -vE 'gpu_best=(NA|0)( |$)' "$OUT" | sort -t= -k3 -n | head
