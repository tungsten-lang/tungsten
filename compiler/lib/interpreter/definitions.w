+ Interpreter

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
  # A trait not seen yet is autoloaded through the same registry as classes
  # (core/tungsten.w registers `auto :Enumerable, "traits/enumerable"` etc.)
  # — without this, a lazily autoloaded core class like Array dropped its
  # `is Enumerable` on the floor and sort_by/min_by/max_by never existed
  # interpreted. An unresolvable trait name is left as a bare
  # :trait_include, which the main evaluate() dispatcher no-ops (see its
  # :trait_include case).
  # Returns [expr, from_trait] pairs so eval_class_def can mark spliced
  # methods as trait DEFAULTS (see register_instance_method's shadowing
  # rule).
  -> expand_trait_includes(body)
    if body == nil
      return []
    expanded = []
    body.each -> (expr)
      if is_ast_node?(expr) && ast_kind(expr) == :trait_include
        trait_name = ast_get(expr, :name)
        if !@traits.has_key?(trait_name)
          try_autoload_class(trait_name)
        if @traits.has_key?(trait_name)
          @traits[trait_name].each -> (m)
            expanded.push([m, true])
        else
          expanded.push([expr, false])
      else
        expanded.push([expr, false])
    expanded

  # Single insertion path for interpreted instance methods. The name map
  # preserves last-definition lookup for callers that do not carry arity;
  # the side table mirrors compiled exact-arity selection and registration-
  # order fallback. Reopening the same arity replaces its old slot so neither
  # dynamic definitions nor generated accessors leave a stale overload.
  -> register_instance_method(w_class, w_method)
    if @method_tables_locked
      raise "method tables are locked by Tungsten.LOCK_THE_DOORS!"
    method_name = w_method[:name]
    if w_class[:method_overloads] == nil
      w_class[:method_overloads] = {}
    overloads = w_class[:method_overloads][method_name]
    if overloads == nil
      overloads = []
      w_class[:method_overloads][method_name] = overloads
    # A trait-spliced method is a DEFAULT: a class's own method of the same
    # name shadows it at EVERY arity, not just its own. Exact-arity lookup
    # otherwise lets a trait method win a call the class meant to own —
    # Enumerable#sort (arity 0, body `to_a.sort`) beat Array#sort(&)
    # (arity 1) for `arr.sort`, and Array#to_a returns self, so dispatch
    # recursed until the stack died. Own methods purge same-name defaults;
    # a default arriving after an own method is dropped.
    if w_method[:trait_default] == true
      i = 0
      while i < overloads.size()
        if overloads[i][:trait_default] != true
          return w_method
        i += 1
    else
      kept = []
      i = 0
      while i < overloads.size()
        if overloads[i][:trait_default] != true
          kept.push(overloads[i])
        i += 1
      if kept.size() != overloads.size()
        overloads = kept
        w_class[:method_overloads][method_name] = overloads
    w_class[:methods][method_name] = w_method
    replaced = false
    i = 0
    while i < overloads.size()
      # Same-arity siblings that differ only by declared PARAMETER TYPE
      # (`-> */1(Vector)` vs `-> */1(Number)`) are distinct typed overloads —
      # keep both. Only a same-arity, same-param-type redefinition clobbers.
      if overloads[i][:params].size() == w_method[:params].size() && same_param_types?(overloads[i][:param_types], w_method[:param_types])
        overloads[i] = w_method
        replaced = true
        break
      i += 1
    if !replaced
      overloads.push(w_method)
    w_method

  -> register_interpreted_class_method(w_class, w_method)
    if @method_tables_locked
      raise "method tables are locked by Tungsten.LOCK_THE_DOORS!"
    method_name = w_method[:name]
    if w_class[:class_method_overloads] == nil
      w_class[:class_method_overloads] = {}
    overloads = w_class[:class_method_overloads][method_name]
    if overloads == nil
      overloads = []
      w_class[:class_method_overloads][method_name] = overloads
    w_class[:class_methods][method_name] = w_method
    replaced = false
    i = 0
    while i < overloads.size()
      if overloads[i][:params].size() == w_method[:params].size() && same_param_types?(overloads[i][:param_types], w_method[:param_types])
        overloads[i] = w_method
        replaced = true
        i = overloads.size()
      else
        i += 1
    if !replaced
      overloads.push(w_method)
    w_method

  # Two param-type signatures are equal when both are absent, or both list the
  # same type names in order. Used so typed operator overloads coexist while a
  # genuine redefinition still replaces its predecessor.
  -> same_param_types?(a, b)
    if a == nil && b == nil
      return true
    if a == nil || b == nil
      return false
    if a.size() != b.size()
      return false
    i = 0
    while i < a.size()
      if a[i] != b[i]
        return false
      i += 1
    true

  # Register a top-level `->`/`fn` without discarding typed siblings. The
  # Environment binding intentionally remains last-definition-wins for legacy
  # untyped lookup; dispatch_bare_call consults this side table first only when
  # a typed signature matches the evaluated arguments.
  -> register_global_method(w_method)
    if @method_tables_locked
      raise "method tables are locked by Tungsten.LOCK_THE_DOORS!"
    method_name = w_method[:name]
    overloads = @function_overloads[method_name]
    if overloads == nil
      overloads = []
      @function_overloads[method_name] = overloads
    replaced = false
    i = 0
    while i < overloads.size()
      if overloads[i][:params].size() == w_method[:params].size() && same_param_types?(overloads[i][:param_types], w_method[:param_types])
        overloads[i] = w_method
        replaced = true
        break
      i += 1
    if !replaced
      overloads.push(w_method)
    @env.define("__method__" + method_name, w_method)
    w_method

  -> eval_class_def(node, env)
    # Class re-open: if a class with this name already exists, merge the
    # new methods into the existing class table with last-wins semantics
    # on name collisions. First-declaration wins for superclass.
    # If the name belongs to core, load that base first; a partial user reopen
    # must not suppress the primitive's standard methods. Do not recursively
    # autoload a core file while evaluating that same file's class definition.
    class_name = ast_get(node, :name)
    registry = autoload_registry()
    if @core_protected && !interpreter_core_file?(@current_file) && (class_name == "Tungsten" || registry[class_name] != nil)
      raise "Tungsten.PROTECT_THE_CORE! forbids replacing or reopening Core definition '" + class_name + "'"
    core_path = nil
    if registry[class_name] != nil
      core_path = core_dir() + "/core/" + registry[class_name] + ".w"
    if core_path != nil && @current_file != core_path
      try_autoload_class(class_name)
    w_class = @classes[class_name]
    if w_class == nil
      if @type_tables_locked
        raise "type tables are locked by Tungsten.STOP_THE_PRESS!"
      superclass = nil
      if ast_get(node, :superclass) != nil
        # Autoload the parent so a subclass of an autoloaded generic (e.g.
        # Octonion < Hypercomplex) inherits its methods (+, abs2, <=>) — the
        # bare lookup below would otherwise miss a not-yet-referenced parent.
        try_autoload_class(ast_get(node, :superclass))
        superclass = @classes[ast_get(node, :superclass)]
      w_class = {rt: :class, name: ast_get(node, :name), superclass: superclass, methods: {}, method_overloads: {}, class_methods: {}, class_method_overloads: {}}
      @classes[class_name] = w_class
    elsif ast_get(node, :superclass) != nil && w_class[:superclass] == nil
      # The entry may be a parentless autoload stub: when a registry entry
      # maps this class to a file other than the one defining it (e.g. an
      # orchestrator like core/physics.w for a class defined in a worker),
      # the try_autoload_class above installs {superclass-less} before the
      # real definition runs, and the merge below would silently drop the
      # `< Parent` link. A definition that names a superclass is
      # authoritative for a stub that has none.
      try_autoload_class(ast_get(node, :superclass))
      w_class[:superclass] = @classes[ast_get(node, :superclass)]
    if w_class[:class_methods] == nil
      w_class[:class_methods] = {}
    if w_class[:class_method_overloads] == nil
      w_class[:class_method_overloads] = {}
    if w_class[:method_overloads] == nil
      w_class[:method_overloads] = {}
    # Retain template parameter names for interpret-time `## T` resolution.
    # Native lowering substitutes these during monomorphization; the tree
    # walker binds them to a scoped class send or its constructed instance.
    if ast_get(node, :type_params) != nil
      w_class[:type_params] = ast_get(node, :type_params)

    prev_defining = @defining_class
    @defining_class = w_class
    if w_class[:cvars] == nil
      w_class[:cvars] = {}
    pending_aliases = []
    expand_trait_includes(ast_get(node, :body)).each -> (entry)
      expr = entry[0]
      from_trait = entry[1]
      if ast_kind(expr) == :method_def
        mbody = register_trailing_accessors(expr, ast_get(expr, :body), w_class)
        w_method = {rt: :method, name: ast_get(expr, :name), params: ast_get(expr, :params), body: mbody, w_class: w_class, file: @current_file, trait_default: from_trait, param_types: ast_get(expr, :param_types)}
        if ast_get(expr, :is_class_method) == true
          register_interpreted_class_method(w_class, w_method)
        else
          register_instance_method(w_class, w_method)
      elsif ast_kind(expr) == :view_decl && ast_get(expr, :kind) == "struct"
        register_data_field_accessors(expr, w_class)
      elsif ast_kind(expr) == :call && ast_get(expr, :receiver) == nil && (ast_get(expr, :name) == "ro" || ast_get(expr, :name) == "rw")
        # Standalone class-body `ro :name` / `rw :name` — synthesize accessors
        # (mirrors expand_class_body_accessors / lower_accessors).
        register_class_body_accessors(expr, w_class)
      elsif ast_kind(expr) == :call && ast_get(expr, :receiver) == nil && ast_get(expr, :name) == "alias_method"
        # Class-body `alias_method :new/N, :old/N` — deferred to the end of
        # the body walk: the alias may textually precede the definition it
        # points at (core/date.w aliases to_s/1 above strftime's def).
        pending_aliases.push(expr)
      else
        # Declarative class-body pragmas (noncommutative / noassoc / runtime …)
        # are bare receiver-less calls the interpreter has no handler for. The
        # compiled lower_class_def silently skips any class-body statement that
        # isn't a method / accessor / view / assign; mirror that here. Without
        # this, the pragma's `evaluate` raise aborts method registration and
        # leaves the class a method-less husk (autoload's rescue then hides it).
        if !(ast_kind(expr) == :call && ast_get(expr, :receiver) == nil)
          evaluate(expr, env)
    ai = 0
    while ai < pending_aliases.size()
      register_method_alias(pending_aliases[ai], w_class)
      ai += 1
    @defining_class = prev_defining
    w_class

  # `alias_method :new/N, :old/N` in a class body: re-register the named
  # method's overloads under the new spelling. An /arity suffix narrows the
  # alias to that overload; without one every overload is copied.
  -> register_method_alias(expr, w_class)
    cargs = ast_get(expr, :args)
    if cargs == nil || cargs.size() != 2
      return nil
    if !is_ast_node?(cargs[0]) || !is_ast_node?(cargs[1])
      return nil
    if ast_kind(cargs[0]) != :symbol || ast_kind(cargs[1]) != :symbol
      return nil
    new_raw = "" + ast_get(cargs[0], :value).to_s()
    old_raw = "" + ast_get(cargs[1], :value).to_s()
    new_name = new_raw
    slash = new_raw.index("/")
    if slash != nil
      new_name = new_raw.slice(0, slash)
    old_name = old_raw
    old_arity = 0 - 1
    slash = old_raw.index("/")
    if slash != nil
      old_name = old_raw.slice(0, slash)
      old_arity = old_raw.slice(slash + 1, old_raw.size() - slash - 1).to_i()
    overloads = w_class[:method_overloads][old_name]
    if overloads == nil
      return nil
    i = 0
    while i < overloads.size()
      m = overloads[i]
      if old_arity < 0 || m[:params].size() == old_arity
        alias_m = {rt: :method, name: new_name, params: m[:params], body: m[:body], w_class: m[:w_class], file: m[:file], trait_default: m[:trait_default], param_types: m[:param_types]}
        register_instance_method(w_class, alias_m)
      i += 1
    nil

  # Standalone `ro :x, :y` / `rw :x` in a class body → getter (and setter for
  # rw) methods reading `@x` ivars. Args are Symbol nodes (`:name`).
  -> register_class_body_accessors(expr, w_class)
    writable = ast_get(expr, :name) == "rw"
    args = ast_get(expr, :args)
    default_expr = ast_get(expr, :default)
    if args == nil
      return nil
    i = 0
    while i < args.size()
      arg = args[i]
      field = nil
      if is_ast_node?(arg)
        if ast_kind(arg) == :symbol
          field = "" + ast_get(arg, :value).to_s()
        elsif ast_kind(arg) == :var
          field = "" + ast_get(arg, :name).to_s()
        else
          field = "" + evaluate(arg, Environment.new()).to_s()
      else
        field = "" + arg.to_s()
      # Symbol may print as ":name" — strip leading colon
      if field.starts_with?(":")
        field = field.slice(1, field.size() - 1)
      ivar = "@" + field
      if !w_class[:methods].has_key?(field)
        getter_body = [Tungsten:AST:Ivar.new(ivar)]
        if default_expr != nil
          default_check = Tungsten:AST:If.new(Tungsten:AST:BinaryOp.new(Tungsten:AST:Ivar.new(ivar), :EQ, Tungsten:AST:Nil.new), [Tungsten:AST:Assign.new(Tungsten:AST:Ivar.new(ivar), default_expr)], [], nil)
          getter_body = [default_check, Tungsten:AST:Ivar.new(ivar)]
        reader = {rt: :method, name: field, params: [], body: getter_body, w_class: w_class}
        register_instance_method(w_class, reader)
      if writable
        sname = field + "="
        if !w_class[:methods].has_key?(sname)
          writer = {rt: :method, name: sname, params: [Tungsten:AST:Param.new("value", nil, false)], body: [Tungsten:AST:Assign.new(Tungsten:AST:Ivar.new(ivar), Tungsten:AST:Var.new("value"))], w_class: w_class}
          register_instance_method(w_class, writer)
      i += 1
    nil

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
          reader = {rt: :method, name: fname, params: [], body: [Tungsten:AST:Ivar.new("@" + fname)], w_class: w_class}
          register_instance_method(w_class, reader)
        if marker == "rw"
          sname = fname + "="
          if !w_class[:methods].has_key?(sname)
            writer = {rt: :method, name: sname, params: [Tungsten:AST:Param.new("value", nil, false)], body: [Tungsten:AST:Assign.new(Tungsten:AST:Ivar.new("@" + fname), Tungsten:AST:Var.new("value"))], w_class: w_class}
            register_instance_method(w_class, writer)
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
    if w_class[:data_fields] == nil
      w_class[:data_fields] = {}
    layout[:fields].each -> (f)
      fname = f[:name]
      if fname != nil
        w_class[:data_fields][fname] = f[:type]
        # BigInt's view mirrors the C WBigint header purely for internal
        # `$field` reads/writes; its raw signed limb count must not leak as
        # a public `size` accessor (Int exposes no such method, and duck-
        # typed `.size` callers would silently get limb counts). Layout
        # registration above still happens, so `$size` keeps working.
        # Mirrors the compiled suppression in lowering/definitions.w.
        if w_class[:name] != "BigInt" && !w_class[:methods].has_key?(fname)
          accessor = {rt: :method, name: fname, params: [], body: [Tungsten:AST:Ivar.new("@" + fname)], w_class: w_class, data_field: true}
          register_instance_method(w_class, accessor)

  -> eval_method_def(node, env)
    s = current_self()
    if s != nil && type(s) == "Hash" && s.has_key?(:rt) && s[:rt] == :object
      w_method = {rt: :method, name: ast_get(node, :name), params: ast_get(node, :params), body: ast_get(node, :body), w_class: s[:w_class], param_types: ast_get(node, :param_types)}
      register_instance_method(s[:w_class], w_method)
    else
      w_method = {rt: :method, name: ast_get(node, :name), params: ast_get(node, :params), body: ast_get(node, :body), param_types: ast_get(node, :param_types)}
      register_global_method(w_method)
    ast_get(node, :name)

  # `fn name(args) ...` — pure/memoized at compile time; the tree-walker
  # registers the same global method table entry as `-> name` without memo
  # tables (correct results; memo is an optimization, not a semantic require).
  -> eval_fn_def(node, env)
    w_method = {rt: :method, name: ast_get(node, :name), params: ast_get(node, :params), body: ast_get(node, :body), param_types: ast_get(node, :param_types)}
    register_global_method(w_method)
    ast_get(node, :name)

  # `with i in 1..3` / `parallel_with` — bind each range (or array) element and
  # run the body. Nested bindings form nested loops (outer → inner).
  -> eval_with(node, env)
    bindings = ast_get(node, :bindings)
    body = ast_get(node, :body)
    if bindings == nil || bindings.size() == 0
      return evaluate_body(body, env)
    eval_with_bindings(bindings, 0, body, env)

  -> eval_with_bindings(bindings, index, body, env)
    if index >= bindings.size()
      return evaluate_body(body, env)
    binding = bindings[index]
    var_node = binding[0]
    collection = binding[1]
    name = ast_get(var_node, :name)
    last = nil
    # Range form
    if is_ast_node?(collection) && ast_kind(collection) == :range
      from_v = evaluate(ast_get(collection, :from), env)
      exclusive = ast_get(collection, :exclusive) == true
      to_node = ast_get(collection, :to)
      if to_node == nil
        # Right-unbounded: iterate until break
        i = from_v
        while true
          env.set(name, i)
          begin
            last = eval_with_bindings(bindings, index + 1, body, env)
          rescue err
            if err == "__SIGNAL__" && @signal[:type] == :break
              @signal[:type] = nil
              return @signal[:value]
            if err == "__SIGNAL__" && @signal[:type] == :next
              @signal[:type] = nil
              i += 1
              next
            raise err
          i += 1
        return last
      to_v = evaluate(to_node, env)
      i = from_v
      while (exclusive && i < to_v) || (!exclusive && i <= to_v)
        env.set(name, i)
        begin
          last = eval_with_bindings(bindings, index + 1, body, env)
        rescue err
          if err == "__SIGNAL__" && @signal[:type] == :break
            @signal[:type] = nil
            return @signal[:value]
          if err == "__SIGNAL__" && @signal[:type] == :next
            @signal[:type] = nil
            i += 1
            next
          raise err
        i += 1
      return last
    # Evaluated range object or array
    coll = evaluate(collection, env)
    if type(coll) == "Hash" && coll.has_key?(:rt) && coll[:rt] == :range
      from_v = coll[:from]
      to_v = coll[:to]
      exclusive = coll[:exclusive] == true
      if to_v == nil
        i = from_v
        while true
          env.set(name, i)
          begin
            last = eval_with_bindings(bindings, index + 1, body, env)
          rescue err
            if err == "__SIGNAL__" && @signal[:type] == :break
              @signal[:type] = nil
              return @signal[:value]
            if err == "__SIGNAL__" && @signal[:type] == :next
              @signal[:type] = nil
              i += 1
              next
            raise err
          i += 1
        return last
      i = from_v
      while (exclusive && i < to_v) || (!exclusive && i <= to_v)
        env.set(name, i)
        begin
          last = eval_with_bindings(bindings, index + 1, body, env)
        rescue err
          if err == "__SIGNAL__" && @signal[:type] == :break
            @signal[:type] = nil
            return @signal[:value]
          if err == "__SIGNAL__" && @signal[:type] == :next
            @signal[:type] = nil
            i += 1
            next
          raise err
        i += 1
      return last
    # Array / enumerable
    items = coll
    if type(items) != "Array"
      raise "with: expected range or array"
    j = 0
    while j < items.size()
      env.set(name, items[j])
      begin
        last = eval_with_bindings(bindings, index + 1, body, env)
      rescue err
        if err == "__SIGNAL__" && @signal[:type] == :break
          @signal[:type] = nil
          return @signal[:value]
        if err == "__SIGNAL__" && @signal[:type] == :next
          @signal[:type] = nil
          j += 1
          next
        raise err
      j += 1
    last

  # Duration literal (`2h30m`, `500ms`) → runtime Duration WValue.
  -> eval_duration(node)
    raw = "" + ast_get(node, :raw).to_s()
    parsed = interp_parse_duration(raw)
    if parsed[:mode] == 0
      return ccall("w_duration_ns", parsed[:ns])
    ccall("w_duration_months_ms", parsed[:months], parsed[:ms])

  # Mirror of lowering/literals.w parse_duration — kept local so the
  # interpreter does not depend on the lowering chain.
  -> interp_parse_duration(raw)
    total_months = 0
    total_ms = 0
    total_ns = 0
    has_calendar = false
    has_ns = false
    pos = 0
    chars = raw.chars()
    while pos < chars.size()
      num_str = ""
      while pos < chars.size() && chars[pos] >= "0" && chars[pos] <= "9"
        num_str += chars[pos]
        pos += 1
      num = num_str.to_i()
      if pos + 1 < chars.size() && chars[pos] == "m" && chars[pos + 1] == "o"
        total_months += num
        has_calendar = true
        pos += 2
      elsif pos + 1 < chars.size() && chars[pos] == "m" && chars[pos + 1] == "s"
        total_ms += num
        pos += 2
      elsif pos + 1 < chars.size() && chars[pos] == "n" && chars[pos + 1] == "s"
        total_ns += num
        has_ns = true
        pos += 2
      elsif pos < chars.size() && chars[pos] == "y"
        total_months += num * 12
        has_calendar = true
        pos += 1
      elsif pos < chars.size() && chars[pos] == "w"
        total_ms += num * 7 * 24 * 3600 * 1000
        pos += 1
      elsif pos < chars.size() && chars[pos] == "d"
        total_ms += num * 24 * 3600 * 1000
        pos += 1
      elsif pos < chars.size() && chars[pos] == "h"
        total_ms += num * 3600 * 1000
        pos += 1
      elsif pos < chars.size() && chars[pos] == "m"
        total_ms += num * 60 * 1000
        pos += 1
      elsif pos < chars.size() && chars[pos] == "s"
        total_ms += num * 1000
        pos += 1
      else
        raise "Invalid duration unit in '[raw]'"
    if has_calendar || (!has_ns && total_ms > 0)
      return {mode: 1, months: total_months, ms: total_ms}
    if has_ns || total_ns > 0
      return {mode: 0, ns: total_ns + total_ms * 1000000}
    {mode: 1, months: 0, ms: total_ms}

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
    # Packed scalar facades cannot be represented by the ordinary Hash-backed
    # object allocator below. Date's source class method normally returns its
    # validated packed value before this point; reaching instantiate means the
    # call did not match that one-to-seven-argument contract. Decimal remains
    # intentionally without a generic scalar constructor.
    if w_class[:name] == "Date"
      raise "Date.new expects one to seven arguments"
    if w_class[:name] == "Decimal"
      raise "Decimal.new is not a supported scalar constructor; use a decimal literal or String#to_d"
    if w_class[:name] == "Rational"
      if args.size() < 1 || args.size() > 2
        raise "Rational.new expects one or two arguments"
      denominator = args.size() == 2 ? args[1] : 1
      return ccall("w_rational_new", args[0], denominator)
    if w_class[:name] == "Array"
      if args.size() > 2
        raise "Array.new expects zero, one, or two arguments"
      size = args.size() > 0 ? args[0] : 0
      fill = args.size() > 1 ? args[1] : nil
      return ccall("w_array_new_filled", size, fill)
    if w_class[:name] == "SmallArray"
      if args.size() != 2
        raise "SmallArray.new expects element type and size"
      return ccall("w_small_array_new_value", args[0], args[1])
    # ByteArray/BoolArray are Array facades whose `.new` the compiled
    # engine intercepts in runtime dispatch (WArray with ebits=8/1). The
    # scaffold classes define no `-> new`, so without this arm the tree
    # walker raised "no constructor accepts 1 argument(s)". Both C fns
    # take a RAW int64 length — marshal like eval_typed_array_new does
    # (a boxed int truncates into a bogus cap/size).
    if w_class[:name] == "ByteArray"
      bn = args.size() > 0 ? args[0] : 0
      bn_raw = ccall_nobox("w_numeric_to_i64", bn) ## i64
      return ccall_rawargs("w_bytes_new", bn_raw)
    if w_class[:name] == "BoolArray"
      bn = args.size() > 0 ? args[0] : 0
      bn_raw = ccall_nobox("w_numeric_to_i64", bn) ## i64
      return ccall_rawargs("w_bool_array_new", bn_raw)
    obj = {rt: :object, w_class: w_class, ivars: {}}
    if w_class[:active_type_args] != nil
      obj[:type_args] = w_class[:active_type_args]
    # Arity-aware constructor selection: overloaded `-> new` definitions must
    # resolve like the compiled engine (exact name+arity first, then the
    # name-only fallback) — the bare name-only lookup returned the LAST
    # registration and nil-padded its missing parameters.
    constructor = lookup_method(w_class, "new", args.size(), false, args)
    if constructor != nil
      call_w_method(obj, constructor, args, nil, env)
    elsif args != nil && args.size() > 0
      # Mirrors the runtime's constructor check (w_method_dispatch `new`
      # arm): arguments with no constructor to receive them used to be
      # dropped, leaving every field unset so the mistake surfaced later as
      # a nil field read. `-> new(...)` is the constructor (spec 5.3.1).
      raise w_class[:name].to_s() + ".new: no constructor accepts " + args.size().to_s() + " argument(s). Define `-> new(@field)` on " + w_class[:name].to_s() + " -- `init`/`initialize` are not constructor hooks in Tungsten, and `ro :field` / `- data` declarations do not generate a constructor."
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
    constructor = lookup_method(super_class, "new", args.size(), false, args)
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

    source = path == nil ? nil : read_file(path)
    # An unresolvable/unreadable use crashed as parse_source(nil) with no
    # location — raise a real error naming what failed to resolve and from
    # where instead.
    if source == nil
      shown = path == nil ? "(unresolved)" : path
      from = @current_file == nil ? "top level" : @current_file
      raise "use: cannot load '" + ast_get(node, :path) + "' (resolved to " + shown + ", from " + from + ")"
    prev_file = @current_file
    @current_file = path
    begin
      ast = parse_source(source)
      execute_program(ast)
    ensure
      @current_file = prev_file

  -> resolve_use_path(use_path, base_dir)
    # `core/` prefix: resolves against the NEAREST ancestor that actually
    # carries the requested core file — the interpreter twin of loader.w's
    # find_core_root nearest-ancestor rule. The old single-candidate form
    # asked find_use_project_root (shallowest Bitfile), which from a bit's
    # lib dir returns the BIT root; a bit module reached via a ../..
    # relative use then failed to resolve `use core/mmap` even though the
    # project root's core/ was right there on the ancestry.
    if use_path.starts_with?("core/")
      if base_dir != ""
        cparts = base_dir.split("/")
        ci = cparts.size()
        while ci > 0
          core_candidate = cparts[0...ci].join("/") + "/" + use_path + ".w"
          if read_file(core_candidate) != nil
            return core_candidate
          ci -= 1
      cwd_candidate = use_path + ".w"
      if read_file(cwd_candidate) != nil
        return cwd_candidate
      # Install-root fallback (main's find_use_core_root carried this):
      # a .w run from outside any checkout still finds the installed core.
      troot = env("TUNGSTEN_ROOT")
      if troot != nil && troot != ""
        root_candidate = troot + "/" + use_path + ".w"
        if read_file(root_candidate) != nil
          return root_candidate

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

    # Same order as loader.w: vendor/bits (bit install) → BIT_HOME → bits/
    project_root = find_use_project_root(base_dir)
    if project_root != ""
      found = resolve_use_bit(bit_name, sub_path, project_root + "/vendor/bits", project_root)
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
      found = resolve_use_bit(bit_name, sub_path, bit_home, project_root)
      if found != nil
        return found

    if project_root != ""
      found = resolve_use_bit(bit_name, sub_path, project_root + "/bits", project_root)
      if found != nil
        return found

    # Standard library: project_root/core/<path>.w first, then
    # project_root/lib/<path>.w for backward compat during migration.
    if project_root != ""
      core_candidate = project_root + "/core/" + use_path + ".w"
      if read_file(core_candidate) != nil
        return core_candidate
      lib_candidate = project_root + "/lib/" + use_path + ".w"
      if read_file(lib_candidate) != nil
        return lib_candidate

    # Standard library anchored on the install root rather than the caller's
    # ancestry. `find_use_project_root` is Bitfile-anchored, so it is "" for
    # any program outside a Tungsten project -- a script in ~/math, say -- and
    # then every stdlib branch above is skipped, resolution falls through to a
    # nonexistent sibling path, and read_file returns nil. The failure only
    # surfaces later in parse_source/strip_bash_shebang as
    # `undefined method 'starts_with?' for nil`.
    core_root = find_use_core_root(base_dir)
    if core_root != "" && core_root != project_root
      core_candidate = core_root + "/core/" + use_path + ".w"
      if read_file(core_candidate) != nil
        return core_candidate
      lib_candidate = core_root + "/lib/" + use_path + ".w"
      if read_file(lib_candidate) != nil
        return lib_candidate

    path

  -> use_bit_lock_fields(line)
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

  -> locked_use_bit_version(bit_name, project_root)
    if project_root == nil || project_root == ""
      return nil
    source = read_file(project_root + "/Bitfile.lock")
    if source == nil
      return nil
    lines = source.split("\n")
    i = 0
    while i < lines.size()
      line = lines[i].strip()
      if line.starts_with?("bit ") || line.starts_with?("dependency ")
        fields = use_bit_lock_fields(line)
        if fields.size() == 2
          locked_name = fields[0]
          if locked_name == bit_name || locked_name == "tungsten-" + bit_name
            version = fields[1]
            if version != "" && version.index("/") == nil && version != "." && version != ".."
              return version
      i += 1
    nil

  -> resolve_use_bit_package(package_dir, bit_name, sub_path, entry_file)
    candidate = package_dir + "/lib/" + entry_file
    if read_file(candidate) != nil
      return candidate
    if sub_path != ""
      namespace = bit_name.replace("tungsten-", "")
      candidate = package_dir + "/lib/" + namespace + "/" + sub_path + ".w"
      if read_file(candidate) != nil
        return candidate
    nil

  -> resolve_use_bit(bit_name, sub_path, bit_home, project_root = "")
    if sub_path == ""
      entry_file = bit_name.replace("tungsten-", "") + ".w"
    else
      entry_file = sub_path + ".w"

    locked_version = locked_use_bit_version(bit_name, project_root)
    package_names = [bit_name]
    if !bit_name.starts_with?("tungsten-")
      package_names.push("tungsten-" + bit_name)
    i = 0
    while i < package_names.size()
      package_root = bit_home + "/" + package_names[i]
      if locked_version != nil
        found = resolve_use_bit_package(package_root + "/" + locked_version, bit_name, sub_path, entry_file)
        if found != nil
          return found
      found = resolve_use_bit_package(package_root + "/current", bit_name, sub_path, entry_file)
      if found != nil
        return found
      i += 1

    if bit_name.starts_with?("tungsten-")
      candidate = bit_home + "/" + bit_name + "/lib/" + entry_file
      if read_file(candidate) != nil
        return candidate
      if sub_path != ""
        namespace = bit_name.replace("tungsten-", "")
        candidate = bit_home + "/" + bit_name + "/lib/" + namespace + "/" + sub_path + ".w"
        if read_file(candidate) != nil
          return candidate

    exact = bit_home + "/" + bit_name + "/lib/" + entry_file
    if read_file(exact) != nil
      return exact
    if sub_path != ""
      namespace = bit_name.replace("tungsten-", "")
      namespaced = bit_home + "/" + bit_name + "/lib/" + namespace + "/" + sub_path + ".w"
      if read_file(namespaced) != nil
        return namespaced
    prefixed = bit_home + "/tungsten-" + bit_name + "/lib/" + entry_file
    if read_file(prefixed) != nil
      return prefixed
    if sub_path != ""
      namespaced = bit_home + "/tungsten-" + bit_name + "/lib/" + bit_name + "/" + sub_path + ".w"
      if read_file(namespaced) != nil
        return namespaced
    nil

  # Anchored on core/tungsten.w (the stdlib marker) rather than a Bitfile, and
  # carrying the install-root fallback that bin/tungsten exports as
  # TUNGSTEN_ROOT. Mirrors loader.w:find_core_root so the interpreter and the
  # compiled loader resolve the standard library identically: local project
  # files against the program's own root, core files against the install root.
  -> find_use_core_root(dir)
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
    root = env("TUNGSTEN_ROOT")
    if root != nil && root != ""
      if file?(root + "/core/tungsten.w")
        return root
    ""

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

  # Spec 4.6.5: evaluate the body; a raised error binds/runs the rescue
  # clause if present; the ensure body runs whether the body completed, was
  # rescued, raised unrescued, or was exited by a control signal — and an
  # unrescued error (or signal) propagates AFTER ensure. The pending-error
  # shape keeps the re-raise outside this frame's own rescue.
  # Raise a typed error object (a core Error subclass) the way `raise Cls,
  # msg` does, so `rescue e: Cls` can select it; when the class is not
  # available the message string is raised alone, as before.
  -> raise_typed(class_name, msg)
    if try_autoload_class(class_name) && @classes.has_key?(class_name)
      @raised_value = construct_error(class_name, msg)
      @raised_message = msg
    raise msg

  # `Cls.new(msg)` evaluated exactly as `raise Cls, msg` evaluates it — the
  # ordinary call path binds `self` for the constructor and accessors; a
  # direct instantiate() from here left the message ivar unreadable.
  -> construct_error(class_name, msg)
    obj = {rt: :object, w_class: @classes[class_name], ivars: {}}
    obj[:ivars]["@message"] = msg
    obj

  # The compiled runtime raises "ClassName: message" strings when the typed
  # class is not linked into this binary (w_raise_error_named); the
  # interpreter can still build the named core class for the interpreted
  # program. Returns the typed object, or nil when the message is not a
  # tagged core error.
  -> typed_runtime_error(message)
    if type(message) != "String"
      return mirror_compiled_error(message)
    idx = message.index(": ")
    if idx == nil || idx <= 0
      return nil
    class_name = message.slice(0, idx)
    if autoload_registry()[class_name] == nil
      return nil
    if !try_autoload_class(class_name) || !@classes.has_key?(class_name)
      return nil
    construct_error(class_name, message.slice(idx + 2, message.size() - idx - 2))

  # When this binary links the core error classes (any program with a
  # handler does, and the compiler is one), the runtime raises a COMPILED
  # instance. Interpreted accessors cannot run against a compiled object, so
  # mirror it as an interpreted instance of the same core class, carrying
  # the message read through runtime dispatch. Anything that is not an
  # Exception descendant is returned unchanged.
  -> mirror_compiled_error(value)
    class_name = "" + type(value).to_s()
    if autoload_registry()[class_name] == nil
      return nil
    if !try_autoload_class(class_name) || !@classes.has_key?(class_name)
      return nil
    if !interpreted_class_descends_from?(@classes[class_name], "Exception")
      return nil
    construct_error(class_name, ccall("w_method_call", value, "message", []))

  -> interpreted_class_descends_from?(w_class, ancestor_name)
    cur = w_class
    guard = 0
    while cur != nil && guard < 64
      if cur[:name] == ancestor_name
        return true
      cur = cur[:superclass]
      guard += 1
    false

  -> eval_begin(node, env)
    result = nil
    pending = nil
    begin
      result = evaluate_body(ast_get(node, :body), env)
    rescue err
      if err == "__SIGNAL__"
        pending = err
      elsif ast_get(node, :rescue_body) != nil
        # Bind the raised VALUE when this message matches the most recent
        # user-level raise (error objects survive rescue); otherwise the
        # host message string is all there is — unless it is a tagged core
        # error from the runtime, which becomes the named class here.
        bound = err
        if @raised_value != nil && @raised_message == err
          bound = @raised_value
        else
          typed = typed_runtime_error(err)
          if typed != nil
            bound = typed
        @raised_value = nil
        @raised_message = nil
        if ast_get(node, :rescue_var) != nil
          env.set(ast_get(node, :rescue_var), bound)
        begin
          result = evaluate_body(ast_get(node, :rescue_body), env)
        rescue err2
          # The rescue clause itself raised (or signaled): ensure still
          # runs, then the new error propagates.
          pending = err2
      else
        pending = err
    if ast_get(node, :ensure_body) != nil
      evaluate_body(ast_get(node, :ensure_body), env)
    if pending != nil
      raise pending
    result

  # Postfix `expr rescue fallback` (:rescue_expr) — the single-expression
  # form of begin/rescue. Mirrors eval_begin's rescue arm: errors select the
  # fallback expression; control-flow signals (return/break/next) tunnel
  # through the host raise and must not be swallowed.
  -> eval_rescue_expr(node, env)
    result = nil
    pending = nil
    caught = false
    begin
      result = evaluate(ast_get(node, :body), env)
    rescue err
      if err == "__SIGNAL__"
        pending = err
      else
        caught = true
        @raised_value = nil
        @raised_message = nil
    if pending != nil
      raise pending
    if caught
      result = evaluate(ast_get(node, :fallback), env)
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
    # A call-site kwargs group carries the runtime kwargs mark so
    # call_w_method can rebind declared keyword params by name — the
    # same W_HASH_FLAG_KWARGS protocol the compiled engine uses
    # (literals.w mark + w_kwargs_remap12 prologue).
    if ast_get(node, :from_kwargs) == true
      ccall("w_hash_mark_kwargs", result)
    result

  # `bool[N]` / `i32[N]` / etc. — zero-filled typed array. Mirrors
  # lower_typed_array_new (compiler/lib/lowering/literals.w): known element
  # types, including bit-packed bool, route to the generic bits-keyed
  # zero-fill; anything else raises — mirroring the compiled engine's
  # E_LOWER_TYPED_ARRAY_UNSUPPORTED.
  -> eval_typed_array_new(node, env)
    etype = ast_get(node, :element_type)
    size = evaluate(ast_get(node, :size), env)
    size_raw = ccall_nobox("w_numeric_to_i64", size) ## i64
    bits = 0 ## i64
    if etype == "bool" || etype == "u1" || etype == "i1"
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
    elsif etype == "u32"
      bits = 32
    elsif etype == "i32"
      bits = 33
    elsif etype == "u64"
      bits = 64
    elsif etype == "i64"
      bits = 66
    elsif etype == "f32"
      bits = 0 - 32
    elsif etype == "f16"
      bits = 0 - 16
    elsif etype == "bf16"
      bits = 0 - 116
    elsif etype == "w64"
      bits = 65
    elsif etype == "f64"
      bits = 0 - 64
    if bits != 0
      return ccall_rawargs("w_array_zeros", bits, size_raw)
    raise "typed array element type '" + etype + "' is not supported yet (supported: u1/i1/u4/i4/u8/i8/u16/i16/u32/i32/u64/i64/f16/f32/f64/bf16/w64/bool)"

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
    # String/Symbol share compiled method dispatch but retain distinct public
    # primitive identities. Resolve their exact class/string targets without
    # autoloading the legacy Symbol scaffold.
    primitive_name = type(recv)
    if primitive_name in ("String" "Symbol")
      target_name = klass
      if type(klass) == "Hash" && klass.has_key?(:rt) && klass[:rt] == :class
        target_name = klass[:name]
      return primitive_name == target_name
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
