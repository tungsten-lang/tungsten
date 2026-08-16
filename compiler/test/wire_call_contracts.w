# Direct unit contract for emitter.w's pre-render WIRE verifier.

use ../lib/wire
use ../lib/emitter

fn wire_test_module(instructions)
  {functions: [{name: "wire_test", blocks: [{instructions: instructions}]}]}

same = [
  wire_instruction({op: :call_direct_i64, name: "w_demo", args: ["1"]}),
  wire_instruction({op: :call_direct_i64, name: "w_demo", args: ["2"], arg_types: ["i64"]})
]
if verify_wire_call_contracts(wire_test_module(same)) != nil
  raise "equal WIRE call contracts were rejected"

different_arity = [
  wire_instruction({op: :call_direct_i64, name: "w_demo", args: ["1"]}),
  wire_instruction({op: :call_direct_i64, name: "w_demo", args: ["1", "2"]})
]
arity_error = verify_wire_call_contracts(wire_test_module(different_arity))
if arity_error == nil || arity_error.index("i64(i64)") == nil || arity_error.index("i64(i64,i64)") == nil
  raise "WIRE arity mismatch was not diagnosed"

different_return = [
  wire_instruction({op: :call_direct_i64, name: "w_demo", args: ["1"]}),
  wire_instruction({op: :call_direct_void, name: "w_demo", args: ["1"]})
]
return_error = verify_wire_call_contracts(wire_test_module(different_return))
if return_error == nil || return_error.index("i64(i64)") == nil || return_error.index("void(i64)") == nil
  raise "WIRE return mismatch was not diagnosed"

<< "wire-call-contracts: ok"
