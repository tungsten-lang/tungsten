# Dispatch shim — the AST-node-type dispatchers (lower_program,
# lower_statement, lower_expression) plus the binding/error helpers
# they share. Sits first in the worker dep chain because every other
# lowering module recurses through these dispatchers.
#
# All worker modules depend on this module; it imports NO worker
# modules. The case statements below name the per-node lowerers
# directly (lower_if, lower_var, ...); those identifiers resolve via
# Tungsten's flat top-level namespace once lowering.w's worker imports
# are merged.
#
# This file has no `use` directives: from `compiler/lib/lowering/`,
# `use wire` would resolve to `compiler/lib/lowering/wire.w` (not the
# real `compiler/lib/wire.w`). All names referenced by the dispatchers
# (`block_terminated`, `emit_instruction`, `typed_value`, `w_nil`, type
# predicates, lowerer functions) live in the flat top-level namespace
# once lowering.w's worker imports are merged.

# -- Program --

-> lower_program(ctx, statements)
  prev_stmts = ctx[:enclosing_stmts]
  ctx[:enclosing_stmts] = statements
  i = 0
  while i < statements.size()
    if block_terminated(ctx[:func])
      ctx[:enclosing_stmts] = prev_stmts
      return nil
    ctx[:enclosing_stmt_idx] = i
    lower_statement(ctx, statements[i])
    i += 1
  ctx[:enclosing_stmts] = prev_stmts

# -- Statements --

-> lower_statement(ctx, node)
  t = ast_kind(node)

  case t
  when :assign
    lower_assign_expr(ctx, node)
    return nil
  when :if
    materialize_bindings(ctx)
    return lower_if(ctx, node)
  when :call
    if node.receiver == nil && node.name == "constant_alias"
      return nil
    lower_expression(ctx, node)
    return nil
  when :return
    return lower_return(ctx, node)
  when :compound_assign
    lower_compound_assign(ctx, node)
    return nil
  when :binary_op
    lower_expression(ctx, node)
    return nil
  when :while
    materialize_bindings(ctx)
    return lower_while(ctx, node)
  when :method_def
    return lower_method_def(ctx, node)
  when :puts
    return lower_puts(ctx, node, false)
  when :print
    return lower_print(ctx, node, false)
  when :fn_def
    return lower_fn_def(ctx, node)
  # GPU kernel defs get emitted to a sibling .metal file (or embedded MSL
  # string constant) by a separate pass after lowering — here we just
  # skip them so the normal pipeline doesn't try to lower GPU primitives
  # as ordinary Tungsten expressions.
  when :gpu_kernel_def
    record_gpu_kernel(ctx, node)
    return nil
  # @fastmath / @strictmath scoped math-mode override blocks.
  when :fastmath_block
    return lower_mathmode_block(ctx, node, :fast)
  when :strictmath_block
    return lower_mathmode_block(ctx, node, :strict)
  # `Math.promote / trap / wrap` scoped integer-overflow-mode blocks.
  when :overflow_block
    return lower_overflow_block(ctx, node)
  # Schedule and layout defs are picked up by the metal_emitter pass
  # alongside gpu_kernel_def. Skip here so the normal pipeline doesn't
  # try to lower the directive list as ordinary expressions.
  when :schedule_def, :layout_def
    record_gpu_schedule(ctx, node)
    return nil
  when :class_def, :module_def
    return lower_class_def(ctx, node)
  when :trait_def, :trait_include
    return nil
  when :namespace_decl
    # `in Foo:Bar` directive — purely structural; the parser used it
    # to qualify class names at parse time. Nothing left to lower.
    return nil
  when :ivars_decl
    # `- ivars` class-body block — declarative slab layout. Consumer
    # passes can read entries off the class_def body; the lowerer
    # itself has nothing to emit.
    return nil
  when :case
    materialize_bindings(ctx)
    lower_case(ctx, node)
    return nil
  when :case_value
    materialize_bindings(ctx)
    lower_case_value(ctx, node)
    return nil
  when :begin
    materialize_bindings(ctx)
    return lower_begin(ctx, node)
  when :raise
    return lower_raise(ctx, node)
  when :break
    return lower_break(ctx)
  when :next
    return lower_next(ctx)
  when :recase
    return lower_recase(ctx, node)
  when :with
    materialize_bindings(ctx)
    return lower_with(ctx, node)
  when :yield
    lower_yield(ctx, node)
    return nil
  when :passthrough
    lower_expression(ctx, node)
    return nil
  when :go
    lower_go(ctx, node)
    return nil
  when :multi_assign
    lower_multi_assign(ctx, node)
    return nil
  when :on_guard
    return lower_on_guard(ctx, node)
  when :view_decl
    return nil
  when :field_decl
    return nil
  else
    # Expression statement — evaluate and discard
    lower_expression(ctx, node)
    nil

# -- Expressions --
# Returns a typed_value {type:, value:}

-> lower_expression(ctx, node)
  t = ast_kind(node)

  # Cases are ordered by measured AST-node frequency across the full
  # compiler import graph (sampled via `bin/tungsten --ast` on every
  # .w file under compiler/lib/, bin/tungsten.w, and core deps).
  # Tungsten compiles `case` to a linear chain of w_eq calls, so the
  # most frequent dispatches must come first. The top 16 are hot path;
  # the rest are kept in their original semantic groupings.
  case t

  # Hot path — measured frequencies in parentheses
  when :var            # 33934
    return lower_var(ctx, node)
  when :gvar
    return lower_gvar(ctx, node)
  when :class_ref
    # ClassRef lowering: pass the ClassRef node DIRECTLY to lower_var.
    # lower_var only reads `node.name` and ClassRef shares the same
    # slab layout as Var (@name w64 at slot 0), so the accessor returns
    # the same value. Avoiding the synthetic Tungsten:AST:Var.new
    # construction keeps stage 0 (interpreted) and stage 1 binary
    # (compiled) byte-identical — the synthetic allocation in the
    # dispatch arm was leaking a closure between stages.
    return lower_var(ctx, node)
  when :call           # 17573
    return lower_call(ctx, node)
  when :symbol         # 13153
    return lower_symbol(ctx, node)
  when :binary_op      # 11348
    return lower_binary_op(ctx, node)
  when :string         # 5730
    return lower_string(ctx, node)
  when :int            # 4880
    return lower_int(ctx, node)
  when :nil_lit        # 2196
    return typed_value(:i64, w_nil.to_s())
  when :ivar           # 1270
    return lower_ivar(ctx, node)
  when :and            # 1245
    materialize_bindings(ctx)
    return lower_short_circuit(ctx, node, :and)
  when :hash_literal   # 1046
    return lower_hash_literal(ctx, node)
  when :bool           # 954
    return lower_bool(node)
  when :or             # 557
    materialize_bindings(ctx)
    return lower_short_circuit(ctx, node, :or)
  when :array          # 551
    return lower_array(ctx, node)
  when :char           # 288
    return lower_char(ctx, node)
  when :in_test        # 255
    materialize_bindings(ctx)
    return lower_in_test(ctx, node)
  when :not            # 210
    return lower_not(ctx, node)

  # Mid-frequency
  when :case_value
    materialize_bindings(ctx)
    return lower_case_value(ctx, node)
  when :block
    materialize_bindings(ctx)
    return lower_block_closure(ctx, node)
  when :unary_op
    return lower_unary_op(ctx, node)
  when :map, :calc
    materialize_bindings(ctx)
    return lower_pipeline(ctx, node)
  when :string_interp
    return lower_string_interp(ctx, node)
  when :assign
    return lower_assign_expr(ctx, node)
  when :compound_assign
    return lower_compound_assign(ctx, node)
  when :if
    # if-expression (inline if)
    materialize_bindings(ctx)
    return lower_if_expr(ctx, node)
  when :case
    materialize_bindings(ctx)
    return lower_case(ctx, node)
  when :passthrough
    lower_statement(ctx, node.expression)
    return lower_expression(ctx, node.value)
  # @fastmath / @strictmath blocks in expression position (e.g. a method whose
  # entire body is the block, or the block as an if/case arm) — return the
  # block body's value. Mirrors the statement dispatch in lower_statement.
  when :fastmath_block
    return lower_mathmode_block(ctx, node, :fast)
  when :strictmath_block
    return lower_mathmode_block(ctx, node, :strict)
  when :overflow_block
    return lower_overflow_block(ctx, node)
  # `recase` as an arm-body tail (lower_body_value lowers the last stmt via
  # lower_expression). It terminates the block with a branch; the typed_value
  # return is a formality the caller discards.
  when :recase
    return lower_recase(ctx, node)
  when :wvalue
    return lower_wvalue(ctx, node)
  when :puts
    return lower_puts(ctx, node)
  when :print
    return lower_print(ctx, node)
  when :cvar
    return lower_cvar(ctx, node)
  when :yield
    return lower_yield(ctx, node)
  when :regex
    return lower_regex(ctx, node)
  when :regex_capture
    return lower_regex_capture(ctx, node)
  when :typed_array_new, :typed_array
    return lower_typed_array_new(ctx, node)
  when :range
    materialize_bindings(ctx)
    return lower_range(ctx, node)
  when :float
    return lower_float(ctx, node)
  when :decimal
    return lower_decimal(ctx, node)
  when :currency
    return lower_currency(ctx, node)
  when :quantity
    return lower_quantity(ctx, node)
  when :duration
    return lower_duration(ctx, node)
  when :uuid
    return lower_uuid(ctx, node)

  # Deep-wired literal types
  when :date
    return lower_date(ctx, node)
  when :datetime
    return lower_datetime(ctx, node)
  when :time
    return lower_time(ctx, node)
  when :ip4
    return lower_ipv4(ctx, node)
  when :cidr4
    return lower_cidr4(ctx, node)
  when :ip6
    return lower_ipv6(ctx, node)
  when :cidr6
    return lower_cidr6(ctx, node)
  when :rational
    return lower_rational(ctx, node)
  when :codepoint
    return lower_codepoint(ctx, node)
  when :color
    return lower_color(ctx, node)

  # CIDR pattern match: case ip when 10.0.0.0/8
  when :cidr_match
    return lower_cidr_match(ctx, node)
  when :regex_match
    return lower_regex_match(ctx, node)
  when :parg
    # `@N` positional ref. `:index` is an inline(32) integer (the digit
    # N); bind it to `__argN` — the param name that range.each / Phase 6g
    # and the /N-arity method synthesizer (`__arg1`, …) both produce.
    name = "__arg" + node.index.to_s()
    return lower_var(ctx, Tungsten:AST:Var.new(name))

  when :word_array     # `%w[a b c]` → Array of String literals
    return lower_word_or_symbol_array(ctx, node.words)

  # Shallow-wired literal types (return nil at runtime)
  when :month, :key, :symbol_array, :map_op, :lambda_arity, :superscript, :encoded
    return unsupported_node(ctx, node)

  when :view_access
    return lower_view_access(ctx, node)
  when :view_field
    return lower_view_field(ctx, node)
  when :view_field_var
    return lower_view_field_var(ctx, node)
  when :view_base
    return lower_view_base(ctx)
  when :view_value
    return lower_view_value(ctx)
  when :multi_assign
    return lower_multi_assign(ctx, node)
  when :safe_nav
    materialize_bindings(ctx)
    return lower_safe_nav(ctx, node)
  when :rescue_expr
    materialize_bindings(ctx)
    return lower_rescue_expr(ctx, node)

  when :go
    return lower_go(ctx, node)
  when :magic_constant
    return lower_magic_constant(ctx, node)
  # :self_ref — only 2 occurrences across the entire compiler corpus.
  # Kept near the bottom so it doesn't slow down the hot path.
  when :self_ref
    return lower_var(ctx, Tungsten:AST:Var.new("__self"))
  else
    # Unsupported node
    unsupported_node(ctx, node)

# -- Binding materialization --

-> materialize_bindings(ctx)
  wfn = ctx[:func]
  bindings = ctx[:bindings]
  names = bindings.keys().sort()
  preserved = {}
  i = 0
  while i < names.size()
    name = names[i]
    reg = bindings[name]
    if reg != nil
      # A pristine machine-int parameter (a raw-int param with no var_slot — so
      # never reassigned, since find_reassigned_params slots reassigned params at
      # entry) is bound by the prologue to its i48 untag, emitted in the ENTRY
      # block. That value dominates every block, so it survives branches without
      # materialization. Materializing it into a var_slot is unsafe: the promotion
      # pass strips the slot's alloca, leaving this store and the later load
      # dangling — which surfaced as `use of undefined value %vN` when such a
      # param was passed as an inline-asm builtin operand after a branch/loop.
      # Preserve the dominating binding instead. (Narrowed to raw-int params to
      # leave object/default-param materialization behavior unchanged.)
      if is_raw_int_storage_type(ctx[:var_types][name]) && wfn[:params].include?(name) && wfn[:var_slots][name] == nil
        preserved[name] = reg
      else
        slot_type = "i64"
        if is_raw_int_storage_type(ctx[:var_types][name])
          slot_type = machine_slot_type(ctx[:var_types][name])
        elsif is_machine_float_type(ctx[:var_types][name])
          slot_type = float_slot_type(ctx[:var_types][name])
        ptr = ensure_var_slot(wfn, name, slot_type)
        if is_raw_int_storage_type(ctx[:var_types][name])
          # Binding may already be raw (from ## i64 param unboxing) — store directly
          emit_instruction(wfn, {op: machine_store_op(ctx[:var_types][name]), value: reg, ptr: ptr})
        elsif is_machine_float_type(ctx[:var_types][name])
          emit_instruction(wfn, {op: float_store_op(ctx[:var_types][name]), value: reg, ptr: ptr})
        else
          emit_instruction(wfn, {op: :store_i64, value: reg, ptr: ptr})
    i += 1
  ctx[:bindings] = preserved

# -- Fallback for unsupported AST nodes --

-> unsupported_node(ctx, node)
  kind = "unknown"
  if node != nil && ast_kind(node) != nil
    kind = ast_kind(node).to_s()
  # Return nil as the value but emit a comment
  typed_value(:i64, w_nil.to_s())

# -- Top-level constant globals --
#
# A top-level binding with one `## i64` assignment from a literal int is
# emitted as an LLVM `constant` initializer with that value. Skip the
# runtime store_global so we don't write to a `constant` (illegal IR).

-> emit_store_global_unless_const(wfn, ctx, name, value_reg, value_type = nil)
  cv = ctx[:mod][:top_level_const_values]
  if cv != nil && cv[name] != nil
    return
  if value_type == nil
    value_type = "i64"
  emit_instruction(wfn, {op: :store_global, name: name, value: value_reg, type: value_type})
