+ Interpreter

  -> dispatch_method(recv, name, args, block, env)
    # A closure value (an [env, block-node] pair) responds to `.call(args)` by
    # invoking the block. Mirrors the compiled method-dispatch-on-closure path
    # (runtime.c w_closure_call_N) and the bare-call closure dispatch in
    # dispatch_bare_call, so `f.call(x)` and `f(x)` behave the same.
    if name in ("arity" "curry") && type(recv) == "Array" && recv.size() == 2 && is_ast_node?(recv[1]) && ast_kind(recv[1]) == :block
      closure_arity = ast_get(recv[1], :params).size()
      if name == "arity"
        return closure_arity
      curry_n = closure_arity
      if args.size() > 0 && args[0] != nil
        curry_n = args[0]
      if curry_n <= 1
        return recv
      if curry_n > 4
        raise "curry supports closures of arity 1..4, got " + curry_n.to_s()
      # ->(__ca1) ->(__ca2) ... __cf.call(__ca1, ..., __caN), evaluated with
      # __cf bound to the receiver — the same shape core/closure.w builds.
      curry_env = Environment.new(env, true)
      curry_env.define("__cf", recv)
      call_args = []
      ci = 0
      while ci < curry_n
        call_args.push(Tungsten:AST:Var.new("__ca" + (ci + 1).to_s()))
        ci += 1
      inner = Tungsten:AST:Call.new(Tungsten:AST:Var.new("__cf"), "call", call_args, nil)
      ci = curry_n
      while ci >= 1
        inner = Tungsten:AST:Block.new(["__ca" + ci.to_s()], [inner])
        ci -= 1
      return evaluate(inner, curry_env)
    if name == "call" && type(recv) == "Array" && recv.size() == 2 && is_ast_node?(recv[1]) && ast_kind(recv[1]) == :block
      return call_block(recv, args)

    # Universal spaceship: a <=> b → -1/0/1 (nil if incomparable). Mirrors the
    # compiled path's universal w_spaceship in w_method_dispatch so ordered
    # primitives (Integer/Float/String/…) get Comparable under quick-run too.
    # User objects with their own <=> resolve via the class method lookup
    # below, which is reached only for :object receivers.
    if name == "<=>" && args.size() == 1 && !(type(recv) == "Hash" && recv.has_key?(:rt) && recv[:rt] == :object)
      other = args[0]
      if recv < other
        return -1
      if recv > other
        return 1
      return 0

    # Universal: .class returns the class object; .class_name returns
    # the class name string. Mirrors the compiled-path intercept in
    # lowering/calls.w so primitives and user instances behave the same
    # under bin/tungsten -e and the REPL.
    # Class receivers fixpoint at the "Class" singleton: Integer.class,
    # Class.class, and 4.class.class.class all return the same value.
    if name == "class_name" && args.size() == 0
      if type(recv) == "Hash" && recv.has_key?(:rt) && recv[:rt] == :class
        return "Class"
      if type(recv) == "Hash" && recv.has_key?(:rt) && recv[:rt] == :object
        return recv[:w_class][:name]
      return type(recv)
    if name == "class" && args.size() == 0
      if type(recv) == "Hash" && recv.has_key?(:rt) && recv[:rt] == :class
        return class_class_singleton()
      if type(recv) == "Hash" && recv.has_key?(:rt) && recv[:rt] == :object
        return recv[:w_class]
      cname = type(recv)
      if @classes.has_key?(cname)
        return @classes[cname]
      stub = {rt: :class, name: cname, methods: {}, method_overloads: {}, class_methods: {}, class_method_overloads: {}, parent: nil}
      @classes[cname] = stub
      return stub
    # `.name` on a class returns its name string (Integer.name -> "Integer").
    if name == "name" && args.size() == 0 && type(recv) == "Hash" && recv.has_key?(:rt) && recv[:rt] == :class
      return recv[:name]

    # Math.* libm intrinsics — the compiled path lowers these directly
    # (lowering/calls.w); the tree-walker routes them to the same WValue-ABI
    # runtime wrappers so the doc examples run under `tungsten run` too.
    if type(recv) == "Hash" && recv.has_key?(:rt) && recv[:rt] == :class && recv[:name] == "Math"
      m = eval_math_intrinsic(name, args)
      if m != nil
        return m

    # Class methods (`-> .parse`) live on the class object, distinct from
    # instance methods/constructors (`-> parse`, `-> new`).
    if type(recv) == "Hash" && recv.has_key?(:rt) && recv[:rt] == :class
      m = lookup_class_method(recv, name, args.size(), block != nil, args)
      if m != nil
        return call_w_method(recv, m, args, block, env)

    # Class.new constructor
    if name == "new" && type(recv) == "Hash" && recv.has_key?(:rt) && recv[:rt] == :class
      if recv[:name] == "Atomic"
        if args.size() != 1
          raise "Atomic.new expects one argument"
        return ccall("w_atomic_new", args[0])
      if recv[:name] == "Channel"
        if args.size() != 1
          raise "Channel.new expects one argument"
        return ccall("w_chan_new", args[0])
      if recv[:name] == "Thread"
        if block == nil
          raise "Thread.new requires a block"
        result = call_block0(block)
        return {rt: :object, w_class: recv, ivars: {"@__thread_result" => result, "@__thread_alive" => false, "@__thread_killed" => false}}
      return instantiate(recv, args, env)

    # Thread.new runs synchronously in the tree walker. Retained native
    # join/kill declarations therefore need a small fake-handle equivalent.
    if interpreted_thread?(recv)
      if name == "join"
        if args.size() > 0
          return true
        return recv[:ivars]["@__thread_result"]
      if name == "kill"
        recv[:ivars]["@__thread_alive"] = false
        recv[:ivars]["@__thread_killed"] = true
        return nil

    # Method on object
    if type(recv) == "Hash" && recv.has_key?(:rt) && recv[:rt] == :object
      m = lookup_method(recv[:w_class], name, args.size(), block != nil, args)
      if m != nil
        # Implicit construction from the receiver's class: a one-param
        # method called with N>1 args builds its argument from the
        # receiver's own class when the constructor arity matches —
        # p.distance(2, 3, 4) ≡ p.distance(Point.new(2, 3, 4)). Mirrors
        # the runtime dispatch rule.
        if args.size() > 1 && m[:params] != nil && m[:params].size() == 1
          ctor = lookup_method(recv[:w_class], "new")
          if ctor != nil && ctor[:params] != nil && ctor[:params].size() == args.size()
            inst = instantiate(recv[:w_class], args, env)
            return call_w_method(recv, m, [inst], block, env)
        return call_w_method(recv, m, args, block, env)

    # Builtin Object#hash is supplied by the runtime after ordinary class
    # lookup, so explicit user overrides above still win. Delegate primitive
    # values and containers to the same structural/identity split used by the
    # compiled dispatcher instead of executing a bodyless Core declaration.
    if name == "hash" && args.size() == 0
      return ccall("w_method_call", recv, "hash", [])

    # String/Symbol#to_sym remains a native String IC. Mirror it directly:
    # routing through w_method_call would manufacture and recycle an argument
    # Array inside the interpreter and has a mixed-ABI failure in self-hosts.
    if type(recv) in ("String" "Symbol") && name == "to_sym"
      # type(WRope) is String, but w_str_to_sym itself only sets the Symbol
      # marker bit. Canonicalize first so an interpreted rope never turns its
      # pointer word into a malformed Symbol value.
      recv = ccall("w_rope_flatten", recv)
      return ccall("w_str_to_sym", recv)

    # String and Symbol share compiled method dispatch but not public type
    # identity. Answer this before primitive-class autoload so a Symbol check
    # never depends on parsing the legacy Symbol scaffold reentrantly.
    if type(recv) in ("String" "Symbol") && name == "is_a?" && args.size() == 1
      return is_a_class?(recv, args[0])

    # Native-engine regex objects (String#to_regex under the tree walker;
    # compiled regex literals never reach here) have no source class — the
    # source Regex engine's methods read ivars a native object lacks. Route
    # the match surface straight through the native engine.
    if type(recv) == "Regex" && ccall_nobox("w_is_native_regex", recv) == 1
      if name in ("match?" "===" "=~") && args.size() == 1
        return ccall("w_regex_match", recv, args[0])
      if name == "scan" && args.size() == 1
        return ccall("w_regex_scan", recv, args[0])
      raise "native regex supports match?/===/=~/scan under the interpreter (got [name])"

    # Primitive values can be extended by core classes (Array, String, etc.).
    # Give those class methods first refusal before falling back to boot
    # builtins so traits such as Enumerable participate for primitive arrays.
    primitive_class = nil
    # Compiled String and Symbol values share dispatch key 0xF9, so the source
    # String methods are also Symbol#to_s/#empty?/#size/#length. The tree walker
    # ordinarily distinguishes host Symbols from Strings; route these shared
    # methods through String instead of the legacy Symbol scaffold.
    if type(recv) == "Symbol" && name in ("to_s" "empty?" "size" "length" "ascii?" "blank?" "byte_at" "bytes" "codepoints" "characters" "each_byte" "each_codepoint" "each_character" "each_line" "lines" "contains?" "levenshtein" "nfc" "nfd" "nfkc" "nfkd" "normalize" "graphemes" "each_grapheme" "scan" "to_regex" "constantize")
      try_autoload_class("String")
      primitive_class = @classes["String"]
    else
      primitive_class = primitive_runtime_class(recv)
    if primitive_class != nil
      # The native WN_sort IC row intercepts every compiled blockless
      # `sort` dispatch before the type-class body is consulted. Mirror
      # that interception here (host .sort() rides the same IC row). A
      # comparator block must NOT take this shortcut: it falls through to
      # Array#sort(&), whose source body tree-walks the stable
      # __mergesort_copy (the compiled engine's IC row routes its blocked
      # calls to the runtime twin, w_array_sort_block).
      if primitive_class[:name] == "Array" && name == "sort" && type(recv) == "Array" && args.empty?() && block == nil
        return recv.sort()
      # BigInt#+ carries a compile-only embedded limb kernel; the walker
      # delegates the selector to the same exported C boundary the kernel's
      # fallback arms use, exactly like compiled infix `+` reaching the
      # runtime arm. Values are engine-identical either way.
      if primitive_class[:name] == "BigInt" && name in ("+" "-" "*" "&" "|" "^" "/" "%") && args.size() == 1 && block == nil
        if name == "+"
          return ccall("w_bigint_add", recv, args[0])
        if name == "*"
          return ccall("w_mul", recv, args[0])
        if name == "&"
          return ccall("w_bit_and", recv, args[0])
        if name == "|"
          return ccall("w_bit_or", recv, args[0])
        if name == "^"
          return ccall("w_bit_xor", recv, args[0])
        if name == "/"
          return ccall("w_div", recv, args[0])
        if name == "%"
          return ccall("w_mod", recv, args[0])
        return ccall("w_bigint_sub", recv, args[0])
      m = lookup_method(primitive_class, name, args.size(), block != nil, args)
      # BigInt#isqrt's one/two-limb native leaf is an embedded LLVM function,
      # which the tree walker cannot execute. Delegate only the Core-owned
      # body to its exact retained C boundary; a user reopen has another file
      # and continues through ordinary last-definition method dispatch.
      if primitive_class[:name] == "BigInt" && name == "isqrt" && args.empty?() && block == nil && m != nil && m[:file] != nil && m[:file].ends_with?("core/numeric/big_int.w")
        return ccall("bigint_isqrt_any", recv)
      # For names the interpreter implements as builtins, a TRAIT DEFAULT
      # must not preempt the builtin: the builtins mirror the compiled
      # engine's native IC rows and proven host semantics (Enumerable's
      # include?, for one, mis-executes under the tree walker's closure
      # `return`). A class's OWN source method still wins over the builtin,
      # exactly as before traits were spliced for autoloaded core classes;
      # trait defaults serve only the names no builtin covers (sort_by,
      # min_by, max_by, …).
      if m != nil && m[:trait_default] == true && is_builtin?(name)
        m = nil
      # StringBuffer's core file contains bodyless primitive declarations as
      # well as the source-backed size body. After correcting the class name
      # so its type class can register, those declarations must remain
      # fallthroughs to the interpreter/runtime builtins rather than execute
      # as empty source methods returning nil.
      if m != nil && primitive_class[:name] == "StringBuffer"
        method_body = m[:body]
        if method_body == nil || method_body.size() == 0
          # Bodyless native declarations fall through to runtime. `append`
          # must mutate via w_strbuf_append (not String#concat).
          if name == "append" && args.size() == 1
            ccall("w_strbuf_append", recv, w_to_s(args[0]))
            return recv
          if name == "<<" && args.size() == 1
            ccall("w_strbuf_append", recv, w_to_s(args[0]))
            return recv
          if name == "to_s" && args.size() == 0
            return ccall("w_strbuf_to_s", recv)
          if name in ("length" "byte_size" "\[]" "[]" "clear" "empty?" "include?" "starts_with?")
            native_name = name == "\[]" ? "[]" : "" + name
            return ccall("w_method_call", recv, native_name, args)
          m = nil
      # Decimal's bodyless conversion/rounding declarations are native IC
      # methods. Several names are also generic interpreter builtins (`to_i`,
      # `floor`, ...), whose host-oriented behavior stringifies or coerces the
      # receiver and is not Decimal's exact runtime contract. Delegate these
      # declarations before the generic bodyless fallthrough so the tree
      # walker and compiled engine use the same handlers.
      if m != nil && primitive_class[:name] == "Decimal"
        method_body = m[:body]
        if (method_body == nil || method_body.size() == 0) && name in ("abs" "to_f" "to_i" "to_d" "floor" "ceil" "round" "sqrt" "sq")
          return ccall("w_method_call", recv, "" + name, args)
      # A bodyless `-> name` on a runtime-backed receiver is a native/
      # abstract DECLARATION, never a nil-returning empty body — the
      # compiled engine dispatches these to the runtime's handlers. Fall
      # through to the builtin/runtime delegation below instead of
      # "executing" nothing. This generalizes the former Mmap/Thread
      # special cases and covers every all-facade core class (Decimal's
      # floor/round declarations were being run as empty bodies, which
      # crashed evaluating their `digits = scale` default). data_field
      # accessors are exempt: they are handled by the dedicated branch
      # underneath.
      if m != nil && m[:data_field] != true
        method_body = m[:body]
        if method_body == nil || method_body.size() == 0
          m = nil
      # `- data` accessors model ivars for ordinary interpreted objects. A
      # small set of runtime-backed classes expose scalar layout fields through
      # w_native_data_field; fixed arrays and every other native layout stay on
      # the ordinary accessor path. This keeps the tree walker from pretending
      # it can decode layouts the storage boundary does not implement.
      if m != nil && m[:data_field] == true
        # Only a bare field access (no block, no args) reads the raw storage
        # scalar. `h.count -> (k, v)` / `h.count(:sym)` are Enumerable calls,
        # not the `count` storage field — they must fall through to the builtin
        # instead of returning the element count and ignoring the block.
        if block == nil && args.empty?() && native_data_field_supported?(primitive_class, name)
          return ccall("w_native_data_field", recv, name)
        # A generated storage accessor must not shadow a semantic runtime
        # method with the same name (notably Hash#keys and Hash#values).
        m = nil
      if m != nil
        # Compiled cached dispatch flattens ropes before invoking a String
        # source method. Do this only after such a method was found so other
        # interpreted primitive calls pay no new type check.
        if m[:w_class] != nil && m[:w_class][:name] == "String"
          recv = ccall("w_rope_flatten", recv)
        return call_w_method(recv, m, args, block, env)

      # Error-sensitive byte_at, common-spelling close/subscript, and the
      # mixed-decoder view_at remain native; only typed-view leaves use source.
      if primitive_class[:name] == "Mmap" && name in ("close" "byte_at" "\[]" "[]" "view_at")
        native_name = name == "\[]" ? "[]" : "" + name
        return ccall("w_method_call", recv, native_name, args)

      # The other synchronization selectors intentionally retain their native
      # IC rows; route them there after giving the four source leaves priority.
      if primitive_class[:name] == "Atomic" && name in ("cas" "get" "set" "add")
        return ccall("w_method_call", recv, "" + name, args)
      if primitive_class[:name] == "Channel" && name in ("send" "close")
        return ccall("w_method_call", recv, "" + name, args)
      if primitive_class[:name] == "Thread" && name in ("join" "kill")
        return ccall("w_method_call", recv, "" + name, args)
      # String#lchs is a native lexer primitive rather than a Core source
      # method. Keep the tree walker on the same WValue-preserving runtime
      # path as compiled code so compiler-facing storage specs exercise both
      # engines.
      if primitive_class[:name] == "String" && name == "lchs"
        return ccall("w_method_call", recv, "lchs", args)

    # Range methods
    if type(recv) == "Hash" && recv.has_key?(:rt) && recv[:rt] == :range
      from = recv[:from]
      to = recv[:to]
      # A bound can be a whole-valued Decimal (`1e10`, common
      # scientific-notation shorthand for a big integer) — none of the
      # arithmetic/comparisons below (`+`, `<`, `-`) handle Decimal, so
      # coerce upfront (mirrors the compiled lowering's w_range_bound_i64).
      # Gated on the runtime class specifically (not just "not Integer")
      # so non-numeric bounds — a Char range's `:-A..:-Z`, say — pass
      # through unchanged; only Decimal is a confirmed-broken case.
      if from != nil && type(from) != "Int" && ccall("w_class_name", from) == "Decimal"
        from = ccall("w_range_bound_i64_w", from)
      if to != nil && type(to) != "Int" && ccall("w_class_name", to) == "Decimal"
        to = ccall("w_range_bound_i64_w", to)
      excl = recv[:exclusive]
      unbounded = to == nil
      if name == "each" && block != nil
        i = from
        limit = 0
        if !unbounded
          limit = excl ? to : to + 1
          linear = range_block_linear_update(block)
          if linear != nil && type(from) == "Int" && type(limit) == "Int"
            iterations = limit - from
            if iterations < 0
              iterations = 0
            linear[0].set(linear[1], linear[0].get(linear[1]) + linear[2] * iterations)
            return nil
        reuse_env = reusable_block_environment(block)
        if block_can_break?(block)
          while unbounded || i < limit
            begin
              call_block1(block, i, reuse_env)
            rescue err
              if err == "__SIGNAL__" && @signal[:type] == :break
                @signal[:type] = nil
                break
              elsif err == "__SIGNAL__" && @signal[:type] == :next
                @signal[:type] = nil
              else
                raise err
            i = i + 1
        else
          # call_block1 owns `next`; without a syntactic non-local break this
          # second handler only rethrows ordinary errors, so omit it entirely.
          while unbounded || i < limit
            call_block1(block, i, reuse_env)
            i = i + 1
        return nil
      if name == "step" && args.size() == 1
        raise "cannot call .step on unbounded range" if unbounded
        if block != nil
          i = from
          limit = excl ? to : to + 1
          reuse_env = reusable_block_environment(block)
          if block_can_break?(block)
            while i < limit
              begin
                call_block1(block, i, reuse_env)
              rescue err
                if err == "__SIGNAL__" && @signal[:type] == :break
                  @signal[:type] = nil
                  break
                elsif err == "__SIGNAL__" && @signal[:type] == :next
                  @signal[:type] = nil
                else
                  raise err
              i += args[0]
          else
            while i < limit
              call_block1(block, i, reuse_env)
              i += args[0]
          return nil
        return eval_range_step(recv, args[0])
      if name == "map" && block != nil
        raise "cannot call .map on unbounded range" if unbounded
        result = []
        i = from
        limit = excl ? to : to + 1
        reuse_env = reusable_block_environment(block)
        while i < limit
          result.push(call_block1(block, i, reuse_env))
          i = i + 1
        return result
      if name == "to_a"
        raise "cannot call .to_a on unbounded range" if unbounded
        result = []
        i = from
        limit = excl ? to : to + 1
        while i < limit
          result.push(i)
          i = i + 1
        return result
      if name in ("length" "size")
        raise "cannot take .size of unbounded range" if unbounded
        if excl
          return to - from
        return to - from + 1

      # Any other method (count/select/reject/reduce/sum/min/max/sort/…):
      # materialize the bounded range to an array and dispatch there, where the
      # full Enumerable surface is implemented for primitives.
      if !unbounded
        arr = []
        i = from
        limit = excl ? to : to + 1
        while i < limit
          arr.push(i)
          i = i + 1
        return dispatch_method(arr, name, args, block, env)

    # Date formatting: `d.strftime(fmt)` and its core alias `d.to_s(fmt)`
    # are runtime-backed (w_ic_date_to_s) — the core/date.w declarations are
    # bodiless. Checked before the generic builtins: builtin to_s ignores
    # its arguments, which would drop the format string.
    if args.size() == 1 && name in ("strftime" "to_s") && w_type_name(recv) == "Date"
      return ccall("w_method_call", recv, "" + name, args)

    # Builtins
    if is_builtin?(name)
      return dispatch_builtin(self, name, recv, args, block)

    # Index operators. Arrays need Ruby `[]` semantics the tree-walker's host
    # `recv[idx]` does not reproduce here: a negative index wraps from the end
    # and a Range argument returns a sub-array slice (both work on the compiled
    # path via w_array_get / a runtime slice, but returned nil/empty under -e).
    if name == "\[]"
      if type(recv) == "Array" && args.size() == 1
        idx = args[0]
        if type(idx) == "Hash" && idx.has_key?(:rt) && idx[:rt] == :range
          asz = recv.size()
          af = idx[:from]
          af = af < 0 ? af + asz : af
          # Unbounded upper (`a[n..]` / `a[n...]`) runs through the end; the
          # `...` exclusivity only trims an EXPLICIT upper bound, so it must not
          # apply when there is none.
          if idx[:to] == nil
            at = asz - 1
          else
            at = idx[:to] < 0 ? idx[:to] + asz : idx[:to]
            at = idx[:exclusive] == true ? at - 1 : at
          out = []
          k = af
          while k <= at && k < asz
            out.push(recv[k]) if k >= 0
            k += 1
          return out
        if type(idx) == "Int" && idx < 0
          nidx = idx + recv.size()
          return nil if nidx < 0
          return recv[nidx]
      # `s[a..b]` on a String is a code-point substring. The compiled path
      # reaches w_string_slice_range through w_array_view_range's polymorphic
      # dispatch; call the same helper here so the engines cannot drift.
      if type(recv) == "String" && args.size() == 1
        sidx = args[0]
        if type(sidx) == "Hash" && sidx.has_key?(:rt) && sidx[:rt] == :range
          return ccall("w_string_slice_range", recv, sidx[:from], sidx[:to], sidx[:exclusive] == true)
      return recv[args[0]]
    if name == "\[]="
      recv[args[0]] = args[1]
      return args[1]
    if name == "flip" && args.size() == 1
      recv[args[0]] = !recv[args[0]]
      return nil

    # Parity is lowered inline on the compiled path; the runtime IC has no
    # handler, so compute it here so `n.even?` / `n.odd?` work under -e/--wit.
    if type(recv) == "Int" && args.size() == 0
      if name == "even?"
        return (recv % 2) == 0
      if name == "odd?"
        return (recv % 2) != 0

    # Methods the runtime's IC tables implement for primitives — delegate so
    # the tree-walker matches the compiled surface: conversions (to_f/to_i/
    # floor/ceil/round/chr/ord) plus the Int intrinsics (abs/sqrt/succ/prev/
    # negative?/prime? and the arg-taking gcd). Name-gated: anything else must
    # keep raising a catchable interpreter error (the runtime dispatcher exits
    # instead of raising). Block-taking intrinsics (times/each) are excluded —
    # w_method_call can't carry the block.
    if type(recv) != "Hash"
      if args.size() == 0 && name in ("to_f" "to_i" "floor" "ceil" "round" "chr" "ord" "codes" "prime?" "prime_12k?" "prime_30k?" "abs" "to_s" "sqrt" "sq" "succ" "prev" "negative?")
        return ccall("w_method_call", recv, "" + name, [])
      # `to_d` is receiver-gated: only String (exact-Decimal parse), Decimal
      # (identity), and Integer (scale-0 convert) have runtime IC handlers.
      # Other receivers keep the catchable undefined-method error below — the
      # runtime dispatcher exits instead of raising.
      if args.size() == 0 && name == "to_d"
        tdn = w_type_name(recv)
        if tdn == "String" || tdn == "Decimal" || tdn == "Int"
          return ccall("w_method_call", recv, "" + name, [])
      if args.size() == 1 && name == "gcd"
        return ccall("w_method_call", recv, "" + name, args)

    raise_typed("NoMethodError", "undefined method '[name]' for [w_to_s(recv)]")

  -> primitive_runtime_class(recv)
    class_name = nil
    t = type(recv)
    # A `:rt`-tagged hash is an INTERNAL representation, not a user Hash.
    # `(1..100)` evaluates to {rt: :range, from:, to:, exclusive:}, so
    # classifying it as Hash resolved `size` to Hash's `- data` layout field
    # and returned the hash's KEY COUNT — `(1..100).size` was 4 — while
    # `.to_a` died inside Hash#to_a. Claiming no primitive class lets
    # dispatch_method reach its dedicated range branch, which implements
    # size/length/to_a directly and materializes to an array for every other
    # Enumerable name. This must return EARLY, not merely leave class_name
    # nil: the `class_name == nil` fallback below re-derives the class from
    # w_type_name, which reports plain "Hash" for this value.
    if t == "Hash" && recv.has_key?(:rt) && recv[:rt] == :range
      return nil
    if t == "Array"
      class_name = "Array"
    elsif t == "String"
      class_name = "String"
    elsif t == "Int"
      # Host integers use the generic host type name, but Tungsten method
      # dispatch belongs to the auto-promoting Int facade. Int inherits the
      # representation-independent Integer algorithms.
      class_name = "Int"
    elsif t == "Hash"
      class_name = "Hash"
    elsif t == "Float"
      class_name = "Float"
    elsif t == "Symbol"
      class_name = "Symbol"
    elsif t == "NilClass"
      class_name = "Nil"
    elsif t == "TrueClass" || t == "FalseClass"
      class_name = "Bool"
    # These handles remain publicly Unknown; the private numeric support
    # boundary exists only so the tree walker can find their source facades.
    if class_name == nil && t == "Unknown"
      sync_kind = ccall("w_sync_handle_kind_support", recv)
      if sync_kind == 1
        class_name = "Atomic"
      elsif sync_kind == 2
        class_name = "Thread"
      elsif sync_kind == 3
        class_name = "Channel"
      elsif sync_kind == 4
        class_name = "Mutex"
    if class_name == nil
      tn = w_type_name(recv)
      # Generic-subtag runtime values report the host-level type "Object" to
      # the tree walker even when their native discriminator names a registered
      # core class (BigArray is one; SmallArray's object-like display follows
      # the same path). Ask the runtime only for that ambiguous bucket so
      # source methods on values created by a ccall can autoload normally.
      if tn == "Object"
        native_name = ccall("w_class_name", recv)
        if native_name != nil && native_name != "Object" && native_name != "Unknown"
          tn = native_name
      # Rich runtime literal types (Date/IPv4/IPv6/MAC/…) report their core
      # class through `type`. Literal syntax never names the class, so lazy
      # autoload may not have fired before a bodied helper is called.
      if tn != nil
        try_autoload_class(tn)
        if @classes.has_key?(tn)
          return @classes[tn]
      return nil
    # seed_primitive_class_stubs installs placeholders before any source is
    # evaluated, so merely finding a class entry does not mean its core
    # methods have been loaded. Let the registry's loaded-file guard make this
    # a one-time lazy load before looking up methods on primitive receivers.
    try_autoload_class(class_name)
    @classes[class_name]

  # Scalar fields whose C layout is mirrored by w_native_data_field. Fixed
  # arrays such as Array#_pad and IPv6#bytes are deliberately excluded: the
  # compiled view-field operation treats them as raw scalar loads, not Arrays.
  -> native_data_field_supported?(w_class, name)
    if w_class == nil
      return false
    cname = w_class[:name]
    if cname == "Array"
      return name in ("flags" "ebits" "start" "size" "cap" "slots")
    if cname == "BigArray"
      return name in ("ebits" "flags" "start" "size" "cap" "slots")
    if cname == "SmallArray"
      return name in ("ebits" "size" "slots")
    if cname == "Hash"
      return name in ("count" "capacity" "flags")
    if cname == "BigInt"
      # `limbs` is the indexed u64[] tail — served by the w_native_data_elem
      # bridge in eval_call/eval_call_assign, not by this scalar path.
      return name == "size"
    if cname == "StringBuffer"
      return name == "length"
    if cname == "Mmap"
      return name == "size"
    if cname in ("IPv6" "MAC")
      return name in ("len" "prefix" "_pad")
    false

  # Runtime-backed view writes are an unsafe core boundary, not general
  # reflection. Add entries only with a matching checked runtime setter.
  -> native_data_field_writable?(w_class, name)
    if w_class == nil
      return false
    w_class[:name] == "BigInt" && name == "size"

  -> native_data_field_declared?(w_class, name)
    w_class != nil && w_class[:data_fields] != nil && w_class[:data_fields].has_key?(name)

  # Resolve only source-defined methods for a receiver-less call inside a
  # method body. Runtime-backed values (Date/IPv4/IPv6/MAC/...) are not the
  # Hash-backed :object shape used by ordinary user instances, but their core
  # classes can still contain Tungsten method bodies that call sibling methods
  # through implicit self (Date#cwyear -> cweek, for example).
  #
  # Keep this lookup narrow: dispatch_bare_call retains its existing global and
  # builtin ordering, and does not recurse through dispatch_method (which would
  # consult builtins and the runtime IC again).
  # `args` (when the call site has evaluated them) flows to lookup_method
  # so same-arity typed overloads select by value on this path too — the
  # bare-sibling route previously took the last-registered def and
  # silently skipped the (BigInt)/(Number) selection the explicit-receiver
  # path performs.
  -> implicit_self_method(recv, name, argc = nil, has_block = false, args = nil)
    if recv == nil
      return nil
    if type(recv) == "Hash" && recv.has_key?(:rt)
      if recv[:rt] == :object
        return lookup_method(recv[:w_class], name, argc, has_block, args)
      # Inside a class method (`-> .parse`) self is the class sentinel, and a
      # bare call there names a sibling CLASS method — `parse_value_b(s, ...)`
      # in core/json.w is the canonical case. The compiled engine resolves it;
      # without this the interpreter raised "Undefined method 'parse_value_b'"
      # and JSON.parse was unusable interpreted.
      #
      # Only :class_methods are consulted, so the guard below still holds: a
      # class/module sentinel can never accidentally dispatch a Hash instance
      # method just because it is represented as an interpreter Hash.
      if recv[:rt] == :class
        return lookup_class_method(recv, name)
      return nil
    w_class = primitive_runtime_class(recv)
    if w_class == nil
      return nil
    lookup_method(w_class, name, argc, has_block, args)

  -> w_type_name(value)
    if value == nil
      return "Nil"
    t = type(value)
    if t == "Hash" && value.has_key?(:rt)
      if value[:rt] == :class
        return value[:name]
      if value[:rt] == :object
        return value[:w_class][:name]
    t

  # Resolve the .w source FILE that defines `class_name` (REPL introspection,
  # e.g. show-method String#split). Prefers the autoload registry — canonical for
  # core classes, and it works even when the interpreter can't parse the file
  # itself (it dispatches many stdlib methods via intrinsics and keeps only a
  # stub class). Falls back to a loaded method's recorded :file for user/`use`d
  # classes. Returns the path or nil.
  -> class_file(class_name)
    reg = autoload_registry()
    if reg.has_key?(class_name)
      return "core/" + reg[class_name] + ".w"
    c = @classes[class_name]
    if c == nil
      return nil
    ks = c[:methods].keys()
    i = 0
    while i < ks.size()
      mm = c[:methods][ks[i]]
      if mm[:file] != nil
        return mm[:file]
      i = i + 1
    nil

  # A method "takes a block" when any declared parameter is a `&` block
  # param — anonymous `(&)`, named `(&name)`, or the arity form `-> m/&`
  # (whose parser records `&` FIRST, so scan rather than peek at the tail).
  -> method_takes_block?(m)
    params = m[:params]
    if params == nil
      return false
    i = 0
    while i < params.size()
      if ast_get(params[i], :block_param) == true
        return true
      i += 1
    false

  # Choose among same-arity overloads the one whose declared parameter types
  # most specifically match the argument runtime types — the interpret-time
  # equivalent of the compiled synthesized `@1.is_a?("Type")` dispatcher.
  # Returns nil when no typed overload matches (normal dispatch then applies).
  -> select_typed_overload(overloads, argc, has_block, args)
    best = nil
    i = 0
    while i < overloads.size()
      m = overloads[i]
      pts = m[:param_types]
      if pts != nil
        takes_block = method_takes_block?(m)
        arity = m[:params].size()
        if takes_block
          arity -= 1
        if arity == argc && takes_block == has_block && overload_matches_args?(pts, args)
          if best == nil || param_types_more_specific?(pts, best[:param_types])
            best = m
      i += 1
    best

  # Every declared param type must be satisfied by the corresponding arg's
  # runtime type — is_a? over the class ancestry for most names, an exact
  # NaN-box tag compare for the few names the compiled gate also tests by
  # tag (see exact_tag_overload_hi16 below).
  -> overload_matches_args?(pts, args)
    j = 0
    while j < pts.size()
      if j >= args.size()
        return false
      tn = "" + pts[j].to_s()
      if machine_integer_overload_type?(tn)
        if !(type(args[j]) in ("Int" "BigInt"))
          return false
      elsif machine_float_overload_type?(tn)
        if type(args[j]) != "Float"
          return false
      else
        exact_hi16 = exact_tag_overload_hi16(tn)
        if exact_hi16 != nil
          if ((wvalue_bits(args[j]) >> 48) & 65535) != exact_hi16
            return false
        elsif !is_a_class?(args[j], tn)
          return false
      j += 1
    true

  # Raw scalar type information is erased once a value enters the tree
  # walker: every machine integer is represented by Integer/BigInt and every
  # machine float by Float. Preserve the category boundary used by compiled
  # typed-overload resolution so `(i64)` and `(f64)` arms remain distinct.
  -> machine_integer_overload_type?(tn)
    tn in ("i1" "i4" "i8" "i16" "i32" "i64" "i128" "u1" "u4" "u8" "u16" "u32" "u64" "u128")

  -> machine_float_overload_type?(tn)
    tn in ("f16" "bf16" "f32" "f64")

  # HAND-COPIED mirror of lowering's exact-tag overload rule — see
  # overload_exact_tag_test in lowering/types.w. No shared module exists
  # between the interpreter and lowering (this file cannot `use` lowering
  # workers), so the copy is deliberate; the engine-parity spec
  # (spec/compiler/overload_exact_tag_parity_spec.w) keeps the two in
  # step. Rule: a name in the generated tag table matches by EXACT
  # NaN-box tag, never by ancestry — unless some interpreted class
  # DESCENDS from it, because a subclass instance is an :object hash
  # carrying no primitive tag, and ancestry is what routes it to the arm
  # the program wrote for it. The walk is cheap and only runs for
  # table-name arms (explicit sends through typed-overload groups).
  -> exact_tag_overload_hi16(tn)
    expected = nil
    if tn == "BigInt"
      expected = 65531  # 0xFFFB
    if expected == nil
      return nil
    ks = @classes.keys()
    i = 0
    while i < ks.size()
      sup = @classes[ks[i]][:superclass]
      guard = 0
      while sup != nil && guard < 64
        if sup[:name] == tn
          return nil
        sup = sup[:superclass]
        guard += 1
      i += 1
    expected

  # `a` is at least as specific as `b` when each declared type is the same as,
  # or a subclass of, `b`'s — so `(Vector)` beats `(Number)` for a Vec3
  # argument while `(Number)` stays the base fallback.
  -> param_types_more_specific?(a, b)
    if b == nil
      return true
    j = 0
    while j < a.size()
      if j >= b.size()
        return true
      if !class_name_subtype?("" + a[j].to_s(), "" + b[j].to_s())
        return false
      j += 1
    true

  # Is the class named `a_name` the same as, or a descendant of, `b_name`?
  # Walks the class table's superclass chain. Number is the universal
  # numeric-tower base (load-order tolerant), mirroring lowering's
  # overload_type_is_ancestor? fallback.
  -> class_name_subtype?(a_name, b_name)
    if a_name == b_name
      return true
    c = @classes[a_name]
    guard = 0
    while c != nil && guard < 64
      if c[:name] == b_name
        return true
      c = c[:superclass]
      guard += 1
    if b_name == "Number"
      return true
    false

  -> lookup_method_exact_arity(w_class, name, argc, has_block = false, args = nil)
    if w_class == nil
      return nil
    overload_map = w_class[:method_overloads]
    if overload_map != nil && overload_map.has_key?(name)
      overloads = overload_map[name]
      # Typed operator-overload selection: with arg VALUES in hand, prefer the
      # same-arity overload whose declared parameter type most specifically
      # matches the argument's runtime type. Untyped methods fall through.
      if args != nil
        typed = select_typed_overload(overloads, argc, has_block, args)
        if typed != nil
          return typed
      # Block-aware pass first: prefer the overload whose declared block
      # parameter matches the call site's block presence, at the arity
      # net of that block param. This mirrors the compiled engine's
      # method_takes_block == caller_has_block specialization gate, so
      # `-> sort!` / `-> sort!(&)` pairs dispatch the same way on both
      # engines (previously the blocked call matched the blockless
      # definition and silently dropped its comparator).
      i = overloads.size() - 1
      while i >= 0
        m = overloads[i]
        takes_block = method_takes_block?(m)
        arity = m[:params].size()
        if takes_block
          arity -= 1
        if arity == argc && takes_block == has_block
          return m
        i -= 1
      # Legacy positional pass: a closure may also arrive positionally in
      # a `&` slot (lambda passed as an ordinary argument), so keep the
      # historical raw params-count match as the tie-breaker for every
      # call shape the pass above does not cover.
      i = overloads.size() - 1
      while i >= 0
        if overloads[i][:params].size() == argc
          return overloads[i]
        i -= 1
      # A trailing default makes the method callable at every smaller arity
      # down to its last required parameter. Resolve that compatible range in
      # the subclass before walking to an ancestor's exact-arity method.
      i = overloads.size() - 1
      while i >= 0
        m = overloads[i]
        takes_block = method_takes_block?(m)
        declared = m[:params].size()
        if takes_block
          declared -= 1
        minimum = declared
        pi = declared - 1
        while pi >= 0 && ast_get(m[:params][pi], :default) != nil
          minimum -= 1
          pi -= 1
        if takes_block == has_block && argc >= minimum && argc <= declared
          return m
        i -= 1
    lookup_method_exact_arity(w_class[:superclass], name, argc, has_block, args)

  -> lookup_method_fallback(w_class, name)
    if w_class == nil
      return nil
    if w_class[:methods].has_key?(name)
      overload_map = w_class[:method_overloads]
      if overload_map != nil && overload_map.has_key?(name) && overload_map[name].size() > 0
        return overload_map[name][0]
      return w_class[:methods][name]
    lookup_method_fallback(w_class[:superclass], name)

  # The compiled runtime searches the full class chain for exact name+arity
  # first, then performs a second name-only walk. The fallback selects the
  # first registration for overloaded names; no-arity introspection retains
  # the interpreter's established last-definition map.
  -> lookup_method(w_class, name, argc = nil, has_block = false, args = nil)
    if w_class == nil
      return nil
    if argc != nil
      exact = lookup_method_exact_arity(w_class, name, argc, has_block, args)
      if exact != nil
        return exact
      return lookup_method_fallback(w_class, name)
    if w_class[:methods].has_key?(name)
      return w_class[:methods][name]
    # Check superclass
    lookup_method(w_class[:superclass], name)

  -> lookup_class_method_exact_arity(w_class, name, argc, has_block = false, args = nil)
    if w_class == nil
      return nil
    overload_map = w_class[:class_method_overloads]
    if overload_map != nil && overload_map.has_key?(name)
      overloads = overload_map[name]
      if args != nil
        typed = select_typed_overload(overloads, argc, has_block, args)
        if typed != nil
          return typed
      i = overloads.size() - 1
      while i >= 0
        method = overloads[i]
        takes_block = method_takes_block?(method)
        declared = method[:params].size()
        if takes_block
          declared -= 1
        if declared == argc && takes_block == has_block
          return method
        i -= 1
      i = overloads.size() - 1
      while i >= 0
        method = overloads[i]
        takes_block = method_takes_block?(method)
        declared = method[:params].size()
        if takes_block
          declared -= 1
        minimum = declared
        pi = declared - 1
        while pi >= 0 && ast_get(method[:params][pi], :default) != nil
          minimum -= 1
          pi -= 1
        if takes_block == has_block && argc >= minimum && argc <= declared
          return method
        i -= 1
    lookup_class_method_exact_arity(w_class[:superclass], name, argc, has_block, args)

  -> lookup_class_method_fallback(w_class, name)
    if w_class == nil
      return nil
    class_methods = w_class[:class_methods]
    overload_map = w_class[:class_method_overloads]
    if class_methods != nil && class_methods.has_key?(name)
      if overload_map != nil && overload_map.has_key?(name) && overload_map[name].size() > 0
        return overload_map[name][0]
      return class_methods[name]
    lookup_class_method_fallback(w_class[:superclass], name)

  -> lookup_class_method(w_class, name, argc = nil, has_block = false, args = nil)
    if w_class == nil
      return nil
    if argc != nil
      exact = lookup_class_method_exact_arity(w_class, name, argc, has_block, args)
      if exact != nil
        return exact
      return lookup_class_method_fallback(w_class, name)
    class_methods = w_class[:class_methods]
    if class_methods != nil && class_methods.has_key?(name)
      return class_methods[name]
    lookup_class_method(w_class[:superclass], name)

  # Mirror of the compiled engine's keyword-argument entry remap
  # (w_kwargs_remap12 in runtime.c; prologue emitted by
  # lowering/definitions.w). A call-site kwargs group arrives as ONE
  # hash marked W_HASH_FLAG_KWARGS (eval_hash). When the callee declares
  # keyword params, rebind by NAME: positional args before the group keep
  # their slots, trailing non-nil post args (a positionally passed
  # closure) right-align, each keyword slot at/after the group takes
  # hash[name] when present (else nil so the default fires), and leftover
  # keys form a fresh unmarked residual hash placed at the first free
  # non-keyword slot. Callees without keyword params keep the group as an
  # ordinary trailing hash (`options = {}` collapse).
  -> kwargs_remap_args(params, args)
    if params == nil || args == nil || args.size() == 0
      return args
    has_kw = false
    i = 0
    while i < params.size()
      if ast_get(params[i], :keyword) == true
        has_kw = true
      i += 1
    if !has_kw
      return args
    n = params.size()
    k = -1
    i = 0
    while i < args.size() && i < n
      if args[i] != nil && ccall("w_hash_is_kwargs", args[i]) == true
        k = i
        break
      i += 1
    if k == -1
      return args
    kwh = args[k]
    kwkeys = kwh.keys()
    out = []
    i = 0
    while i < n
      if i < k
        out.push(args[i])
      else
        out.push(nil)
      i += 1
    post = []
    i = k + 1
    while i < args.size() && i < n
      if args[i] != nil
        post.push(args[i])
      i += 1
    i = 0
    while i < post.size()
      out[n - post.size() + i] = post[i]
      i += 1
    consumed = {}
    i = 0
    while i < n
      if i >= k && ast_get(params[i], :keyword) == true
        keyname = ast_get(params[i], :name)
        j = 0
        while j < kwkeys.size()
          if kwkeys[j].to_s() == keyname
            out[i] = kwh[kwkeys[j]]
            consumed[keyname] = true
            break
          j += 1
      i += 1
    residual = {}
    rcount = 0
    j = 0
    while j < kwkeys.size()
      if consumed[kwkeys[j].to_s()] == nil
        residual[kwkeys[j]] = kwh[kwkeys[j]]
        rcount += 1
      j += 1
    if rcount > 0
      j = k
      while j < n
        if out[j] == nil && ast_get(params[j], :keyword) != true && ast_get(params[j], :block_param) != true
          out[j] = residual
          break
        j += 1
    out

  # Collect the middle args for a `*rest` param at `splat_index` in a method
  # declaring `nparams` params. count = args.size - (nparams - 1), floored at
  # 0, so trailing fixed params keep their share and an exhausted splat is [].
  -> splat_collect(args, splat_index, nparams)
    count = args.size() - nparams + 1
    if count < 0
      count = 0
    out = []
    i = 0
    while i < count
      out.push(args[splat_index + i])
      i += 1
    out

  -> call_w_method(recv, method, args, block, env)
    # Barrier scope: a method/function body is lexically isolated from the
    # top-level (and caller) locals. Without the barrier, a callee that
    # assigns a name also bound at top level (e.g. a loop variable `n`)
    # walks up Environment.set's parent chain and CLOBBERS the caller's
    # `n` on return — an infinite loop when the caller loops on it. The
    # compiled-native and Ruby engines both isolate here; this restores
    # parity. Reads still resolve globals/constants (get ignores the
    # barrier); closures that capture method-locals keep write-through
    # because their block_env has no barrier and chains to this env.
    method_env = Environment.new(@env, true)
    # Own a __block__ slot per frame (nil when no block arrives) so
    # block? answers for THIS call — without the slot, the lookup
    # would walk past the barrier into a caller frame's binding. The
    # param-binding and block-binding paths below overwrite it.
    method_env.define("__block__", nil)
    @self_stack.push(recv)
    @method_stack.push(method)
    result = nil
    pending_error = nil
    begin
      # Bind parameters after establishing the callee context: default
      # expressions containing self/$value belong to the callee, not the
      # caller whose method happened to invoke it.
      params = ast_get(method, :params)
      args = kwargs_remap_args(params, args)
      # Locate a `*rest` splat param (at most one). When present, the arg
      # binder switches from positional-with-nil-pad to Ruby's splat model:
      # fixed params before the splat keep their slots, the splat slot
      # collects the middle args into a real array ([] when none remain
      # after satisfying trailing fixed params), and trailing fixed params
      # right-align against the end of args.
      splat_index = -1
      nparams = params.size()
      i = 0
      while i < nparams
        if ast_get(params[i], :splat) == true
          splat_index = i
          break
        i += 1
      # Arity contract, mirroring the compiled engine's compile-time check:
      # more args than params, or fewer than the leading plain params, is
      # an error — never silently dropped or nil-padded. A splat, keyword,
      # or block param makes the maximum open-ended. TUNGSTEN_ARITY=off
      # disables it (triage kill switch).
      if env("TUNGSTEN_ARITY") != "off"
        arity_required = 0
        arity_max = nparams
        arity_counting = true
        pi = 0
        while pi < nparams
          ap = params[pi]
          if ast_get(ap, :splat) == true || ast_get(ap, :keyword) == true || ast_get(ap, :block_param) == true
            arity_max = nil
            arity_counting = false
          elsif arity_counting && ast_get(ap, :default) == nil
            arity_required += 1
          else
            arity_counting = false
          pi += 1
        if args.size() < arity_required || (arity_max != nil && args.size() > arity_max)
          arity_expected = arity_required.to_s()
          if arity_max == nil
            arity_expected = "at least " + arity_required.to_s()
          elsif arity_max != arity_required
            arity_expected = arity_required.to_s() + ".." + arity_max.to_s()
          raise "'" + ast_get(method, :name).to_s() + "' takes " + arity_expected + " argument" + (arity_expected == "1" ? "" : "s") + ", got " + args.size().to_s() + " — arguments are never silently dropped or padded"
      i = 0
      while i < params.size()
        param = params[i]
        value = nil
        if splat_index == -1
          if i < args.size()
            value = args[i]
        elsif i < splat_index
          if i < args.size()
            value = args[i]
        elsif i == splat_index
          value = splat_collect(args, splat_index, nparams)
        else
          idx = args.size() - nparams + i
          if idx >= 0 && idx < args.size()
            value = args[idx]
        # nil is the missing-argument sentinel, exactly as in the compiled
        # engine (call sites pad with nil; the default guard selects on
        # nil). A nil-valued slot — absent, padded, or left empty by the
        # kwargs remap — takes the declared default.
        if value == nil && ast_get(param, :default) != nil
          value = evaluate(ast_get(param, :default), method_env)

        # `&blk` binds the attached trailing block (a lambda passed
        # positionally already arrived through args above). Mirrors the
        # compiled engine, where both spellings reach the block param.
        if value == nil && block != nil && ast_get(param, :block_param) == true
          value = block

        method_env.define(ast_get(param, :name), value)

        # A closure bound to a block param must also serve `yield` /
        # `&(...)` inside the body when it arrived positionally (no
        # attached block to bind below).
        if ast_get(param, :block_param) == true && block == nil && value != nil
          method_env.define("__block__", value)

        # Auto-assign ivar params
        if ast_get(param, :ivar_assign) && recv != nil && type(recv) == "Hash" && recv.has_key?(:rt) && recv[:rt] == :object
          recv[:ivars]["@" + ast_get(param, :name)] = value
        i += 1

      # Bind block
      if block != nil
        method_env.define("__block__", block)

      begin
        result = evaluate_body(ast_get(method, :body), method_env)
      rescue err
        if err == "__SIGNAL__" && @signal[:type] == :return
          result = @signal[:value]
          @signal[:type] = nil
        else
          # Defer the re-raise until the method's rescue frame has been fully
          # popped. Re-raising from inside this rescue could target the same
          # frame again, which made exceptions raised by interpreted methods
          # disappear as a nil return value.
          pending_error = err
    ensure
      @method_stack.pop()
      @self_stack.pop()
    if pending_error != nil
      raise pending_error
    result

  # Syntactic implicit-parameter candidates for a paramless block: every name
  # the body READS before assigning it, in first-appearance order. Purely a
  # function of the AST — no Environment is consulted, so the result is safe to
  # cache on the node (see call_block). Deciding which candidates are actually
  # free (rather than captures of the enclosing frame) happens per call.
  -> collect_free_vars(node, vars, seen)
    if node == nil
      return nil
    if type(node) == "Array"
      node.each -> (child)
        collect_free_vars(child, vars, seen)
      return nil
    if !is_ast_node?(node) || ast_kind(node) == nil
      return nil
    t = ast_kind(node)
    if t == :block
      return nil
    if t == :var
      name = ast_get(node, :name)
      if seen[name] == nil && name[0] != "@"
        seen[name] = true
        vars.push(name)
      return nil
    if t == :assign
      collect_free_vars(ast_get(node, :value), vars, seen)
      if ast_get(node, :target) != nil && ast_kind(ast_get(node, :target)) == :var
        seen[ast_get(ast_get(node, :target), :name)] = true
      return nil
    if t == :compound_assign
      collect_free_vars(ast_get(node, :value), vars, seen)
      collect_free_vars(ast_get(node, :target), vars, seen)
      return nil
    if t == :string_interp
      parts = ast_get(node, :parts)
      i = 0
      while i < parts.size()
        part = parts[i]
        if part[0] != :str
          collect_free_vars(part[1], vars, seen)
        i += 1
      return nil
    # Generic walk: recurse into all AST children. The Hash-era walk
    # skipped :node/:op/:name/:exclusive keys explicitly — those carry
    # primitives (kind sym, op sym, identifier name, range exclusive
    # flag), not children, and ast_children() already excludes them
    # by walking only Hash/Array slot values.
    ast_children(node).each -> (c)
      collect_free_vars(c, vars, seen)
    nil

  -> ast_contains_kind?(node, wanted)
    if node == nil
      return false
    if type(node) == "Array"
      i = 0
      while i < node.size()
        if ast_contains_kind?(node[i], wanted)
          return true
        i += 1
      return false
    if !is_ast_node?(node) || ast_kind(node) == nil
      return false
    if ast_kind(node) == wanted
      return true
    children = ast_children(node)
    i = 0
    while i < children.size()
      if ast_contains_kind?(children[i], wanted)
        return true
      i += 1
    false

  # A nested block may escape with this invocation Environment as its captured
  # parent. Reusing that Environment would make closures from earlier
  # iterations observe later bindings, so only closure-free bodies qualify.
  -> reusable_block_environment(block_data)
    if type(block_data) != "Array" || block_data.size() < 2
      return nil
    blk_node = block_data[1]
    reusable = ast_get(blk_node, :_environment_reusable)
    if reusable == nil
      reusable = !ast_contains_kind?(ast_get(blk_node, :body), :block)
      ast_set(blk_node, :_environment_reusable, reusable)
    if !reusable
      return nil
    Environment.new(block_data[0])

  -> block_can_break?(block_data)
    if type(block_data) != "Array" || block_data.size() < 2
      return true
    blk_node = block_data[1]
    can_break = ast_get(blk_node, :_can_break)
    if can_break == nil
      can_break = ast_contains_kind?(ast_get(blk_node, :body), :break)
      ast_set(blk_node, :_can_break, can_break)
    can_break

  # Exact fold for the common interactive hot loop `range -> counter++` (and
  # its `+= constant` / decrement mirrors). The block has no parameter and no
  # observable work besides updating an already-captured binding, so applying
  # delta * iteration_count is semantically identical to invoking it N times,
  # including Int-to-BigInt promotion. Return [environment, name, delta], or
  # nil for every body with another possible effect.
  -> range_block_linear_update(block_data)
    if type(block_data) != "Array" || block_data.size() < 2
      return nil
    blk_env = block_data[0]
    blk_node = block_data[1]
    params = ast_get(blk_node, :params)
    body = ast_get(blk_node, :body)
    if params == nil || params.size() != 0 || body == nil || body.size() != 1
      return nil
    stmt = body[0]
    if ast_kind(stmt) != :compound_assign
      return nil
    target = ast_get(stmt, :target)
    value = ast_get(stmt, :value)
    if ast_kind(target) != :var || ast_kind(value) != :int
      return nil
    name = ast_get(target, :name)
    if !blk_env.defined_locally_or_in_scope?(name)
      return nil
    delta = ast_get(value, :value)
    op = ast_get(stmt, :op)
    if op == :MINUS
      delta = 0 - delta
    elsif op != :PLUS
      return nil
    [blk_env, name, delta]

  -> call_block0(block_data)
    if type(block_data) == "Array"
      blk_env = block_data[0]
      blk_node = block_data[1]
      block_env = Environment.new(blk_env)
      params = ast_get(blk_node, :params)
      i = 0
      while i < params.size()
        block_env.define(params[i], nil)
        i += 1
      captured_self = current_self()
      if blk_env.defined?("__block_self__")
        captured_self = blk_env.get("__block_self__")
      @self_stack.push(captured_self)
      result = nil
      pending_error = nil
      begin
        result = evaluate_body(ast_get(blk_node, :body), block_env)
      rescue err
        if err == "__SIGNAL__" && @signal[:type] == :next
          @signal[:type] = nil
        else
          pending_error = err
      ensure
        @self_stack.pop()
      if pending_error != nil
        raise pending_error
      return result
    nil

  # Scalar one-argument block invocation. This preserves call_block's implicit
  # parameter and destructuring rules without allocating an `[arg]` Array.
  # Range passes a reusable Environment only after the escape check above.
  -> call_block1(block_data, arg, reuse_env = nil)
    if type(block_data) == "Array"
      blk_env = block_data[0]
      blk_node = block_data[1]
      block_env = reuse_env
      if block_env == nil
        block_env = Environment.new(blk_env)
      else
        block_env.clear_bindings()
      params = ast_get(blk_node, :params)
      if params.size() == 0
        if ast_get(blk_node, :_free_vars) == nil
          vars = []
          collect_free_vars(ast_get(blk_node, :body), vars, {})
          ast_set(blk_node, :_free_vars, vars)
        free_vars = ast_get(blk_node, :_free_vars)
        i = 0
        bound = false
        while i < free_vars.size() && !bound
          candidate = free_vars[i]
          if !blk_env.defined_locally_or_in_scope?(candidate)
            block_env.define(candidate, arg)
            bound = true
          i += 1
      elsif params.size() > 1 && type(arg) == "Array"
        i = 0
        while i < params.size()
          block_env.define(params[i], i < arg.size() ? arg[i] : nil)
          i += 1
      else
        i = 0
        while i < params.size()
          block_env.define(params[i], i == 0 ? arg : nil)
          i += 1
      captured_self = current_self()
      if blk_env.defined?("__block_self__")
        captured_self = blk_env.get("__block_self__")
      @self_stack.push(captured_self)
      result = nil
      pending_error = nil
      begin
        result = evaluate_body(ast_get(blk_node, :body), block_env)
      rescue err
        if err == "__SIGNAL__" && @signal[:type] == :next
          @signal[:type] = nil
        else
          pending_error = err
      ensure
        @self_stack.pop()
      if pending_error != nil
        raise pending_error
      return result
    nil

  -> call_block(block_data, args)
    if type(block_data) == "Array"
      blk_env = block_data[0]
      blk_node = block_data[1]
      block_env = Environment.new(blk_env)
      params = ast_get(blk_node, :params)
      if params.size() == 0 && args.size() > 0
        if ast_get(blk_node, :_free_vars) == nil
          vars = []
          collect_free_vars(ast_get(blk_node, :body), vars, {})
          ast_set(blk_node, :_free_vars, vars)
        # The cached list is syntactic; a candidate already bound in the
        # enclosing FRAME is a capture, not a parameter, so it is skipped and
        # consumes no argument. Frame-scoped on purpose: `defined?` reads past
        # the method barrier, which let a caller's `i` steal the implicit
        # index parameter of core/array.w's `-> each/&` (`$size -> &(self[i])`)
        # and hand every iteration the same element. Re-checked per call so
        # the cache can never freeze one caller's answer for all the others.
        free_vars = ast_get(blk_node, :_free_vars)
        i = 0
        argi = 0
        while i < free_vars.size() && argi < args.size()
          candidate = free_vars[i]
          if !blk_env.defined_locally_or_in_scope?(candidate)
            block_env.define(candidate, args[argi])
            argi += 1
          i += 1
      else
        # Ruby-style destructuring: a multi-param block receiving a single
        # Array element spreads it across the params (missing → nil).
        eff_args = args
        if params.size() > 1 && args.size() == 1 && type(args[0]) == "Array"
          eff_args = args[0]
        i = 0
        while i < params.size()
          if i < eff_args.size()
            block_env.define(params[i], eff_args[i])
          else
            block_env.define(params[i], nil)
          i += 1
      # Evaluate the body under the closure's captured self (see the :block
      # arm of evaluate). Interpreter-built [env, node] pairs carry no
      # capture; they keep the current self unchanged.
      captured_self = current_self()
      if blk_env.defined?("__block_self__")
        captured_self = blk_env.get("__block_self__")
      @self_stack.push(captured_self)
      result = nil
      pending_error = nil
      begin
        result = evaluate_body(ast_get(blk_node, :body), block_env)
      rescue err
        if err == "__SIGNAL__" && @signal[:type] == :next
          @signal[:type] = nil
        else
          pending_error = err
      ensure
        @self_stack.pop()
      if pending_error != nil
        raise pending_error
      return result
    nil
