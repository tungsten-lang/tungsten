use lexer
use parser

+ Loader
  -> new(@verbose = false)
    @loaded_files = []
    @manifest_files = []
    @cacheable = false
    @runtime_id = nil
    @service_bindings = parse_service_bindings(env("TUNGSTEN_SERVICE_BINDINGS"))
    @autoload_registry = nil
    @autoload_loaded = {}

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

  -> load_program_ast(path, from_file = nil)
    resolved = resolve_path(path, from_file)

    if from_file == nil
      @loaded_files = []
      @manifest_files = []
      @runtime_id = runtime_identity()
      @cacheable = @runtime_id.starts_with?("ruby ")

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
      ast = autoload_pass(ast, resolved)
      write_ast_cache(resolved, ast)
    ast

  # Lazy iterative autoload. After the entry-file's recursive `:use` walk
  # produces `ast`, scan for unresolved class/trait references whose names
  # appear in core/tungsten.w's `auto :Name, "path"` registry. Load each
  # missing file once, append its expressions, and rescan — newly-loaded
  # files often introduce further references (e.g. core/array.w → Enumerable).
  -> autoload_pass(ast, base_resolved)
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
    iteration = 0
    while iteration < 64
      defined = collect_defined_names(expressions)
      pending = collect_unresolved_autoload_names(expressions, defined, registry)
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
            li = 0
            while li < loaded.expressions.size()
              expressions.push(loaded.expressions[li])
              li += 1
        pi += 1
      iteration += 1
    # Reorder so autoloaded class defs come before user code that inherits
    # from them: `+ Foo < Object` would otherwise reference @class.Object
    # before Object's class_new ran. Autoload pulls in top-down order
    # (user-referenced first, then their deps), so the deepest dependency
    # was loaded LAST — reversing the autoloaded tail puts roots first,
    # which is what class creation needs.
    reordered = []
    ai = expressions.size() - 1
    while ai >= user_count
      reordered.push(expressions[ai])
      ai -= 1
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

  -> collect_unresolved_autoload_names(exprs, defined, registry)
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
    seen = {}
    pending = []
    i = 0
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
      if node.superclass != nil
        consider_autoload_name(node.superclass, defined, registry, seen, pending)
      if node.body != nil
        bj = 0
        while bj < node.body.size()
          collect_autoload_refs(node.body[bj], defined, registry, seen, pending)
          bj += 1
    # Phase 1.5: const/class-name receiver autoload. `Array.new(...)` and
    # `ByteArray.from_array(...)` reach a class via a var receiver — when the
    # name appears in the autoload registry and isn't already defined,
    # pull the file in. Made safe by the tolerant-load block above: a
    # broken stub (e.g. core/object.w) is silently skipped instead of
    # blowing up the entire compile.
    if t == :call && node.receiver != nil && ast_kind(node.receiver) == :var
      consider_autoload_name(node.receiver.name, defined, registry, seen, pending)
    # ClassRef receiver — always a class reference, autoload if the
    # name is in the registry.
    if t == :call && node.receiver != nil && ast_kind(node.receiver) == :class_ref
      consider_autoload_name(node.receiver.name, defined, registry, seen, pending)
    # Standalone ClassRef (Integer as a bare expression): same.
    if t == :class_ref
      consider_autoload_name(node.name, defined, registry, seen, pending)
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
    if t == :hash_literal
      consider_autoload_name("Hash", defined, registry, seen, pending)
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
    if node.args != nil
      ai = 0
      while ai < node.args.size()
        collect_autoload_refs(node.args[ai], defined, registry, seen, pending)
        ai += 1
    if node.body != nil && t != :class_def
      bj = 0
      while bj < node.body.size()
        collect_autoload_refs(node.body[bj], defined, registry, seen, pending)
        bj += 1
    if node.then_body != nil
      bj = 0
      while bj < node.then_body.size()
        collect_autoload_refs(node.then_body[bj], defined, registry, seen, pending)
        bj += 1
    if node.else_body != nil
      bj = 0
      while bj < node.else_body.size()
        collect_autoload_refs(node.else_body[bj], defined, registry, seen, pending)
        bj += 1
    if node.expressions != nil
      ej = 0
      while ej < node.expressions.size()
        collect_autoload_refs(node.expressions[ej], defined, registry, seen, pending)
        ej += 1
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
    nil

  -> consider_autoload_name(name, defined, registry, seen, pending)
    if name == nil
      return nil
    if defined[name] == true
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
    "loader-ast-v2"

  -> cache_dir
    override = env("TUNGSTEN_CACHE_DIR")
    if override != nil && override != ""
      return override
    home = env("HOME")
    if home == nil || home == ""
      return nil
    home + "/.tungsten/cache"

  -> cache_key(resolved)
    bit_home = env("BIT_HOME")
    if bit_home == nil
      bit_home = ""
    project_root = find_project_root("")
    digest_sha256(cache_version() + "|" + resolved + "|" + bit_home + "|" + project_root + "|" + @runtime_id)

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
    manifest = {version: cache_version(), runtime: @runtime_id, entry: resolved, files: @manifest_files, schema_hash: w_ast_schema_hash_tungsten()}
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

  -> record_manifest_file(path)
    if !@cacheable
      return nil
    mtime = file_mtime_ns(path)
    if mtime == nil
      @cacheable = false
      @manifest_files = []
      return nil
    @manifest_files.push([path, mtime])
    mtime

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
          return core_path

    if !resolved.starts_with?("/")
      if resolved.starts_with?("lib/") && root_dir != ""
        resolved = root_dir + "/" + resolved
      elsif base_dir != ""
        resolved = base_dir + "/" + resolved

    if !resolved.ends_with?(".w") && !resolved.ends_with?(".w0")
      resolved += ".w"

    if file?(resolved)
      return resolved

    # Bit resolution
    bit_name = path.split("/").first().downcase()
    sub_parts = path.split("/")
    sub_parts.shift()
    sub_path = sub_parts.join("/")

    bit_home = env("BIT_HOME")
    if bit_home == nil
      project_root = find_project_root(base_dir)
      if project_root != ""
        bit_home = project_root + "/bits"

    if bit_home != nil
      found = resolve_bit(bit_name, sub_path, bit_home)
      if found != nil
        return found

    # Standard library: project_root/core/<path>.w first (new canonical
    # location), then project_root/lib/<path>.w as backward-compat
    # fallback during the lib/ → core/ migration.
    project_root = find_project_root(base_dir)
    if project_root != ""
      core_candidate = project_root + "/core/" + path + ".w"
      if file?(core_candidate)
        return core_candidate
      lib_candidate = project_root + "/lib/" + path + ".w"
      if file?(lib_candidate)
        return lib_candidate

    resolved

  -> resolve_bit(bit_name, sub_path, bit_home)
    if sub_path == ""
      entry_file = bit_name.replace("tungsten-", "") + ".w"
    else
      entry_file = sub_path + ".w"

    if bit_name.starts_with?("tungsten-")
      candidate = bit_home + "/" + bit_name + "/lib/" + entry_file
      if file?(candidate)
        return candidate

    # Try exact: bit_home/<name>/lib/<name>.w
    exact = bit_home + "/" + bit_name + "/lib/" + entry_file
    if file?(exact)
      return exact
    # Try tungsten-prefixed: bit_home/tungsten-<name>/lib/<name>.w
    prefixed = bit_home + "/tungsten-" + bit_name + "/lib/" + entry_file
    if file?(prefixed)
      return prefixed
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
      result = ""
      i = parts.size()
      while i > 0
        candidate = parts[0...i].join("/")
        if file?(candidate + "/core/tungsten.w")
          result = candidate
        i -= 1
      if result != ""
        return result
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
