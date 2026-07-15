# Candidate-only regression coverage for release-mode stacktrace metadata
# stripping. The in-place trials were rejected by the performance gate, so
# this identity-sensitive fixture is intentionally not in scripts/test-specs.
# It records that a future candidate must remove every location-set
# pseudo-instruction, clear all location
# fields on survivors, preserve survivor order/object identity, and compact
# each block's existing instruction array rather than replacing it.

# compiler.w's lowering dependency refers to helpers normally loaded by the
# compiler entry point before compiler.w itself. Include those two providers so
# this focused fixture links independently of compiler/tungsten.w.
use ../../compiler/lib/lexer
use ../../compiler/lib/error_formatter
use ../../compiler/lib/compiler

-> check(name, condition)
  if !condition
    << "FAIL strip stacktrace metadata: " + name
    exit(1)
  << "PASS strip stacktrace metadata " + name

-> no_location_markers?(instructions)
  i = 0
  while i < instructions.size()
    if instructions[i][:op] == :call_loc_set_col
      return false
    i += 1
  true

first = {
  op: :add_i64,
  temp: "%first",
  lhs: "1",
  rhs: "2",
  src_line: 10,
  src_col: 11,
  loc_site_id: 12,
  sentinel: "keep-first"
}
second = {
  op: :call_direct_i64,
  temp: "%second",
  name: "w_int",
  args: ["3"],
  src_line: 20,
  src_col: 21,
  loc_site_id: 22,
  sentinel: "keep-second"
}
third = {
  op: :ret_i64,
  value: "%second",
  src_line: 30,
  src_col: 31,
  loc_site_id: 32,
  sentinel: "keep-third"
}
without_metadata = {
  op: :br,
  label: "exit",
  sentinel: "keep-without-metadata"
}

mixed_instructions = [
  {op: :call_loc_set_col, line: 1, col: 2},
  first,
  {op: :call_loc_set_col, line: 3, col: 4},
  {op: :call_loc_set_col, line: 5, col: 6},
  second,
  third,
  {op: :call_loc_set_col, line: 7, col: 8}
]
marker_free_instructions = [without_metadata]
marker_only_instructions = [
  {op: :call_loc_set_col, line: 40, col: 41},
  {op: :call_loc_set_col, line: 42, col: 43}
]
empty_instructions = []

mixed_bits = wvalue_bits(mixed_instructions)
marker_free_bits = wvalue_bits(marker_free_instructions)
marker_only_bits = wvalue_bits(marker_only_instructions)
empty_bits = wvalue_bits(empty_instructions)
first_bits = wvalue_bits(first)
second_bits = wvalue_bits(second)
third_bits = wvalue_bits(third)
without_metadata_bits = wvalue_bits(without_metadata)

mod = {
  functions: [
    {
      name: "mixed",
      blocks: [
        {label: "entry", instructions: mixed_instructions},
        {label: "marker_free", instructions: marker_free_instructions}
      ]
    },
    {
      name: "edge_blocks",
      blocks: [
        {label: "marker_only", instructions: marker_only_instructions},
        {label: "empty", instructions: empty_instructions}
      ]
    }
  ]
}

strip_enhanced_stacktrace_metadata(mod)

mixed = mod[:functions][0][:blocks][0][:instructions]
marker_free = mod[:functions][0][:blocks][1][:instructions]
marker_only = mod[:functions][1][:blocks][0][:instructions]
empty = mod[:functions][1][:blocks][1][:instructions]

check("mixed array identity", wvalue_bits(mixed) == mixed_bits)
check("marker-free array identity", wvalue_bits(marker_free) == marker_free_bits)
check("marker-only array identity", wvalue_bits(marker_only) == marker_only_bits)
check("empty array identity", wvalue_bits(empty) == empty_bits)

check("all mixed markers removed", mixed.size() == 3 && no_location_markers?(mixed))
check("consecutive and edge markers preserve order",
      wvalue_bits(mixed[0]) == first_bits &&
      wvalue_bits(mixed[1]) == second_bits &&
      wvalue_bits(mixed[2]) == third_bits)
check("marker-free survivor identity",
      marker_free.size() == 1 && wvalue_bits(marker_free[0]) == without_metadata_bits)
check("marker-only block emptied", marker_only.size() == 0)
check("empty block unchanged", empty.size() == 0)

i = 0
while i < mixed.size()
  inst = mixed[i]
  check("mixed survivor [i] line cleared", inst[:src_line] == nil)
  check("mixed survivor [i] column cleared", inst[:src_col] == nil)
  check("mixed survivor [i] site cleared", inst[:loc_site_id] == nil)
  i += 1
check("missing metadata remains semantically nil",
      marker_free[0][:src_line] == nil &&
      marker_free[0][:src_col] == nil &&
      marker_free[0][:loc_site_id] == nil)
check("unrelated fields preserved",
      mixed[0][:sentinel] == "keep-first" &&
      mixed[1][:sentinel] == "keep-second" &&
      mixed[2][:sentinel] == "keep-third" &&
      marker_free[0][:sentinel] == "keep-without-metadata")

# A second release-mode strip must be a no-op on shape and identity.
strip_enhanced_stacktrace_metadata(mod)
check("second pass mixed identity", wvalue_bits(mixed) == mixed_bits && mixed.size() == 3)
check("second pass marker-free identity", wvalue_bits(marker_free) == marker_free_bits && marker_free.size() == 1)
check("second pass remains marker-free", no_location_markers?(mixed) && no_location_markers?(marker_free))

<< "PASS strip stacktrace metadata in-place compaction"
