#!/bin/sh
# collect.sh ROOT OUTDIR SET...: copy ROOT/SET/rows.tsv to OUTDIR/SET-rows.tsv and write OUTDIR/SET-summary.tsv (summarize.sh).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$1 out=$2
shift 2
mkdir -p "$out"
for set in "$@"; do
  cp "$root/$set/rows.tsv" "$out/$set-rows.tsv"
  "$here/summarize.sh" "$root/$set/rows.tsv" > "$out/$set-summary.tsv"
done
