# Built-in method dispatch for boot1's interpreter
# Called by the interpreter when a method is a builtin.
# The interp parameter is the Interpreter instance.

-> dispatch_builtin(interp, name, recv, args, block)
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
    args.each -> << interp.w_to_s(arg)
    nil

  when "print"
    args.each -> (a)
      <- interp.w_to_s(a)
    nil

  when "read_file"
    read_file(args[0])

  when "file?"
    content = read_file(args[0])
    content != nil

  when "file_mtime_ns"
    file_mtime_ns(args[0])

  when "cache_read"
    cache_read(args[0])

  when "cache_write"
    cache_write(args[0], args[1])

  when "exit"
    if args.empty?()
      exit 0
    else
      exit args[0]

  # -- Type info --
  when "type"
    # Bare type(value) arrives with the value in args and a nil top-level
    # receiver; receiver-style dispatch has no explicit argument.
    target = args.empty?() ? recv : args[0]
    type(target)

  when "to_s"
    interp.w_to_s(recv)

  when "to_i"
    interp.w_to_s(recv).to_i()

  when "class"
    type(recv)

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

  # Phase 4f: arr.slice renamed to arr.copy for clarity (slice now connotes
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
    if type(recv) == "Hash" && block != nil
      recv.any? -> (k, v)
        interp.truthy?(interp.call_block(block, [k, v]))
    else
      recv.any? -> (elem)
        interp.truthy?(interp.apply_iteratee(block, args, elem))

  when "all?"
    if type(recv) == "Hash" && block != nil
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
    total = 0
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
      return recv.max()

    recv.max(args[0])

  when "min"
    if type(recv) == "Array"
      return recv.min()

    recv.min(args[0])

  # -- Object introspection --
  when "respond_to?"
    interp.respond_to_method?(recv, args[0])

  when "is_a?"
    interp.is_a_class?(recv, args[0])

  when "freeze"
    recv

  when "argv"
    interp.argv()

  when "gets"
    gets()

  when "clock"
    clock()

  when "runtime_identity"
    runtime_identity()

  when "capture"
    capture(args[0])

  when "system"
    system(args[0])

  when "env"
    env(args[0])

  when "ljust"
    s = recv
    width = args[0]
    cur = s.size()
    if cur >= width
      return s
    pad = " " * (width - cur)
    s + pad

  when "rjust"
    s = recv
    width = args[0]
    cur = s.size()
    if cur >= width
      return s
    pad = " " * (width - cur)
    pad + s

  when "round"
    if args.empty?()
      return recv.round()
    recv.round(args[0])

  else
    raise "Unknown builtin method '[name]'"

# List of builtin names
builtin_names = [
  "puts", "print", "read_file", "file?", "file_mtime_ns", "cache_read", "cache_write",
  "exit", "type", "to_s", "to_i", "class",
  "length", "size", "chars", "split", "strip", "ltrim", "rtrim", "ascii?", "valid_utf8?", "replace", "starts_with?",
  "ends_with?", "upcase", "downcase", "swapcase", "capitalize", "include?", "index", "rindex", "gsub", "concat",
  "append", "prepend",
  "reverse", "slice", "copy", "push", "pop", "first", "last", "empty?", "nil?",
  "join", "sort", "flatten", "uniq", "delete", "each", "map", "select",
  "reject", "reduce", "each_with_index", "map_with_index", "zip", "any?", "all?",
  "find", "count", "sum", "times", "keys", "values", "has_key?", "abs", "max", "min",
  "respond_to?", "is_a?", "freeze", "argv", "clock", "runtime_identity",
  "capture", "system", "env", "ljust", "rjust", "round", "gets"
]

-> is_builtin?(name)
  builtin_names.include?(name)
