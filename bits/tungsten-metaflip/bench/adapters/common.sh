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

# mb_measure LOG CMD...: run CMD as the direct child of /usr/bin/time -l and set
# MB_INSTR, MB_CYCLES and MB_RSS_KB (empty when the platform does not report them).
# Returns the exit status of CMD.
mb_measure() {
  _mb_log=$1
  shift
  /usr/bin/time -l -o "$_mb_log" "$@"
  _mb_status=$?
  MB_INSTR=$(awk '/instructions retired/ { print $1; exit }' "$_mb_log" 2> /dev/null)
  MB_CYCLES=$(awk '/cycles elapsed/ { print $1; exit }' "$_mb_log" 2> /dev/null)
  MB_RSS_KB=$(awk '/maximum resident set size/ { printf "%d", $1 / 1024; exit }' "$_mb_log" 2> /dev/null)
  return $_mb_status
}

# mb_json_tail: the measured fields as JSON object members (no braces, no trailing comma).
mb_json_tail() {
  printf '"instr_retired": %s, "cycles": %s, "max_rss_kb": %s' \
    "${MB_INSTR:-null}" "${MB_CYCLES:-null}" "${MB_RSS_KB:-null}"
}
