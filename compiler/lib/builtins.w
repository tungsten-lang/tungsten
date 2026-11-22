# Built-in method dispatch for boot1's interpreter
# Called by the interpreter when a method is a builtin.
# The interp parameter is the Interpreter instance.
use builtin_arity

# Argument contract of the receiver-method arms below, `[min, max]` with a
# trailing block counted as one argument (nil = not a receiver method, or an
# arm that states its own contract). Interpreter#dispatch_method checks it
# before dispatch_builtin runs, so no arm below drops or pads arguments.
# Bare-call builtins (puts, type, exit, env, …) are absent on purpose: their
# receiver is the enclosing self and their arguments are the whole call.
-> builtin_fallback_arity(name)
  case name
    "length"          => [0, 0]
    "size"            => [0, 0]
    "chars"           => [0, 0]
    "split"           => [0, 1]
    "strip"           => [0, 0]
    "ltrim"           => [0, 0]
    "rtrim"           => [0, 0]
    "ascii?"          => [0, 0]
    "valid_utf8?"     => [0, 0]
    "replace"         => [2, 2]
    "starts_with?"    => [1, 1]
    "ends_with?"      => [1, 1]
    "upcase"          => [0, 0]
    "downcase"        => [0, 0]
    "swapcase"        => [0, 0]
    "capitalize"      => [0, 0]
    "include?"        => [1, 1]
    "index"           => [1, 2]
    "rindex"          => [1, 2]
    "gsub"            => [2, 2]
    "concat"          => [1, 1]
    "append"          => [1, 1]
    "prepend"         => [1, 1]
    "zip"             => [1, 1]
    "reverse"         => [0, 0]
    "slice"           => [1, 2]
    "copy"            => [1, 2]
    "push"            => [1, 1]
    "pop"             => [0, 0]
    "shift"           => [0, 0]
    "unshift"         => [1, 1]
    "first"           => [0, 0]
    "last"            => [0, 0]
    "empty?"          => [0, 0]
    "nil?"            => [0, 0]
    "join"            => [0, 1]
    "sort"            => [0, 1]
    "flatten"         => [0, 0]
    "uniq"            => [0, 0]
    "delete"          => [1, 1]
    "each"            => [0, 1]
    "map"             => [0, 1]
    "select"          => [0, 1]
    "reject"          => [0, 1]
    "reduce"          => [0, 2]
    "each_with_index" => [0, 1]
    "map_with_index"  => [0, 1]
    "any?"            => [0, 1]
    "all?"            => [0, 1]
    "find"            => [0, 1]
    "count"           => [0, 1]
    "sum"             => [0, 1]
    "times"           => [0, 1]
    "keys"            => [0, 0]
    "values"          => [0, 0]
    "has_key?"        => [1, 1]
    "key?"            => [1, 1]
    "abs"             => [0, 0]
    "respond_to?"     => [1, 1]
    "is_a?"           => [1, 1]
    "freeze"          => [0, 0]
    "frozen?"         => [0, 0]
    "ljust"           => [1, 2]
    "rjust"           => [1, 2]
    "center"          => [1, 2]
    "round"           => [0, 1]
    "to_i"            => [0, 1]
    "to_s"            => [0, 0]
    "class"           => [0, 0]
    => nil

# For the arms whose contract depends on the receiver (Array#max vs Int#max).
-> builtin_expect_argc(interp, name, args, block, min_argc, max_argc)
  if env("TUNGSTEN_ARITY") == "off"
    return nil
  argc = args.size()
  if block != nil
    argc += 1
  if !builtin_arity_accepts?([min_argc, max_argc], argc)
    interp.raise_typed("ArgumentError", arity_contract_message(name, [min_argc, max_argc], argc))
  nil

-> dispatch_builtin(interp, name, recv, args, block)
  if interp.sandboxed?()
    stub = interp.sandbox_builtin(name)
    if stub != nil
      return stub[0]
  # A lambda passed as the last positional argument to a block-taking
  # builtin IS the block — `arr.reject(-> (s) s.empty?)` and the trailing
  # form `arr.reject -> (s) s.empty?` are the same call in the compiled
  # engine; mirror that here. Closure values are [Environment, block-node]
  # pairs (see the :block arm of Interpreter#evaluate). Only block-taking
  # names promote: a lambda pushed with `arr.push(f)` must stay an argument.
  if block == nil && args.size() > 0 && name in ("each" "map" "select" "reject" "reduce" "each_with_index" "map_with_index" "any?" "all?" "find" "count" "times")
    cand = args[args.size() - 1]
    if type(cand) == "Array" && cand.size() == 2 && is_ast_node?(cand[1]) && ast_kind(cand[1]) == :block
      block = cand
      args = args.copy(0, args.size() - 1)

  case name
  # -- I/O --
  when "puts"
    args.each -> interp.output_line(interp.w_to_s(arg))
    nil

  when "print"
    args.each -> (a)
      interp.output_text(interp.w_to_s(a))
    nil

  when "read_file"
    read_file(args[0])

  when "read_file_bytes"
    read_file_bytes(args[0])

  when "file?"
    content = read_file(args[0])
    content != nil

  when "file_exists?"
    file_exists?(args[0])

  when "file_directory?"
    file_directory?(args[0])

  when "read_dir"
    read_dir(args[0])

  when "file_pwd"
    ccall("__w_file_pwd")

  when "file_chdir"
    ccall("__w_file_chdir", args[0])

  when "file_mkdir"
    ccall("__w_file_mkdir", args[0], args[1])

  when "file_rmdir"
    ccall("__w_file_rmdir", args[0])

  when "file_size"
    file_size(args[0])

  when "file_mtime_ns"
    file_mtime_ns(args[0])

  when "file_expand_path"
    ccall("__w_file_expand_path", args[0])

  when "file_expand_path_base"
    ccall("__w_file_expand_path_base", args[0], args[1])

  when "file_realpath"
    ccall("__w_file_realpath", args[0])

  when "file_readlink"
    ccall("__w_file_readlink", args[0])

  when "file_symlink"
    ccall("__w_file_symlink", args[0], args[1])

  when "file_basename"
    ccall("__w_file_basename", args[0])

  when "file_dirname"
    ccall("__w_file_dirname", args[0])

  when "file_extname"
    ccall("__w_file_extname", args[0])

  when "file_join"
    ccall("__w_file_join", args[0], args[1])

  when "write_file"
    write_file(args[0], args[1])

  when "write_file_bytes"
    write_file_bytes(args[0], args[1])

  when "file_stat_data"
    ccall("__w_file_stat_data", args[0], args[1])

  when "tempfile_create"
    ccall("__w_tempfile_create", args[0], args[1])

  when "file_unlink"
    ccall("__w_unlink", args[0])

  when "file_unlink_strict"
    ccall("__w_file_unlink_strict", args[0])

  when "file_link"
    ccall("__w_file_link", args[0], args[1])

  when "file_chmod"
    ccall("__w_file_chmod", args[0], args[1])

  when "file_touch"
    ccall("__w_file_touch", args[0])

  when "file_rename"
    ccall("__w_rename", args[0], args[1])

  when "file_temp_for"
    ccall("__w_temp_file_for", args[0])

  when "file_fsync"
    ccall("__w_fsync_path", args[0])

  when "file_fsync_parent"
    ccall("__w_fsync_parent", args[0])

  when "cache_read"
    cache_read(args[0])

  when "cache_write"
    cache_write(args[0], args[1])

  when "freeze_slab"
    if args.size() != 0
      raise "freeze_slab expects no arguments"
    ccall("w_slab_freeze_safe")

  when "exit"
    if args.empty?()
      exit 0
    else
      exit args[0]

  # -- Type info --
  when "type"
    # Bare type(value) arrives with the value in args and a nil top-level
    # receiver; receiver-style dispatch has no explicit argument.
    # Use w_type_name so interpreter objects ({rt: :object, w_class: …})
    # report their class name rather than "Hash" (their storage shape).
    target = args.empty?() ? recv : args[0]
    interp.w_type_name(target)

  when "to_s"
    interp.w_to_s(recv)

  when "to_i"
    if args.empty?()
      interp.w_to_s(recv).to_i()
    else
      interp.w_to_s(recv).to_i(args[0])

  when "class"
    interp.w_type_name(recv)

  # -- String methods --
  when "length", "size"
    recv.size()

  when "chars"
    recv.chars()

  when "split"
    if args.empty?()
      return recv.split()

    recv.split(args[0])

  when "strip"
    recv.strip()

  when "ltrim"
    recv.ltrim()

  when "rtrim"
    recv.rtrim()

  when "ascii?"
    recv.ascii?()

  when "valid_utf8?"
    recv.valid_utf8?()

  when "replace"
    recv.replace(args[0], args[1])

  when "starts_with?"
    recv.starts_with?(args[0])

  when "ends_with?"
    recv.ends_with?(args[0])

  when "upcase"
    recv.upcase()

  when "downcase"
    recv.downcase()

  when "swapcase"
    recv.swapcase()

  when "capitalize"
    recv.capitalize()

  when "include?"
    recv.include?(args[0])

  when "index"
    # Optional second arg is the search start offset (String#index(needle,
    # offset)); the compiled engine honors it (w_ic_string_index), so forward
    # it rather than silently searching from 0.
    if args.size() == 2
      return recv.index(args[0], args[1])
    recv.index(args[0])

  when "rindex"
    # Optional second arg caps the match start (Ruby rindex semantics),
    # mirroring the compiled w_ic_string_rindex.
    if args.size() == 2
      return recv.rindex(args[0], args[1])
    recv.rindex(args[0])

  when "gsub"
    # Plain-string patterns only — identical to the compiled engine, whose
    # gsub IC row routes to the same literal replace-all handler as replace
    # (w_ic_string_replace); neither engine does regex substitution here.
    recv.replace(args[0], args[1])

  when "concat"
    recv.concat(args[0])

  when "append"
    # StringBuffer is handled in interpreter dispatch_method before builtins;
    # other receivers (String) use concat.
    recv.concat(args[0])

  when "prepend"
    recv.prepend(args[0])

  when "zip"
    recv.zip(args[0])

  when "reverse"
    recv.reverse()

  when "slice"
    if args.size() == 2
      return recv.slice(args[0], args[1])

    recv.slice(args[0])

  # arr.slice renamed to arr.copy for clarity (slice now connotes
  # the zero-copy `arr[from..to]` view). Strings/bytes still use .slice.
  when "copy"
    if args.size() == 2
      return recv.copy(args[0], args[1])

    recv.copy(args[0])

  # -- Array methods --
  when "push"
    args.each -> recv.push(arg)

    recv

  when "pop"
    recv.pop()

  when "shift"
    recv.shift()

  when "unshift"
    raise "unshift requires 1 argument" if args.empty?()
    recv.unshift(args[0])

  when "first"
    recv.first()

  when "last"
    recv.last()

  when "empty?"
    recv.empty?()

  when "nil?"
    recv == nil

  when "join"
    if args.empty?()
      mapped = recv.map -> (e)
        interp.w_to_s(e)
      return mapped.join("")
    mapped = recv.map -> (e)
      interp.w_to_s(e)

    mapped.join(args[0])

  when "sort"
    recv.sort()

  when "flatten"
    recv.flatten()

  when "uniq"
    recv.uniq()

  when "delete"
    recv.delete(args[0])

  # -- Array methods with blocks --
  when "each"
    # Hash#each yields (key, value) — a fixed single-param wrapper would
    # silently drop the value, so forward both only for Hash receivers.
    if type(recv) == "Hash"
      recv.each -> (k, v)
        interp.call_block(block, [k, v])
    else
      recv.each -> (elem)
        interp.call_block(block, [elem])

    recv

  when "map"
    # Hash#map yields (key, value) — forward both, like Hash#each above; a
    # single-param wrapper drops the value and a `-> (k, v)` block then sees
    # v == nil (crashes on `v * 2`). Non-hash receivers keep the iteratee path
    # (symbol iteratees like map(:to_s) resolve there).
    if type(recv) == "Hash"
      recv.map -> (k, v)
        interp.call_block(block, [k, v])
    else
      recv.map -> (elem)
        interp.apply_iteratee(block, args, elem)

  when "select"
    if type(recv) == "Hash"
      recv.select -> (k, v)
        interp.truthy?(interp.call_block(block, [k, v]))
    else
      recv.select -> (elem)
        interp.truthy?(interp.apply_iteratee(block, args, elem))

  when "reject"
    if type(recv) == "Hash"
      recv.reject -> (k, v)
        interp.truthy?(interp.call_block(block, [k, v]))
    else
      recv.reject -> (elem)
        interp.truthy?(interp.apply_iteratee(block, args, elem))

  when "reduce"
    if args.empty?()
      return recv.reduce -> (acc, elem)
        interp.call_block(block, [acc, elem])

    recv.reduce(args[0]) -> (acc, elem)
      interp.call_block(block, [acc, elem])

  when "each_with_index"
    recv.each_with_index -> (elem, idx)
      interp.call_block(block, [elem, idx])

    recv

  when "map_with_index"
    recv.map_with_index -> (elem, idx)
      interp.call_block(block, [elem, idx])

  when "any?"
    if block == nil
      recv.any?
    elsif type(recv) == "Hash"
      recv.any? -> (k, v)
        interp.truthy?(interp.call_block(block, [k, v]))
    else
      recv.any? -> (elem)
        interp.truthy?(interp.apply_iteratee(block, args, elem))

  when "all?"
    if block == nil
      recv.all?
    elsif type(recv) == "Hash"
      recv.all? -> (k, v)
        interp.truthy?(interp.call_block(block, [k, v]))
    else
      recv.all? -> (elem)
        interp.truthy?(interp.apply_iteratee(block, args, elem))

  when "find"
    if type(recv) == "Hash" && block != nil
      recv.find -> (k, v)
        interp.truthy?(interp.call_block(block, [k, v]))
    else
      recv.find -> (elem)
        interp.truthy?(interp.apply_iteratee(block, args, elem))

  when "count"
    # No block/arg: number of elements. With a block or a method symbol
    # (count(:prime?)): number of elements whose iteratee result is truthy.
    if block == nil && args.empty?()
      return recv.size()
    n = 0
    if type(recv) == "Hash" && block != nil
      recv.each -> (k, v)
        if interp.truthy?(interp.call_block(block, [k, v]))
          n = n + 1
    else
      recv.each -> (elem)
        if interp.truthy?(interp.apply_iteratee(block, args, elem))
          n = n + 1
    n

  when "sum"
    # sum(init) seeds the accumulator (Ruby Enumerable#sum(init)) —
    # mirrors the compiled engine's w_ic_array_sum, whose same
    # dropped-arg bug was fixed in e857a36. Previously sum(10) == sum()
    # and [].sum(5) == 0 here.
    total = 0
    if args.size() > 0
      total = args[0]
    recv.each -> (elem)
      total = total + elem
    total

  when "times"
    recv.times -> (i)
      interp.call_block(block, [i])

    recv

  # -- Hash methods --
  when "keys"
    recv.keys()

  when "values"
    recv.values()

  when "has_key?"
    recv.has_key?(args[0])

  when "key?"
    recv.key?(args[0])

  # -- Numeric methods --
  when "abs"
    recv.abs()

  when "max"
    if type(recv) == "Array"
      builtin_expect_argc(interp, name, args, block, 0, 0)
      return recv.max()
    builtin_expect_argc(interp, name, args, block, 1, 1)
    recv.max(args[0])

  when "min"
    if type(recv) == "Array"
      builtin_expect_argc(interp, name, args, block, 0, 0)
      return recv.min()
    builtin_expect_argc(interp, name, args, block, 1, 1)
    recv.min(args[0])

  # -- Object introspection --
  when "respond_to?"
    interp.respond_to_method?(recv, args[0])

  when "is_a?"
    interp.is_a_class?(recv, args[0])

  when "freeze"
    ccall("w_freeze", recv)

  when "frozen?"
    ccall("w_frozen_p", recv)

  when "argv"
    interp.argv()

  when "gets"
    gets()

  when "clock"
    clock()

  when "clock_ms"
    clock_ms()

  when "runtime_identity"
    runtime_identity()

  # hashing.w uses the native string digest when the interpreter itself is a
  # compiled compiler. Stage 0 and Ruby keep taking hashing.w's portable path;
  # this arm prevents `tungsten run` from treating the runtime bridge as an
  # unknown user function.
  when "digest_string64"
    digest_string64(args[0])

  when "capture"
    capture(args[0])

  when "system"
    system(args[0])

  when "env"
    env(args[0])

  # Host-topology and file bridges the compiled path routes through
  # known_calls (lowering.w); the tree-walker reaches the same runtime
  # symbols directly.
  when "cpu_count"
    ccall("__w_cpu_count")

  when "l1d_cache_bytes"
    ccall("__w_l1d_cache_bytes")

  when "l2_cache_bytes"
    ccall("__w_l2_cache_bytes")

  when "cpus_per_l2"
    ccall("__w_cpus_per_l2")

  when "write_file_bytes_n"
    ccall("__w_write_file_n", args[0], args[1], args[2])

  when "file_rm"
    ccall("__w_file_rm", args[0])

  when "ljust"
    s = recv
    width = args[0]
    fill = args.size() > 1 ? args[1] : " "
    cur = s.size()
    if cur >= width
      return s
    pad = (fill * (width - cur)).slice(0, width - cur)
    s + pad

  when "rjust"
    s = recv
    width = args[0]
    fill = args.size() > 1 ? args[1] : " "
    cur = s.size()
    if cur >= width
      return s
    pad = (fill * (width - cur)).slice(0, width - cur)
    pad + s

  when "center"
    s = recv
    width = args[0]
    fill = args.size() > 1 ? args[1] : " "
    cur = s.size()
    if cur >= width
      return s
    total = width - cur
    left = total / 2
    right = total - left
    lf = (fill * left).slice(0, left)
    rf = (fill * right).slice(0, right)
    lf + s + rf

  when "round"
    if args.empty?()
      return recv.round()
    recv.round(args[0])

  else
    raise "Unknown builtin method '[name]'"

# List of builtin names
builtin_names = [
  "puts", "print", "read_file", "read_file_bytes", "file?", "file_exists?", "file_directory?", "read_dir",
  "file_pwd", "file_chdir", "file_mkdir", "file_rmdir", "file_size", "file_mtime_ns", "file_expand_path", "file_expand_path_base", "file_join", "file_basename", "file_dirname", "file_extname", "file_realpath", "file_readlink", "file_symlink", "write_file", "write_file_bytes", "file_stat_data", "tempfile_create", "file_unlink", "file_unlink_strict",
  "file_link", "file_chmod", "file_touch", "file_rename", "file_temp_for", "file_fsync", "file_fsync_parent",
  "cache_read", "cache_write",
  "exit", "type", "to_s", "to_i", "class",
  "length", "size", "chars", "split", "strip", "ltrim", "rtrim", "ascii?", "valid_utf8?", "replace", "starts_with?",
  "ends_with?", "upcase", "downcase", "swapcase", "capitalize", "include?", "index", "rindex", "gsub", "concat",
  "append", "prepend",
  "reverse", "slice", "copy", "push", "pop", "shift", "unshift", "first", "last", "empty?", "nil?",
  "join", "sort", "flatten", "uniq", "delete", "each", "map", "select",
  "reject", "reduce", "each_with_index", "map_with_index", "zip", "any?", "all?",
  "find", "count", "sum", "times", "keys", "values", "has_key?", "abs", "max", "min",
  "respond_to?", "is_a?", "freeze", "frozen?", "argv", "clock", "clock_ms", "runtime_identity", "digest_string64",
  "capture", "system", "env", "ljust", "rjust", "center", "round", "gets", "freeze_slab",
  "cpu_count", "l1d_cache_bytes", "l2_cache_bytes", "cpus_per_l2", "write_file_bytes_n", "file_rm",
  "flush"
]

-> is_builtin?(name)
  builtin_names.include?(name)
