# Lowering / assign — variables and assignment: var/gvar reads, the
# assignment-expression lowerer (with closure/range binding elision
# from elision.w), multi-assign, and safe navigation.
#
# This file deliberately has no `use` directives — see pass_registry.w
# for the rationale (path resolution from compiler/lib/lowering/).

-> source_constructor_returns_exact_class?(mod, class_name)
  current = class_name
  guard = 0
  while current != nil && guard < 64
    # A static `.new` may return any value. Ordinary instance `new` methods are
    # initializers invoked only after the runtime allocates the requested class.
    if mod[:class_static_new][current] == true
      return false
    current = mod[:class_super_names][current]
    guard += 1
  true

# -- Variables --

# Ruby-style namespace walk-up for an unqualified class reference.
# `enclosing` is the fully-qualified name of the class (or namespace
# path) the reference sits inside, e.g. "Tungsten:Bit:Commands:Help".
# Drop the trailing simple name to recover the namespace, then look for
# `<ns>:name`, `<parent-ns>:name`, … in mod[:known_classes], returning
# the first qualified match (nil if none). This mirrors the parser's
# same-file superclass walk-up (parser.w) but resolves ACROSS files,
# because mod[:known_classes] is module-global by the time lowering
# runs. First-declaration wins; unmatched names return nil so the
# caller falls through to its existing behavior.
-> resolve_class_in_namespace(mod, enclosing, name)
  if enclosing == nil
    return nil
  segments = enclosing.split(":")
  segments.pop()
  while segments.size() > 0
    candidate = segments.join(":") + ":" + name
    if mod[:known_classes][candidate] != nil
      return candidate
    segments.pop()
  nil

# Bit constant alias expansion (`constant_alias "WC"` in a bit's entry
# file). A registered alias is a straight first-segment substitution —
# `WC:Route` → `Tungsten:Carbide:Route` — no suffix matching and no
# namespace walking. Unqualified names and unregistered heads return nil
# so callers fall through to their existing behavior.
-> constant_alias_expand(mod, name)
  aliases = mod[:constant_aliases]
  if aliases == nil || aliases.size() == 0
    return nil
  c = name.index(":")
  if c == nil
    return nil
  target = aliases[name.slice(0, c)]
  if target == nil
    return nil
  target + name.slice(c, name.size() - c)

# A bare identifier in an instance-method body is ambiguous between an
# implicit `self.name()` call and one of Tungsten's module-scope bindings.
# Top-level bindings are predeclared before method bodies are lowered so
# functions may read globals initialized later. That prepass must not,
# however, retroactively capture a method that is already part of the
# receiver's class hierarchy:
#
#   -> normalize(x)
#     equal?(x, zero)
#   ...
#   zero = some_unrelated_value
#
# The interpreter resolves `zero` as a method when normalize runs before the
# later assignment. Prefer a statically-known instance method here; unknown
# names retain the existing top-level-global behavior. The hierarchy walk is
# also required for ordinary inherited helpers.
-> class_has_instance_method?(mod, class_name, method_name)
  if class_name == nil || mod[:class_method_asts] == nil
    return false
  current = class_name
  guard = 0
  while current != nil && guard < 64
    if mod[:class_method_asts][current + "." + method_name] != nil
      return true
    supers = mod[:class_super_names]
    current = supers == nil ? nil : supers[current]
    guard += 1
  false

-> lower_implicit_self_bare_method(ctx, name)
  wfn = ctx[:func]
  self_val = lower_var(ctx, Tungsten:AST:Var.new("__self"))
  self_reg = ensure_i64_value(wfn, self_val)
  method_name_tv = lower_string(ctx, Tungsten:AST:String.new(name))
  method_name_val = ensure_i64_value(wfn, method_name_tv)
  temp_args = next_temp(wfn)
  temp = next_temp(wfn)
  ic_id = ctx[:mod][:next_ic]
  ctx[:mod][:next_ic] = ic_id + 1
  emit_instruction(wfn, {
    op: :call_method_i64,
    temp: temp,
    temp_args_val: temp_args,
    receiver: self_reg,
    method_name_val: method_name_val,
    args: [],
    ic_id: ic_id
  })
  typed_value(:i64, temp)

# Materialize all temp bindings to var slots. Called before control flow
# (if, while, case, etc.) and closures so that cross-block reads and
# capture analysis find values in var_slots.
-> builtin_math_constant_text(name)
  case name
  when "π"
    return "3.141592653589793"
  when "τ"
    return "6.283185307179586"
  when "ϕ", "φ"
    return "1.618033988749895"
  when "ℯ"
    return "2.718281828459045"
  when "ℇ"
    return "0.5772156649015329"
  nil

-> lower_var(ctx, node)
  name = node.name
  wfn = ctx[:func]

  # Bare zero-argument block-presence query. This must precede ordinary
  # function/implicit-self lookup: the parser represents `block?` as :var.
  if name in ("block?" "block_given?")
    return lower_block_present(ctx)

  # Build-time defines (`bin/tungsten -D NAME=VALUE`) win over any other
  # binding. Emit the corresponding nanboxed i64 literal directly so the
  # value is a compile-time constant — `if FAST_MATH` after substitution
  # becomes `if w_true` (a literal i64), which LLVM's SimplifyCFG passes
  # fold into an unconditional branch with no global load.
  #
  # Value parsing order:
  #   "true" / "false"   → boolean (w_true / w_false)
  #   /^-?[0-9]+$/       → integer (w_int(N))
  #   "..." / '...'      → string (quotes stripped)
  #   anything else      → string (raw token, e.g. -D BACKEND=metal)
  define_val = ctx[:mod][:build_defines][name]
  if define_val != nil
    if define_val == "true"
      return typed_value(:i64, w_true.to_s())
    if define_val == "false"
      return typed_value(:i64, w_false.to_s())
    if build_define_is_int?(define_val)
      # Construct the nanboxed i64 literal directly: w_tag_int (0xFFFA...) ORed
      # with the i48 payload. No w_int() helper exists at compile time — the
      # runtime symbol is C-only. Mirrors lower_build_define_string's SSO-5
      # construction, just with the int tag instead of the string tag.
      bits = (w_tag_int + define_val.to_i()) ## i64
      return typed_value(:i64, wvalue_literal_text(machine_i64_box(bits)))
    # String: strip optional surrounding quotes (shell may or may not have
    # stripped them, depending on how the user quoted on the CLI).
    str_val = define_val
    if str_val.size() >= 2
      first = str_val.slice(0, 1)
      last = str_val.slice(str_val.size() - 1, 1)
      if first == "\"" && last == "\""
        str_val = str_val.slice(1, str_val.size() - 2)
      elsif first == "'" && last == "'"
        str_val = str_val.slice(1, str_val.size() - 2)
    return lower_build_define_string(ctx, str_val)

  # Bare `class` inside a method body resolves to the class, so the
  # constructor pattern `class.new(args)` produces an instance of the
  # receiver's concrete class regardless of which specialization is active
  # (Quaternion$f32, Quaternion$f64, …). In an INSTANCE method `__self` is
  # an instance, so `class` is its runtime class via w_class_of. In a CLASS
  # method `__self` IS already the class — taking w_class_of there would
  # yield the metaclass, so `class.new` (e.g. Mat3.identity / Mat3.zero)
  # would build a `Class`, not a `Mat3`. Gated on `method_name != nil` to
  # avoid clobbering top-level contexts where `class` is a dispatch target.
  if name == "class" && ctx[:class_name] != nil && ctx[:method_name] != nil
    if ctx[:is_class_method] == true
      # __self IS the class here. Reference the parameter directly rather
      # than routing through lower_var("__self"): a captured __self gets a
      # var-slot/binding whose load can land in a different basic block,
      # leaving a dangling SSA ref at the call site (seen in dead, never-
      # instantiated template static methods). The entry param dominates
      # every block, so it's always valid.
      return typed_value(:i64, "%__self")
    self_tv = lower_expression(ctx, Tungsten:AST:Var.new("__self"))
    self_reg = ensure_i64_value(wfn, self_tv)
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_class_of", args: [self_reg]})
    return typed_value(:i64, temp)

  # Bare `$field` inside a class method is a view-field
  # access on `self`. The lexer emits `$<name>` as a :GLOBAL token which
  # the parser turns into `Tungsten:AST:Var.new("$field")`. Resolve here
  # by looking the bare name up in the class's view_layouts and routing
  # to lower_view_field. Without this, $size etc. fall through to method
  # dispatch and fail at runtime with "undefined method '$size'".
  if name.starts_with?("$") && ctx[:class_name] != nil
    field = name.slice(1, name.size() - 1)
    # $value is the bare 64-bit content of self — works for any class,
    # not just classes with a heap view layout. Tag the result as
    # :raw_i64 so subsequent `>>` / `&` lower to raw machine ops rather
    # than dispatch through the receiver's tag class.
    if field == "value"
      self_tv = lower_var(ctx, Tungsten:AST:Var.new("__self"))
      self_reg = ensure_i64_value(wfn, self_tv)
      return typed_value(:raw_i64, self_reg)
    info = view_field_info(ctx, field)
    if info != nil
      return lower_view_field(ctx, Tungsten:AST:ViewField.new(field))

  raw_type = ctx[:var_types][name]
  machine_int = is_raw_int_storage_type(raw_type)
  machine_float = is_machine_float_type(raw_type)
  top_level_raw_type = nil
  if ctx[:mod][:top_level_var_types] != nil
    top_level_raw_type = ctx[:mod][:top_level_var_types][name]

  # Unboxed loop variable: load raw, return as :raw_i64. As of
  # 2026-04-15: must be :raw_i64, NOT :raw_int, because under
  # silent-wrap native arithmetic the accumulated value can exceed
  # the 48-bit nanbox payload range. :raw_i64 routes boundary-crossing
  # boxing through w_int (bigint-safe), while :raw_int would mask to
  # 48 bits and produce garbage for sums like 0..99999999.
  if ctx[:unboxed_vars] != nil && ctx[:unboxed_vars][name] != nil
    raw_slot = ctx[:unboxed_vars][name]
    raw = next_temp(wfn)
    emit_instruction(wfn, {op: :load_i64, temp: raw, ptr: raw_slot})
    return typed_value(:raw_i64, raw)


  # Check var slot before bindings/parameters — once a name is materialized, the slot
  # becomes the source of truth (important for reassigned params with defaults).
  ptr = wfn[:var_slots][name]
  if ptr != nil
    temp = next_temp(wfn)
    load_op = :load_i64
    if machine_int
      load_op = machine_load_op(raw_type)
    elsif machine_float
      load_op = float_load_op(raw_type)
    emit_instruction(wfn, {op: load_op, temp: temp, ptr: ptr})
    if machine_int
      return typed_value(raw_machine_value_type(raw_type), temp)
    if machine_float
      return typed_value(raw_float_value_type(raw_type), temp)
    return typed_value(:i64, temp)

  # Check temp bindings next (covers default-param overrides and register renames)
  binding = ctx[:bindings][name]
  if binding != nil
    if machine_int
      return typed_value(raw_machine_value_type(raw_type), binding)
    if machine_float
      return typed_value(raw_float_value_type(raw_type), binding)
    return typed_value(:i64, binding)

  # Check if it's a parameter (directly available as %name)
  i = 0
  while i < wfn[:params].size()
    if wfn[:params][i] == name
      if machine_int
        # Raw-ABI fns (raw_i64_signature) receive machine-int params as raw
        # bits, not nanboxed WValues. When the entry binding for such a param
        # has been dropped (e.g. materialize_bindings / loop-end binding reset
        # inside a `loop`/`while true` body), reading it must reconstruct the
        # RAW param register directly — applying w_to_i64 to a raw pointer or
        # int corrupts it ("expected int, got object"). Boxed-ABI fns keep the
        # nanunbox path below.
        if wfn[:raw_i64_signature] == true
          return typed_value(raw_machine_value_type(raw_type), cast_raw_machine_int(wfn, "%" + llvm_safe_name(name), :i64, raw_type))
        return typed_value(raw_machine_value_type(raw_type), ensure_raw_machine_int(wfn, typed_value(:i64, "%" + llvm_safe_name(name)), raw_type, raw_type))
      if machine_float
        if raw_type in (:f32 :raw_f32)
          return typed_value(:raw_f32, ensure_raw_f32(wfn, typed_value(:i64, "%" + llvm_safe_name(name))))
        return typed_value(:raw_f64, ensure_raw_f64(wfn, typed_value(:i64, "%" + llvm_safe_name(name))))
      return typed_value(:i64, "%" + llvm_safe_name(name))
    i += 1

  # Check if it's a built-in runtime class
  if mark_builtin_class_used(ctx[:mod], name)
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :load_class, temp: temp, class_name: name})
    return typed_value(:i64, temp)

  # Check if it's a class name (user-defined)
  if ctx[:mod][:known_classes][name] != nil
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :load_class, temp: temp, class_name: name})
    return typed_value(:i64, temp)

  # Bit constant alias: a qualified reference whose first segment is a
  # registered `constant_alias` resolves by substitution — `WC:Route`
  # under `use carbide` loads `Tungsten:Carbide:Route`. Exact lookup
  # only; unmatched names fall through unchanged.
  if name.include?(":")
    aliased = constant_alias_expand(ctx[:mod], name)
    if aliased != nil && ctx[:mod][:known_classes][aliased] != nil
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :load_class, temp: temp, class_name: aliased})
      return typed_value(:i64, temp)

  # Unqualified class reference resolved via the enclosing namespace
  # chain (Ruby-style). A bare `Clean` inside a method of
  # `Tungsten:Bit:Commands:Help` resolves to
  # `Tungsten:Bit:Commands:Clean`; a bare `Bitfile` walks further up to
  # `Tungsten:Bit:Bitfile`. Only reached when the name is not a local,
  # parameter, builtin class, or exact top-level class, so it is purely
  # additive — it rescues references that would otherwise fall through to
  # implicit-self dispatch (and fail) or resolve to nil.
  if !name.include?(":") && ctx[:class_name] != nil
    ns_resolved = resolve_class_in_namespace(ctx[:mod], ctx[:class_name], name)
    if ns_resolved != nil
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :load_class, temp: temp, class_name: ns_resolved})
      return typed_value(:i64, temp)

  # Built-in constants
  if name == "ARGV"
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "__w_argv", args: []})
    return typed_value(:i64, temp)

  # Mathematical constants are ordinary numeric f64 values at the language
  # surface.  Exact symbolic work deliberately uses Expression.pi/e instead.
  constant_text = builtin_math_constant_text(name)
  if constant_text != nil
    return lower_float(ctx, Tungsten:AST:Float.new(constant_text))

  # A declared method on self is lexical to the class and wins over a
  # same-spelled module binding predeclared by the top-level analysis pass.
  if ctx[:class_name] != nil && ctx[:is_class_method] != true
    if class_has_instance_method?(ctx[:mod], ctx[:class_name], name)
      return lower_implicit_self_bare_method(ctx, name)

  # Check if it's a top-level (module-scope) variable
  if ctx[:mod][:top_level_vars][name] == true
    temp = next_temp(wfn)
    # Match the load width to the global's storage width. i128/u128
    # globals (`## u128` / `## i128`) need `load i128`; otherwise the
    # IR is a type-mismatch.
    load_type = "i64"
    if is_machine_int128_type(top_level_raw_type)
      load_type = "i128"
    emit_instruction(wfn, {op: :load_global, temp: temp, name: name, type: load_type})
    if is_raw_int_storage_type(top_level_raw_type)
      return typed_value(raw_machine_value_type(top_level_raw_type), temp)
    if machine_int
      return typed_value(raw_machine_value_type(raw_type), ensure_raw_machine_int(wfn, typed_value(:i64, temp), raw_type, raw_type))
    return typed_value(:i64, temp)

  # Zero-arg function call: bare `greet` → call __w_greet()
  call_target = ctx[:mod][:known_calls][name]
  if call_target != nil
    # The source call has zero positional arguments, but the callee can still
    # own hidden/default slots. In particular `-> probe; block?` has one hidden
    # block slot which must receive nil here; omitting the LLVM argument lets a
    # caller's closure register leak into the nested call.
    call_args = []
    expected = ctx[:mod][:known_fn_param_counts][name]
    if expected != nil
      while call_args.size() < expected
        call_args.push(w_nil.to_s())
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: call_target, args: call_args})
    if call_target == "__w_exit"
      emit_instruction(wfn, {op: :unreachable})
    return typed_value(:i64, temp)

  # Implicit self dispatch: inside a class method, bare `foo` resolves as a
  # direct static call on the current class when such a method is known.
  if ctx[:is_class_method] == true && ctx[:class_name] != nil
    static_key = ctx[:class_name] + "." + name
    static_info = known_static_method_for(ctx[:mod], static_key, 0)
    if static_info != nil && static_info[:arity] == 1
      return lower_direct_static_method_call(ctx, static_info, Tungsten:AST:Self.new, [])

  # Δ-prefixed identifier: an UNDEFINED `Δx` means "my x minus theirs" —
  # it desugars to `x - x'` = `x - @1.x` (prime-notation delta, README's
  # `√(Δx² + Δy² + Δz²)`). A real variable named Δx resolves through the
  # normal paths above; this must sit BEFORE the blind implicit-self
  # dispatch below, which would otherwise claim Δx as self.Δx(). The Δ
  # prefix is therefore reserved: a class method literally named Δx is
  # shadowed by the delta reading.
  if name.starts_with?("Δ") && name.size() > "Δ".size()
    dlen = "Δ".size()
    delta_base = name.slice(dlen, name.size() - dlen)
    delta_node = Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(delta_base), :MINUS, Tungsten:AST:Call.new(Tungsten:AST:Parg.new(1), delta_base, [], nil))
    return lower_expression(ctx, delta_node)

  # Implicit self dispatch: inside a class, bare `foo` resolves as self.foo().
  # This handles accessor methods (ro/rw) and any zero-arg instance method.
  if ctx[:class_name] != nil
    return lower_implicit_self_bare_method(ctx, name)

  # Undefined variable — treat as nil
  typed_value(:i64, w_nil.to_s())

# `$name` — always a real global read (@global.<name>), regardless of
# which function/method body it appears in. Contrast lower_var above,
# which only resolves to load_global once ctx[:mod][:top_level_vars]
# already has the name — true for a direct top-level :var assignment,
# but never for one inside a function/method body (see ast.w's GVar
# doc comment). A :gvar has no such gate: reading $foo unconditionally
# registers it as a global (idempotent — safe even if this read
# happens before any assignment ever runs) and loads it.
-> lower_gvar(ctx, node)
  name = node.name
  wfn = ctx[:func]

  # Preserved from lower_var's original $-prefix
  # handling (predating :gvar as a distinct AST kind): bare `$field`
  # inside a class method with a matching view-field layout is a
  # view-field access on `self`, not a global-variable read. Checked
  # first since it's the narrower case.
  if ctx[:class_name] != nil
    field = name.slice(1, name.size() - 1)
    if field == "value"
      self_tv = lower_var(ctx, Tungsten:AST:Var.new("__self"))
      self_reg = ensure_i64_value(wfn, self_tv)
      return typed_value(:raw_i64, self_reg)
    info = view_field_info(ctx, field)
    if info != nil
      return lower_view_field(ctx, Tungsten:AST:ViewField.new(field))

  ctx[:mod][:top_level_vars][name] = true
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :load_global, temp: temp, name: name, type: "i64"})
  typed_value(:i64, temp)

# Shared write-back for $name = value and $name += value alike (mirrors
# lower_ivar_set_expr's role for @ivar). A matching `$field` in a class with a
# native `- data` layout writes that field on implicit `self`, symmetric with
# lower_gvar's read path. Every other `$name` remains a generic boxed global.
-> lower_gvar_set(ctx, name, val_tv)
  if ctx[:class_name] != nil && name.starts_with?("$")
    field = name.slice(1, name.size() - 1)
    info = view_field_info(ctx, field)
    if info != nil
      return lower_view_field_set(ctx, field, val_tv)

  wfn = ctx[:func]
  val_reg = ensure_i64_value(wfn, val_tv)
  ctx[:mod][:top_level_vars][name] = true
  emit_store_global_unless_const(wfn, ctx, name, val_reg)
  typed_value(:i64, val_reg)

# Word-overwrite destination call spec (E4 stage 3). For a mut-candidate
# `r = a op w` (the syntactic shape shared with the walker's admission arm
# in analysis.w), pick the runtime entry and operand orientation, or nil
# when the boxed-bigint gates fail. Gates mirror the rotation shape's:
# the target must be an explicitly BigInt-typed boxed local (raw-slot-
# promoted or machine-typed vars keep their documented native semantics),
# the base operand a statically BigInt-typed var, and the word side
# anything BUT a BigInt-typed var (both-big spellings keep the guarded
# __w_bigint_*_src route). The word operand is passed BOXED — the entry
# validates the dynamic inline-int/one-limb shape itself.
-> bigint_word_dest_call_spec(ctx, name, v)
  if bigint_word_dest_rhs_shape(v, name) == nil
    return nil
  if !is_bigint_type(ctx[:var_types][name])
    return nil
  if ctx[:unboxed_vars] != nil && ctx[:unboxed_vars][name] != nil
    return nil
  l = v.left
  r = v.right
  lbig = is_ast_node?(l) && ast_kind(l) == :var && is_bigint_type(ctx[:var_types][l.name])
  if lbig && ctx[:unboxed_vars] != nil && ctx[:unboxed_vars][l.name] != nil
    lbig = false
  rbig = is_ast_node?(r) && ast_kind(r) == :var && is_bigint_type(ctx[:var_types][r.name])
  if rbig && ctx[:unboxed_vars] != nil && ctx[:unboxed_vars][r.name] != nil
    rbig = false
  a_node = nil
  w_node = nil
  if lbig && !rbig
    a_node = l
    w_node = r
  elsif rbig && !lbig && v.op in (:PLUS :STAR)
    # commutative ops accept the word on the left (`5 * a`); subtraction
    # keeps strict left orientation (`w - a` is a different operation)
    a_node = r
    w_node = l
  if a_node == nil
    return nil
  entry = "w_bigint_mul_word_dest"
  if v.op == :PLUS
    entry = "w_bigint_add_word_dest"
  elsif v.op == :MINUS
    entry = "w_bigint_sub_word_dest"
  {entry: entry, a: a_node, w: w_node}

-> lower_assign_expr(ctx, node)
  wfn = ctx[:func]
  target = node.target
  # Statement-position marker from lower_statement, consumed immediately so
  # any assign lowered from this one's RHS reads as expression position.
  stmt_position = ctx[:assign_stmt_position] == true
  ctx[:assign_stmt_position] = nil

  # Tag facts: a write to a name voids what the body's entry
  # conditions proved about it. nil-ing the slot is indistinguishable from
  # an absent fact, and every consumer treats absent as "keep the guard",
  # so killing is always safe; seeding never was (see lower_method_def).
  if ctx[:tag_facts] != nil && target != nil && is_ast_node?(target) && ast_kind(target) == :var
    ctx[:tag_facts][target.name] = nil

  # Rotation shape (E4 stage 2, MINUS mirror stage 4): the triple's FIRST
  # statement computes the sum — or, for the descending triple, the
  # difference — into old-a's dying buffer; the two slot-copy statements
  # that follow lower ordinarily. The vars live in slots (the isolation
  # proof admits no bindings-only uses), and the dest entries' runtime
  # guards degrade any dynamic surprise to the allocating op.
  rot = ctx[:rotation_shape]
  if rot != nil && ast_kind(target) == :var && target.name == rot[:t]
    # Boxed accumulators only: raw-i64-promoted vars keep their documented
    # native-wrap semantics (and are faster than any boxed path); firing
    # here would mix a boxed store into raw slot reads.
    # Both source operands must be EXPLICITLY ## big — that is the
    # sanctioned boxed-accumulator opt-in, and precisely the case where
    # the loop pays an allocation per pass. Untyped rotation vars keep
    # the documented raw-slot wrap semantics (faster, and mixing a boxed
    # store into their raw reads corrupted values); t must additionally
    # not be raw/unboxed anywhere.
    rot_boxed = is_bigint_type(ctx[:var_types][rot[:a]]) && is_bigint_type(ctx[:var_types][rot[:b]])
    ttty = ctx[:var_types][rot[:t]]
    if is_machine_int_type(ttty) || ttty in (:raw_int :raw_i64 :raw_u64) || (ctx[:unboxed_vars] != nil && ctx[:unboxed_vars][rot[:t]] != nil)
      rot_boxed = false
    v = node.value
    if rot_boxed && v != nil && is_ast_node?(v) && ast_kind(v) == :binary_op && v.op == rot[:op] && v.op in (:PLUS :MINUS)
      wfn2 = ctx[:func]
      a_tv = lower_expression(ctx, Tungsten:AST:Var.new(rot[:a]))
      b_tv = lower_expression(ctx, Tungsten:AST:Var.new(rot[:b]))
      a_reg = ensure_i64_value(wfn2, a_tv)
      b_reg = ensure_i64_value(wfn2, b_tv)
      dest_temp = next_temp(wfn2)
      # dest = old rot[:a] value; for MINUS the walker pinned rot[:a] as
      # the minuend, so the (dest, x, y) argument shape is identical.
      rot_entry = rot[:op] == :MINUS ? "w_bigint_sub_dest" : "w_bigint_add_dest"
      emit_instruction(wfn2, {op: :call_direct_i64, temp: dest_temp, name: rot_entry, args: [a_reg, a_reg, b_reg]})
      range_binding_invalidate(ctx, rot[:t])
      ctx[:bindings][rot[:t]] = nil
      t_slot = ensure_var_slot(wfn2, rot[:t])
      emit_instruction(wfn2, {op: :store_i64, value: dest_temp, ptr: t_slot})
      return typed_value(:i64, dest_temp)

  # Word-overwrite destination (E4 stage 3): `r = a op w` over a proven-
  # dead candidate hands r's dying OLD value to the dest-taking word entry,
  # which computes into that buffer when the dynamic shape allows. Every
  # guard refusal inside the entry fails open to the ordinary polymorphic
  # op with the dead buffer released — so this site also stops the
  # overwrite-without-release churn the plain emission leaks. The walker's
  # admission arm (analysis.w) guarantees the old value is unaliased-or-
  # shared-marked and that a dominating literal seed initialized the slot.
  if ast_kind(target) == :var && node.type_hint == nil && ctx[:mut_accumulators] != nil && ctx[:mut_accumulators][target.name] == true && node.value != nil && is_ast_node?(node.value)
    wd = bigint_word_dest_call_spec(ctx, target.name, node.value)
    if wd != nil
      wfn3 = ctx[:func]
      wd_name = target.name
      wd_ptr = nil
      wd_old = ctx[:bindings][wd_name]
      if wd_old == nil
        wd_ptr = ensure_var_slot(wfn3, wd_name)
        wd_old = next_temp(wfn3)
        emit_instruction(wfn3, {op: :load_i64, temp: wd_old, ptr: wd_ptr})
      # operands are plain vars/literals (walker leaves), so lowering them
      # cannot materialize bindings or reorder effects
      wd_a_tv = lower_expression(ctx, wd[:a])
      wd_w_tv = lower_expression(ctx, wd[:w])
      wd_a_reg = ensure_i64_value(wfn3, wd_a_tv)
      wd_w_reg = ensure_i64_value(wfn3, wd_w_tv)
      wd_temp = next_temp(wfn3)
      emit_instruction(wfn3, {op: :call_direct_i64, temp: wd_temp, name: wd[:entry], args: [wd_old, wd_a_reg, wd_w_reg], call_conv: "preserve_mostcc"})
      range_binding_invalidate(ctx, wd_name)
      ctx[:bindings][wd_name] = nil
      if wd_ptr == nil
        wd_ptr = ensure_var_slot(wfn3, wd_name)
      emit_instruction(wfn3, {op: :store_i64, value: wd_temp, ptr: wd_ptr})
      return typed_value(:i64, wd_temp)

  # Sum-chunking: inside a qualifying while, this accumulator statement
  # feeds the raw partial instead of touching r at all.
  if ctx[:sum_chunk] != nil && ast_kind(target) == :var && target.name == ctx[:sum_chunk][:var]
    v = node.value
    if v != nil && is_ast_node?(v) && ast_kind(v) == :binary_op && v.op in (:PLUS :MINUS) && v.left != nil && is_ast_node?(v.left) && ast_kind(v.left) == :var && v.left.name == target.name
      return lower_sum_chunk_step(ctx, v.op, v.right)

  # Mutate-if-unique (E4 stage 1): supported `r = r op e` shapes where the
  # accumulator analysis proved r's value dies here routes the guarded
  # arm's runtime fallback through w_bigint_add_mut/w_bigint_sub_mut (see
  # lower_binary_op). Scoped to exactly this assignment's RHS lowering.
  mut_target_set = false
  if ast_kind(target) == :var && ctx[:mut_accumulators] != nil && ctx[:mut_accumulators][target.name] == true
    v = node.value
    if v != nil && is_ast_node?(v) && ast_kind(v) == :binary_op && v.op in (:PLUS :MINUS :STAR :SLASH :PERCENT) && v.left != nil && is_ast_node?(v.left) && ast_kind(v.left) == :var && v.left.name == target.name
      ctx[:mut_accum_target] = target.name
      mut_target_set = true

  # Ivar assignment: @name = value
  if ast_kind(target) == :ivar
    val = lower_expression(ctx, node.value)
    return lower_ivar_set_expr(ctx, target.name, val)

  # Class variable assignment: @@name = value
  if ast_kind(target) == :cvar
    val = lower_expression(ctx, node.value)
    return lower_cvar_set(ctx, target, val)

  # Global-variable assignment: $name = value. Unlike a bare :var (only
  # promoted to a real global when the assignment is directly at top
  # level, i.e. wfn[:name] == "main"), a :gvar assignment ALWAYS writes
  # through to @global.<name> regardless of which function/method body
  # it's in. Checked before `name = target.name` below so a $-prefixed
  # name never pollutes ctx[:var_types]/ctx[:bindings]/ctx[:unboxed_vars]
  # — those are per-function local-variable bookkeeping that a global
  # has no business appearing in.
  if ast_kind(target) == :gvar
    val = lower_expression(ctx, node.value)
    return lower_gvar_set(ctx, target.name, val)

  # Explicit native-data field assignment: receiver$field = value.
  if ast_kind(target) == :view_field_var
    val = lower_expression(ctx, node.value)
    return lower_view_field_var_set(ctx, target, val)

  # Method-style assignment: recv.field = value → dispatch recv.field=(value)
  # rw accessors and any user method ending in `=` go through this path.
  if ast_kind(target) == :call && target.receiver != nil
    # Preserve the target call's own arguments (mirrors
    # lower_compound_assign): an or-assign subscript target arrives here
    # as the "[]" READ node — `h[k] ||= v` must write through
    # h.[]=(k, k_or_value), not h.[]=(or_value). Property setters
    # (obj.attr = v) have no args, so this is the identity for them.
    setter_args = []
    ai = 0
    while ai < target.args.size()
      setter_args.push(target.args[ai])
      ai += 1
    setter_args.push(node.value)
    setter_call = Tungsten:AST:Call.new(target.receiver, target.name + "=", setter_args, nil)
    setter_call.loc = ast_get(target, :loc)
    return lower_method_call(ctx, setter_call)

  name = target.name

  # Flow compile-time quantity signatures through ordinary local bindings.
  # Reassignment to an unknown expression clears the fact conservatively.
  if ctx[:quantity_dimensions] == nil
    ctx[:quantity_dimensions] = {}
  ctx[:quantity_dimensions][name] = static_quantity_signature(ctx, node.value)

  # Source-class facts distinguish an exact constructor result from a merely
  # compatible declaration. Exact facts enable guarded devirtualization and,
  # once method tables are locked, unconditional direct calls. Copying a local
  # preserves its certainty, while any unproved reassignment clears it.
  if ctx[:local_class_facts] == nil
    ctx[:local_class_facts] = {}
  fact = nil
  if node.value != nil && is_ast_node?(node.value) && ast_kind(node.value) == :call && node.value.name == "new" && node.value.receiver != nil && is_ast_node?(node.value.receiver)
    ctor_cls = ast_get(node.value.receiver, :name)
    if normal_source_instance_class?(ctx[:mod], ctor_cls)
      stable = false
      if ctx[:local_assignment_counts] != nil && ctx[:local_assignment_counts][name] == 1 && source_constructor_returns_exact_class?(ctx[:mod], ctor_cls)
        stable = true
      fact = {class_name: ctor_cls, certainty: :exact, stable: stable}
  elsif node.value != nil && is_ast_node?(node.value) && ast_kind(node.value) == :var
    source_fact = ctx[:local_class_facts][node.value.name]
    if source_fact != nil
      # A copied reference can be exact, but it is a second mutable binding;
      # keep the speculative guard until a future SSA fact proves both stable.
      fact = {class_name: source_fact[:class_name], certainty: source_fact[:certainty], stable: false}
  if fact == nil && node.type_hint != nil
    hinted_class = "" + node.type_hint.to_s()
    if normal_source_instance_class?(ctx[:mod], hinted_class)
      fact = {class_name: hinted_class, certainty: :compatible, stable: false}
  ctx[:local_class_facts][name] = fact

  # Range-elision (#49): stash range-literal RHS so a later `r.each ...`
  # substitutes the range expression at the call site and routes through
  # the with-loop fast path. Any rebind of the var — or of a var its bounds
  # read — clears the stash so we never substitute a stale binding; only
  # pure bounds are recorded at all (substitution re-evaluates them at each
  # use site, so calls would replay their side effects).
  if ctx[:range_bindings] == nil
    ctx[:range_bindings] = {}
  range_binding_invalidate(ctx, name)
  if node.value != nil && is_ast_node?(node.value) && ast_kind(node.value) == :range && range_binding_pure_bound?(ast_get(node.value, :from)) && range_binding_pure_bound?(ast_get(node.value, :to))
    ctx[:range_bindings][name] = node.value
    # When every use of the var is an elidable position (each-with-block /
    # pipeline base — the shapes ctx[:range_bindings] substitution rewrites),
    # the materialization below is dead: skip it entirely. See the
    # range_elision_* walkers for the proof obligations. Statement position
    # only — an assign-as-expression's value is consumed by the enclosing
    # expression and must stay materialized.
    if stmt_position && range_assign_elidable?(ctx, name, node.value)
      return typed_value(:i64, w_nil.to_s())

  # Closure-escape (#61): stash block-literal RHS so a later
  # `arr.each(cb)` substitutes the block at the call site and inlines
  # via the existing .each handler. Same shape as range_bindings —
  # reassigning to a non-block value clears the stash. Conservative
  # escape model: we only consult this binding when the closure value
  # appears as the last arg of a known iter method and the receiver is
  # a fresh :var; the binding stays available for the closure's normal
  # call sites too (the closure allocation itself isn't elided here).
  if ctx[:closure_bindings] == nil
    ctx[:closure_bindings] = {}
  if node.value != nil && is_ast_node?(node.value) && ast_kind(node.value) == :block
    ctx[:closure_bindings][name] = node.value
    if ctx[:closure_noalloc_bindings] == nil
      ctx[:closure_noalloc_bindings] = {}
    if wfn[:name] != "main" && (closure_binding_no_escape?(ctx, name) || closure_binding_consumed_by_next_stmt?(ctx, name))
      ctx[:closure_noalloc_bindings][name] = true
  else
    ctx[:closure_bindings][name] = nil
    if ctx[:closure_noalloc_bindings] != nil
      ctx[:closure_noalloc_bindings][name] = nil

  # Headerless stack SmallArray. `buf = i32[N]` that the escape pass proved
  # non-escaping (node.stack_safe) — used only via []/[]=/size/length, a single
  # assignment, not in a loop. Emit a bare `[payload x i8]` alloca and bind the
  # var to the RAW alloca pointer: no 2-byte ebits/size header, no
  # w_small_array_init, no box (subtag OR). Keeping the pointer un-ptrtoint'd is
  # exactly what lets LLVM SROA promote the buffer to registers (the sorting-
  # network leaf win). `.size`/[]/[]= use the compile-time N/T (wfn[:sa_size] +
  # the :small_array_* type) instead of reading a runtime header.
  #   - `wfn[:name] != "main"`: a top-level var stores through @global.<name> via
  #     ptrtoint, which re-escapes the pointer — keep those on the boxed path.
  #   - `wfn[:var_slots][name] == nil`: a pre-allocated i64 slot would also
  #     ptrtoint the pointer on store; only pure SSA-binding vars go headerless.
  if wfn[:name] != "main" && wfn[:var_slots][name] == nil && node.value != nil && is_ast_node?(node.value) && ast_kind(node.value) in (:typed_array_new :typed_array) && typed_array_new_stack_promoted?(node.value)
    ta_node = node.value
    sa_sym = small_array_etype_to_sym(ta_node.element_type)
    if sa_sym != nil
      sa_bits = typed_array_element_bits(small_array_to_typed_array_type(sa_sym))
      sa_size = ast_get(ta_node, :size).value
      sa_payload = small_array_payload_bytes(sa_bits, sa_size)
      sa_ptr = next_temp(wfn)
      emit_instruction(wfn, {op: :small_array_alloca, temp_ptr: sa_ptr, total_bytes: sa_payload})
      # Keep the raw alloca pointer OUT of ctx[:bindings]: materialize_bindings
      # spills bindings to i64 slots (`store i64 <binding>, ptr %vs.N`), which
      # would ptrtoint-and-re-escape the pointer AND is a type error (ptr into an
      # i64 slot). The alloca dominates every use (entry block), so no spill is
      # needed — the []/[]=/size use sites read the pointer straight from
      # wfn[:sa_ptr]. var_types is still set so the receiver infers :small_array_*
      # and the use sites take the inline path.
      ctx[:var_types][name] = sa_sym
      if wfn[:sa_ptr] == nil
        wfn[:sa_ptr] = {}
      if wfn[:sa_size] == nil
        wfn[:sa_size] = {}
      wfn[:sa_ptr][name] = sa_ptr
      wfn[:sa_size][name] = sa_size
      return typed_value(sa_sym, sa_ptr)

  target_type = ctx[:var_types][name]
  hint_array_etype = nil
  if node.type_hint != nil
    # `w64` is a synonym for the NaN-boxed WValue-int64 form.
    # Under the old semantics this was the default (unannotated) type,
    # but raw i64 is now the unannotated default. Users who want
    # explicit boxed semantics annotate `## w64`, which maps to `:i64`
    # here (the internal symbol for boxed that pre-dates the raw-i64
    # switch; the full rename is deferred to a follow-up).
    hint_text = node.type_hint
    hint_array_etype = array_hint_element_type(hint_text)
    if hint_text == "w64"
      target_type = :i64
    elsif hint_array_etype != nil
      # `## f32[]` / `## i32[N]` / etc. — normalize the array-shaped hint
      # to the canonical :typed_array_<etype> symbol so element access
      # (`a[i]`) lowers via :typed_array_get_inline instead of
      # dispatching through generic Array#[]. Mirrors the param-hint
      # normalization in definitions.w. EXCEPT when the hint matches a
      # typed-array literal RHS that stack-promotes (`a = bf16[4] ##
      # bf16[]`) — same rule as top_level_assignment_static_type: resolve
      # to the :small_array_* symbol as inference would, or readers run
      # heap-WArray offsets against a SmallArray handle (segfault).
      hv = node.value
      hint_etype = hint_array_etype
      if hv != nil && is_ast_node?(hv) && ast_kind(hv) in (:typed_array_new :typed_array) && hv.element_type == hint_etype && typed_array_new_stack_promoted?(hv)
        target_type = small_array_etype_to_sym(hint_etype)
      else
        target_type = typed_array_etype_to_sym(hint_etype)
    elsif hint_text == "big" || hint_text == "bigint" || hint_text == "bignum"
      # Opt-in auto-promoting BigInt accumulator. Canonicalize all three
      # spellings to the single :bigint type so the value stays off the
      # native-i64 path and its arithmetic promotes (w_mul/w_add) instead
      # of wrapping. See is_bigint_type in lowering/types.w.
      target_type = :bigint
    else
      target_type = hint_text.to_sym()

  # Unboxed loop variable: store raw value directly
  if ctx[:unboxed_vars] != nil && ctx[:unboxed_vars][name] != nil
    val = lower_expression(ctx, node.value)
    raw_val = ensure_raw_int(wfn, val)
    raw_slot = ctx[:unboxed_vars][name]
    emit_instruction(wfn, {op: :store_i64, value: raw_val, ptr: raw_slot})
    return typed_value(:raw_int, raw_val)

  if ctx[:closure_noalloc_bindings] != nil && ctx[:closure_noalloc_bindings][name] == true && node.value != nil && is_ast_node?(node.value) && ast_kind(node.value) == :block
    return typed_value(:i64, w_nil.to_s())

  if is_raw_int_storage_type(target_type)
    # Retype guard (round-3 bug 1, 2026-07-22): an annotated reassign of an
    # EXISTING boxed variable — a parameter, a materialized boxed slot, or a
    # live boxed binding — must NOT switch the variable to a raw machine
    # slot. The switch happens at whatever point the assignment sits in the
    # statement stream, so a reassign inside one branch of an `if` leaves
    # the other branch holding the boxed representation; post-merge reads
    # and the function's inferred return type then mix NaN-boxed and raw
    # bits (observed as tag-junk integers at call boundaries). The
    # annotation KEEPS its wrapping semantics — the RHS is lowered raw —
    # but the result is boxed back into the variable's existing
    # representation and the variable's type stays boxed (:int).
    hint_existing_t = ctx[:var_types][name]
    hint_retype_safe = hint_existing_t != nil && is_raw_int_storage_type(hint_existing_t)
    if !hint_retype_safe
      hint_retype_safe = ctx[:bindings][name] == nil && wfn[:var_slots][name] == nil
      if hint_retype_safe
        pi = 0
        while pi < wfn[:params].size()
          if wfn[:params][pi] == name
            hint_retype_safe = false
          pi += 1
    if !hint_retype_safe
      raw_val = lower_machine_int_expression(ctx, node.value, target_type)
      boxed_tmp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: boxed_tmp, name: machine_box_fn(target_type), args: [raw_val]})
      # Round-4 fix (2026-07-22): stamp :bigint, NOT :int. boxed_tmp above is
      # machine_box_fn(:u64) = w_u64(...), a real BIGNUM box for values past
      # 2^48. A :int stamp routes later machine-context reads through the
      # 48-bit nanunbox_int shortcut in ensure_raw_machine_int, truncating
      # chained param reassigns (x = x ^ (x >> 12) ## u64; …) to garbage.
      # :bigint is not a machine-int type, so the var read returns the boxed
      # value and ensure_raw_machine_int takes the full-width machine_unbox_fn
      # (w_to_u64/w_to_i64) path. Chained annotated reassigns re-enter this
      # box-back branch (existing type :bigint is neither nil nor
      # raw-int-storage, so hint_retype_safe stays false), keeping the
      # representation consistent. Verified clean stage1≡stage2 fixed point.
      if hint_existing_t == nil
        ctx[:var_types][name] = :bigint
      hint_ptr = wfn[:var_slots][name]
      if hint_ptr != nil
        emit_instruction(wfn, {op: :store_i64, value: boxed_tmp, ptr: hint_ptr})
      else
        ctx[:bindings][name] = boxed_tmp
      if wfn[:name] == "main"
        ctx[:mod][:top_level_vars][name] = true
        ctx[:mod][:top_level_var_types][name] = nil
        emit_store_global_unless_const(wfn, ctx, name, boxed_tmp)
      return typed_value(:i64, boxed_tmp)
    raw_val = lower_machine_int_expression(ctx, node.value, target_type)
    ctx[:var_types][name] = target_type
    ctx[:bindings][name] = nil
    ptr = ensure_var_slot(wfn, name, machine_slot_type(target_type))
    emit_instruction(wfn, {op: machine_store_op(target_type), value: raw_val, ptr: ptr})
    if wfn[:name] == "main"
      ctx[:mod][:top_level_vars][name] = true
      ctx[:mod][:top_level_var_types][name] = target_type
      if ctx[:mod][:top_level_static_types] != nil
        ctx[:mod][:top_level_static_types][name] = target_type
      emit_store_global_unless_const(wfn, ctx, name, raw_val, machine_slot_type(target_type))
    return typed_value(raw_machine_value_type(target_type), raw_val)

  if is_machine_float_type(target_type)
    val = lower_expression(ctx, node.value)
    raw_val = nil
    if target_type in (:f32 :raw_f32)
      raw_val = ensure_raw_f32(wfn, val)
    else
      raw_val = ensure_raw_f64(wfn, val)
    ctx[:var_types][name] = target_type
    ctx[:bindings][name] = nil
    ptr = ensure_var_slot(wfn, name, float_slot_type(target_type))
    emit_instruction(wfn, {op: float_store_op(target_type), value: raw_val, ptr: ptr})
    if wfn[:name] == "main"
      ctx[:mod][:top_level_vars][name] = true
      ctx[:mod][:top_level_var_types][name] = nil
      if ctx[:mod][:top_level_static_types] != nil
        ctx[:mod][:top_level_static_types][name] = target_type
      boxed = ensure_i64_value(wfn, typed_value(raw_float_value_type(target_type), raw_val))
      emit_store_global_unless_const(wfn, ctx, name, boxed)
    return typed_value(raw_float_value_type(target_type), raw_val)

  val = lower_expression(ctx, node.value)
  if hint_array_etype == "f64" || hint_array_etype == "f32"
    if target_type == typed_array_etype_to_sym(hint_array_etype)
      if val[:type] != target_type
        source = ensure_i64_value(wfn, val)
        converted = next_temp(wfn)
        helper = hint_array_etype == "f32" ? "w_array_to_f32" : "w_array_to_f64"
        emit_instruction(wfn, {op: :call_direct_i64, temp: converted, name: helper, args: [source]})
        val = typed_value(target_type, converted)
  if mut_target_set
    ctx[:mut_accum_target] = nil
  inferred = nil
  if node.type_hint == nil
    inferred = infer_type(node.value, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    # Some lowering paths carry a stronger representation fact than the shared
    # AST inference can express. In particular, lower_ivar knows a constructor-
    # declared typed-array ivar from mod[:ivar_types], while infer_type has no
    # class context. Keep that proven array type on a register alias.
    if inferred == nil && is_array_type?(val[:type])
      inferred = val[:type]
    machine_type = canonical_machine_int_type(inferred)
    typed_raw_machine_value = false
    raw_int_candidate = true
    if ctx[:raw_int_candidates] != nil && ctx[:raw_int_candidates][name] != true
      raw_int_candidate = false
    # Genuinely-typed raw machine values (:raw_i64/u64/i128/u128 from typed
    # sources) prove their own rawness, so they skip the conservative
    # candidate-map gate below.
    # A wide integer literal also lowers as :raw_i64 so a boxing boundary can
    # promote it without truncating to the i48 payload. It is not, by itself,
    # an explicit machine-type proof: when the local escapes (notably through
    # method dispatch or wvalue_bits), materialize one stable BigInt object so
    # receiver identity is preserved. Non-literal typed producers retain the
    # representation proof and may bypass the candidate-map gate.
    value_is_int_literal = is_ast_node?(node.value) && ast_kind(node.value) == :int
    if is_ast_node?(node.value) && ast_kind(node.value) == :unary_op
      if node.value.op in (:PLUS :MINUS) && node.value.operand != nil
        if ast_kind(node.value.operand) == :int
          value_is_int_literal = true
    # A decimal literal beyond i64 has already been materialized by
    # lower_int_bigint_literal as a boxed BigInt (:i64 here means WValue, not
    # raw machine i64).  Raw-slot promotion would immediately w_to_i64 that
    # object, discard every limb above the low word, and later rebox only the
    # truncation at a call boundary.  Mid-width literals that lower as
    # :raw_i64 remain eligible: all of their bits genuinely fit the slot.
    if value_is_int_literal && val[:type] == :i64
      raw_int_candidate = false
      machine_type = nil
      inferred = :bigint
    # The raw-typed arm honors the candidate gate exactly like the
    # :raw_int arm below: a var analysis pinned (notably a plain-ccall
    # argument, which the ccall ABI forwards RAW with no box at the call
    # site) must keep boxed WValue storage even when its RHS derives
    # from machine-typed sources (`lo = i % 1000` with a promoted loop
    # var). Before this gate, such a local silently became a raw slot
    # and crossed the ccall boundary as raw bits where the C function
    # expected a WValue.
    if val[:type] in (:raw_i64 :raw_u64 :raw_i128 :raw_u128) && !value_is_int_literal && raw_int_candidate
      value_machine_type = raw_value_machine_type(val[:type])
      if machine_type == nil
        machine_type = value_machine_type
      # A statically inferred machine type and the lowered value's actual
      # representation are independent proofs. Honor the raw representation
      # even when inference ran first, but require exact signedness/width so a
      # raw u64 result cannot silently initialize an i64 slot (or vice versa).
      if machine_type == value_machine_type
        typed_raw_machine_value = true
    # :raw_int is the tag for BOTH ccall_nobox results AND plain int literals
    # (`0`). The literal case must still respect the candidate gate: an
    # escaping accumulator seeded `= 0` (e.g. `dot/1 0` summing floats via an
    # each_with_index closure) is not a raw-int candidate, so promoting it to
    # a raw :i64 slot here would make a later `acc += <float>` coerce the
    # float through w_to_i64 and die ("expected int, got numeric").
    elsif machine_type == nil && val[:type] == :raw_int && raw_int_candidate
      machine_type = raw_value_machine_type(:raw_int)
      typed_raw_machine_value = true
    if machine_type != nil && (raw_int_candidate || typed_raw_machine_value) && ctx[:bindings][name] == nil && wfn[:var_slots][name] == nil
      raw_val = ensure_raw_machine_int(wfn, val, machine_type, inferred)
      ctx[:var_types][name] = machine_type
      ctx[:bindings][name] = nil
      ptr = ensure_var_slot(wfn, name, machine_slot_type(machine_type))
      emit_instruction(wfn, {op: machine_store_op(machine_type), value: raw_val, ptr: ptr})
      if wfn[:name] == "main"
        ctx[:mod][:top_level_vars][name] = true
        ctx[:mod][:top_level_var_types][name] = machine_type
        if ctx[:mod][:top_level_static_types] != nil
          ctx[:mod][:top_level_static_types][name] = machine_type
        emit_store_global_unless_const(wfn, ctx, name, raw_val, machine_slot_type(machine_type))
      return typed_value(raw_machine_value_type(machine_type), raw_val)

    if (inferred == :float || inferred == :f64) && ctx[:bindings][name] == nil && wfn[:var_slots][name] == nil
      raw_val = ensure_raw_f64(wfn, val)
      ctx[:var_types][name] = inferred
      ctx[:bindings][name] = nil
      ptr = ensure_var_slot(wfn, name, "double")
      emit_instruction(wfn, {op: :store_double, value: raw_val, ptr: ptr})
      if wfn[:name] == "main"
        ctx[:mod][:top_level_vars][name] = true
        ctx[:mod][:top_level_var_types][name] = nil
        if ctx[:mod][:top_level_static_types] != nil
          ctx[:mod][:top_level_static_types][name] = inferred
        boxed = ensure_i64_value(wfn, typed_value(:raw_f64, raw_val))
        emit_store_global_unless_const(wfn, ctx, name, boxed)
      return typed_value(:raw_f64, raw_val)

  val_reg = ensure_i64_value(wfn, val)

  # Track type for optimization — explicit hint takes priority over inference
  if node.type_hint != nil
    ctx[:var_types][name] = target_type
  else
    if inferred != nil
      # Type tracking is function-wide rather than control-flow-sensitive.
      # Once a local has been materialized as a boxed WValue, a later integer
      # assignment in another branch must not make reads treat that boxed slot
      # as raw machine bits.
      existing_boxed_local = wfn[:var_slots][name] != nil || ctx[:bindings][name] != nil
      raw_int_candidate = true
      if ctx[:raw_int_candidates] != nil && ctx[:raw_int_candidates][name] != true
        raw_int_candidate = false
      if is_bigint_type(target_type) && !is_bigint_type(inferred)
        # Sticky BigInt: a `## big` accumulator stays :bigint across
        # reassignments (`f = f * i`) so every iteration keeps routing
        # through the promoting w_mul path. Re-narrowing it to :int here
        # would re-enable native-wrap unboxing on a later loop pass and
        # silently corrupt the running product. (Mirrors how machine-int
        # stickiness is preserved at collect_top_level_static_types.)
        nil
      elsif is_raw_int_storage_type(inferred) && !raw_int_candidate
        # Inside a `Math.promote / trap / wrap` block, a boxed integer local
        # must carry an :int type so its +/-/* reads route through the guarded
        # overflow path (promote/trap) or explicit native wrap in
        # lower_binary_op, instead of the generic polymorphic w_* fallback
        # (which would silently promote and make trap impossible). :int is a
        # BOXED integer type, so reads still box via ensure_i64_value — no
        # raw-machine-bits hazard, which is why the default (non-block) path
        # deliberately leaves it unset here.
        if ctx[:overflow_mode] != nil
          ctx[:var_types][name] = :int
      elsif existing_boxed_local && (is_raw_int_storage_type(inferred) || is_machine_float_type(inferred))
        # Once a local is a materialized boxed WValue, a later machine-int OR
        # machine-FLOAT inference (e.g. `if c: v = ~0.0` on a v already holding a
        # boxed Float) must not retype the slot — reads would `load double` the
        # boxed i64 bits and corrupt it (2.0 -> 2.125 in the NaN-box tag bits).
        nil
      else
        ctx[:var_types][name] = inferred

  # If variable already has a var slot (was materialized), store to it
  ptr = wfn[:var_slots][name]
  if ptr != nil
    emit_instruction(wfn, {op: :store_i64, value: val_reg, ptr: ptr})
    # Top-level assignments also store to globals for cross-function access
    if wfn[:name] == "main"
      ctx[:mod][:top_level_vars][name] = true
      ctx[:mod][:top_level_var_types][name] = nil
      if ctx[:mod][:top_level_static_types] != nil
        if node.type_hint != nil
          ctx[:mod][:top_level_static_types][name] = target_type
        else
          ctx[:mod][:top_level_static_types][name] = inferred
      emit_store_global_unless_const(wfn, ctx, name, val_reg)
    return typed_value(:i64, val_reg)

  # Otherwise track as a temp binding (register rename, no alloca)
  ctx[:bindings][name] = val_reg

  # Top-level assignments also store to globals for cross-function access
  if wfn[:name] == "main"
    ctx[:mod][:top_level_vars][name] = true
    ctx[:mod][:top_level_var_types][name] = nil
    if ctx[:mod][:top_level_static_types] != nil
      if node.type_hint != nil
        ctx[:mod][:top_level_static_types][name] = target_type
      else
        ctx[:mod][:top_level_static_types][name] = inferred
    emit_store_global_unless_const(wfn, ctx, name, val_reg)

  typed_value(:i64, val_reg)

-> lower_multi_assign(ctx, node)
  wfn = ctx[:func]
  # Evaluate RHS (should produce an array)
  val = lower_expression(ctx, node.value)
  val_reg = ensure_i64_value(wfn, val)
  targets = node.targets
  i = 0
  while i < targets.size()
    target = targets[i]
    name = target.name
    range_binding_invalidate(ctx, name)
    # Get element i from the array
    idx_tv = lower_int(ctx, Tungsten:AST:Int.new(i))
    idx_reg = ensure_i64_value(wfn, idx_tv)
    elem_temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: elem_temp, name: "w_array_get", args: [val_reg, idx_reg]})
    # Store to variable
    ensure_var_slot(wfn, name)
    slot = wfn[:var_slots][name]
    emit_instruction(wfn, {op: :store_i64, value: elem_temp, ptr: slot})
    i += 1
  typed_value(:i64, val_reg)

-> lower_safe_nav(ctx, node)
  wfn = ctx[:func]
  # Evaluate receiver
  recv_tv = lower_expression(ctx, node.receiver)
  recv_reg = ensure_i64_value(wfn, recv_tv)

  # Check if receiver is nil
  cmp_reg = next_temp(wfn)
  emit_instruction(wfn, {op: :icmp_ne_i64, temp: cmp_reg, lhs: recv_reg, rhs: w_nil.to_s()})

  not_nil_label = next_label(wfn, "safenav.nn")
  nil_label = next_label(wfn, "safenav.nil")
  merge_label = next_label(wfn, "safenav.mrg")

  emit_instruction(wfn, {op: :cond_br, cond: cmp_reg, then_label: not_nil_label, else_label: nil_label})

  # Not-nil branch: perform method call using the already-evaluated receiver
  start_block(wfn, not_nil_label)
  # Lower args
  arg_regs = []
  i = 0
  while i < node.args.size()
    val = lower_expression(ctx, node.args[i])
    arg_regs.push(ensure_i64_value(wfn, val))
    i += 1
  # Block if present
  sblk = node.block
  if sblk != nil && is_ast_node?(sblk)
    closure_tv = lower_block_closure(ctx, sblk)
    closure_reg = ensure_i64_value(wfn, closure_tv)
    arg_regs.push(closure_reg)
  # Emit method call — compute method name as WValue
  method_name = node.name
  method_name_tv = lower_string(ctx, Tungsten:AST:String.new(method_name))
  method_name_val = ensure_i64_value(wfn, method_name_tv)

  temp_args_val = next_temp(wfn)
  call_temp = next_temp(wfn)
  ic_id = ctx[:mod][:next_ic]
  ctx[:mod][:next_ic] = ic_id + 1

  emit_instruction(wfn, {
    op: :call_method_i64,
    temp: call_temp,
    temp_args_val: temp_args_val,
    receiver: recv_reg,
    method_name_val: method_name_val,
    args: arg_regs,
    ic_id: ic_id
  })
  call_from = wfn[:blocks][wfn[:blocks].size() - 1][:label]
  emit_instruction(wfn, {op: :br, label: merge_label})

  # Nil branch: return nil
  start_block(wfn, nil_label)
  nil_reg = w_nil.to_s()
  nil_from = nil_label
  emit_instruction(wfn, {op: :br, label: merge_label})

  # Merge with phi
  start_block(wfn, merge_label)
  result = next_temp(wfn)
  emit_instruction(wfn, {op: :phi_i64, temp: result, a_value: call_temp, a_label: call_from, b_value: nil_reg, b_label: nil_from})
  typed_value(:i64, result)
