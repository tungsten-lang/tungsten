#!/usr/bin/env bash
# Warm rebuilds must not reuse block ids that cached Core functions carry.
#
# The incremental Core cache stores lowered Core function bodies and relowers
# only the Core top-level startup on a hit. When startup, user code and Core
# bodies shared one block counter, a warm build named its startup / user
# closures __block_0, __block_1, ... while cached Core bodies (Enumerable
# blocks and the like) already used those names; content hashing then folded
# two different closures into one function and calling one ran the other's
# body (null environment, segfault). This builds a program, edits it, and
# rebuilds warm, then checks the sidemap for a block name with two different
# origins and runs both binaries. core/codec/audio/pcm brings Core files whose
# top-level code creates closures (codec registration), the startup blocks
# that collided.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-core-cache-blocks.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

export TUNGSTEN_CACHE_DIR="$TMP/cache"
export TUNGSTEN_INCREMENTAL=0

cat >"$TMP/lib.w" <<'EOF'
LT = {}
-> lreg(id, m)
  LT[id] = m
lreg("b", ->(c) c * 3)
EOF
cat >"$TMP/main.w" <<'EOF'
use core/codec/audio/pcm
use lib
T = {}
-> reg(id, m)
  T[id] = m
reg("a", ->(c) c + 1)
xs = [1, 2, 3].map ->(x) x * 2
ys = [5, 6, 7].select ->(x) x > 5
<< T["a"].call(41)
<< LT["b"].call(14)
<< xs.to_s
<< ys.to_s
EOF

check_build() {
  local out="$1"
  "$TUNGSTEN" -o "$TMP/$out" "$TMP/main.w" >"$TMP/$out.log" 2>&1 || { cat "$TMP/$out.log" >&2; exit 1; }
  local got
  got="$("$TMP/$out" | tr '\n' ' ')"
  if [[ "$got" != "42 42 [2, 4, 6] [6, 7] "* ]]; then
    echo "FAIL: $out printed '$got'" >&2
    exit 1
  fi
  python3 -I - "$TMP/$out.sidemap" "$out" <<'EOF'
import re, sys
text = open(sys.argv[1]).read()
origins = {}
for name, cls, meth, path in re.findall(r'"symbol":"(__c?block_\d+)","class":([^,]*),"method":([^,]*),"kind":"block","file":"([^"]*)"', text):
    origins.setdefault(name, set()).add((cls, meth, path))
dups = {k: v for k, v in origins.items() if len(v) > 1}
if dups:
    k = sorted(dups)[0]
    print("FAIL: %s: %d block names have two origins, e.g. %s: %s" % (sys.argv[2], len(dups), k, sorted(dups[k])), file=sys.stderr)
    sys.exit(1)
EOF
}

check_build cold
echo '<< "edit 1"' >>"$TMP/main.w"
check_build warm1
echo '<< "edit 2"' >>"$TMP/main.w"
check_build warm2
echo "PASS core cache block ids (cold + 2 warm rebuilds)"
