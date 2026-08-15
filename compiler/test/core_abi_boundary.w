# Call-site observation is allowed to specialize user functions, but never a
# definition loaded from the canonical core prelude.

use ../lib/lowering

core_fn = Tungsten:AST:FnDef.new("core_probe", [Tungsten:AST:Param.new("x")], [Tungsten:AST:Var.new("x")])
core_fn.source_path = env("TUNGSTEN_ROOT") + "/core/probe.w"

user_fn = Tungsten:AST:FnDef.new("user_probe", [Tungsten:AST:Param.new("x")], [Tungsten:AST:Var.new("x")])
user_fn.source_path = env("TUNGSTEN_ROOT") + "/compiler/test/user_probe.w"
if !definition_from_core?(core_fn)
  raise "core definition provenance was not recognized"
if definition_from_core?(user_fn)
  raise "user definition was classified as core"

mod = wire_module("core-abi-boundary")
# Feed the same unanimous observation to both definitions.  The lowering
# boundary, rather than the observer, is authoritative: observations are an
# optimization hint and must not become part of a core function's ABI.
observation = [{:f64 => true}]
mod[:observed_param_types] = {
  "core_probe" => observation,
  "user_probe" => observation
}
mod[:param_infer_bailed] = {}

core_types = {}
populate_definition_var_types(core_fn, core_types, mod)
if core_types["x"] != nil
  raise "user call site rewrote a core ABI"

user_types = {}
populate_definition_var_types(user_fn, user_types, mod)
if user_types["x"] != :f64
  raise "user function did not consume call-site observation"

# Under the executable-owned protection contract, Core may recover facts from
# Core call sites, but the same user call must remain invisible across the
# boundary.
core_call = Tungsten:AST:Call.new(nil, "core_probe", [Tungsten:AST:Float.new(1.25)], nil)
core_call.source_path = env("TUNGSTEN_ROOT") + "/core/probe.w"
user_call = Tungsten:AST:Call.new(nil, "core_probe", [Tungsten:AST:Float.new(2.5)], nil)
user_call.source_path = env("TUNGSTEN_ROOT") + "/compiler/test/user_probe.w"

protected_user_only = wire_module("core-abi-user-only")
protected_user_only[:protect_core] = true
collect_param_type_observations(protected_user_only, [core_fn, user_call], [core_fn], {})
user_only_types = {}
populate_definition_var_types(core_fn, user_only_types, protected_user_only)
if user_only_types["x"] != nil
  raise "user observation crossed the protected Core boundary"

protected_core_call = wire_module("core-abi-core-call")
protected_core_call[:protect_core] = true
collect_param_type_observations(protected_core_call, [core_fn, core_call, user_call], [core_fn, core_call], {})
core_call_types = {}
populate_definition_var_types(core_fn, core_call_types, protected_core_call)
if core_call_types["x"] != :f64
  raise "Core-to-Core observation did not recover a stable parameter fact"

<< "core ABI boundary: PASS"
