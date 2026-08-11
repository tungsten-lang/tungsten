# A registry value must prove it belongs to the requested source key before
# lowering turns it into an ABI-sensitive direct call.

use ../lib/lowering/signatures

guarded = {
  known_static_methods: {
    "Tensor.zeros_unit": {
      lookup_key: "Tensor.zeros",
      fn_name: "__w_Tensor_S_zeros",
      arity: 2
    }
  }
}
if known_static_method_for(guarded, "Tensor.zeros_unit") != nil
  raise "mismatched static-method registry entry was accepted"

exact = {
  known_static_methods: {
    "Tensor.zeros_unit": {
      lookup_key: "Tensor.zeros_unit",
      fn_name: "__w_Tensor_S_zeros_unit",
      arity: 4
    }
  }
}
if known_static_method_for(exact, "Tensor.zeros_unit")[:arity] != 4
  raise "exact static-method registry entry was rejected"

overloaded = {known_static_methods: {}}
register_known_static_method_info(overloaded, "Probe.pick", {
  lookup_key: "Probe.pick",
  fn_name: "__w_Probe_S_pick_1",
  arity: 2
}, 1, 1)
register_known_static_method_info(overloaded, "Probe.pick", {
  lookup_key: "Probe.pick",
  fn_name: "__w_Probe_S_pick_3",
  arity: 4
}, 3, 3)
if known_static_method_for(overloaded, "Probe.pick", 1)[:fn_name] != "__w_Probe_S_pick_1"
  raise "one-argument static overload was not retained"
if known_static_method_for(overloaded, "Probe.pick", 3)[:fn_name] != "__w_Probe_S_pick_3"
  raise "three-argument static overload was not retained"

<< "static-method-registry-guard: ok"
