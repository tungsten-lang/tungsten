#!/bin/sh
# check-converters.sh: the scheme converters of adapters/ are exact.
#
# Takes the GF(2) schemes published with the Kauers-Moosbauer programs (flips/solutions/*-mod2.exp) and checks, for each:
#   1. exp -> MFW1 gives a scheme that tools/verify_tensor.rb accepts as exact for the tensor, with rank equal to the line count;
#   2. MFW1 -> exp -> MFW1 and MFW1 -> tfg text -> MFW1 reproduce the canonical file byte for byte;
#   3. (if WIDE_RECT_WALK names the metaflip walker) the walker's strict reader and exactness gate accept the file.
# Also converts the standard algorithm of a few shapes and checks it the same way. Prints "n of N" per check.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
adapters=$here/adapters
verify=$here/../../tools/verify_tensor.rb
SOTA_SRC=${SOTA_SRC:-$HOME/.tungsten/metaflip/experiments/record-hunt-20260926/work/sota}
solutions=$SOTA_SRC/flips/solutions
tmp=$(mktemp -d "${TMPDIR:-/tmp}/check-converters.XXXXXX")
trap 'find "$tmp" -depth -delete' EXIT
export LC_ALL=C

conv="-f $adapters/mfw-lib.awk"
exact=0 roundexp=0 roundtfg=0 strict=0 total=0 expholds=0

check() { # name shape n m p mfw-file
  total=$((total + 1))
  n=$3 m=$4 p=$5 f=$6
  ruby "$verify" --shape "$2" "$f" 2> /dev/null | grep -q '"exact": true' && exact=$((exact + 1))
  if [ "$n" -le 9 ] && [ "$m" -le 9 ] && [ "$p" -le 9 ] && [ $((n * m)) -le 64 ] && [ $((m * p)) -le 64 ] && [ $((n * p)) -le 64 ]; then
    expholds=$((expholds + 1))
    awk $conv -f "$adapters/mfw2exp.awk" "$f" > "$tmp/x.exp"
    awk -v n="$n" -v m="$m" -v p="$p" $conv -f "$adapters/exp2mfw.awk" "$tmp/x.exp" | cmp -s - "$f" && roundexp=$((roundexp + 1))
  fi
  awk $conv -f "$adapters/mfw2tfg.awk" "$f" > "$tmp/x.tfg"
  awk $conv -f "$adapters/tfg2mfw.awk" "$tmp/x.tfg" | cmp -s - "$f" && roundtfg=$((roundtfg + 1))
  if [ -n "${WIDE_RECT_WALK:-}" ]; then
    rm -f "$tmp/walk.mfw"
    "$WIDE_RECT_WALK" "$2" "$f" "$tmp/walk.mfw" 1 1 > /dev/null 2>&1 && strict=$((strict + 1))
  fi
}

for f in "$solutions"/*-mod2.exp; do
  b=$(basename "$f" .exp)
  dims=${b%%-*}
  n=$(echo "$dims" | cut -c1) m=$(echo "$dims" | cut -c2) p=$(echo "$dims" | cut -c3)
  awk -v n="$n" -v m="$m" -v p="$p" $conv -f "$adapters/exp2mfw.awk" "$f" > "$tmp/$b.mfw"
  lines=$(wc -l < "$f" | tr -d ' ')
  read -r _ _ _ _ rank < "$tmp/$b.mfw"
  [ "$rank" = "$lines" ] || echo "rank $rank differs from the $lines terms of $b" >&2
  check "$b" "${n}x${m}x${p}" "$n" "$m" "$p" "$tmp/$b.mfw"
done
published=$total
for shape in "2 2 2" "3 3 3" "4 4 4" "3 4 5" "2 5 7" "9 9 9" "10 13 14"; do
  # shellcheck disable=SC2086
  set -- $shape
  awk -v n="$1" -v m="$2" -v p="$3" $conv -f "$adapters/std2mfw.awk" > "$tmp/std.mfw"
  check "standard" "$1x$2x$3" "$1" "$2" "$3" "$tmp/std.mfw"
done

echo "published mod-2 schemes: $published; standard algorithms: $((total - published))"
echo "exact under verify_tensor.rb:            $exact of $total"
echo "MFW1 -> exp -> MFW1 identical:           $roundexp of $expholds (the schemes that .exp can hold)"
echo "MFW1 -> tfg text -> MFW1 identical:      $roundtfg of $total"
[ -z "${WIDE_RECT_WALK:-}" ] || echo "accepted by the walker's strict reader:   $strict of $total"
