#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
compiler="${TUNGSTEN_TEST_COMPILER:-$root/implementations/c/build/tungsten-c}"
if [[ ! -x "$compiler" ]]; then
  echo "missing compiler: $compiler" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

run_compiler() {
  TUNGSTEN_ROOT="$root" \
  TUNGSTEN_C_FAST_PARSE=0 \
  TUNGSTEN_MARCH_ARGS="${TUNGSTEN_MARCH_ARGS:--mcpu=apple-m5}" \
    "$compiler" "$root/compiler/tungsten.w" "$@"
}

run_compiler --emit-wire "$root/compiler/test/fixtures/type_facts_scc.w" > "$tmp/scc.wire"
grep -q 'function __w_depth1' "$tmp/scc.wire"
grep -q 'function __w_even_depth' "$tmp/scc.wire"
main_scc="$(awk '/function main/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/scc.wire")"
grep -q 'add_i64' <<<"$main_scc"

TUNGSTEN_ROOT="$root" TUNGSTEN_C_FAST_PARSE=0 TUNGSTEN_PARAM_INFER=1 "$compiler" "$root/compiler/test/core_abi_boundary.w" > "$tmp/core-boundary.out"
grep -q 'core ABI boundary: PASS' "$tmp/core-boundary.out"

run_compiler --emit-wire "$root/compiler/test/fixtures/final_method.w" > "$tmp/final.wire"
run_line="$(awk '/function __w_FinalCounter_run/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/final.wire")"
grep -q 'call_direct_i64.*__w_FinalCounter_step__a2' <<<"$run_line"
if grep -q 'call_method_i64' <<<"$run_line"; then
  echo "final self-call retained dynamic dispatch" >&2
  exit 1
fi
relay_line="$(awk '/function __w_FinalCounter_relay/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/final.wire")"
grep -q 'call_direct_i64.*__w_FinalCounter_step__a2' <<<"$relay_line"
if grep -q 'call_method_i64' <<<"$relay_line"; then
  echo "final compatible-class call retained dynamic dispatch" >&2
  exit 1
fi

if run_compiler check "$root/compiler/test/fixtures/final_method_override.w" > "$tmp/override.out" 2>&1; then
  echo "overriding @final method unexpectedly compiled" >&2
  exit 1
fi
grep -q 'cannot override final method' "$tmp/override.out"

echo "type facts: PASS"
