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

<< "core ABI boundary: PASS"
