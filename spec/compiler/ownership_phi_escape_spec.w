# Regression coverage for the ownership pass's single-scan phi handling.
# WIRE phi operands are flat value/label pairs. Every incoming value and the
# result must be conservatively escaped in that scan, including values flowing
# through another phi and values arriving on loop backedges.

use ../../compiler/lib/ownership

-> check_escaped(escaped, name)
  if escaped[name] != true
    << "FAIL ownership phi escape: " + name
    exit(1)
  << "PASS ownership phi escape " + name

func = {
  name: "ownership_phi_shapes",
  params: ["cond"],
  blocks: [
    {
      label: "entry",
      instructions: [
        wire_instruction({op: :const_float, temp: "%owned", value: "1.5"}),
        wire_instruction({op: :cond_br, cond: "%cond", then_label: "left", else_label: "right"})
      ]
    },
    {
      label: "left",
      instructions: [
        wire_instruction({op: :add_i64, temp: "%left", lhs: "1", rhs: "2"}),
        wire_instruction({op: :br, label: "join"})
      ]
    },
    {
      label: "right",
      instructions: [
        wire_instruction({op: :add_i64, temp: "%right", lhs: "3", rhs: "4"}),
        wire_instruction({op: :br, label: "join"})
      ]
    },
    {
      label: "join",
      instructions: [
        wire_instruction({
          op: :phi_ssa,
          temp: "%joined",
          incoming: ["%left", "left", "%right", "right"]
        }),
        wire_instruction({op: :cond_br, cond: "%cond", then_label: "chain_left", else_label: "chain_right"})
      ]
    },
    {
      label: "chain_left",
      instructions: [
        wire_instruction({op: :br, label: "chain_join"})
      ]
    },
    {
      label: "chain_right",
      instructions: [
        wire_instruction({op: :add_i64, temp: "%late", lhs: "5", rhs: "6"}),
        wire_instruction({op: :br, label: "chain_join"})
      ]
    },
    {
      label: "chain_join",
      instructions: [
        wire_instruction({
          op: :phi_ssa,
          temp: "%chained",
          incoming: ["%joined", "chain_left", "%late", "chain_right"]
        }),
        wire_instruction({op: :br, label: "loop_header"})
      ]
    },
    {
      label: "loop_header",
      instructions: [
        wire_instruction({
          op: :phi_ssa,
          temp: "%loop_value",
          incoming: ["%chained", "chain_join", "%loop_next", "loop_body"]
        }),
        wire_instruction({op: :cond_br, cond: "%cond", then_label: "loop_body", else_label: "exit"})
      ]
    },
    {
      label: "loop_body",
      instructions: [
        wire_instruction({op: :add_i64, temp: "%loop_next", lhs: "%loop_value", rhs: "1"}),
        wire_instruction({op: :br, label: "loop_header"})
      ]
    },
    {
      label: "exit",
      instructions: [
        wire_instruction({op: :ret_i64, value: w_nil.to_s()})
      ]
    }
  ]
}

ownership_analyze(func, {})
escaped = func[:ownership][:escaped]

check_escaped(escaped, "%left")
check_escaped(escaped, "%right")
check_escaped(escaped, "%joined")
check_escaped(escaped, "%late")
check_escaped(escaped, "%chained")
check_escaped(escaped, "%loop_next")
check_escaped(escaped, "%loop_value")

if escaped["%owned"] == true
  << "FAIL ownership phi escape: unrelated producer escaped"
  exit(1)

<< "PASS ownership phi single scan"

# Lowering-emitted retention shapes: :phi_i64 carries (a_value, b_value)
# pairs rather than an incoming list, and the inline stores / cleanup /
# recycle ops retain a WValue without a runtime call the arg-escape arm
# would see. Each was a hole that let a still-live value be freed.
func2 = {
  name: "ownership_retention_shapes",
  params: [],
  blocks: [
    {
      label: "entry",
      instructions: [
        wire_instruction({op: :call_direct_i64, temp: "%owned2", name: "w_hash_new", args: []}),
        wire_instruction({op: :phi_i64, temp: "%merged", a_value: "%pa", a_label: "left", b_value: "%pb", b_label: "right"}),
        wire_instruction({op: :store_cvar, cvar_key: "@@cache", value: "%cv"}),
        wire_instruction({op: :view_store_field, temp: "%vs", ptr: "%self", value: "%vf"}),
        wire_instruction({op: :store_memo_ptr, value: "%memo", global: "g"}),
        wire_instruction({op: :class_store, value: "%cls", class_name: "C"}),
        wire_instruction({op: :small_array_set_inline, temp: "%s1", arr: "%arr", idx: "0", value: "%sav"}),
        wire_instruction({op: :typed_array_set_inline, temp: "%s2", arr: "%arr", idx: "0", value: "%tav"}),
        wire_instruction({op: :typed_array_compound_op_inline, temp: "%s3", arr: "%arr", idx: "0", value: "%tcv"}),
        wire_instruction({op: :bool_array_set_inline, temp: "%s4", arr: "%arr", idx: "0", val: "%bav"}),
        wire_instruction({op: :bool_array_set_byte_inline, temp: "%s5", arr: "%arr", idx: "0", val: "%bbv"}),
        wire_instruction({op: :cleanup_push_hash, value: "%cph"}),
        wire_instruction({op: :call_recycle_hash, value: "%crh"}),
        wire_instruction({op: :call_direct_ptr, temp: "%p1", name: "w_x", args: ["%parg"]}),
        wire_instruction({op: :ret_i64, value: w_nil.to_s()})
      ]
    }
  ]
}

ownership_analyze(func2, {})
escaped2 = func2[:ownership][:escaped]

check_escaped(escaped2, "%merged")
check_escaped(escaped2, "%pa")
check_escaped(escaped2, "%pb")
check_escaped(escaped2, "%cv")
check_escaped(escaped2, "%vf")
check_escaped(escaped2, "%memo")
check_escaped(escaped2, "%cls")
check_escaped(escaped2, "%sav")
check_escaped(escaped2, "%tav")
check_escaped(escaped2, "%tcv")
check_escaped(escaped2, "%bav")
check_escaped(escaped2, "%bbv")
check_escaped(escaped2, "%cph")
check_escaped(escaped2, "%crh")
check_escaped(escaped2, "%parg")

if escaped2["%owned2"] == true
  << "FAIL ownership retention shapes: unrelated producer escaped"
  exit(1)

<< "PASS ownership retention shapes"
