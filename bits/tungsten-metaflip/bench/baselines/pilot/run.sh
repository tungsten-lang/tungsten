#!/bin/bash
# run.sh ROOT JOBS_FILE [PARALLEL]: run the jobs of JOBS_FILE (one per line: ALGO TASK TARGET SEED BUDGET [VAR=VALUE ...])
# at most PARALLEL (default 4) at a time, in a seeded shuffled order, then collect ROOT/rows.tsv.
root=$1 jobs=$2 par=${3:-4}
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$root"
awk 'BEGIN { srand(20260930) } { printf "%.9f\t%s\n", rand(), $0 }' "$jobs" | sort -n | cut -f2- \
  | xargs -P "$par" -L 1 bash "$here/job.sh" "$root"
printf 'label\ttask\tseed\tbudget\ttarget\tstatus\thit\tbest_rank\ttool_cpu_to_hit\tflips_to_hit\tproposals_to_hit\tflips_total\ttree_cpu\twall_s\texact\tinstr_retired\twalks\tcycles\tload1\n' > "$root/rows.tsv"
find "$root" -name row.tsv | sort | xargs cat >> "$root/rows.tsv"
echo "$(($(wc -l < "$root/rows.tsv") - 1)) rows in $root/rows.tsv"
