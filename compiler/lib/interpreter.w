# Tree-walking interpreter for tungsten
use ast
use lexer
use parser
use environment
use builtins
use target

-> interpreter_process_argv
  values = argv()
  if values == nil
    return []
  values

+ Interpreter
  -> new(argv_values = nil)
    @env = Environment.new()
    @classes = {}
    @traits = {}
    @self_stack = [nil]
    @signal = {type: nil, value: nil}
    @loaded_files = []
    @current_file = nil
    @autoload_registry = nil
    if argv_values == nil
      argv_values = interpreter_process_argv()
    if argv_values == nil
      @argv = []
    else
      @argv = argv_values.copy(0, argv_values.size())
    # $name globals — a dedicated store, not part of the Environment
    # scope chain. A :var barrier deliberately blocks write-through
    # from inside a fn/method body (call_w_method's comment explains
    # why); :gvar reads/writes go through @globals instead, bypassing
    # the barrier question entirely by never touching Environment.
    @globals = {}
    # Goroutines spawned via `go ->`: the tree-walker has no scheduler, so
    # they are queued here and drained at end of the top-level program
    # (mirrors the compiled path's end-of-main drain). Single-threaded, so
    # they run to completion in spawn order — cooperative, not preemptive.
    @goroutines = []
    seed_primitive_class_stubs()

  -> argv
    @argv.copy(0, @argv.size())

  # Backstop for environments where autoload can't reach core/tungsten.w
  # (running from /tmp, no Bitfile in source ancestry, etc.). When the
  # autoload path IS reachable, eval_var triggers try_autoload_class for
  # PascalCase names and overlays the real WClass on top of these stubs.
  # See [[project_const_ref_node_kind]] for the parser-level fix that
  # would eliminate this backstop.
  -> seed_primitive_class_stubs
    names = ["Integer", "Float", "String", "Boolean", "Bool", "Nil", "Array", "Hash", "Symbol", "Range", "Regex", "Class"]
    i = 0
    while i < names.size()
      name = names[i]
      if !@classes.has_key?(name)
        @classes[name] = {rt: :class, name: name, methods: {}, class_methods: {}, parent: nil}
      i += 1

  # Directory that contains `core/` for stdlib autoload. Prefer cwd
  # (running inside the repo / a project holding core/), else fall back
  # to the install root the bin/tungsten wrapper exports as
  # TUNGSTEN_ROOT. Without the fallback, `tungsten /tmp/foo.w` from
  # outside the repo can't autoload any pure-Tungsten core class (JSON,
  # Matrix, …) in the quick-run interpreter. Mirrors loader.w's
  # find_core_root for the compiled path.
  -> core_dir
    if file?("core/tungsten.w")
      return "."
    root = env("TUNGSTEN_ROOT")
    if root != nil && root != "" && file?(root + "/core/tungsten.w")
      return root
    "."

  # Lazy-build the autoload registry by parsing core/tungsten.w's
  # `auto :Name, "path"` table. PascalCase names that aren't legal as
  # variables route through this registry the first time they're
  # referenced — exact same source of truth as loader.w's compile-time
  # autoload pass, just triggered on-demand at eval time.
  -> autoload_registry
    if @autoload_registry != nil
      return @autoload_registry
    registry = {}
    registry_path = core_dir() + "/core/tungsten.w"
    if !file?(registry_path)
      @autoload_registry = registry
      return registry
    source = read_file(registry_path)
    if source == nil
      @autoload_registry = registry
      return registry
    begin
      ast = parse_source(source)
      i = 0
      while i < ast.expressions.size()
        e = ast.expressions[i]
        if ast_kind(e) == :class_def && e.name == "Tungsten" && e.body != nil
          bj = 0
          while bj < e.body.size()
            n = e.body[bj]
            if ast_kind(n) == :call && n.name == "auto" && n.args != nil && n.args.size() == 2
              sym = n.args[0]
              path = n.args[1]
              if ast_kind(sym) == :symbol && ast_kind(path) == :string
                registry[sym.value] = path.value
            bj += 1
        i += 1
    rescue err
      nil
    @autoload_registry = registry
    registry

  # Load the core/*.w file for `name` if the registry knows about it.
  # Tolerant: if the file fails to parse (broken stubs like core/object.w
  # or core/string.w), install a bare stub class so further .class /
  # .class_name dispatch still works. Returns true if the name was
  # registered (real or stub), false if not in the registry at all.
  -> try_autoload_class(name)
    reg = autoload_registry()
    path = reg[name]
    if path == nil
      return false
    full_path = core_dir() + "/core/" + path + ".w"
    if !@loaded_files.include?(full_path)
      @loaded_files.push(full_path)
      source = read_file(full_path)
      if source != nil
        prev_file = @current_file
        @current_file = full_path
        begin
          inner = parse_source(source)
          execute_program(inner)
        rescue err
          nil
        @current_file = prev_file
    if !@classes.has_key?(name)
      @classes[name] = {rt: :class, name: name, methods: {}, parent: nil}
    true

  -> run(source, file_path = nil)
    if file_path != nil
      @current_file = file_path
    ast = parse_source(source)
    result = execute_program(ast)
    drain_goroutines()
    result

  # Run every queued goroutine body to completion, in spawn order. A goroutine
  # may spawn more, so loop until the queue stays empty (mirrors the compiled
  # scheduler draining the run queue before main returns).
  -> drain_goroutines
    while @goroutines.size() > 0
      pending = @goroutines
      @goroutines = []
      i = 0
      while i < pending.size()
        evaluate_body(pending[i][:body], pending[i][:env])
        i += 1

  # -- State snapshot (for nested evaluation) --

  -> save_state
    classes_copy = {}
    @classes.keys().each -> (k)
      classes_copy[k] = @classes[k]
    stack_copy = @self_stack.copy(0, @self_stack.size())
    files_copy = @loaded_files.copy(0, @loaded_files.size())
    {env: @env, classes: classes_copy, signal_type: @signal[:type], signal_value: @signal[:value], self_stack: stack_copy, loaded_files: files_copy, current_file: @current_file}

  -> restore_state(snapshot)
    @env = snapshot[:env]
    @classes = snapshot[:classes]
    @signal[:type] = snapshot[:signal_type]
    @signal[:value] = snapshot[:signal_value]
    @self_stack = snapshot[:self_stack]
    @loaded_files = snapshot[:loaded_files]
    @current_file = snapshot[:current_file]

  -> evaluate_isolated(source, file_path = nil)
    snapshot = save_state()
    @env = Environment.new(@env, true)
    begin
      run(source, file_path)
    ensure
      restore_state(snapshot)

  # -- Dynamic code loading (hot reload) --

  -> reload_module(path)
    source = read_file(path)
    prev_file = @current_file
    @current_file = path
    begin
      ast = parse_source(source)
      execute_program(ast)
    ensure
      @current_file = prev_file

  -> parse_source(source)
    file = @current_file
    if file == nil
      file = "(eval)"
    lexer = Lexer.new(source, file)
    token_count = lexer.tokenize()
    parser = Parser.new(token_count, lexer.packed_tokens, source, lexer.values, lexer.line_at, lexer.col_at, lexer.file).set_chars(lexer.chars)
    parser.parse()

  -> execute_program(program)
    result = nil
    i = 0
    while i < ast_get(program, :expressions).size()
      result = evaluate(ast_get(program, :expressions)[i], @env)
      i += 1
    result

  # True when an Int node's raw text is a plain decimal literal whose
  # magnitude exceeds 2^63 - 1 (so parse_int_value's native-i64 accumulator
  # wrapped). Hex/bin/oct and missing raw return false. Leading zeros ignored;
  # i64 max is 19 digits, so >19 always overflows and ==19 compares lexically.
  -> interp_decimal_exceeds_i64?(raw)
    if raw == nil
      return false
    if raw.starts_with?("0x") || raw.starts_with?("0X")
      return false
    if raw.starts_with?("0b") || raw.starts_with?("0B")
      return false
    if raw.starts_with?("0o") || raw.starts_with?("0O")
      return false
    s = "" + raw.replace("_", "")
    i = 0
    while i < s.size() - 1 && s.slice(i, 1) == "0"
      i += 1
    s = s.slice(i, s.size() - i)
    n = s.size()
    if n > 19
      return true
    if n < 19
      return false
    s > "9223372036854775807"

  # -- Main evaluation dispatch --

  -> evaluate(node, env)
    t = ast_kind(node)

    if t == :int
      # A decimal literal above the signed-i64 range wrapped at parse time
      # (parse_int_value's accumulator is compiled native i64), so rebuild it
      # as a BigInt from the original text — the runtime primitive the compiled
      # path uses for the same case (lowering/literals.w). Hex/bin/oct and all
      # in-range literals keep their cached value.
      raw = ast_get(node, :raw)
      if interp_decimal_exceeds_i64?(raw)
        return ccall("w_bigint_from_dec_str", "" + raw.replace("_", ""))
      return ast_get(node, :value)
    if t == :char
      return ast_get(node, :value)
    if t == :codepoint
      return ast_get(node, :value)
    if t == :wvalue
      return ast_get(node, :value)
    if t == :float
      # The parser stores the literal's text in :value; coerce to an f64 so
      # arithmetic doesn't hit "expected int, got string" (mirrors :decimal
      # below). Without this, `~2.0 * ~3.0` multiplies the raw strings.
      return ast_get(node, :value).to_s().to_f()
    if t == :decimal
      # Exact decimal semantics, same as the compiled path: parse the literal
      # text into a sig/scale decimal WValue (0.1 + 0.2 == 0.3 must hold here
      # too). The shim materializes via the runtime's own constructor.
      return ccall("w_decimal_parse", "" + ast_get(node, :value).to_s())
    if t == :currency
      return ccall("w_currency_parse", "" + ast_get(node, :amount).to_s(), ast_get(node, :prefix), ast_get(node, :suffix))
    if t == :quantity
      return ccall("w_quantity_parse", "" + ast_get(node, :number_str).to_s(), "" + ast_get(node, :unit).to_s())
    # Rich literal types the compiled path lowers via const_* ops; the
    # interpreter constructs them through w_*_parse shims so dates/colors/etc.
    # evaluate (and live-scrub) in the REPL. Same constructors as the -o path.
    if t == :date
      return ccall("w_date_parse", "" + ast_get(node, :value).to_s())
    if t == :datetime
      return ccall("w_date_parse", "" + ast_get(node, :value).to_s())
    if t == :time
      return ccall("w_time_parse", "" + ast_get(node, :value).to_s())
    if t == :month
      return ccall("w_date_parse", "" + ast_get(node, :value).to_s())
    if t == :rational
      return ccall("w_rational_parse", "" + ast_get(node, :value).to_s())
    if t == :color
      return ccall("w_color_packed", ast_get(node, :rgba))
    if t == :ip4
      # "a.b.c.d" or "a.b.c.d:port" → w_ipv4(a,b,c,d,-1) (mirror lower_ipv4)
      raw = "" + ast_get(node, :value).to_s()
      colon = raw.index(":")
      if colon != nil
        raw = raw.slice(0, colon)
      parts = raw.split(".")
      return ccall("w_ipv4", parts[0].to_i(), parts[1].to_i(), parts[2].to_i(), parts[3].to_i(), -1)
    if t == :cidr4
      # "a.b.c.d/prefix" → w_ipv4(a,b,c,d,prefix) (mirror lower_cidr4)
      raw = "" + ast_get(node, :value).to_s()
      slash = raw.index("/")
      ip_part = raw.slice(0, slash)
      prefix = raw.slice(slash + 1, raw.size() - slash - 1).to_i()
      parts = ip_part.split(".")
      return ccall("w_ipv4", parts[0].to_i(), parts[1].to_i(), parts[2].to_i(), parts[3].to_i(), prefix)
    if t == :ip6
      # "::1" / "2001:db8::1" → w_ipv6_parse (parses the string into 16 bytes)
      return ccall("w_ipv6_parse", "" + ast_get(node, :value).to_s())
    if t == :cidr6
      # "2001:db8::/32" → w_ipv6_parse (splits the "/prefix" internally)
      return ccall("w_ipv6_parse", "" + ast_get(node, :value).to_s())
    if t == :string
      return ast_get(node, :value)
    if t == :bool
      return ast_get(node, :value)
    if t == :nil_lit
      return nil
    if t == :symbol
      return ast_get(node, :value).to_sym()
    if t == :self_ref
      return current_self()
    if t == :array
      return ast_get(node, :elements).map -> (e)
        evaluate(e, env)
    if t in (:typed_array :typed_array_new)
      return eval_typed_array_new(node, env)
    if t == :hash_literal
      return eval_hash(node, env)
    if t == :string_interp
      return eval_string_interp(node, env)
    if t == :byte_array
      return ast_get(node, :values)
    if t == :byte_array_interp
      result = []
      i = 0
      while i < ast_get(node, :parts).size()
        val = evaluate(ast_get(node, :parts)[i], env)
        if val.is_a?(Array)
          result = result + val
        else
          result.push(val)
        i += 1
      return result
    if t == :var
      return eval_var(node, env)
    if t == :gvar
      return eval_gvar(node)
    if t == :view_field_var
      return eval_view_field_var(node, env)
    if t == :ivar
      return eval_ivar(node)
    if t == :assign
      return eval_assign(node, env)
    if t == :multi_assign
      return eval_multi_assign(node, env)
    if t == :compound_assign
      return eval_compound_assign(node, env)
    if t == :binary_op
      return eval_binary_op(node, env)
    if t == :unary_op
      return eval_unary_op(node, env)
    if t == :not
      return !truthy?(evaluate(ast_get(node, :operand), env))
    if t == :and
      return eval_and(node, env)
    if t == :or
      return eval_or(node, env)
    if t == :if
      return eval_if(node, env)
    if t == :while
      return eval_while(node, env)
    if t == :case
      return eval_case(node, env)
    if t == :case_value
      return eval_case_value(node, env)
    if t == :range
      # Right-unbounded ranges (`1..`, `1...`) carry ast_get(node, :to) == nil.
      # Preserve the nil on the evaluated range so iteration logic can
      # detect it and run without an upper bound.
      to_val = nil
      if ast_get(node, :to) != nil
        to_val = evaluate(ast_get(node, :to), env)
      return {rt: :range, from: evaluate(ast_get(node, :from), env), to: to_val, exclusive: ast_get(node, :exclusive)}
    if t == :call
      return eval_call(node, env)
    if t == :method_def
      return eval_method_def(node, env)
    if t == :class_def
      return eval_class_def(node, env)
    if t == :trait_def
      return eval_trait_def(node, env)
    if t == :block
      return [env, node]
    if t == :puts
      return eval_puts(node, env)
    if t == :print
      return eval_print(node, env)
    if t == :return
      return signal_return(evaluate_or_nil(ast_get(node, :value), env))
    if t == :break
      return signal_break()
    if t == :next
      return signal_next()
    if t == :recase
      val_node = ast_get(node, :value)
      if val_node != nil
        return signal_recase(evaluate(val_node, env), true)
      return signal_recase(nil, false)
    if t == :raise
      raise w_to_s(evaluate(ast_get(node, :value), env))
    if t == :super
      return eval_super(node, env)
    if t == :use
      return eval_use(node)
    if t == :begin
      return eval_begin(node, env)
    if t == :yield
      return eval_yield(node, env)
    if t == :on_guard
      return eval_on_guard(node, env)
    if t == :program
      return execute_program(node)
    if t == :magic_constant
      return eval_magic_constant(node)
    if t == :parg
      # `@N` positional ref — binds to the __argN param the `/N`-arity
      # method synthesizer creates (mirrors lowering/pass_registry.w).
      return eval_var(Tungsten:AST:Var.new("__arg" + node.index.to_s()), env)
    if t == :map
      return eval_pipeline_map(node, env)
    if t == :calc
      return eval_pipeline_calc(node, env)
    if t == :class_ref
      return eval_class_ref(node, env)
    # Purely declarative kinds: `- ivars` slab layout (the interpreter has no
    # slab to populate) and the `in Foo` namespace prefix (already consumed at
    # parse time). The compiled path treats these as no-ops in pass_registry;
    # mirror that here so `run`/`-e`/`--repl` don't crash on the new syntax.
    if t == :ivars_decl
      return nil
    if t == :namespace_decl
      return nil
    # The slab-declaration family. `- data` struct blocks (:view_decl) are
    # consumed in eval_class_def, where each field becomes an ivar accessor;
    # the rest are structural sub-nodes or backend-only declarations. The
    # compiled pipeline either records them for the metal emitter or no-ops
    # them in pass_registry — the tree-walker has no slab, no metal backend,
    # and no extern linkage, so a no-op is the faithful mirror. A program that
    # actually *calls* a @gpu kernel or an extern fails later with a clear
    # "undefined method", not a generic Unknown-AST crash at definition time.
    # :trait_include (`is Enumerable` in a class body) is expanded inline by
    # eval_class_def (see expand_trait_includes below), which splices the
    # named trait's own methods into the class body before it's walked. A
    # :trait_include reached here is either outside a class body or names an
    # unknown trait — a no-op is the faithful mirror of the compiled path's
    # E_LOWER_UNKNOWN_TRAIT-or-ignore behavior without erroring at load time.
    if t in (:field_decl :layout_def :view_decl :view_field :view_base :view_value :view_access :extern_fn :extern_lib :gpu_kernel_def :schedule_def :trait_include)
      return nil

    # @fastmath / @strictmath scoped blocks. The tree-walker does direct
    # floating-point arithmetic with no FMA contraction or fast-math license,
    # so the math mode is a no-op here: the block is just a transparent scoped
    # body. Evaluate its statements and return the last value (mirrors the
    # compiled lower_mathmode_block, which reads node[:body] by subscript —
    # these are plain hash nodes, not slab nodes).
    # `Math.promote / trap / wrap` overflow-mode blocks are a transparent scoped
    # body in the tree-walker: the interpreter does arbitrary-precision integer
    # arithmetic, so :promote is implicit and :wrap/:trap are not yet enforced
    # here (a known interp-vs-compiled divergence — the compiled lowering
    # applies the mode). See [[project_math_wrap_fix]].
    if t in (:fastmath_block :strictmath_block :overflow_block)
      return evaluate_body(ast_get(node, :body), env)

    # `go -> …` spawns a goroutine. The tree-walker has no preemptive
    # scheduler, so queue the body (with its captured env) and drain it at
    # end of program in drain_goroutines — matching the compiled end-of-main
    # drain, so `-e` and `-o` produce the same output order.
    if t == :go
      @goroutines.push({body: ast_get(node, :body), env: env})
      return nil

    raise "Unknown AST node type: [t]"

  # PascalCase class reference. Parser emits :class_ref for T_NAME
  # tokens, so this is reached without ever entering eval_var. Tries
  # autoload first so referencing `Integer` pulls in core/integer.w,
  # then resolves from @classes.
  -> eval_class_ref(node, env)
    name = ast_get(node, :name)
    if !@classes.has_key?(name)
      try_autoload_class(name)
    if @classes.has_key?(name)
      return @classes[name]
    hint = foreign_name_hint(name)
    if hint != nil
      raise "Undefined class '[name]' — [hint]"
    raise "Undefined class '[name]'"

  -> eval_magic_constant(node)
    name = ast_get(node, :name)
    if name == "FILE"
      if @current_file == nil
        return "(eval)"
      return @current_file
    if name == "LINE"
      return node.line
    if name == "DIR"
      if @current_file == nil
        return capture("pwd").strip()
      parts = @current_file.split("/")
      parts.pop()
      dir = parts.join("/")
      if dir == ""
        return "."
      return dir
    raise "Unknown magic constant: [name]"

  # Lazy singleton for the "Class" class — what `.class` returns for any
  # class receiver. Cached in @classes so repeated calls return the same
  # identity and `Class.class.class.class` is a fixpoint.
  -> class_class_singleton
    if @classes.has_key?("Class")
      return @classes["Class"]
    cls = {rt: :class, name: "Class", methods: {}, class_methods: {}, parent: nil}
    @classes["Class"] = cls
    cls

  # Pipeline (:map / :calc) evaluation. Counterpart to the fused lowering
  # in compiler/lib/lowering/calls.w — runs the slow tree-walking path so
  # `bin/tungsten -e "<< [1,2,3]/sq:sum"` works under the interpreter.
  # Stages aren't fused (one materialized array per stage); the inline
  # heuristics for common elementwise ops + predicates mirror lowering's
  # pipeline_transform_node / pipeline_pred_node, so it works even when
  # the corresponding trait method isn't loaded in this process.
  -> eval_pipeline_map(node, env)
    source = ast_get(node, :source)
    func = ast_get(node, :func)
    kind = ast_get(node, :kind)
    src_val = evaluate(source, env)
    arr = to_pipeline_array(src_val)
    # A Block func (e.g. the lambda `Σ(2x⁷ + 3x²)` desugars to) is invoked per
    # element via call_block; only named funcs use the op-name table. (A Block
    # has :params/:body, not :args — reading :args here yielded nil and crashed
    # the named fallback's arg_nodes.map.)
    func_is_block = ast_kind(func) == :block
    func_name = nil
    func_args_nodes = nil
    if !func_is_block
      func_name = ast_get(func, :name)
      func_args_nodes = ast_get(func, :args)
    out = []
    i = 0
    while i < arr.size()
      elem = arr[i]
      if func_is_block
        result = call_block([env, func], [elem])
      else
        result = apply_pipeline_func(elem, func_name, func_args_nodes, env)
      if kind == :map
        out.push(result)
      elsif kind == :select
        if truthy?(result)
          out.push(elem)
      elsif kind == :reject
        if !truthy?(result)
          out.push(elem)
      i += 1
    out

  -> eval_pipeline_calc(node, env)
    op = ast_get(node, :op)
    # Range/predicate:count closed forms — computed WITHOUT materializing the
    # range (a `(2..1e10)/prime?:count` would otherwise build a 10-billion-element
    # array and crash). prime? → the segmented wheel sieve (w_prime_count_u64);
    # even?/odd? → O(1) arithmetic. Mirrors the compiled pipeline lowering.
    if op == "count"
      csrc = ast_get(node, :source)
      if is_ast_node?(csrc) && ast_kind(csrc) == :map
        cinner = ast_get(csrc, :source)
        cfunc = ast_get(csrc, :func)
        if is_ast_node?(cfunc) && !(ast_kind(cfunc) == :block) && is_ast_node?(cinner)
          cpred = ast_get(cfunc, :name)
          if cpred == "prime?" || cpred == "prime_12k?" || cpred == "even?" || cpred == "odd?"
            # (0..N / 12) / prime_12k? : count — read N from the range AST before
            # evaluation (the :to bound becomes N/12 once materialized).
            if cpred == "prime_12k?" && is_ast_node?(cinner) && ast_kind(cinner) == :range
              from_ast = ast_get(cinner, :from)
              to_ast = ast_get(cinner, :to)
              if is_ast_node?(from_ast) && ast_kind(from_ast) == :int && ast_get(from_ast, :value) == 0
                if is_ast_node?(to_ast) && ast_kind(to_ast) == :binary_op && ast_get(to_ast, :op) == :SLASH
                  right_ast = ast_get(to_ast, :right)
                  if is_ast_node?(right_ast) && ast_kind(right_ast) == :int && ast_get(right_ast, :value) == 12
                    n_hi = evaluate(ast_get(to_ast, :left), env)
                    return ccall("w_prime_count_u64_w", 2, n_hi)
            crv = evaluate(cinner, env)
            if type(crv) == "Hash" && crv[:rt] == :range
              # Coerce to genuine Int WValues before any arithmetic/comparison
              # below — a bound can be a whole-valued Decimal (`1e10`), which
              # none of `<`/`-`/`%` handle (mirrors the compiled lowering's
              # w_range_bound_i64, raising a catchable TypeError instead of
              # the fatal as_int abort a raw Decimal would hit).
              clo = ccall("w_range_bound_i64_w", crv[:from])
              chi = ccall("w_range_bound_i64_w", crv[:to])
              if crv[:exclusive]
                chi = chi - 1
              # even?/odd? are pure arithmetic — no ccall, so bounds of ANY
              # size (incl. boxed bigints, which ccall marshaling corrupts)
              # stay exact. Sign-safe: only the parity of lo matters, and the
              # divisions are on the (non-negative) total.
              if cpred == "even?" || cpred == "odd?"
                if chi < clo
                  return 0
                total = chi - clo + 1
                evens = total / 2
                if clo % 2 == 0
                  evens = (total + 1) / 2
                if cpred == "even?"
                  return evens
                return total - evens
              # prime?: the sieve ccall is only safe for inline-int bounds
              # (< 2^48 — ccall nanunboxes args, corrupting boxed bigints);
              # larger bounds fall through to the loop.
              if cpred == "prime?" && chi < 281474976710656 && clo > 0 - 281474976710656
                return ccall("w_prime_count_u64_w", clo, chi)
    # (1..n)/Σ(poly) closed form: a sum over a range-sourced Block map whose
    # body is an integer polynomial skips materialization entirely — exact
    # Faulhaber via w_range_pow_sum, same as the compiled lowering.
    if op == "sum"
      msrc = ast_get(node, :source)
      if is_ast_node?(msrc) && ast_kind(msrc) == :map
        inner = ast_get(msrc, :source)
        mfunc = ast_get(msrc, :func)
        if is_ast_node?(mfunc) && ast_kind(mfunc) == :block && is_ast_node?(inner)
          cf_terms = sigma_poly_extract([env, mfunc])
          if cf_terms != nil
            rv = evaluate(inner, env)
            if type(rv) == "Hash" && rv[:rt] == :range
              cf_hi = rv[:to]
              if rv[:exclusive]
                cf_hi = cf_hi - 1
              return sigma_terms_sum(cf_terms, rv[:from], cf_hi)
            # Non-range source with a poly block: fall through to the loop
            # path (src_val recomputed below is fine — ranges were the only
            # side-effect concern and this arm didn't consume rv).
            src_val0 = rv
            arr0 = to_pipeline_array(src_val0)
            acc0 = 0
            i0 = 0
            while i0 < arr0.size()
              acc0 = acc0 + call_block([env, mfunc], [arr0[i0]])
              i0 += 1
            return acc0
    src_val = evaluate(ast_get(node, :source), env)
    arr = to_pipeline_array(src_val)
    if op == "sum"
      acc = 0
      i = 0
      while i < arr.size()
        acc = acc + arr[i]
        i += 1
      return acc
    if op == "product"
      acc = 1
      i = 0
      while i < arr.size()
        acc = acc * arr[i]
        i += 1
      return acc
    if op == "min"
      if arr.size() == 0
        return nil
      acc = arr[0]
      i = 1
      while i < arr.size()
        if arr[i] < acc
          acc = arr[i]
        i += 1
      return acc
    if op == "max"
      if arr.size() == 0
        return nil
      acc = arr[0]
      i = 1
      while i < arr.size()
        if arr[i] > acc
          acc = arr[i]
        i += 1
      return acc
    if op == "detect"
      if arr.size() > 0
        return arr[0]
      return nil
    if op == "count"
      # Count truthy elements. After a predicate map (`/prime?:count`) the
      # sequence is booleans, so this is the number of matches — consistent
      # with Enumerable#count(:predicate).
      acc = 0
      i = 0
      while i < arr.size()
        if truthy?(arr[i])
          acc = acc + 1
        i += 1
      return acc
    raise "Unknown pipeline calc op: [op]"

  # Inline common elementwise ops + predicates so primitives work even
  # when the matching trait method isn't loaded. Fall back to a regular
  # method dispatch for anything else (lets user-defined methods through).
  # Resolve a map/filter iteratee for an element: use the block if one was
  # given, otherwise treat the first argument as a method name to send to the
  # element (symbol-to-proc), so `arr.select(:prime?)` / `arr.count(:prime?)`
  # behave like `-> (x) x.prime?`. A symbol or string arg both work via to_s.
  -> apply_iteratee(block, args, elem)
    if block != nil
      return call_block(block, [elem])
    if args != nil && args.size() >= 1
      return dispatch_method(elem, "" + args[0].to_s(), [], nil, @env)
    raise "expected a block or a method symbol"

  # ── Closed-form Σ (interpreter side) ────────────────────────────
  # If `f` is a Block whose body is an integer polynomial in its single
  # parameter — sums/differences of `c`, `x`, `x**k`, `c * x**k` (exactly the
  # shape the parser's Σ rewrite emits for `Σ(2x⁷ + 3x²)`) — return the exact
  # sum over lo..hi via w_range_pow_sum (Faulhaber; the runtime primitive the
  # compiled closed-form lowering calls). Returns nil when the body isn't a
  # recognizable polynomial; the caller falls back to the O(n) loop.
  -> sigma_closed_form(f, lo, hi)
    terms = sigma_poly_extract(f)
    if terms == nil
      return nil
    sigma_terms_sum(terms, lo, hi)

  # Pure-AST half: [coefficient, power] terms of the Block's polynomial body,
  # or nil. Safe to call before evaluating the range (no side effects).
  -> sigma_poly_extract(f)
    if type(f) != "Array" || f.size() != 2
      return nil
    blk = f[1]
    if ast_kind(blk) != :block
      return nil
    params = ast_get(blk, :params)
    if params == nil || params.size() != 1
      return nil
    body = ast_get(blk, :body)
    if body == nil || body.size() != 1
      return nil
    terms = []
    if !sigma_poly_terms(body[0], params[0], 1, terms)
      return nil
    terms

  -> sigma_terms_sum(terms, lo, hi)
    acc = 0
    i = 0
    while i < terms.size()
      acc = acc + terms[i][0] * ccall("w_range_pow_sum_w", lo, hi, terms[i][1], 0)
      i += 1
    acc

  # Collect [coefficient, power] terms of an integer polynomial AST in `vn`.
  # Handles +, -, unary -, int literals, `vn`, `vn ** int`, `int * <power>`,
  # `<power> * int`. Anything else → false (not closed-formable).
  -> sigma_poly_terms(node, vn, sign, terms)
    if !is_ast_node?(node)
      return false
    k = ast_kind(node)
    if k == :int
      terms.push([sign * ast_get(node, :value), 0])
      return true
    if k == :var
      if "" + ast_get(node, :name) != "" + vn
        return false
      terms.push([sign, 1])
      return true
    if k == :unary_op
      if ast_get(node, :op) == :MINUS
        return sigma_poly_terms(ast_get(node, :operand), vn, 0 - sign, terms)
      return false
    if k != :binary_op
      return false
    op = ast_get(node, :op)
    left = ast_get(node, :left)
    right = ast_get(node, :right)
    if op == :PLUS
      return sigma_poly_terms(left, vn, sign, terms) && sigma_poly_terms(right, vn, sign, terms)
    if op == :MINUS
      return sigma_poly_terms(left, vn, sign, terms) && sigma_poly_terms(right, vn, 0 - sign, terms)
    if op == :POW
      p = sigma_pow_of(node, vn)
      if p < 0
        return false
      terms.push([sign, p])
      return true
    if op == :STAR
      c = nil
      powed = nil
      if ast_kind(left) == :int
        c = ast_get(left, :value)
        powed = right
      elsif ast_kind(right) == :int
        c = ast_get(right, :value)
        powed = left
      else
        return false
      p = sigma_pow_of(powed, vn)
      if p < 0
        return false
      terms.push([sign * c, p])
      return true
    false

  # The power of a `vn`-based factor: `vn` → 1, `vn ** int` → the int; -1 if
  # the node is neither.
  -> sigma_pow_of(node, vn)
    if !is_ast_node?(node)
      return 0 - 1
    k = ast_kind(node)
    if k == :var
      if "" + ast_get(node, :name) == "" + vn
        return 1
      return 0 - 1
    if k == :binary_op && ast_get(node, :op) == :POW
      b = ast_get(node, :left)
      e = ast_get(node, :right)
      if ast_kind(b) == :var && "" + ast_get(b, :name) == "" + vn && ast_kind(e) == :int
        return ast_get(e, :value)
    0 - 1

  -> apply_pipeline_func(elem, name, arg_nodes, env)
    if name == "sq"
      return elem * elem
    if name == "cube"
      return elem * elem * elem
    if name == "negate"
      return 0 - elem
    if name == "abs"
      if elem < 0
        return 0 - elem
      return elem
    if name == "even?"
      return (elem % 2) == 0
    if name == "odd?"
      return (elem % 2) != 0
    if name == "zero?"
      return elem == 0
    if name == "positive?"
      return elem > 0
    if name == "negative?"
      return elem < 0
    if name == "itself"
      return elem
    arg_vals = arg_nodes.map -> (a)
      evaluate(a, env)
    dispatch_method(elem, name, arg_vals, nil, env)

  # Coerce a source value into an array for tree-walking iteration.
  # Arrays pass through; ranges (interpreter's Hash representation) expand
  # to an integer list.
  -> to_pipeline_array(val)
    if type(val) == "Array"
      return val
    if type(val) == "Hash" && val[:rt] == :range
      out = []
      x = val[:from]
      hi = val[:to]
      if val[:exclusive]
        while x < hi
          out.push(x)
          x += 1
      else
        while x <= hi
          out.push(x)
          x += 1
      return out
    val

  -> evaluate_or_nil(node, env)
    if node == nil
      return nil
    evaluate(node, env)

  -> evaluate_body(exprs, env)
    result = nil
    i = 0
    while i < exprs.size()
      result = evaluate(exprs[i], env)
      i += 1
    result

  # -- Helpers --

  -> truthy?(value)
    value != nil && value != false

  -> w_to_s(value)
    if value == nil
      return "nil"
    if value == true
      return "true"
    if value == false
      return "false"
    t = type(value)
    if t == "Integer"
      return value.to_s()
    if t == "String"
      return value
    if t == "Symbol"
      return value.to_s()
    if t == "Array"
      items = value.map -> (v)
        w_inspect(v)
      return "\[" + items.join(", ") + "]"
    if t == "Hash" && value.has_key?(:rt) && value[:rt] == :range
      op = value[:exclusive] ? "..." : ".."
      return w_to_s(value[:from]) + op + w_to_s(value[:to])
    if t == "Hash"
      if value.has_key?(:rt)
        rt = value[:rt]
        if rt == :class
          return value[:name]
        if rt == :object
          obj_class = value[:w_class]
          # Try to call to_s
          m = lookup_method(obj_class, "to_s")
          if m != nil
            return call_w_method(value, m, [], nil, @env)
          return obj_class[:name] + " instance"
      entries = value.keys().map -> (k)
        w_inspect(k) + ": " + w_inspect(value[k])
      return "{" + entries.join(", ") + "}"
    value.to_s()

  -> w_inspect(value)
    if value == nil
      return "nil"
    if value == true
      return "true"
    if value == false
      return "false"
    if type(value) == "String"
      return "\"" + value + "\""
    if type(value) == "Symbol"
      return value.to_s()
    w_to_s(value)

  # -- Control flow signals --

  -> signal_return(value)
    @signal[:type] = :return
    @signal[:value] = value
    raise "__SIGNAL__"

  -> signal_break
    @signal[:type] = :break
    raise "__SIGNAL__"

  -> signal_next
    @signal[:type] = :next
    raise "__SIGNAL__"

  # `recase [expr]` — re-dispatch the innermost enclosing case. has_value
  # distinguishes `recase expr` (use value) from bare `recase` (re-eval subject).
  -> signal_recase(value, has_value)
    @signal[:type] = :recase
    @signal[:value] = value
    @signal[:has_value] = has_value
    raise "__SIGNAL__"

  # -- Variable evaluation --

  -> eval_var(node, env)
    name = ast_get(node, :name)
    if name == "ARGV"
      return argv()
    # Bare `class` in a method body resolves to the current class — the runtime
    # class of the receiver for instance methods, or self for class methods — so
    # `class.new(...)` / `class.zero` factory methods work, matching the compiled
    # path (which treats `class` as the enclosing/receiver class, not a variable).
    if name == "class"
      cs = current_self()
      if cs != nil && type(cs) == "Hash"
        if cs.has_key?(:w_class)
          return cs[:w_class]
        if cs.has_key?(:rt) && cs[:rt] == :class
          return cs
    if env.defined?(name)
      return env.get(name)
    if !@classes.has_key?(name)
      try_autoload_class(name)
    if @classes.has_key?(name)
      return @classes[name]
    if @env.defined?(name)
      return @env.get(name)
    # Try as bare method call
    if callable?(name)
      return dispatch_bare_call(name, [], nil, env)
    # Δ-prefixed identifier: an UNDEFINED `Δx` means "my x minus theirs" —
    # desugars to `x - x'` = `x - @1.x` (prime-notation delta). Mirrors
    # lowering.w's lower_var fallback; a real Δx variable resolves above.
    if name.starts_with?("Δ") && name.size() > "Δ".size()
      dlen = "Δ".size()
      delta_base = name.slice(dlen, name.size() - dlen)
      delta_node = Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(delta_base), :MINUS, Tungsten:AST:Call.new(Tungsten:AST:Parg.new(1), delta_base, [], nil))
      return evaluate(delta_node, env)
    hint = foreign_name_hint(name)
    if hint != nil
      raise "Undefined variable or method '[name]' — [hint]"
    raise "Undefined variable or method '[name]'"

  # The libm set the compiled path treats as intrinsics. Returns nil when the
  # name isn't one (all real results are Floats, so nil is a safe sentinel).
  -> eval_math_intrinsic(name, args)
    if args.size() == 1
      x = args[0]
      case name
      when "sqrt"
        return ccall("w_math_sqrt", x)
      when "sin"
        return ccall("w_math_sin", x)
      when "cos"
        return ccall("w_math_cos", x)
      when "tan"
        return ccall("w_math_tan", x)
      when "exp"
        return ccall("w_math_exp", x)
      when "log"
        return ccall("w_math_log", x)
      when "floor"
        return ccall("w_math_floor", x)
      when "ceil"
        return ccall("w_math_ceil", x)
      when "round"
        return ccall("w_math_round", x)
      when "abs"
        return ccall("w_math_abs", x)
    if args.size() == 2
      case name
      when "pow"
        return ccall("w_math_pow", args[0], args[1])
      when "atan2"
        return ccall("w_math_atan2", args[0], args[1])
      when "ldexp"
        return ccall("w_math_ldexp", args[0], args[1])
    nil

  -> dispatch_interpreted_ccall(args)
    if args.size() == 0
      raise "ccall requires a runtime function name"
    cname = "" + args[0]
    case cname
    when "w_to_s"
      return ccall("w_to_s", args[1])

    when "w_ipv4_parse"
      return ccall("w_ipv4_parse", args[1])
    when "w_ipv4_from_octets"
      return ccall("w_ipv4_from_octets", args[1], args[2], args[3], args[4], args[5])
    when "w_ipv4_to_i"
      return ccall("w_ipv4_to_i", args[1])
    when "w_ipv4_prefix"
      return ccall("w_ipv4_prefix", args[1])
    when "w_ipv4_cidr_p"
      return ccall("w_ipv4_cidr_p", args[1])
    when "w_ipv4_with_prefix"
      return ccall("w_ipv4_with_prefix", args[1], args[2])
    when "w_ipv4_octet"
      return ccall("w_ipv4_octet", args[1], args[2])
    when "w_ipv4_octets"
      return ccall("w_ipv4_octets", args[1])
    when "w_ipv4_network"
      return ccall("w_ipv4_network", args[1])
    when "w_ipv4_broadcast"
      return ccall("w_ipv4_broadcast", args[1])
    when "w_ipv4_netmask"
      return ccall("w_ipv4_netmask", args[1])
    when "w_ipv4_in_cidr"
      return ccall("w_ipv4_in_cidr", args[1], args[2])
    when "w_ipv4_private_p"
      return ccall("w_ipv4_private_p", args[1])
    when "w_ipv4_loopback_p"
      return ccall("w_ipv4_loopback_p", args[1])
    when "w_ipv4_link_local_p"
      return ccall("w_ipv4_link_local_p", args[1])
    when "w_ipv4_multicast_p"
      return ccall("w_ipv4_multicast_p", args[1])
    when "w_ipv4_unspecified_p"
      return ccall("w_ipv4_unspecified_p", args[1])
    when "w_ipv4_broadcast_p"
      return ccall("w_ipv4_broadcast_p", args[1])
    when "w_ipv4_reserved_p"
      return ccall("w_ipv4_reserved_p", args[1])
    when "w_ipv4_global_p"
      return ccall("w_ipv4_global_p", args[1])

    when "w_ipv6_parse"
      return ccall("w_ipv6_parse", args[1])
    when "w_ipv6_prefix"
      return ccall("w_ipv6_prefix", args[1])
    when "w_ipv6_cidr_p"
      return ccall("w_ipv6_cidr_p", args[1])
    when "w_ipv6_with_prefix"
      return ccall("w_ipv6_with_prefix", args[1], args[2])
    when "w_ipv6_byte"
      return ccall("w_ipv6_byte", args[1], args[2])
    when "w_ipv6_bytes"
      return ccall("w_ipv6_bytes", args[1])
    when "w_ipv6_network"
      return ccall("w_ipv6_network", args[1])
    when "w_ipv6_in_cidr"
      return ccall("w_ipv6_in_cidr", args[1], args[2])
    when "w_ipv6_unspecified_p"
      return ccall("w_ipv6_unspecified_p", args[1])
    when "w_ipv6_loopback_p"
      return ccall("w_ipv6_loopback_p", args[1])
    when "w_ipv6_multicast_p"
      return ccall("w_ipv6_multicast_p", args[1])
    when "w_ipv6_link_local_p"
      return ccall("w_ipv6_link_local_p", args[1])
    when "w_ipv6_unique_local_p"
      return ccall("w_ipv6_unique_local_p", args[1])
    when "w_ipv6_global_p"
      return ccall("w_ipv6_global_p", args[1])
    when "w_ip_in_cidr"
      return ccall("w_ip_in_cidr", args[1], args[2])

    when "w_mac_parse"
      return ccall("w_mac_parse", args[1])
    when "w_mac_byte"
      return ccall("w_mac_byte", args[1], args[2])
    when "w_mac_bytes"
      return ccall("w_mac_bytes", args[1])
    when "w_mac_multicast_p"
      return ccall("w_mac_multicast_p", args[1])
    when "w_mac_unicast_p"
      return ccall("w_mac_unicast_p", args[1])
    when "w_mac_local_p"
      return ccall("w_mac_local_p", args[1])
    when "w_mac_universal_p"
      return ccall("w_mac_universal_p", args[1])
    when "w_mac_broadcast_p"
      return ccall("w_mac_broadcast_p", args[1])

    when "w_crypto_random_bytes"
      return ccall("w_crypto_random_bytes", args[1])
    when "w_crypto_md5_bytes"
      return ccall("w_crypto_md5_bytes", args[1])
    when "w_crypto_md5_hex"
      return ccall("w_crypto_md5_hex", args[1])
    when "w_crypto_sha1_bytes"
      return ccall("w_crypto_sha1_bytes", args[1])
    when "w_crypto_sha1_hex"
      return ccall("w_crypto_sha1_hex", args[1])
    when "w_crypto_sha1_base64"
      return ccall("w_crypto_sha1_base64", args[1])
    when "w_crypto_sha224_bytes"
      return ccall("w_crypto_sha224_bytes", args[1])
    when "w_crypto_sha224_hex"
      return ccall("w_crypto_sha224_hex", args[1])
    when "w_crypto_sha256_bytes"
      return ccall("w_crypto_sha256_bytes", args[1])
    when "w_crypto_sha256_hex"
      return ccall("w_crypto_sha256_hex", args[1])
    when "w_crypto_sha384_bytes"
      return ccall("w_crypto_sha384_bytes", args[1])
    when "w_crypto_sha384_hex"
      return ccall("w_crypto_sha384_hex", args[1])
    when "w_crypto_sha512_bytes"
      return ccall("w_crypto_sha512_bytes", args[1])
    when "w_crypto_sha512_hex"
      return ccall("w_crypto_sha512_hex", args[1])
    when "w_crypto_sha512_224_bytes"
      return ccall("w_crypto_sha512_224_bytes", args[1])
    when "w_crypto_sha512_224_hex"
      return ccall("w_crypto_sha512_224_hex", args[1])
    when "w_crypto_sha512_256_bytes"
      return ccall("w_crypto_sha512_256_bytes", args[1])
    when "w_crypto_sha512_256_hex"
      return ccall("w_crypto_sha512_256_hex", args[1])

    when "w_uuid_parse"
      return ccall("w_uuid_parse", args[1])
    when "w_uuid_namespace_nil"
      return ccall("w_uuid_namespace_nil")
    when "w_uuid_namespace_dns"
      return ccall("w_uuid_namespace_dns")
    when "w_uuid_namespace_url"
      return ccall("w_uuid_namespace_url")
    when "w_uuid_namespace_oid"
      return ccall("w_uuid_namespace_oid")
    when "w_uuid_namespace_x500"
      return ccall("w_uuid_namespace_x500")
    when "w_uuid_v1"
      return ccall("w_uuid_v1", args[1])
    when "w_uuid_v2"
      return ccall("w_uuid_v2", args[1])
    when "w_uuid_v3"
      return ccall("w_uuid_v3", args[1], args[2])
    when "w_uuid_v4"
      return ccall("w_uuid_v4")
    when "w_uuid_v5"
      return ccall("w_uuid_v5", args[1], args[2])
    when "w_uuid_v6"
      return ccall("w_uuid_v6")
    when "w_uuid_v7"
      return ccall("w_uuid_v7")
    when "w_uuid_v8"
      return ccall("w_uuid_v8", args[1])
    when "w_uuid_byte"
      return ccall("w_uuid_byte", args[1], args[2])
    when "w_uuid_bytes"
      return ccall("w_uuid_bytes", args[1])
    when "w_uuid_to_s"
      return ccall("w_uuid_to_s", args[1])

    raise "Unsupported ccall '[cname]' in interpreter"

  # Familiar names from other languages, mapped to the Tungsten idiom — only
  # consulted after every real lookup has failed. (The lowering pass keeps its
  # own copy for unknown compiled calls; use-order separates the two files.)
  -> foreign_name_hint(name)
    case name
      "console" => "Tungsten prints with `<<`: << expression"
      "fmt" => "Tungsten prints with `<<`: << expression"
      "System" => "Tungsten prints with `<<`: << expression"
      "std" => "Tungsten prints with `<<`: << expression"
      "len" => "length is a method: value.size()"
      "elif" => "Tungsten spells it `elsif`"
      "lambda" => "blocks are written with `->`: list.map -> item * 2"
      "require" => "Tungsten imports with `use`: use core/tensor"
      "import" => "Tungsten imports with `use`: use core/tensor"
      "null" => "Tungsten's missing value is `nil`"
      "None" => "Tungsten's missing value is `nil`"
      "True" => "Tungsten booleans are lowercase: true"
      "False" => "Tungsten booleans are lowercase: false"
      => nil

  -> callable?(name)
    if is_builtin?(name)
      return true
    if @env.defined?("__method__" + name)
      return true
    s = current_self()
    if s != nil && type(s) == "Hash" && s.has_key?(:rt) && s[:rt] == :object
      if lookup_method(s[:w_class], name) != nil
        return true
    false

  -> eval_ivar(node)
    obj = current_self()
    if obj == nil || type(obj) != "Hash" || !obj.has_key?(:rt) || obj[:rt] != :object
      raise "Instance variable outside of object context"
    name = ast_get(node, :name)
    if obj[:ivars].has_key?(name)
      return obj[:ivars][name]
    nil

  # An unset $global reads as nil (matches Ruby) rather than raising —
  # unlike eval_var's undefined-name error path, since there's no
  # "did you mean a bare method call" ambiguity for a $-sigiled name.
  -> eval_gvar(node)
    @globals[ast_get(node, :name)]

  # `receiver$field` — read a view-decl field off an explicit receiver.
  # The tree-walker models `- data` layout fields as accessor methods
  # (register_data_field_accessors), so the faithful mirror of the
  # compiled inline struct read is to dispatch the field's accessor on
  # the evaluated receiver. Works for user classes with a data block and
  # for builtins whose field name coincides with a query method (arr$size).
  -> eval_view_field_var(node, env)
    recv = evaluate(ast_get(node, :receiver), env)
    field = ast_get(node, :field)
    dispatch_method(recv, field, [], nil, env)

  # -- Assignment --

  -> eval_assign(node, env)
    value = evaluate(ast_get(node, :value), env)
    value = apply_type_hint(value, ast_get(node, :type_hint))
    target = ast_get(node, :target)

    if ast_kind(target) == :var
      env.set(ast_get(target, :name), value)
      return value

    if ast_kind(target) == :gvar
      @globals[ast_get(target, :name)] = value
      return value

    if ast_kind(target) == :ivar
      obj = current_self()
      if obj == nil || type(obj) != "Hash" || !obj.has_key?(:rt) || obj[:rt] != :object
        raise "Instance variable assignment outside of object context"
      obj[:ivars][ast_get(target, :name)] = value
      return value

    if ast_kind(target) == :call
      eval_call_assign(target, value, env)
      return value

    raise "Invalid assignment target"

  # `a, b = [1, 2]` / `<int>: a, b, c` — destructure the value list into the
  # targets. The parser supplies the value as an Array node, so evaluating it
  # yields a list to index per target.
  -> eval_multi_assign(node, env)
    value = evaluate(ast_get(node, :value), env)
    targets = ast_get(node, :targets)
    i = 0
    while i < targets.size()
      env.set(ast_get(targets[i], :name), value[i])
      i += 1
    value

  -> eval_call_assign(call_node, value, env)
    recv = evaluate(ast_get(call_node, :receiver), env)
    if ast_get(call_node, :name) == "\[]="
      index_val = evaluate(ast_get(call_node, :args)[0], env)
      rhs = evaluate(ast_get(call_node, :args)[1], env)
      recv[index_val] = rhs
    else
      dispatch_method(recv, ast_get(call_node, :name) + "=", [value], nil, env)

  -> eval_compound_assign(node, env)
    target = ast_get(node, :target)
    op = ast_get(node, :op)
    new_val = evaluate(ast_get(node, :value), env)

    if ast_kind(target) == :var
      old = env.get(ast_get(target, :name))
      result = apply_compound_op(op, old, new_val)
      env.set(ast_get(target, :name), result)
      return result

    if ast_kind(target) == :gvar
      name = ast_get(target, :name)
      old = @globals[name]
      if old == nil
        old = 0
      result = apply_compound_op(op, old, new_val)
      @globals[name] = result
      return result

    if ast_kind(target) == :ivar
      obj = current_self()
      old = obj[:ivars][ast_get(target, :name)]
      if old == nil
        old = 0
      result = apply_compound_op(op, old, new_val)
      obj[:ivars][ast_get(target, :name)] = result
      return result

    raise "Invalid compound assignment target"

  -> apply_compound_op(op, left, right)
    if op == :PLUS
      if type(left) == "String"
        return left + w_to_s(right)
      return left + right
    if op == :MINUS
      return left - right
    if op == :STAR
      return left * right
    if op == :SLASH
      return left / right
    if op == :PERCENT
      return left % right
    raise "Unknown compound operator"

  # -- Binary operations --

  # Conversion-pipe target for `| lb` / `| lb(2)` / `| J`: a bare known-unit
  # name (var, PascalCase class_ref, or one-int-arg call) that isn't shadowed
  # by a local. Mirrors lowering/ops.w pipe_unit_target.
  -> interp_pipe_unit_target(node, env)
    r = ast_get(node, :right)
    if !is_ast_node?(r)
      return nil
    uname = nil
    udigits = 0 - 1
    k = ast_kind(r)
    if k == :var || k == :class_ref
      uname = ast_get(r, :name)
    elsif k == :call && ast_get(r, :receiver) == nil
      cargs = ast_get(r, :args)
      if cargs != nil && cargs.size() == 1 && is_ast_node?(cargs[0]) && ast_kind(cargs[0]) == :int
        uname = ast_get(r, :name)
        udigits = ast_get(cargs[0], :value)
    if uname == nil
      return nil
    # Materialize: node-field strings can be lexer slices whose WValue bits
    # never match known_unit_name?'s interned tuple members.
    uname = "" + uname.to_s()
    if !known_unit_name?(uname)
      return nil
    if env.defined?(uname) || @env.defined?(uname)
      return nil
    {name: uname, digits: udigits}

  -> eval_binary_op(node, env)
    # Canonicalize the op symbol: slab-stored short symbols carry different
    # WValue bits than SSO literals, and mixed-mode == is slab-layout-
    # sensitive. w_switch_canonical repacks ≤5-byte content to SSO bits so
    # every comparison below is a deterministic bit match.
    node_op = ccall("w_switch_canonical", ast_get(node, :op))
    if node_op == :PIPE
      pu = interp_pipe_unit_target(node, env)
      if pu != nil
        left = evaluate(ast_get(node, :left), env)
        if w_type_name(left) == "Quantity"
          return ccall("w_quantity_pipe", left, "" + pu[:name], pu[:digits])
    if node_op == :LSHIFT && ast_get(node, :left) != nil && ast_kind(ast_get(node, :left)) == :var
      left = evaluate(ast_get(node, :left), env)
      if type(left) == "String"
        right = evaluate(ast_get(node, :right), env)
        result = left + w_to_s(right)
        env.set(ast_get(ast_get(node, :left), :name), result)
        return result
    left = evaluate(ast_get(node, :left), env)
    right = evaluate(ast_get(node, :right), env)
    apply_binary_op(node_op, left, right)

  -> apply_binary_op(op, left, right)
    # Object operands dispatch their own operator method (a + b -> a.+(b)),
    # mirroring the compiled operator-overload path and the `·` arm below —
    # covers the hypercomplex tower, Vec/Mat, etc. Arithmetic/bitwise only;
    # comparisons (== < > …) fall through to the primitive arms unchanged.
    if type(left) == "Hash" && left.has_key?(:rt) && left[:rt] == :object
      opn = binop_method_name(op)
      if opn != nil
        return dispatch_method(left, opn, [right], nil, nil)
    if op == :PLUS
      # Strict string `+` — only text concatenates with text; a String
      # mixed with anything else is a TypeError, mirroring runtime w_add.
      if type(left) == "String"
        if type(right) == "String" || type(right) == "Char"
          return left + right
        raise "TypeError: no implicit conversion of [w_type_name(right)] into String"
      if type(left) == "Array"
        if type(right) == "Array"
          return left + right
        return left + [right]
      if type(right) == "String" && type(left) != "Char" && type(left) != "StringBuffer"
        raise "TypeError: String can't be coerced into [w_type_name(left)]"
      return left + right
    if op == :MINUS
      return left - right
    if op == :STAR
      return left * right
    if op == :DOT_PRODUCT
      # `·` — multiplication on numerics/quantities; objects (Vec3 etc.)
      # dispatch their own `·` method, mirroring the compiled universal arm.
      if type(left) == "Hash"
        return dispatch_method(left, "·", [right], nil, nil)
      return left * right
    if op == :POW
      return left ** right
    if op == :SLASH
      if type(left) == "Hash" && left[:rt] == :range
        return eval_range_step(left, right)
      return left / right
    if op == :PERCENT
      return left % right
    if op == :AMPERSAND
      return left & right
    if op == :PIPE
      return left | right
    if op == :CARET
      return left ^ right
    if op == :LSHIFT
      # StringBuffer append — mutates in place, mirrors the compiled
      # direct-builtin lowering of `buf << str`.
      if w_type_name(left) == "StringBuffer"
        ccall("w_strbuf_append", left, w_to_s(right))
        return left
      return left << right
    if op == :RSHIFT
      return left >> right
    if op == :EQ
      return left == right
    if op == :NEQ
      return left != right
    if op == :LT
      return left < right
    if op == :LTE
      return left <= right
    if op == :GT
      return left > right
    if op == :GTE
      return left >= right
    raise "Unknown operator: [op]"

  # Operator symbol -> the method name an object overloads it with, so
  # apply_binary_op can dispatch `a <op> b` to `a.<method>(b)`. Returns nil
  # for ops not overloaded here (comparisons stay on the primitive arms).
  -> binop_method_name(op)
    if op == :PLUS
      return "+"
    if op == :MINUS
      return "-"
    if op == :STAR
      return "*"
    if op == :SLASH
      return "/"
    if op == :PERCENT
      return "%"
    if op == :POW
      return "**"
    if op == :AMPERSAND
      return "&"
    if op == :PIPE
      return "|"
    if op == :CARET
      return "^"
    nil

  # Range#/ (step): materialize `(a..b) / n` as [a, a+n, a+2n, ...] while
  # < b (or <= b for an inclusive range). Mirrors the compiled path's
  # lower_range_step, which desugars to the same array+while-loop shape.
  -> eval_range_step(range, step)
    from = range[:from]
    to = range[:to]
    excl = range[:exclusive]
    limit = excl ? to : to + 1
    result = []
    i = from
    while i < limit
      result.push(i)
      i += step
    result

  -> eval_unary_op(node, env)
    operand = evaluate(ast_get(node, :operand), env)
    if ast_get(node, :op) == :MINUS
      return 0 - operand
    raise "Unknown unary operator"

  -> apply_type_hint(value, hint)
    if hint == nil || type(value) != "Integer"
      return value
    if hint == "u64"
      return wrap_unsigned_bits(value, 64)
    if hint == "i64"
      return wrap_signed_bits(value, 64)
    if hint == "u128"
      return wrap_unsigned_bits(value, 128)
    if hint == "i128"
      return wrap_signed_bits(value, 128)
    value

  -> wrap_unsigned_bits(value, bits)
    modulus = pow2(bits)
    wrapped = value % modulus
    if wrapped < 0
      return wrapped + modulus
    wrapped

  -> wrap_signed_bits(value, bits)
    modulus = pow2(bits)
    wrapped = wrap_unsigned_bits(value, bits)
    sign_bit = modulus / 2
    if wrapped >= sign_bit
      return wrapped - modulus
    wrapped

  -> pow2(bits)
    result = 1
    i = 0
    while i < bits
      result = result * 2
      i += 1
    result

  -> eval_and(node, env)
    left = evaluate(ast_get(node, :left), env)
    if !truthy?(left)
      return left
    evaluate(ast_get(node, :right), env)

  -> eval_or(node, env)
    left = evaluate(ast_get(node, :left), env)
    if truthy?(left)
      return left
    evaluate(ast_get(node, :right), env)

  # -- Control flow --

  -> eval_if(node, env)
    if truthy?(evaluate(ast_get(node, :condition), env))
      return evaluate_body(ast_get(node, :then_body), env)

    # Elsif clauses
    clauses = ast_get(node, :elsif_clauses)
    i = 0
    while i < clauses.size()
      if truthy?(evaluate(clauses[i][0], env))
        return evaluate_body(clauses[i][1], env)
      i += 1

    if ast_get(node, :else_body) != nil
      return evaluate_body(ast_get(node, :else_body), env)
    nil

  -> eval_while(node, env)
    result = nil
    while truthy?(evaluate(ast_get(node, :condition), env))
      begin
        result = evaluate_body(ast_get(node, :body), env)
      rescue err
        if err == "__SIGNAL__" && @signal[:type] == :break
          @signal[:type] = nil
          break
        elsif err == "__SIGNAL__" && @signal[:type] == :next
          @signal[:type] = nil
          next
        else
          raise err
    result

  # Subject-less cond-case. A bare `recase` in an arm re-tests the conditions:
  # the retry loop re-runs the (unchanged) dispatch. A value `recase` is
  # meaningless without a subject, so its value is ignored.
  -> eval_case(node, env)
    result = nil
    retry_case = true
    while retry_case
      retry_case = false
      begin
        result = eval_case_dispatch(node, env)
      rescue err
        if err == "__SIGNAL__" && @signal[:type] == :recase
          @signal[:type] = nil
          @signal[:has_value] = false
          retry_case = true
        else
          raise err
    result

  -> eval_case_dispatch(node, env)
    whens = ast_get(node, :whens)
    i = 0
    while i < whens.size()
      w = whens[i]
      # ast_get, not w[:conditions] subscript: slab when-nodes don't answer
      # symbol subscript (the hash-AST-era form returned nil → crash).
      conditions = ast_get(w, :conditions)
      j = 0
      while j < conditions.size()
        if truthy?(evaluate(conditions[j], env))
          return evaluate_body(ast_get(w, :body), env)
        j += 1
      i += 1
    if ast_get(node, :else_body) != nil
      return evaluate_body(ast_get(node, :else_body), env)
    nil

  -> eval_case_value(node, env)
    subject = evaluate(ast_get(node, :subject), env)
    result = nil
    retry_case = true
    while retry_case
      retry_case = false
      begin
        result = eval_case_value_dispatch(node, subject, env)
      rescue err
        if err == "__SIGNAL__" && @signal[:type] == :recase
          # `recase expr` sets a new subject; bare `recase` re-evaluates the
          # original subject expression (so `case next_token()` advances).
          if @signal[:has_value]
            subject = @signal[:value]
          else
            subject = evaluate(ast_get(node, :subject), env)
          @signal[:type] = nil
          @signal[:has_value] = false
          retry_case = true
        else
          raise err
    result

  -> eval_case_value_dispatch(node, subject, env)
    arms = ast_get(node, :arms)
    i = 0
    while i < arms.size()
      arm = arms[i]
      pattern = evaluate(ast_get(arm, :pattern), env)
      if pattern == subject
        guard = ast_get(arm, :guard)
        if guard == nil || truthy?(evaluate(guard, env))
          return evaluate_body(ast_get(arm, :body), env)
      i += 1
    if ast_get(node, :else_body) != nil
      return evaluate_body(ast_get(node, :else_body), env)
    nil

  # -- Method calls --

  -> eval_call(node, env)
    block = nil
    if ast_get(node, :block) != nil
      block = evaluate(ast_get(node, :block), env)
    args = ast_get(node, :args).map -> (a)
      evaluate(a, env)

    if ast_get(node, :receiver) != nil
      recv = evaluate(ast_get(node, :receiver), env)
      result = dispatch_method(recv, ast_get(node, :name), args, block, env)
      if ast_kind(ast_get(node, :receiver)) == :var && type(recv) == "String"
        if ast_get(node, :name) in ("concat" "append" "prepend" "<<" "<</1")
          env.set(ast_get(ast_get(node, :receiver), :name), result)
      return result

    dispatch_bare_call(ast_get(node, :name), args, block, env)

  -> dispatch_bare_call(name, args, block, env)
    if name == "ccall"
      return dispatch_interpreted_ccall(args)

    # Explicit fused multiply-add. The tree-walker has no hardware FMA and no
    # runtime fma() to call, so it computes a*b+c directly — double-rounded,
    # NOT the single-rounding the compiled `llvm.fma.f64` gives. Good enough as
    # a reference value; code that depends on the exact single-rounding residual
    # is compiled-path-specific.
    if name == "fma" && args.size() == 3
      return args[0] * args[1] + args[2]

    # Σ(f, a..b): sum f(x) over the integer range. ∫(f, a..b): numeric integral
    # of f over [a, b] (composite Simpson's rule, n = 256). Both receive the
    # lambda the parser's math_fn_rewrite built from polynomial notation
    # (Σ(2x⁷ + 3x²) → Block(x, 2*x**7 + 3*x**2)); a Block evaluates to the
    # [env, node] pair call_block takes. The pipeline form (1..10)/Σ(…) is
    # handled separately by eval_pipeline_calc.
    if name == "Σ" && args.size() == 2
      f = args[0]
      r = args[1]
      if type(r) != "Hash" || r[:rt] != :range
        raise "Σ(f, range): the second argument must be a range, e.g. Σ(2x² + x, 1..10)"
      lo = r[:from]
      hi = r[:to]
      if r[:exclusive]
        hi = hi - 1
      # Closed form first: when the lambda body is a plain integer polynomial
      # (the shape Σ's own rewrite produces), sum it exactly via the SAME
      # runtime primitive the compiled pipeline lowering uses —
      # w_range_pow_sum, Faulhaber in O(p²), BigInt-exact, range-length
      # independent. Falls back to the O(n) loop for anything else.
      cf = sigma_closed_form(f, lo, hi)
      if cf != nil
        return cf
      acc = 0
      x = lo
      while x <= hi
        acc = acc + call_block(f, [x])
        x += 1
      return acc
    if name == "Σ" && args.size() == 1
      raise "Σ needs bounds: Σ(2x² + x, 1..10) or (1..10)/Σ(2x² + x)"
    if name == "∫" && args.size() == 2
      f = args[0]
      r = args[1]
      if type(r) != "Hash" || r[:rt] != :range
        raise "∫(f, range): the second argument must be the bounds, e.g. ∫(x², 0..2)"
      # Float-clean throughout: `1.0`-style literals are Decimals, and mixed
      # decimal/float arithmetic has gaps in the tree-walker; .to_f keeps every
      # intermediate a plain float.
      a = r[:from].to_f
      b = r[:to].to_f
      # Backwards bounds use the sign convention (∫ₐᵇ = −∫ᵇₐ) instead of
      # erroring — scrubbing a bound through the other one stays live.
      flip = 1
      if a > b
        t = a
        a = b
        b = t
        flip = 0 - 1
      n = 256
      h = (b - a) / n
      acc = call_block(f, [a]) + call_block(f, [b])
      i = 1
      while i < n
        w = 2
        if i % 2 == 1
          w = 4
        acc = acc + w * call_block(f, [a + h * i])
        i += 1
      return flip * acc * h / 3
    if name == "∫" && args.size() == 1
      raise "∫ needs bounds: ∫(x², 0..2)"

    # Built-in StringBuffer constructor — mirrors the compiled lowering
    # (calls.w): StringBuffer() / StringBuffer(N) → w_strbuf_new(N).
    if name == "StringBuffer"
      cap = 0
      if args.size() > 0
        cap = args[0]
      return ccall("w_strbuf_new", cap)

    # Method on current self — checked before the generic builtin table so a
    # user's own method (or top-level function, below) wins over a same-named
    # builtin that expects a real receiver (e.g. a top-level `-> max(arr)`
    # must resolve before `is_builtin?("max")`, which would otherwise call
    # dispatch_builtin with a hardcoded nil receiver and crash).
    s = current_self()
    if s != nil && type(s) == "Hash" && s.has_key?(:rt) && s[:rt] == :object
      m = lookup_method(s[:w_class], name)
      if m != nil
        return call_w_method(s, m, args, block, env)

    # Global method
    method_key = "__method__" + name
    if @env.defined?(method_key)
      m = @env.get(method_key)
      return call_w_method(current_self(), m, args, block, env)

    # Builtins — dispatched on the current self (e.g. a bare `map(...)` inside
    # a method body means `self.map(...)`), which is nil at top level (same as
    # the previous hardcoded nil), so this only changes behavior when a real
    # self is active.
    if is_builtin?(name)
      return dispatch_builtin(self, name, current_self(), args, block)

    # Class constructor
    if @classes.has_key?(name)
      return instantiate(@classes[name], args, env)

    # A local/top-level variable holding a closure, invoked directly:
    # `f = -> x ...; f(21)`. A block evaluates to an [env, node] pair (see the
    # :block arm of evaluate); invoke it through call_block. Checked last so
    # real methods/builtins keep priority — this only fires where dispatch
    # would otherwise raise.
    if env.defined?(name) || @env.defined?(name)
      v = nil
      if env.defined?(name)
        v = env.get(name)
      else
        v = @env.get(name)
      if type(v) == "Array" && v.size() == 2 && is_ast_node?(v[1]) && ast_kind(v[1]) == :block
        return call_block(v, args)

    raise "Undefined method '[name]'"

  -> dispatch_method(recv, name, args, block, env)
    # A closure value (an [env, block-node] pair) responds to `.call(args)` by
    # invoking the block. Mirrors the compiled method-dispatch-on-closure path
    # (runtime.c w_closure_call_N) and the bare-call closure dispatch in
    # dispatch_bare_call, so `f.call(x)` and `f(x)` behave the same.
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
      stub = {rt: :class, name: cname, methods: {}, class_methods: {}, parent: nil}
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
      m = lookup_class_method(recv, name)
      if m != nil
        return call_w_method(recv, m, args, block, env)

    # Class.new constructor
    if name == "new" && type(recv) == "Hash" && recv.has_key?(:rt) && recv[:rt] == :class
      return instantiate(recv, args, env)

    # Method on object
    if type(recv) == "Hash" && recv.has_key?(:rt) && recv[:rt] == :object
      m = lookup_method(recv[:w_class], name)
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

    # Date runtime intrinsics (year/month/day/wday/day_of_week/…) have no
    # Tungsten body in core/date.w — route them to the runtime date IC (key
    # 0xE4) via w_method_call BEFORE the class lookup, so they don't resolve to
    # an empty bodyless method. Bodied Date methods (day_name/month_name/
    # strftime/…) fall through to the Date class below, and their internal
    # intrinsic calls land back here.
    if args.size() == 0 && w_type_name(recv) == "Date" && name in ("year" "month" "day" "hour" "minute" "second" "wday" "day_of_week" "day_of_month" "day_of_year" "yday" "cweek" "cwday" "days_in_month" "days_in_year" "leap?" "jd" "quarter" "tz")
      return ccall("w_method_call", recv, "" + name, [])

    # Primitive values can be extended by core classes (Array, String, etc.).
    # Give those class methods first refusal before falling back to boot
    # builtins so traits such as Enumerable participate for primitive arrays.
    primitive_class = primitive_runtime_class(recv)
    if primitive_class != nil
      m = lookup_method(primitive_class, name)
      if m != nil
        return call_w_method(recv, m, args, block, env)

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
      if from != nil && type(from) != "Integer" && ccall("w_class_name", from) == "Decimal"
        from = ccall("w_range_bound_i64_w", from)
      if to != nil && type(to) != "Integer" && ccall("w_class_name", to) == "Decimal"
        to = ccall("w_range_bound_i64_w", to)
      excl = recv[:exclusive]
      unbounded = to == nil
      if name == "each" && block != nil
        i = from
        limit = 0
        if !unbounded
          limit = excl ? to : to + 1
        while unbounded || i < limit
          begin
            call_block(block, [i])
          rescue err
            if err == "__SIGNAL__" && @signal[:type] == :break
              @signal[:type] = nil
              break
            elsif err == "__SIGNAL__" && @signal[:type] == :next
              @signal[:type] = nil
            else
              raise err
          i = i + 1
        return nil
      if name == "step" && args.size() == 1
        raise "cannot call .step on unbounded range" if unbounded
        if block != nil
          i = from
          limit = excl ? to : to + 1
          while i < limit
            begin
              call_block(block, [i])
            rescue err
              if err == "__SIGNAL__" && @signal[:type] == :break
                @signal[:type] = nil
                break
              elsif err == "__SIGNAL__" && @signal[:type] == :next
                @signal[:type] = nil
              else
                raise err
            i += args[0]
          return nil
        return eval_range_step(recv, args[0])
      if name == "map" && block != nil
        raise "cannot call .map on unbounded range" if unbounded
        result = []
        i = from
        limit = excl ? to : to + 1
        while i < limit
          result.push(call_block(block, [i]))
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

    # Builtins
    if is_builtin?(name)
      return dispatch_builtin(self, name, recv, args, block)

    # Index operators
    if name == "\[]"
      return recv[args[0]]
    if name == "\[]="
      recv[args[0]] = args[1]
      return args[1]
    if name == "flip" && args.size() == 1
      recv[args[0]] = !recv[args[0]]
      return nil

    # Parity is lowered inline on the compiled path; the runtime IC has no
    # handler, so compute it here so `n.even?` / `n.odd?` work under -e/--wit.
    if type(recv) == "Integer" && args.size() == 0
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
      if args.size() == 0 && name in ("to_f" "to_i" "floor" "ceil" "round" "chr" "ord" "prime?" "prime_12k?" "prime_30k?" "abs" "to_s" "sqrt" "sq" "succ" "prev" "negative?")
        return ccall("w_method_call", recv, "" + name, [])
      if args.size() == 1 && name == "gcd"
        return ccall("w_method_call", recv, "" + name, args)

    raise "undefined method '[name]' for [w_to_s(recv)]"

  -> primitive_runtime_class(recv)
    class_name = nil
    t = type(recv)
    if t == "Array"
      class_name = "Array"
    elsif t == "String"
      class_name = "String"
    elsif t == "Integer"
      class_name = "Integer"
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
    if class_name == nil
      tn = w_type_name(recv)
      # Rich runtime literal types (Date/IPv4/IPv6/MAC/…) report their core
      # class through `type`. Literal syntax never names the class, so lazy
      # autoload may not have fired before a bodied helper is called.
      if tn != nil
        try_autoload_class(tn)
        if @classes.has_key?(tn)
          return @classes[tn]
      return nil
    @classes[class_name]

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

  -> lookup_method(w_class, name)
    if w_class == nil
      return nil
    if w_class[:methods].has_key?(name)
      return w_class[:methods][name]
    # Check superclass
    lookup_method(w_class[:superclass], name)

  -> lookup_class_method(w_class, name)
    if w_class == nil
      return nil
    class_methods = w_class[:class_methods]
    if class_methods != nil && class_methods.has_key?(name)
      return class_methods[name]
    lookup_class_method(w_class[:superclass], name)

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

    # Bind parameters
    params = ast_get(method, :params)
    i = 0
    while i < params.size()
      param = params[i]
      value = nil
      if i < args.size()
        value = args[i]
      elsif ast_get(param, :default) != nil
        value = evaluate(ast_get(param, :default), method_env)

      method_env.define(ast_get(param, :name), value)

      # Auto-assign ivar params
      if ast_get(param, :ivar_assign) && recv != nil && type(recv) == "Hash" && recv.has_key?(:rt) && recv[:rt] == :object
        recv[:ivars]["@" + ast_get(param, :name)] = value
      i += 1

    # Bind block
    if block != nil
      method_env.define("__block__", block)

    @self_stack.push(recv)
    result = nil
    begin
      result = evaluate_body(ast_get(method, :body), method_env)
    rescue err
      if err == "__SIGNAL__" && @signal[:type] == :return
        result = @signal[:value]
        @signal[:type] = nil
      else
        @self_stack.pop()
        raise err
    @self_stack.pop()
    result

  -> collect_free_vars(node, env, vars, seen)
    if node == nil
      return nil
    if type(node) == "Array"
      node.each -> (child)
        collect_free_vars(child, env, vars, seen)
      return nil
    if !is_ast_node?(node) || ast_kind(node) == nil
      return nil
    t = ast_kind(node)
    if t == :block
      return nil
    if t == :var
      name = ast_get(node, :name)
      if seen[name] == nil && name[0] != "@" && !env.defined?(name)
        seen[name] = true
        vars.push(name)
      return nil
    if t == :assign
      collect_free_vars(ast_get(node, :value), env, vars, seen)
      if ast_get(node, :target) != nil && ast_kind(ast_get(node, :target)) == :var
        seen[ast_get(ast_get(node, :target), :name)] = true
      return nil
    if t == :compound_assign
      collect_free_vars(ast_get(node, :value), env, vars, seen)
      collect_free_vars(ast_get(node, :target), env, vars, seen)
      return nil
    if t == :string_interp
      parts = ast_get(node, :parts)
      i = 0
      while i < parts.size()
        part = parts[i]
        if part[0] != :str
          collect_free_vars(part[1], env, vars, seen)
        i += 1
      return nil
    # Generic walk: recurse into all AST children. The Hash-era walk
    # skipped :node/:op/:name/:exclusive keys explicitly — those carry
    # primitives (kind sym, op sym, identifier name, range exclusive
    # flag), not children, and ast_children() already excludes them
    # by walking only Hash/Array slot values.
    ast_children(node).each -> (c)
      collect_free_vars(c, env, vars, seen)
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
          collect_free_vars(ast_get(blk_node, :body), blk_env, vars, {})
          ast_set(blk_node, :_free_vars, vars)
        free_vars = ast_get(blk_node, :_free_vars)
        i = 0
        while i < free_vars.size() && i < args.size()
          block_env.define(free_vars[i], args[i])
          i += 1
      else
        i = 0
        while i < params.size()
          block_env.define(params[i], args[i])
          i += 1
      begin
        return evaluate_body(ast_get(blk_node, :body), block_env)
      rescue err
        if err == "__SIGNAL__" && @signal[:type] == :next
          @signal[:type] = nil
          return nil
        raise err
    nil

  # -- Class/method definitions --

  # `trait Name ... ` — record the trait's own body (its method_defs) under
  # its name; expand_trait_includes splices these into a composing class's
  # body, mirroring the compiled path's expand_class_traits (lowering.w).
  -> eval_trait_def(node, env)
    @traits[ast_get(node, :name)] = ast_get(node, :body)
    nil

  # Replace each `is TraitName` (:trait_include) marker in a class body with
  # the named trait's own method_defs, spliced in place. A class's own
  # methods appear later in the walked list (either before or after the
  # `is TraitName` line, depending on source order) and simply overwrite the
  # trait's entry in w_class[:methods] via eval_class_def's last-wins
  # assignment — so the trait acts as a set of defaults, not an override.
  # An unresolvable trait name is left as a bare :trait_include, which the
  # main evaluate() dispatcher no-ops (see its :trait_include case).
  -> expand_trait_includes(body)
    if body == nil
      return body
    expanded = []
    body.each -> (expr)
      if is_ast_node?(expr) && ast_kind(expr) == :trait_include && @traits.has_key?(ast_get(expr, :name))
        @traits[ast_get(expr, :name)].each -> (m)
          expanded.push(m)
      else
        expanded.push(expr)
    expanded

  -> eval_class_def(node, env)
    # Class re-open: if a class with this name already exists, merge the
    # new methods into the existing class table with last-wins semantics
    # on name collisions. First-declaration wins for superclass.
    w_class = @classes[ast_get(node, :name)]
    if w_class == nil
      superclass = nil
      if ast_get(node, :superclass) != nil
        # Autoload the parent so a subclass of an autoloaded generic (e.g.
        # Octonion < Hypercomplex) inherits its methods (+, abs2, <=>) — the
        # bare lookup below would otherwise miss a not-yet-referenced parent.
        try_autoload_class(ast_get(node, :superclass))
        superclass = @classes[ast_get(node, :superclass)]
      w_class = {rt: :class, name: ast_get(node, :name), superclass: superclass, methods: {}, class_methods: {}}
      @classes[ast_get(node, :name)] = w_class
    if w_class[:class_methods] == nil
      w_class[:class_methods] = {}

    expand_trait_includes(ast_get(node, :body)).each -> (expr)
      if ast_kind(expr) == :method_def
        mbody = register_trailing_accessors(expr, ast_get(expr, :body), w_class)
        w_method = {rt: :method, name: ast_get(expr, :name), params: ast_get(expr, :params), body: mbody, w_class: w_class, file: @current_file}
        if ast_get(expr, :is_class_method) == true
          w_class[:class_methods][ast_get(expr, :name)] = w_method
        else
          w_class[:methods][ast_get(expr, :name)] = w_method
      elsif ast_kind(expr) == :view_decl && ast_get(expr, :kind) == "struct"
        register_data_field_accessors(expr, w_class)
      else
        # Declarative class-body pragmas (noncommutative / noassoc / runtime …)
        # are bare receiver-less calls the interpreter has no handler for. The
        # compiled lower_class_def silently skips any class-body statement that
        # isn't a method / accessor / view / assign; mirror that here. Without
        # this, the pragma's `evaluate` raise aborts method registration and
        # leaves the class a method-less husk (autoload's rescue then hides it).
        if !(ast_kind(expr) == :call && ast_get(expr, :receiver) == nil)
          evaluate(expr, env)
    w_class

  # `-> new(@x, @y) ro` — a bare ro/rw body statement marks the @-bound
  # params for accessor generation (readers; rw adds writers). Registers the
  # accessors and returns the body with the marker stripped — mirrors the
  # compiled desugar in lowering/definitions.w.
  -> register_trailing_accessors(mdef, body, w_class)
    if body == nil
      return body
    marker = nil
    kept = []
    i = 0
    while i < body.size()
      st = body[i]
      if marker == nil && is_ast_node?(st) && ast_kind(st) == :call && ast_get(st, :receiver) == nil && (ast_get(st, :name) == "ro" || ast_get(st, :name) == "rw") && (ast_get(st, :args) == nil || ast_get(st, :args).size() == 0)
        marker = ast_get(st, :name)
      else
        kept.push(st)
      i += 1
    if marker == nil
      return body
    params = ast_get(mdef, :params)
    i = 0
    while i < params.size()
      p = params[i]
      if ast_get(p, :ivar_assign) == true
        fname = ast_get(p, :name)
        if !w_class[:methods].has_key?(fname)
          w_class[:methods][fname] = {rt: :method, name: fname, params: [], body: [Tungsten:AST:Ivar.new("@" + fname)], w_class: w_class}
        if marker == "rw"
          sname = fname + "="
          if !w_class[:methods].has_key?(sname)
            w_class[:methods][sname] = {rt: :method, name: sname, params: [Tungsten:AST:Param.new("value", nil, false)], body: [Tungsten:AST:Assign.new(Tungsten:AST:Ivar.new("@" + fname), Tungsten:AST:Var.new("value"))], w_class: w_class}
      i += 1
    kept

  # A `- data` struct block (`field x` / `T components[3]`) declares the
  # instance's memory layout. The compiled path emits a getter per field;
  # the tree-walker stores fields as plain ivars (the constructor's `@field`
  # params populate them), so each field just needs a method that reads the
  # matching `@field`. Defined only when the class doesn't already supply an
  # explicit method of that name (a hand-written accessor wins).
  -> register_data_field_accessors(view_decl, w_class)
    layout = ast_get(view_decl, :count)
    if layout == nil || type(layout) != "Hash" || layout[:fields] == nil
      return nil
    layout[:fields].each -> (f)
      fname = f[:name]
      if fname != nil && !w_class[:methods].has_key?(fname)
        accessor = {rt: :method, name: fname, params: [], body: [Tungsten:AST:Ivar.new("@" + fname)], w_class: w_class}
        w_class[:methods][fname] = accessor

  -> eval_method_def(node, env)
    s = current_self()
    if s != nil && type(s) == "Hash" && s.has_key?(:rt) && s[:rt] == :object
      w_method = {rt: :method, name: ast_get(node, :name), params: ast_get(node, :params), body: ast_get(node, :body), w_class: s[:w_class]}
      s[:w_class][:methods][ast_get(node, :name)] = w_method
    else
      w_method = {rt: :method, name: ast_get(node, :name), params: ast_get(node, :params), body: ast_get(node, :body)}
      @env.define("__method__" + ast_get(node, :name), w_method)
    ast_get(node, :name)

  -> eval_on_guard(node, env)
    target = detect_target()
    if !target_matches?(ast_get(node, :predicate), ast_get(node, :capabilities), target)
      return nil
    result = nil
    i = 0
    while i < ast_get(node, :body).size()
      result = evaluate(ast_get(node, :body)[i], env)
      i += 1
    result

  -> instantiate(w_class, args, env)
    obj = {rt: :object, w_class: w_class, ivars: {}}
    constructor = lookup_method(w_class, "new")
    if constructor != nil
      call_w_method(obj, constructor, args, nil, env)
    obj

  # -- Super --

  -> eval_super(node, env)
    obj = current_self()
    if obj == nil || type(obj) != "Hash" || !obj.has_key?(:rt) || obj[:rt] != :object
      raise "super outside of method"
    w_class = obj[:w_class]
    super_class = w_class[:superclass]
    if super_class == nil
      raise "no superclass"
    args = ast_get(node, :args).map -> (a)
      evaluate(a, env)
    constructor = lookup_method(super_class, "new")
    if constructor != nil
      call_w_method(obj, constructor, args, nil, env)

  # -- Use --

  -> eval_use(node)
    base_dir = ""
    if @current_file != nil
      # Get directory of current file
      parts = @current_file.split("/")
      parts.pop()
      base_dir = parts.join("/")
    path = resolve_use_path(ast_get(node, :path), base_dir)

    if @loaded_files.include?(path)
      return nil
    @loaded_files.push(path)

    source = read_file(path)
    prev_file = @current_file
    @current_file = path
    begin
      ast = parse_source(source)
      execute_program(ast)
    ensure
      @current_file = prev_file

  -> resolve_use_path(use_path, base_dir)
    # `core/` prefix: always resolves to <project_root>/core/<rest>.w.
    if use_path.starts_with?("core/")
      project_root = find_use_project_root(base_dir)
      if project_root != ""
        core_path = project_root + "/" + use_path + ".w"
        if read_file(core_path) != nil
          return core_path

    path = use_path
    if !path.starts_with?("/")
      full_path = StringBuffer(base_dir.size() + path.size() + 1)
      full_path << base_dir
      full_path << "/"
      full_path << path
      path = full_path.to_s()
    if !path.ends_with?(".w") && !path.ends_with?(".w0")
      if @current_file != nil && @current_file.ends_with?(".w0")
        path += ".w0"
      else
        path += ".w"

    source = read_file(path)
    if source != nil
      return path

    # Bit resolution
    bit_name = use_path.split("/").first().downcase()
    sub_parts = use_path.split("/")
    sub_parts.shift()
    sub_path = sub_parts.join("/")

    bit_home = env("BIT_HOME")
    if bit_home == nil
      project_root = find_use_project_root(base_dir)
      if project_root != ""
        bit_home = project_root + "/bits"

    if bit_home != nil
      found = resolve_use_bit(bit_name, sub_path, bit_home)
      if found != nil
        return found

    # Standard library: project_root/core/<path>.w first, then
    # project_root/lib/<path>.w for backward compat during migration.
    project_root = find_use_project_root(base_dir)
    if project_root != ""
      core_candidate = project_root + "/core/" + use_path + ".w"
      if read_file(core_candidate) != nil
        return core_candidate
      lib_candidate = project_root + "/lib/" + use_path + ".w"
      if read_file(lib_candidate) != nil
        return lib_candidate

    path

  -> resolve_use_bit(bit_name, sub_path, bit_home)
    if sub_path == ""
      entry_file = bit_name.replace("tungsten-", "") + ".w"
    else
      entry_file = sub_path + ".w"

    if bit_name.starts_with?("tungsten-")
      candidate = bit_home + "/" + bit_name + "/lib/" + entry_file
      if read_file(candidate) != nil
        return candidate

    exact = bit_home + "/" + bit_name + "/lib/" + entry_file
    if read_file(exact) != nil
      return exact
    prefixed = bit_home + "/tungsten-" + bit_name + "/lib/" + entry_file
    if read_file(prefixed) != nil
      return prefixed
    nil

  -> find_use_project_root(dir)
    # Source-ancestry-first: walk up from the source file's directory.
    # Only fall back to CWD-relative "." if source ancestry has no
    # Bitfile at all. See loader.w:find_project_root for rationale.
    if dir != ""
      parts = dir.split("/")
      result = ""
      i = parts.size()
      while i > 0
        candidate = parts[0...i].join("/")
        if file?(candidate + "/Bitfile")
          result = candidate
        i -= 1
      if result != ""
        return result
    if file?("Bitfile")
      return "."
    ""

  # -- Begin/rescue/ensure --

  -> eval_begin(node, env)
    result = nil
    begin
      result = evaluate_body(ast_get(node, :body), env)
    rescue err
      if err == "__SIGNAL__"
        raise err
      if ast_get(node, :rescue_body) != nil
        if ast_get(node, :rescue_var) != nil
          env.set(ast_get(node, :rescue_var), err)
        result = evaluate_body(ast_get(node, :rescue_body), env)
      else
        raise err
    if ast_get(node, :ensure_body) != nil
      evaluate_body(ast_get(node, :ensure_body), env)
    result

  # -- Yield --

  -> eval_yield(node, env)
    args = ast_get(node, :args).map -> (a)
      evaluate(a, env)
    block = find_block(env)
    if block == nil
      raise "no block given"
    call_block(block, args)

  -> find_block(env)
    current = env
    while current != nil
      if current.defined_locally?("__block__")
        return current.get("__block__")
      current = current.parent()
    nil

  # -- I/O --

  -> eval_puts(node, env)
    ast_get(node, :value).each -> (v)
      << w_to_s(evaluate(v, env))
    nil

  -> eval_print(node, env)
    value = evaluate(ast_get(node, :value), env)
    <- w_to_s(value)
    nil

  # -- Hash literal --

  -> eval_hash(node, env)
    result = {}
    ast_get(node, :entries).each -> (entry)
      k = evaluate(entry[0], env)
      v = evaluate(entry[1], env)
      result[k] = v
    result

  # `bool[N]` / `i32[N]` / etc. — zero-filled typed array. Mirrors
  # lower_typed_array_new (compiler/lib/lowering/literals.w): bool routes
  # to the bit-packed BoolArray allocator, other known element types to
  # the generic bits-keyed zero-fill, anything else falls back to a plain
  # empty Array so the tree-walker never crashes on an unrecognized etype.
  -> eval_typed_array_new(node, env)
    etype = ast_get(node, :element_type)
    size = evaluate(ast_get(node, :size), env)
    if etype == "bool"
      return ccall("w_bool_array_new", size)
    bits = 0
    if etype == "u1" || etype == "i1"
      bits = 1
    elsif etype == "u4"
      bits = 4
    elsif etype == "i4"
      bits = -4
    elsif etype == "u8"
      bits = 8
    elsif etype == "i8"
      bits = 108
    elsif etype == "u16"
      bits = 16
    elsif etype == "i16"
      bits = 116
    elsif etype in ("u32" "i32")
      bits = 32
    elsif etype in ("u64" "i64")
      bits = 64
    elsif etype == "f32"
      bits = 0 - 32
    elsif etype == "bf16"
      bits = 0 - 116
    elsif etype == "w64"
      bits = 65
    elsif etype == "f64"
      bits = 0 - 64
    if bits != 0
      return ccall("w_array_zeros", bits.to_s(), size)
    ccall("w_array_new_empty")

  # -- String interpolation --

  -> eval_string_interp(node, env)
    parts = ast_get(node, :parts)
    result = ""
    parts.each -> (part)
      if part[0] == :str
        result += part[1]
      else
        result += w_to_s(evaluate(part[1], env))
    result

  -> current_self
    @self_stack.last()

  # -- Introspection helpers for builtins --

  -> respond_to_method?(recv, method_name)
    if type(recv) == "Hash" && recv.has_key?(:rt) && recv[:rt] == :object
      return lookup_method(recv[:w_class], method_name) != nil
    is_builtin?(method_name)

  -> is_a_class?(recv, klass)
    w_class = nil
    if type(recv) == "Hash" && recv.has_key?(:rt) && recv[:rt] == :object
      w_class = recv[:w_class]
    else
      # Primitive receiver (Array/String/Integer/…) — not an :object hash,
      # so walk its core-class chain instead of bailing out to false.
      w_class = primitive_runtime_class(recv)
    while w_class != nil
      if w_class == klass || w_class[:name] == klass
        return true
      w_class = w_class[:superclass]
    false
