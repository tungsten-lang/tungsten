# Arity contracts for runtime-backed builtin methods.
#
# The C runtime implements many Core methods natively through per-type
# inline-cache tables (runtime/runtime.c, the `w_ic_*_table` rows): Array
# storage primitives, String scanning, Hash access, Int/Float/Decimal leaves,
# and the Socket/Thread/Channel/Mmap handles. Those rows carry no source
# signature, so a call with the wrong argument count used to be padded with
# nil or silently truncated. This module is the compiler-side mirror of the
# runtime rows: `[min, max]` is the argument count the native handler
# consumes, a trailing block counted as one argument (that is how a block
# reaches a builtin); max -1 means variadic.
#
# Three checks consult it. Lowering (lowering/method_call.w) raises
# E_LOWER_ARITY when the receiver's static type names one of these classes;
# the interpreter (interpreter.w, dispatch on primitive receivers) raises the
# same message at the call; the runtime checks its own rows on the IC-miss
# path with the same message. TUNGSTEN_ARITY=off disables all three.
#
# scripts/check-core-dispatch-contracts.rb fails when a row here and the
# runtime row disagree, and when either disagrees with a Core `.w`
# declaration of the same method (the declaration is the source of truth).
# Keep the class labels identical to w_ic_table_for_key in runtime.c.

-> builtin_method_arity(class_name, method_name)
  case class_name
    "Array"        => builtin_arity_array(method_name)
    "String"       => builtin_arity_string(method_name)
    "Hash"         => builtin_arity_hash(method_name)
    "Int"          => builtin_arity_int(method_name)
    "Quantity"     => builtin_arity_quantity(method_name)
    "StringBuffer" => builtin_arity_string_buffer(method_name)
    "BigArray"     => builtin_arity_big_array(method_name)
    "SmallArray"   => builtin_arity_small_array(method_name)
    "Socket"       => builtin_arity_socket(method_name)
    "Mmap"         => builtin_arity_mmap(method_name)
    "WIRE"         => builtin_arity_wire(method_name)
    => nil

-> builtin_arity_accepts?(contract, argc)
  argc >= contract[0] && (contract[1] < 0 || argc <= contract[1])

-> builtin_arity_expected_display(contract)
  if contract[1] < 0
    return "at least " + contract[0].to_s() + " arguments"
  if contract[1] == contract[0]
    return contract[0].to_s() + " argument" + (contract[0] == 1 ? "" : "s")
  contract[0].to_s() + ".." + contract[1].to_s() + " arguments"

# The message every engine raises for an arity contract violation. The head
# is the interpreter's source-method message; the tail names the builtin.
-> arity_contract_message(method_name, contract, argc)
  "'" + method_name + "' takes " + builtin_arity_expected_display(contract) + ", got " + argc.to_s() + " — arguments are never silently dropped or padded"

-> builtin_arity_message(class_name, method_name, contract, argc)
  arity_contract_message(method_name, contract, argc) + "; " + class_name + "#" + method_name + " is a runtime builtin with a fixed signature, so fix the call"

# ── Per-table mirrors (one arm per named runtime row) ─────────────────────

-> builtin_arity_wire(name)
  case name
    "\[]"           => [1, 1]
    "\[]="          => [2, 2]
    "size"          => [0, 0]
    => nil

-> builtin_arity_array(name)
  case name
    "push"          => [1, 1]
    "pop"           => [0, 0]
    "shift"         => [0, 0]
    "\[]"           => [1, 1]
    "\[]="          => [2, 2]
    "has?"          => [1, 1]
    "get"           => [1, 1]
    "set"           => [2, 2]
    "include?"      => [1, 1]
    "unshift"       => [1, 1]
    "sort"          => [0, 1]
    "stable_sort"   => [0, 1]
    "view"          => [1, 1]
    "min"           => [0, 0]
    "max"           => [0, 0]
    "sum"           => [0, 1]
    "fastsum"       => [0, 0]
    "sumsq"         => [0, 0]
    "dot"           => [1, 1]
    "cos"           => [0, 0]
    "sin"           => [0, 0]
    "sqrt"          => [0, 0]
    "each"          => [0, 1]
    "any?"          => [0, 1]
    "all?"          => [0, 1]
    "none?"         => [0, 1]
    "count"         => [0, 1]
    "find_index"    => [1, 1]
    "index"         => [1, 1]
    "last_index"    => [1, 1]
    "replace_byte!" => [2, 2]
    "slice"         => [2, 2]
    "exp"           => [0, 0]
    "log"           => [0, 0]
    "tan"           => [0, 0]
    => nil

-> builtin_arity_string(name)
  case name
    "\[]"           => [1, 1]
    "concat"        => [1, 1]
    "append"        => [1, 1]
    "<<"            => [1, 1]
    "prepend"       => [1, 1]
    "include?"      => [1, 1]
    "valid_utf8?"   => [0, 0]
    "repeat"        => [1, 1]
    "codes"         => [0, 0]
    "lchs"          => [0, 2]
    "slice"         => [1, 2]
    "strip"         => [0, 0]
    "ltrim"         => [0, 0]
    "rtrim"         => [0, 0]
    "to_i"          => [0, 1]
    "to_f"          => [0, 0]
    "to_sym"        => [0, 0]
    "split"         => [0, 1]
    "replace"       => [2, 2]
    "gsub"          => [2, 2]
    "index"         => [1, 2]
    "=~"            => [1, 1]
    "match?"        => [1, 1]
    "rindex"        => [1, 2]
    "size"          => [0, 0]
    "length"        => [0, 0]
    "to_d"          => [0, 0]
    => nil

-> builtin_arity_int(name)
  case name
    "times"         => [0, 1]
    "each"          => [0, 1]
    "to_d"          => [0, 0]
    => nil

-> builtin_arity_big_array(name)
  case name
    "\[]"           => [1, 1]
    "\[]="          => [2, 2]
    "get"           => [1, 1]
    "set"           => [2, 2]
    "push"          => [1, 1]
    "subview"       => [2, 2]
    => nil

-> builtin_arity_small_array(name)
  case name
    "\[]"           => [1, 1]
    "\[]="          => [2, 2]
    "get"           => [1, 1]
    "set"           => [2, 2]
    => nil

-> builtin_arity_socket(name)
  case name
    "accept"        => [0, 0]
    "read"          => [0, 1]
    "read_exact"    => [1, 1]
    "write"         => [1, 1]
    "write_bytes"   => [1, 1]
    "close"         => [0, 0]
    "shutdown"      => [0, 1]
    "set_timeout"   => [1, 1]
    "alpn_protocol" => [0, 0]
    "serve_http"    => [0, 2]
    "read_into"     => [3, 3]
    "write_slice"   => [3, 3]
    => nil

-> builtin_arity_mmap(name)
  case name
    "close"         => [0, 0]
    "byte_at"       => [1, 1]
    "\[]"           => [1, 1]
    "view_at"       => [3, 3]
    => nil

-> builtin_arity_string_buffer(name)
  case name
    "to_s"          => [0, 0]
    "include?"      => [1, 1]
    "starts_with?"  => [1, 1]
    "append"        => [1, 1]
    "<<"            => [1, 1]
    "\[]"           => [1, 1]
    "clear"         => [0, 0]
    => nil

-> builtin_arity_hash(name)
  case name
    "has_key?"      => [1, 1]
    "keys"          => [0, 0]
    "values"        => [0, 0]
    "merge!"        => [1, 1]
    "each"          => [0, 1]
    "delete"        => [1, 1]
    "get"           => [1, 1]
    "\[]"           => [1, 1]
    "set"           => [2, 2]
    "\[]="          => [2, 2]
    => nil

-> builtin_arity_quantity(name)
  case name
    "point"         => [0, 1]
    "delta"         => [0, 1]
    "point?"        => [0, 0]
    "delta?"        => [0, 0]
    "origin"        => [0, 0]
    "value"         => [0, 0]
    "unit_name"     => [0, 0]
    "to_f"          => [0, 0]
    "equivalent"    => [2, 2]
    "equivalent_to" => [2, 2]
    => nil

