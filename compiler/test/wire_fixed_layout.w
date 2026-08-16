# Generated fixed-layout constructor and ordinal field-walk contract. This is
# intentionally small enough to run through both the bootstrap C VM and the
# self-hosted native compiler.

use ../lib/wire

inst = wire_make_add_i64("%left", "%right", "%sum")

if wire_kind(inst) != :add_i64
  raise "fixed-layout WIRE kind did not round-trip"
if wire_field_count(inst) != 3
  raise "fixed-layout WIRE field count did not round-trip"
if wire_field_symbol_at(inst, 0) != :lhs || wire_field_value_at(inst, 0) != "%left"
  raise "fixed-layout WIRE lhs ordinal did not round-trip"
if wire_field_symbol_at(inst, 1) != :rhs || wire_field_value_at(inst, 1) != "%right"
  raise "fixed-layout WIRE rhs ordinal did not round-trip"
if wire_field_symbol_at(inst, 2) != :temp || wire_field_value_at(inst, 2) != "%sum"
  raise "fixed-layout WIRE temp ordinal did not round-trip"

dynamic = wire_make_dynamic_3(:add_i64, :lhs, "%a", :rhs, "%b", :temp, "%c")
if wire_kind(dynamic) != :add_i64 || wire_field_count(dynamic) != 3
  raise "dynamic fixed-layout WIRE constructor did not round-trip"

call = wire_make_call_direct_ptr(["%x", "%y"], "w_demo", "%out")
call_args = wire_get(call, :args)
if ccall_nobox("w_is_wire_extern", call_args) != 1 || wire_sequence_size(call_args) != 2
  raise "static WIRE constructor did not pack variable-width args"
if wire_sequence_get(call_args, 0) != "%x" || wire_sequence_get(call_args, 1) != "%y"
  raise "packed WIRE args did not preserve order"
wire_sequence_set(call_args, 1, "%z")
if wire_sequence_get(call_args, 1) != "%z"
  raise "packed WIRE args did not support mid-end mutation"

dynamic_call = wire_make_dynamic_3(:call_direct_ptr,
  :args, ["%dynamic"], :name, "w_demo", :temp, "%dynamic_out")
dynamic_args = wire_get(dynamic_call, :args)
if ccall_nobox("w_is_wire_extern", dynamic_args) != 1 || wire_sequence_size(dynamic_args) != 1
  raise "dynamic WIRE constructor did not pack variable-width args"
if wire_sequence_get(dynamic_args, 0) != "%dynamic"
  raise "dynamic packed WIRE args did not round-trip"

<< "wire-fixed-layout: ok"
