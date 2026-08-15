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
    # Top-level methods share the same overload rules as class methods, but
    # their legacy name lookup lives in Environment. Keep the complete
    # definition groups here so typed siblings are not collapsed to the last
    # `__method__NAME` binding before a call can inspect its arguments.
    @function_overloads = {}
    @self_stack = [nil]
    @method_stack = [nil]
    @signal = {type: nil, value: nil}
    @loaded_files = []
    @current_file = nil
    @autoload_registry = nil
    @entry_file = nil
    @core_protected = false
    @type_tables_locked = false
    @method_tables_locked = false
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
    # Class currently being defined (for `@@cvar` in class body statements).
    @defining_class = nil
    # `constant_alias "WC"` registrations: alias → namespace
    # ("WC" → "Tungsten:Carbide"). eval_class_ref expands the first
    # segment of a qualified reference through this map.
    @constant_aliases = {}
    # The most recent user-level `raise` value + its message string. The
    # host raise only carries a message; eval_begin re-pairs the caught
    # message with this value so `rescue e` binds the raised OBJECT (an
    # error instance, say) exactly as the compiled engine does. A host
    # (interpreter-internal) raise never matches @raised_message and
    # binds the plain message string as before.
    @raised_value = nil
    @raised_message = nil
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
    names = ["Integer", "Int", "Float", "String", "Boolean", "Bool", "Nil", "Array", "Hash", "Symbol", "Range", "Regex", "Class"]
    i = 0
    while i < names.size()
      name = names[i]
      if !@classes.has_key?(name)
        @classes[name] = {rt: :class, name: name, methods: {}, method_overloads: {}, class_methods: {}, class_method_overloads: {}, parent: nil}
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
      @classes[name] = {rt: :class, name: name, methods: {}, method_overloads: {}, parent: nil}
    true

  -> run(source, file_path = nil)
    if file_path != nil
      @current_file = file_path
      @entry_file = file_path
    ast = parse_source(source)
    prepare_interpreter_contracts(ast, file_path)
    result = execute_program(ast)
    drain_goroutines()
    result

  -> interpreter_contract_name(node)
    if node == nil || !is_ast_node?(node) || ast_kind(node) != :call
      return nil
    recv = ast_get(node, :receiver)
    if recv == nil || !is_ast_node?(recv) || ast_kind(recv) != :class_ref || ast_get(recv, :name) != "Tungsten"
      return nil
    name = ast_get(node, :name)
    if name in ("PROTECT_THE_CORE!" "STOP_THE_PRESS!" "LOCK_THE_DOORS!")
      return name
    nil

  -> interpreter_definition?(node)
    ast_kind(node) in (:class_def :module_def :trait_def :fn_def :method_def)

  -> interpreter_core_file?(path)
    if path == nil
      return false
    text = "" + path
    prefix = core_dir() + "/core/"
    if text.size() >= prefix.size() && text.slice(0, prefix.size()) == prefix
      return true
    root = env("TUNGSTEN_ROOT")
    if root != nil
      prefix = root + "/core/"
      if text.size() >= prefix.size() && text.slice(0, prefix.size()) == prefix
        return true
    text.size() >= 5 && text.slice(0, 5) == "core/"

  -> prepare_interpreter_contracts(program, file_path)
    expressions = ast_get(program, :expressions)
    protect = false
    stop_seen = false
    lock_seen = false
    known_types = {}
    i = 0
    while i < expressions.size()
      node = expressions[i]
      contract = interpreter_contract_name(node)
      if contract != nil
        args = ast_get(node, :args)
        if args == nil || args.size() != 0 || ast_get(node, :block) != nil
          raise "Tungsten." + contract + " takes no arguments or block"
        if contract == "PROTECT_THE_CORE!"
          protect = true
        elsif contract == "STOP_THE_PRESS!"
          stop_seen = true
        else
          stop_seen = true
          lock_seen = true
        ast_set(node, :validated_program_contract, true)
      elsif lock_seen && interpreter_definition?(node)
        raise "method and type definitions must appear before Tungsten.LOCK_THE_DOORS!"
      elsif stop_seen && ast_kind(node) in (:class_def :module_def :trait_def) && known_types[ast_get(node, :name)] != true
        raise "new type definitions must appear before Tungsten.STOP_THE_PRESS!"
      if ast_kind(node) in (:class_def :module_def :trait_def)
        known_types[ast_get(node, :name)] = true
      i += 1

    # Apply Core protection before evaluation so a `use` preceding the marker
    # cannot mutate Core and then retroactively claim the protected contract.
    if protect
      @core_protected = true
      registry = autoload_registry()
      i = 0
      while i < expressions.size()
        node = expressions[i]
        if ast_kind(node) in (:class_def :module_def :trait_def)
          name = ast_get(node, :name)
          if name == "Tungsten" || registry[name] != nil
            raise "Tungsten.PROTECT_THE_CORE! forbids replacing or reopening Core definition '" + name + "'"
        i += 1
    nil

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
    function_overloads_copy = {}
    @function_overloads.keys().each -> (k)
      overloads = @function_overloads[k]
      function_overloads_copy[k] = overloads.copy(0, overloads.size())
    stack_copy = @self_stack.copy(0, @self_stack.size())
    method_stack_copy = @method_stack.copy(0, @method_stack.size())
    files_copy = @loaded_files.copy(0, @loaded_files.size())
    {env: @env, classes: classes_copy, function_overloads: function_overloads_copy, signal_type: @signal[:type], signal_value: @signal[:value], self_stack: stack_copy, method_stack: method_stack_copy, loaded_files: files_copy, current_file: @current_file}

  -> restore_state(snapshot)
    # save_state stores this exact source instance through a Hash boundary;
    # retain the trusted class contract so exact-ivar dispatch can prove the
    # interpreter's hot Environment receiver without changing semantics.
    @env = snapshot[:env] ## Environment
    @classes = snapshot[:classes]
    @function_overloads = snapshot[:function_overloads]
    @signal[:type] = snapshot[:signal_type]
    @signal[:value] = snapshot[:signal_value]
    @self_stack = snapshot[:self_stack]
    @method_stack = snapshot[:method_stack]
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
    source = ccall("w_algebra_rewrite_source", source)
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

  # Expression-local `## type` ascriptions belong to every AST expression,
  # not only assignment RHSes. Keep the main evaluator unaware of the wrapper
  # so all recursive calls still pass through this conversion boundary.
  -> evaluate(node, env)
    value = evaluate_node(node, env)
    return value if node == nil
    hint = ast_get(node, :type_hint)
    # Assignments must coerce before storing (eval_assign owns that boundary),
    # so do not apply their hint a second time on the returned value.
    return value if hint == nil || ast_kind(node) == :assign
    apply_type_hint(value, hint)

  -> evaluate_node(node, env)
    t = ast_kind(node)

    if t == :int
      # A decimal literal above the signed-i64 range wrapped at parse time
      # (parse_int_value's accumulator is compiled native i64), so rebuild it
      # as a BigInt from the original text — the runtime primitive the compiled
      # path uses for the same case (lowering/literals.w).  The parser's AST
      # may itself hold a boxed BigInt for an in-range hex/bin/oct or >i48
      # literal; never return that mutable template directly, because an
      # alias-visible bang method would then change every later evaluation of
      # the source literal.  Reparse its exact decimal value into a fresh
      # ordinary BigInt, mirroring the compiled template-copy contract.
      raw = ast_get(node, :raw)
      if interp_decimal_exceeds_i64?(raw)
        return ccall("w_bigint_from_dec_str", "" + raw.replace("_", ""))
      value = ast_get(node, :value)
      if type(value) == "BigInt"
        return ccall("w_bigint_from_dec_str", value.to_s())
      return value
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
    if t == :uuid
      return ccall("w_uuid_parse", "" + ast_get(node, :value).to_s())
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
    if t == :word_array
      # `%w[a b c]` is already stored on the AST as an Array of String
      # values. Materialize a fresh Array for each evaluation, matching the
      # compiled lower_word_or_symbol_array path instead of exposing the
      # parser's mutable backing array.
      words = ast_get(node, :words)
      result = []
      i = 0
      while i < words.size()
        result.push(words[i])
        i += 1
      return result
    if t == :symbol_array
      # `%i[a b c]` — the spellings are stored as Strings; materialize a
      # fresh Array of Symbols per evaluation, mirroring lower_symbol_array.
      syms = ast_get(node, :symbols)
      result = []
      i = 0
      while i < syms.size()
        result.push(("" + syms[i].to_s()).to_sym())
        i += 1
      return result
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
    if t == :passthrough
      # `expression : value` evaluates the left side for its effects and
      # returns the right side. Storage iterators use this to yield every item
      # while returning self (`$size -> &(self[i]) : self`).
      evaluate(ast_get(node, :expression), env)
      return evaluate(ast_get(node, :value), env)
    if t == :type_ascription
      # evaluate() applies this wrapper's type_hint after the underlying
      # expression has produced its ordinary value.
      return evaluate(ast_get(node, :expression), env)
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
    if t == :fn_def
      return eval_fn_def(node, env)
    if t == :class_def
      return eval_class_def(node, env)
    if t == :trait_def
      return eval_trait_def(node, env)
    if t == :with || t == :parallel_with
      # Tree-walker runs with/parallel_with serially (no real parallel
      # scheduler); same output as lower_with's nested range loops.
      return eval_with(node, env)
    if t == :duration
      return eval_duration(node)
    if t == :cvar
      return eval_cvar(node)
    if t == :block
      # A closure captures the creating frame's `self` so `self`/`@ivar`
      # inside the block body resolve to the enclosing method's receiver —
      # not whatever receiver happens to be on the dispatch stack when the
      # block is invoked (Array#each's own array receiver, for example).
      # Mirrors compiled closures, which capture self as an ordinary value.
      # The capture rides a wrapper Environment so the closure value keeps
      # its established [env, node] pair shape.
      benv = Environment.new(env)
      benv.define("__block_self__", current_self())
      return [benv, node]
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
      err_val = evaluate(ast_get(node, :value), env)
      err_msg = w_to_s(err_val)
      # Keep the raised VALUE so `rescue e` can bind the error object; the
      # host raise below only transports the message string (see eval_begin).
      @raised_value = err_val
      @raised_message = err_msg
      raise err_msg
    if t == :super
      return eval_super(node, env)
    if t == :use
      return eval_use(node)
    if t == :begin
      return eval_begin(node, env)
    if t == :rescue_expr
      return eval_rescue_expr(node, env)
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
      # Bit constant alias: rewrite the first segment (`WC:Route` →
      # `Tungsten:Carbide:Route`) and resolve exactly — mirrors
      # constant_alias_expand on the compiled path.
      expanded = expand_constant_alias(name)
      if expanded != nil
        name = expanded
    # Primitive class stubs make `.class` available before Core loads, but a
    # stub must not suppress the real class when source names it directly.
    # Regex exposed this: the seeded empty class made `Regex.new(pattern)`
    # skip core/regex.w and report that no constructor existed. Autoload is
    # idempotent (`@loaded_files` guards it), so registered classes can always
    # be hydrated here before returning the class object.
    try_autoload_class(name)
    if @classes.has_key?(name)
      return @classes[name]
    hint = foreign_name_hint(name)
    if hint != nil
      raise "Undefined class '[name]' — [hint]"
    raise "Undefined class '[name]'"

  # First-segment constant-alias substitution: "WC:Route" with alias
  # WC → Tungsten:Carbide gives "Tungsten:Carbide:Route". Returns nil
  # for unqualified names and unregistered heads (no suffix matching,
  # no namespace walking).
  -> expand_constant_alias(name)
    if @constant_aliases.size() == 0
      return nil
    c = name.index(":")
    if c == nil
      return nil
    target = @constant_aliases[name.slice(0, c)]
    if target == nil
      return nil
    target + name.slice(c, name.size() - c)

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
    cls = {rt: :class, name: "Class", methods: {}, method_overloads: {}, class_methods: {}, class_method_overloads: {}, parent: nil}
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
        result = call_block1([env, func], elem)
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
              acc0 = acc0 + call_block1([env, mfunc], arr0[i0])
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
      return call_block1(block, elem)
    if args != nil && args.size() >= 1
      # A closure argument is the iteratee itself (paren-lambda spelling);
      # anything else is a method name to send (symbol-to-proc).
      cand = args[0]
      if type(cand) == "Array" && cand.size() == 2 && is_ast_node?(cand[1]) && ast_kind(cand[1]) == :block
        return call_block1(cand, elem)
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
    if t == "Int"
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
          m = lookup_method(obj_class, "to_s", 0)
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

  # Semantic, fail-closed label for REPL inspection.  Interpreted instances
  # are host Hashes internally, but `? value` must never expose that storage.
  # Prefer the object's zero-argument `inspect`, then `to_s`; a broken user
  # formatter falls through to a stable logical class label.
  -> w_try_inspection_formatter(value, name)
    method = lookup_method(value[:w_class], name, 0)
    if method == nil
      return nil
    begin
      rendered = call_w_method(value, method, [], nil, @env)
      return rendered if type(rendered) == "String"
    rescue error
      # Inspection is diagnostic. A faulty formatter must not make the object
      # uninspectable or reveal its interpreter representation.
      return nil
    nil

  -> w_inspection_label(value)
    if type(value) == "Hash" && value.has_key?(:rt) && value[:rt] == :object
      rendered = w_try_inspection_formatter(value, "inspect")
      return rendered if rendered != nil
      rendered = w_try_inspection_formatter(value, "to_s")
      return rendered if rendered != nil
      return "#<" + value[:w_class][:name].to_s() + ">"
    w_inspect(value)

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

  -> builtin_math_constant(name)
    case name
    when "π"
      return ~3.141592653589793
    when "τ"
      return ~6.283185307179586
    when "ϕ", "φ"
      return ~1.618033988749895
    when "ℯ"
      return ~2.718281828459045
    when "ℇ"
      return ~0.5772156649015329
    nil

  -> eval_var(node, env, symbolic = false)
    name = ast_get(node, :name)
    if name == "ARGV"
      # Script-scoped args (the run driver strips `run <script> --`), NOT
      # the bare argv() builtin — that one sees the compiler binary's own
      # process argv and leaked `run|<script>|--|...` into programs.
      return @argv.copy(0, @argv.size())
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
    # Locals and parameters win, but stop at the current method frame. A
    # module binding lives beyond that barrier and must not capture a declared
    # zero-arg method on self with the same name.
    if env.defined_locally_or_in_scope?(name)
      return env.get(name)
    mathematical_constant = self.builtin_math_constant(name)
    return mathematical_constant if mathematical_constant != nil
    # File is a compiler intrinsic rather than an autoload-registry entry.
    # Its Mmap constructor needs the small core/mmap facade in the tree walker;
    # loading the registered Mmap name defines both classes from that file.
    if name == "File" && !@classes.has_key?("Mmap")
      try_autoload_class("Mmap")
    if !@classes.has_key?(name)
      try_autoload_class(name)
    if @classes.has_key?(name)
      return @classes[name]
    # Bit constant alias: an all-caps head lexes as a constant, so
    # `WC:Migration` arrives here as a :var rather than a :class_ref.
    # Same first-segment substitution as eval_class_ref.
    expanded = expand_constant_alias(name)
    if expanded != nil && @classes.has_key?(expanded)
      return @classes[expanded]
    # Match compiled lowering: a declared instance method is lexical to the
    # receiver and wins over a same-spelled module binding. This check must
    # precede @env below because method-frame Environment reads deliberately
    # reach through their write barrier to top-level bindings.
    s = current_self()
    m = implicit_self_method(s, name, 0, false)
    if m != nil
      return call_w_method(s, m, [], nil, env)
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
    if symbolic
      # `2 * x` multiplication operand: an undefined bare name becomes a
      # 1·name unit factor, mirroring the `2x` juxtaposition (and the
      # compiled lowering's :STAR rewrite).
      return ccall("w_quantity_parse", "1", "" + name.to_s())
    hint = foreign_name_hint(name)
    if hint != nil
      raise_typed("NameError", "Undefined variable or method '[name]' — [hint]")
    raise_typed("NameError", "Undefined variable or method '[name]'")

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
      when "asin"
        return ccall("w_math_asin", x)
      when "acos"
        return ccall("w_math_acos", x)
      when "atan"
        return ccall("w_math_atan", x)
      when "cbrt"
        return ccall("w_math_cbrt", x)
      when "exp"
        return ccall("w_math_exp", x)
      when "log"
        return ccall("w_math_log", x)
      when "expm1"
        return ccall("w_math_expm1", x)
      when "log1p"
        return ccall("w_math_log1p", x)
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
      when "hypot"
        return ccall("w_math_hypot", args[0], args[1])
      when "ldexp"
        return ccall("w_math_ldexp", args[0], args[1])
    nil
