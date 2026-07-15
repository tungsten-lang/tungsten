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
        {op: :const_float, temp: "%owned", value: "1.5"},
        {op: :cond_br, cond: "%cond", then_label: "left", else_label: "right"}
      ]
    },
    {
      label: "left",
      instructions: [
        {op: :add_i64, temp: "%left", lhs: "1", rhs: "2"},
        {op: :br, label: "join"}
      ]
    },
    {
      label: "right",
      instructions: [
        {op: :add_i64, temp: "%right", lhs: "3", rhs: "4"},
        {op: :br, label: "join"}
      ]
    },
    {
      label: "join",
      instructions: [
        {
          op: :phi_ssa,
          temp: "%joined",
          incoming: ["%left", "left", "%right", "right"]
        },
        {op: :cond_br, cond: "%cond", then_label: "chain_left", else_label: "chain_right"}
      ]
    },
    {
      label: "chain_left",
      instructions: [
        {op: :br, label: "chain_join"}
      ]
    },
    {
      label: "chain_right",
      instructions: [
        {op: :add_i64, temp: "%late", lhs: "5", rhs: "6"},
        {op: :br, label: "chain_join"}
      ]
    },
    {
      label: "chain_join",
      instructions: [
        {
          op: :phi_ssa,
          temp: "%chained",
          incoming: ["%joined", "chain_left", "%late", "chain_right"]
        },
        {op: :br, label: "loop_header"}
      ]
    },
    {
      label: "loop_header",
      instructions: [
        {
          op: :phi_ssa,
          temp: "%loop_value",
          incoming: ["%chained", "chain_join", "%loop_next", "loop_body"]
        },
        {op: :cond_br, cond: "%cond", then_label: "loop_body", else_label: "exit"}
      ]
    },
    {
      label: "loop_body",
      instructions: [
        {op: :add_i64, temp: "%loop_next", lhs: "%loop_value", rhs: "1"},
        {op: :br, label: "loop_header"}
      ]
    },
    {
      label: "exit",
      instructions: [
        {op: :ret_i64, value: w_nil.to_s()}
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
