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

run_compiler --emit-wire "$root/compiler/test/fixtures/core_abi_stable_a.w" > "$tmp/core-abi-a.wire"
run_compiler --emit-wire "$root/compiler/test/fixtures/core_abi_stable_b.w" > "$tmp/core-abi-b.wire"
grep -q '^core reuse: stable$' "$tmp/core-abi-a.wire"
grep -q '^core reuse: stable$' "$tmp/core-abi-b.wire"
core_abi_a="$(awk '/^core abi:/{print $3}' "$tmp/core-abi-a.wire")"
core_abi_b="$(awk '/^core abi:/{print $3}' "$tmp/core-abi-b.wire")"
if [[ -z "$core_abi_a" || "$core_abi_a" != "$core_abi_b" ]]; then
  echo "protected programs with the same Core closure produced different ABI fingerprints" >&2
  exit 1
fi

run_compiler --emit-wire "$root/compiler/test/fixtures/core_abi_stable_stop.w" > "$tmp/core-abi-stop.wire"
grep -q '^core reuse: stable$' "$tmp/core-abi-stop.wire"
core_abi_stop="$(awk '/^core abi:/{print $3}' "$tmp/core-abi-stop.wire")"
if [[ -z "$core_abi_stop" || "$core_abi_stop" == "$core_abi_a" ]]; then
  echo "open and type-frozen Core variants shared an ABI compatibility fingerprint" >&2
  exit 1
fi

run_compiler --fast --emit-wire "$root/compiler/test/fixtures/core_abi_stable_a.w" > "$tmp/core-abi-fast.wire"
grep -q '^core reuse: stable$' "$tmp/core-abi-fast.wire"
core_abi_fast="$(awk '/^core abi:/{print $3}' "$tmp/core-abi-fast.wire")"
if [[ -z "$core_abi_fast" || "$core_abi_fast" == "$core_abi_a" ]]; then
  echo "fast and precise Core variants shared an ABI compatibility fingerprint" >&2
  exit 1
fi

run_compiler --emit-wire "$root/compiler/test/fixtures/core_abi_subclass_fallback.w" > "$tmp/core-abi-subclass.wire"
grep -q '^core reuse: monolithic fallback (program class CoreAbiArrayChild subclasses Core class Array)$' "$tmp/core-abi-subclass.wire"

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
grep -q 'call_direct_i64.*__w_SecondReceiver_value__a1' <<<"$reassigned_main"
if grep -q 'call_method_i64.*SecondReceiver_value' <<<"$reassigned_main"; then
  echo "locked flow-singleton reassignment retained inline-cache dispatch" >&2
  exit 1
fi

run_compiler --emit-wire "$root/compiler/test/fixtures/locked_class_set_receiver.w" > "$tmp/class-set.wire"
class_set_main="$(awk '/function main/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/class-set.wire")"
grep -q 'call_direct_i64.*__w_SharedSetBase_value__a1' <<<"$class_set_main"
grep -q 'call_direct_i64.*__w_DistinctSetDog_value__a1' <<<"$class_set_main"
grep -q 'call_direct_i64.*__w_DistinctSetCat_value__a1' <<<"$class_set_main"
grep -q 'call_direct_i64.*w_class_of' <<<"$class_set_main"
if grep -q 'call_method_i64.*\(SharedSet\|DistinctSet\).*value' <<<"$class_set_main"; then
  echo "locked bounded class set retained inline-cache dispatch" >&2
  exit 1
fi
run_compiler --emit-wire "$root/compiler/test/fixtures/locked_return_class_sets.w" > "$tmp/return-class-sets.wire"
return_class_main="$(awk '/function main/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/return-class-sets.wire")"
if [[ "$(grep -c 'call_direct_i64.*__w_ReturnSetDog_value__a1' <<<"$return_class_main")" -lt 2 ]] || \
   [[ "$(grep -c 'call_direct_i64.*__w_ReturnSetCat_value__a1' <<<"$return_class_main")" -lt 2 ]]; then
  echo "function/method SCC return class sets did not produce exhaustive direct dispatch" >&2
  exit 1
fi
if grep -q 'call_method_i64.*ReturnSet.*value' <<<"$return_class_main"; then
  echo "function/method SCC return class sets retained value inline caches" >&2
  exit 1
fi
run_compiler run "$root/compiler/test/fixtures/locked_return_class_sets.w" > "$tmp/return-class-sets-dog.out"
run_compiler run "$root/compiler/test/fixtures/locked_return_class_sets.w" one > "$tmp/return-class-sets-cat.out"
printf '41\n41\n' > "$tmp/return-class-sets-dog.expected"
printf '42\n42\n' > "$tmp/return-class-sets-cat.expected"
cmp "$tmp/return-class-sets-dog.expected" "$tmp/return-class-sets-dog.out"
cmp "$tmp/return-class-sets-cat.expected" "$tmp/return-class-sets-cat.out"

run_compiler --emit-wire "$root/compiler/test/fixtures/locked_no_raise_rescue.w" > "$tmp/no-raise.wire"
safe_no_raise="$(awk '/function __w_NoRaiseProof_safe_add__a2/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/no-raise.wire")"
safe_int_no_raise="$(awk '/function __w_NoRaiseProof_safe_int_add__a1/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/no-raise.wire")"
safe_scc_no_raise="$(awk '/function __w_NoRaiseProof_safe_scc_call__a1/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/no-raise.wire")"
safe_method_scc_no_raise="$(awk '/function __w_NoRaiseProof_safe_method_scc_call__a2/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/no-raise.wire")"
risky_no_raise="$(awk '/function __w_NoRaiseProof_risky_div__a3/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/no-raise.wire")"
risky_transitive_no_raise="$(awk '/function __w_NoRaiseProof_risky_transitive_div__a3/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/no-raise.wire")"
if grep -q 'w_exception_push' <<<"$safe_no_raise" || \
   grep -q 'w_exception_push' <<<"$safe_int_no_raise" || \
   grep -q 'w_exception_push' <<<"$safe_scc_no_raise" || \
   grep -q 'w_exception_push' <<<"$safe_method_scc_no_raise"; then
  echo "proven no-raise begin retained exception-frame setup" >&2
  exit 1
fi
grep -q 'w_exception_push' <<<"$risky_no_raise"
grep -q 'w_exception_push' <<<"$risky_transitive_no_raise"
run_compiler run "$root/compiler/test/fixtures/locked_no_raise_rescue.w" > "$tmp/no-raise.out"
printf '42\n42\n40\n42\n42\n42\n' > "$tmp/no-raise.expected"
cmp "$tmp/no-raise.expected" "$tmp/no-raise.out"
run_compiler --emit-wire "$root/compiler/test/fixtures/locked_class_set_widen.w" > "$tmp/class-set-widen.wire"
class_set_widen_main="$(awk '/function main/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/class-set-widen.wire")"
grep -q 'call_method_i64' <<<"$class_set_widen_main"
if grep -q 'call_direct_i64.*__w_WidenSet.*_value__a1' <<<"$class_set_widen_main"; then
  echo "class set above the exact-set cap emitted exhaustive direct dispatch" >&2
  exit 1
fi
run_compiler --emit-wire "$root/compiler/test/fixtures/locked_class_set_with.w" > "$tmp/class-set-with.wire"
class_set_with_main="$(awk '/function main/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/class-set-with.wire")"
grep -q 'call_method_i64.*WithSetFirst_value' <<<"$class_set_with_main"
if grep -q 'call_direct_i64.*__w_WithSetFirst_value__a1' <<<"$class_set_with_main"; then
  echo "iterative with body retained a first-pass direct-call fact" >&2
  exit 1
fi
run_compiler run "$root/compiler/test/fixtures/locked_class_set_receiver.w" > "$tmp/class-set-cat.out"
run_compiler run "$root/compiler/test/fixtures/locked_class_set_receiver.w" dog > "$tmp/class-set-dog.out"
printf '40\n42\n41\n' > "$tmp/class-set-cat.expected"
printf '40\n41\n41\n' > "$tmp/class-set-dog.expected"
cmp "$tmp/class-set-cat.expected" "$tmp/class-set-cat.out"
cmp "$tmp/class-set-dog.expected" "$tmp/class-set-dog.out"
if [[ "${TUNGSTEN_TEST_COMPILER_DIRECT:-0}" == "1" ]]; then
  run_compiler run --interpret "$root/compiler/test/fixtures/locked_class_set_receiver.w" > "$tmp/class-set-cat.interpret.out"
  run_compiler run --interpret "$root/compiler/test/fixtures/locked_class_set_receiver.w" dog > "$tmp/class-set-dog.interpret.out"
  cmp "$tmp/class-set-cat.expected" "$tmp/class-set-cat.interpret.out"
  cmp "$tmp/class-set-dog.expected" "$tmp/class-set-dog.interpret.out"
fi

run_compiler --emit-wire "$root/compiler/test/fixtures/locked_conditional_receiver.w" > "$tmp/conditional.wire"
conditional_main="$(awk '/function main/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/conditional.wire")"
grep -q 'call_method_i64.*devirt=@__w_ConditionalReceiver_value__a1' <<<"$conditional_main"
if grep -q 'call_direct_i64.*__w_ConditionalReceiver_value__a1' <<<"$conditional_main"; then
  echo "conditional constructor assignment was treated as dominating" >&2
  exit 1
fi

run_compiler --emit-wire "$root/compiler/test/fixtures/locked_static_new_receiver.w" > "$tmp/static-new.wire"
static_new_main="$(awk '/function main/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/static-new.wire")"
grep -q 'call_method_i64' <<<"$static_new_main"
if grep -q 'call_direct_i64.*__w_ClaimedReceiver_value__a1' <<<"$static_new_main"; then
  echo "static .new result was treated as the nominal receiver class" >&2
  exit 1
fi

run_compiler --emit-wire "$root/compiler/test/fixtures/locked_extended_dispatch.w" > "$tmp/extended.wire"
extended_main="$(awk '/function main/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/extended.wire")"
shared_self="$(awk '/function __w_SharedDispatchBase_through_self__a2/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/extended.wire")"
override_self="$(awk '/function __w_OverrideDispatchBase_through_self__a2/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/extended.wire")"
if [[ "$(grep -c 'call_direct_i64.*__w_FreshDispatchReceiver_value__a1' <<<"$extended_main")" -lt 2 ]]; then
  echo "locked copied/fresh exact receivers retained dispatch" >&2
  exit 1
fi
grep -q 'call_direct_i64.*__w_SharedDispatchBase_step__a2' <<<"$shared_self"
if grep -q 'call_method_i64' <<<"$shared_self"; then
  echo "locked self call with an override-free hierarchy retained dispatch" >&2
  exit 1
fi
grep -q 'call_method_i64' <<<"$override_self"
if grep -q 'call_direct_i64.*__w_OverrideDispatchBase_step__a2' <<<"$override_self"; then
  echo "locked self call ignored a known subclass override" >&2
  exit 1
fi
run_compiler run "$root/compiler/test/fixtures/locked_extended_dispatch.w" > "$tmp/extended.out"
printf '42\n42\n41\n42\n' > "$tmp/extended.expected"
cmp "$tmp/extended.expected" "$tmp/extended.out"

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

run_compiler --emit-wire "$root/compiler/test/fixtures/stopped_type_reopen.w" > "$tmp/type-stop.wire"
type_stop_main="$(awk '/function main/{inside=1; next} inside && /^function /{exit} inside{print}' "$tmp/type-stop.wire")"
grep -q 'call_direct_i64.*w_type_tables_lock_safe' <<<"$type_stop_main"
if grep -q 'call_direct_i64.*w_method_tables_lock_safe' <<<"$type_stop_main"; then
  echo "STOP_THE_PRESS unexpectedly locked existing method tables" >&2
  exit 1
fi
run_compiler run "$root/compiler/test/fixtures/stopped_type_reopen.w" > "$tmp/type-stop.out"
printf '42\n' > "$tmp/type-stop.expected"
cmp "$tmp/type-stop.expected" "$tmp/type-stop.out"
if [[ "${TUNGSTEN_TEST_COMPILER_DIRECT:-0}" == "1" ]]; then
  run_compiler run --interpret "$root/compiler/test/fixtures/stopped_type_reopen.w" > "$tmp/type-stop.interpret.out"
  cmp "$tmp/type-stop.expected" "$tmp/type-stop.interpret.out"
fi

if run_compiler check "$root/compiler/test/fixtures/stopped_new_type_after_barrier.w" > "$tmp/type-stop-order.out" 2>&1; then
  echo "new type after STOP_THE_PRESS unexpectedly compiled" >&2
  exit 1
fi
grep -q 'new type definitions must appear before Tungsten.STOP_THE_PRESS' "$tmp/type-stop-order.out"

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
