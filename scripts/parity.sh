#!/usr/bin/env bash
# Cross-engine conformance suite.
#
# Every spec/parity/*_spec.w is a small deterministic program that prints
# values with `<<`. Each spec is run through every selected engine and the
# captured stdout+stderr+exit code must agree byte-for-byte (only trailing
# whitespace is stripped). A spec passes when all engines agree AND no
# output line starts with `FAIL`.
#
# A spec may declare an expected divergence with a header line
#     ## parity xfail <one-line reason>
# Such a spec is reported XFAIL (green) while the engines still disagree,
# and XPASS (a failure) once they agree — so spec/parity/DIVERGENCES.md
# cannot go stale silently. The ledger is required in the other direction
# too: an xfail spec with no row there is a FAIL, not an XFAIL.
#
# Engines (default comparison is interp vs compiled):
#   interp    bin/tungsten run --interpret  (native tree-walker,
#                                            compiler/lib/interpreter.w)
#   compiled  bin/tungsten compile + run    (WIRE -> LLVM -> native)
#   ruby      bin/tungsten --interpret      (Ruby tree-walker,
#                                            implementations/ruby; off by default)
#   nofree    compiled with TUNGSTEN_FREE=0 (no compiler-inserted frees)
#   noinfer   compiled with TUNGSTEN_PARAM_INFER=0 (no call-site param typing)
#
# Usage:
#   scripts/parity.sh                         # all specs, interp,compiled
#   scripts/parity.sh --files PATH...         # a subset (bare names resolve
#                                             # under spec/parity/)
#   scripts/parity.sh --engines interp,compiled,ruby
#   scripts/parity.sh --jobs 8                # parallel (default: ncpu-2)
#   scripts/parity.sh --verbose               # print every engine's output
#   scripts/parity.sh --keep                  # keep the work dir
#
# Exit status is non-zero on any FAIL or XPASS. The last line is always
#   parity: N pass, N xfail, N fail, N xpass
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="${TUNGSTEN:-"$ROOT/bin/tungsten"}"
COMPILER="$ROOT/bin/tungsten-compiler"
SPEC_DIR="$ROOT/spec/parity"
DEFAULT_ENGINES="interp,compiled"
ALL_ENGINES="interp compiled ruby nofree noinfer"

# Isolated incremental cache so the suite never disturbs build/cache/specs
# or a developer's default cache. An inherited TUNGSTEN_CACHE_DIR (the one
# scripts/test-specs.sh exports for its own lanes) is honoured only as a
# *parent*: parity gets its own subtree under it, never its slots.
# Compiled variants that change lowering get a cache of their own too: the
# irbin slot key does not encode these env switches, so sharing would let a
# plain-compiled artifact masquerade as the variant.
if [[ -n "${TUNGSTEN_PARITY_CACHE_DIR:-}" ]]; then
  PARITY_CACHE_ROOT="$TUNGSTEN_PARITY_CACHE_DIR"
elif [[ -n "${TUNGSTEN_CACHE_DIR:-}" ]]; then
  PARITY_CACHE_ROOT="$TUNGSTEN_CACHE_DIR/parity"
else
  PARITY_CACHE_ROOT="$ROOT/build/cache/parity"
fi

# The header comment block IS the help text: print it verbatim (minus the
# shebang and the leading "# ") and stop at the first line of code, so
# editing the header can never truncate --help.
usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' \
    "${BASH_SOURCE[0]}"
}

die() {
  echo "parity: $*" >&2
  exit 2
}

# ── engine runners ─────────────────────────────────────────────────────────
# Each writes the normalized transcript (stdout+stderr, trailing whitespace
# stripped, then an `exit=N` line) to $2. Tooling failures (the compile step
# itself failing) are written into the transcript so they diff loudly.

normalize() {
  sed -e 's/[[:space:]]*$//'
}

# An xfail spec must carry a row in the ledger (the `Spec` column of a
# DIVERGENCES.md table), so a divergence can never be parked behind a
# header with no explanation. Only enforced for specs that live in
# spec/parity — a one-off file passed with --files has no row to have.
LEDGER="$SPEC_DIR/DIVERGENCES.md"
ledger_has_row() {
  local name="$1"
  [[ -f "$LEDGER" ]] || return 1
  awk -F'|' -v want="$name.w" '
    /^\|/ && NF > 5 {
      cell = $3
      gsub(/^[ \t`]+|[ \t`]+$/, "", cell)
      if (cell == want) { found = 1; exit }
    }
    END { exit(found ? 0 : 1) }
  ' "$LEDGER"
}

engine_cache_dir() {
  case "$1" in
    interp|compiled|ruby) printf '%s\n' "$PARITY_CACHE_ROOT" ;;
    *) printf '%s/%s\n' "$PARITY_CACHE_ROOT" "$1" ;;
  esac
}

engine_env() {
  case "$1" in
    nofree)  printf 'TUNGSTEN_FREE=0\n' ;;
    noinfer) printf 'TUNGSTEN_PARAM_INFER=0\n' ;;
    *) ;;
  esac
}

run_engine() {
  local engine="$1" spec="$2" out="$3"
  local name cache bin status compile_log
  local -a env_prefix
  name="$(basename "${spec%.w}")"
  cache="$(engine_cache_dir "$engine")"
  mkdir -p "$cache/parity-bin"
  env_prefix=(env "TUNGSTEN_CACHE_DIR=$cache")
  local extra
  extra="$(engine_env "$engine")"
  [[ -n "$extra" ]] && env_prefix+=("$extra")

  case "$engine" in
    interp)
      set +e
      "${env_prefix[@]}" "$TUNGSTEN" run --interpret "$spec" 2>&1 | normalize >"$out"
      status=${PIPESTATUS[0]}
      set -e
      ;;
    ruby)
      set +e
      "${env_prefix[@]}" "$TUNGSTEN" --interpret "$spec" 2>&1 | normalize >"$out"
      status=${PIPESTATUS[0]}
      set -e
      ;;
    compiled|nofree|noinfer)
      # Stable output names keep the incremental cache reusable (a unique
      # -o would key a fresh irbin slot per run). A parity-only subdir keeps
      # them clear of test-specs.sh binaries with the same basename when
      # the cache is shared.
      bin="$cache/parity-bin/$name"
      compile_log="$out.compile"
      set +e
      "${env_prefix[@]}" "$TUNGSTEN" compile "$spec" --out "$bin" >"$compile_log" 2>&1
      status=$?
      set -e
      if [[ "$status" -ne 0 ]]; then
        {
          echo "parity: compile failed (exit $status) under engine $engine"
          normalize <"$compile_log"
        } >"$out"
        rm -f "$compile_log"
        echo "exit=compile-failed" >>"$out"
        return
      fi
      rm -f "$compile_log"
      set +e
      "${env_prefix[@]}" "$bin" 2>&1 | normalize >"$out"
      status=${PIPESTATUS[0]}
      set -e
      ;;
    *)
      die "unknown engine: $engine (known: $ALL_ENGINES)"
      ;;
  esac
  echo "exit=$status" >>"$out"
}

# ── worker entry ───────────────────────────────────────────────────────────
if [[ "${1:-}" == "--job" ]]; then
  [[ $# -eq 4 ]] || die "--job ENGINE SPEC RESULTS"
  engine="$2"; spec="$3"; results="$4"
  name="$(basename "${spec%.w}")"
  run_engine "$engine" "$spec" "$results/$name.$engine.out"
  exit 0
fi

# ── argument parsing ───────────────────────────────────────────────────────
engines_csv="$DEFAULT_ENGINES"
jobs="${JOBS:-auto}"
verbose=0
keep=0
work=""
files=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --files)
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do
        files+=("$1"); shift
      done
      ;;
    --engines) engines_csv="$2"; shift 2 ;;
    --engines=*) engines_csv="${1#--engines=}"; shift ;;
    --jobs) jobs="$2"; shift 2 ;;
    --jobs=*) jobs="${1#--jobs=}"; shift ;;
    --verbose|-v) verbose=1; shift ;;
    --keep) keep=1; shift ;;
    --work) work="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    --*) die "unknown option: $1 (see --help)" ;;
    *) files+=("$1"); shift ;;
  esac
done

if [[ "$jobs" == "auto" ]]; then
  jobs="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"
  jobs=$(( jobs - 2 ))
  (( jobs < 1 )) && jobs=1
fi
[[ "$jobs" =~ ^[0-9]+$ && "$jobs" -ge 1 ]] || die "--jobs expects a positive integer"

engines=()
IFS=',' read -r -a engines <<<"$engines_csv"
[[ ${#engines[@]} -ge 1 ]] || die "--engines needs at least one engine"
for e in "${engines[@]}"; do
  case " $ALL_ENGINES " in
    *" $e "*) ;;
    *) die "unknown engine: $e (known: $ALL_ENGINES)" ;;
  esac
done

if [[ ! -x "$COMPILER" ]]; then
  echo "bin/tungsten-compiler is missing; run bin/tungsten build first." >&2
  exit 1
fi

cd "$ROOT"

# Spec discovery: every spec/parity/*_spec.w on disk (tracked or not — the
# suite is the directory), or the --files list. Bare names resolve under
# spec/parity/ with or without the _spec.w suffix.
specs=()
if [[ ${#files[@]} -eq 0 ]]; then
  while IFS= read -r p; do
    [[ -n "$p" ]] && specs+=("$p")
  done < <(ls "$SPEC_DIR"/*_spec.w 2>/dev/null | LC_ALL=C sort)
else
  for f in "${files[@]}"; do
    if [[ -f "$f" ]]; then
      specs+=("$f")
    elif [[ -f "$SPEC_DIR/$f" ]]; then
      specs+=("$SPEC_DIR/$f")
    elif [[ -f "$SPEC_DIR/${f}_spec.w" ]]; then
      specs+=("$SPEC_DIR/${f}_spec.w")
    elif [[ -f "$SPEC_DIR/$f.w" ]]; then
      specs+=("$SPEC_DIR/$f.w")
    else
      die "no such spec: $f"
    fi
  done
fi
[[ ${#specs[@]} -ge 1 ]] || die "no specs found under $SPEC_DIR"

# Result names are basenames; two specs with the same basename would
# overwrite each other's transcripts.
dups="$(for s in "${specs[@]}"; do basename "${s%.w}"; done | LC_ALL=C sort | uniq -d)"
[[ -z "$dups" ]] || die "duplicate spec basenames: $dups"

if [[ -z "$work" ]]; then
  work="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-parity.XXXXXX")"
fi
results="$work/results"
mkdir -p "$results" "$PARITY_CACHE_ROOT"
cleanup() {
  if [[ "$keep" -eq 0 ]]; then
    rm -rf "$work"
  else
    echo "parity: work dir kept at $work"
  fi
}
trap cleanup EXIT

echo "parity: ${#specs[@]} specs x engines [${engines[*]}] jobs=$jobs cache=$PARITY_CACHE_ROOT"

# ── fan out ────────────────────────────────────────────────────────────────
# One job per (engine, spec). Spec paths never contain whitespace (they
# live in the repo), so xargs -L 1 word-splitting is safe.
{
  for e in "${engines[@]}"; do
    for s in "${specs[@]}"; do
      printf '%s %s %s\n' "$e" "$s" "$results"
    done
  done
} | xargs -P "$jobs" -L 1 "${BASH_SOURCE[0]}" --job

# ── aggregate in list order ────────────────────────────────────────────────
n_pass=0; n_xfail=0; n_fail=0; n_xpass=0
for spec in "${specs[@]}"; do
  name="$(basename "${spec%.w}")"
  xfail_reason="$(grep -m1 -E '^## parity xfail' "$spec" | sed -E 's/^## parity xfail[[:space:]]*//' || true)"
  is_xfail=0
  [[ -n "$xfail_reason" ]] && is_xfail=1
  if grep -q -E '^## parity xfail' "$spec" && [[ -z "$xfail_reason" ]]; then
    xfail_reason="(no reason given)"
    is_xfail=1
  fi

  first="${engines[0]}"
  base="$results/$name.$first.out"
  diverged=""
  fail_line=""
  missing=""
  for e in "${engines[@]}"; do
    out="$results/$name.$e.out"
    if [[ ! -f "$out" ]]; then
      missing="$e"
      break
    fi
    if grep -q -E '^FAIL' "$out"; then
      fail_line="${fail_line:+$fail_line,}$e"
    fi
    if [[ "$e" != "$first" ]] && ! cmp -s "$base" "$out"; then
      diverged="${diverged:+$diverged,}$e"
    fi
  done
  if [[ ${#engines[@]} -eq 1 ]]; then
    # Nothing to diff against: a non-zero exit is the only engine signal.
    if [[ -z "$missing" ]] && ! tail -n1 "$base" | grep -q -x 'exit=0'; then
      diverged="$first"
    fi
  fi

  if [[ -n "$missing" ]]; then
    echo "FAIL  [$name] no transcript for engine $missing"
    n_fail=$((n_fail + 1))
    continue
  fi

  if [[ -n "$fail_line" ]]; then
    echo "FAIL  [$name] output contains a FAIL line (engine: $fail_line)"
    for e in "${engines[@]}"; do
      echo "--- $e"
      sed 's/^/    /' "$results/$name.$e.out"
    done
    n_fail=$((n_fail + 1))
    continue
  fi

  if [[ -n "$diverged" ]]; then
    if [[ "$is_xfail" -eq 1 ]]; then
      if [[ "$(cd "$(dirname "$spec")" && pwd)" == "$SPEC_DIR" ]] && ! ledger_has_row "$name"; then
        echo "FAIL  [$name] '## parity xfail' with no row in spec/parity/DIVERGENCES.md"
        n_fail=$((n_fail + 1))
        continue
      fi
      echo "XFAIL [$name] $xfail_reason"
      n_xfail=$((n_xfail + 1))
      if [[ "$verbose" -eq 1 ]]; then
        for e in "${engines[@]}"; do
          [[ "$e" == "$first" ]] && continue
          diff -u --label "$first" --label "$e" "$base" "$results/$name.$e.out" | sed 's/^/    /' || true
        done
      fi
    else
      echo "FAIL  [$name] engines disagree: $first vs $diverged"
      for e in "${engines[@]}"; do
        [[ "$e" == "$first" ]] && continue
        diff -u --label "$first" --label "$e" "$base" "$results/$name.$e.out" | sed 's/^/    /' || true
      done
      n_fail=$((n_fail + 1))
    fi
  else
    if [[ "$is_xfail" -eq 1 ]]; then
      echo "XPASS [$name] engines now agree; drop the '## parity xfail' header and its DIVERGENCES.md row ($xfail_reason)"
      n_xpass=$((n_xpass + 1))
    else
      echo "PASS  [$name]"
      n_pass=$((n_pass + 1))
    fi
    if [[ "$verbose" -eq 1 ]]; then
      sed 's/^/    /' "$base"
    fi
  fi
done

echo "parity: $n_pass pass, $n_xfail xfail, $n_fail fail, $n_xpass xpass"
if [[ "$n_fail" -gt 0 || "$n_xpass" -gt 0 ]]; then
  exit 1
fi
exit 0
