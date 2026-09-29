#!/bin/sh
# Build robolab controller binaries: ./build.sh [skill ...] (default: all).
# Each lib/entry/<skill>.w becomes bin/robolab_<skill>; lib/robolab.w (every
# skill behind one binary) becomes bin/robolab.
set -e
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
cd "$repo"
if [ $# -eq 0 ]; then
  set -- $(ls "$here/lib/entry" | sed 's/\.w$//')
  [ -f "$here/lib/robolab.w" ] && bin/tungsten --release -o "$here/bin/robolab" "$here/lib/robolab.w"
fi
for s in "$@"; do
  bin/tungsten --release -o "$here/bin/robolab_$s" "$here/lib/entry/$s.w"
done
