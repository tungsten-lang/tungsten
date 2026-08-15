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
  if [[ "${TUNGSTEN_TEST_COMPILER_DIRECT:-0}" == "1" ]]; then
    TUNGSTEN_ROOT="$root" \
    TUNGSTEN_C_FAST_PARSE=0 \
    TUNGSTEN_MARCH_ARGS="${TUNGSTEN_MARCH_ARGS:--mcpu=apple-m5}" \
      "$compiler" "$@"
  else
    TUNGSTEN_ROOT="$root" \
    TUNGSTEN_C_FAST_PARSE=0 \
    TUNGSTEN_MARCH_ARGS="${TUNGSTEN_MARCH_ARGS:--mcpu=apple-m5}" \
      "$compiler" "$root/compiler/tungsten.w" "$@"
  fi
}

run_compiler --emit-wire "$root/compiler/test/fixtures/type_facts_scc.w" > "$tmp/scc.wire"
grep -q 'function __w_depth1' "$tmp/scc.wire"
grep -q 'function __w_even_depth' "$tmp/scc.wire"
main_scc="$(awk '/function main/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/scc.wire")"
grep -q 'add_i64' <<<"$main_scc"

TUNGSTEN_PARAM_INFER=1 run_compiler run "$root/compiler/test/core_abi_boundary.w" > "$tmp/core-boundary.out"
grep -q 'core ABI boundary: PASS' "$tmp/core-boundary.out"

run_compiler --emit-wire "$root/compiler/test/fixtures/open_world_dispatch.w" > "$tmp/open.wire"
run_compiler --emit-wire "$root/compiler/test/fixtures/closed_world_dispatch.w" > "$tmp/closed.wire"
open_main="$(awk '/function main/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/open.wire")"
closed_main="$(awk '/function main/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/closed.wire")"
grep -q 'call_method_i64.*devirt=@__w_LockedCounter_step__a2' <<<"$open_main"
grep -q 'call_direct_i64.*__w_LockedCounter_step__a2' <<<"$closed_main"
grep -q 'call_direct_i64.*w_method_tables_lock_safe' <<<"$closed_main"
if grep -q 'call_method_i64.*LockedCounter_step' <<<"$closed_main"; then
  echo "locked exact-class call retained inline-cache dispatch" >&2
  exit 1
fi

run_compiler --emit-wire "$root/compiler/test/fixtures/locked_reassigned_receiver.w" > "$tmp/reassigned.wire"
reassigned_main="$(awk '/function main/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/reassigned.wire")"
grep -q 'call_method_i64.*devirt=@__w_SecondReceiver_value__a1' <<<"$reassigned_main"

run_compiler --emit-wire "$root/compiler/test/fixtures/locked_static_new_receiver.w" > "$tmp/static-new.wire"
static_new_main="$(awk '/function main/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/static-new.wire")"
grep -q 'call_method_i64' <<<"$static_new_main"
if grep -q 'call_direct_i64.*__w_ClaimedReceiver_value__a1' <<<"$static_new_main"; then
  echo "static .new result was treated as the nominal receiver class" >&2
  exit 1
fi

if run_compiler check "$root/compiler/test/fixtures/protected_core_reopen.w" > "$tmp/core-reopen.out" 2>&1; then
  echo "protected Core reopen unexpectedly compiled" >&2
  exit 1
fi
grep -q 'PROTECT_THE_CORE.*forbids' "$tmp/core-reopen.out"

if run_compiler check "$root/compiler/test/fixtures/protected_core_registry_reopen.w" > "$tmp/core-registry-reopen.out" 2>&1; then
  echo "protected unloaded Core reopen unexpectedly compiled" >&2
  exit 1
fi
grep -q 'PROTECT_THE_CORE.*forbids' "$tmp/core-registry-reopen.out"

if run_compiler check "$root/compiler/test/fixtures/locked_definition_after_barrier.w" > "$tmp/lock-order.out" 2>&1; then
  echo "definition after LOCK_THE_DOORS unexpectedly compiled" >&2
  exit 1
fi
grep -q 'definitions must appear before Tungsten.LOCK_THE_DOORS' "$tmp/lock-order.out"

if run_compiler check "$root/compiler/test/fixtures/contract_dependency.w" > "$tmp/dependency.out" 2>&1; then
  echo "dependency-owned closed-world contract unexpectedly compiled" >&2
  exit 1
fi
grep -q 'may only be declared by the entry program' "$tmp/dependency.out"

if run_compiler check "$root/compiler/test/fixtures/nested_contract.w" > "$tmp/nested.out" 2>&1; then
  echo "nested closed-world contract unexpectedly compiled" >&2
  exit 1
fi
grep -q 'must be a top-level entry-program declaration' "$tmp/nested.out"

echo "type facts: PASS"
