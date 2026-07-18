# Lowering / method_call — receiver-method dispatch (`recv.method(args)`).
#
# The counterpart to lower_call (bare / implicit-self calls), extracted from
# calls.w for size. Handles operator-overload dispatch, typed-value overloads,
# universal methods (.class etc.), inline iterators, intrinsics, and
# user-method dispatch. Shares a flat namespace with calls.w, so the mutual
# lower_call <-> lower_method_call dispatch resolves at merge.
#
# This file deliberately has no `use` directives — see pass_registry.w.

-> lower_method_call(ctx, node)
  wfn = ctx[:func]
  method_name = node.name

  recv_node = node.receiver

  # Unit-carrying tensor factory syntax is intentionally a type-level spelling
  # even though Tensor's implementation stores dtype/unit as runtime metadata:
  #
  #   Tensor<f64, m/s>.zeros([100, 100])
  #
  # Do this before generic monomorphized dispatch. Tensor is not a generic
  # template (units are open-ended expressions), so specializing a class for
  # every unit would be both misleading and needlessly expensive.
  if recv_node != nil && ast_kind(recv_node) == :class_ref && recv_node.name == "Tensor" && method_name == "zeros"
    tensor_args = node.type_args
    if tensor_args == nil
      tensor_args = recv_node.type_args
    if tensor_args != nil
      if tensor_args.size() != 2 || node.args == nil || node.args.size() != 1
        raise compile_error_for_node(:E_LOWER_TENSOR_UNIT_TYPE, "Tensor unit factory expects Tensor<dtype, unit>.zeros(shape)", ctx[:source_path], node)
      if lookup_unit_static_signature(tensor_args[1]) == nil
        raise compile_error_for_node(:E_LOWER_TENSOR_UNIT_TYPE, "unknown Tensor unit expression: " + tensor_args[1], ctx[:source_path], node)
      rewritten = Tungsten:AST:Call.new(Tungsten:AST:ClassRef.new("Tensor"), "zeros_unit", [Tungsten:AST:String.new(tensor_args[0]), Tungsten:AST:String.new(tensor_args[1]), node.args[0]], nil)
      rewritten.loc = ast_get(node, :loc)
      return lower_method_call(ctx, rewritten)

  # `arr.flip(i)` — toggle element i in place. Sugar for `arr[i] = !arr[i]`,
  # built from the same "[]"/"[]=" calls the parser emits for subscript
  # get/set (not an Assign-with-call-target, which drops the index arg).
  # Works on any indexable receiver; primarily meant for bool[]/BoolArray.
  if recv_node != nil && method_name == "flip" && node.block == nil && node.args != nil && node.args.size() == 1
    idx_node = node.args[0]
    get_call = Tungsten:AST:Call.new(recv_node, "\[]", [idx_node])
    set_call = Tungsten:AST:Call.new(recv_node, "\[]=", [idx_node, Tungsten:AST:Not.new(get_call)])
    return lower_method_call(ctx, set_call)

  # Block passthrough: a trailing block on a method that declares no block of
  # its own is NOT consumed by that method — it iterates over the call's
  # RESULT (implicit `.each`). So `n.prev -> body` runs `body` (n-1) times,
  # while `arr.map -> body` is untouched because `map` is a known block method.
  # This makes `@1.prev -> result *= self` (Hypercomplex#**) work and removes
  # the arity-mismatch "undefined method" a no-block method hit on a block.
  if node.block != nil && is_ast_node?(node.block) && method_takes_no_block?(ctx[:mod], method_name)
    inner = Tungsten:AST:Call.new(recv_node, method_name, node.args, nil)
    outer = Tungsten:AST:Call.new(inner, "each", [], node.block)
    return lower_method_call(ctx, outer)

  # Integer parity/divisibility predicates on an integer-literal receiver
  # (`4.even?`) lower to inline arithmetic. These live on the numeric-tower
  # Int class but integer literals dispatch to the (method-less) Integer
  # class, so a runtime call would not resolve — emit `% 2 == 0` directly,
  # the same way Math.sqrt/to_s are intrinsics rather than core dispatch.
  if recv_node != nil && ast_kind(recv_node) == :int
    if method_name == "even?" && node.args.size() == 0
      return lower_expression(ctx, Tungsten:AST:BinaryOp.new(Tungsten:AST:BinaryOp.new(recv_node, :PERCENT, Tungsten:AST:Int.new(2)), :EQ, Tungsten:AST:Int.new(0)))
    if method_name == "odd?" && node.args.size() == 0
      return lower_expression(ctx, Tungsten:AST:BinaryOp.new(Tungsten:AST:BinaryOp.new(recv_node, :PERCENT, Tungsten:AST:Int.new(2)), :NEQ, Tungsten:AST:Int.new(0)))
    if method_name == "divisible_by?" && node.args.size() == 1
      return lower_expression(ctx, Tungsten:AST:BinaryOp.new(Tungsten:AST:BinaryOp.new(recv_node, :PERCENT, node.args[0]), :EQ, Tungsten:AST:Int.new(0)))

  # prime?/prime_12k?/prime_30k? on a KNOWN-Int receiver (literal or a value
  # whose static type is integer-like) → a direct raw C call, skipping the
  # WValue method/IC dispatch that a boxed receiver would otherwise pay per
  # call in an ordinary loop. Returns :i1 like the parity predicates above, so
  # it boxes to true/false as a value and feeds `if` conditions with no box.
  if recv_node != nil && node.block == nil && (node.args == nil || node.args.size() == 0) && method_name in ("prime?" "prime_12k?" "prime_30k?")
    pr_type = receiver_static_type(ctx, recv_node)
    # Exclude :u64/:raw_u64 — a value in [2^63,2^64) would trip w_prime_test_i64's
    # signed n<0 guard (the boxed path routes those through the exact bigint test).
    # This also excludes huge int literals (typed bigint, not integer-like).
    if is_integer_like_type(pr_type) && pr_type != :u64 && pr_type != :raw_u64
      pr_helper = "w_prime_test_i64"
      if method_name == "prime_12k?"
        pr_helper = "w_prime_test_i64_12k"
      if method_name == "prime_30k?"
        pr_helper = "w_prime_test_i64_30k"
      pr_raw = ensure_raw_machine_int(wfn, lower_expression(ctx, recv_node), :i64, pr_type)
      pr_res = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: pr_res, name: pr_helper, args: [pr_raw]})
      pr_bit = next_temp(wfn)
      emit_instruction(wfn, {op: :icmp_i64, temp: pr_bit, pred: "ne", lhs: pr_res, rhs: "0"})
      return typed_value(:i1, pr_bit)

  # Symbol-to-proc for Enumerable methods on a collection receiver:
  # `coll.count(:prime?)` / `.map(:sym)` / `.select(:sym)` / `.reject(:sym)`
  # lower like the `/sym` pipeline (send `sym` to each element, then map/filter/
  # count). The interpreter does this via apply_iteratee; mirroring it here
  # keeps -o in agreement with -e/--wit. Single symbol arg, no block, and a
  # collection-shaped receiver (literal ints/strings can't be a pipeline base).
  if recv_node != nil && node.block == nil && node.args != nil && node.args.size() == 1 && is_ast_node?(node.args[0]) && ast_kind(node.args[0]) == :symbol && ast_kind(recv_node) in (:range :array :var :call :map :calc) && method_name in ("map" "select" "reject" "count")
    per_elem = Tungsten:AST:Call.new(nil, "" + ast_get(node.args[0], :value), [], nil)
    if method_name == "map"
      return lower_expression(ctx, Tungsten:AST:Map.new(recv_node, per_elem, :map))
    if method_name == "select"
      return lower_expression(ctx, Tungsten:AST:Map.new(recv_node, per_elem, :select))
    if method_name == "reject"
      return lower_expression(ctx, Tungsten:AST:Map.new(recv_node, per_elem, :reject))
    if method_name == "count"
      return lower_expression(ctx, Tungsten:AST:Calc.new("count", Tungsten:AST:Map.new(recv_node, per_elem, :map), :auto))

  # Closure-escape Phase B (#61): rewrite `arr.<iter>(args..., cb)` into
  # `arr.<iter>(args...) -> ...` when cb is a single-assignment local bound
  # to a block literal. The trait body (Enumerable's map/select/reduce/etc.)
  # then runs with the user's block in `&(...)` position; the existing
  # .each rewrite further inlines the trait's outer iteration. Conservative
  # model: only fires when the call has no explicit block and the LAST arg
  # is a simple :var lookup. Multi-arg iter methods (reduce(init, &) being
  # the canonical case) are now covered too.
  if recv_node != nil && node.block == nil && node.args != nil && node.args.size() >= 1 && ctx[:closure_bindings] != nil
    if inline_closure_arg_iterator_method?(method_name)
      last_idx = node.args.size() - 1
      last_arg = node.args[last_idx]
      if last_arg != nil && is_ast_node?(last_arg) && ast_kind(last_arg) == :var
        bound = ctx[:closure_bindings][last_arg.name]
        if bound != nil
          # Drop the closure arg from positional args; pass it as the block.
          new_args = []
          ai = 0
          while ai < last_idx
            new_args.push(node.args[ai])
            ai += 1
          synthetic = Tungsten:AST:Call.new(recv_node, method_name, new_args, bound)
          return lower_method_call(ctx, synthetic)

  # Thread.new -> ... creates an OS thread around the block closure. Thread is a
  # runtime primitive, so bypass class lookup here just like Atomic.new.
  if recv_node != nil && ast_kind(recv_node) in (:var :call :class_ref) && recv_node.name == "Thread" && method_name == "new" && node.block != nil
    materialize_bindings(ctx)
    closure_tv = lower_block_closure(ctx, node.block)
    closure_reg = ensure_i64_value(wfn, closure_tv)
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_thread_spawn_slots", args: [closure_reg]})
    return typed_value(:i64, temp)

  # `self.foo(...)` calls inside a class context dispatch directly when
  # foo is registered. Both class methods (`-> .foo`) and typed instance
  # methods (`fn foo`) populate known_static_methods; this gate only
  # cares about (a) the receiver being self_ref and (b) we're in a
  # known class. Untyped instance methods aren't registered so they
  # naturally fall through to w_method_call_cached.
  if recv_node != nil && ast_kind(recv_node) == :self_ref && ctx[:class_name] != nil
    static_key = ctx[:class_name] + "." + method_name
    static_info = ctx[:mod][:known_static_methods][static_key]
    if static_info != nil
      return lower_direct_static_method_call(ctx, static_info, recv_node, node.args)

  # NOTE: Per-method .map / .select / .reject lowering handlers were removed
  # here in favor of the trait-based path (core/traits/enumerable.w +
  # runtime/runtime.c WN_map/WN_select/WN_reject closure-dispatch loops).
  # The general-purpose replacement lives at the closure boundary: when a
  # closure passed to an iter call doesn't escape, inline its body into the
  # loop. That covers every Enumerable method uniformly (find, reduce, any?,
  # all?, count, ...) and user-defined block-taking methods (mutex.synchronize,
  # db.transaction, ...) without per-method AST synthesis. See task #61.

  # Range-elision (#49): if recv is a :var with a stashed range-literal
  # binding, substitute the range expression so the with-loop fast path
  # at `range.each` fires directly. The Range allocation from `r = (0...n)`
  # is left in place (eliding the assign would require escape analysis),
  # but the .each call avoids dispatching on the heap range and instead
  # iterates inline with the original bounds.
  if recv_node != nil && method_name == "each" && node.block != nil && ast_kind(recv_node) == :var && ctx[:range_bindings] != nil && ctx[:range_bindings][recv_node.name] != nil
    recv_node = ctx[:range_bindings][recv_node.name]

  recv_type = receiver_static_type(ctx, recv_node)

  # Quantity is an immediate/domain runtime value rather than a heap Instance,
  # so its metadata/equivalence methods lower directly instead of entering the
  # user-class method cache.
  recv_is_known_quantity = recv_type == :quantity || ast_kind(recv_node) == :quantity
  if !recv_is_known_quantity && ast_kind(recv_node) == :var && ctx[:quantity_dimensions] != nil
    recv_is_known_quantity = ctx[:quantity_dimensions][recv_node.name] != nil
  if recv_is_known_quantity && node.block == nil && method_name in ("point" "delta" "point?" "delta?" "origin" "equivalent" "equivalent_to")
    recv_tv = lower_expression(ctx, recv_node)
    call_args = [ensure_i64_value(wfn, recv_tv)]
    helper = "w_quantity_origin"
    if method_name == "point"
      helper = "w_quantity_point"
      annotation = node.args.size() == 0 ? Tungsten:AST:Symbol.new("default") : node.args[0]
      call_args.push(ensure_i64_value(wfn, lower_expression(ctx, annotation)))
    elsif method_name == "delta"
      helper = "w_quantity_delta"
      annotation = node.args.size() == 0 ? Tungsten:AST:Nil.new() : node.args[0]
      call_args.push(ensure_i64_value(wfn, lower_expression(ctx, annotation)))
    elsif method_name == "point?"
      helper = "w_quantity_point_p"
    elsif method_name == "delta?"
      helper = "w_quantity_delta_p"
    elsif method_name == "equivalent" || method_name == "equivalent_to"
      if node.args.size() != 2
        raise compile_error_for_node(:E_LOWER_QUANTITY_EQUIVALENCE, "quantity equivalence expects target unit and named bridge", ctx[:source_path], node)
      helper = "w_quantity_equivalent"
      call_args.push(ensure_i64_value(wfn, lower_expression(ctx, node.args[0])))
      call_args.push(ensure_i64_value(wfn, lower_expression(ctx, node.args[1])))
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: helper, args: call_args})
    return typed_value(:i64, temp)

  if recv_type == :array && call_has_ast_block?(node) && (node.args == nil || node.args.size() == 0) && inline_array_iterator_method?(method_name)
    inlined = lower_inline_array_iterator_call(ctx, recv_node, method_name, node.block)
    if inlined != nil
      return inlined

  if recv_node != nil && method_name == "each" && node.block != nil
    # Phase 6i follow-up: rewrite bare `$field` var receivers (the syntax
    # the .each iteration in core/{small,big,}_array.w each-bodies uses)
    # into :view_field nodes so the integer-iteration shortcut below
    # fires. Without this, `$size -> &(self[i])` dispatches `int.each(closure)`
    # and crashes with "undefined method 'each' for Integer".
    if ast_kind(recv_node) == :var && recv_node.name.starts_with?("$") && ctx[:class_name] != nil
      field = recv_node.name.slice(1, recv_node.name.size() - 1)
      info = view_field_info(ctx, field)
      if info != nil
        recv_node = Tungsten:AST:ViewField.new(field)
    recv_type = receiver_static_type(ctx, recv_node)
    if ast_kind(recv_node) in (:int :view_field) || is_integer_like_type(recv_type)
      range_node = Tungsten:AST:Range.new(Tungsten:AST:Int.new(0), recv_node, true)
      range_each = Tungsten:AST:Call.new(range_node, "each", [], node.block)
      return lower_method_call(ctx, range_each)

    # Phase 6g: typed-array.each (with explicit single block param) →
    # range with-loop over indices, with `param = recv[i]` synthesized
    # as the first body statement. Existing range.each path lowers as
    # a with-loop (no closure allocation, body inlined). Inside the
    # loop, `recv[i]` lowers to typed_array_get_inline (raw int) so
    # nothing is boxed in the inner loop. Eliminates the per-element
    # w_closure_call_1 function-call overhead.
    #
    # Only fires when:
    #   - receiver is a simple :var or `self` (avoids re-evaluating
    #     expressions with side effects like `make_arr().each(...)`)
    #   - block has exactly one explicit parameter (positional-ref
    #     blocks need different rewriting and aren't covered yet)
    if ast_kind(recv_node) in (:var :self_ref) && is_array_type?(recv_type) && call_has_ast_block?(node)
      block = node.block
      bparams = block.params
      # Implicit-free-var shape (`arr.each -> << v`) parses as block with
      # empty params and a body that references `v` as a free var.
      # Mirror the range.each path: collect free vars and use the first
      # as the iteration param name.
      if bparams == nil || bparams.size() == 0
        bparams = lower_block_free_vars(block, ctx)
      if bparams != nil && bparams.size() == 1
        param = bparams[0]
        param_name = nil
        if is_ast_node?(param) && param.name != nil
          param_name = param.name
        elsif type(param) == "String"
          param_name = param
        if param_name != nil && !param_name.starts_with?("&")
          # Allocate a unique iteration index variable
          idx_id = ctx[:mod][:next_block]
          ctx[:mod][:next_block] = idx_id + 1
          idx_name = "__each_idx_" + idx_id.to_s()
          # v = recv[idx_name]
          subscript_call = Tungsten:AST:Call.new(recv_node, "[]", [Tungsten:AST:Var.new(idx_name)], nil)
          elem_value_type = typed_array_element_value_type(recv_type)
          type_hint_val = nil
          if elem_value_type != nil
            type_hint_val = elem_value_type.to_s()
          v_assign = Tungsten:AST:Assign.new(Tungsten:AST:Var.new(param_name), subscript_call, type_hint_val)
          new_body = [v_assign]
          bi = 0
          while bi < block.body.size()
            new_body.push(block.body[bi])
            bi += 1
          # Use a bare string for the param (not a :param hash) — matches
          # the AST shape the parser produces for explicit block params,
          # which is what range.each / lower_with expect at params[0].
          new_block = Tungsten:AST:Block.new([idx_name], new_body)
          # (0...recv.size).each(new_block)
          size_call = Tungsten:AST:Call.new(recv_node, "size", [], nil)
          range_node = Tungsten:AST:Range.new(Tungsten:AST:Int.new(0), size_call, true)
          range_each = Tungsten:AST:Call.new(range_node, "each", [], new_block)
          return lower_method_call(ctx, range_each)

  # Range.each with block → lower as with-loop (scope-stack, no closure allocation)
  if recv_node != nil && ast_kind(recv_node) == :range && method_name == "each" && node.block != nil
    block = node.block
    params = block.params
    if params == nil || params.size() == 0
      params = lower_block_free_vars(block, ctx)
    param_name = "_"
    if params.size() > 0
      param_name = params[0]
    with_node = Tungsten:AST:With.new([[Tungsten:AST:Var.new(param_name), recv_node]], block.body)
    lower_with(ctx, with_node)
    # `.each` is a statement in Ruby — it doesn't produce a meaningful value.
    # But the method-body lowering treats any :call as value-producing and
    # passes the result into ensure_i64_value. Return a nil WValue so that
    # boundary doesn't receive nil (which crashes ensure_i64_value).
    return typed_value(:i64, w_nil.to_s())

  # Direct dispatch for built-in constructors (bypass method dispatch entirely).
  # :class_ref must be accepted alongside :var here — without it, ClassRef
  # receivers (PascalCase class names emitted by the parser) bypass the
  # static-method inlining at line 1213 and fall through to the runtime's
  # default `.new` handler, which silently returns a generic WObject
  # instead of invoking the user's slab `-> .new` static method.
  if recv_node != nil && ast_kind(recv_node) in (:var :class_ref :call) && recv_node.name != nil
    recv_name = recv_node.name
    if recv_name == "Response" && method_name == "new" && node.args.size() == 2
      status_val = lower_expression(ctx, node.args[0])
      status_reg = ensure_i64_value(wfn, status_val)
      body_val = lower_expression(ctx, node.args[1])
      body_reg = ensure_i64_value(wfn, body_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_response_new_wv", args: [status_reg, body_reg]})
      return typed_value(:i64, temp)

    if recv_name == "Atomic" && method_name == "new" && node.args.size() == 1
      init_val = lower_expression(ctx, node.args[0])
      init_reg = ensure_i64_value(wfn, init_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_atomic_new", args: [init_reg]})
      return typed_value(:i64, temp)

    if recv_name == "Channel" && method_name == "new" && node.args.size() == 1
      size_val = lower_expression(ctx, node.args[0])
      size_reg = ensure_i64_value(wfn, size_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_chan_new", args: [size_reg]})
      return typed_value(:i64, temp)

    # Phase 3: BigArray.new(ebits, capacity) — i64-indexed array tier.
    # ebits is symbol (:u8, :i32, :f32, :w64, :bf16, …) or raw int (16/32/64/-32/…).
    if recv_name == "BigArray" && method_name == "new" && node.args.size() == 2
      ebits_raw = ebits_arg_to_raw(ctx, node.args[0])
      cap_val = lower_expression(ctx, node.args[1])
      cap_raw = ensure_raw_machine_int(wfn, cap_val, :i64, infer_type(node.args[1], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps))
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_big_array_new", args: [ebits_raw, cap_raw]})
      return typed_value(:i64, temp)

    # Phase 3: SmallArray.new(ebits, size) — frozen ≤255-element packed
    # array. Zero-initialized; richer from-bytes / from-array constructors
    # land alongside the SmallArray inline ops in Phase 5. Third arg is a
    # raw int byte-pointer (0 → leave the calloc-zeroed payload).
    #
    # Phase 6d: when `## stack` annotation is present (or Phase 6e's
    # escape analysis deems the allocation non-escaping) AND both ebits
    # and size are compile-time int literals, emit LLVM `alloca` instead
    # of a heap calloc. The alloca lives in the current frame; misuse
    # (escape) is the user's responsibility until 6e is automatic.
    if recv_name == "SmallArray" && method_name == "new" && node.args.size() == 2
      ebits_arg = node.args[0]
      size_arg = node.args[1]
      stack_safe = node.stack_safe == true
      ebits_const = ebits_const_value(ebits_arg)
      size_const = nil
      if ast_kind(size_arg) == :int
        size_const = size_arg.value
      if stack_safe && ebits_const != nil && size_const != nil && size_const >= 0 && size_const <= 255
        # Phase 6h: WSmallArray header is 2 bytes (ebits + size); slots
        # start at offset 2. Total = 2 + packed payload bytes.
        payload_bytes = small_array_payload_bytes(ebits_const, size_const)
        total_bytes = 2 + payload_bytes
        temp_ptr = next_temp(wfn)
        temp_int = next_temp(wfn)
        temp_box = next_temp(wfn)
        emit_instruction(wfn, {op: :small_array_alloca, temp_ptr: temp_ptr, total_bytes: total_bytes})
        emit_instruction(wfn, {op: :ptr_to_i64, temp: temp_int, value: temp_ptr})
        emit_instruction(wfn, {op: :call_direct_i64, temp: temp_box, name: "w_small_array_init", args: [temp_int, ebits_const.to_s(), size_const.to_s()]})
        return typed_value(:i64, temp_box)
      ebits_raw = ebits_arg_to_raw(ctx, ebits_arg)
      size_val = lower_expression(ctx, size_arg)
      size_raw = ensure_raw_machine_int(wfn, size_val, :i64, infer_type(size_arg, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps))
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_small_array_new", args: [ebits_raw, size_raw, "0"]})
      return typed_value(:i64, temp)

    static_key = recv_name + "." + method_name
    static_info = ctx[:mod][:known_static_methods][static_key]
    if static_info != nil
      return lower_direct_static_method_call(ctx, static_info, recv_node, node.args)

    # File module methods → direct runtime calls
    if recv_name == "File"
      args = expand_kwargs(node.args)
      if method_name == "read" && args.size() == 1
        path_val = lower_expression(ctx, args[0])
        path_reg = ensure_i64_value(wfn, path_val)
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "__w_read_file", args: [path_reg]})
        return typed_value(:i64, temp)
      if method_name == "read_bytes" && args.size() == 1
        path_val = lower_expression(ctx, args[0])
        path_reg = ensure_i64_value(wfn, path_val)
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "__w_read_file_bytes", args: [path_reg]})
        return typed_value(:i64, temp)
      if method_name == "write" && args.size() == 2
        path_val = lower_expression(ctx, args[0])
        path_reg = ensure_i64_value(wfn, path_val)
        content_val = lower_expression(ctx, args[1])
        content_reg = ensure_i64_value(wfn, content_val)
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "__w_write_file", args: [path_reg, content_reg]})
        return typed_value(:i64, temp)
      if method_name in ("exist?" "exists?") && args.size() == 1
        path_val = lower_expression(ctx, args[0])
        path_reg = ensure_i64_value(wfn, path_val)
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "__w_file_exists", args: [path_reg]})
        return typed_value(:i64, temp)
      if method_name in ("directory?" "dir?") && args.size() == 1
        path_val = lower_expression(ctx, args[0])
        path_reg = ensure_i64_value(wfn, path_val)
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "__w_file_directory", args: [path_reg]})
        return typed_value(:i64, temp)
      if method_name in ("entries" "read_dir") && args.size() == 1
        path_val = lower_expression(ctx, args[0])
        path_reg = ensure_i64_value(wfn, path_val)
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "__w_file_read_dir", args: [path_reg]})
        return typed_value(:i64, temp)
      if method_name == "size" && args.size() == 1
        path_val = lower_expression(ctx, args[0])
        path_reg = ensure_i64_value(wfn, path_val)
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "__w_file_size", args: [path_reg]})
        return typed_value(:i64, temp)
      if method_name == "mtime_ns" && args.size() == 1
        path_val = lower_expression(ctx, args[0])
        path_reg = ensure_i64_value(wfn, path_val)
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "__w_file_mtime_ns", args: [path_reg]})
        return typed_value(:i64, temp)
      if method_name == "expand_path" && args.size() >= 1
        path_val = lower_expression(ctx, args[0])
        path_reg = ensure_i64_value(wfn, path_val)
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "__w_file_expand_path", args: [path_reg]})
        return typed_value(:i64, temp)
      if method_name == "join"
        arg_regs = []
        i = 0
        while i < args.size()
          val = lower_expression(ctx, args[i])
          arg_regs.push(ensure_i64_value(wfn, val))
          i += 1
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "__w_file_join", args: arg_regs})
        return typed_value(:i64, temp)
      if method_name == "mmap" && args.size() == 1
        path_val = lower_expression(ctx, args[0])
        path_reg = ensure_i64_value(wfn, path_val)
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "__w_file_mmap", args: [path_reg]})
        return typed_value(:i64, temp)

    if recv_name == "OS"
      args = expand_kwargs(node.args)
      os_target = nil
      if method_name == "capture"
        os_target = "__w_capture"
      elsif method_name == "system"
        os_target = "__w_system"
      elsif method_name == "read_file"
        os_target = "__w_read_file"
      elsif method_name == "read_file_bytes"
        os_target = "__w_read_file_bytes"
      elsif method_name in ("file?" "exists?")
        os_target = "__w_file_exists"
      elsif method_name == "directory?"
        os_target = "__w_file_directory"
      elsif method_name == "read_dir"
        os_target = "__w_file_read_dir"
      elsif method_name == "file_size"
        os_target = "__w_file_size"
      elsif method_name == "file_mtime_ns"
        os_target = "__w_file_mtime_ns"
      if os_target != nil && args.size() == 1
        arg_val = lower_expression(ctx, args[0])
        arg_reg = ensure_i64_value(wfn, arg_val)
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: os_target, args: [arg_reg]})
        return typed_value(:i64, temp)
      if method_name == "write_file" && args.size() == 2
        path_val = lower_expression(ctx, args[0])
        path_reg = ensure_i64_value(wfn, path_val)
        content_val = lower_expression(ctx, args[1])
        content_reg = ensure_i64_value(wfn, content_val)
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "__w_write_file", args: [path_reg, content_reg]})
        return typed_value(:i64, temp)

    if recv_name == "Digest"
      args = expand_kwargs(node.args)
      digest_target = nil
      if method_name == "bytes64"
        digest_target = "__w_digest_bytes64"
      elsif method_name == "file64"
        digest_target = "__w_digest_file64"
      elsif method_name == "string64"
        digest_target = "__w_digest_string64"
      if digest_target != nil && args.size() == 1
        arg_val = lower_expression(ctx, args[0])
        arg_reg = ensure_i64_value(wfn, arg_val)
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: digest_target, args: [arg_reg]})
        return typed_value(:i64, temp)

    # Math.* libm wrappers — direct runtime calls.
    if recv_name == "Math"
      args = expand_kwargs(node.args)
      math_unary = nil
      if method_name == "exp"
        math_unary = "w_math_exp"
      elsif method_name == "log"
        math_unary = "w_math_log"
      elsif method_name == "sin"
        math_unary = "w_math_sin"
      elsif method_name == "cos"
        math_unary = "w_math_cos"
      elsif method_name == "tan"
        math_unary = "w_math_tan"
      elsif method_name == "sqrt"
        math_unary = "w_math_sqrt"
      elsif method_name == "floor"
        math_unary = "w_math_floor"
      elsif method_name == "ceil"
        math_unary = "w_math_ceil"
      elsif method_name == "round"
        math_unary = "w_math_round"
      elsif method_name == "abs"
        math_unary = "w_math_abs"
      if math_unary != nil && args.size() == 1
        arg_val = lower_expression(ctx, args[0])
        # Raw fast path: operand is already an unboxed machine number — call
        # libm directly on the double (call_libm_f64) and stay raw, skipping
        # the box → w_math_* → unbox → re-box round-trip. Boxed WValues keep
        # the runtime path: they carry Int/Float dynamically and
        # w_math_to_double resolves that at runtime.
        if arg_val[:type] in (:raw_f64 :raw_f32 :raw_int :raw_i64 :raw_u64)
          libm_name = method_name
          if method_name == "abs"
            libm_name = "fabs"
          arg_raw = ensure_raw_f64(wfn, arg_val)
          temp = next_temp(wfn)
          emit_instruction(wfn, {op: :call_libm_f64, temp: temp, name: libm_name, value: arg_raw})
          return typed_value(:raw_f64, temp)
        arg_reg = ensure_i64_value(wfn, arg_val)
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: math_unary, args: [arg_reg]})
        return typed_value(:i64, temp)
      if method_name in ("pow" "ldexp" "atan2") && args.size() == 2
        a_val = lower_expression(ctx, args[0])
        b_val = lower_expression(ctx, args[1])
        # Raw fast path for the pure-libm pair (ldexp's second arg is an
        # int, so it stays on the runtime path). Both operands must already
        # be raw — a boxed WValue needs w_math_to_double's dynamic Int/Float
        # handling.
        if method_name in ("pow" "atan2")
          if a_val[:type] in (:raw_f64 :raw_f32 :raw_int :raw_i64 :raw_u64) && b_val[:type] in (:raw_f64 :raw_f32 :raw_int :raw_i64 :raw_u64)
            a_raw = ensure_raw_f64(wfn, a_val)
            b_raw = ensure_raw_f64(wfn, b_val)
            temp = next_temp(wfn)
            emit_instruction(wfn, {op: :call_libm_f64, temp: temp, name: method_name, lhs: a_raw, rhs: b_raw})
            return typed_value(:raw_f64, temp)
        a_reg = ensure_i64_value(wfn, a_val)
        b_reg = ensure_i64_value(wfn, b_val)
        rt_name = "w_math_pow"
        if method_name == "ldexp"
          rt_name = "w_math_ldexp"
        elsif method_name == "atan2"
          rt_name = "w_math_atan2"
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: rt_name, args: [a_reg, b_reg]})
        return typed_value(:i64, temp)

    # Float.from_u32_bits / to_u32_bits / from_u64_bits / to_u64_bits —
    # reinterpret integer bits as a float (or back). Needed for GGUF
    # dequant and any other binary-format work.
    if recv_name == "Float"
      args = expand_kwargs(node.args)
      bitcast_fn = nil
      if method_name == "from_u32_bits"
        bitcast_fn = "w_float_from_u32_bits"
      elsif method_name == "to_u32_bits"
        bitcast_fn = "w_float_to_u32_bits"
      elsif method_name == "from_u64_bits"
        bitcast_fn = "w_float_from_u64_bits"
      elsif method_name == "to_u64_bits"
        bitcast_fn = "w_float_to_u64_bits"
      if bitcast_fn != nil && args.size() == 1
        arg_val = lower_expression(ctx, args[0])
        arg_reg = ensure_i64_value(wfn, arg_val)
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: bitcast_fn, args: [arg_reg]})
        return typed_value(:i64, temp)

  # range.each(block) → inline for-loop (no array allocation)
  if recv_node != nil && ast_kind(recv_node) == :range && method_name == "each" && node.block != nil
    range_node = recv_node
    block = node.block

    # Lower bounds
    from_tv = lower_expression(ctx, range_node.from)
    from_reg = ensure_i64_value(wfn, from_tv)
    to_tv = lower_expression(ctx, range_node.to)
    to_reg = ensure_i64_value(wfn, to_tv)

    # nanunbox_int_emit is raw bit extraction with no type check — correct
    # only when the bound is genuinely an inline-boxed int. A bound that's
    # statically known non-int (e.g. a Decimal literal like `1e10`, common
    # scientific-notation shorthand for a big integer) would otherwise
    # silently reinterpret its sig/scale bits as a small garbage int
    # (`(1..1e10)` iterating ~130 times instead of ten billion). Route
    # those through w_range_bound_i64 (real type check + coercion,
    # catchable TypeError on a non-whole bound) instead; leave the fast
    # nanunbox path untouched for the common case (known int, or a
    # non-statically-typed expression that's an int at runtime).
    from_static_type = infer_type(range_node.from, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    to_static_type = infer_type(range_node.to, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    if from_static_type != nil && !is_integer_like_type(from_static_type)
      from_raw = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: from_raw, name: "w_range_bound_i64", args: [from_reg]})
    else
      from_raw = nanunbox_int_emit(wfn, from_reg)
    if to_static_type != nil && !is_integer_like_type(to_static_type)
      to_raw = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: to_raw, name: "w_range_bound_i64", args: [to_reg]})
    else
      to_raw = nanunbox_int_emit(wfn, to_reg)

    # Materialize bindings before the loop (for capture correctness)
    materialize_bindings(ctx)

    pre_label = next_label(wfn, "each.pre")
    header_label = next_label(wfn, "each.hdr")
    body_label = next_label(wfn, "each.body")
    exit_label = next_label(wfn, "each.exit")

    emit_instruction(wfn, {op: :br, label: pre_label})
    start_block(wfn, pre_label)
    emit_instruction(wfn, {op: :br, label: header_label})

    start_block(wfn, header_label)
    phi_reg = next_temp(wfn)
    inc_reg = next_temp(wfn)
    emit_instruction(wfn, {op: :phi_i64, temp: phi_reg, a_value: from_raw, a_label: pre_label, b_value: inc_reg, b_label: body_label})

    cmp_op = "sle"
    if range_node.exclusive == true
      cmp_op = "slt"
    cmp_reg = next_temp(wfn)
    emit_instruction(wfn, {op: :icmp_i64, temp: cmp_reg, pred: cmp_op, lhs: phi_reg, rhs: to_raw})
    emit_instruction(wfn, {op: :cond_br, cond: cmp_reg, then_label: body_label, else_label: exit_label})

    # Body: box counter, bind block param, execute body inline
    start_block(wfn, body_label)
    boxed_i = next_temp(wfn)
    emit_instruction(wfn, {op: :nanbox_int, temp: boxed_i, temp_masked: boxed_i + ".m", raw: phi_reg})

    # Bind the iteration variable (named param or first free var)
    block_params = block.params
    if block_params.size() == 0
      block_params = lower_block_free_vars(block, ctx)
    if block_params.size() > 0
      param_name = block_params[0]
      ptr = ensure_var_slot(wfn, param_name)
      emit_instruction(wfn, {op: :store_i64, value: boxed_i, ptr: ptr})
      ctx[:var_types][param_name] = :int

    # Lower block body inline
    if block.body != nil
      bi = 0
      while bi < block.body.size()
        if block_terminated(wfn)
          break
        lower_statement(ctx, block.body[bi])
        bi += 1

    if !block_terminated(wfn)
      # Find the actual back-edge label: if any instruction in the body created
      # inline blocks (checked arithmetic → ovf.merge.N), the phi must reference
      # the last merge block, not the original body label.
      back_label = body_label
      body_blk = current_block(wfn)
      body_instrs = body_blk[:instructions]
      bi2 = 0
      while bi2 < body_instrs.size()
        inst2 = body_instrs[bi2]
        if inst2[:op] in (:add_i48_checked :sub_i48_checked :mul_i48_checked)
          back_label = "ovf.merge." + inst2[:block_id].to_s()
        bi2 += 1

      emit_instruction(wfn, {op: :add_i64, temp: inc_reg, lhs: phi_reg, rhs: "1"})
      emit_instruction(wfn, {op: :br, label: header_label})

      # Patch the phi's back-edge label
      hdr_block = nil
      bi = 0
      while bi < wfn[:blocks].size()
        if wfn[:blocks][bi][:label] == header_label
          hdr_block = wfn[:blocks][bi]
          break
        bi += 1
      if hdr_block != nil
        pi = 0
        while pi < hdr_block[:instructions].size()
          inst = hdr_block[:instructions][pi]
          if inst[:op] == :phi_i64 && inst[:b_label] == body_label
            inst[:b_label] = back_label
          pi += 1

    start_block(wfn, exit_label)
    return typed_value(:i64, w_nil.to_s())

  # arr[from..to] or arr[from...to] → zero-copy view via
  # w_array_view_range. Phase 4e: was a copy through w_array_copy_range;
  # the plan calls for view semantics by default (Rust-style explicit
  # aliasing — mutations to the slice affect the parent). Callers that
  # want the legacy copy can explicitly call `arr.copy(from, len)`.
  if method_name == "\[]" && node.args.size() == 1 && ast_kind(node.args[0]) == :range
    receiver_val = lower_expression(ctx, recv_node)
    receiver_reg = ensure_i64_value(wfn, receiver_val)
    range_node = node.args[0]
    from_val = lower_expression(ctx, range_node.from)
    from_reg = ensure_i64_value(wfn, from_val)
    to_val = lower_expression(ctx, range_node.to)
    to_reg = ensure_i64_value(wfn, to_val)
    excl_reg = w_false.to_s()
    if range_node.exclusive in (true 2)
      excl_reg = w_true.to_s()
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_array_view_range", args: [receiver_reg, from_reg, to_reg, excl_reg]})
    return typed_value(:i64, temp)

  # Range#step(n): same desugar as `range / n` (lower_range_step in ops.w) —
  # exposed as a method too since `range / n` needs a space before the `/`
  # to avoid lexing as the `/name` pipeline-map operator.
  if method_name == "step" && node.args != nil && node.args.size() == 1 && recv_node != nil && ast_kind(recv_node) == :range
    return lower_range_step(ctx, recv_node, node.args[0], node.block)

  # Range#to_a optimization: (0..255).to_a → pre-sized array
  if method_name == "to_a" && node.args.size() == 0 && recv_node != nil && ast_kind(recv_node) == :range
    from_node = recv_node.from
    to_node = recv_node.to
    if from_node != nil && ast_kind(from_node) == :int && to_node != nil && ast_kind(to_node) == :int
      from_v = from_node.value
      to_v = to_node.value
      size = to_v - from_v
      if recv_node.exclusive != true
        size = size + 1
      # Emit: create array, push each value in a loop
      arr_temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: arr_temp, name: "w_array_new_empty", args: []})
      # Use a compile-time unrolled fill if small enough, otherwise emit a loop
      if size <= 256
        i = 0
        while i < size
          val_temp = next_temp(wfn)
          emit_instruction(wfn, {op: :nanbox_int, temp: val_temp, temp_masked: next_temp(wfn), raw: (from_v + i).to_s()})
          push_temp = next_temp(wfn)
          emit_instruction(wfn, {op: :call_direct_i64, temp: push_temp, name: "w_array_push", args: [arr_temp, val_temp]})
          i += 1
        return typed_value(:i64, arr_temp)

  # Infer receiver type for direct dispatch
  recv_type = nil
  if recv_node != nil && ast_kind(recv_node) == :var
    recv_type = ctx[:var_types][recv_node.name]
  elsif recv_node != nil && ast_kind(recv_node) == :self_ref
    # Phase 5: transitive composition. Inside a specialized method, __self
    # carries the variant type so self.foo() inside re-specializes foo.
    recv_type = ctx[:var_types]["__self"]
  elsif recv_node != nil && ast_kind(recv_node) == :ivar && ctx[:class_name] != nil
    # Phase 5 (gap #2): self.@arr.method() — look up the ivar's recorded
    # type from the class-level pre-pass. nil here means either the ivar
    # was never written with an inferable type, or had conflicting writes
    # (so we bail to runtime dispatch, which is correct behavior).
    class_ivars = ctx[:mod][:ivar_types][ctx[:class_name]]
    if class_ivars != nil
      recv_type = class_ivars[recv_node.name]

  # Universal: .class returns the runtime class (class-tagged WValue);
  # .class_name returns the class name (string). Works for any receiver —
  # primitives, instances, and class objects themselves. Dispatch is via
  # the g_type_class table the runtime IC already maintains, with a
  # name-based fallback for classes that haven't registered a dispatch key.
  if recv_node != nil && method_name == "class" && node.args.size() == 0
    receiver_val = lower_expression(ctx, recv_node)
    receiver_reg = ensure_i64_value(wfn, receiver_val)
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_class_of", args: [receiver_reg]})
    return typed_value(:i64, temp)

  if recv_node != nil && method_name == "class_name" && node.args.size() == 0
    receiver_val = lower_expression(ctx, recv_node)
    receiver_reg = ensure_i64_value(wfn, receiver_val)
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_class_name", args: [receiver_reg]})
    return typed_value(:i64, temp)

  # Direct builtins for StringBuffer operations when receiver type is known.
  if recv_type == :string_buffer
    if method_name in ("append" "<<" "<</1") && node.args.size() == 1
      arg_type = infer_type(node.args[0], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
      if arg_type == :string
        receiver_val = lower_expression(ctx, recv_node)
        receiver_reg = ensure_i64_value(wfn, receiver_val)
        arg_val = lower_expression(ctx, node.args[0])
        arg_reg = ensure_i64_value(wfn, arg_val)
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_strbuf_append", args: [receiver_reg, arg_reg]})
        return typed_value(:i64, temp)

    if method_name == "to_s" && node.args.size() == 0
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_strbuf_to_s", args: [receiver_reg]})
      return typed_value(:i64, temp)

  # Strings are represented as immutable WValues. Methods that are mutable in
  # the language update a simple variable receiver by rebinding it to the newly
  # constructed string and returning that value.
  if recv_type == :string && recv_node != nil && ast_kind(recv_node) == :var
    if method_name in ("concat" "append" "<<" "<</1") && node.args.size() == 1
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      arg_val = lower_expression(ctx, node.args[0])
      arg_reg = ensure_i64_value(wfn, arg_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_str_append", args: [receiver_reg, arg_reg]})
      return rebind_local_i64(ctx, recv_node.name, temp, :string)

    if method_name == "prepend" && node.args.size() == 1
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      arg_val = lower_expression(ctx, node.args[0])
      arg_reg = ensure_i64_value(wfn, arg_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_str_concat", args: [arg_reg, receiver_reg]})
      return rebind_local_i64(ctx, recv_node.name, temp, :string)

  # Inside an array-tier class method, `self` is known even when its concrete
  # element type is only available at runtime. Route storage primitives
  # directly through the tier's dynamic decoder; assigning the broad `:array`
  # type here would be unsound because `array_get_inline` assumes w64 slots.
  if ast_kind(recv_node) == :self_ref && ctx[:class_name] in ("Array" "BigArray" "SmallArray")
    size_helper = "w_array_size"
    idx_helper = "w_array_idx"
    if ctx[:class_name] == "BigArray"
      size_helper = "w_big_array_size"
      idx_helper = "w_big_array_idx"
    elsif ctx[:class_name] == "SmallArray"
      size_helper = "w_small_array_size"
      idx_helper = "w_small_array_idx"
    if method_name == "size" && node.args.size() == 0
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: size_helper, args: [receiver_reg]})
      return typed_value(:i64, temp)
    if method_name == "\[]" && node.args.size() == 1
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      idx_val = lower_expression(ctx, node.args[0])
      # A raw machine-int index (promoted loop var) skips the w_int box +
      # w_as_int unbox pair via the raw-index runtime twin — the dominant
      # per-element cost of core/array.w method loops.
      if idx_helper == "w_array_idx" && idx_val[:type] in (:raw_int :raw_i64 :raw_u64)
        idx_raw = ensure_raw_int(wfn, idx_val)
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "__w_array_idx_i64_fast", args: [receiver_reg, idx_raw]})
        return typed_value(:i64, temp)
      idx_reg = ensure_i64_value(wfn, idx_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: idx_helper, args: [receiver_reg, idx_reg]})
      return typed_value(:i64, temp)

  # Direct builtins for array operations — only when receiver is known to be an array
  if recv_type == :array
    if method_name == "push" && node.args.size() == 1
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      arg_val = lower_expression(ctx, node.args[0])
      arg_reg = ensure_i64_value(wfn, arg_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_array_push", args: [receiver_reg, arg_reg]})
      return typed_value(:i64, temp)

    if method_name == "pop" && node.args.size() == 0
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_array_pop", args: [receiver_reg]})
      return typed_value(:i64, temp)

    if method_name == "shift" && node.args.size() == 0
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_array_shift", args: [receiver_reg]})
      return typed_value(:i64, temp)

    if method_name == "cap" && node.args.size() == 0
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_array_cap", args: [receiver_reg]})
      return typed_value(:i64, temp)

    if recv_type == :array && method_name == "size" && node.args.size() == 0
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_array_size", args: [receiver_reg]})
      return typed_value(:i64, temp)


    if method_name == "\[]" && node.args.size() == 1
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      idx_val = lower_expression(ctx, node.args[0])
      cs_id = nil
      if node.line != nil
        cs_id = next_call_site_id(ctx[:mod])
      # Raw machine-int index: same negative-wrap/nil-on-OOB semantics via
      # the raw twin, minus the per-element box/unbox pair.
      if idx_val[:type] in (:raw_int :raw_i64 :raw_u64)
        idx_raw = ensure_raw_int(wfn, idx_val)
        temp = next_temp(wfn)
        emit_instruction(wfn, {
          op: :call_direct_i64, temp: temp, name: "__w_array_get_i64_fast",
          args: [receiver_reg, idx_raw],
          src_line: node.line, src_col: node.col, loc_site_id: cs_id
        })
        return typed_value(:i64, temp)
      idx_reg = ensure_i64_value(wfn, idx_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {
        op: :call_direct_i64, temp: temp, name: "w_array_get",
        args: [receiver_reg, idx_reg],
        src_line: node.line, src_col: node.col, loc_site_id: cs_id
      })
      return typed_value(:i64, temp)

    if method_name == "\[]=" && node.args.size() == 2
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      idx_val = lower_expression(ctx, node.args[0])
      idx_reg = ensure_i64_value(wfn, idx_val)
      val_expr = lower_expression(ctx, node.args[1])
      val_reg = ensure_i64_value(wfn, val_expr)
      temp = next_temp(wfn)
      cs_id = nil
      if node.line != nil
        cs_id = next_call_site_id(ctx[:mod])
      emit_instruction(wfn, {
        op: :call_direct_i64, temp: temp, name: "w_array_set",
        args: [receiver_reg, idx_reg, val_reg],
        src_line: node.line, src_col: node.col, loc_site_id: cs_id
      })
      return typed_value(:i64, temp)

  # Direct builtins for bool array operations — inline bit manipulation.
  # Both :bool_array (BoolArray class) and :typed_array_bool (u1[] from a
  # typed `- data` field or `u1[N]` constructor) hit the same ebits=1
  # WArray layout, so the same inline ops apply.
  if recv_type == :bool_array || recv_type == :typed_array_bool
    if method_name == "\[]" && node.args.size() == 1
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      # ensure_raw_int passes through `:raw_int` values (e.g. `num >> 1`)
      # without the round-trip through w_int + nanunbox that the prior
      # ensure_i64_value + nanunbox_int_emit pair forced.
      idx_val = lower_expression(ctx, node.args[0])
      idx_raw = ensure_raw_int(wfn, idx_val)
      temp = next_temp(wfn)
      # `as_i1: true` keeps the inline-op output as a raw bit (icmp ne).
      # Returning :i1 lets `if`/`while`/`!` consumers branch on it
      # directly; ensure_i64_value re-boxes via nanbox_bool when a
      # caller (e.g. assignment, hash insert) wants W_TRUE/W_FALSE.
      emit_instruction(wfn, {op: :bool_array_get_inline, temp: temp, arr: receiver_reg, idx: idx_raw, as_i1: true})
      return typed_value(:i1, temp)

    if method_name == "\[]=" && node.args.size() == 2
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      idx_val = lower_expression(ctx, node.args[0])
      idx_raw = ensure_raw_int(wfn, idx_val)
      # Translate int 0/1 to false/true at compile time for bool[] set
      val_node = node.args[1]
      if ast_kind(val_node) == :int && val_node.value == 0
        val_reg = w_false.to_s()
      elsif ast_kind(val_node) == :int && val_node.value == 1
        val_reg = w_true.to_s()
      else
        val_expr = lower_expression(ctx, val_node)
        val_reg = ensure_i64_value(wfn, val_expr)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :bool_array_set_inline, temp: temp, arr: receiver_reg, idx: idx_raw, val: val_reg})
      return typed_value(:i64, temp)

    if method_name == "size" && node.args.size() == 0
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_bool_array_size", args: [receiver_reg]})
      return typed_value(:i64, temp)

  # BigArray direct ops. BigArray has the same packed element semantics as
  # WArray, but a different C layout (i64 start/size/cap, slots at offset 32).
  # Keeping these before Phase 5 specialization lets the typed-array `each`
  # rewrite turn `big[i]` into a direct load instead of a cached dispatch.
  if is_big_array_type?(recv_type)
    elem_type = small_array_to_typed_array_type(recv_type)
    if method_name == "size" && node.args.size() == 0
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_big_array_size", args: [receiver_reg]})
      return typed_value(:i64, temp)
    if method_name == "\[]" && node.args.size() == 1
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      idx_val = lower_expression(ctx, node.args[0])

      # Keep signed/unhandled payloads on the direct runtime idx helper:
      # it preserves today's BigArray boxing semantics while still avoiding
      # cached method dispatch. Unsigned integer, float, and w64 loads are raw.
      inline_raw_get = elem_type in (:typed_array_u4 :typed_array_u8 :typed_array_u16 :typed_array_u32 :typed_array_u64 :typed_array_f32 :typed_array_f64 :typed_array_bf16 :typed_array_w64)
      if !inline_raw_get
        idx_reg = ensure_i64_value(wfn, idx_val)
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_big_array_idx", args: [receiver_reg, idx_reg]})
        return typed_value(:i64, temp)

      elem_bits = typed_array_element_bits(elem_type)
      idx_raw = false
      if idx_val[:type] in (:raw_int :raw_i64 :raw_u64)
        idx_reg = idx_val[:value]
        idx_raw = true
      else
        idx_reg = ensure_i64_value(wfn, idx_val)
      scratch = []
      si = 0
      while si < 8
        scratch.push(next_temp(wfn))
        si += 1
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :big_array_get_inline, temp: temp, arr: receiver_reg, idx: idx_reg, idx_raw: idx_raw, s: scratch, bits: elem_bits, signed: false})
      if elem_type in (:typed_array_f32 :typed_array_f64 :typed_array_bf16)
        return raw_float_from_bits_i64(wfn, temp, elem_type)
      if elem_type == :typed_array_w64
        return typed_value(:i64, temp)
      return typed_value(:raw_int, temp)
    if method_name == "\[]=" && node.args.size() == 2
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      idx_val = lower_expression(ctx, node.args[0])
      idx_reg = ensure_i64_value(wfn, idx_val)
      val_expr = lower_expression(ctx, node.args[1])
      val_reg = ensure_i64_value(wfn, val_expr)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_big_array_idxset", args: [receiver_reg, idx_reg, val_reg]})
      return typed_value(:i64, temp)

  # Phase 6f: SmallArray inline ops. Layout differs from WArray:
  # slots are inline at offset 2 (no separate ptr load), no `start`
  # (size==cap, no shift), no negative-index normalization at this
  # level. The GEP index is a full i64 — narrowing to i8 wraps any
  # index 128..255 to a negative offset (see emitter small_array_*).
  if is_small_array_type?(recv_type)
    elem_bits = typed_array_element_bits(small_array_to_typed_array_type(recv_type))
    elem_signed = typed_array_signed?(small_array_to_typed_array_type(recv_type))
    if method_name == "size" && node.args.size() == 0
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_small_array_size", args: [receiver_reg]})
      return typed_value(:i64, temp)
    if method_name == "cap" && node.args.size() == 0
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_small_array_size", args: [receiver_reg]})
      return typed_value(:i64, temp)
    # Phase 6f: empty? is handled inline so Phase 5 specialization
    # doesn't try to monomorphize Enumerable's `each -> return false : true`
    # body (which would surface SmallArray-context bugs in `$size`
    # lowering). The fast path is a tiny size==0 compare.
    if method_name == "empty?" && node.args.size() == 0
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      size_temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: size_temp, name: "w_small_array_size", args: [receiver_reg]})
      raw_shl = next_temp(wfn)
      raw_size = next_temp(wfn)
      emit_instruction(wfn, {op: :nanunbox_int, temp: raw_size, temp_shl: raw_shl, boxed: size_temp})
      cmp = next_temp(wfn)
      emit_instruction(wfn, {op: :icmp_i64, temp: cmp, pred: "eq", lhs: raw_size, rhs: "0"})
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :select_i64, temp: temp, cond: cmp, then_val: w_true.to_s(), else_val: w_false.to_s()})
      return typed_value(:i64, temp)
    if method_name == "\[]" && node.args.size() == 1
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      idx_val = lower_expression(ctx, node.args[0])
      idx_raw = false
      if idx_val[:type] in (:raw_int :raw_i64 :raw_u64)
        idx_reg = idx_val[:value]
        idx_raw = true
      else
        idx_reg = ensure_i64_value(wfn, idx_val)
      scratch = []
      si = 0
      while si < 6
        scratch.push(next_temp(wfn))
        si += 1
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :small_array_get_inline, temp: temp, arr: receiver_reg, idx: idx_reg, idx_raw: idx_raw, s: scratch, bits: elem_bits, signed: elem_signed})
      elem_type = small_array_to_typed_array_type(recv_type)
      if elem_type in (:typed_array_f32 :typed_array_f64 :typed_array_bf16)
        return raw_float_from_bits_i64(wfn, temp, elem_type)
      return typed_value(:raw_int, temp)
    if method_name == "\[]=" && node.args.size() == 2
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      idx_val = lower_expression(ctx, node.args[0])
      idx_raw = false
      if idx_val[:type] in (:raw_int :raw_i64 :raw_u64)
        idx_reg = idx_val[:value]
        idx_raw = true
      else
        idx_reg = ensure_i64_value(wfn, idx_val)
      val_expr = lower_expression(ctx, node.args[1])
      elem_type = small_array_to_typed_array_type(recv_type)
      if elem_type in (:typed_array_f32 :typed_array_f64 :typed_array_bf16)
        val_reg = raw_float_bits_i64(wfn, val_expr, elem_type)
      elsif val_expr[:type] in (:raw_int :raw_i64 :raw_u64)
        val_reg = val_expr[:value]
      else
        val_reg = ensure_i64_value(wfn, val_expr)
      scratch = []
      si = 0
      while si < 6
        scratch.push(next_temp(wfn))
        si += 1
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :small_array_set_inline, temp: temp, arr: receiver_reg, idx: idx_reg, idx_raw: idx_raw, value: val_reg, s: scratch, bits: elem_bits, signed: elem_signed})
      return typed_value(:i64, temp)

  # Direct builtins for typed arrays (integer widths plus runtime-backed floats)
  if is_typed_array_type?(recv_type)
    elem_bits = typed_array_element_bits(recv_type)
    elem_signed = typed_array_signed?(recv_type)
    if method_name == "push" && node.args.size() == 1
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      arg_val = lower_expression(ctx, node.args[0])
      arg_reg = ensure_i64_value(wfn, arg_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_array_push", args: [receiver_reg, arg_reg]})
      return typed_value(:i64, temp)
    if method_name == "shift" && node.args.size() == 0
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_array_shift", args: [receiver_reg]})
      return typed_value(:i64, temp)
    if method_name == "pop" && node.args.size() == 0
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_array_pop", args: [receiver_reg]})
      return typed_value(:i64, temp)
    if method_name == "size" && node.args.size() == 0
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_array_size", args: [receiver_reg]})
      return typed_value(:i64, temp)
    if method_name in ("min" "max" "sum") && node.args.size() == 0
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      temp = next_temp(wfn)
      suffix = typed_array_kernel_suffix(recv_type)
      fn_name = "w_array_" + method_name + "_" + suffix
      if method_name == "sum" && suffix == "float" && ctx[:mod][:fast_mode] == true
        fn_name = "w_array_fastsum_float"
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: fn_name, args: [receiver_reg]})
      return typed_value(:i64, temp)
    if recv_type in (:typed_array_f32 :typed_array_f64 :typed_array_bf16) && method_name in ("fastsum" "sumsq") && node.args.size() == 0
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      temp = next_temp(wfn)
      fn_name = method_name == "fastsum" ? "w_array_fastsum_float" : "w_array_sumsq_float"
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: fn_name, args: [receiver_reg]})
      return typed_value(:i64, temp)
    if recv_type in (:typed_array_i8 :typed_array_u8) && method_name == "dot" && node.args.size() == 1
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      arg_val = lower_expression(ctx, node.args[0])
      arg_reg = ensure_i64_value(wfn, arg_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_array_dot_i8", args: [receiver_reg, arg_reg]})
      return typed_value(:i64, temp)
    if recv_type in (:typed_array_i8 :typed_array_u8) && method_name == "matvec_i8" && node.args.size() == 3
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      x_val = lower_expression(ctx, node.args[0])
      rows_val = lower_expression(ctx, node.args[1])
      cols_val = lower_expression(ctx, node.args[2])
      x_reg = ensure_i64_value(wfn, x_val)
      rows_reg = ensure_i64_value(wfn, rows_val)
      cols_reg = ensure_i64_value(wfn, cols_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_array_matvec_i8", args: [receiver_reg, x_reg, rows_reg, cols_reg]})
      return typed_value(:i64, temp)
    if recv_type in (:typed_array_i8 :typed_array_u8) && method_name == "matmul_i8" && node.args.size() == 4
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      rhs_val = lower_expression(ctx, node.args[0])
      m_val = lower_expression(ctx, node.args[1])
      k_val = lower_expression(ctx, node.args[2])
      n_val = lower_expression(ctx, node.args[3])
      rhs_reg = ensure_i64_value(wfn, rhs_val)
      m_reg = ensure_i64_value(wfn, m_val)
      k_reg = ensure_i64_value(wfn, k_val)
      n_reg = ensure_i64_value(wfn, n_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_array_matmul_i8", args: [receiver_reg, rhs_reg, m_reg, k_reg, n_reg]})
      return typed_value(:i64, temp)
    if recv_type in (:typed_array_f32 :typed_array_f64 :typed_array_bf16) && method_name in ("dot" "cross" "scale" "scale!") && node.args.size() == 1
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      arg_val = lower_expression(ctx, node.args[0])
      arg_reg = ensure_i64_value(wfn, arg_val)
      temp = next_temp(wfn)
      fn_name = "w_array_dot_float"
      if method_name == "cross"
        fn_name = "w_array_cross_float"
      elsif method_name == "scale"
        fn_name = "w_array_scale_float"
      elsif method_name == "scale!"
        fn_name = "w_array_scale_float_bang"
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: fn_name, args: [receiver_reg, arg_reg]})
      return typed_value(:i64, temp)
    if method_name in ("cos" "sin" "sqrt" "exp" "log" "tan") && node.args.size() == 0
      # f64 receivers fuse into a single raw loop with a scalar libm call
      # per element (vectorizable); other dtypes keep the kernel.
      fused = try_fuse_elementwise(ctx, node)
      if fused != nil
        return fused
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      temp = next_temp(wfn)
      suffix = typed_array_kernel_suffix(recv_type)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_array_" + method_name + "_" + suffix, args: [receiver_reg]})
      return typed_value(:i64, temp)
    if method_name == "\[]" && node.args.size() == 1
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      idx_val = lower_expression(ctx, node.args[0])
      # Pass raw index directly when available (skip box/unbox roundtrip)
      idx_raw = false
      if idx_val[:type] in (:raw_int :raw_i64 :raw_u64)
        idx_reg = idx_val[:value]
        idx_raw = true
      else
        idx_reg = ensure_i64_value(wfn, idx_val)
      scratch = []
      si = 0
      while si < 10
        scratch.push(next_temp(wfn))
        si += 1
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :typed_array_get_inline, temp: temp, arr: receiver_reg, idx: idx_reg, idx_raw: idx_raw, s: scratch, bits: elem_bits, signed: elem_signed})
      if recv_type in (:typed_array_f32 :typed_array_f64 :typed_array_bf16)
        return raw_float_from_bits_i64(wfn, temp, recv_type)
      # w64 arrays store raw WValue bits. The loaded i64 IS a fully-tagged
      # WValue; return it as :i64 (WValue) so downstream method dispatch,
      # string ops, nil checks, etc. treat it polymorphically — not as a
      # raw int that would get nanbox_int'd and corrupted.
      if recv_type == :typed_array_w64
        return typed_value(:i64, temp)
      if recv_type == :typed_array_i64
        return typed_value(:raw_i64, temp)
      if recv_type == :typed_array_u64
        return typed_value(:raw_u64, temp)
      return typed_value(:raw_int, temp)
    # Compound-op fast path: `arr[i] = arr[i] OP X` collapses to a single
    # pointer-chain + load + op + store. Skips the round-trip pointer
    # materialization that emitting separate get + set inline ops would
    # produce. Restricted to integer-typed arrays (not w64 / float — the
    # bit-level ops would corrupt boxed payloads or float reps).
    if method_name == "\[]=" && node.args.size() == 2 && recv_type in (:typed_array_u8 :typed_array_i8 :typed_array_u16 :typed_array_i16 :typed_array_u32 :typed_array_i32 :typed_array_u64 :typed_array_i64) && elem_bits in (8 16 32 64)
      val_node = node.args[1]
      fused_op = nil
      fused_rhs_node = nil
      if val_node != nil && is_ast_node?(val_node) && ast_kind(val_node) == :binary_op && val_node.op in (:PLUS :MINUS :STAR :PIPE :AMPERSAND :CARET :LSHIFT :RSHIFT)
        left = val_node.left
        right = val_node.right
        if left != nil && is_ast_node?(left) && ast_kind(left) == :call && left.name == "[]" && left.args != nil && left.args.size() == 1 && ast_equiv?(left.receiver, recv_node) && ast_equiv?(left.args[0], node.args[0])
          fused_op = val_node.op
          fused_rhs_node = right
        elsif right != nil && is_ast_node?(right) && ast_kind(right) == :call && right.name == "[]" && right.args != nil && right.args.size() == 1 && val_node.op in (:PLUS :STAR :PIPE :AMPERSAND :CARET) && ast_equiv?(right.receiver, recv_node) && ast_equiv?(right.args[0], node.args[0])
          # Commutative ops: `arr[i] = X | arr[i]` is the same fused form.
          fused_op = val_node.op
          fused_rhs_node = left
      if fused_op != nil
        receiver_val = lower_expression(ctx, recv_node)
        receiver_reg = ensure_i64_value(wfn, receiver_val)
        idx_val = lower_expression(ctx, node.args[0])
        idx_raw = false
        if idx_val[:type] in (:raw_int :raw_i64 :raw_u64)
          idx_reg = idx_val[:value]
          idx_raw = true
        else
          idx_reg = ensure_i64_value(wfn, idx_val)
        rhs_tv = lower_expression(ctx, fused_rhs_node)
        if rhs_tv[:type] in (:raw_int :raw_i64 :raw_u64)
          rhs_reg = rhs_tv[:value]
        elsif rhs_tv[:type] in (:int :i64)
          # A generic WValue may be a heap BigInt once its magnitude exceeds
          # the immediate i48 payload. Shifting its tag bits is only valid for
          # a known immediate integer; use the numeric boundary here so a
          # boxed RHS contributes its value, not heap-pointer bits.
          rhs_machine_type = :i64
          if recv_type == :typed_array_u64
            rhs_machine_type = :u64
          rhs_reg = ensure_raw_machine_int(wfn,rhs_tv,rhs_machine_type,nil)
        else
          rhs_reg = ensure_i64_value(wfn, rhs_tv)
        scratch = []
        si = 0
        while si < 10
          scratch.push(next_temp(wfn))
          si += 1
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :typed_array_compound_op_inline, temp: temp, arr: receiver_reg, idx: idx_reg, idx_raw: idx_raw, value: rhs_reg, compound_op: fused_op, s: scratch, bits: elem_bits, signed: elem_signed})
        return typed_value(:i64, temp)

    if method_name == "\[]=" && node.args.size() == 2
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      idx_val = lower_expression(ctx, node.args[0])
      idx_raw = false
      if idx_val[:type] in (:raw_int :raw_i64 :raw_u64)
        idx_reg = idx_val[:value]
        idx_raw = true
      else
        idx_reg = ensure_i64_value(wfn, idx_val)
      val_expr = lower_expression(ctx, node.args[1])
      if recv_type in (:typed_array_f32 :typed_array_f64 :typed_array_bf16)
        val_reg = raw_float_bits_i64(wfn, val_expr, recv_type)
      elsif val_expr[:type] in (:raw_int :raw_i64 :raw_u64)
        # Raw machine ints pass through to the typed store directly.
        # `:raw_u64` was previously missing here, which made u64[] stores
        # round-trip through ensure_i64_value (NaN-boxing the integer),
        # so reading the slot back returned a tagged WValue instead of
        # the original bit pattern. Same fix as :raw_i64.
        val_reg = val_expr[:value]
      elsif val_expr[:type] in (:int :i64) && recv_type != :typed_array_w64
        # Polymorphic Integer (`:int`) or boxed WValue (`:i64` — a dynamic
        # function/method result or a plain boxed variable) going into a raw
        # typed-integer array: convert at the store boundary. A tag shift is
        # insufficient because integers outside i48 are heap BigInts; shifting
        # such a WValue writes pointer-derived garbage. `w64[]` is deliberately
        # excluded because its slots intentionally keep boxed WValue bits.
        store_machine_type = :i64
        if recv_type == :typed_array_u64
          store_machine_type = :u64
        val_reg = ensure_raw_machine_int(wfn,val_expr,store_machine_type,nil)
      else
        val_reg = ensure_i64_value(wfn, val_expr)
      scratch = []
      si = 0
      while si < 10
        scratch.push(next_temp(wfn))
        si += 1
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :typed_array_set_inline, temp: temp, arr: receiver_reg, idx: idx_reg, idx_raw: idx_raw, value: val_reg, s: scratch, bits: elem_bits, signed: elem_signed})
      return typed_value(:i64, temp)

  # Direct builtins for string operations — bypass method dispatch
  if recv_type == :string
    if method_name == "index" && node.args.size() >= 1 && node.args.size() <= 2
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      needle_val = lower_expression(ctx, node.args[0])
      needle_reg = ensure_i64_value(wfn, needle_val)
      if node.args.size() == 2
        offset_val = lower_expression(ctx, node.args[1])
        offset_reg = ensure_i64_value(wfn, offset_val)
      else
        offset_reg = w_nil.to_s()
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_string_index", args: [receiver_reg, needle_reg, offset_reg]})
      return typed_value(:i64, temp)

    if method_name == "rindex" && node.args.size() >= 1 && node.args.size() <= 2
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      needle_val = lower_expression(ctx, node.args[0])
      needle_reg = ensure_i64_value(wfn, needle_val)
      if node.args.size() == 2
        offset_val = lower_expression(ctx, node.args[1])
        offset_reg = ensure_i64_value(wfn, offset_val)
      else
        offset_reg = w_nil.to_s()
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_string_rindex", args: [receiver_reg, needle_reg, offset_reg]})
      return typed_value(:i64, temp)

    if method_name == "repeat" && node.args.size() == 1
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      count_val = lower_expression(ctx, node.args[0])
      count_reg = ensure_i64_value(wfn, count_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_string_repeat", args: [receiver_reg, count_reg]})
      return typed_value(:i64, temp)

    if method_name == "count" && node.args.size() == 1
      receiver_val = lower_expression(ctx, recv_node)
      receiver_reg = ensure_i64_value(wfn, receiver_val)
      needle_val = lower_expression(ctx, node.args[0])
      needle_reg = ensure_i64_value(wfn, needle_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_string_count", args: [receiver_reg, needle_reg]})
      return typed_value(:i64, temp)

  # Phase 5: monomorphization. When the receiver has a known typed-array
  # variant AND there's a user-defined method on the corresponding source
  # class (Array / BigArray / SmallArray), specialize the method (clone +
  # re-lower with __self pre-typed) and emit a direct call to the variant.
  # No runtime method-dispatch tax inside the specialized body — self[i]
  # lowers via :typed_array_get_inline at the variant's ebits.
  #
  # Block-bearing calls (`arr.each -> (v) ...`) participate too: the block
  # is lowered as a closure with the parent context (so captures see the
  # specialized __self type), then appended as the trailing arg. The
  # specialized fn signature inherits the block param from its source AST,
  # so the runtime contract is identical to the generic dispatch path.
  if recv_type != nil && is_array_type?(recv_type)
    spec_class = source_class_for_array_type(recv_type)
    method_ast = nil
    call_arity = node.args.size()
    if spec_class != nil
      # Prefer the overload whose param count matches the call's argument
      # count (e.g. `sum` vs `sum(init)`); fall back to the bare-name entry.
      method_ast = ctx[:mod][:class_method_asts][spec_class + "." + method_name + "/" + call_arity.to_s()]
      if method_ast == nil
        method_ast = ctx[:mod][:class_method_asts][spec_class + "." + method_name]
    if method_ast != nil
      # Verify the block presence on the call matches the method's expectation.
      # A block parameter may also be supplied as the final positional closure
      # (`values.map(mapper)`); that is the form benchmark harnesses and higher-
      # order code use to reuse one closure without reallocating it per call.
      method_takes_block = method_lowering_analysis(method_ast)[:yield_block_name] != nil
      caller_has_block = call_has_ast_block?(node)
      positional_block_arg = false
      if method_takes_block && !caller_has_block
        positional_count = 0
        mpi = 0
        while mpi < method_ast.params.size()
          if method_ast.params[mpi].block_param != true
            positional_count += 1
          mpi += 1
        positional_block_arg = node.args.size() == positional_count + 1
      if method_takes_block == caller_has_block || positional_block_arg
        # Flush pending SSA bindings (e.g. an accumulator `acc = init`) into
        # var_slots BEFORE the inline-safety check — find_captures reads
        # ctx[:func][:var_slots], so an unmaterialized local reads as captureless.
        # Without this, a capturing block like `acc += item` is judged inline-safe,
        # wrongly takes the inlined path, and emits a closure-less call to the
        # block-taking specialized method → garbage block param → "expected
        # closure". (Surfaces on the small/big array Enumerable accumulators —
        # typed arrays use runtime kernels and never reach this path.)
        if caller_has_block
          materialize_bindings(ctx)
        # Phase C (#61): if the call site has a literal block that's
        # captureless and a single expression, specialize with the block
        # inlined at every :yield. The resulting fn doesn't take the
        # closure at all — no allocation, no per-element call.
        inline_block = nil
        if caller_has_block && block_inline_safe?(node.block, ctx)
          inline_block = node.block
        if inline_block != nil
          mangled = specialize_method_with_inlined_block(ctx, spec_class, method_name, recv_type, inline_block)
          if mangled != nil
            receiver_val = lower_expression(ctx, recv_node)
            receiver_reg = ensure_i64_value(wfn, receiver_val)
            spec_args = [receiver_reg]
            si = 0
            while si < node.args.size()
              arg_val = lower_expression(ctx, node.args[si])
              spec_args.push(ensure_i64_value(wfn, arg_val))
              si += 1
            # No closure arg — yields are inlined into the body.
            temp = next_temp(wfn)
            emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: mangled, args: spec_args})
            return typed_value(:i64, temp)
        mangled = specialize_method(ctx, spec_class, method_name, recv_type, call_arity)
        if mangled != nil
          receiver_val = lower_expression(ctx, recv_node)
          receiver_reg = ensure_i64_value(wfn, receiver_val)
          spec_args = [receiver_reg]
          si = 0
          while si < node.args.size()
            arg_val = lower_expression(ctx, node.args[si])
            spec_args.push(ensure_i64_value(wfn, arg_val))
            si += 1
          if caller_has_block
            materialize_bindings(ctx)
            closure_tv = lower_block_closure(ctx, node.block, iterator_block_param_types(recv_type, method_name))
            spec_args.push(ensure_i64_value(wfn, closure_tv))
          temp = next_temp(wfn)
          emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: mangled, args: spec_args})
          return typed_value(:i64, temp)

  receiver_val = lower_expression(ctx, recv_node)
  receiver_reg = ensure_i64_value(wfn, receiver_val)

  # Lower args
  call_args = expand_kwargs(node.args)
  arg_regs = []
  i = 0
  while i < call_args.size()
    val = lower_expression(ctx, call_args[i])
    arg_regs.push(ensure_i64_value(wfn, val))
    i += 1

  # If call has a block, materialize bindings for capture analysis
  blk = node.block
  if blk != nil && is_ast_node?(blk)
    materialize_bindings(ctx)
    closure_tv = lower_block_closure(ctx, blk, iterator_block_param_types(recv_type, method_name))
    closure_reg = ensure_i64_value(wfn, closure_tv)
    arg_regs.push(closure_reg)

  method_name_tv = lower_string(ctx, Tungsten:AST:String.new(method_name))
  method_name_val = ensure_i64_value(wfn, method_name_tv)

  temp_args_val = next_temp(wfn)
  temp = next_temp(wfn)

  ic_id = ctx[:mod][:next_ic]
  ctx[:mod][:next_ic] = ic_id + 1

  scalar_source_argc1 = false
  if arg_regs.size() == 1 && recv_node != nil && ast_kind(recv_node) == :ivar && ctx[:class_name] != nil
    exact_ivars = ctx[:mod][:exact_source_ivar_types][ctx[:class_name]]
    source_class_name = nil
    if exact_ivars != nil
      source_class_name = exact_ivars[recv_node.name]
    source_class = ctx[:mod][:known_classes][source_class_name]
    if source_class != nil && is_ast_node?(source_class) && ast_kind(source_class) == :class_def
      own_method = ctx[:mod][:class_method_asts][source_class_name + "." + method_name + "/1"]
      scalar_source_argc1 = own_method != nil

  emit_instruction(wfn, {
    op: :call_method_i64,
    temp: temp,
    temp_args_val: temp_args_val,
    receiver: receiver_reg,
    method_name_val: method_name_val,
    args: arg_regs,
    scalar_source_argc1: scalar_source_argc1,
    ic_id: ic_id,
    src_line: node.line,
    src_col: node.col
  })
  typed_value(:i64, temp)
