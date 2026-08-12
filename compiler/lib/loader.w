use lexer
use parser

+ Loader
  -> new(@verbose = false)
    @loaded_files = []
    @manifest_files = []
    @cacheable = false
    @runtime_id = nil
    @service_bindings = parse_service_bindings(env("TUNGSTEN_SERVICE_BINDINGS"))
    @service_bindings_id = canonical_service_bindings(@service_bindings)
    @autoload_registry = nil
    @autoload_loaded = {}
    @manifest_poisoned = false
    @manifest_wanted = false

  # Parse the shell-wrapper-exported TUNGSTEN_SERVICE_BINDINGS env var.
  # Format: "name1=bit1,name2=bit2". Missing/empty → empty hash.
  # e.g. "json=tungsten-json,yaml=tungsten-yaml" →
  #   {"json" => "tungsten-json", "yaml" => "tungsten-yaml"}
  -> parse_service_bindings(raw)
    bindings = {}
    if raw == nil || raw == ""
      return bindings
    pairs = raw.split(",")
    i = 0
    while i < pairs.size()
      pair = pairs[i]
      eq_idx = pair.index("=")
      if eq_idx != nil
        key = pair.slice(0, eq_idx)
        val = pair.slice(eq_idx + 1, pair.size() - eq_idx - 1)
        if key != "" && val != ""
          bindings[key] = val
      i += 1
    bindings

  -> canonical_service_bindings(bindings)
    # Sorted deliberately (NOT an iteration-order workaround): the env
    # string's pair order is caller-controlled, and the canonical form
    # must be identical regardless of how the pairs were written.
    keys = bindings.keys().sort()
    parts = []
    i = 0
    while i < keys.size()
      key = keys[i]
      parts.push(key + "=" + bindings[key])
      i += 1
    parts.join(",")

  -> load_program_ast(path, from_file = nil)
    resolved = resolve_path(path, from_file)

    if from_file == nil
      @loaded_files = []
      @manifest_files = []
      @runtime_id = runtime_identity()
      @cacheable = @runtime_id.starts_with?("ruby ")
      # Manifest recording engages for the ruby AST cache AND the compiled
      # driver's incremental binary cache. The C VM stage-0 lacks the bare
      # file_mtime_ns builtin, so it must not attempt to record at all.
      @manifest_wanted = @cacheable || @runtime_id == "compiled-runtime"

      cached = read_ast_cache(resolved)
      if cached != nil
        return cached

    if @loaded_files.include?(resolved)
      return Tungsten:AST:Program.new([])

    @loaded_files.push(resolved)
    record_manifest_file(resolved)
    if @verbose && env("DEBUG_LOADS") == "1"
      << "  load " + display_path(resolved)

    source = read_file(resolved)
    if source == nil
      raise compile_error(:E_LOAD_MISSING_FILE, "Could not load '" + path + "' (resolved to '" + resolved + "')", from_file, 1, 1)
    source = ccall("w_algebra_rewrite_source", source)
    lexer = Lexer.new(source, resolved)
    token_count = lexer.tokenize()
    parser = Parser.new(token_count, lexer.packed_tokens, source, lexer.values, lexer.line_at, lexer.col_at, lexer.file).set_chars(lexer.chars)
    ast = parser.parse()

    expressions = []
    i = 0
    while i < ast.expressions.size()
      expr = ast.expressions[i]
      if ast_kind(expr) == :use
        imported = load_program_ast(expr.path, resolved)
        imported.expressions.each -> (imported_expr)
          expressions.push(imported_expr)
      else
        expressions.push(expr)
      i += 1

    ast = Tungsten:AST:Program.new(expressions)
    if from_file == nil
      # BigInt comparison and bitwise arithmetic are runtime support, not
      # demand-loaded class methods. Integer values can enter through opaque
      # native boundaries and runtime-internal callers without any BigInt name
      # or relevant syntax in the source AST. Always prepend the small native
      # support modules so every production binary supplies their strong
      # source seams; the runtime's weak C bodies remain only stage0/bootstrap
      # defaults and differential oracles. Loading these modules through the
      # normal path also records and deduplicates them.
      compare_support = load_program_ast("core/numeric/big_int_compare", resolved)
      bitwise_support = load_program_ast("core/numeric/big_int_bitwise", resolved)
      has_compare_support = compare_support != nil && compare_support.expressions.size() > 0
      has_bitwise_support = bitwise_support != nil && bitwise_support.expressions.size() > 0
      if has_compare_support || has_bitwise_support
        with_support = []
        if compare_support != nil
          compare_support.expressions.each -> (support_expr)
            with_support.push(support_expr)
        if bitwise_support != nil
          bitwise_support.expressions.each -> (support_expr)
            with_support.push(support_expr)
        expressions.each -> (program_expr)
          with_support.push(program_expr)
        expressions = with_support
        ast = Tungsten:AST:Program.new(expressions)
      ast = autoload_pass(ast, resolved)
      write_ast_cache(resolved, ast)
    ast

  # Lazy iterative autoload. After the entry-file's recursive `:use` walk
  # produces `ast`, scan for unresolved class/trait references whose names
  # appear in core/tungsten.w's `auto :Name, "path"` registry. Load each
  # missing file once, append its expressions, and rescan — newly-loaded
  # files often introduce further references (e.g. core/array.w → Enumerable).
  -> autoload_pass(ast, base_resolved, fast_loaded = nil)
    # TUNGSTEN_C_FAST_PARSE bootstrap: the C fast-loader inlines the whole
    # use-graph itself, bypassing load_program_ast's bookkeeping, then
    # re-enters here. It hands the inlined file list over so this pass
    # doesn't re-load a module the flatten already included — a re-load
    # duplicates every definition in it (e.g. `use core/numeric/big_int`
    # at the compiler's top produced duplicate __bigint_* fns).
    if fast_loaded != nil
      @loaded_files = []
      fli = 0
      while fli < fast_loaded.size()
        @loaded_files.push(fast_loaded[fli])
        fli += 1
    registry = autoload_registry(base_resolved)
    if registry == nil
      return ast
    @autoload_loaded = {}
    # Working copy, not an alias — `ast.expressions` is immutable once
    # frozen into the Program's slot, but this loop accumulates newly
    # autoloaded files into `expressions` across up to 64 iterations.
    # The function builds a fresh Program from `reordered` at the end
    # regardless, so `ast` itself is never written back to.
    expressions = []
    ast.expressions.each -> (e)
      expressions.push(e)
    user_count = expressions.size()
    # [start, count] per autoloaded file so the final reorder can reverse
    # at file granularity (see below).
    blocks = []
    iteration = 0
    # Deep autoload walk watermark: each iteration only recurses into
    # expressions appended since the last one. Re-walking already-scanned
    # expressions is pure waste — any autoload name they reference was either
    # collected in an earlier iteration (and is now loaded or marked in
    # @autoload_loaded, so consider_autoload_name filters it) or was never in
    # the registry. New pending names can only come from newly-loaded files.
    # The lighter whole-program passes (collect_defined_names, the array-
    # necessity analysis inside collect_unresolved_autoload_names) still see
    # everything. This turns the fixpoint from O(iterations x total AST) into
    # a single pass over each expression — the autoload walker was the hottest
    # function in a compile.
    walked = 0
    while iteration < 64
      defined = collect_defined_names(expressions)
      pending = collect_unresolved_autoload_names(expressions, walked, defined, registry)
      walked = expressions.size()
      if pending.size() == 0
        break
      pi = 0
      while pi < pending.size()
        name = pending[pi]
        if @autoload_loaded[name] != true
          @autoload_loaded[name] = true
          path = registry[name]
          # Tolerant load: if the autoloaded file has a parse error or other
          # compile-time failure, swallow it and skip this name. Several core
          # `.w` files (notably core/object.w with `-> !~/1` and `-> ARGF`
          # stubs the lexer doesn't yet accept) are still scaffolds — they
          # only matter once their methods are actually used. A user program
          # that *needs* them will fail at lowering time with a clear "no
          # such class" or "no such trait" error rather than crashing the
          # loader for every other compilation. `core/tungsten.w`'s registry
          # remains the source of truth for what *can* be autoloaded; this
          # block decides what *currently can be* loaded.
          loaded = nil
          begin
            loaded = load_program_ast("core/" + path, base_resolved)
          rescue err
            if @verbose && env("DEBUG_LOADS") == "1"
              << "  autoload skip " + name + " (parse error in core/" + path + ")"
            loaded = nil
          if loaded != nil
            block_start = expressions.size()
            li = 0
            while li < loaded.expressions.size()
              expressions.push(loaded.expressions[li])
              li += 1
            blocks.push([block_start, loaded.expressions.size()])
        pi += 1
      iteration += 1
    # Reorder so autoloaded class defs come before user code that inherits
    # from them: `+ Foo < Object` would otherwise reference @class.Object
    # before Object's class_new ran. Autoload pulls in top-down order
    # (user-referenced first, then their deps), so the deepest dependency
    # was loaded LAST — reversing the autoloaded tail puts roots first,
    # which is what class creation needs. The reverse is at FILE-BLOCK
    # granularity: each autoloaded file keeps its own declaration order
    # (an orchestrator like core/dynamics.w splices `use`d workers with
    # parents before children — an expression-level reverse would run
    # child class_new before its parent and leave a nil superclass).
    reordered = []
    bi = blocks.size() - 1
    while bi >= 0
      bstart = blocks[bi][0]
      bcount = blocks[bi][1]
      k = 0
      while k < bcount
        reordered.push(expressions[bstart + k])
        k += 1
      bi -= 1
    ui = 0
    while ui < user_count
      reordered.push(expressions[ui])
      ui += 1
    Tungsten:AST:Program.new(reordered)

  -> autoload_registry(base_resolved)
    if @autoload_registry != nil
      return @autoload_registry
    parts = base_resolved.split("/")
    parts.pop()
    base_dir = parts.join("/")
    project_root = find_core_root(base_dir)
    if project_root == ""
      return nil
    registry_path = project_root + "/core/tungsten.w"
    if !file?(registry_path)
      return nil
    if @loaded_files.include?(registry_path)
      # Caller already loaded it — registry already merged inline, skip.
      @autoload_registry = {}
      return @autoload_registry
    source = read_file(registry_path)
    if source == nil
      return nil
    lexer = Lexer.new(source, registry_path)
    token_count = lexer.tokenize()
    parser = Parser.new(token_count, lexer.packed_tokens, source, lexer.values, lexer.line_at, lexer.col_at, lexer.file).set_chars(lexer.chars)
    parsed = parser.parse()
    registry = {}
    extract_autoload_entries(parsed.expressions, registry)
    @autoload_registry = registry
    record_manifest_file(registry_path)
    registry

  -> extract_autoload_entries(exprs, registry)
    i = 0
    while i < exprs.size()
      e = exprs[i]
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

  -> collect_defined_names(exprs)
    defined = {}
    i = 0
    while i < exprs.size()
      e = exprs[i]
      if ast_kind(e) == :class_def && e.name != nil
        defined[e.name] = true
      elsif ast_kind(e) == :trait_def && e.name != nil
        defined[e.name] = true
      i += 1
    defined

  -> collect_unresolved_autoload_names(exprs, start, defined, registry)
    # Decide whether an array literal should pull in the Array class. The
    # literal alone needs Array only for class/Enumerable methods the runtime
    # WArray and the compiler's inline-iterator lowering don't cover (uniq,
    # zip, flatten, sort, +, <<, ==, …). A program that builds an array and
    # only ever drives it with inlined scalar iterators (any?/all?/none?/
    # count/find/detect) needs none of that — autoloading Array there drags
    # the whole Enumerable/Array/Hash tower (w_add / w_closure_new method
    # bodies) into a program that never calls them. `array_class_needed?` is
    # SOUND-by-overapproximation: it returns false ONLY when every array
    # literal is provably used in that inlined-iterator-only shape, and true
    # for anything it can't prove (unknown node, escape, non-safe method).
    @array_needed = array_class_needed?(exprs)
    # Preserve simple String provenance across the pre-lowering autoload
    # pass. `text = ""; text.empty?` used to miss String's source method
    # because string_empty_receiver? could recognize only the literal node,
    # not the variable that held it. Any second/non-string assignment drops
    # the proof; a conservative extra autoload is preferable to an undefined
    # method at runtime.
    @string_literal_vars = {}
    string_other_assign = {}
    collect_string_literal_vars_list(exprs, @string_literal_vars, string_other_assign)
    string_names = @string_literal_vars.keys()
    sni = 0
    while sni < string_names.size()
      if string_other_assign[string_names[sni]] == true
        @string_literal_vars[string_names[sni]] = nil
      sni += 1
    # Source-defined Array methods have no runtime fallback, and an Array can
    # enter through argv/a parameter without any literal or class reference.
    # Scan call names only until the first such method schedules Array. Later
    # autoload iterations see Array in @autoload_loaded and skip the guard.
    @array_source_method_unresolved = defined["Array"] != true && registry["Array"] != nil && @autoload_loaded["Array"] != true
    # Source-defined Float leaves have no runtime fallback. A Float can arrive
    # through a parameter or native call without a literal or class reference,
    # so schedule its class on the first matching method name.
    @float_source_method_unresolved = defined["Float"] != true && registry["Float"] != nil && @autoload_loaded["Float"] != true
    # Decimal's portable source leaves (normalization, reciprocal, and the
    # transcendental facade) likewise need the class even when a packed or
    # heap Decimal crosses an untyped boundary. Its primitive conversions and
    # rounding methods remain native IC rows and do not need this trigger.
    @decimal_source_method_unresolved = defined["Decimal"] != true && registry["Decimal"] != nil && @autoload_loaded["Decimal"] != true
    # BigInt#to_i is likewise source-defined identity and a heap BigInt can
    # cross a parameter/native boundary without a literal in this AST.
    @bigint_to_i_unresolved = defined["BigInt"] != true && registry["BigInt"] != nil && @autoload_loaded["BigInt"] != true
    # BigInts also cross literal, promotion, parameter, and native boundaries
    # without a reliable receiver-class node. Their five representation-only
    # predicates and in-place sign operations now live in source, so schedule
    # BigInt on the first matching spelling and collapse the guard for the
    # remainder of this walk/pass.
    @bigint_predicates_unresolved = defined["BigInt"] != true && registry["BigInt"] != nil && @autoload_loaded["BigInt"] != true
    # String and Symbol share runtime dispatch key 0xF9 and may arrive through
    # parameters, native calls, or rope-producing expressions. Once both
    # native length aliases are removed, a one-shot name gate is the sound
    # registration boundary for their deliberately tiny source facade.
    @string_length_unresolved = defined["String"] != true && registry["String"] != nil && @autoload_loaded["String"] != true
    # Opaque synchronization handles have no reliable receiver-class evidence
    # in the AST. Only the four bounded source leaves participate; ubiquitous
    # or hard-fatal native selectors deliberately keep their IC fallback.
    @atomic_source_method_unresolved = defined["Atomic"] != true && registry["Atomic"] != nil && @autoload_loaded["Atomic"] != true
    @channel_source_method_unresolved = defined["Channel"] != true && registry["Channel"] != nil && @autoload_loaded["Channel"] != true
    @thread_source_method_unresolved = defined["Thread"] != true && registry["Thread"] != nil && @autoload_loaded["Thread"] != true
    # Keep Mmap call-name triggers separate. size is common but already retained
    # under its deliberately tiny facade. The typed-view names are narrow
    # enough to cover unknown native/parameter boundaries without the unsound
    # provenance assumptions that `[]` or `close` would require.
    @mmap_size_unresolved = defined["Mmap"] != true && registry["Mmap"] != nil && @autoload_loaded["Mmap"] != true
    mmap_missing = defined["Mmap"] != true && registry["Mmap"] != nil && @autoload_loaded["Mmap"] != true
    big_array_missing = defined["BigArray"] != true && registry["BigArray"] != nil && @autoload_loaded["BigArray"] != true
    @mmap_typed_view_unresolved = mmap_missing || big_array_missing
    seen = {}
    pending = []
    i = start
    while i < exprs.size()
      collect_autoload_refs(exprs[i], defined, registry, seen, pending)
      i += 1
    pending

  # --- Array-autoload necessity analysis (see collect_unresolved_autoload_names) ---

  # Scalar/element-returning iterators the compiler inlines for a plain array
  # without consulting the Array class. Verified: each result is bool/int/an
  # element — never a fresh array — so the result can't transitively need the
  # class. `each` is excluded (it returns the array itself).
  -> arr_safe_iter?(name)
    name in ("any?" "all?" "none?" "count" "find" "detect")

  -> array_class_needed?(exprs)
    arr_vars = {}
    other_assign = {}
    collect_arr_literal_vars_list(exprs, arr_vars, other_assign)
    # A var assigned anything besides a scalar-element array literal is not a
    # clean array binding — drop it so its uses fall to the conservative path.
    names = arr_vars.keys()
    ni = 0
    while ni < names.size()
      if other_assign[names[ni]] == true
        arr_vars[names[ni]] = nil
      ni += 1
    st = {needed: false}
    scan_arr_safety_list(exprs, arr_vars, st)
    st[:needed]

  # True iff every element of an array literal is a scalar literal (so the
  # array is a flat int/string/… array, never an array-of-arrays whose
  # element results could themselves need the class).
  -> arr_literal_all_scalar?(node)
    els = node.elements
    if els == nil
      return true
    i = 0
    while i < els.size()
      e = els[i]
      if !is_ast_node?(e)
        return false
      if ast_kind(e) in (:int :float :string :bool :char :symbol :nil :decimal)
        nil
      else
        return false
      i += 1
    true

  -> collect_arr_literal_vars_list(nodes, arr_vars, other_assign)
    if nodes == nil
      return nil
    # A "list" field is not always a list: rescue_expr.body (postfix
    # `rescue`) holds a single packed node, and .size() on an AST node is
    # nil — `i < nil` raises in the compiled compiler. Route single nodes
    # through the node walker (which forwards real arrays back here),
    # mirroring the puts/value convention in scan_arr_safety_node.
    if is_ast_node?(nodes)
      collect_arr_literal_vars_node(nodes, arr_vars, other_assign)
      return nil
    i = 0
    while i < nodes.size()
      collect_arr_literal_vars_node(nodes[i], arr_vars, other_assign)
      i += 1

  -> collect_arr_literal_vars_node(node, arr_vars, other_assign)
    if !is_ast_node?(node)
      if type(node) == "Array"
        collect_arr_literal_vars_list(node, arr_vars, other_assign)
      return nil
    t = ast_kind(node)
    # @fastmath / @strictmath / Math.promote blocks are plain hash nodes that
    # answer only subscript access, not the method-style `.body` the recursion
    # below uses (calling `.body` on the hash raises). Recurse via subscript.
    if t in (:fastmath_block :strictmath_block :overflow_block)
      collect_arr_literal_vars_list(node[:body], arr_vars, other_assign)
      return nil
    if t == :assign && node.target != nil && ast_kind(node.target) == :var
      v = node.value
      if v != nil && is_ast_node?(v) && ast_kind(v) == :array && arr_literal_all_scalar?(v)
        arr_vars[node.target.name] = true
      else
        other_assign[node.target.name] = true
    if t == :compound_assign && node.target != nil && ast_kind(node.target) == :var
      other_assign[node.target.name] = true
    # Recurse into bodies/children to find nested assignments.
    collect_arr_literal_vars_list(node.body, arr_vars, other_assign)
    collect_arr_literal_vars_list(node.then_body, arr_vars, other_assign)
    collect_arr_literal_vars_list(node.else_body, arr_vars, other_assign)
    collect_arr_literal_vars_list(node.expressions, arr_vars, other_assign)
    if node.value != nil && is_ast_node?(node.value)
      collect_arr_literal_vars_node(node.value, arr_vars, other_assign)
    nil

  -> collect_string_literal_vars_list(nodes, string_vars, other_assign)
    if nodes == nil
      return nil
    if is_ast_node?(nodes)
      collect_string_literal_vars_node(nodes, string_vars, other_assign)
      return nil
    i = 0
    while i < nodes.size()
      collect_string_literal_vars_node(nodes[i], string_vars, other_assign)
      i += 1

  -> collect_string_literal_vars_node(node, string_vars, other_assign)
    if !is_ast_node?(node)
      if type(node) == "Array"
        collect_string_literal_vars_list(node, string_vars, other_assign)
      return nil
    t = ast_kind(node)
    if t in (:fastmath_block :strictmath_block :overflow_block)
      collect_string_literal_vars_list(node[:body], string_vars, other_assign)
      return nil
    if t == :assign && node.target != nil && ast_kind(node.target) == :var
      value = node.value
      if value != nil && is_ast_node?(value) && ast_kind(value) in (:string :string_interp)
        string_vars[node.target.name] = true
      else
        other_assign[node.target.name] = true
    if t == :compound_assign && node.target != nil && ast_kind(node.target) == :var
      other_assign[node.target.name] = true
    collect_string_literal_vars_list(node.body, string_vars, other_assign)
    collect_string_literal_vars_list(node.then_body, string_vars, other_assign)
    collect_string_literal_vars_list(node.else_body, string_vars, other_assign)
    collect_string_literal_vars_list(node.expressions, string_vars, other_assign)
    if node.value != nil && is_ast_node?(node.value)
      collect_string_literal_vars_node(node.value, string_vars, other_assign)
    nil

  -> scan_arr_safety_list(nodes, arr_vars, st)
    if nodes == nil
      return nil
    if st[:needed] == true
      return nil
    i = 0
    while i < nodes.size()
      scan_arr_safety_node(nodes[i], arr_vars, st)
      i += 1

  -> scan_arr_safety_node(node, arr_vars, st)
    if st[:needed] == true
      return nil
    if node == nil
      return nil
    if !is_ast_node?(node)
      if type(node) == "Array"
        scan_arr_safety_list(node, arr_vars, st)
      return nil
    t = ast_kind(node)
    case t
    when :int, :float, :string, :bool, :nil, :symbol, :char, :decimal
      return nil
    when :var
      # An array-var reaching here is NOT a safe-iterator receiver (those are
      # consumed in the :call arm) — treat it as an escape that may need the class.
      if arr_vars[node.name] == true
        st[:needed] = true
      return nil
    when :array
      # An array literal anywhere except a tracked `V = [scalars]` assignment
      # (handled in :assign) is an unproven use.
      st[:needed] = true
      return nil
    when :program
      scan_arr_safety_list(node.expressions, arr_vars, st)
      return nil
    when :assign
      tgt = node.target
      val = node.value
      if tgt != nil && ast_kind(tgt) == :var && arr_vars[tgt.name] == true && val != nil && is_ast_node?(val) && ast_kind(val) == :array
        # The tracking assignment: literal is all-scalar (proven at collect
        # time), so nothing to flag.
        return nil
      scan_arr_safety_node(tgt, arr_vars, st)
      scan_arr_safety_node(val, arr_vars, st)
      return nil
    when :compound_assign
      scan_arr_safety_node(node.target, arr_vars, st)
      scan_arr_safety_node(node.value, arr_vars, st)
      return nil
    when :call
      recv = node.receiver
      recv_is_arr_var = recv != nil && is_ast_node?(recv) && ast_kind(recv) == :var && arr_vars[recv.name] == true
      if recv_is_arr_var && arr_safe_iter?(node.name)
        # Safe inlined iterator on a tracked array — scan args/block only.
        scan_arr_safety_list(node.args, arr_vars, st)
        scan_arr_safety_node(node.block, arr_vars, st)
        return nil
      scan_arr_safety_node(recv, arr_vars, st)
      scan_arr_safety_list(node.args, arr_vars, st)
      scan_arr_safety_node(node.block, arr_vars, st)
      return nil
    when :binary_op, :and, :or
      scan_arr_safety_node(node.left, arr_vars, st)
      scan_arr_safety_node(node.right, arr_vars, st)
      return nil
    when :unary_op, :not
      scan_arr_safety_node(node.operand, arr_vars, st)
      return nil
    when :fn_def, :method_def
      scan_arr_safety_list(node.params, arr_vars, st)
      scan_arr_safety_list(node.body, arr_vars, st)
      return nil
    when :param
      scan_arr_safety_node(node.default, arr_vars, st)
      return nil
    when :block
      scan_arr_safety_list(node.body, arr_vars, st)
      return nil
    when :puts
      # puts.value may be a single print-arg node or a list of them; the
      # node dispatcher handles both (it forwards arrays to the list walker).
      scan_arr_safety_node(node.value, arr_vars, st)
      return nil
    when :return, :print
      scan_arr_safety_node(node.value, arr_vars, st)
      return nil
    else
      # Unknown / not-modeled node — conservatively assume Array may be needed.
      st[:needed] = true
      return nil

  -> collect_autoload_refs(node, defined, registry, seen, pending)
    if !is_ast_node?(node) || ast_kind(node) == nil
      return nil
    t = ast_kind(node)
    # @fastmath / @strictmath scoped blocks are plain hash nodes
    # ({node:, body:}) that only live until lowering. Recurse into the body
    # via subscript (hash nodes don't answer the method-style `.args` /
    # `.body` accessors the generic field-probe below uses — calling `.args`
    # on the hash raises) so class refs inside the block still autoload.
    if t in (:fastmath_block :strictmath_block :overflow_block)
      mblock_body = node[:body]
      if mblock_body != nil
        mbi = 0
        while mbi < mblock_body.size()
          collect_autoload_refs(mblock_body[mbi], defined, registry, seen, pending)
          mbi += 1
      return nil
    if t == :trait_include && node.name != nil
      consider_autoload_name(node.name, defined, registry, seen, pending)
    if t == :class_def
      # `+ Name` is a reopen when Name is supplied by core. Load the core
      # definition before the user's body even though collect_defined_names
      # has already seen this declaration; otherwise the partial user class
      # suppresses autoload and replaces the primitive dispatch surface.
      consider_autoload_name(node.name, defined, registry, seen, pending, true)
      if node.superclass != nil
        consider_autoload_name(node.superclass, defined, registry, seen, pending)
      if node.body != nil
        bj = 0
        while bj < node.body.size()
          collect_autoload_refs(node.body[bj], defined, registry, seen, pending)
          bj += 1
    # Keep every call-specific autoload trigger in one arm. This walker visits
    # the complete AST, so repeatedly fetching `receiver`/`name` in separate
    # `t == :call` conditions is measurable on a self-host compile.
    if t == :call
      call_receiver = node.receiver
      call_name = node.name

      # Const/class-name receivers: `Array.new(...)` and
      # `ByteArray.from_array(...)` reach a class via a var receiver. A broken
      # core stub is handled by the tolerant-load block above.
      if call_receiver != nil && ast_kind(call_receiver) == :var
        consider_autoload_name(call_receiver.name, defined, registry, seen, pending)
      # ClassRef receiver — always a class reference.
      if call_receiver != nil && ast_kind(call_receiver) == :class_ref
        consider_autoload_name(call_receiver.name, defined, registry, seen, pending)

      # File's other operations stay compiler intrinsics and should not pull in
      # its full source facade. Mmap#size uniquely needs the Mmap type class,
      # which lives in core/mmap.w and is registered under Mmap itself.
      if call_receiver != nil && ast_kind(call_receiver) in (:var :class_ref) && call_receiver.name == "File" && call_name == "mmap"
        consider_autoload_name("Mmap", defined, registry, seen, pending)

      # A direct ccall can construct a value whose runtime type is visible only
      # after the call. Keep this scoped to exact known value-producing names.
      if call_receiver == nil && call_name in ("ccall" "ccall_rawargs") && node.args != nil && node.args.size() > 0
        target = node.args[0]
        if target != nil && ast_kind(target) == :string
          result_class = native_ccall_result_class(target.value)
          if result_class != nil
            consider_autoload_name(result_class, defined, registry, seen, pending)

      # argv() returns the process Array without a literal or class reference.
      if call_receiver == nil && call_name == "argv"
        consider_autoload_name("Array", defined, registry, seen, pending)

      # StringBuffer(...) is a compiler-recognized bare constructor rather
      # than a class receiver call, so its spelling is the only source-level
      # class reference. Its methods now include a source-defined size.
      if call_receiver == nil && call_name == "StringBuffer"
        consider_autoload_name("StringBuffer", defined, registry, seen, pending)

      # String#empty? lives in the native source class. Load it only for a
      # receiver expression proven String/Symbol-producing.
      if call_name == "empty?" && string_empty_receiver?(call_receiver)
        consider_autoload_name("String", defined, registry, seen, pending)

      # String/Symbol#to_s now lives in the shared 0xF9 native source class.
      # Name-gating covers dynamic receivers; loading this tiny class does not
      # interfere with other built-in or user-defined to_s implementations.
      if call_name == "to_s" && (node.args == nil || node.args.size() == 0)
        consider_autoload_name("String", defined, registry, seen, pending)

      if @string_length_unresolved
        # size/length and the source-defined transforms (swapcase/capitalize/
        # reverse) all just need String's tiny facade scheduled once. Gating
        # them behind this latch — false from the start whenever String is
        # already loaded, which is nearly always — keeps the per-call-node
        # autoload walk from re-testing these names on every compile after
        # String is in. reverse also names an Array method; over-scheduling
        # String on an array.reverse is harmless (matches the prior
        # unconditional behavior) and only happens while String is unresolved.
        if call_name in ("size" "length" "swapcase" "capitalize" "reverse" "chars" "bytes" "upcase" "downcase" "lpad" "rpad" "center" "delete" "squeeze" "tr")
          consider_autoload_name("String", defined, registry, seen, pending)
          @string_length_unresolved = false
        # Lowering synthesizes a per-element call for these Symbol-to-proc
        # forms after this source-AST walk. Mirror that exact domain here so
        # :size/:length cannot bypass String registration.
        elsif call_name in ("map" "select" "reject" "count") && node.block == nil && call_receiver != nil && node.args != nil && node.args.size() == 1
          iteratee = node.args[0]
          if iteratee != nil && is_ast_node?(iteratee) && ast_kind(iteratee) == :symbol && iteratee.value in ("size" "length") && ast_kind(call_receiver) in (:range :array :var :call :map :calc)
            consider_autoload_name("String", defined, registry, seen, pending)
            @string_length_unresolved = false

      if @atomic_source_method_unresolved && call_name in ("increment" "decrement")
        consider_autoload_name("Atomic", defined, registry, seen, pending)
        @atomic_source_method_unresolved = false
      if @channel_source_method_unresolved && call_name == "recv"
        consider_autoload_name("Channel", defined, registry, seen, pending)
        @channel_source_method_unresolved = false
      if @thread_source_method_unresolved && call_name == "alive?"
        consider_autoload_name("Thread", defined, registry, seen, pending)
        @thread_source_method_unresolved = false

      # These methods are source-defined after removal of their runtime ICs.
      # Arrays can arrive through argv, a parameter, or a native factory, so
      # no receiver-shape test can soundly cover every use.
      if @array_source_method_unresolved && call_name in ("join" "compact" "dup" "take" "drop" "reverse" "uniq" "minmax" "copy" "delete_at" "flatten")
        consider_autoload_name("Array", defined, registry, seen, pending)
        @array_source_method_unresolved = false

      if @float_source_method_unresolved && call_name in ("to_f" "abs" "nan?" "infinite?" "finite?" "sqrt" "ceil" "floor" "round" "sq" "truncate")
        consider_autoload_name("Float", defined, registry, seen, pending)
        @float_source_method_unresolved = false

      if @decimal_source_method_unresolved && call_receiver != nil && call_name in ("to_s" "normalize" "reciprocal" "inv" "sin" "cos" "tan" "arcsin" "arccos" "arctan" "sinh" "cosh" "tanh" "arcsinh" "arccosh" "arctanh")
        consider_autoload_name("Decimal", defined, registry, seen, pending)
        @decimal_source_method_unresolved = false

      if @mmap_size_unresolved && call_name == "size"
        consider_autoload_name("Mmap", defined, registry, seen, pending)
        @mmap_size_unresolved = false

      if @mmap_typed_view_unresolved && call_name in ("as_u8" "as_u16" "as_u32" "as_u64" "as_i8" "as_i16" "as_i32" "as_i64" "as_f32" "as_f64")
        consider_autoload_name("Mmap", defined, registry, seen, pending)
        consider_autoload_name("BigArray", defined, registry, seen, pending)
        @mmap_typed_view_unresolved = false

      # Integer/Number leaf methods commonly receive literals or locals, which
      # carry no explicit class reference. The to_i spelling is shared with
      # source-only BigInt identity, so schedule that tiny class once as well.
      # The bitwise/divmod spellings require an explicit receiver: a
      # receiverless call named "&" is BLOCK INVOCATION `&(args)` — gating
      # on it would autoload Integer/BigInt into every block-using program
      # (including the compiler itself, which broke stage identity).
      bitwise_op_send = call_receiver != nil && call_name in ("&" "|" "^" "/" "%")
      if bitwise_op_send || call_name in ("to_i" "prev" "succ" "next" "zero?" "even?" "odd?" "negative?" "positive?" "sq" "gcd" "lcm" "chr" "pow" "modpow" "factorial" "digits" "isqrt" "bit_length" "to_s" "to_f" "abs" "prime?" "+" "-" "*")
        consider_autoload_name("Integer", defined, registry, seen, pending)
        if call_name == "to_i" && @bigint_to_i_unresolved
          consider_autoload_name("BigInt", defined, registry, seen, pending)
          @bigint_to_i_unresolved = false
        # BigInt (and its base Int) supply the source bodies for these on a
        # bigint receiver. even?/odd?/... already loaded BigInt widely, so the
        # incremental cost of also loading it for the integer methods is small,
        # and it makes a standalone bigint-method program (e.g. `n.modpow(...)`
        # with no predicate) resolve instead of dispatching to Object.
        if @bigint_predicates_unresolved && (bitwise_op_send || call_name in ("zero?" "even?" "odd?" "negative?" "positive?" "neg!" "abs!" "abs" "gcd" "lcm" "pow" "modpow" "digits" "isqrt" "bit_length" "prev" "succ" "next" "prime?" "to_f" "to_s" "+" "-" "*"))
          consider_autoload_name("BigInt", defined, registry, seen, pending)
          @bigint_predicates_unresolved = false

      # Legacy Base64 globals are source-defined bare calls.
      if call_receiver == nil && call_name in ("base64_encode" "base64_decode" "base64url_encode" "base64url_decode")
        consider_autoload_name("Base64", defined, registry, seen, pending)
    # Standalone ClassRef (Integer as a bare expression): same.
    if t == :class_ref
      consider_autoload_name(node.name, defined, registry, seen, pending)
      if node.name == "ARGV"
        consider_autoload_name("Array", defined, registry, seen, pending)
    if t == :var && node.name == "ARGV"
      consider_autoload_name("Array", defined, registry, seen, pending)
    # Literal-driven autoload: an array literal `[...]` needs Array's
    # class def (for Enumerable methods like zip/uniq that the runtime
    # WArray doesn't provide); a hash literal `{...}` needs Hash. Without
    # this, code that builds arrays via literals and then calls a pure
    # Enumerable method fails at runtime with "undefined method" because
    # array.w was never pulled in (the literal alone references no name).
    if t == :array
      if @array_needed != false
        consider_autoload_name("Array", defined, registry, seen, pending)
      els = node.elements
      if els != nil
        ej2 = 0
        while ej2 < els.size()
          collect_autoload_refs(els[ej2], defined, registry, seen, pending)
          ej2 += 1
    # Typed-array constructors lower directly to WArray factories and carry no
    # Array class reference. Their public query leaves share Array's source
    # method table, so register it before the first dynamic dispatch.
    if t in (:typed_array :typed_array_new)
      consider_autoload_name("Array", defined, registry, seen, pending)
    if t == :hash_literal
      consider_autoload_name("Hash", defined, registry, seen, pending)
    # IPv4/CIDR literals carry their runtime type without naming the IPv4
    # class in source. Once accessors and predicates have Tungsten bodies,
    # their class definition must still be registered before a literal-only
    # call such as `10.0.0.1.private?` reaches runtime dispatch.
    if t == :ip4 || t == :cidr4
      consider_autoload_name("IPv4", defined, registry, seen, pending)
    # IPv6/CIDR literals likewise carry their heap type without spelling the
    # class name; their accessors now require the source-defined type class.
    if t == :ip6 || t == :cidr6
      consider_autoload_name("IPv6", defined, registry, seen, pending)
    # Date and Datetime literals share the packed Date runtime type. Their
    # native accessors now live in core/date.w, so literal-only programs must
    # register Date's 0xE4 type class even when they never name Date directly.
    if t == :date || t == :datetime
      consider_autoload_name("Date", defined, registry, seen, pending)
    # Rational literals are packed values whose accessors and conversions
    # live in core/numeric/rational.w.
    if t == :rational
      consider_autoload_name("Rational", defined, registry, seen, pending)
    # UUID literals carry the runtime subtag without a class reference. Once
    # byte is source-defined, literal-only programs must register UUID's type
    # class before public dispatch.
    if t == :uuid
      consider_autoload_name("UUID", defined, registry, seen, pending)
    # A range literal `(a..b)` references no class name, but its numeric
    # machinery — and the elementwise methods (`sq`, `cube`, …) the fused
    # pipeline's closed-form recognizer resolves by AST — lives on Number.
    # Pull it in so those method bodies are registered (mirrors Array/Hash).
    if t == :range
      consider_autoload_name("Number", defined, registry, seen, pending)
      consider_autoload_name("Range", defined, registry, seen, pending)
    # `<< a, b` stores a list of value nodes in Puts#value. The generic
    # single-value walk below intentionally ignores non-AST containers, so
    # recurse the print list here or class refs inside `<< Digest.sha1(...)`
    # never trigger core autoload.
    if t == :puts && node.value != nil
      vals = node.value
      vi = 0
      while vi < vals.size()
        collect_autoload_refs(vals[vi], defined, registry, seen, pending)
        vi += 1
    # `"[Sandbox.active?]"` keeps its parts as [tag, payload] pairs in
    # Node#parts, not as AST children, so the generic probes below never see
    # them. A class named ONLY inside an interpolation would resolve to nil at
    # runtime. Literal parts carry a String payload (tag :str); the rest carry
    # an expression node.
    if t in (:string_interp :byte_array_interp) && node.parts != nil
      iparts = node.parts
      pi = 0
      while pi < iparts.size()
        ipart = iparts[pi]
        if ipart != nil && ipart[0] != :str
          collect_autoload_refs(ipart[1], defined, registry, seen, pending)
        pi += 1
    if node.args != nil
      ai = 0
      while ai < node.args.size()
        collect_autoload_refs(node.args[ai], defined, registry, seen, pending)
        ai += 1
    if node.body != nil && t != :class_def
      collect_autoload_refs_seq(node.body, defined, registry, seen, pending)
    if node.then_body != nil
      collect_autoload_refs_seq(node.then_body, defined, registry, seen, pending)
    if node.else_body != nil
      collect_autoload_refs_seq(node.else_body, defined, registry, seen, pending)
    # begin/rescue/ensure — the rescue and ensure clauses live in their own
    # fields, so class refs that appear only inside them (`rescue TypeError`
    # checks, ensure-time cleanup) would otherwise never trigger autoload.
    if node.rescue_body != nil
      collect_autoload_refs_seq(node.rescue_body, defined, registry, seen, pending)
    if node.ensure_body != nil
      collect_autoload_refs_seq(node.ensure_body, defined, registry, seen, pending)
    # Postfix `rescue` (rescue_expr) packs its fallback expression as a single
    # node in its own field — a class named only there must still autoload.
    if node.fallback != nil
      collect_autoload_refs_seq(node.fallback, defined, registry, seen, pending)
    if node.expressions != nil
      collect_autoload_refs_seq(node.expressions, defined, registry, seen, pending)
    if node.value != nil && is_ast_node?(node.value)
      collect_autoload_refs(node.value, defined, registry, seen, pending)
    if node.left != nil && is_ast_node?(node.left)
      collect_autoload_refs(node.left, defined, registry, seen, pending)
    if node.right != nil && is_ast_node?(node.right)
      collect_autoload_refs(node.right, defined, registry, seen, pending)
    if node.condition != nil && is_ast_node?(node.condition)
      collect_autoload_refs(node.condition, defined, registry, seen, pending)
    # `range.each { }` (and the bare `1..N -> …` loop, which parses to `each`)
    # lowers to a native counting loop — no Range/Number method is ever called.
    # Recursing into the range receiver here would autoload Range, which
    # `is Enumerable` and transitively drags in Array/Hash/Enumerable (all their
    # w_add/closure-bearing method bodies) into a program that needs none of it.
    # Skip the receiver walk for that one native form; every other range use
    # (`.to_a`, `.map`, pipeline `source`, …) still autoloads normally.
    is_native_range_each = t == :call && node.name == "each" && node.block != nil && node.receiver != nil && ast_kind(node.receiver) == :range
    if node.receiver != nil && is_ast_node?(node.receiver) && !is_native_range_each
      collect_autoload_refs(node.receiver, defined, registry, seen, pending)
    if node.target != nil && is_ast_node?(node.target)
      collect_autoload_refs(node.target, defined, registry, seen, pending)
    # Pipeline stages (Map/Calc) carry their input in `source` and the
    # per-element function in `func` — neither is args/body, so without
    # these the range/array at the bottom of a `/stage…:reduce` chain is
    # never visited and its autoload (Number/Array) is missed.
    if node.source != nil && is_ast_node?(node.source)
      collect_autoload_refs(node.source, defined, registry, seen, pending)
    if node.func != nil && is_ast_node?(node.func)
      collect_autoload_refs(node.func, defined, registry, seen, pending)
    # A trailing block hangs off `block`, which is none of the fields above, so
    # a class named ONLY inside one (`lines.each -> (l) out.push(JSON.parse(l))`)
    # never autoloaded and resolved to nil at runtime. The block node carries
    # its own `body`, which the generic walk above picks up on recursion.
    if node.block != nil && is_ast_node?(node.block)
      collect_autoload_refs(node.block, defined, registry, seen, pending)
    nil

  # Walk a body-ish field that is usually a node Array but may hold a SINGLE
  # packed node (rescue_expr's body/fallback from postfix `rescue`). Calling
  # .size() on an AST node yields nil, and `i < nil` raises in the compiled
  # compiler, so the two shapes must be told apart before iterating.
  -> collect_autoload_refs_seq(nodes, defined, registry, seen, pending)
    if is_ast_node?(nodes)
      collect_autoload_refs(nodes, defined, registry, seen, pending)
      return nil
    i = 0
    while i < nodes.size()
      collect_autoload_refs(nodes[i], defined, registry, seen, pending)
      i += 1
    nil

  # Native runtime entry points whose WValue result has source-defined methods.
  # This is intentionally a return-type map, not a prefix match: helpers such
  # as w_ipv6_in_cidr returns Bool, while w_date_scrub
  # returns String, and must not autoload the address/Date classes.
  -> native_ccall_result_class(name)
    if name in ("w_date" "w_date_parse")
      return "Date"
    if name in ("w_ipv4" "w_ipv4_parse" "w_ipv4_from_octets")
      return "IPv4"
    if name in ("w_ipv6" "w_ipv6_from_string" "w_ipv6_parse" "w_ipv6_storage_clone" "w_ipv6_storage_from_words")
      return "IPv6"
    if name in ("w_mac" "w_mac_parse")
      return "MAC"
    if name in ("w_uuid_from_hex" "w_uuid_parse")
      return "UUID"
    if name == "w_strbuf_new"
      return "StringBuffer"
    if name == "w_atomic_new"
      return "Atomic"
    if name == "w_chan_new"
      return "Channel"
    if name == "w_mutex_new"
      return "Mutex"
    if name in ("w_thread_spawn" "w_thread_spawn_slots")
      return "Thread"
    # Runtime-backed packed-array values can enter without a class reference
    # through low-level C factories. Once their public leaves live in source,
    # those exact value-producing calls must register the corresponding type
    # class before the first dynamic method dispatch. Do not prefix-match:
    # accessors such as w_big_array_size return Integer, not BigArray.
    if name in ("w_big_array_new" "w_big_array_view" "w_big_array_subview" "w_big_array_view_range")
      return "BigArray"
    if name in ("w_small_array_new" "w_small_array_new_value" "w_small_array_init")
      return "SmallArray"
    if name == "__w_file_mmap"
      return "Mmap"
    # Exact WArray-producing runtime entry points. Keep this a return-type map,
    # not a prefix match: w_array_size/w_array_get/etc. return other types.
    if name in ("w_array_new_empty" "w_array_new" "w_array_new_filled" "w_array_new_uninit" "w_array_new_uninit_sized" "w_array_new_inline_uninit_sized" "w_array_new_aligned" "w_array_zeros" "w_array_view_raw" "w_array_view" "w_array_view_range" "w_array_reinterpret" "w_array_copy_range" "w_array_reuse_or_new_empty" "w_bytes_new" "w_bool_array_new")
      return "Array"
    nil

  -> string_empty_receiver?(node)
    if node == nil || !is_ast_node?(node)
      return false
    t = ast_kind(node)
    if t == :var && @string_literal_vars != nil && @string_literal_vars[node.name] == true
      return true
    if t == :string || t == :string_interp
      return true
    if t == :binary_op
      if node.op == :PLUS
        return string_empty_receiver?(node.left) || string_empty_receiver?(node.right)
      if node.op == :STAR
        return string_empty_receiver?(node.left)
      return false
    if t == :call
      # Conversion is String-producing regardless of receiver type.
      if node.name == "to_s"
        return true
      # These preserve/derive String storage when their receiver is known.
      if node.name in ("slice" "strip" "ltrim" "rtrim" "upcase" "downcase" "swapcase" "capitalize" "concat" "append" "prepend" "replace" "gsub" "to_sym")
        return string_empty_receiver?(node.receiver)
      # Common dynamic String-producing boundaries.
      if node.receiver == nil && node.name in ("read_file" "env" "gets")
        return true
    false

  -> consider_autoload_name(name, defined, registry, seen, pending, force = false)
    if name == nil
      return nil
    if defined[name] == true && !force
      return nil
    if seen[name] == true
      return nil
    if registry[name] == nil
      return nil
    if @autoload_loaded[name] == true
      return nil
    seen[name] = true
    pending.push(name)
    nil

  -> cache_version
    # v23: dynamic Decimal source methods schedule their Core facade.
    "loader-ast-v23"

  -> cache_dir
    override = env("TUNGSTEN_CACHE_DIR")
    if override != nil && override != ""
      return override
    project_root = find_project_root("")
    if project_root != ""
      return project_root + "/build/cache"
    root = env("TUNGSTEN_ROOT")
    if root != nil && root != ""
      return root + "/build/cache"
    nil

  -> cache_key(resolved)
    bit_home = env("BIT_HOME")
    if bit_home == nil
      bit_home = ""
    project_root = find_project_root("")
    digest_sha256(cache_version() + "|" + resolved + "|" + bit_home + "|" + project_root + "|" + @runtime_id + "|" + @service_bindings_id)

  -> ast_cache_path(resolved)
    dir = cache_dir()
    if dir == nil
      return nil
    dir + "/loader-ast-" + cache_key(resolved) + ".memo"

  -> ast_manifest_path(resolved)
    dir = cache_dir()
    if dir == nil
      return nil
    dir + "/loader-ast-" + cache_key(resolved) + "-manifest.memo"

  -> read_ast_cache(resolved)
    if !@cacheable
      return nil

    manifest_path = ast_manifest_path(resolved)
    ast_path = ast_cache_path(resolved)
    if manifest_path == nil || ast_path == nil
      return nil

    manifest = cache_read(manifest_path)
    if !manifest_valid?(manifest, resolved)
      return nil

    ast = cache_read(ast_path)
    if ast == nil
      return nil

    if @verbose && env("DEBUG_LOADS") == "1"
      << "  ast cache hit " + display_path(resolved)
    ast

  -> write_ast_cache(resolved, ast)
    if !@cacheable
      return ast

    ast_path = ast_cache_path(resolved)
    manifest_path = ast_manifest_path(resolved)
    if ast_path == nil || manifest_path == nil
      return ast

    # v2: include schema_hash so the loader rejects caches whose
    # KIND_*/SC_*/STRIDE_* schema doesn't match the running compiler.
    # See compiler/lib/ast_schema.w:w_ast_schema_hash_tungsten.
    manifest = {version: cache_version(), runtime: @runtime_id, entry: resolved, service_bindings: @service_bindings_id, files: @manifest_files, schema_hash: w_ast_schema_hash_tungsten()}
    ast_written = cache_write(ast_path, ast)
    manifest_written = false
    if ast_written
      manifest_written = cache_write(manifest_path, manifest)
    if @verbose && env("DEBUG_LOADS") == "1" && ast_written && manifest_written
      << "  ast cache write " + display_path(resolved)
    ast

  -> display_path(path)
    parts = path.split("/")
    if parts.size() > 1
      parts.pop()
    base_dir = parts.join("/")
    project_root = find_project_root(base_dir)
    if project_root == "."
      cwd = env("PWD")
      if cwd != nil && cwd != ""
        project_root = cwd
    prefix = project_root + "/"
    if project_root != "" && path.starts_with?(prefix)
      return path.slice(prefix.size(), path.size() - prefix.size())
    path

  -> manifest_valid?(manifest, resolved)
    if type(manifest) != "Hash"
      return false
    if manifest[:version] != cache_version()
      return false
    if manifest[:runtime] != @runtime_id
      return false
    if manifest[:entry] != resolved
      return false
    if manifest[:service_bindings] != @service_bindings_id
      return false
    if manifest[:schema_hash] != w_ast_schema_hash_tungsten()
      return false

    files = manifest[:files]
    if type(files) != "Array"
      return false

    i = 0
    while i < files.size()
      entry = files[i]
      if type(entry) != "Array" || entry.size() != 2
        return false
      current = file_mtime_ns(entry[0])
      if current == nil || current != entry[1]
        return false
      i += 1

    true

  # Record (path, mtime_ns) for every loaded file — for the ruby AST cache
  # AND the compiled driver's incremental binary cache (which keys on this
  # manifest; the ruby-only @cacheable never engages there). A missing
  # mtime poisons both consumers.
  -> record_manifest_file(path)
    if @manifest_wanted != true
      return nil
    mtime = file_mtime_ns(path)
    if mtime == nil
      @cacheable = false
      @manifest_files = []
      @manifest_poisoned = true
      return nil
    @manifest_files.push([path, mtime])
    mtime

  # Driver accessors for the incremental compile cache.
  -> manifest_files
    if @manifest_poisoned == true || @manifest_wanted != true
      return nil
    @manifest_files

  -> resolve_path(path, from_file = nil)
    # Service registry: if `path` is a bare service name (no slash)
    # and the project Bitfile has `Tungsten[:<path>] = "<bit>"`,
    # rewrite the path to load the bit instead of the core stdlib.
    # Allows `use json` to pick up tungsten-json (or any other bound
    # bit) without callers having to know which implementation is
    # installed. Falls through to core/json.w when no binding is set.
    if !path.starts_with?("/") && path.index("/") == nil && @service_bindings[path] != nil
      path = @service_bindings[path]

    resolved = path
    base_dir = ""
    root_dir = ""

    if from_file != nil
      parts = from_file.split("/")
      parts.pop()
      base_dir = parts.join("/")
      if parts.last() == "lib"
        root_dir = parts[0...-1].join("/")
      else
        root_dir = base_dir

    # `core/` prefix: always resolves to <project_root>/core/<rest>.w.
    # Unambiguous — bits use this to reach back into the project's
    # canonical core classes regardless of their own location.
    if path.starts_with?("core/")
      project_root = find_core_root(base_dir)
      if project_root != ""
        core_path = project_root + "/" + path + ".w"
        if file?(core_path)
          return normalize_load_path(core_path)

    if !resolved.starts_with?("/")
      if resolved.starts_with?("lib/") && root_dir != ""
        resolved = root_dir + "/" + resolved
      elsif base_dir != ""
        resolved = base_dir + "/" + resolved

    if !resolved.ends_with?(".w") && !resolved.ends_with?(".w0")
      resolved += ".w"

    if file?(resolved)
      return normalize_load_path(resolved)

    # Bit resolution
    bit_name = path.split("/").first().downcase()
    sub_parts = path.split("/")
    sub_parts.shift()
    sub_path = sub_parts.join("/")

    # Bit search order for `use`:
    #   1. project_root/vendor/bits  — `bit install` destination
    #   2. $BIT_HOME                — monorepo / local registry of bit sources
    #   3. project_root/bits        — in-tree bits layout
    project_root = find_project_root(base_dir)
    if project_root != ""
      found = resolve_bit(bit_name, sub_path, project_root + "/vendor/bits", project_root)
      if found != nil
        return found

    bit_home = env("BIT_HOME")
    if bit_home == nil || bit_home == ""
      tungsten_home = env("TUNGSTEN_HOME")
      if tungsten_home == nil || tungsten_home == ""
        home = env("HOME")
        if home != nil && home != ""
          tungsten_home = home + "/.tungsten"
      if tungsten_home != nil && tungsten_home != ""
        bit_home = tungsten_home + "/bits"
    if bit_home != nil && bit_home != ""
      found = resolve_bit(bit_name, sub_path, bit_home, project_root)
      if found != nil
        return found

    if project_root != ""
      found = resolve_bit(bit_name, sub_path, project_root + "/bits", project_root)
      if found != nil
        return found

    # Standard library: project_root/core/<path>.w first (new canonical
    # location), then project_root/lib/<path>.w as backward-compat
    # fallback during the lib/ → core/ migration.
    if project_root != ""
      core_candidate = project_root + "/core/" + path + ".w"
      if file?(core_candidate)
        return normalize_load_path(core_candidate)
      lib_candidate = project_root + "/lib/" + path + ".w"
      if file?(lib_candidate)
        return normalize_load_path(lib_candidate)

    # Stdlib fallback anchored on the install root rather than the caller's
    # ancestry. `project_root` above is Bitfile-anchored, so it is empty for
    # any program outside a Tungsten project — a script in ~/math, say — and
    # then falls back to "." only when the *current working directory*
    # happens to hold a Bitfile. That made `use algebra` succeed or fail
    # depending on where the shell was sitting, with the failure surfacing
    # far downstream as `undefined method 'starts_with?' for nil`.
    #
    # find_core_root is anchored on core/tungsten.w and already carries the
    # TUNGSTEN_ROOT fallback that bin/tungsten exports, so consulting it here
    # gives the intended split: local project files resolve against the
    # program's own root, core files against the install root.
    core_root = find_core_root(base_dir)
    if core_root != "" && core_root != project_root
      core_candidate = core_root + "/core/" + path + ".w"
      if file?(core_candidate)
        return normalize_load_path(core_candidate)
      lib_candidate = core_root + "/lib/" + path + ".w"
      if file?(lib_candidate)
        return normalize_load_path(lib_candidate)

    resolved

  # Collapse `.` and `..` before recording a loaded file. Without this, the
  # same shared source can arrive through two valid spellings (for example
  # compiler/lib/../../languages/... and languages/...) and be parsed twice,
  # producing duplicate top-level definitions. This matters for programs that
  # intentionally load both the packed lexer and the reference RegexLexer.
  -> normalize_load_path(path)
    absolute = path.starts_with?("/")
    input = path.split("/")
    output = []
    i = 0
    while i < input.size()
      part = input[i]
      if part != "" && part != "."
        if part == ".."
          if output.size() > 0 && output.last() != ".."
            output.pop()
          elsif !absolute
            output.push(part)
        else
          output.push(part)
      i += 1
    normalized = output.join("/")
    if absolute
      return "/" + normalized
    normalized

  -> bit_lock_fields(line)
    fields = []
    tail = line
    while fields.size() < 2
      first = tail.index("\"")
      if first == nil
        return fields
      tail = tail.slice(first + 1, tail.size() - first - 1)
      finish = tail.index("\"")
      if finish == nil
        return fields
      fields.push(tail.slice(0, finish))
      tail = tail.slice(finish + 1, tail.size() - finish - 1)
    fields

  -> locked_bit_version(bit_name, project_root)
    if project_root == nil || project_root == ""
      return nil
    lock_path = project_root + "/Bitfile.lock"
    if !file?(lock_path)
      return nil
    lines = read_file(lock_path).split("\n")
    i = 0
    while i < lines.size()
      line = lines[i].strip()
      if line.starts_with?("bit ") || line.starts_with?("dependency ")
        fields = bit_lock_fields(line)
        if fields.size() == 2
          locked_name = fields[0]
          if locked_name == bit_name || locked_name == "tungsten-" + bit_name
            version = fields[1]
            if version != "" && version.index("/") == nil && version != "." && version != ".."
              return version
      i += 1
    nil

  -> resolve_bit_package(package_dir, bit_name, sub_path, entry_file)
    candidate = package_dir + "/lib/" + entry_file
    if file?(candidate)
      return candidate
    if sub_path != ""
      namespace = bit_name.replace("tungsten-", "")
      candidate = package_dir + "/lib/" + namespace + "/" + sub_path + ".w"
      if file?(candidate)
        return candidate
    nil

  -> resolve_bit(bit_name, sub_path, bit_home, project_root = "")
    if sub_path == ""
      entry_file = bit_name.replace("tungsten-", "") + ".w"
    else
      entry_file = sub_path + ".w"

    # Global installs are immutable and versioned:
    #   $BIT_HOME/<package>/<version>/
    # A project lock selects the exact directory. Without a project lock,
    # `bit install` maintains a `current` symlink for standalone scripts.
    locked_version = locked_bit_version(bit_name, project_root)
    package_names = [bit_name]
    if !bit_name.starts_with?("tungsten-")
      package_names.push("tungsten-" + bit_name)
    i = 0
    while i < package_names.size()
      package_root = bit_home + "/" + package_names[i]
      if locked_version != nil
        found = resolve_bit_package(package_root + "/" + locked_version, bit_name, sub_path, entry_file)
        if found != nil
          return found
      found = resolve_bit_package(package_root + "/current", bit_name, sub_path, entry_file)
      if found != nil
        return found
      i += 1

    if bit_name.starts_with?("tungsten-")
      candidate = bit_home + "/" + bit_name + "/lib/" + entry_file
      if file?(candidate)
        return candidate
      # Application-sized bits may keep internal modules under the same
      # namespace as their public entry, e.g. tungsten-metaflip exposes
      # lib/metaflip.w and lib/metaflip/scheme.w. Preserve the historical flat
      # lookup above, then admit that physical namespace for submodules.
      if sub_path != ""
        namespace = bit_name.replace("tungsten-", "")
        candidate = bit_home + "/" + bit_name + "/lib/" + namespace + "/" + sub_path + ".w"
        if file?(candidate)
          return candidate

    # Try exact: bit_home/<name>/lib/<name>.w
    exact = bit_home + "/" + bit_name + "/lib/" + entry_file
    if file?(exact)
      return exact
    if sub_path != ""
      namespace = bit_name.replace("tungsten-", "")
      namespaced = bit_home + "/" + bit_name + "/lib/" + namespace + "/" + sub_path + ".w"
      if file?(namespaced)
        return namespaced
    # Try tungsten-prefixed: bit_home/tungsten-<name>/lib/<name>.w
    prefixed = bit_home + "/tungsten-" + bit_name + "/lib/" + entry_file
    if file?(prefixed)
      return prefixed
    if sub_path != ""
      namespaced = bit_home + "/tungsten-" + bit_name + "/lib/" + bit_name + "/" + sub_path + ".w"
      if file?(namespaced)
        return namespaced
    nil

  -> find_project_root(dir)
    # Source-ancestry-first: walk up from the source file's directory
    # looking for a Bitfile. If the source file's tree has one,
    # use it — this isolates tmpdir spec fixtures from the repo root
    # they were chdir'd to.
    #
    # Only fall back to CWD-relative "." if source ancestry has no
    # Bitfile at all (typical case: compiling /tmp/foo.w while the
    # shell is sitting in the project root).
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

  # Like find_project_root, but anchored on `core/tungsten.w` (the stdlib
  # autoload manifest) rather than a Bitfile. A bit carries its own Bitfile
  # but no `core/` of its own, so stdlib autoload and `core/…` resolution
  # must reach *past* the bit to the surrounding project root that actually
  # holds core/. find_project_root would stop at the bit's Bitfile and miss
  # it — which silently disabled all core autoload inside bits.
  -> find_core_root(dir)
    if dir != ""
      parts = dir.split("/")
      i = parts.size()
      while i > 0
        candidate = parts[0...i].join("/")
        # NEAREST ancestor wins. The walk used to continue upward and keep
        # the SHALLOWEST match, so a checkout nested inside another
        # (git worktrees under .claude/worktrees/, a vendored repo) silently
        # compiled the OUTER repo's core/ — stage identity checks then raced
        # against concurrent edits in the outer tree.
        if file?(candidate + "/core/tungsten.w")
          return candidate
        i -= 1
    if file?("core/tungsten.w")
      return "."
    # Install-root fallback: compiling a .w file whose ancestry AND cwd both
    # lack core/tungsten.w (e.g. `tungsten /tmp/foo.w` run from outside the
    # repo). The bin/tungsten wrapper exports TUNGSTEN_ROOT = install root, so
    # stdlib autoload still resolves. Without this, every pure-Tungsten core
    # class silently autoloads to nil from a foreign directory.
    root = env("TUNGSTEN_ROOT")
    if root != nil && root != "" && file?(root + "/core/tungsten.w")
      return root
    ""
