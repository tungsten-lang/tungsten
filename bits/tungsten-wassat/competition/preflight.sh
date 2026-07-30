#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
sat_instance=""
unsat_instance=""

usage() {
  cat <<'EOF'
Usage: preflight.sh [--sat SAT.cnf] [--unsat UNSAT.cnf]

Build Wassat, exercise Main and Parallel entrypoints on known SAT and UNSAT
instances, validate competition stdout and SAT models, and check Main's ASCII
DRAT proof. DRAT_TRIM is required. CAKE_LPR is used when available.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --sat)
      (( $# >= 2 )) || { usage >&2; exit 2; }
      sat_instance="$2"
      shift 2
      ;;
    --unsat)
      (( $# >= 2 )) || { usage >&2; exit 2; }
      unsat_instance="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

command -v python3 >/dev/null 2>&1 ||
  { echo "preflight requires python3" >&2; exit 1; }

drat_trim="${DRAT_TRIM:-}"
if [[ -z "$drat_trim" ]]; then
  drat_trim="$(command -v drat-trim 2>/dev/null || true)"
fi
if [[ -z "$drat_trim" || ! -x "$drat_trim" ]]; then
  echo "preflight requires drat-trim (set DRAT_TRIM=/path/to/drat-trim)" >&2
  exit 1
fi

cake_lpr="${CAKE_LPR:-}"
if [[ -z "$cake_lpr" ]]; then
  cake_lpr="$(command -v cake_lpr 2>/dev/null || true)"
fi
if [[ -n "$cake_lpr" && ! -x "$cake_lpr" ]]; then
  echo "CAKE_LPR is not executable: $cake_lpr" >&2
  exit 1
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/wassat-competition-preflight.XXXXXX")"
cleanup() {
  case "$work" in
    */wassat-competition-preflight.*) rm -rf -- "$work" ;;
  esac
}
trap cleanup EXIT HUP INT TERM

if [[ -z "$sat_instance" || -z "$unsat_instance" ]]; then
  generated_sat="$work/local-sat.cnf"
  generated_unsat="$work/local-unsat.cnf"
  python3 - "$generated_sat" "$generated_unsat" <<'PY'
from pathlib import Path
import sys

sat = Path(sys.argv[1])
unsat = Path(sys.argv[2])

# Long enough to force multiple competition value lines, but still trivial.
nvars = 1500
sat.write_text(
    f"p cnf {nvars} {nvars}\n"
    + "".join(f"{variable} 0\n" for variable in range(1, nvars + 1)),
    encoding="ascii",
)

# Pigeonhole principle PHP(5,4): small, UNSAT, and nontrivial enough to emit
# an actual DRAT derivation rather than relying on malformed or empty input.
pigeons, holes = 5, 4
clauses = []
variable = lambda pigeon, hole: pigeon * holes + hole + 1
for pigeon in range(pigeons):
    clauses.append([variable(pigeon, hole) for hole in range(holes)])
for hole in range(holes):
    for left in range(pigeons):
        for right in range(left + 1, pigeons):
            clauses.append([-variable(left, hole), -variable(right, hole)])
unsat.write_text(
    f"p cnf {pigeons * holes} {len(clauses)}\n"
    + "".join(" ".join(map(str, clause)) + " 0\n" for clause in clauses),
    encoding="ascii",
)
PY
  [[ -n "$sat_instance" ]] || sat_instance="$generated_sat"
  [[ -n "$unsat_instance" ]] || unsat_instance="$generated_unsat"
fi

[[ -r "$sat_instance" ]] || { echo "cannot read SAT instance: $sat_instance" >&2; exit 1; }
[[ -r "$unsat_instance" ]] || { echo "cannot read UNSAT instance: $unsat_instance" >&2; exit 1; }

"$script_dir/build.sh"

run_and_check() {
  local mode="$1"
  local expected="$2"
  local instance="$3"
  local expected_name
  case "$expected" in
    SAT) expected_name="sat" ;;
    UNSAT) expected_name="unsat" ;;
    *) echo "internal preflight verdict error: $expected" >&2; exit 2 ;;
  esac
  local output="$work/$mode-$expected_name.out"
  local errors="$work/$mode-$expected_name.err"
  local proof_dir="$work/$mode-$expected_name-proof"
  local status

  mkdir -p -- "$proof_dir"
  set +e
  if [[ "$mode" == "main" ]]; then
    "$script_dir/run-main.sh" "$instance" "$proof_dir" >"$output" 2>"$errors"
    status=$?
  else
    "$script_dir/run-parallel.sh" "$instance" >"$output" 2>"$errors"
    status=$?
  fi
  set -e

  if ! python3 "$script_dir/check_output.py" \
      "$instance" "$output" "$expected" "$status"; then
    echo "--- $mode $expected stdout ---" >&2
    sed -n '1,120p' "$output" >&2
    echo "--- $mode $expected stderr ---" >&2
    sed -n '1,120p' "$errors" >&2
    exit 1
  fi
  printf 'PASS %-8s %s output/model/exit\n' "$mode" "$expected"
}

run_and_check main SAT "$sat_instance"
run_and_check main UNSAT "$unsat_instance"
run_and_check parallel SAT "$sat_instance"
run_and_check parallel UNSAT "$unsat_instance"

proof="$work/main-unsat-proof/proof.out"
if [[ ! -s "$proof" ]]; then
  echo "Main UNSAT did not create a nonempty proof.out" >&2
  exit 1
fi
python3 - "$proof" <<'PY'
from pathlib import Path
import sys

proof = Path(sys.argv[1]).read_bytes()
try:
    proof.decode("ascii")
except UnicodeDecodeError as error:
    raise SystemExit(f"proof.out is not ASCII DRAT: {error}")
if not proof.rstrip().endswith(b"0"):
    raise SystemExit("proof.out does not end in a zero-terminated DRAT step")
PY

"$drat_trim" "$unsat_instance" "$proof" -I \
  >"$work/drat-trim.out" 2>"$work/drat-trim.err"
if ! grep -q '^s VERIFIED' "$work/drat-trim.out"; then
  echo "drat-trim did not report a verified proof" >&2
  sed -n '1,80p' "$work/drat-trim.out" >&2
  sed -n '1,80p' "$work/drat-trim.err" >&2
  exit 1
fi
printf 'PASS drat-trim accepted Main proof.out\n'

if [[ -n "$cake_lpr" ]]; then
  lrat="$work/main-unsat.lrat"
  "$drat_trim" "$unsat_instance" "$proof" -I -L "$lrat" \
    >"$work/drat-to-lrat.out" 2>"$work/drat-to-lrat.err"
  "$cake_lpr" "$unsat_instance" "$lrat" \
    >"$work/cake-lpr.out" 2>"$work/cake-lpr.err"
  if ! grep -qx 's VERIFIED UNSAT' "$work/cake-lpr.out"; then
    echo "cake_lpr did not report verified UNSAT" >&2
    sed -n '1,80p' "$work/cake-lpr.out" >&2
    sed -n '1,80p' "$work/cake-lpr.err" >&2
    exit 1
  fi
  printf 'PASS drat-trim -L + cake_lpr formally verified Main proof.out\n'
else
  printf 'SKIP cake_lpr not found; drat-trim compatibility was checked\n'
fi

printf 'PASS local competition preflight on %s/%s\n' "$(uname -s)" "$(uname -m)"
printf 'NOTE this does not establish Linux, NHR-container, or AWS acceptance\n'
