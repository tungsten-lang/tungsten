#!/bin/sh
# Mirror Blade's engine into the Tungsten js-runtime worktree (languages/javascript/runtime/).
# The lexer and parser stay in languages/javascript/ (js-frontend), one level up.
set -e
SRC="$(cd "$(dirname "$0")/.." && pwd)"
DST="${1:-$HOME/tungsten-worktrees/js-runtime}/languages/javascript/runtime"
mkdir -p "$DST/tools"
for f in "$SRC"/*.w; do
  b=$(basename "$f")
  case "$b" in lexer.w|parser.w) continue ;; esac
  cp "$f" "$DST/$b"
done
sed -i '' 's/^use lexer$/use ..\/lexer/; s/^use parser$/use ..\/parser/' "$DST/engine.w"
cp "$SRC/tools/test262.w" "$SRC/tools/test262.py" "$SRC/tools/sync_runtime.sh" "$DST/tools/"
# Blade's lexer copy defines js_chr (a workaround for toolchains without the chr-nul fix);
# here the frontend lexer is upstream's, where 0.chr is already "\0".
printf '\n# One code point as UTF-8 (WTF-8 for lone surrogates).\n-> js_chr(cp)\n  cp.chr\n' >> "$DST/value.w"
