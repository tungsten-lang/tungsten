# spec: compiled -- WIRE extern inspection uses compiled-only ccall_nobox
use ../../compiler/lib/emitter

-> check(name, condition)
  raise "FAIL library render dependencies: " + name unless condition
  << "PASS " + name

-> late_string_module(op, field)
  ins = wire_instruction({op: op, temp: "%text"})
  wire_set(ins, field, 2)
  {strings: [{id: 0, text: "library prefix"},
             {id: 1, text: "intervening literal"},
             {id: 2, text: "late library literal"},
             {id: 3, text: "entry-only literal"}],
   functions: [{name: "library_function", source_path: "library.w",
                blocks: [{instructions: [ins]}]}],
   library_reachability_paths: {"library.w": true},
   incremental_library_cache_compact_string_count: 1,
   incremental_library_cache_key: "same lowered library",
   incremental_core_cache_key: "same core"}

-> bucket_key(mod)
  function_emit_library_cache_bucket(mod, false, "", true, false, false, "")[:key]

ops = [[:string_i64, :string_id], [:symbol_i64, :string_id],
       [:bigint_literal_i64, :string_id], [:const_uuid, :string_id],
       [:const_ipv6, :string_id], [:ivar_get, :str_id], [:ivar_set, :str_id],
       [:register_unit, :str_id], [:class_new, :name_str_id],
       [:builtin_class_init, :name_str_id], [:class_add_method, :method_str_id],
       [:class_add_static_method, :method_str_id], [:class_add_ivar, :ivar_str_id],
       [:call_loc_set_col, :file_str_id]]
ops.each -> (pair)
  mod = late_string_module(pair[0], pair[1])
  original = bucket_key(mod)
  mod[:strings][3][:text] = "different entry-only literal"
  check("reuses across unrelated entry strings [pair[0]]", original == bucket_key(mod))
  mod[:strings][1][:text] = "an intervening literal that occupies two slab slots"
  check("invalidates shifted late binding [pair[0]]", original != bucket_key(mod))
  shifted = bucket_key(mod)
  mod[:strings][2][:text] = "changed late library literal"
  check("invalidates changed late literal [pair[0]]", shifted != bucket_key(mod))

mod = late_string_module(:string_i64, :string_id)
mod[:functions][0][:blocks][0][:instructions] = [wire_instruction({
  op: :switch_i64, cases: [{string_id: 2, label: "match"}]
})]
before = bucket_key(mod)
mod[:strings][1][:text] = "a longer literal before a string switch case"
check("covers string switch cases", before != bucket_key(mod))

<< "library_emit_string_dependencies_spec: all checks passed"
