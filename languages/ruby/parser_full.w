# tungsten/languages/ruby/parser_full.w — Complete Ruby 3.4 / 4.0 Parser
# emitting RbNode AST mapped directly to Tungsten's KIND_* AST vocabulary.

use ast
use lexer_full

+ RbParser
  -> new(@toks, @frozen_strings = false, @filename = "(eval)", @end_data = nil)
    @i = 0
    @n = @toks.size
    @is_stream = @toks.is_a?(RbTokenStream)
    @in_arg_list = false
    @in_hash_key = false
    @in_case_subj = false
    @in_multi_lhs = false
    @in_block_params = false
    @no_do_block = false
    @no_brace_block = false

  -> space_before?(idx = nil)
    return false if !@is_stream
    @toks.space_before?(idx == nil ? @i : idx)

  -> cur
    @i < @n ? @toks[@i] : @toks[@n - 1]

  -> peek(off = 1)
    k = @i + off
    k < @n ? @toks[k] : @toks[@n - 1]

  -> adv
    t = cur()
    @i += 1 if @i < @n - 1
    t

  -> at?(tp)
    if @is_stream
      id = RB_SYM_TO_ID[tp]
      return id != nil && @toks.id_at(@i) == id
    cur().type == tp

  -> at_op?(s)
    if @is_stream
      return @toks.id_at(@i) == RB_T_OP && @toks.raw_slice(@i) == s
    cur().type == :op && cur().val == s

  -> skip_nl
    if @is_stream
      while @i < @n - 1 && @toks.id_at(@i) == RB_T_NL
        @i += 1
      return nil
    while cur().type == :nl
      adv()

  -> skip_seps
    if @is_stream
      while @i < @n - 1
        id = @toks.id_at(@i)
        break if id != RB_T_NL && id != RB_T_SEMI
        @i += 1
      return nil
    while cur().type == :nl || cur().type == :semi
      adv()

  -> expect(tp)
    t = cur()
    raise "Ruby SyntaxError line " + t.line.to_s + ": expected " + tp.to_s + ", got " + t.type.to_s + " (" + t.val.to_s + ")" if t.type != tp
    adv()

  -> parse_program
    stmts = parse_stmts([:eof])
    RbNode.new(:program, stmts, @frozen_strings, @end_data, nil, 1)

  -> parse_stmts(stops)
    out = []
    skip_seps()
    while !at?(:eof) && !stops.include?(cur().type)
      out.push(parse_stmt())
      skip_seps()
    out

  -> parse_stmt
    t = cur()
    # Low-precedence statement keywords
    if t.type == :kw_alias
      adv()
      a = parse_alias_name()
      b = parse_alias_name()
      return RbNode.new(:alias, a, b, nil, nil, t.line)
    if t.type == :kw_undef
      adv()
      names = [parse_alias_name()]
      while at?(:comma)
        adv()
        names.push(parse_alias_name())
      return RbNode.new(:undef, names, nil, nil, nil, t.line)
    expr = parse_expr()
    # Check statement modifiers: expr if/unless/while/until/rescue cond
    while true
      m = cur()
      if m.type == :kw_if
        adv()
        skip_nl()
        c = parse_expr()
        expr = RbNode.new(:if, c, [expr], nil, nil, m.line)
      elsif m.type == :kw_unless
        adv()
        skip_nl()
        c = parse_expr()
        expr = RbNode.new(:if, RbNode.new(:not, c, nil, nil, nil, m.line), [expr], nil, nil, m.line)
      elsif m.type == :kw_while
        adv()
        skip_nl()
        c = parse_expr()
        expr = RbNode.new(:while, c, [expr], false, nil, m.line)
      elsif m.type == :kw_until
        adv()
        skip_nl()
        c = parse_expr()
        expr = RbNode.new(:while, c, [expr], true, nil, m.line)
      elsif m.type == :kw_rescue
        adv()
        skip_nl()
        fb = parse_expr()
        expr = RbNode.new(:begin, [expr], [[[], nil, [fb]]], nil, nil, m.line)
      else
        break
    expr

  -> parse_alias_name
    t = cur()
    if t.type == :symbol
      adv()
      return t.val
    if t.type == :dsym
      adv()
      return build_dstr_node(t.val, t.line, false)
    if t.type == :lbrack && peek().type == :rbrack
      adv(); adv()
      if at?(:assign) && cur().val == "=" && !space_before?()
        adv()
        return "[]="
      return "[]"
    if t.type == :ident || t.type == :const || t.type == :gvar || t.type == :op
      adv()
      nm = t.val.to_s
      if (nm == "-" || nm == "+" || nm == "~" || nm == "!") && at?(:ivar) && cur().val == "@"
        adv()
        nm = nm + "@"
      elsif t.type == :ident && at?(:assign) && cur().val == "=" && !space_before?()
        adv()
        nm = nm + "="
      return nm
    if @is_stream && @toks.id_at(@i) >= 50
      adv()
      return t.val.to_s
    raise "Ruby SyntaxError line " + t.line.to_s + ": invalid alias name " + t.val.to_s

  # Precedence levels:
  # 1. `and` / `or` / `not`
  # 2. assignment (`=`, `+=`, `||=`, ..., multi-assign `a, b = ...`)
  # 3. ternary `? :`
  # 4. ranges `..`, `...`
  # 5. `||`
  # 6. `&&`
  # 7. `==`, `!=`, `===`, `<=>`, `=~`, `!~`
  # 8. `<`, `<=`, `>`, `>=`
  # 9. `|`, `^`
  # 10. `&`
  # 11. `<<`, `>>`
  # 12. `+`, `-`
  # 13. `*`, `/`, `%`
  # 14. unary `-`, `+`, `~`, `!`
  # 15. `**` (right-associative)
  # 16. postfix (`.`, `&.`, `::`, `[]`, `()`, blocks)

  -> parse_expr
    e = parse_not_low()
    while cur().type == :kw_and || cur().type == :kw_or
      op = adv()
      skip_nl()
      r = parse_not_low()
      e = RbNode.new(op.type == :kw_and ? :and : :or, e, r, nil, nil, op.line)
    e

  -> parse_not_low
    if at?(:kw_not)
      t = adv()
      return RbNode.new(:not, parse_not_low(), nil, nil, nil, t.line)
    parse_assign()

  -> assignable?(n)
    n != nil && (n.kind == :var || n.kind == :ivar || n.kind == :cvar || n.kind == :gvar || n.kind == :const_ref || n.kind == :const_path || n.kind == :index || n.kind == :call || n.kind == :safe_nav || n.kind == :splat || n.kind == :mlhs_group)

  -> parse_mlhs_item(allow_expr_fallback = true)
    if at_op?("*")
      st = adv()
      if at?(:comma) || at?(:rparen) || (at?(:assign) && cur().val == "=") || at?(:kw_in)
        return RbNode.new(:splat, nil, nil, nil, nil, st.line)
      return RbNode.new(:splat, parse_ternary(), nil, nil, nil, st.line)
    if at?(:lparen)
      # Try grouped MLHS `(a, b)`; if not a valid grouped target (e.g. `(expr; obj).a`), rewind!
      save_p = @i
      lp = adv()
      items = []
      skip_nl()
      ok_p = true
      while !at?(:eof) && !at?(:rparen)
        nt = cur().type
        if !(nt == :ident || nt == :ivar || nt == :cvar || nt == :gvar || nt == :const || nt == :kw_self || nt == :lparen || (nt == :op && cur().val == "*"))
          ok_p = false
          break
        it = parse_mlhs_item(nt == :lparen)
        if it == nil || !assignable?(it)
          ok_p = false
          break
        items.push(it)
        if at?(:comma)
          adv()
          skip_nl()
        else
          break
      if ok_p && at?(:rparen)
        adv()
        if !at?(:dot) && !at?(:safe_dot) && !at?(:lbrack)
          return RbNode.new(:mlhs_group, items, nil, nil, nil, lp.line)
      @i = save_p
      return nil if !allow_expr_fallback
    parse_ternary()

  -> parse_assign
    # Handle return / break / next with optional value(s)
    t = cur()
    if t.type == :kw_return || t.type == :kw_break || t.type == :kw_next
      adv()
      k = t.type == :kw_return ? :return : (t.type == :kw_break ? :break : :next)
      val = nil
      if !at_stmt_end?()
        vals = [parse_expr()]
        while at?(:comma)
          adv()
          vals.push(parse_expr())
        val = vals.size == 1 ? vals[0] : RbNode.new(:array, vals, nil, nil, nil, t.line)
      return RbNode.new(k, val, nil, nil, nil, t.line)
    if t.type == :kw_redo
      adv()
      return RbNode.new(:redo, nil, nil, nil, nil, t.line)
    if t.type == :kw_retry
      adv()
      return RbNode.new(:retry, nil, nil, nil, nil, t.line)

    # Check grouped multi-assign LHS `((a, b), c), d = rhs`
    if at?(:lparen) && !@in_arg_list && !@in_multi_lhs
      pt = peek().type
      if pt == :ident || pt == :ivar || pt == :cvar || pt == :gvar || pt == :const || pt == :kw_self || pt == :lparen || (pt == :op && peek().val == "*")
        save_g = @i
        prev_m = @in_multi_lhs
        @in_multi_lhs = true
        first_g = parse_mlhs_item(false)
        if first_g != nil && first_g.kind == :mlhs_group && (at?(:comma) || (at?(:assign) && cur().val == "="))
          lhs_g = [first_g]
          ok_g = true
          while at?(:comma)
            adv()
            skip_nl()
            break if at?(:assign) && cur().val == "="
            ni = parse_mlhs_item()
            if !assignable?(ni)
              ok_g = false
              break
            lhs_g.push(ni)
          @in_multi_lhs = prev_m
          if ok_g && at?(:assign) && cur().val == "="
            eq = adv()
            skip_nl()
            rhs = [parse_assign()]
            while at?(:comma)
              adv()
              skip_nl()
              rhs.push(parse_assign())
            rhs_node = rhs.size == 1 ? rhs[0] : RbNode.new(:array, rhs, nil, nil, nil, eq.line)
            return RbNode.new(:multi_assign, lhs_g, rhs_node, nil, nil, eq.line)
        @in_multi_lhs = prev_m
        @i = save_g

    # Check splat LHS: `*a, b = ...` or `* = 1`
    left = nil
    if at_op?("*")
      st = adv()
      if at?(:comma) || (at?(:assign) && cur().val == "=")
        left = RbNode.new(:splat, nil, nil, nil, nil, st.line)
      else
        left = RbNode.new(:splat, parse_ternary(), nil, nil, nil, st.line)
    else
      left = parse_ternary()

    # Check Ruby 3.0-4.0 one-line pattern match: `expr in pat` or `expr => pat`
    if at?(:kw_in) && !@in_case_subj
      it = adv()
      skip_nl()
      pat = @in_arg_list ? parse_pattern() : parse_top_pattern()
      return RbNode.new(:pat_test, left, pat, false, nil, it.line)
    if at?(:arrow) && !@in_hash_key && !@in_arg_list && (assignable?(left) == false || peek().type != :nl)
      at_t = adv()
      skip_nl()
      pat = @in_arg_list ? parse_pattern() : parse_top_pattern()
      return RbNode.new(:pat_test, left, pat, true, nil, at_t.line)

    # Check multi-assignment `a, b, *c = rhs` (including `gc_stress, GC.stress = ...` and `ENV["a"], ENV["b"] = ...`)
    if at?(:comma) && assignable?(left) && !@in_arg_list
      save = @i
      prev_mlhs = @in_multi_lhs
      @in_multi_lhs = true
      lhs = [left]
      ok_multi = true
      while at?(:comma)
        adv()
        skip_nl()
        if at?(:assign) && cur().val == "="
          break
        nxt = parse_mlhs_item()
        if !assignable?(nxt)
          ok_multi = false
          break
        lhs.push(nxt)
      @in_multi_lhs = prev_mlhs
      if ok_multi && at?(:assign) && cur().val == "="
        eq = adv()
        skip_nl()
        rhs = [parse_assign()]
        while at?(:comma)
          adv()
          skip_nl()
          rhs.push(parse_assign())
        rhs_node = rhs.size == 1 ? rhs[0] : RbNode.new(:array, rhs, nil, nil, nil, eq.line)
        return RbNode.new(:multi_assign, lhs, rhs_node, nil, nil, eq.line)
      @i = save

    if at?(:assign)
      op = adv()
      skip_nl()
      rhs = parse_assign()
      # Allow `a = 1, 2, 3` (array RHS) at statement level
      if op.val == "=" && at?(:comma) && !@in_arg_list
        arr = [rhs]
        while at?(:comma)
          adv()
          skip_nl()
          arr.push(parse_assign())
        rhs = RbNode.new(:array, arr, nil, nil, nil, op.line)
      if op.val == "="
        return RbNode.new(:assign, left, rhs, nil, nil, op.line)
      return RbNode.new(:compound_assign, op.val, left, rhs, nil, op.line)
    left

  -> at_stmt_end?
    t = cur().type
    t == :eof || t == :nl || t == :semi || t == :colon || t == :kw_end || t == :kw_else || t == :kw_elsif ||
      t == :kw_when || t == :kw_rescue || t == :kw_ensure || t == :kw_if || t == :kw_unless ||
      t == :kw_while || t == :kw_until || t == :rparen || t == :rbrack || t == :rbrace || t == :kw_do

  -> parse_ternary
    cond = parse_range()
    if at?(:qmark)
      qt = adv()
      skip_nl()
      then_e = parse_assign()
      skip_nl()
      expect(:colon)
      skip_nl()
      else_e = parse_assign()
      return RbNode.new(:if, cond, [then_e], [else_e], nil, qt.line)
    cond

  -> parse_range
    # Beginless range `..5` or `...5`
    if at?(:dot2) || at?(:dot3)
      t = adv()
      excl = t.type == :dot3
      hi = at_stmt_end?() || at?(:rparen) || at?(:rbrack) || at?(:comma) ? nil : parse_or()
      return RbNode.new(:range, nil, hi, excl, nil, t.line)
    lo = parse_or()
    if at?(:dot2) || at?(:dot3)
      t = adv()
      excl = t.type == :dot3
      hi = at_stmt_end?() || at?(:rparen) || at?(:rbrack) || at?(:rbrace) || at?(:comma) ? nil : parse_or()
      return RbNode.new(:range, lo, hi, excl, nil, t.line)
    lo

  -> parse_or
    l = parse_and()
    while at_op?("||")
      t = adv()
      skip_nl()
      l = RbNode.new(:or, l, parse_and(), nil, nil, t.line)
    l

  -> parse_and
    l = parse_eq()
    while at_op?("&&")
      t = adv()
      skip_nl()
      l = RbNode.new(:and, l, parse_eq(), nil, nil, t.line)
    l

  -> parse_eq
    l = parse_rel()
    while cur().type == :op && (cur().val == "==" || cur().val == "!=" || cur().val == "===" || cur().val == "<=>" || cur().val == "=~" || cur().val == "!~")
      t = adv()
      skip_nl()
      l = RbNode.new(:binary_op, t.val, l, parse_rel(), nil, t.line)
    l

  -> parse_rel
    l = parse_bitor()
    while cur().type == :op && (cur().val == "<" || cur().val == "<=" || cur().val == ">" || cur().val == ">=")
      t = adv()
      skip_nl()
      l = RbNode.new(:binary_op, t.val, l, parse_bitor(), nil, t.line)
    l

  -> parse_bitor
    l = parse_bitand()
    while cur().type == :op && ((!@in_block_params && cur().val == "|") || cur().val == "^")
      t = adv()
      skip_nl()
      l = RbNode.new(:binary_op, t.val, l, parse_bitand(), nil, t.line)
    l

  -> parse_bitand
    l = parse_shift()
    while at_op?("&")
      t = adv()
      skip_nl()
      l = RbNode.new(:binary_op, "&", l, parse_shift(), nil, t.line)
    l

  -> parse_shift
    l = parse_add()
    while cur().type == :op && (cur().val == "<<" || cur().val == ">>")
      t = adv()
      skip_nl()
      l = RbNode.new(:binary_op, t.val, l, parse_add(), nil, t.line)
    l

  -> parse_add
    l = parse_mul()
    while cur().type == :op && (cur().val == "+" || cur().val == "-")
      t = adv()
      skip_nl()
      l = RbNode.new(:binary_op, t.val, l, parse_mul(), nil, t.line)
    l

  -> parse_mul
    l = parse_unary()
    while cur().type == :op && (cur().val == "*" || cur().val == "/" || cur().val == "%")
      t = adv()
      skip_nl()
      l = RbNode.new(:binary_op, t.val, l, parse_unary(), nil, t.line)
    l

  -> parse_unary
    t = cur()
    if t.type == :op && (t.val == "-" || t.val == "+" || t.val == "~" || t.val == "!")
      adv()
      skip_nl()
      op = t.val == "-" ? "-@" : (t.val == "+" ? "+@" : t.val)
      return RbNode.new(:unary_op, op, parse_unary(), nil, nil, t.line)
    parse_pow()

  -> parse_pow
    l = parse_postfix()
    if at_op?("**")
      t = adv()
      skip_nl()
      return RbNode.new(:binary_op, "**", l, parse_unary(), nil, t.line)
    l

  -> can_start_arg?
    t = cur().type
    return false if t == :eof || t == :nl || t == :semi || t == :rparen || t == :rbrack || t == :rbrace ||
                    t == :comma || t == :colon || t == :dot || t == :safe_dot || t == :arrow || t == :qmark ||
                    t == :assign || t == :kw_do || t == :kw_end || t == :kw_then || t == :kw_else ||
                    t == :kw_elsif || t == :kw_when || t == :kw_rescue || t == :kw_ensure ||
                    t == :kw_if || t == :kw_unless || t == :kw_while || t == :kw_until ||
                    t == :kw_and || t == :kw_or || t == :kw_in
    if t == :op
      v = cur().val
      return true if v == "!" || v == "~" || v == "**"
      if v == "-" || v == "+" || v == "*" || v == "&"
        return space_before?(@i) && !space_before?(@i + 1)
      return false
    true

  -> parse_call_args(close_tok)
    # close_tok: :rparen, :rbrack, or nil (unparenthesized command call)
    has_close = close_tok != nil
    args = []
    kw = []
    block_pass = nil
    prev_in_arg = @in_arg_list
    prev_bp = @in_block_params
    @in_arg_list = true
    @in_block_params = false if has_close
    skip_nl() if has_close
    while !at?(:eof)
      break if has_close && at?(close_tok)
      break if !has_close && !can_start_arg?()
      if at?(:dot3) && (peek().type == :comma || (has_close && peek().type == close_tok) || (!has_close && at_stmt_end?()))
        t3 = adv()
        args.push(RbNode.new(:arg_forward, nil, nil, nil, nil, t3.line))
      elsif at_op?("**")
        t2 = adv()
        if at?(:comma) || (has_close && at?(close_tok))
          kw.push([nil, RbNode.new(:var, "**", nil, nil, nil, t2.line)])
        else
          kw.push([nil, parse_ternary()])
      elsif at_op?("*")
        t1 = adv()
        if at?(:comma) || (has_close && at?(close_tok))
          args.push(RbNode.new(:splat, RbNode.new(:var, "*", nil, nil, nil, t1.line), nil, nil, nil, t1.line))
        else
          args.push(RbNode.new(:splat, parse_ternary(), nil, nil, nil, t1.line))
      elsif at_op?("&")
        ta = adv()
        if at?(:comma) || (has_close && at?(close_tok))
          block_pass = RbNode.new(:var, "&", nil, nil, nil, ta.line)
        else
          block_pass = parse_ternary()
      elsif at?(:label)
        lb = adv()
        skip_nl()
        # Ruby 3.1+ shorthand keyword arg `foo(x:, y:)` when value is omitted
        if at?(:comma) || (has_close && at?(close_tok)) || at_stmt_end?()
          kw.push([lb.val, RbNode.new(:var, lb.val, nil, nil, nil, lb.line)])
        else
          kw.push([lb.val, parse_assign()])
      else
        e = parse_assign()
        if at?(:arrow)
          adv()
          skip_nl()
          v = parse_assign()
          kw.push([e, v])
        else
          args.push(e)
      skip_nl() if has_close
      if at?(:comma)
        adv()
        skip_nl()
      else
        break
    skip_nl() if has_close
    expect(close_tok) if has_close
    @in_arg_list = prev_in_arg
    @in_block_params = prev_bp
    [args, kw, block_pass]

  -> parse_block_params
    params = []
    if at_op?("||")
      adv()
      return params
    return params if !at_op?("|")
    adv()
    prev_bp = @in_block_params
    @in_block_params = true
    skip_nl()
    while !at?(:eof) && !at_op?("|")
      if at_op?("*")
        adv()
        nm = at?(:ident) ? adv().val : "*"
        params.push([:splat, nm, nil])
      elsif at_op?("**")
        adv()
        nm = "**"
        if at?(:ident)
          nm = adv().val
        elsif at?(:kw_nil)
          adv()
          nm = :nil
        params.push([:kw_splat, nm, nil])
      elsif at_op?("&")
        adv()
        nm = at?(:ident) ? adv().val : "&"
        params.push([:block, nm, nil])
      elsif at?(:label)
        lb = adv()
        has_dflt = !at?(:comma) && !at_op?("|") && !at?(:semi)
        dflt = has_dflt ? parse_ternary() : nil
        params.push([has_dflt ? :kw_opt : :kw_req, lb.val, dflt])
      elsif at?(:ident)
        nm = adv().val
        dflt = nil
        if at?(:assign) && cur().val == "="
          adv()
          dflt = parse_ternary()
        params.push([dflt == nil ? :req : :opt, nm, dflt])
      elsif at?(:lparen)
        # Destructuring block param `|(a, b)|`, `|(a, *b)|`, `|(a, (b, c))|`
        adv()
        sub = []
        depth = 1
        while !at?(:eof) && depth > 0
          if at?(:lparen)
            depth += 1
            adv()
          elsif at?(:rparen)
            depth -= 1
            adv() if depth > 0
          elsif at?(:ident)
            sub.push(adv().val)
          else
            adv()
        expect(:rparen)
        params.push([:destruct, sub, nil])
      elsif at?(:semi)
        # Block-local variable declarations `|a; local1, local2|`
        adv()
        while !at?(:eof) && !at_op?("|")
          if at?(:ident)
            params.push([:block_local, adv().val, nil])
          else
            adv()
        break
      else
        break
      skip_nl()
      if at?(:comma)
        adv()
        skip_nl()
        if at_op?("|") || at?(:semi)
          params.push([:trailing_comma, nil, nil])
    adv() if at_op?("|")
    @in_block_params = prev_bp
    params

  -> parse_block_if_any(allow_do = true)
    if at?(:lbrace) && !@no_brace_block
      t = adv()
      params = parse_block_params()
      body = parse_stmts([:rbrace])
      expect(:rbrace)
      return RbNode.new(:block, params, body, false, nil, t.line)
    if allow_do && !@no_do_block && at?(:kw_do)
      t = adv()
      params = parse_block_params()
      body = parse_body_with_rescue(t.line, :kw_end)
      expect(:kw_end)
      return RbNode.new(:block, params, body, false, nil, t.line)
    nil

  -> parse_postfix
    node = parse_primary()
    while true
      # Continuation dot on next line: `foo\n  .bar`
      if at?(:nl) && (peek().type == :dot || peek().type == :safe_dot)
        adv()
      t = cur()
      if t.type == :dot || t.type == :safe_dot
        adv()
        skip_nl()
        safe = t.type == :safe_dot
        # Call syntax `obj.(args)` -> `obj.call(args)`
        if at?(:lparen)
          adv()
          ca = parse_call_args(:rparen)
          blk = parse_block_if_any(true)
          node = RbNode.new(safe ? :safe_nav : :call, node, "call", [ca[0], ca[1], ca[2], blk], nil, t.line)
          next
        mt = adv()
        mname = mt.val.to_s
        if mt.type == :lbrack && at?(:rbrack)
          adv()
          mname = "[]"
          if at?(:assign) && cur().val == "=" && !space_before?()
            adv()
            mname = "[]="
        # Check setter `obj.foo = val` (unless inside multi-assign LHS `a, obj.foo = 1, 2`)
        if !@in_multi_lhs && at?(:assign) && cur().val == "="
          adv()
          skip_nl()
          rhs = parse_assign()
          if at?(:comma) && !@in_arg_list
            arr = [rhs]
            while at?(:comma)
              adv()
              skip_nl()
              arr.push(parse_assign())
            rhs = RbNode.new(:array, arr, nil, nil, nil, t.line)
          node = RbNode.new(safe ? :safe_nav : :call, node, mname + "=", [[rhs], [], nil, nil], :assign_ret, t.line)
          next
        ca = [[], [], nil]
        if at?(:lparen) && !space_before?()
          adv()
          ca = parse_call_args(:rparen)
        elsif can_start_arg?() && !at?(:lbrace) && !at?(:kw_do) && (!at?(:lbrack) || space_before?())
          ca = parse_call_args(nil)
        blk = parse_block_if_any(true)
        node = RbNode.new(safe ? :safe_nav : :call, node, mname, [ca[0], ca[1], ca[2], blk], nil, t.line)
      elsif t.type == :colon2
        adv()
        mt = adv()
        if mt.type == :const && !at?(:lparen)
          node = RbNode.new(:const_path, node, mt.val, nil, nil, t.line)
        else
          ca = [[], [], nil]
          if at?(:lparen)
            adv()
            ca = parse_call_args(:rparen)
          blk = parse_block_if_any(true)
          node = RbNode.new(:call, node, mt.val.to_s, [ca[0], ca[1], ca[2], blk], nil, t.line)
      elsif t.type == :lbrack
        adv()
        ca = parse_call_args(:rbrack)
        if !@in_multi_lhs && at?(:assign) && cur().val == "="
          adv()
          skip_nl()
          rhs = parse_assign()
          if at?(:comma) && !@in_arg_list
            arr = [rhs]
            while at?(:comma)
              adv()
              skip_nl()
              arr.push(parse_assign())
            rhs = RbNode.new(:array, arr, nil, nil, nil, t.line)
          a2 = ca[0] + [rhs]
          node = RbNode.new(:call, node, '[]=', [a2, ca[1], ca[2], nil], :assign_ret, t.line)
        else
          node = RbNode.new(:call, node, '[]', [ca[0], ca[1], ca[2], nil], nil, t.line)
      elsif (t.type == :lbrace && !@no_brace_block) || (t.type == :kw_do && !@no_do_block)
        if node.kind == :call || node.kind == :safe_nav || node.kind == :var || node.kind == :super
          blk = parse_block_if_any(true)
          if node.kind == :var
            node = RbNode.new(:call, nil, node.a, [[], [], nil, blk], nil, node.line)
          elsif node.kind == :super
            node = RbNode.new(:super, node.a, blk, nil, nil, node.line)
          else
            node.c[3] = blk
        else
          break
      else
        break
    node

  -> parse_primary
    t = cur()
    case t.type
    when :int
      adv()
      RbNode.new(:int, t.val, nil, nil, nil, t.line)
    when :float
      adv()
      RbNode.new(:float, t.val, nil, nil, nil, t.line)
    when :rational
      adv()
      RbNode.new(:rational, t.val, t.extra, nil, nil, t.line)
    when :complex
      adv()
      RbNode.new(:complex, t.val, t.extra, nil, nil, t.line)
    when :string
      adv()
      node = RbNode.new(:string, t.val, t.extra, nil, nil, t.line)
      parse_adjacent_strings(node, t.line, t.extra)
    when :heredoc
      adv()
      hd = t.val
      if hd[0] == :xstr
        inner = hd[1][0] == :dstr ? build_dstr_node(hd[1][1], t.line, false) : RbNode.new(:string, hd[1][1], false, nil, nil, t.line)
        return RbNode.new(:call, nil, "`", [[inner], [], nil, nil], nil, t.line)
      node = hd[0] == :dstr ? build_dstr_node(hd[1], t.line, t.extra) : RbNode.new(:string, hd[1], t.extra, nil, nil, t.line)
      parse_adjacent_strings(node, t.line, t.extra)
    when :dstr
      adv()
      node = build_dstr_node(t.val, t.line, t.extra)
      parse_adjacent_strings(node, t.line, t.extra)
    when :xstr
      adv()
      inner = t.val[0] == :dstr ? build_dstr_node(t.val[1], t.line, false) : RbNode.new(:string, t.val[1], false, nil, nil, t.line)
      RbNode.new(:call, nil, "`", [[inner], [], nil, nil], nil, t.line)
    when :symbol
      adv()
      RbNode.new(:symbol, t.val, nil, nil, nil, t.line)
    when :dsym
      adv()
      RbNode.new(:call, build_dstr_node(t.val, t.line, false), "to_sym", [[], [], nil, nil], nil, t.line)
    when :regex
      adv()
      RbNode.new(:regex, t.val, t.extra, nil, nil, t.line)
    when :dregex
      adv()
      RbNode.new(:dregex, build_dstr_node(t.val, t.line, false), t.extra, nil, nil, t.line)
    when :word_array
      adv()
      els = []
      t.val.each ->(w)
        if w.is_a?(Array) && w.size == 2 && w[0] == :dstr
          els.push(build_dstr_node(w[1], t.line, @frozen_strings))
        else
          els.push(RbNode.new(:string, w, @frozen_strings, nil, nil, t.line))
      RbNode.new(:array, els, nil, nil, nil, t.line)
    when :sym_array
      adv()
      els = []
      t.val.each ->(w)
        if w.is_a?(Array) && w.size == 2 && w[0] == :dstr
          els.push(RbNode.new(:call, build_dstr_node(w[1], t.line, false), "to_sym", [[], [], nil, nil], nil, t.line))
        else
          els.push(RbNode.new(:symbol, w, nil, nil, nil, t.line))
      RbNode.new(:array, els, nil, nil, nil, t.line)
    when :kw_true
      adv(); RbNode.new(:bool, true, nil, nil, nil, t.line)
    when :kw_false
      adv(); RbNode.new(:bool, false, nil, nil, nil, t.line)
    when :kw_nil
      adv(); RbNode.new(:nil, nil, nil, nil, nil, t.line)
    when :kw_self
      adv(); RbNode.new(:self, nil, nil, nil, nil, t.line)
    when :kw_line
      adv(); RbNode.new(:int, t.line, nil, nil, nil, t.line)
    when :kw_file
      adv(); RbNode.new(:string, @filename, @frozen_strings, nil, nil, t.line)
    when :kw_encoding
      adv(); RbNode.new(:const_path, RbNode.new(:const_ref, "Encoding", nil, nil, nil, t.line), "UTF_8", nil, nil, t.line)
    when :ivar
      adv(); RbNode.new(:ivar, t.val, nil, nil, nil, t.line)
    when :cvar
      adv(); RbNode.new(:cvar, t.val, nil, nil, nil, t.line)
    when :gvar
      adv(); RbNode.new(:gvar, t.val, nil, nil, nil, t.line)
    when :colon2
      adv()
      ct = expect(:const)
      RbNode.new(:const_path, nil, ct.val, nil, nil, t.line)
    when :const
      adv()
      if at?(:lparen) && !space_before?()
        adv()
        ca = parse_call_args(:rparen)
        blk = parse_block_if_any(true)
        return RbNode.new(:call, nil, t.val, [ca[0], ca[1], ca[2], blk], nil, t.line)
      RbNode.new(:const_ref, t.val, nil, nil, nil, t.line)
    when :ident
      adv()
      if at?(:lparen) && !space_before?()
        adv()
        ca = parse_call_args(:rparen)
        blk = parse_block_if_any(true)
        return RbNode.new(:call, nil, t.val, [ca[0], ca[1], ca[2], blk], nil, t.line)
      if can_start_arg?() && !at?(:lbrace) && !at?(:kw_do) && !at?(:assign) && (!at?(:lbrack) || space_before?())
        # Command call `puts "hi"`, `assert_equal [x], y`, `raise TypeError, "bad"`
        ca = parse_call_args(nil)
        blk = parse_block_if_any(true)
        return RbNode.new(:call, nil, t.val, [ca[0], ca[1], ca[2], blk], nil, t.line)
      RbNode.new(:var, t.val, nil, nil, nil, t.line)
    when :lparen
      adv()
      prev_bp = @in_block_params
      prev_arg = @in_arg_list
      prev_mlhs = @in_multi_lhs
      @in_block_params = false
      @in_arg_list = false
      @in_multi_lhs = false
      stmts = parse_stmts([:rparen])
      expect(:rparen)
      @in_block_params = prev_bp
      @in_arg_list = prev_arg
      @in_multi_lhs = prev_mlhs
      return RbNode.new(:nil, nil, nil, nil, nil, t.line) if stmts.size == 0
      return stmts[0] if stmts.size == 1
      RbNode.new(:begin, stmts, [], nil, nil, t.line)
    when :lbrack
      adv()
      prev_in_arg = @in_arg_list
      prev_bp = @in_block_params
      @in_arg_list = true
      @in_block_params = false
      skip_nl()
      els = []
      hash_pairs = []
      while !at?(:eof) && !at?(:rbrack)
        if at_op?("**")
          adv()
          hash_pairs.push([nil, parse_ternary()])
        elsif at_op?("*")
          st = adv()
          els.push(RbNode.new(:splat, parse_assign(), nil, nil, nil, st.line))
        elsif at?(:label)
          lb = adv()
          skip_nl()
          if at?(:comma) || at?(:rbrack)
            hash_pairs.push([RbNode.new(:symbol, lb.val, nil, nil, nil, lb.line), RbNode.new(:var, lb.val, nil, nil, nil, lb.line)])
          else
            hash_pairs.push([RbNode.new(:symbol, lb.val, nil, nil, nil, lb.line), parse_assign()])
        else
          e = parse_assign()
          if at?(:arrow)
            adv()
            skip_nl()
            v = parse_assign()
            hash_pairs.push([e, v])
          else
            els.push(e)
        skip_nl()
        if at?(:comma)
          adv()
          skip_nl()
        else
          break
      if hash_pairs.size > 0
        els.push(RbNode.new(:hash, hash_pairs, nil, nil, nil, t.line))
      expect(:rbrack)
      @in_arg_list = prev_in_arg
      @in_block_params = prev_bp
      RbNode.new(:array, els, nil, nil, nil, t.line)
    when :kw_BEGIN
      adv()
      expect(:lbrace)
      body = parse_stmts([:rbrace])
      expect(:rbrace)
      RbNode.new(:begin_hook, body, nil, nil, nil, t.line)
    when :kw_END
      adv()
      expect(:lbrace)
      body = parse_stmts([:rbrace])
      expect(:rbrace)
      RbNode.new(:call, nil, "at_exit", [[], [], nil, RbNode.new(:block, [], body, false, nil, t.line)], nil, t.line)
    when :lbrace
      parse_hash_literal()
    when :stabby
      parse_stabby_lambda()
    when :kw_if
      parse_if(false)
    when :kw_unless
      parse_if(true)
    when :kw_case
      parse_case()
    when :kw_while
      parse_while(false)
    when :kw_until
      parse_while(true)
    when :kw_for
      parse_for()
    when :kw_begin
      parse_begin()
    when :kw_def
      parse_def()
    when :kw_class
      parse_class()
    when :kw_module
      parse_module()
    when :kw_yield
      adv()
      ca = [[], [], nil]
      if at?(:lparen) && !space_before?()
        adv()
        ca = parse_call_args(:rparen)
      elsif can_start_arg?() && (!at?(:lbrack) || space_before?())
        ca = parse_call_args(nil)
      RbNode.new(:yield, ca[0], ca[1], nil, nil, t.line)
    when :kw_super
      adv()
      ca = nil
      if at?(:lparen) && !space_before?()
        adv()
        ca = parse_call_args(:rparen)
      elsif can_start_arg?() && !at?(:lbrace) && !at?(:kw_do) && (!at?(:lbrack) || space_before?())
        ca = parse_call_args(nil)
      blk = parse_block_if_any(true)
      RbNode.new(:super, ca, blk, nil, nil, t.line)
    when :kw_defined
      adv()
      has_p = at?(:lparen)
      adv() if has_p
      inner = has_p && at?(:rparen) ? RbNode.new(:nil, nil, nil, nil, nil, t.line) : parse_expr()
      expect(:rparen) if has_p
      RbNode.new(:defined, inner, nil, nil, nil, t.line)
    else
      raise "Ruby SyntaxError line " + t.line.to_s + ": unexpected token " + t.type.to_s + " (" + t.val.to_s + ")"

  -> parse_adjacent_strings(node, line, frozen)
    while at?(:string) || at?(:dstr)
      nt = adv()
      rhs = nt.type == :dstr ? build_dstr_node(nt.val, nt.line, nt.extra) : RbNode.new(:string, nt.val, nt.extra, nil, nil, nt.line)
      if node.kind == :string && rhs.kind == :string
        node = RbNode.new(:string, node.a + rhs.a, frozen, nil, nil, line)
      else
        parts = node.kind == :string_interp ? node.a.dup : [node]
        if rhs.kind == :string_interp
          rhs.a.each ->(p) parts.push(p)
        else
          parts.push(rhs)
        node = RbNode.new(:string_interp, parts, frozen, nil, nil, line)
    node

  -> build_dstr_node(parts, line, frozen)
    out = []
    parts.each ->(p)
      if p[0] == :str
        out.push(RbNode.new(:string, p[1], frozen, nil, nil, line))
      elsif p[0] == :toks
        sub = RbParser.new(p[1], @frozen_strings).parse_program()
        out.push(sub)
      else
        sub = RbParser.new(RbLexer.new(p[1]).tokenize(), @frozen_strings).parse_program()
        out.push(sub)
    RbNode.new(:string_interp, out, frozen, nil, nil, line)

  -> parse_hash_literal
    t = expect(:lbrace)
    prev_arg = @in_arg_list
    prev_hk = @in_hash_key
    prev_bp = @in_block_params
    @in_arg_list = true
    @in_hash_key = true
    @in_block_params = false
    skip_nl()
    pairs = []
    while !at?(:eof) && !at?(:rbrace)
      if at_op?("**")
        adv()
        pairs.push([nil, parse_ternary()])
      elsif at?(:label)
        lb = adv()
        skip_nl()
        # Ruby 3.1+ shorthand hash `{a:, b:}`
        if at?(:comma) || at?(:rbrace)
          pairs.push([RbNode.new(:symbol, lb.val, nil, nil, nil, lb.line), RbNode.new(:var, lb.val, nil, nil, nil, lb.line)])
        else
          pairs.push([RbNode.new(:symbol, lb.val, nil, nil, nil, lb.line), parse_assign()])
      else
        k = parse_ternary()
        if at?(:colon) && (k.kind == :string || k.kind == :string_interp)
          adv()
          skip_nl()
          sym_k = k.kind == :string ? RbNode.new(:symbol, k.a, nil, nil, nil, k.line) : RbNode.new(:call, k, "to_sym", [[], [], nil, nil], nil, k.line)
          v = parse_assign()
          pairs.push([sym_k, v])
        else
          expect(:arrow)
          skip_nl()
          v = parse_assign()
          pairs.push([k, v])
      skip_nl()
      if at?(:comma)
        adv()
        skip_nl()
      else
        break
    expect(:rbrace)
    @in_arg_list = prev_arg
    @in_hash_key = prev_hk
    @in_block_params = prev_bp
    RbNode.new(:hash, pairs, nil, nil, nil, t.line)

  -> parse_stabby_lambda
    t = expect(:stabby)
    params = []
    if at?(:lparen)
      adv()
      params = parse_def_params_until(:rparen)
      expect(:rparen)
    elsif at?(:ident) || at_op?("*") || at_op?("**") || at_op?("&") || at?(:label)
      prev_nb = @no_brace_block
      prev_nd = @no_do_block
      @no_brace_block = true
      @no_do_block = true
      params = parse_def_params_until(:lbrace)
      @no_brace_block = prev_nb
      @no_do_block = prev_nd
    skip_nl()
    body = nil
    if at?(:lbrace)
      adv()
      body = parse_stmts([:rbrace])
      expect(:rbrace)
    else
      expect(:kw_do)
      body = parse_body_with_rescue(t.line, :kw_end)
      expect(:kw_end)
    RbNode.new(:lambda, params, body, true, nil, t.line)

  -> parse_if(negated)
    t = adv()
    cond = parse_expr()
    cond = RbNode.new(:not, cond, nil, nil, nil, t.line) if negated
    adv() if at?(:kw_then) || at?(:nl) || at?(:semi)
    then_b = parse_stmts([:kw_elsif, :kw_else, :kw_end])
    else_b = nil
    if at?(:kw_elsif)
      else_b = [parse_if(false)]
      return RbNode.new(:if, cond, then_b, else_b, nil, t.line)
    if at?(:kw_else)
      adv()
      else_b = parse_stmts([:kw_end])
    expect(:kw_end)
    RbNode.new(:if, cond, then_b, else_b, nil, t.line)

  -> parse_case
    t = expect(:kw_case)
    subj = nil
    if !(at?(:nl) || at?(:semi) || at?(:kw_when) || at?(:kw_in))
      prev_cs = @in_case_subj
      @in_case_subj = true
      subj = parse_expr()
      @in_case_subj = prev_cs
    skip_seps()
    # Pattern matching `case expr in pat ...`
    if at?(:kw_in)
      arms = []
      while at?(:kw_in)
        adv()
        pat = parse_top_pattern()
        guard = nil
        if at?(:kw_if)
          adv()
          guard = [:if, parse_expr()]
        elsif at?(:kw_unless)
          adv()
          guard = [:unless, parse_expr()]
        adv() if at?(:kw_then) || at?(:nl) || at?(:semi)
        body = parse_stmts([:kw_in, :kw_else, :kw_end])
        arms.push([pat, guard, body])
      else_b = nil
      if at?(:kw_else)
        adv()
        else_b = parse_stmts([:kw_end])
      expect(:kw_end)
      return RbNode.new(:case_in, subj, arms, else_b, nil, t.line)
    whens = []
    while at?(:kw_when)
      adv()
      vals = []
      while true
        if at_op?("*")
          st = adv()
          vals.push(RbNode.new(:splat, parse_ternary(), nil, nil, nil, st.line))
        else
          vals.push(parse_ternary())
        if at?(:comma)
          adv()
          skip_nl()
        else
          break
      adv() if at?(:kw_then) || at?(:nl) || at?(:semi)
      body = parse_stmts([:kw_when, :kw_else, :kw_end])
      whens.push([vals, body])
    else_b = nil
    if at?(:kw_else)
      adv()
      else_b = parse_stmts([:kw_end])
    expect(:kw_end)
    RbNode.new(:case, subj, whens, else_b, nil, t.line)

  # Ruby 3.0-4.0 Pattern Matching grammar: alt `|`, as `=> var`, pin `^x`, array `[a, *rest]`, hash `{x:, y: pat}`
  -> parse_top_pattern
    pat = parse_pattern()
    if at?(:comma)
      els = [pat]
      while at?(:comma)
        adv()
        skip_nl()
        break if at?(:nl) || at?(:semi) || at?(:kw_if) || at?(:kw_unless) || at?(:kw_then) || at?(:kw_end) || at?(:eof) || at?(:rparen)
        if at_op?("*")
          st = adv()
          nm = at?(:ident) ? adv().val : "_"
          els.push(RbNode.new(:splat, nm, nil, nil, nil, st.line))
        else
          els.push(parse_pattern())
      pat = RbNode.new(:pat_array, els, nil, nil, nil, pat.line)
    pat

  -> parse_pattern
    p = parse_pattern_atom()
    if at_op?("|")
      alts = [p]
      while at_op?("|")
        adv()
        skip_nl()
        alts.push(parse_pattern_atom())
      p = RbNode.new(:pat_alt, alts, nil, nil, nil, p.line)
    if at?(:arrow)
      adv()
      nm = expect(:ident).val
      p = RbNode.new(:pat_as, p, nm, nil, nil, p.line)
    p

  -> parse_pattern_atom
    t = cur()
    if at_op?("**")
      st = adv()
      rest_nm = "_"
      if at?(:ident)
        rest_nm = adv().val
      elsif at?(:kw_nil)
        adv()
        rest_nm = :nil
      return RbNode.new(:pat_hash, [], rest_nm, nil, nil, st.line)
    if at_op?("*")
      st = adv()
      nm = at?(:ident) ? adv().val : "_"
      return RbNode.new(:pat_array, [RbNode.new(:splat, nm, nil, nil, nil, st.line)], nil, nil, nil, st.line)
    if at_op?("^")
      adv()
      return RbNode.new(:pat_pin, parse_postfix(), nil, nil, nil, t.line)
    if at?(:lbrack)
      adv()
      skip_nl()
      els = []
      while !at?(:eof) && !at?(:rbrack)
        if at_op?("*")
          adv()
          nm = at?(:ident) ? adv().val : "_"
          els.push(RbNode.new(:splat, nm, nil, nil, nil, t.line))
        else
          els.push(parse_pattern())
        skip_nl()
        adv() if at?(:comma)
        skip_nl()
      expect(:rbrack)
      return RbNode.new(:pat_array, els, nil, nil, nil, t.line)
    if at?(:lbrace)
      adv()
      skip_nl()
      pairs = []
      rest_nm = nil
      while !at?(:eof) && !at?(:rbrace)
        if at_op?("**")
          adv()
          if at?(:ident)
            rest_nm = adv().val
          elsif at?(:kw_nil)
            adv()
            rest_nm = :nil
          else
            rest_nm = "_"
        elsif at?(:label)
          lb = adv()
          if at?(:comma) || at?(:rbrace)
            pairs.push([lb.val, RbNode.new(:var, lb.val, nil, nil, nil, lb.line)])
          else
            pairs.push([lb.val, parse_pattern()])
        elsif at?(:string) && peek().type == :colon
          sk = adv()
          adv() # ':'
          pairs.push([sk.val, parse_pattern()])
        else
          break
        skip_nl()
        adv() if at?(:comma)
        skip_nl()
      expect(:rbrace)
      return RbNode.new(:pat_hash, pairs, rest_nm, nil, nil, t.line)
    if at?(:label)
      # Bare hash pattern `in a: 1, b: 2`
      pairs = []
      rest_nm = nil
      while true
        if at_op?("**")
          adv()
          if at?(:ident)
            rest_nm = adv().val
          elsif at?(:kw_nil)
            adv()
            rest_nm = :nil
          else
            rest_nm = "_"
        elsif at?(:label)
          lb = adv()
          if at?(:comma) || at?(:nl) || at?(:semi) || at?(:kw_if) || at?(:kw_unless) || at?(:kw_then) || at?(:kw_end) || at?(:kw_in) || at?(:kw_else) || at?(:eof)
            pairs.push([lb.val, RbNode.new(:var, lb.val, nil, nil, nil, lb.line)])
          else
            pairs.push([lb.val, parse_pattern()])
        else
          break
        if at?(:comma)
          adv()
          skip_nl()
        else
          break
      return RbNode.new(:pat_hash, pairs, rest_nm, nil, nil, t.line)
    if at?(:ident)
      nm = adv().val
      return RbNode.new(:var, nm, nil, nil, nil, t.line)
    parse_range()

  -> parse_while(is_until)
    t = adv()
    prev_nd = @no_do_block
    @no_do_block = true
    cond = parse_expr()
    @no_do_block = prev_nd
    adv() if at?(:kw_do) || at?(:nl) || at?(:semi)
    body = parse_stmts([:kw_end])
    expect(:kw_end)
    RbNode.new(:while, cond, body, is_until, nil, t.line)

  -> parse_for
    t = expect(:kw_for)
    vars = []
    prev_m = @in_multi_lhs
    prev_cs = @in_case_subj
    @in_multi_lhs = true
    @in_case_subj = true
    while true
      if at_op?("*")
        adv()
        if at?(:ident) || at?(:ivar) || at?(:cvar) || at?(:gvar) || at?(:const)
          vars.push(RbNode.new(:splat, parse_postfix(), nil, nil, nil, t.line))
        else
          vars.push(RbNode.new(:splat, nil, nil, nil, nil, t.line))
      else
        vars.push(parse_mlhs_item())
      if at?(:comma)
        adv()
        break if at?(:kw_in)
      else
        break
    @in_multi_lhs = prev_m
    @in_case_subj = prev_cs
    expect(:kw_in)
    prev_nd = @no_do_block
    @no_do_block = true
    iter = parse_expr()
    @no_do_block = prev_nd
    adv() if at?(:kw_do) || at?(:nl) || at?(:semi)
    body = parse_stmts([:kw_end])
    expect(:kw_end)
    RbNode.new(:for, vars, iter, body, nil, t.line)

  -> parse_rescue_clauses(stop_tok)
    rescues = []
    while at?(:kw_rescue)
      adv()
      klasses = []
      var_nm = nil
      if !at?(:nl) && !at?(:semi) && !at?(:arrow) && !at?(:kw_then)
        while true
          if at_op?("*")
            st = adv()
            klasses.push(RbNode.new(:splat, parse_postfix(), nil, nil, nil, st.line))
          else
            klasses.push(parse_postfix())
          if at?(:comma)
            adv()
            skip_nl()
          else
            break
      if at?(:arrow)
        adv()
        if (at?(:ident) || at?(:ivar) || at?(:cvar) || at?(:gvar)) && peek().type != :dot && peek().type != :safe_dot && peek().type != :lbrack
          var_nm = adv().val
        else
          vn = parse_postfix()
          var_nm = vn.kind == :var ? vn.a : "_"
      adv() if at?(:kw_then) || at?(:nl) || at?(:semi)
      rbody = parse_stmts([:kw_rescue, :kw_else, :kw_ensure, stop_tok])
      rescues.push([klasses, var_nm, rbody])
    else_b = nil
    if at?(:kw_else)
      adv()
      else_b = parse_stmts([:kw_ensure, stop_tok])
    ensure_b = nil
    if at?(:kw_ensure)
      adv()
      ensure_b = parse_stmts([stop_tok])
    [rescues, else_b, ensure_b]

  -> parse_body_with_rescue(line, stop_tok)
    body = parse_stmts([:kw_rescue, :kw_else, :kw_ensure, stop_tok])
    if at?(:kw_rescue) || at?(:kw_else) || at?(:kw_ensure)
      rc = parse_rescue_clauses(stop_tok)
      return [RbNode.new(:begin, body, rc[0], rc[1], rc[2], line)]
    body

  -> parse_begin
    t = expect(:kw_begin)
    body = parse_stmts([:kw_rescue, :kw_else, :kw_ensure, :kw_end])
    rc = parse_rescue_clauses(:kw_end)
    expect(:kw_end)
    RbNode.new(:begin, body, rc[0], rc[1], rc[2], t.line)

  -> parse_def_params_until(stop_tok)
    params = []
    prev_arg = @in_arg_list
    @in_arg_list = true
    skip_nl()
    while !at?(:eof) && !at?(stop_tok) && !at?(:nl) && !at?(:semi) && !at?(:assign) && !at?(:kw_do)
      if at?(:dot3)
        adv()
        params.push([:forward, "...", nil])
      elsif at_op?("**")
        adv()
        nm = "**"
        if at?(:ident)
          nm = adv().val
        elsif at?(:kw_nil)
          adv()
          nm = :nil
        params.push([:kw_splat, nm, nil])
      elsif at_op?("*")
        adv()
        nm = at?(:ident) ? adv().val : "*"
        params.push([:splat, nm, nil])
      elsif at_op?("&")
        adv()
        nm = at?(:ident) ? adv().val : "&"
        params.push([:block, nm, nil])
      elsif at?(:lparen)
        # Destructuring method param `def f((a, b), &blk)`
        adv()
        sub = []
        depth = 1
        while !at?(:eof) && depth > 0
          if at?(:lparen)
            depth += 1
            adv()
          elsif at?(:rparen)
            depth -= 1
            adv() if depth > 0
          elsif at?(:ident)
            sub.push(adv().val)
          else
            adv()
        expect(:rparen)
        params.push([:destruct, sub, nil])
      elsif at?(:label)
        lb = adv()
        dflt = (!at?(:comma) && !at?(stop_tok) && !at?(:nl) && !at?(:semi) && !at?(:kw_do)) ? parse_assign() : :req_kw
        params.push([dflt == :req_kw ? :kw_req : :kw_opt, lb.val, dflt == :req_kw ? nil : dflt])
      elsif at?(:ident)
        nm = adv().val
        if at?(:assign) && cur().val == "="
          adv()
          params.push([:opt, nm, parse_assign()])
        else
          params.push([:req, nm, nil])
      else
        break
      skip_nl() if stop_tok == :rparen
      if at?(:comma)
        adv()
        skip_nl()
      else
        break
    @in_arg_list = prev_arg
    params

  -> parse_def
    t = expect(:kw_def)
    recv = nil
    mname = nil
    # Check singleton method `def self.foo`, `def @obj.foo`, `def (expr).foo`, `def A::foo`
    if at?(:lparen)
      save = @i
      adv()
      re = parse_expr()
      if at?(:rparen)
        adv()
        if at?(:dot) || at?(:colon2)
          adv()
          recv = re
        else
          @i = save
      else
        @i = save
    elsif (at?(:kw_self) || at?(:ident) || at?(:const) || at?(:ivar) || at?(:cvar) || at?(:gvar) || at?(:kw_nil) || at?(:kw_true) || at?(:kw_false)) && (peek().type == :dot || peek().type == :colon2)
      rt = adv()
      adv() # '.' or '::'
      if rt.type == :kw_self
        recv = RbNode.new(:self, nil, nil, nil, nil, rt.line)
      elsif rt.type == :kw_nil
        recv = RbNode.new(:nil, nil, nil, nil, nil, rt.line)
      elsif rt.type == :kw_true
        recv = RbNode.new(:bool, true, nil, nil, nil, rt.line)
      elsif rt.type == :kw_false
        recv = RbNode.new(:bool, false, nil, nil, nil, rt.line)
      elsif rt.type == :const
        recv = RbNode.new(:const_ref, rt.val, nil, nil, nil, rt.line)
      elsif rt.type == :ivar
        recv = RbNode.new(:ivar, rt.val, nil, nil, nil, rt.line)
      elsif rt.type == :cvar
        recv = RbNode.new(:cvar, rt.val, nil, nil, nil, rt.line)
      elsif rt.type == :gvar
        recv = RbNode.new(:gvar, rt.val, nil, nil, nil, rt.line)
      else
        recv = RbNode.new(:var, rt.val, nil, nil, nil, rt.line)
    nt = adv()
    mname = nt.val.to_s
    # Handle operator defs like `def []`, `def []=`, `def -@`, `def +@`, `def ~@`, `def !@`, `def foo=`
    if mname == '[' && at?(:rbrack)
      adv()
      mname = '[]'
    if (mname == "-" || mname == "+" || mname == "~" || mname == "!") && at?(:ivar) && cur().val == "@"
      adv()
      mname = mname + "@"
    elsif at?(:assign) && cur().val == "=" && !space_before?() && (mname == '[]' || nt.type == :ident || nt.type == :const || (@is_stream && @toks.id_at(@i - 1) >= 50))
      adv()
      mname = mname + "="
    params = []
    if at?(:lparen)
      adv()
      params = parse_def_params_until(:rparen)
      expect(:rparen)
    elsif !at?(:nl) && !at?(:semi) && !at?(:assign) && !at?(:kw_end)
      params = parse_def_params_until(:nl)
    # Ruby 3.0-4.0 endless method definition `def add(a, b) = a + b`
    if at?(:assign) && cur().val == "="
      adv()
      skip_nl()
      body = [parse_stmt()]
      return RbNode.new(:method_def, mname, params, body, recv, t.line)
    skip_seps()
    body = parse_body_with_rescue(t.line, :kw_end)
    expect(:kw_end)
    RbNode.new(:method_def, mname, params, body, recv, t.line)

  -> parse_class
    t = expect(:kw_class)
    if at_op?("<<")
      adv()
      target = parse_expr()
      skip_seps()
      body = parse_body_with_rescue(t.line, :kw_end)
      expect(:kw_end)
      return RbNode.new(:singleton_class, target, body, nil, nil, t.line)
    cname = parse_const_name()
    super_e = nil
    if at_op?("<")
      adv()
      super_e = parse_expr()
    skip_seps()
    body = parse_body_with_rescue(t.line, :kw_end)
    expect(:kw_end)
    RbNode.new(:class_def, cname, super_e, body, nil, t.line)

  -> parse_module
    t = expect(:kw_module)
    mname = parse_const_name()
    skip_seps()
    body = parse_body_with_rescue(t.line, :kw_end)
    expect(:kw_end)
    RbNode.new(:module_def, mname, body, nil, nil, t.line)

  -> parse_const_name
    parts = []
    if at?(:colon2)
      adv()
      parts.push("")
    elsif (at?(:ident) || at?(:ivar) || at?(:kw_self) || at?(:kw_nil)) && peek().type == :colon2
      # Dynamic namespace `class parent::C` / `module m::N` / `class nil::Foo`
      parts.push(adv().val.to_s)
      adv()
    parts.push(expect(:const).val)
    while at?(:colon2)
      adv()
      parts.push(expect(:const).val)
    parts.join("::")

-> rb_parse(source, filename = "(eval)")
  lex = RbLexer.new(source)
  toks = lex.tokenize()
  RbParser.new(toks, lex.frozen_strings, filename, lex.end_data).parse_program()
