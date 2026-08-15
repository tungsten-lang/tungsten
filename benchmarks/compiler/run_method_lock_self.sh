#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
compiler="${TUNGSTEN_COMPILER:-$root/bin/tungsten-compiler}"
iterations="${ITERATIONS:-200000000}"
samples="${SAMPLES:-7}"

if [[ ! -x "$compiler" ]]; then
  echo "missing compiler: $compiler" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

compile_one() {
  local source="$1"
  local output="$2"
  TUNGSTEN_ROOT="$root" TUNGSTEN_CACHE_DIR="$tmp/cache" \
    "$compiler" compile "$source" --release --native --out "$output" >/dev/null
}

open_source="$root/benchmarks/compiler/method_lock_self_open.w"
locked_source="$root/benchmarks/compiler/method_lock_self_locked.w"

TUNGSTEN_ROOT="$root" TUNGSTEN_CACHE_DIR="$tmp/cache" \
  "$compiler" compile "$open_source" --emit-wire > "$tmp/open.wire"
TUNGSTEN_ROOT="$root" TUNGSTEN_CACHE_DIR="$tmp/cache" \
  "$compiler" compile "$locked_source" --emit-wire > "$tmp/locked.wire"

awk '/function __w_MethodLockSelfCounter_run__a2/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/open.wire" > "$tmp/open-run.wire"
awk '/function __w_MethodLockSelfCounter_run__a2/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/locked.wire" > "$tmp/locked-run.wire"
grep -q 'call_method_i64.*MethodLockSelfCounter_step' "$tmp/open-run.wire"
grep -q 'call_direct_i64.*MethodLockSelfCounter_step' "$tmp/locked-run.wire"
if grep -q 'call_method_i64.*MethodLockSelfCounter_step' "$tmp/locked-run.wire"; then
  echo "locked benchmark retained dynamic step dispatch" >&2
  exit 1
fi

compile_one "$open_source" "$tmp/open"
compile_one "$locked_source" "$tmp/locked"

i=0
while [[ "$i" -lt "$samples" ]]; do
  "$tmp/open" "$iterations" | tee -a "$tmp/results"
  "$tmp/locked" "$iterations" | tee -a "$tmp/results"
  i=$((i + 1))
done

ruby - "$tmp/results" <<'RUBY'
rows = File.readlines(ARGV.fetch(0), chomp: true).map { |line| line.split("|") }
groups = rows.group_by { |row| row.fetch(1) }
medians = groups.transform_values do |group|
  values = group.map { |row| Float(row.fetch(2)) }.sort
  values.fetch(values.length / 2)
end
open_ns = medians.fetch("open-self")
locked_ns = medians.fetch("locked-self")
puts format("MEDIAN|open-self|%.9f", open_ns)
puts format("MEDIAN|locked-self|%.9f", locked_ns)
puts format("SPEEDUP|%.6fx", open_ns / locked_ns)
RUBY
