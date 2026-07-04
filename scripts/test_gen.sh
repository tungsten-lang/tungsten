#!/bin/bash
# Regenerate language codepoint tables and validate their sizes /
# cross-equality. Run after touching gen_unicode_codepoints.py.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 scripts/gen_unicode_codepoints.py --lang c --bits 64 >/dev/null
python3 scripts/gen_unicode_codepoints.py --lang c --bits 32 >/dev/null
python3 scripts/gen_unicode_codepoints.py --lang c --bits 16 >/dev/null
python3 scripts/gen_unicode_codepoints.py --lang tungsten --bits 64 >/dev/null
python3 scripts/gen_unicode_codepoints.py --lang tungsten --bits 32 >/dev/null

size64=$(wc -c < languages/c/c.lex64 | tr -d ' ')
size32=$(wc -c < languages/c/c.lex32 | tr -d ' ')
size16=$(wc -c < languages/c/c.lex16 | tr -d ' ')
tsize64=$(wc -c < languages/tungsten/tungsten.lex64 | tr -d ' ')
tsize32=$(wc -c < languages/tungsten/tungsten.lex32 | tr -d ' ')

[ "$size64" -eq 1114112 ] || { echo "FAIL: c.lex64 size=$size64 expected 1114112"; exit 1; }
[ "$size32" -eq 1114112 ] || { echo "FAIL: c.lex32 size=$size32 expected 1114112"; exit 1; }
[ "$size16" -eq 256     ] || { echo "FAIL: c.lex16 size=$size16 expected 256"; exit 1; }
[ "$tsize64" -eq 1114112 ] || { echo "FAIL: tungsten.lex64 size=$tsize64 expected 1114112"; exit 1; }
[ "$tsize32" -eq 1114112 ] || { echo "FAIL: tungsten.lex32 size=$tsize32 expected 1114112"; exit 1; }

# lex64 and lex32 share content (only the runtime element width differs).
cmp -s languages/c/c.lex64 languages/c/c.lex32 || {
  echo "FAIL: c.lex64 and c.lex32 differ"; exit 1;
}
cmp -s languages/tungsten/tungsten.lex64 languages/tungsten/tungsten.lex32 || {
  echo "FAIL: tungsten.lex64 and tungsten.lex32 differ"; exit 1;
}

echo "test_gen: PASS (c.lex64=${size64} c.lex32=${size32} c.lex16=${size16} tungsten.lex64=${tsize64} tungsten.lex32=${tsize32})"
