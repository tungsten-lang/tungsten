# Focused source-call-graph coverage for transitive known-impure ccall
# propagation. Use the same minimal lowering harness as the neighbouring
# compiler analysis specs so the bootstrap supplies the packed-AST runtime.
use ../../compiler/lib/ast
use ../../compiler/lib/error_formatter
# lowering/core_cache references the deterministic rename helper when loaded
# standalone; include its provider without pulling the emitter/compiler tower.
use ../../compiler/lib/content_hash
use ../../compiler/lib/lowering

-> check(name, condition)
  if !condition
    << "FAIL " + name
    exit 1
  << "PASS " + name

-> one_param(name)
  [Tungsten:AST:Param.new(name)]

-> source_owned(node, path)
  node.source_path = path
  node

-> direct_impure(name, path)
  source_owned(
    Tungsten:AST:MethodDef.new(name, one_param("x"), [
      Tungsten:AST:Call.new(nil, "ccall", [Tungsten:AST:String.new("w_blas_dscal")])
    ]),
    path
  )

-> calls(name, callee, path, as_fn = false)
  body = [Tungsten:AST:Call.new(nil, callee, [Tungsten:AST:Var.new("x")])]
  if as_fn
    return source_owned(Tungsten:AST:FnDef.new(name, one_param("x"), body), path)
  source_owned(Tungsten:AST:MethodDef.new(name, one_param("x"), body), path)

-> identity_fn(name, path)
  source_owned(
    Tungsten:AST:FnDef.new(name, one_param("x"), [Tungsten:AST:Var.new("x")]),
    path
  )

-> fresh_mod(pure_nodes, contract)
  pure_calls = {}
  memo_tables = {}
  i = 0
  while i < pure_nodes.size()
    key = method_call_key_for_def(pure_nodes[i])
    pure_calls[key] = "__w_" + pure_nodes[i].name
    memo_tables[key] = "__w_" + pure_nodes[i].name + ".memo"
    i += 1
  {
    protect_core: true,
    core_reuse_contract: contract,
    known_pure_calls: pure_calls,
    fn_memo_tables: memo_tables
  }

# Realizable stable-partition chain: user callers may consume Core facts, so a
# Core ccall seed must flow through a Core wrapper and into a user fn. Only the
# reverse (Core caller -> user definition) is suppressed for cache identity.
core_leaf = direct_impure("core_impure_leaf", "core/spec_impure.w")
core_wrapper = calls("core_impure_wrapper", "core_impure_leaf", "core/spec_impure.w", true)
user_wrapper = calls("user_impure_wrapper", "core_impure_wrapper", "spec/compiler/spec_impure.w", true)
pure_user = identity_fn("unrelated_pure", "spec/compiler/spec_pure.w")
boundary_expressions = [core_leaf, core_wrapper, user_wrapper, pure_user]

stable = fresh_mod([core_wrapper, user_wrapper, pure_user], :stable)
propagate_memo_impurity(stable, boundary_expressions)
check("analysis direct Core seed", core_leaf.calls_impure_ccall == true)
check("analysis Core wrapper reaches seed", core_wrapper.calls_impure_ccall == true)
check("analysis user wrapper reaches Core seed", user_wrapper.calls_impure_ccall == true)
check("analysis Core wrapper memo removed", stable[:known_pure_calls][method_call_key_for_def(core_wrapper)] == nil)
check("analysis user wrapper memo removed", stable[:known_pure_calls][method_call_key_for_def(user_wrapper)] == nil)
check("analysis disconnected pure memo retained", stable[:known_pure_calls][method_call_key_for_def(pure_user)] != nil)

# Synthetic filter microtest: stable Core reuse must not depend on a user
# same-name candidate. A real PROTECT_THE_CORE program rejects conflicting
# Core ABI definitions before this point, but the graph boundary is asserted
# directly so cache fingerprints cannot silently acquire user facts.
core_shared = source_owned(
  Tungsten:AST:MethodDef.new("shared_helper", one_param("x"), [Tungsten:AST:Var.new("x")]),
  "core/spec_pure.w"
)
core_caller = calls("core_filter_caller", "shared_helper", "core/spec_pure.w", true)
user_shared = direct_impure("shared_helper", "spec/compiler/spec_impure.w")
user_shared.param_types = [:i64]
filter_expressions = [core_shared, core_caller, user_shared]

filtered = fresh_mod([core_caller], :stable)
propagate_memo_impurity(filtered, filter_expressions)
check("analysis protected Core caller stays pure", core_caller.calls_impure_ccall == false)
check("analysis protected Core memo retained", filtered[:known_pure_calls][method_call_key_for_def(core_caller)] != nil)

monolithic = fresh_mod([core_caller], :monolithic_fallback)
propagate_memo_impurity(monolithic, filter_expressions)
check("analysis monolithic cross-owner propagation", core_caller.calls_impure_ccall == true)
check("analysis monolithic Core memo removed", monolithic[:known_pure_calls][method_call_key_for_def(core_caller)] == nil)

<< "transitive_impure_ccall_analysis_spec: all checks passed"
