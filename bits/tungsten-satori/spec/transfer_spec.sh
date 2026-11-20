#!/bin/sh
# Run with the path to a built Satori executable.
set -eu
satori=${1:?pass the Satori executable}
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
printf 'p cnf 2 1\n1 2 0\n' >"$dir/input"
printf 'p cnf 2 3\n1 0\n2 0\n-1 2 0\n' >"$dir/witness"
printf '4 0 3 0\n' >"$dir/proof"
"$satori" emit-transfer "$dir/input" "$dir/witness" "$dir/miter"
printf 'p cnf 2 3\n1 2 0\n1 0\n0\n' >"$dir/expected"
cmp "$dir/expected" "$dir/miter"
"$satori" check-transfer "$dir/input" "$dir/witness" "$dir/proof"
reject() {
  if "$satori" check-transfer "$dir/input" "$dir/witness" "$dir/proof"; then
    echo "unexpectedly accepted $1" >&2
    exit 1
  fi
}
printf '4 0 1 0\n' >"$dir/proof"
reject 'invalid proof'
printf '4 0 3 0\n' >"$dir/proof"
printf 'p cnf 2 3\n1 0\n0\n-1 0\n' >"$dir/witness"
reject 'transfer violating the original formula'
printf 'p cnf 2 3\n1 0\n-2 0\n-1 2 0\n' >"$dir/witness"
reject 'transfer missing its target'
printf 'p cnf 2 3\n1 0\n2 0\n2 0\n' >"$dir/witness"
reject 'transfer remaining in the source'
printf 'p cnf 2 3\n1 0\n2 0\n2 -2 0\n' >"$dir/witness"
reject 'conflicting substitution'
printf 'p cnf 3 3\n1 0\n2 0\n-1 2 0\n' >"$dir/witness"
reject 'mismatched witness domain'
