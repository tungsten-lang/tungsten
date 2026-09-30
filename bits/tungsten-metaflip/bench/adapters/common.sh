# Shell helpers for metabench adapters. Source from an adapter:
#   . "${MB_BENCH:-$(cd "$(dirname "$0")/.." && pwd)}/adapters/common.sh"
# The contract is described in bench/README.md, section 3.

MB_BENCH=${MB_BENCH:-$(cd "$(dirname "${BASH_SOURCE:-$0}")/.." && pwd)}

# mb_task_field ID FIELD: value of a column of tasks.tsv (the first non-comment line names the columns).
mb_task_field() {
  awk -F'\t' -v id="$1" -v field="$2" '
    /^#/ || NF == 0 { next }
    !have_header { for (i = 1; i <= NF; i++) col[$i] = i; have_header = 1; next }
    $1 == id { print $(col[field]); exit }' "$MB_BENCH/tasks.tsv"
}

# mb_seed_path NAME: absolute path of a named seed scheme of seeds.tsv.
mb_seed_path() {
  awk -F'\t' -v name="$1" -v bench="$MB_BENCH" '
    /^#/ || NF == 0 { next }
    !have_header { for (i = 1; i <= NF; i++) col[$i] = i; have_header = 1; next }
    $1 == name { f = $(col["file"]); print (substr(f, 1, 1) == "/" ? f : bench "/" f); exit }' "$MB_BENCH/seeds.tsv"
}

# mb_measure REPORT CMD...: run CMD as the measured section of the run. CMD is a child of
# `$MB_TOOL exec` (the harness), which meters its CPU time exactly, kills its process group
# at 1.05 x budget + 0.05 CPU seconds, and writes a JSON report to REPORT. Sets MB_CPU_S (CPU
# of CMD and its descendants), MB_INSTR and MB_CYCLES (retired instructions and cycles of the
# CMD process), MB_RSS_KB (peak resident set); empty when unknown. Returns the exit status of
# CMD. Without $MB_TOOL, /usr/bin/time -l gives the instructions, cycles and resident set.
mb_measure() {
  _mb_report=$1
  shift
  MB_CPU_S=
  if [ -n "${MB_TOOL:-}" ] && [ -x "$MB_TOOL" ]; then
    _mb_limit=$(awk -v b="${MB_BUDGET_CPU_S:-0}" 'BEGIN { if (b > 0) printf "%.3f", b * 1.05 + 0.05; else print 0 }')
    "$MB_TOOL" exec --report "$_mb_report" --kill-after "$_mb_limit" -- "$@"
    _mb_status=$?
    MB_CPU_S=$(sed -n 's/.*"cpu_s":\([0-9.]*\).*/\1/p' "$_mb_report" 2> /dev/null)
    MB_INSTR=$(sed -n 's/.*"instr_retired":\([0-9]*\).*/\1/p' "$_mb_report" 2> /dev/null)
    MB_CYCLES=$(sed -n 's/.*"cycles":\([0-9]*\).*/\1/p' "$_mb_report" 2> /dev/null)
    MB_RSS_KB=$(sed -n 's/.*"max_rss_kb":\([0-9]*\).*/\1/p' "$_mb_report" 2> /dev/null)
  else
    /usr/bin/time -l -o "$_mb_report" "$@"
    _mb_status=$?
    MB_INSTR=$(awk '/instructions retired/ { print $1; exit }' "$_mb_report" 2> /dev/null)
    MB_CYCLES=$(awk '/cycles elapsed/ { print $1; exit }' "$_mb_report" 2> /dev/null)
    MB_RSS_KB=$(awk '/maximum resident set size/ { printf "%d", $1 / 1024; exit }' "$_mb_report" 2> /dev/null)
  fi
  return $_mb_status
}

# mb_json_tail: the measured fields as JSON object members (no braces, no trailing comma).
mb_json_tail() {
  printf '"cpu_s_tool": %s, "instr_retired": %s, "cycles": %s, "max_rss_kb": %s' \
    "${MB_CPU_S:-null}" "${MB_INSTR:-null}" "${MB_CYCLES:-null}" "${MB_RSS_KB:-null}"
}
