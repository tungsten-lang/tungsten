#!/bin/sh
# Stand-in for the compiled walker: walker_stub.sh SHAPE SEED.mfw OUTPUT.mfw STEPS NONCE
# The behaviour comes from the seed's file name: ok-, drop- (one rank less), fail- (exit 3), noline- (no result line).
seed="$2"
out="$3"
steps="$4"
name=$(basename "$seed")
rank=$(head -n 1 "$seed" | awk '{print $5}')
case "$name" in
  fail-*) echo "walker: cannot open $seed" >&2; exit 3 ;;
  noline-*) echo "done"; cp "$seed" "$out"; exit 0 ;;
  drop-*) new=$((rank - 1)) ;;
  *) new=$rank ;;
esac
cp "$seed" "$out"
echo "seed_rank=$rank rank=$new moves=$steps accepted=7 no_pair=2 escapes=1"
