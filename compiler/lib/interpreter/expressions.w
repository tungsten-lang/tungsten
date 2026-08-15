+ Interpreter

  # -- Assignment --

  -> eval_assign(node, env)
    value = evaluate(ast_get(node, :value), env)
    value = apply_type_hint(value, ast_get(node, :type_hint))
    target = ast_get(node, :target)

    if ast_kind(target) == :var
      env.set(ast_get(target, :name), value)
      return value

    if ast_kind(target) == :gvar
      # A matching `$field` inside a runtime-backed class method is a native
      # data-view store, just as compiled lowering writes the declared field
      # at its static offset. Keep the tree-walker bridge deliberately narrow.
      name = ast_get(target, :name)
      current_method = @method_stack.last()
      if name.starts_with?("$") && current_method != nil && current_method[:w_class] != nil
        field = name.slice(1, name.size() - 1)
        if native_data_field_declared?(current_method[:w_class], field)
          if native_data_field_writable?(current_method[:w_class], field)
            return ccall("w_native_data_field_set", current_self(), field, value)
          raise "native data field '[field]' is not writable in the interpreter"
      @globals[ast_get(target, :name)] = value
      return value

    if ast_kind(target) == :ivar
      obj = current_self()
      if obj == nil || type(obj) != "Hash" || !obj.has_key?(:rt) || obj[:rt] != :object
        raise "Instance variable assignment outside of object context"
      obj[:ivars][ast_get(target, :name)] = value
      return value

    if ast_kind(target) == :cvar
      set_cvar(ast_get(target, :name), value)
      return value

    if ast_kind(target) == :view_field_var
      return eval_view_field_var_set(target, value, env)

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
    recv_node = ast_get(call_node, :receiver)
    # `$limbs[i] = v` / `result$limbs[i] = v` — indexed native array element
    # stores on a BigInt's u64[] tail (walker mirror of the compiled strided
    # store). Intercept before receiver evaluation: the `$limbs` gvar itself
    # has no interpreter value.
    if ast_get(call_node, :name) == "\[]=" && ast_kind(recv_node) == :gvar && ast_get(recv_node, :name) == "$limbs"
      current_method = @method_stack.last()
      if current_method != nil && current_method[:w_class] != nil
        idx = evaluate(ast_get(call_node, :args)[0], env)
        rhs = evaluate(ast_get(call_node, :args)[1], env)
        return ccall("w_native_data_elem_set", current_self(), "limbs", idx, rhs)
    if ast_get(call_node, :name) == "\[]=" && ast_kind(recv_node) == :view_field_var && ast_get(recv_node, :field) == "limbs"
      explicit_recv = evaluate(ast_get(recv_node, :receiver), env)
      idx = evaluate(ast_get(call_node, :args)[0], env)
      rhs = evaluate(ast_get(call_node, :args)[1], env)
      return ccall("w_native_data_elem_set", explicit_recv, "limbs", idx, rhs)
    recv = evaluate(recv_node, env)
    if ast_get(call_node, :name) == "\[]="
      index_val = evaluate(ast_get(call_node, :args)[0], env)
      rhs = evaluate(ast_get(call_node, :args)[1], env)
      recv[index_val] = rhs
    elsif ast_get(call_node, :name) == "\[]"
      # `h[k] ||= v` — the or-assign desugar targets the subscript READ
      # node; write through "[]=" with the index preserved (the compiled
      # engine's lower_assign_expr does the same).
      index_val = evaluate(ast_get(call_node, :args)[0], env)
      recv[index_val] = value
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

    if ast_kind(target) == :view_field_var
      old = eval_view_field_var(target, env)
      result = apply_compound_op(op, old, new_val)
      return eval_view_field_var_set(target, result, env)

    # `h[k] += v` / `a[i] -= v` — the parser hands the target over as an
    # index-read call (name "[]", one index arg). Read through the same
    # dispatch the standalone `h[k]` expression uses, apply the operator,
    # and write back through "[]=". No missing-key default: the compiled
    # engine lets `nil + v` raise, so the tree walker must too.
    if ast_kind(target) == :call && ast_get(target, :name) == "\[]"
      recv = evaluate(ast_get(target, :receiver), env)
      idx = evaluate(ast_get(target, :args)[0], env)
      old = dispatch_method(recv, "\[]", [idx], nil, env)
      result = apply_compound_op(op, old, new_val)
      dispatch_method(recv, "\[]=", [idx, result], nil, env)
      return result

    # `obj.attr += v` — a no-arg getter call with a receiver. Read through
    # the getter, apply the operator, write back through the `attr=` setter,
    # matching the compiled engine (which already lowered this form).
    if ast_kind(target) == :call && ast_get(target, :receiver) != nil
      target_args = ast_get(target, :args)
      if target_args == nil || target_args.size == 0
        recv = evaluate(ast_get(target, :receiver), env)
        old = dispatch_method(recv, ast_get(target, :name), [], nil, env)
        result = apply_compound_op(op, old, new_val)
        dispatch_method(recv, ast_get(target, :name) + "=", [result], nil, env)
        return result

    raise "Invalid compound assignment target"

  -> apply_compound_op(op, left, right)
    # Object operands dispatch their own operator method (`a *= b` -> a.*(b)),
    # mirroring apply_binary_op's object arm. Without this, `result *= base`
    # inside Hypercomplex#** fell through to the primitive `left * right` arm,
    # which fed a whole object into the runtime multiply and died in as_int.
    if type(left) == "Hash" && left.has_key?(:rt) && left[:rt] == :object
      opn = binop_method_name(op)
      if opn != nil
        return dispatch_method(left, opn, [right], nil, nil)
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
    if op == :POW
      return left ** right
    if op == :AMPERSAND
      return left & right
    if op == :PIPE
      return left | right
    if op == :CARET
      return left ^ right
    if op == :LSHIFT
      return left << right
    if op == :RSHIFT
      return left >> right
    raise "Unknown compound operator"

  # -- Binary operations --

  # Conversion-pipe target for `| lb` / `| lb(2)` / `| J` / `| "metric cup"`:
  # a known-unit spelling that isn't shadowed by a local. Bare compound
  # spellings arrive as expression shapes and are rebuilt by
  # interp_pipe_unit_spelling: `km/h` is a `/`-map, `J·s` a DOT_PRODUCT,
  # `W/m²` a POW over a map, and a mixed-case name like `eV` or `mmHg` is a
  # juxtaposition call `e(V)`. The rebuilt spelling must name a registry unit
  # or the pipe evaluates as ordinary bitwise-or. Mirrors lowering/ops.w
  # pipe_unit_target.
  -> interp_pipe_unit_target(node, env)
    r = ast_get(node, :right)
    if !is_ast_node?(r)
      return nil
    uname = nil
    udigits = 0 - 1
    quoted = false
    k = ast_kind(r)
    if k == :string
      uname = ast_get(r, :value)
      quoted = true
    elsif k == :var || k == :class_ref
      uname = ast_get(r, :name)
    elsif k == :call && ast_get(r, :receiver) == nil
      cargs = ast_get(r, :args)
      if cargs != nil && cargs.size() == 1 && is_ast_node?(cargs[0]) && ast_kind(cargs[0]) == :int
        uname = ast_get(r, :name)
        udigits = ast_get(cargs[0], :value)
    if uname == nil && k == :call && ast_get(r, :receiver) == nil
      # `eV` / `mmHg` / `eV(3)`: mixed-case juxtaposition, digits riding the
      # innermost call.
      jt = interp_pipe_juxta_target(r)
      if jt != nil
        uname = jt[:name]
        udigits = jt[:digits]
    if uname == nil && k == :map
      # `km/h(2)`: a compound rate with rounding digits — the map's func call
      # carries the one-int-arg form.
      src = ast_get(r, :source)
      fnode = ast_get(r, :func)
      if is_ast_node?(src) && is_ast_node?(fnode) && ast_kind(fnode) == :call && ast_get(fnode, :receiver) == nil
        fargs = ast_get(fnode, :args)
        if fargs != nil && fargs.size() == 1 && is_ast_node?(fargs[0]) && ast_kind(fargs[0]) == :int
          l = interp_pipe_unit_spelling(src, env)
          fname = ast_get(fnode, :name)
          if l != nil && fname != nil
            fname = "" + fname.to_s()
            if !env.defined?(fname) && !@env.defined?(fname)
              uname = l + "/" + fname
              udigits = ast_get(fargs[0], :value)
    if uname == nil
      uname = interp_pipe_unit_spelling(r, env)
    if uname == nil
      return nil
    # Normalize the AST spelling to a String for the shared registry lookup.
    uname = "" + uname.to_s()
    if !known_unit_name?(uname)
      return nil
    if !quoted && (env.defined?(uname) || @env.defined?(uname))
      return nil
    {name: uname, digits: udigits}

  # Rebuild a bare unit spelling from the expression shape a compound or
  # mixed-case conversion target parses to. Leaves that name real locals stay
  # expressions; the caller validates the joined spelling against the unit
  # registry. Mirrors lowering/ops.w pipe_unit_spelling.
  -> interp_pipe_unit_spelling(r, env)
    if !is_ast_node?(r)
      return nil
    k = ast_kind(r)
    if k == :var || k == :class_ref
      nm = ast_get(r, :name)
      if nm == nil
        return nil
      nm = "" + nm.to_s()
      if env.defined?(nm) || @env.defined?(nm)
        return nil
      return nm
    if k == :binary_op
      bop = ccall("w_switch_canonical", ast_get(r, :op))
      if bop == :SLASH || bop == :DOT_PRODUCT
        lsp = interp_pipe_unit_spelling(ast_get(r, :left), env)
        if lsp == nil
          return nil
        rsp = interp_pipe_unit_spelling(ast_get(r, :right), env)
        if rsp == nil
          return nil
        if bop == :SLASH
          return lsp + "/" + rsp
        return lsp + "·" + rsp
      if bop == :POW
        ex = ast_get(r, :right)
        if is_ast_node?(ex) && ast_kind(ex) == :int
          lsp = interp_pipe_unit_spelling(ast_get(r, :left), env)
          if lsp == nil
            return nil
          sup = unit_superscript_for_power(ast_get(ex, :value))
          if sup == nil
            return nil
          return lsp + sup
      return nil
    if k == :map
      src = ast_get(r, :source)
      fnode = ast_get(r, :func)
      if !is_ast_node?(src) || !is_ast_node?(fnode)
        return nil
      fname = nil
      fk = ast_kind(fnode)
      if fk == :call && ast_get(fnode, :receiver) == nil
        fargs = ast_get(fnode, :args)
        if fargs == nil || fargs.size() == 0
          fname = ast_get(fnode, :name)
      elsif fk == :var || fk == :class_ref
        fname = ast_get(fnode, :name)
      if fname == nil
        return nil
      fname = "" + fname.to_s()
      if env.defined?(fname) || @env.defined?(fname)
        return nil
      lsp = interp_pipe_unit_spelling(src, env)
      if lsp == nil
        return nil
      return lsp + "/" + fname
    if k == :call
      jt = interp_pipe_juxta_target(r)
      if jt == nil
        return nil
      if jt[:digits] >= 0
        return nil
      return jt[:name]
    nil

  # `eV` lexes as ident + Constant and parses as the juxtaposition call
  # `e(V)`; `mmHg` and `kWh` nest the same way, and rounding digits ride the
  # innermost call — `eV(3)` is `e(V(3))`. Rejoin the pieces — the parts are
  # lexer artifacts, not identifiers, so only the joined spelling is
  # meaningful (and is registry-checked by the caller). Returns
  # {name, digits}; digits is -1 when absent.
  -> interp_pipe_juxta_target(r)
    if !is_ast_node?(r)
      return nil
    k = ast_kind(r)
    if k == :var || k == :class_ref
      nm = ast_get(r, :name)
      if nm == nil
        return nil
      return {name: "" + nm.to_s(), digits: 0 - 1}
    if k != :call
      return nil
    if ast_get(r, :receiver) != nil
      return nil
    nm = ast_get(r, :name)
    if nm == nil
      return nil
    cargs = ast_get(r, :args)
    if cargs == nil || cargs.size() != 1
      return nil
    if !is_ast_node?(cargs[0])
      return nil
    if ast_kind(cargs[0]) == :int
      return {name: "" + nm.to_s(), digits: ast_get(cargs[0], :value)}
    inner = interp_pipe_juxta_target(cargs[0])
    if inner == nil
      return nil
    {name: ("" + nm.to_s()) + inner[:name], digits: inner[:digits]}

  -> eval_binary_op(node, env)
    # Canonicalize the op symbol: slab-stored short symbols carry different
    # WValue bits than SSO literals, and mixed-mode == is slab-layout-
    # sensitive. w_switch_canonical repacks ≤5-byte content to SSO bits so
    # every comparison below is a deterministic bit match.
    node_op = ccall("w_switch_canonical", ast_get(node, :op))
    # `add/2` — a method reference (mirrors lowering/ops.w): a bare source
    # function name that is not a variable, over an integer literal, is
    # the closure `->(a, b) add(a, b)`. `x/2` on a variable stays division.
    if node_op == :SLASH
      mr_left = ast_get(node, :left)
      mr_right = ast_get(node, :right)
      if is_ast_node?(mr_left) && ast_kind(mr_left) == :var && is_ast_node?(mr_right) && ast_kind(mr_right) == :int
        mr_name = ast_get(mr_left, :name)
        if !env.defined?(mr_name) && callable?(mr_name)
          mr_arity = ast_get(mr_right, :value)
          mr_params = []
          mr_args = []
          mi = 0
          while mi < mr_arity
            mr_params.push("__mr" + (mi + 1).to_s())
            mr_args.push(Tungsten:AST:Var.new("__mr" + (mi + 1).to_s()))
            mi += 1
          mr_call = Tungsten:AST:Call.new(nil, mr_name, mr_args, nil)
          return evaluate(Tungsten:AST:Block.new(mr_params, [mr_call]), env)
    if node_op == :PIPE
      pu = interp_pipe_unit_target(node, env)
      if pu != nil
        left = evaluate(ast_get(node, :left), env)
        # Quantities convert; bare numbers attach; arrays (`%d[…] | m/s`)
        # map elementwise — all inside w_quantity_pipe, mirroring the
        # compiled path which routes every unit-target pipe through it.
        tn = w_type_name(left)
        if tn == "Quantity" || tn == "Array" || tn == "Decimal" || tn == "Int"
          return ccall("w_quantity_pipe", left, "" + pu[:name], pu[:digits])
    if node_op == :STAR && current_self() == nil
      # Script-level multiplication operands that are undefined bare
      # names resolve as symbolic 1·name unit factors (mirrors `2x`
      # juxtaposition and the compiled :STAR rewrite); inside class
      # bodies implicit-self dispatch keeps sole ownership of bare names.
      star_l = ast_get(node, :left)
      star_r = ast_get(node, :right)
      star_lv = nil
      if is_ast_node?(star_l) && ast_kind(star_l) == :var
        star_lv = eval_var(star_l, env, true)
      else
        star_lv = evaluate(star_l, env)
      star_rv = nil
      if is_ast_node?(star_r) && ast_kind(star_r) == :var
        star_rv = eval_var(star_r, env, true)
      else
        star_rv = evaluate(star_r, env)
      return apply_binary_op(node_op, star_lv, star_rv)
    if node_op == :LSHIFT && ast_get(node, :left) != nil && ast_kind(ast_get(node, :left)) == :var
      left = evaluate(ast_get(node, :left), env)
      if type(left) == "String"
        right = evaluate(ast_get(node, :right), env)
        # Compiled String `<<` lowers to w_str_append. Calling the same helper
        # here is observably important after the static slab freezes: `+` may
        # return the already-interned right operand, while append must mint the
        # fresh heap representation required by source ports such as
        # Array#join.
        result = ccall("w_str_append", left, w_to_s(right))
        env.set(ast_get(ast_get(node, :left), :name), result)
        return result
    left = evaluate(ast_get(node, :left), env)
    right = evaluate(ast_get(node, :right), env)
    # Exactness-gated literal adaptation: ==/!= with an int or decimal
    # LITERAL operand routes through w_eq_lit — the literal adapts to a
    # Float operand iff exactly representable. Variables stay strict.
    if node_op == :EQ || node_op == :NEQ
      eq_ln = ast_get(node, :left)
      eq_rn = ast_get(node, :right)
      eq_lit = false
      if eq_ln != nil && is_ast_node?(eq_ln) && ast_kind(eq_ln) in (:int :decimal)
        eq_lit = true
      if eq_rn != nil && is_ast_node?(eq_rn) && ast_kind(eq_rn) in (:int :decimal)
        eq_lit = true
      if eq_lit
        eq_r = ccall("w_eq_lit", left, right)
        if node_op == :NEQ
          return !eq_r
        return eq_r
    apply_binary_op(node_op, left, right)

  -> apply_binary_op(op, left, right)
    # Ordered user values compare through their polymorphic `<=>`. Dispatching
    # here before the primitive `<`/`>` arms keeps Comparable classes out of
    # the packed-number runtime path; a user object on the right is compared
    # in reverse so `1 < algebraic_root` works too.
    if op in (:LT :LTE :GT :GTE)
      comparison = nil
      reversed = false
      if type(left) == "Hash" && left.has_key?(:rt) && left[:rt] == :object
        comparison = dispatch_method(left, "<=>", [right], nil, nil)
      elsif type(right) == "Hash" && right.has_key?(:rt) && right[:rt] == :object
        comparison = dispatch_method(right, "<=>", [left], nil, nil)
        reversed = true
      if comparison != nil
        comparison = 0 - comparison if reversed
        return comparison < 0 if op == :LT
        return comparison <= 0 if op == :LTE
        return comparison > 0 if op == :GT
        return comparison >= 0

    # Object operands dispatch their own operator method (a + b -> a.+(b)),
    # mirroring the compiled operator-overload path and the `·` arm below —
    # covers the hypercomplex tower, Vec/Mat, etc. Arithmetic/bitwise here and
    # `==`/`!=` just below; ordering comparisons were handled above.
    if type(left) == "Hash" && left.has_key?(:rt) && left[:rt] == :object
      opn = binop_method_name(op)
      if opn != nil
        return dispatch_method(left, opn, [right], nil, nil)
      # `==` dispatches to a BODIED user `==` override, mirroring runtime
      # w_eq's override-guarded dispatch (Object#==/1 is a bodyless native
      # declaration, so plain objects keep identity semantics). `!=` is
      # always the negation of `==`, exactly like compiled w_neq — a
      # user-defined `!=` method is not consulted by the operator.
      if op == :EQ || op == :NEQ
        m = lookup_method(left[:w_class], "==", 1, false, [right])
        if m != nil && m[:body] != nil && m[:body].size() > 0
          result = call_w_method(left, m, [right], nil, nil)
          if op == :EQ
            return result
          return result == true ? false : true
        # Plain source objects use identity equality. Their interpreter
        # representation is a metadata Hash, so falling through to Hash#==
        # would compare fields structurally and diverge from native w_eq.
        identical = wvalue_bits(left) == wvalue_bits(right)
        return identical if op == :EQ
        return !identical
    if op == :PLUS
      # Strict string `+` — only text concatenates with text; a String
      # mixed with anything else is a TypeError, mirroring runtime w_add.
      if type(left) == "String"
        if type(right) == "String" || type(right) == "Char"
          return left + right
        raise "TypeError: no implicit conversion of [w_type_name(right)] into String"
      if type(left) == "Array"
        # array + array concatenates; array + scalar is elementwise
        # broadcast (proposal §3.5) — both go through runtime w_add, which
        # NEVER appends a scalar (mirrors the compiled path).
        return left + right
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
    if op == :APPROX
      return ccall("w_approx_eq", left, right)
    if op == :LT
      return left < right
    if op == :LTE
      return left <= right
    if op == :GT
      return left > right
    if op == :GTE
      return left >= right
    # Dot-prefix elementwise operators (`a .* b`, `a .+ 2`, …) — route to the
    # same runtime kernels the compiled path uses (lowering/ops.w); they own
    # the int/float/w64 ebits split and scalar-rhs broadcast. Interpreter
    # arrays (typed and plain literals) are real runtime WValues, so the
    # passthrough is exact. Added because the compiled path grew these ops
    # without interpreter twins ("Unknown operator: DOT_STAR" under
    # `tungsten run`). One ccall per arm: the C VM stage-0 requires ccall's
    # first argument to be a string LITERAL, not a variable.
    if op == :DOT_PLUS
      return ccall("w_array_add_elem", left, right)
    if op == :DOT_MINUS
      return ccall("w_array_sub_elem", left, right)
    if op == :DOT_STAR
      return ccall("w_array_mul_elem", left, right)
    if op == :DOT_SLASH
      return ccall("w_array_div_elem", left, right)
    if op == :DOT_PIPE
      return ccall("w_array_bor_elem", left, right)
    if op == :DOT_AMP
      return ccall("w_array_band_elem", left, right)
    if op == :DOT_CARET
      return ccall("w_array_bxor_elem", left, right)
    if op == :DOT_LSHIFT
      return ccall("w_array_shl_elem", left, right)
    if op == :DOT_RSHIFT
      return ccall("w_array_shr_elem", left, right)
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
    if op == :HADAMARD
      return "⊙"
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
      # A user object negates through its own `-@` operator method (which the
      # numeric tower aliases to `negate`), mirroring the compiled path's
      # w_neg -> `-@` instance dispatch. Primitives keep the `0 - x` arm.
      if type(operand) == "Hash" && operand.has_key?(:rt) && operand[:rt] == :object
        return dispatch_method(operand, "-@", [], nil, nil)
      # BigInt negation must reach the runtime's w_neg, not the `0 - x`
      # subtraction: w_neg is the tag-sign flip (encoding v4) — a zero-copy
      # LINKED VIEW whose bang-mutation semantics both engines must share.
      # `0 - x` would mint an independent copy and the engines would
      # diverge exactly where the tag-sign spec pins them together.
      if type(operand) == "BigInt"
        return ccall("w_neg", operand)
      return 0 - operand
    raise "Unknown unary operator"

  -> apply_type_hint(value, hint)
    if hint == nil
      return value
    hint = resolve_interpreted_type_hint(hint)
    value_type = type(value)
    if value_type == "Array"
      open = hint.index("\[")
      if open != nil && hint.slice(hint.size() - 1, 1) == "\]"
        element_type = hint.slice(0, open)
        if element_type == "f64"
          return ccall("w_array_to_f64", value)
        if element_type == "f32"
          return ccall("w_array_to_f32", value)
    if hint == "f64" || hint == "f32"
      if value_type in ("Int" "BigInt" "Float" "Decimal" "Rational")
        return ccall("w_num_to_float", value)
      return value
    if value_type == "Float" && hint in ("u64" "i64" "u128" "i128")
      value = value.to_i()
      value_type = type(value)
    if !(value_type in ("Int" "BigInt"))
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

  # Resolve a generic hint against the currently executing receiver. Generic
  # templates are shared by the tree walker, so actual type arguments live on
  # the scoped class send or on the object constructed by that send rather
  # than being written into the template AST. Handles both `## T` and array
  # forms such as `## T[4]`.
  -> resolve_interpreted_type_hint(hint)
    resolved = "" + hint.to_s()
    method = @method_stack.last()
    if method == nil || method[:w_class] == nil
      return resolved
    params = method[:w_class][:type_params]
    if params == nil || params.size() == 0
      return resolved
    receiver = current_self()
    if receiver == nil || type(receiver) != "Hash"
      return resolved
    actuals = nil
    if receiver[:rt] == :class
      actuals = receiver[:active_type_args]
    elsif receiver[:rt] == :object
      actuals = receiver[:type_args]
    if actuals == nil
      return resolved
    i = 0
    while i < params.size() && i < actuals.size()
      param = "" + params[i].to_s()
      actual = "" + actuals[i].to_s()
      if resolved == param
        return actual
      prefix = param + "\["
      if resolved.starts_with?(prefix)
        return actual + resolved.slice(param.size(), resolved.size() - param.size())
      i += 1
    resolved

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
    # These are the only widths apply_type_hint requests. Spelling their
    # moduli as BigInt literals prevents this compiler implementation's own
    # native i64 loop inference from wrapping 2^64 to zero (which made any
    # eval-mode `## i64` assignment die in `value % modulus`).
    if bits == 64
      return 18446744073709551616
    if bits == 128
      return 340282366920938463463374607431768211456
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
      pat_node = ast_get(arm, :pattern)
      pattern = evaluate(pat_node, env)
      matched = pattern == subject
      if !matched && pat_node != nil && is_ast_node?(pat_node) && ast_kind(pat_node) in (:int :decimal)
        # when-literals get the same exactness-gated adaptation as ==:
        # `case ~x when 2` hits when x is exactly 2.0.
        matched = ccall("w_eq_lit", subject, pattern)
      if matched
        guard = ast_get(arm, :guard)
        if guard == nil || truthy?(evaluate(guard, env))
          return evaluate_body(ast_get(arm, :body), env)
      i += 1
    if ast_get(node, :else_body) != nil
      return evaluate_body(ast_get(node, :else_body), env)
    nil

  # -- Method calls --

  -> eval_call(node, env)
    contract = interpreter_contract_name(node)
    if contract != nil
      if ast_get(node, :validated_program_contract) != true
        raise "Tungsten." + contract + " must be a top-level entry-program declaration"
      if @entry_file != nil && @current_file != @entry_file
        raise "Tungsten." + contract + " may only be declared by the entry program"
      if contract == "PROTECT_THE_CORE!"
        @core_protected = true
      elsif contract == "STOP_THE_PRESS!"
        @type_tables_locked = true
      else
        @type_tables_locked = true
        @method_tables_locked = true
      return nil
    # `f(1, _)` — explicit partial application: a bare `_` argument that is
    # not a bound variable is a placeholder, and the call denotes the lambda
    # over the placeholders (mirrors lowering/calls.w placeholder_lambda_for_call).
    if !env.defined?("_")
      ph_names = []
      ph_args = []
      raw_args = ast_get(node, :args)
      pi = 0
      while pi < raw_args.size()
        pa = raw_args[pi]
        if is_ast_node?(pa) && ast_kind(pa) == :var && ast_get(pa, :name) == "_"
          ph_name = "__pa" + (ph_names.size() + 1).to_s()
          ph_names.push(ph_name)
          ph_args.push(Tungsten:AST:Var.new(ph_name))
        else
          ph_args.push(pa)
        pi += 1
      if ph_names.size() > 0
        ph_call = Tungsten:AST:Call.new(ast_get(node, :receiver), ast_get(node, :name), ph_args, ast_get(node, :block))
        return evaluate(Tungsten:AST:Block.new(ph_names, [ph_call]), env)
    block = nil
    if ast_get(node, :block) != nil
      block = evaluate(ast_get(node, :block), env)
    args = ast_get(node, :args).map -> (a)
      evaluate(a, env)

    if ast_get(node, :receiver) != nil
      # `$bytes[i]` on WNetAddr/UUID is an inline fixed-array load in compiled
      # methods. Route the interpreted equivalent through the corresponding
      # narrow storage boundary without materializing a temporary byte array.
      recv_node = ast_get(node, :receiver)
      if ast_get(node, :name) in ("\[]" "[]") && ast_kind(recv_node) == :gvar && ast_get(recv_node, :name) == "$bytes"
        current_method = @method_stack.last()
        if current_method != nil && current_method[:w_class] != nil && current_method[:w_class][:name] == "UUID"
          return ccall("w_uuid_byte", current_self(), args[0])
        return ccall("w_netaddr_raw_byte", current_self(), args[0])
      if ast_get(node, :name) in ("\[]" "[]") && ast_kind(recv_node) == :view_field_var && ast_get(recv_node, :field) == "bytes"
        explicit_recv = evaluate(ast_get(recv_node, :receiver), env)
        if w_type_name(explicit_recv) == "UUID"
          return ccall("w_uuid_byte", explicit_recv, args[0])
        return ccall("w_netaddr_raw_byte", explicit_recv, args[0])
      # `$limbs[i]` / `other$limbs[i]` — indexed native array element on a
      # BigInt's u64[] tail, the walker mirror of the compiled strided load.
      if ast_get(node, :name) in ("\[]" "[]") && ast_kind(recv_node) == :gvar && ast_get(recv_node, :name) == "$limbs"
        current_method = @method_stack.last()
        if current_method != nil && current_method[:w_class] != nil
          return ccall("w_native_data_elem", current_self(), "limbs", args[0])
      if ast_get(node, :name) in ("\[]" "[]") && ast_kind(recv_node) == :view_field_var && ast_get(recv_node, :field) == "limbs"
        explicit_recv = evaluate(ast_get(recv_node, :receiver), env)
        return ccall("w_native_data_elem", explicit_recv, "limbs", args[0])
      # `$limbs[i] = v` reaches the walker as an expression call named "[]="
      # (two args), not through eval_call_assign — handle both stores here.
      if ast_get(node, :name) in ("\[]=" "[]=") && ast_kind(recv_node) == :gvar && ast_get(recv_node, :name) == "$limbs"
        current_method = @method_stack.last()
        if current_method != nil && current_method[:w_class] != nil
          return ccall("w_native_data_elem_set", current_self(), "limbs", args[0], args[1])
      if ast_get(node, :name) in ("\[]=" "[]=") && ast_kind(recv_node) == :view_field_var && ast_get(recv_node, :field) == "limbs"
        explicit_recv = evaluate(ast_get(recv_node, :receiver), env)
        return ccall("w_native_data_elem_set", explicit_recv, "limbs", args[0], args[1])
      recv = evaluate(ast_get(node, :receiver), env)
      # The parser transfers `Mat2<f64>.identity`'s type arguments from the
      # class-ref receiver onto the call node. Keep them scoped to this class
      # send so `## T` inside the class method (and a nested `class.new`) can
      # resolve T without permanently specializing the shared class object.
      call_type_args = ast_get(node, :type_args)
      if call_type_args != nil && type(recv) == "Hash" && recv[:rt] == :class
        previous_type_args = recv[:active_type_args]
        recv[:active_type_args] = call_type_args
        begin
          result = dispatch_method(recv, ast_get(node, :name), args, block, env)
        ensure
          recv[:active_type_args] = previous_type_args
      else
        result = dispatch_method(recv, ast_get(node, :name), args, block, env)
      if ast_kind(ast_get(node, :receiver)) == :var && type(recv) == "String"
        if ast_get(node, :name) in ("concat" "append" "prepend" "<<" "<</1")
          env.set(ast_get(ast_get(node, :receiver), :name), result)
      return result

    dispatch_bare_call(ast_get(node, :name), args, block, env)

  -> dispatch_bare_call(name, args, block, env)
    if name == "ccall"
      return dispatch_interpreted_ccall(args)
    if name == "ccall_nobox"
      return dispatch_interpreted_ccall_nobox(args)
    # `block?` — true iff the innermost enclosing method call carries a
    # block (attached trailing block, or a closure bound to its `&` param).
    # Every call_w_method frame owns a __block__ slot (nil when no block), so
    # the nearest binding is authoritative and a caller's block cannot leak
    # through the environment chain. `block_given?` is the compatibility alias.
    if name in ("block?" "block_given?") && args.size() == 0
      if !env.defined?("__block__")
        return false
      return env.get("__block__") != nil
    # `constant_alias "WC"` bit directive. The parser stamped the declaring
    # file's `in` namespace as a second argument (parser.w), so registration
    # needs no file context; the single-arg form (no active namespace at the
    # declaration site) is a no-op. Mirrors the compiled path: prepass
    # registration in lowering.w + expansion in eval_class_ref here.
    if name == "constant_alias"
      if args.size() == 2 && type(args[0]) == "String" && type(args[1]) == "String"
        @constant_aliases[args[0]] = args[1]
      return nil
    # Compiled packed values and their source-level raw representation are
    # both i64, so these lower to no instructions. The tree walker needs an
    # explicit bridge because its raw bits are represented as an Integer.
    if name == "wvalue_bits"
      if args.size() != 1
        raise "wvalue_bits expects one argument"
      return ccall("w_u64", args[0])

    # Tree-walker mirrors for the compiler's unsigned carry primitives. The
    # interpreter already has arbitrary-precision integers, so compute the
    # exact 64-bit result directly and keep the same 0..2^64-1 value domain as
    # native u64 lowering.
    if name in ("mulhi" "addcarry" "subborrow")
      if args.size() != 2
        raise "[name] expects two arguments"
      mask = 18446744073709551615
      a = args[0] & mask
      b = args[1] & mask
      if name == "mulhi"
        return (a * b) >> 64
      if name == "addcarry"
        return (a + b) >> 64
      return a < b ? 1 : 0
    if name == "wvalue_from_bits"
      if args.size() != 1
        raise "wvalue_from_bits expects one argument"
      bits = args[0]
      # String/Symbol#to_s clears the Symbol marker directly on the raw
      # WValue. Native lowering treats that word as already boxed; mirror the
      # exact rebox through a checked String-only bridge in the tree walker.
      if ((bits >> 48) & 0xFFFF) == 0xFFF9 && (bits & 1) == 0
        return ccall("w_string_from_bits", bits)
      # Immediate integers are the other source-defined user of this
      # intrinsic. Sign-extend their 48-bit NaN-box payload into the tree
      # walker's ordinary arbitrary-precision Integer representation.
      if ((bits >> 48) & 0xFFFF) == 0xFFFA
        payload = bits & 0xFFFFFFFFFFFF
        if payload >= 0x800000000000
          return payload - 0x1000000000000
        return payload
      # Float#abs emits a nonnegative biased Float word. Decode that exact
      # range through the existing IEEE-u64 bridge; the compiled intrinsic is
      # still an instruction-free identity on the already-boxed i64 word.
      # The upper bound is the runtime's canonical positive NaN.
      if bits >= 0x0001000000000000 && bits <= 0x7FF9000000000000
        return ccall("w_float_from_u64_bits", bits - 0x0001000000000000)
      # BigInt#abs flips the tag-sign overlay directly on the raw WValue.
      # Rebox through the checked BigInt-only bridge, mirroring the String
      # arm; native lowering is still an instruction-free identity.
      if ((bits >> 48) & 0xFFFF) == 0xFFFB
        return ccall("w_bigint_from_bits", bits)
      # Decode packed IPv4 through the existing interpreter ccall allowlist;
      # native code remains a zero-call i64 bit cast.
      if ((bits >> 48) & 0xFFFF) == 0xFFFE && ((bits >> 45) & 0x7) == 5
        address = (bits >> 12) & 0xFFFFFFFF
        prefix_bits = (bits >> 6) & 0x3F
        prefix = prefix_bits <= 32 ? prefix_bits : nil
        return ccall("w_ipv4_from_octets",
                     (address >> 24) & 0xFF,
                     (address >> 16) & 0xFF,
                     (address >> 8) & 0xFF,
                     address & 0xFF,
                     prefix)
      raise "wvalue_from_bits: unsupported packed WValue: " + bits.to_s()

    # Tree-walker mirrors of the compiler's inline raw byte intrinsics. Pointer
    # values are ordinary interpreter Integers here, so unbox all operands at
    # this explicit allowlisted boundary before calling the runtime mirrors.
    if name == "raw_load_u8" && args.size() == 2
      ptr = ccall_nobox("w_numeric_to_i64", args[0]) ## i64
      index = ccall_nobox("w_numeric_to_i64", args[1]) ## i64
      return ccall("w_int", ccall_nobox("w_raw_load_u8", ptr, index))
    if name == "raw_store_u8" && args.size() == 3
      ptr = ccall_nobox("w_numeric_to_i64", args[0]) ## i64
      index = ccall_nobox("w_numeric_to_i64", args[1]) ## i64
      value = ccall_nobox("w_numeric_to_i64", args[2]) ## i64
      return ccall("w_int", ccall_nobox("w_raw_store_u8", ptr, index, value))

    # Bit-count intrinsics (compiled: llvm.ctpop / llvm.cttz). Plain integer
    # arithmetic keeps the tree-walker exact over the full u64 domain.
    if name in ("popcount" "cttz") && args.size() == 1
      w = args[0] & 18446744073709551615
      if name == "popcount"
        c = 0
        while w != 0
          w = w & (w - 1)
          c += 1
        return c
      if w == 0
        return 64
      c = 0
      while (w & 1) == 0
        w = w >> 1
        c += 1
      return c
    # u8[] payload word access (compiled: one unaligned i64 load/store).
    # Little-endian, eight subscripts here; prefetch is a hint with no
    # interpreter effect.
    if name == "array_load_u64" && args.size() == 2
      arr = args[0]
      off = args[1]
      w = 0
      k = 7
      while k >= 0
        w = (w << 8) | (arr[off + k] & 255)
        k -= 1
      return w
    if name == "array_store_u64" && args.size() == 3
      arr = args[0]
      off = args[1]
      v = args[2] & 18446744073709551615
      k = 0
      while k < 8
        arr[off + k] = (v >> (8 * k)) & 255
        k += 1
      return args[2]
    if name == "prefetch" && args.size() == 2
      return 0

    # Explicit fused multiply-add. Route the tree-walker through libm so its
    # single-rounding result agrees with compiled llvm.fma.f64.
    if name == "fma" && args.size() == 3
      return ccall("w_math_fma", args[0], args[1], args[2])

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
        acc = acc + call_block1(f, x)
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
      acc = call_block1(f, a) + call_block1(f, b)
      i = 1
      while i < n
        w = 2
        if i % 2 == 1
          w = 4
        acc = acc + w * call_block1(f, a + h * i)
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
    m = implicit_self_method(s, name, args.size(), block != nil, args)
    if m != nil
      return call_w_method(s, m, args, block, env)

    # Bare Base64 compatibility calls do not name the Base64 class, so trigger
    # the same core/base64.w autoload that the compiled loader performs before
    # consulting the global method table.
    if name in ("base64_encode" "base64_decode" "base64url_encode" "base64url_decode")
      method_key = "__method__" + name
      if !@env.defined?(method_key)
        try_autoload_class("Base64")

    # Global method
    method_key = "__method__" + name
    if @env.defined?(method_key)
      m = nil
      overloads = @function_overloads[name]
      if overloads != nil
        m = select_typed_overload(overloads, args.size(), block != nil, args)
      if m == nil
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

    raise_typed("NoMethodError", "Undefined method '[name]'")
