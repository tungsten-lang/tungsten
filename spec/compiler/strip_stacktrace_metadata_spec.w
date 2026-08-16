# Regression coverage for release-mode stacktrace metadata stripping and the
# live-string compaction that follows it. The strip removes every location-set
# pseudo-instruction, clears all location fields on survivors, and preserves
# survivor order/object identity.

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
mixed_again = mod[:functions][0][:blocks][0][:instructions]
marker_free_again = mod[:functions][0][:blocks][1][:instructions]
check("second pass mixed shape", mixed_again.size() == 3)
check("second pass marker-free shape", marker_free_again.size() == 1)
check("second pass preserves survivors",
      wvalue_bits(mixed_again[0]) == first_bits &&
      wvalue_bits(mixed_again[1]) == second_bits &&
      wvalue_bits(mixed_again[2]) == third_bits &&
      wvalue_bits(marker_free_again[0]) == without_metadata_bits)
check("second pass remains marker-free", no_location_markers?(mixed_again) && no_location_markers?(marker_free_again))

<< "PASS strip stacktrace metadata compaction"

# Every instruction string-id spelling, including nested string-switch cases,
# must participate in the live set and remap. The dead source path models a
# release-only call_loc_set_col string after the instruction itself was
# stripped.
string_mod = {
  strings: [
    {id: 0, text: "dead/source.w"},
    {id: 1, text: "literal"},
    {id: 2, text: "unit-name"},
    {id: 3, text: "ClassName"},
    {id: 4, text: "method_name"},
    {id: 5, text: "live/source.w"},
    {id: 6, text: "@field"},
    {id: 7, text: "case-value"},
    {id: 8, text: "also-dead"}
  ],
  string_ids_by_text: {},
  next_string: 9,
  string_index: {stale: true},
  functions: [{
    name: "string_ids",
    blocks: [{label: "entry", instructions: [{
      op: :probe,
      string_id: 1,
      str_id: 2,
      name_str_id: 3,
      method_str_id: 4,
      file_str_id: 5,
      ivar_str_id: 6,
      cases: [{string_id: 7}]
    }]}]
  }]
}

compact_live_module_strings(string_mod)
probe = string_mod[:functions][0][:blocks][0][:instructions][0]
check("dead strings removed", string_mod[:strings].size() == 7)
check("live ids compacted in order",
      probe[:string_id] == 0 &&
      probe[:str_id] == 1 &&
      probe[:name_str_id] == 2 &&
      probe[:method_str_id] == 3 &&
      probe[:file_str_id] == 4 &&
      probe[:ivar_str_id] == 5 &&
      probe[:cases][0][:string_id] == 6)
check("module string registry rebuilt",
      string_mod[:next_string] == 7 &&
      string_mod[:string_ids_by_text]["literal"] == 0 &&
      string_mod[:string_ids_by_text]["case-value"] == 6 &&
      string_mod[:string_ids_by_text]["dead/source.w"] == nil)
check("stale content-hash string index cleared", string_mod[:string_index] == nil)

<< "PASS release live-string compaction"
