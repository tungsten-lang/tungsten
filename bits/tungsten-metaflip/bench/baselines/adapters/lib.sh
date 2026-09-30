# Shared code of the baseline adapters (km2022, km2024, tfg). Source it, do not execute it.
#
# Contract: bench/README.md, section 3:   adapter TASK_ID SEED BUDGET_CPU_S OUTDIR
# The harness exports MB_* and OMP_NUM_THREADS=1; the adapters also work without it (see bl_init).
#
# The harness charges an adapter for the CPU time of its whole process tree, so the wrapper is lean: builtins for
# the arithmetic and one awk per tool run for everything it reads back. The tool runs through mb_measure of
# adapters/common.sh (the harness's meter when MB_TOOL is set, else /usr/bin/time -l).

LC_ALL=C
export LC_ALL

case $0 in
  /*) bl_here=${0%/*} ;;
  */*) bl_here=$(cd "${0%/*}" && pwd) ;;
  *) bl_here=$(pwd) ;;
esac
MB_BENCH=${MB_BENCH:-$(cd "$bl_here/../.." && pwd)}
export MB_BENCH
[ -r "$MB_BENCH/adapters/common.sh" ] && . "$MB_BENCH/adapters/common.sh"
if ! command -v mb_measure > /dev/null 2>&1; then
  # standalone use without the harness helpers: the same measurement around /usr/bin/time -l
  mb_measure() {
    _mb_report=$1
    shift
    MB_CPU_S=
    /usr/bin/time -l -o "$_mb_report" "$@"
    _mb_status=$?
    MB_INSTR=$(awk '/instructions retired/ { print $1; exit }' "$_mb_report" 2> /dev/null)
    MB_CYCLES=$(awk '/cycles elapsed/ { print $1; exit }' "$_mb_report" 2> /dev/null)
    MB_RSS_KB=$(awk '/maximum resident set size/ { printf "%d", $1 / 1024; exit }' "$_mb_report" 2> /dev/null)
    return $_mb_status
  }
fi

# Directory with the programs built by ../build.sh.
MB_SOTA_BIN=${MB_SOTA_BIN:-$HOME/.tungsten/metaflip/experiments/record-hunt-20260926/work/sota/build/bin}

bl_die() { # status message
  _s=$1
  shift
  echo "$BL_NAME: $*" >&2
  exit "$_s"
}

# bl_us DECIMAL_SECONDS: BL_US = the same in whole microseconds.
bl_us() {
  case $1 in
    *.*)
      _i=${1%%.*}
      _f=${1#*.}000000
      _f=${_f%"${_f#??????}"}
      ;;
    *)
      _i=$1
      _f=000000
      ;;
  esac
  BL_US=$((${_i:-0} * 1000000 + 1$_f - 1000000))
}

# bl_sec MICROSECONDS: BL_SEC = decimal seconds with six digits.
bl_sec() {
  _f=$((1000000 + $1 % 1000000))
  BL_SEC=$(($1 / 1000000)).${_f#1}
}

# bl_init NAME TASK_ID SEED BUDGET_CPU_S OUTDIR: parse the contract and leave the shell in OUTDIR.
# Sets BL_TASK BL_SEED BL_BUDGET BL_OUT BL_N BL_M BL_P BL_TARGET BL_START BL_START_RANK and the run totals.
bl_init() {
  BL_NAME=$1
  [ $# -eq 5 ] || bl_die 2 "usage: $BL_NAME TASK_ID SEED BUDGET_CPU_S OUTDIR"
  BL_TASK=$2
  BL_SEED=$3
  BL_BUDGET=$4
  BL_OUT=$5
  [ -d "$BL_OUT" ] || bl_die 2 "OUTDIR $BL_OUT does not exist"
  cd "$BL_OUT" || bl_die 2 "cannot enter $BL_OUT"
  BL_OUT=$(pwd)
  case $BL_SEED in '' | *[!0-9]*) bl_die 2 "SEED must be a non-negative integer" ;; esac
  bl_us "$BL_BUDGET"
  BL_BUDGET_US=$BL_US

  _shape=${BL_TASK%%@*}
  BL_N=${MB_N:-${_shape%%x*}}
  _rest=${_shape#*x}
  BL_M=${MB_M:-${_rest%%x*}}
  BL_P=${MB_P:-${_rest#*x}}
  case "$BL_N$BL_M$BL_P" in '' | *[!0-9]*) bl_die 2 "bad task id $BL_TASK" ;; esac

  BL_TARGET=${MB_TARGET:-${TARGET_RANK:-0}}

  BL_START=${MB_START_FILE:-$BL_OUT/start.mfw}
  if [ ! -r "$BL_START" ]; then
    case $BL_TASK in
      *@*)
        BL_START=$(mb_seed_path "${BL_TASK#*@}" 2> /dev/null)
        [ -r "$BL_START" ] || bl_die 2 "no start scheme for $BL_TASK (MB_START_FILE, start.mfw, seeds.tsv)"
        ;;
      *)
        BL_START=$BL_OUT/start.mfw
        awk -v n="$BL_N" -v m="$BL_M" -v p="$BL_P" -f "$bl_here/mfw-lib.awk" -f "$bl_here/std2mfw.awk" > "$BL_START"
        ;;
    esac
  fi
  read -r _magic _n _m _p BL_START_RANK < "$BL_START"
  [ "$_magic" = MFW1 ] || bl_die 2 "$BL_START is not an MFW1 file"

  # CPU still available to the program: when the harness meters the program (MB_TOOL, cpu_s_tool of result.json) the runs are
  # priced by the program alone and only its shutdown needs a reserve; otherwise the whole process tree is priced and the
  # reserve covers the conversion after a hit, which grows with the rank. Microseconds.
  if [ -n "${MB_TOOL:-}" ] && [ -x "$MB_TOOL" ]; then
    BL_METERED=1
    BL_RESERVE_US=10000
  else
    BL_METERED=0
    BL_RESERVE_US=$((30000 + BL_START_RANK * 200))
  fi

  BL_TRACE=$BL_OUT/trace.tsv
  : > "$BL_TRACE"
  BL_CPU=0 BL_PROP=0 BL_FLIPS=0 BL_EXPANDS=0 BL_BEST=$BL_START_RANK BL_WALKS=0 BL_ERRORS=0 BL_TIMEOUT=0
  BL_INSTR=0 BL_CYCLES=0 BL_RSS=0 BL_MEASURED=1 BL_TOOLCPU=0 BL_TOOLCPU_OK=1
  BL_REM_US=$((BL_BUDGET_US - BL_RESERVE_US))
  BL_HIT=false BL_SCHEME=
}

# bl_seed K: the seed of walk K, SEED + 1000003 K reduced into 1 .. 2^31-2 (walk 0 uses SEED itself). Sets BL_WALK_SEED.
bl_seed() {
  BL_WALK_SEED=$(((BL_SEED + $1 * 1000003) % 2147483646))
  [ "$BL_WALK_SEED" -gt 0 ] || BL_WALK_SEED=1
}

# bl_run REPORT CMD...: run the tool through mb_measure (which sets MB_INSTR, MB_CYCLES, MB_RSS_KB and, with the
# harness's meter, MB_CPU_S), then store the shell's own accounting (the CPU used by everything so far) in
# ${REPORT}.times for bl_merge.
bl_run() {
  _log=$1
  shift
  MB_INSTR= MB_CYCLES= MB_RSS_KB= MB_CPU_S=
  mb_measure "$_log" "$@"
  _status=$?
  times > "$_log.times"
  return $_status
}

# bl_merge STDERR_FILE REPORT PREFIX: fold one tool run into the totals (PREFIX is KM or TFG).
# The tool prints  PREFIXTRACE / PREFIXDONE / PREFIXTIMEOUT  lines with cpu=, flips=, rank= (and attempts=);
# new global bests are appended to the trace. Updates BL_CPU BL_PROP BL_FLIPS BL_BEST BL_TIMEOUT BL_INSTR BL_CYCLES
# BL_RSS and BL_REM_US (microseconds of CPU still available to the tool).
bl_merge() {
  awk -v prefix="$3" -v errf="$1" -v timef="$2" -v timesf="$2.times" -v cpu0="$BL_CPU" -v prop0="$BL_PROP" \
    -v flips0="$BL_FLIPS" -v exp0="$BL_EXPANDS" -v best="$BL_BEST" -v trace="$BL_TRACE" -v budget="$BL_BUDGET_US" -v reserve="$BL_RESERVE_US" \
    -v instr0="$BL_INSTR" -v cycles0="$BL_CYCLES" -v rss0="$BL_RSS" -v walks0="$BL_WALKS" -v toolcpu0="$BL_TOOLCPU" -v cpu_known0="$BL_TOOLCPU_OK" \
    -v call_instr="$MB_INSTR" -v call_cycles="$MB_CYCLES" -v call_rss="$MB_RSS_KB" -v call_cpu="$MB_CPU_S" -v metered="$BL_METERED" 'BEGIN {
      walks = 1
      while ((getline line < errf) > 0) {
        n = split(line, f, " ")
        tag = f[1]
        if (tag != prefix "TRACE" && tag != prefix "DONE" && tag != prefix "TIMEOUT") continue
        delete v
        for (i = 2; i <= n; i++) { p = index(f[i], "="); if (p) v[substr(f[i], 1, p - 1)] = substr(f[i], p + 1) + 0 }
        if (!("cpu" in v)) continue
        lastc = v["cpu"]; lastf = v["flips"]; lastp = ("attempts" in v) ? v["attempts"] : v["flips"]; laste = ("expands" in v) ? v["expands"] : 0
        if (tag == prefix "TIMEOUT") timeout = 1
        if ("walks" in v) walks = v["walks"]
        if (tag == prefix "TRACE" && v["rank"] < best) {
          best = v["rank"]
          printf "%.6f\t%.0f\t%.0f\t%d\n", cpu0 + v["cpu"], prop0 + lastp, flips0 + v["flips"], best >> trace
        }
        if (tag != prefix "TRACE" && ("rank" in v) && v["rank"] < best) best = v["rank"]
      }
      instr = instr0; cycles = cycles0; rss = rss0; measured = 1; toolcpu = toolcpu0
      if (call_instr == "") measured = 0; else { instr += call_instr; cycles += call_cycles }
      if (call_rss != "" && call_rss + 0 > rss) rss = call_rss + 0
      cpu_known = cpu_known0
      if (call_cpu != "") toolcpu += call_cpu; else cpu_known = 0
      while ((getline line < timesf) > 0) {
        n = split(line, f, " ")
        for (i = 1; i <= n; i++) { t = f[i]; sub(/s$/, "", t); split(t, a, "m"); used += a[1] * 60 + a[2] }
      }
      if (metered && cpu_known) rem = budget - toolcpu * 1000000 - reserve
      else rem = budget - used * 1000000 - reserve
      if (rem < 0) rem = 0
      printf "BL_CPU=%.6f BL_PROP=%.0f BL_FLIPS=%.0f BL_EXPANDS=%.0f BL_BEST=%d BL_TIMEOUT=%d BL_INSTR=%.0f BL_CYCLES=%.0f BL_RSS=%d BL_MEASURED=%d BL_REM_US=%.0f BL_WALKS=%d BL_TOOLCPU=%.6f BL_TOOLCPU_OK=%d\n", \
        cpu0 + lastc, prop0 + lastp, flips0 + lastf, exp0 + laste, best, timeout + 0, instr, cycles, rss, measured, rem, walks0 + walks, toolcpu, cpu_known > (timef ".state")
    }'
  . "$2.state"
}

# bl_finish TOOL TOOL_VERSION NOTES: write result.json; scheme.mfw must already be in place when BL_HIT is true.
bl_finish() {
  _sha=
  if [ -r "$BL_OUT/scheme.mfw" ]; then
    if command -v sha256sum > /dev/null 2>&1; then _sha=$(sha256sum "$BL_OUT/scheme.mfw"); else _sha=$(shasum -a 256 "$BL_OUT/scheme.mfw"); fi
    _sha=${_sha%% *}
  fi
  awk -F'\t' -v hit="$BL_HIT" -v best="$BL_BEST" -v prop="$BL_PROP" -v flips="$BL_FLIPS" -v sha="$_sha" \
    -v tool="$1" -v version="$2" -v notes="$3" \
    -v instr="$BL_INSTR" -v cycles="$BL_CYCLES" -v rss="$BL_RSS" -v measured="$BL_MEASURED" -v toolcpu="$BL_TOOLCPU" -v have_cpu="$BL_TOOLCPU_OK" '
    function q(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return "\"" s "\"" }
    { tr = tr (NR > 1 ? ", " : "") "[" $1 ", " $2 ", " $3 ", " $4 "]" }
    END {
      ok = (hit == "true")
      printf "{\"schema\": 1, \"hit\": %s, \"best_rank\": %d,\n", hit, best
      printf " \"proposals_total\": %.0f, \"proposals_to_hit\": %s,\n", prop, (ok ? sprintf("%.0f", prop) : "null")
      printf " \"flips_total\": %.0f, \"flips_to_hit\": %s,\n", flips, (ok ? sprintf("%.0f", flips) : "null")
      printf " \"trace\": [%s],\n", tr
      printf " \"scheme_sha256\": %s,\n", (sha == "" ? "null" : "\"" sha "\"")
      if (have_cpu == "1") printf " \"cpu_s_tool\": %.6f,", toolcpu
      else printf " \"cpu_s_tool\": null,"
      if (measured) printf " \"instr_retired\": %.0f, \"cycles\": %.0f, \"max_rss_kb\": %d,\n", instr, cycles, rss
      else printf " \"instr_retired\": null, \"cycles\": null, \"max_rss_kb\": null,\n"
      printf " \"tool\": %s, \"tool_version\": %s,\n \"notes\": %s}\n", q(tool), q(version), q(notes)
    }' "$BL_TRACE" > "$BL_OUT/result.json.tmp" && mv "$BL_OUT/result.json.tmp" "$BL_OUT/result.json"
}
