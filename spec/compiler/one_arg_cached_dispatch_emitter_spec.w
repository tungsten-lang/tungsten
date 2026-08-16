# Structural coverage for production scalar dispatch lowering. These checks
# cover the exact-source proof bits set by lowering: selected argc-one and
# argc-two calls use scalar helpers and need no scratch, while otherwise-
# identical unproven calls retain the generic ABI.

use ../../compiler/lib/emitter

-> check(name, condition)
  if !condition
    << "FAIL one-argument cached dispatch emitter: " + name
    exit(1)
  << "PASS one-argument cached dispatch emitter " + name

zero_inst = wire_instruction({
  op: :call_method_i64,
  temp: "%zero",
  temp_args_val: "%zero.args",
  receiver: "%recv",
  method_name_val: "%name",
  args: [],
  ic_id: 10,
  src_line: nil,
  src_col: nil
})
one_inst = wire_instruction({
  op: :call_method_i64,
  temp: "%one",
  temp_args_val: "%one.args",
  receiver: "%recv",
  method_name_val: "%name",
  args: ["%arg"],
  scalar_source_argc1: true,
  ic_id: 11,
  src_line: nil,
  src_col: nil
})
generic_one_inst = wire_instruction({
  op: :call_method_i64,
  temp: "%generic.one",
  temp_args_val: "%generic.one.args",
  receiver: "%recv",
  method_name_val: "%name",
  args: ["%arg"],
  scalar_source_argc1: false,
  ic_id: 14,
  src_line: nil,
  src_col: nil
})
two_inst = wire_instruction({
  op: :call_method_i64,
  temp: "%two",
  temp_args_val: "%two.args",
  receiver: "%recv",
  method_name_val: "%name",
  args: ["%arg0", "%arg1"],
  scalar_source_argc2: true,
  ic_id: 12,
  src_line: nil,
  src_col: nil
})
generic_two_inst = wire_instruction({
  op: :call_method_i64,
  temp: "%generic.two",
  temp_args_val: "%generic.two.args",
  receiver: "%recv",
  method_name_val: "%name",
  args: ["%arg0", "%arg1"],
  scalar_source_argc2: false,
  ic_id: 15,
  src_line: nil,
  src_col: nil
})

decls = declare_runtime()
check("runtime declaration",
      decls.include?("declare i64 @w_method_call_cached_1(i64, i64, i64, ptr)"))
check("argc-two runtime declaration",
      decls.include?("declare i64 @w_method_call_cached_2(i64, i64, i64, i64, ptr)"))

# Static slab WValues carry only identity. Runtime aliases may cache length,
# and the runtime masks that optional field for equality and hashing.
slab = build_string_wvalues([{id: 1, text: "has_key?"}])
expected_slab_wvalue = w_tag_stringsym + 12 + 16
check("static slab identity", slab[:wvalues][1] == expected_slab_wvalue)

zero_fns = runtime_fns_for_inst(zero_inst)
one_fns = runtime_fns_for_inst(one_inst)
two_fns = runtime_fns_for_inst(two_inst)
generic_two_fns = runtime_fns_for_inst(generic_two_inst)
generic_one_fns = runtime_fns_for_inst(generic_one_inst)
check("zero declaration selection",
      zero_fns.size() == 1 && zero_fns[0] == "w_method_call_cached_0")
check("one declaration selection",
      one_fns.size() == 1 && one_fns[0] == "w_method_call_cached_1")
check("unproven argc-one declaration stays generic",
      generic_one_fns.size() == 1 && generic_one_fns[0] == "w_method_call_cached")
check("two declaration selection",
      two_fns.size() == 1 && two_fns[0] == "w_method_call_cached_2")
check("unproven argc-two declaration stays generic",
      generic_two_fns.size() == 1 && generic_two_fns[0] == "w_method_call_cached")

one_ir = render_instruction(one_inst, nil, {}, nil, "")
check("argc-one helper call", one_ir.include?("@w_method_call_cached_1("))
check("argc-one generic count zero", !one_ir.include?("@w_method_call_cached("))
check("argc-one zero-helper count zero", !one_ir.include?("@w_method_call_cached_0("))
check("argument travels directly", one_ir.include?(", i64 %arg, ptr %one.ic)"))
check("argc-one first-store count zero", !one_ir.include?("store i64"))
check("argc-one scratch reference count zero", !one_ir.include?("%__mcall_args"))

generic_one_ir = render_instruction(generic_one_inst, nil, {}, nil, "")
check("unproven argc-one stays generic", generic_one_ir.include?("@w_method_call_cached("))
check("unproven argc-one omits helper", !generic_one_ir.include?("@w_method_call_cached_1("))
check("unproven argc-one retains store", generic_one_ir.include?("store i64 %arg"))

two_ir = render_instruction(two_inst, nil, {}, nil, "")
check("argc-two helper call", two_ir.include?("@w_method_call_cached_2("))
check("argc-two generic count zero", !two_ir.include?("@w_method_call_cached("))
check("argc-two direct first argument", two_ir.include?(", i64 %arg0, i64 %arg1, ptr %two.ic)"))
check("argc-two stores zero", !two_ir.include?("store i64"))
check("argc-two scratch reference zero", !two_ir.include?("%__mcall_args"))

generic_two_ir = render_instruction(generic_two_inst, nil, {}, nil, "")
check("unproven argc-two stays generic", generic_two_ir.include?("@w_method_call_cached("))
check("unproven argc-two omits helper", !generic_two_ir.include?("@w_method_call_cached_2("))
check("unproven argc-two first store retained", generic_two_ir.include?("store i64 %arg0"))
check("unproven argc-two second store retained", generic_two_ir.include?("store i64 %arg1"))

one_function = {
  name: "one_only",
  return_type: "i64",
  params: [],
  blocks: [
    {
      label: "entry",
      instructions: [one_inst, wire_instruction({op: :ret_i64, value: "%one"})]
    }
  ],
  var_slots: nil,
  var_slot_types: nil,
  promoted_vars: nil,
  fp_flags: ""
}
one_function_ir = emit_function(one_function, nil, nil, {}, false, "", nil)
check("one helper for one dynamic call",
      one_function_ir.split("@w_method_call_cached_1(").size() == 2)
check("function generic argc-one count zero",
      one_function_ir.split("@w_method_call_cached(").size() == 1)
check("function first-argument store count zero",
      !one_function_ir.include?("store i64 %arg, ptr %__mcall_args"))
check("one-only function scratch-alloca count zero",
      one_function_ir.split("%__mcall_args = alloca i64").size() == 1)

two_function = {
  name: "two_only",
  return_type: "i64",
  params: [],
  blocks: [
    {
      label: "entry",
      instructions: [two_inst, wire_instruction({op: :ret_i64, value: "%two"})]
    }
  ],
  var_slots: nil,
  var_slot_types: nil,
  promoted_vars: nil,
  fp_flags: ""
}
two_function_ir = emit_function(two_function, nil, nil, {}, false, "", nil)
check("arity-two helper emitted exactly once",
      two_function_ir.split("@w_method_call_cached_2(").size() == 2)
check("arity-two scratch alloca count zero",
      two_function_ir.split("%__mcall_args = alloca i64").size() == 1)

located_one = wire_instruction({
  op: :call_method_i64,
  temp: "%located",
  temp_args_val: "%located.args",
  receiver: "%recv",
  method_name_val: "%name",
  args: ["%arg"],
  scalar_source_argc1: true,
  ic_id: 13,
  src_line: 101,
  src_col: 7
})
located_ir = render_instruction(located_one, nil, {}, nil, "")
check("located call remains notail", located_ir.include?("= notail call i64 @w_method_call_cached_1("))
check("located call retains return label", located_ir.include?("cs.13.ret:"))

<< "PASS one-argument cached dispatch emitter"
