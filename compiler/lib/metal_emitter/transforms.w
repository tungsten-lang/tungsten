
# ---- Schedule application: kernel AST + schedule AST → transformed kernel AST ----
#
# Slice 3 of P3.4: implements just `axis :name, parallelize: :threadgroup`.
# Walks the kernel body looking for assigns tagged `## axis :<name>`;
# rewrites the binding from `gpu.thread_position_in_grid.x` to
# `gpu.threadgroup_position_in_grid.x`. Future slices add the b-axis
# rewrites (stride init/increment) and the simd_sum reduction.
-> apply_schedule_to_kernel(kernel, schedule, all_layouts)
  # Deep-clone the kernel so mutations don't leak back to the unscheduled variant.
  out = ast_clone(kernel)
  out.name = kernel.name + "_" + schedule.variant
  directives = schedule.directives
  i = 0
  while i < directives.size()
    apply_directive(out, directives[i], all_layouts)
    i += 1
  out

-> apply_directive(kernel, directive, all_layouts)
  if directive == nil || !is_ast_node?(directive) || ast_kind(directive) != :call
    return nil
  # `use_layout :variant_name` — reference a previously-defined
  # @layout block by its variant name. Applies that layout's directives
  # to the current kernel before any axis directives that follow.
  # Composability: lets a @schedule produce a variant that combines a
  # buffer reshape with parallelization in a single emitted kernel.
  if directive.name == "use_layout"
    apply_use_layout(kernel, directive, all_layouts)
    return nil
  if directive.name != "axis"
    return nil
  args = directive.args
  if args == nil || args.size() < 2
    return nil
  axis_arg = args[0]
  kwargs = args[1]
  if axis_arg == nil || ast_kind(axis_arg) != :symbol
    return nil
  axis_name = axis_arg.value
  parallelize_to = lookup_kwarg(kwargs, "parallelize")
  if parallelize_to == "threadgroup"
    rewrite_axis_to_threadgroup(kernel.body, axis_name)
  if parallelize_to == "simdgroup_lane"
    stride = lookup_kwarg_int(kwargs, "stride")
    if stride == nil
      stride = 32
    rewrite_axis_to_simdgroup_lane(kernel.body, axis_name, stride)
  reduce_with = lookup_kwarg(kwargs, "reduce")
  if reduce_with != nil
    target_var = lookup_kwarg(kwargs, "into")
    if target_var != nil
      rebuilt_body = apply_simd_reduce(kernel.body, axis_name, reduce_with, target_var)
      if rebuilt_body != nil
        kernel.body = rebuilt_body
  vec_factor = lookup_kwarg_int(kwargs, "vectorize")
  if vec_factor != nil && vec_factor > 1
    rewrite_axis_to_vectorize(kernel.body, axis_name, vec_factor)
  nil

# Look up the named @layout for this kernel and apply its directives.
# `directive` is a `use_layout :variant_name` call node.
-> apply_use_layout(kernel, directive, all_layouts)
  args = directive.args
  if args == nil || args.size() < 1
    return nil
  variant_arg = args[0]
  if variant_arg == nil || ast_kind(variant_arg) != :symbol
    return nil
  variant_name = variant_arg.value
  kernel_name = kernel.name
  # Strip any `_<variant>` suffix that schedule expansion already added,
  # so we can match against the original kernel name in @layout's
  # `kernel:` field.
  base_name = kernel_name
  underscore_pos = base_name.index("_")
  while underscore_pos != nil
    candidate = base_name.slice(0, underscore_pos)
    base_name = candidate
    underscore_pos = nil
  # Walk all layouts looking for one with matching kernel + variant.
  if all_layouts == nil
    return nil
  i = 0
  while i < all_layouts.size()
    lay = all_layouts[i]
    if lay.variant == variant_name
      # Apply the layout's directives to the current kernel.
      ldirs = lay.directives
      j = 0
      while j < ldirs.size()
        apply_layout_directive(kernel, ldirs[j])
        j += 1
      return nil
    i += 1
  nil

# Look up a keyword arg in a from_kwargs hash_literal node. Returns
# the value's symbol name (string) or nil.
-> lookup_kwarg(kwargs_node, key_name)
  if kwargs_node == nil || ast_kind(kwargs_node) != :hash_literal
    return nil
  entries = kwargs_node.entries
  if entries == nil
    return nil
  i = 0
  while i < entries.size()
    pair = entries[i]
    if pair != nil && pair.size() >= 2
      k = pair[0]
      v = pair[1]
      if k != nil && ast_kind(k) == :symbol && k.value == key_name
        if v != nil && ast_kind(v) == :symbol
          return v.value
    i += 1
  nil

# Like lookup_kwarg but accepts string-literal values too. Used by
# @layout where buffer-type names like "i32[]" are passed as strings
# (the symbol form `:i32[]` doesn't parse — `[]` collides with array
# subscript syntax).
-> lookup_kwarg_str_or_sym(kwargs_node, key_name)
  if kwargs_node == nil || ast_kind(kwargs_node) != :hash_literal
    return nil
  entries = kwargs_node.entries
  if entries == nil
    return nil
  i = 0
  while i < entries.size()
    pair = entries[i]
    if pair != nil && pair.size() >= 2
      k = pair[0]
      v = pair[1]
      if k != nil && ast_kind(k) == :symbol && k.value == key_name
        if v != nil
          if ast_kind(v) == :symbol
            return v.value
          if ast_kind(v) == :string
            return v.value
    i += 1
  nil

# Same as lookup_kwarg but returns int values for ints (e.g. `stride: 32`).
-> lookup_kwarg_int(kwargs_node, key_name)
  if kwargs_node == nil || ast_kind(kwargs_node) != :hash_literal
    return nil
  entries = kwargs_node.entries
  if entries == nil
    return nil
  i = 0
  while i < entries.size()
    pair = entries[i]
    if pair != nil && pair.size() >= 2
      k = pair[0]
      v = pair[1]
      if k != nil && ast_kind(k) == :symbol && k.value == key_name
        if v != nil && ast_kind(v) == :int
          return v.value
    i += 1
  nil

# Walk the kernel body. For every assign with `axis_name == :a` whose
# RHS is `gpu.thread_position_in_grid.x`, rewrite the inner call name
# to `threadgroup_position_in_grid`. Mutates in place — caller has
# already deep-cloned.
-> rewrite_axis_to_threadgroup(node, axis_name)
  if node == nil
    return nil
  if type(node) == "Array"
    i = 0
    while i < node.size()
      rewrite_axis_to_threadgroup(node[i], axis_name)
      i += 1
    return nil
  if !is_ast_node?(node)
    return nil
  if ast_kind(node) == :assign && node.axis_name == axis_name
    v = node.value
    if v != nil && ast_kind(v) == :call && v.receiver != nil
      inner = v.receiver
      if ast_kind(inner) == :call && inner.name == "thread_position_in_grid"
        inner.name = "threadgroup_position_in_grid"
  # Recurse into all AST children (Arrays are walked into; single
  # AST children get visited directly).
  ast_children(node).each -> (c)
    rewrite_axis_to_threadgroup(c, axis_name)

# `axis :b, parallelize: :simdgroup_lane, stride: N` rewrites:
#   1. The init assign tagged `## axis :b` from `b = <expr>` to
#      `b = gpu.thread_index_in_simdgroup`.
#   2. The b-loop body's increment of `b`. Originals like `b = b + 1`
#      become `b = b + N`. Detected by walking the while-loop body
#      that immediately follows the b-init assign.
-> rewrite_axis_to_simdgroup_lane(body, axis_name, stride)
  if body == nil || type(body) != "Array"
    return nil
  i = 0
  while i < body.size()
    stmt = body[i]
    if stmt != nil && is_ast_node?(stmt) && ast_kind(stmt) == :assign && stmt.axis_name == axis_name
      stmt.value = Tungsten:AST:Call.new(Tungsten:AST:Var.new("gpu"), "thread_index_in_simdgroup", [], nil)
      # Look at subsequent siblings for the matching while-loop.
      j = i + 1
      while j < body.size()
        if body[j] != nil && ast_kind(body[j]) == :while
          rewrite_loop_increment(body[j].body, axis_name, stride)
          j = body.size()
        j += 1
    # Recurse into nested bodies (if/while/etc.).
    if stmt != nil && is_ast_node?(stmt)
      ast_array_fields(stmt).each -> (kv)
        rewrite_axis_to_simdgroup_lane(kv, axis_name, stride)
    i += 1

# Find `var = var + N` (any `N`) inside `body` and replace `N` with
# `stride`. Mutates the matching int-literal RHS in place.
-> rewrite_loop_increment(body, var_name, stride)
  if body == nil || type(body) != "Array"
    return nil
  i = 0
  while i < body.size()
    stmt = body[i]
    if stmt != nil && ast_kind(stmt) == :assign
      tgt = stmt.target
      val = stmt.value
      if tgt != nil && ast_kind(tgt) == :var && tgt.name == var_name
        if val != nil && ast_kind(val) == :binary_op && val.op == :PLUS
          # Pattern: var = var + INT or var = INT + var. Replace the int.
          left = val.left
          right = val.right
          if left != nil && ast_kind(left) == :var && left.name == var_name && right != nil && ast_kind(right) == :int
            right.value = stride
            right.raw = stride
          elsif right != nil && ast_kind(right) == :var && right.name == var_name && left != nil && ast_kind(left) == :int
            left.value = stride
            left.raw = stride
    # Recurse — handles nested loops if any.
    if stmt != nil && is_ast_node?(stmt)
      ast_array_fields(stmt).each -> (kv)
        rewrite_loop_increment(kv, var_name, stride)
    i += 1

# `axis :i, vectorize: N` unrolls the loop body N times with each copy
# substituting `i` → `i + k` for k in 0..N-1, and updates the increment
# from `i = i + 1` to `i = i + N`. The resulting MSL gets a wide loop
# body that the Metal compiler is much more likely to auto-vectorize
# into vec4 loads + FMA chains than the scalar version.
#
# Limitations: only fires when the loop's natural increment is `i = i + 1`
# (or the post-stride value if combined with parallelize). The body must
# be straight-line code without nested conditionals on `i` — the rewrite
# duplicates statements blindly. Q8 matvec inner loops fit this shape.
-> rewrite_axis_to_vectorize(body, axis_name, factor)
  if body == nil || type(body) != "Array"
    return nil
  i = 0
  while i < body.size()
    stmt = body[i]
    if stmt != nil && is_ast_node?(stmt) && ast_kind(stmt) == :assign && stmt.axis_name == axis_name
      # Find the matching while-loop sibling and unroll its body.
      j = i + 1
      while j < body.size()
        if body[j] != nil && ast_kind(body[j]) == :while
          unroll_while_body(body[j], axis_name, factor)
          j = body.size()
        j += 1
    if stmt != nil && is_ast_node?(stmt)
      ast_array_fields(stmt).each -> (kv)
        rewrite_axis_to_vectorize(kv, axis_name, factor)
    i += 1

# Replace the `while`'s body with N concatenated copies of the body,
# minus the induction-variable increment in each copy, then append one
# rewritten increment at the very end. Each copy k = 0..N-1 substitutes
# `axis_name` with `axis_name + k` so the duplicated reads/writes index
# the right elements.
-> unroll_while_body(while_node, axis_name, factor)
  orig_body = while_node.body
  if orig_body == nil
    return nil
  unrolled = []
  saved_increment = nil
  k = 0
  while k < factor
    bi = 0
    while bi < orig_body.size()
      stmt = orig_body[bi]
      if is_axis_increment(stmt, axis_name)
        if saved_increment == nil
          saved_increment = ast_clone(stmt)
      else
        cloned = ast_clone(stmt)
        if k > 0
          replaced = substitute_var_with_offset(cloned, axis_name, k)
          if replaced != nil
            cloned = replaced
        unrolled.push(cloned)
      bi += 1
    k += 1
  if saved_increment != nil
    unrolled.push(saved_increment)
  while_node.body = unrolled
  rewrite_loop_increment([while_node], axis_name, factor)

-> is_axis_increment(stmt, axis_name)
  if stmt == nil || ast_kind(stmt) != :assign
    return false
  tgt = stmt.target
  if tgt == nil || ast_kind(tgt) != :var || tgt.name != axis_name
    return false
  val = stmt.value
  if val == nil || ast_kind(val) != :binary_op || val.op != :PLUS
    return false
  l = val.left
  r = val.right
  if l != nil && ast_kind(l) == :var && l.name == axis_name
    return true
  if r != nil && ast_kind(r) == :var && r.name == axis_name
    return true
  false

# Walk a node tree replacing every var read of `var_name` with the
# expression `var_name + offset`. Skips assign-target positions
# (we only rewrite reads, not writes — the lone write site is the
# induction-variable increment which is preserved by unroll_while_body).
# A W_PACKED_NODE's kind and size class live in the WValue's tag bits,
# so a node can never change kind in place: when `node` itself is the
# var being replaced, the fresh binary_op comes back through the return
# value and the PARENT stores it into the slot it read the child from.
# Interior nodes rewrite their children in place and return nil.
-> substitute_var_with_offset(node, var_name, offset)
  if node == nil || !is_ast_node?(node)
    return nil
  if ast_kind(node) == :var && node.name == var_name
    return Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(var_name), :PLUS, Tungsten:AST:Int.new(offset, nil, offset))
  # For assigns, recurse into value but skip target (don't substitute
  # writes of var_name with a binary expression — that's invalid).
  if ast_kind(node) == :assign
    replaced = substitute_var_with_offset(node.value, var_name, offset)
    if replaced != nil
      node.value = replaced
    return nil
  substitute_children_with_offset(node, var_name, offset)
  nil

# Parent-side store for substitute_var_with_offset: walk every schema
# field of `node`, recurse, and overwrite the field (or array element)
# whenever the recursion hands back a replacement node.
-> substitute_children_with_offset(node, var_name, offset)
  kid = kind_id_table[ast_kind(node)]
  if kid == nil
    return nil
  fields = slab_keys_table[kid]
  if fields == nil
    return nil
  fi = 0
  while fi < fields.size()
    v = ast_get(node, fields[fi])
    if type(v) == "Array"
      # Child-list arrays are immutable once frozen into a node's slot
      # (same discipline as the single-node branch below) — build a
      # replacement array whenever any element changes and write the
      # whole field back, rather than index-assigning into `v` in place.
      any_replaced = false
      rebuilt_arr = []
      vi = 0
      while vi < v.size()
        elt = v[vi]
        replaced = substitute_var_with_offset(elt, var_name, offset)
        if replaced != nil
          rebuilt_arr.push(replaced)
          any_replaced = true
        else
          rebuilt_arr.push(elt)
        vi += 1
      if any_replaced
        ast_set(node, fields[fi], rebuilt_arr)
    elsif is_ast_node?(v)
      replaced = substitute_var_with_offset(v, var_name, offset)
      if replaced != nil
        ast_set(node, fields[fi], replaced)
    fi += 1
  nil

# `axis :b, reduce: :simd_sum, into: :acc` injects two new statements
# right after the b-axis loop:
#   1. `acc = simd_sum(acc)`  — reduces partials across the SIMD group.
#   2. `if gpu.thread_index_in_simdgroup == 0` wrapping every statement
#      that follows in the same body — the lane-0 guard around the
#      writeback.
#
# Only :simd_sum is implemented in slice 4; :simd_max/:simd_min/etc.
# would be similar one-line additions to the dispatch below.
-> apply_simd_reduce(body, axis_name, reduce_with, target_var)
  if body == nil || type(body) != "Array"
    return nil
  reduce_fn = nil
  if reduce_with in ("simd_sum" "simd_max" "simd_min")
    reduce_fn = reduce_with
  if reduce_fn == nil
    return nil
  i = 0
  while i < body.size()
    stmt = body[i]
    # Find the b-axis init assign.
    if stmt != nil && is_ast_node?(stmt) && ast_kind(stmt) == :assign && stmt.axis_name == axis_name
      # The next while-loop is the b-loop. Inject after it.
      j = i + 1
      loop_idx = -1
      while j < body.size()
        if body[j] != nil && ast_kind(body[j]) == :while
          loop_idx = j
          j = body.size()
        j += 1
      if loop_idx >= 0
        # Build the two new statements:
        #   acc = simd_sum(acc)
        reduce_call = Tungsten:AST:Call.new(nil, reduce_fn, [Tungsten:AST:Var.new(target_var)], nil)
        reduce_assign = Tungsten:AST:Assign.new(Tungsten:AST:Var.new(target_var), reduce_call, nil)
        # Wrap whatever sits after the b-loop in `if lane == 0 ... end`.
        # That captures the writeback (e.g. `y[m] = acc`) without us
        # having to know exactly what shape it takes.
        tail = []
        ti = loop_idx + 1
        while ti < body.size()
          tail.push(body[ti])
          ti += 1
        # Truncate body in place: drop tail, append reduce_assign + if-block.
        # The simplest portable mutation is to clear & rebuild.
        rebuilt = []
        ri = 0
        while ri <= loop_idx
          rebuilt.push(body[ri])
          ri += 1
        rebuilt.push(reduce_assign)
        if tail.size() > 0
          lane_call = Tungsten:AST:Call.new(Tungsten:AST:Var.new("gpu"), "thread_index_in_simdgroup", [], nil)
          cond = Tungsten:AST:BinaryOp.new(lane_call, :EQ, Tungsten:AST:Int.new(0))
          rebuilt.push(Tungsten:AST:If.new(cond, tail, [], nil))
        # Return the replacement list — child-list arrays are immutable
        # once frozen into a node's slot (same discipline as node-kind
        # changes), so the caller reassigns `kernel.body = rebuilt`
        # rather than this function mutating `body` in place.
        return rebuilt
    i += 1

# ---- Layout pass: kernel AST + layout AST → transformed kernel AST ----
#
# Slice 5 of P3.4: implements `buffer :name, from: ..., to: ...,
# unpack: :sign_extend_per_byte`.
#   1. Updates the parameter's type hint (`i8[]` → `i32[]`), changing
#      the emitted MSL signature from `device char *buf` to
#      `device int *buf`.
#   2. Rewrites every `buf[idx]` read to
#      `((buf[idx/4] << ((3 - idx%4) * 8)) >> 24)` — sign-extend the
#      byte at position `idx%4` of the int word at position `idx/4`.
#      The MSL/clang compiler folds the index arithmetic for constant
#      indices and recognizes the byte-extract pattern.
-> apply_layout_to_kernel(kernel, layout)
  out = ast_clone(kernel)
  out.name = kernel.name + "_" + layout.variant
  directives = layout.directives
  i = 0
  while i < directives.size()
    apply_layout_directive(out, directives[i])
    i += 1
  out

-> apply_layout_directive(kernel, directive)
  if directive == nil || !is_ast_node?(directive) || ast_kind(directive) != :call
    return nil
  if directive.name != "buffer"
    return nil
  args = directive.args
  if args == nil || args.size() < 2
    return nil
  buf_arg = args[0]
  kwargs = args[1]
  if buf_arg == nil || ast_kind(buf_arg) != :symbol
    return nil
  buf_name = buf_arg.value
  to_type = lookup_kwarg_str_or_sym(kwargs, "to")
  unpack_method = lookup_kwarg(kwargs, "unpack")
  # Update the parameter's type hint.
  if to_type != nil && kernel.type_hints != nil
    kernel.type_hints[buf_name] = to_type
  # Rewrite reads.
  if unpack_method == "sign_extend_per_byte"
    rewrite_byte_reads_to_packed(kernel.body, buf_name)
  nil

# Walk the kernel body. For every call(name="[]", recv=var(buf_name),
# args=[idx]), replace with the packed-int unpack expression:
#   ((buf[idx/4] << ((3 - idx%4) * 8)) >> 24)
# Same replacement protocol as substitute_var_with_offset: a packed
# node can't change kind in place, so a rewritten read is RETURNED and
# the parent stores it into the field / array slot it came from; nil
# means nothing at this position changed. The top-level caller passes
# the kernel body Array, whose elements the Array branch writes back.
-> rewrite_byte_reads_to_packed(node, buf_name)
  if node == nil
    return nil
  if type(node) == "Array"
    i = 0
    while i < node.size()
      replaced = rewrite_byte_reads_to_packed(node[i], buf_name)
      if replaced != nil
        node[i] = replaced
      i += 1
    return nil
  if !is_ast_node?(node)
    return nil
  # Recurse into all AST children first (rewrites operate bottom-up
  # so nested byte reads inside compound expressions get caught),
  # storing any replacement back into the schema field it came from.
  kid = kind_id_table[ast_kind(node)]
  fields = nil
  if kid != nil
    fields = slab_keys_table[kid]
  if fields != nil
    fi = 0
    while fi < fields.size()
      v = ast_get(node, fields[fi])
      if type(v) == "Array"
        rewrite_byte_reads_to_packed(v, buf_name)
      elsif is_ast_node?(v)
        replaced = rewrite_byte_reads_to_packed(v, buf_name)
        if replaced != nil
          ast_set(node, fields[fi], replaced)
      fi += 1
  # If THIS node is a buf_name byte read, hand back the unpack expr.
  if ast_kind(node) == :call && node.name == "\[]"
    recv = node.receiver
    if recv != nil && ast_kind(recv) == :var && recv.name == buf_name
      args = node.args
      if args != nil && args.size() == 1
        idx = args[0]
        # Step 1: word_idx = idx / 4
        word_idx = Tungsten:AST:BinaryOp.new(ast_clone(idx), :SLASH, Tungsten:AST:Int.new(4))
        # Step 2: word_load = buf[word_idx]
        word_load = Tungsten:AST:Call.new(Tungsten:AST:Var.new(buf_name), "\[]", [word_idx], nil)
        # Step 3: byte_in_word = idx % 4
        byte_pos = Tungsten:AST:BinaryOp.new(ast_clone(idx), :PERCENT, Tungsten:AST:Int.new(4))
        # Step 4: shift = (3 - byte_in_word) * 8
        three_minus = Tungsten:AST:BinaryOp.new(Tungsten:AST:Int.new(3), :MINUS, byte_pos)
        shift = Tungsten:AST:BinaryOp.new(three_minus, :STAR, Tungsten:AST:Int.new(8))
        # Step 5: shifted = word_load << shift
        shifted = Tungsten:AST:BinaryOp.new(word_load, :LSHIFT, shift)
        # Step 6: result = shifted >> 24
        return Tungsten:AST:BinaryOp.new(shifted, :RSHIFT, Tungsten:AST:Int.new(24))

# Deep-clone an AST subtree. The old local hash-walking clone predated
# the slab flip and silently returned packed nodes UNCLONED (type() of a
# W_PACKED_NODE is not "Hash"), aliasing every "copy" the scheduler made.
# ast.w's ast_deep_clone allocates fresh slab nodes and copies slots +
# sparse meta, so schedule rewrites mutate real copies.
-> ast_clone(node)
  ast_deep_clone(node)
