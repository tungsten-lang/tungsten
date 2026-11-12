#!/bin/sh
# runtime/sources.sh: read runtime/sources.txt for the shell, make and Ruby
# builds of the runtime (compiler/lib/driver/link.w reads the same file
# natively; scripts/test-runtime-sources.sh keeps the two readers in step).
#
#   sh runtime/sources.sh [-f] PLATFORM SET...
#
# prints every source that belongs to at least one SET and whose platform is
# `any` or PLATFORM (darwin, linux; any other name selects only `any`), one
# per line, relative to runtime/, in manifest order, each once. With -f each
# line is the file, a tab, and its extra cflags (possibly empty).
set -eu

full=0
if [ "${1:-}" = "-f" ]; then
  full=1
  shift
fi
if [ "$#" -lt 2 ]; then
  printf 'usage: sh runtime/sources.sh [-f] PLATFORM SET...\n' >&2
  exit 2
fi
platform="$1"
shift

dir="$(dirname "$0")"
manifest="$dir/sources.txt"
if [ ! -f "$manifest" ]; then
  printf 'runtime/sources.sh: %s not found\n' "$manifest" >&2
  exit 1
fi

awk -v platform="$platform" -v sets=" $* " -v full="$full" '
  /^[ \t]*#/ || NF == 0 { next }
  NF < 3 {
    printf "runtime/sources.txt:%d: expected FILE SETS PLATFORM\n", NR > "/dev/stderr"
    bad = 1
    exit 1
  }
  {
    if ($3 != "any" && $3 != platform) next
    n = split($2, member, ",")
    hit = 0
    for (i = 1; i <= n; i++) {
      if (index(sets, " " member[i] " ") > 0) { hit = 1; break }
    }
    if (!hit || ($1 in seen)) next
    seen[$1] = 1
    if (full) {
      flags = ""
      for (j = 4; j <= NF; j++) flags = flags (flags == "" ? "" : " ") $j
      print $1 "\t" flags
    } else {
      print $1
    }
  }
  END { if (bad) exit 1 }
' "$manifest"
