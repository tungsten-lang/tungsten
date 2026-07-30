#!/usr/bin/env bash
set -u

# UNKNOWN exits 0 per the SAT Competition convention (see README.md).
fail() {
  printf 'c error: %s\ns UNKNOWN\n' "$1"
  exit 0
}

if (( $# != 2 )); then
  fail "Main entrypoint expects: run.sh <instance.cnf> <proof-directory>"
fi

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
solver="$script_dir/wassat"
instance="$1"
proof_directory="$2"

[[ -x "$solver" ]] || fail "competition binary is missing; run build.sh first"
# The solver parses flags anywhere in argv and has no "--" terminator.
case "$instance" in -*) fail "instance path must not begin with -";; esac
[[ -r "$instance" ]] || fail "cannot read input formula: $instance"
mkdir -p -- "$proof_directory" ||
  fail "cannot create proof directory: $proof_directory"

# The 2026 Main contract requires ASCII DRAT at exactly $2/proof.out while
# the verdict and any SAT model remain on stdout.
exec "$solver" "$instance" --drat "$proof_directory/proof.out"

