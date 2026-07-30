#!/usr/bin/env bash
set -u

# UNKNOWN exits 0 per the SAT Competition convention (see README.md).
fail() {
  printf 'c error: %s\ns UNKNOWN\n' "$1"
  exit 0
}

if (( $# != 1 )); then
  fail "Parallel entrypoint expects: run-parallel.sh <instance.cnf>"
fi

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
solver="$script_dir/wassat"
instance="$1"

[[ -x "$solver" ]] || fail "competition binary is missing; run build.sh first"
# The solver parses flags anywhere in argv and has no "--" terminator.
case "$instance" in -*) fail "instance path must not begin with -";; esac
[[ -r "$instance" ]] || fail "cannot read input formula: $instance"

# The top-level trusted path inspects the formula before choosing its scout,
# preprocessing, CDCL-race, SLS, and exact-recognizer work. In particular it
# preserves cheap structure-specific wins that the explicit, always-
# preprocessed portfolio command can erase. Winning models are checked against
# the original CNF before they are rendered.
exec "$solver" "$instance" --fast
