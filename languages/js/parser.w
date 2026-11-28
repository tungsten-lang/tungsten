# blade/js/parser — ECMAScript 2024 parser producing a JsNode AST.
#
#   p = JsParser.new(source, false)      # true for a module
#   prog = p.parse_program()             # raises on a syntax error; p.error
#                                        # then holds a JsSyntaxError (msg, pos,
#                                        # line, col)
#
# Recursive descent for statements, precedence climbing for binary operators,
# and a cover grammar (parse as an expression, then reinterpret) for arrow
# parameters and destructuring assignment, so nothing is parsed twice.
#
# ---- AST ----
#
# Every node is a JsNode: kind (Symbol), pos / fin (byte offsets of the first
# byte and one past the last), str, a, b, c, d, list, flags. A slot holds a
# JsNode, nil, an Array of JsNode, or a scalar (String / Float) as listed:
#
# Program and statements
#   :program        list=body; flags F_MODULE, F_STRICT
#   :expr_stmt      a=expression; str=directive text ("use strict") for directives
#   :var_decl       str="var"/"let"/"const"; list=:declarator
#   :declarator     a=target pattern; b=init or nil
#   :function_decl  like :function (below)
#   :class_decl     like :class (below)
#   :block          list=statements
#   :empty
#   :if             a=test; b=consequent; c=alternate or nil
#   :for            a=init (:var_decl / expression / nil); b=test; c=update; d=body
#   :for_in         a=left (:var_decl with one declarator, or a pattern); b=right; d=body
#   :for_of         same as :for_in; flags F_AWAIT for `for await`
#   :while          a=test; b=body
#   :do_while       a=body; b=test
#   :return         a=argument or nil
#   :break          str=label or nil
#   :continue       str=label or nil
#   :throw          a=argument
#   :try            a=block; b=catch parameter pattern or nil; c=catch body
#                   (:block) or nil when there is no catch; d=finally :block or nil
#   :switch         a=discriminant; list=:case
#   :case           a=test (nil for default); list=consequent statements
#   :labeled        str=label; a=body
#   :debugger
#   :with           a=object; b=body
#   :import_decl    str=source; list=:import_spec; b=attributes :object or nil
#   :import_spec    str=local name; a=imported name ("default", "*" for a namespace)
#   :export_named   a=declaration or nil; list=:export_spec; b=source string or nil
#   :export_spec    str=local name; a=exported name
#   :export_default a=expression or :function_decl / :class_decl
#   :export_all     str=source; a=exported name or nil (export * as ns)
#
# Expressions
#   :ident          str=name
#   :num            a=value (Float)
#   :bigint         str=digits (may keep a 0x / 0o / 0b prefix)
#   :string         str=cooked value (UTF-8; lone surrogates as WTF-8)
#   :template       list=:quasi; a=Array of expressions (one fewer than quasis)
#   :quasi          str=cooked value (nil if invalid, tagged only); a=raw String
#   :tagged_template a=tag; b=:template
#   :regex          str=pattern; a=flags String
#   :null :true :false :this :super
#   :array          list=elements (nil for a hole, :spread)
#   :object         list=:prop / :spread
#   :prop           a=key; b=value; str="init"/"get"/"set";
#                   flags F_COMPUTED, F_SHORTHAND, F_METHOD (value is a :function)
#   :function       str=name or nil; list=params (patterns); b=body (Array of
#                   statements); flags F_ASYNC, F_GENERATOR, F_STRICT, F_METHOD,
#                   F_USES_ARGS, F_HAS_EVAL
#   :arrow          list=params; b=body (Array of statements, or an expression
#                   when F_EXPR_BODY); flags F_ASYNC, F_EXPR_BODY, F_STRICT
#   :class          str=name or nil; a=superclass or nil; list=members
#   :method_def     a=key; b=:function; str="method"/"get"/"set"/"constructor";
#                   flags F_STATIC, F_COMPUTED
#   :field_def      a=key; b=initializer or nil; flags F_STATIC, F_COMPUTED
#   :static_block   list=statements
#   :private_name   str=name without '#' (member property, class key, `#x in o`)
#   :unary          str=operator ("!", "-", "+", "~", "typeof", "void", "delete"); a=argument
#   :update         str="++"/"--"; a=argument; flags F_PREFIX
#   :binary         str=operator; a=left; b=right (arithmetic, bitwise, comparison, in, instanceof)
#   :logical        str="&&"/"||"/"??"; a=left; b=right
#   :assign         str=operator ("=", "+=", ... "??="); a=target; b=value
#   :cond           a=test; b=consequent; c=alternate
#   :call           a=callee; list=arguments (:spread allowed); flags F_OPTIONAL
#                   (the `?.(` link of an optional chain)
#   :new            a=callee; list=arguments
#   :member         a=object; b=property (:ident / :private_name when not
#                   computed, any expression when F_COMPUTED); flags F_OPTIONAL
#   :chain          a=expression containing F_OPTIONAL links: the extent an
#                   optional chain short-circuits
#   :seq            list=expressions
#   :spread         a=argument
#   :yield          a=argument or nil; flags F_DELEGATE (yield*)
#   :await          a=argument
#   :meta_property  str="new.target" or "import.meta"
#   :import_call    a=specifier; b=options or nil
#
# Patterns (binding and assignment targets)
#   :ident, :member (assignment only)
#   :array_pattern  list=elements (nil for a hole, :rest)
#   :object_pattern list=:prop (b = value pattern) / :rest
#   :assign_pattern a=target; b=default value
#   :rest           a=target
#
# Any expression can carry F_PAREN when it was written in parentheses.

use lexer

F_ASYNC = 1
F_GENERATOR = 2
F_EXPR_BODY = 4
F_STRICT = 8
F_COMPUTED = 16
F_SHORTHAND = 32
F_STATIC = 64
F_OPTIONAL = 128
F_PREFIX = 256
F_DELEGATE = 512
F_AWAIT = 1024
F_METHOD = 2048
F_MODULE = 4096
F_USES_ARGS = 8192
F_HAS_EVAL = 16384
F_PAREN = 32768
F_REST_TRAIL = 65536
F_TAIL = 131072

# parser context bits
C_FUNC = 1
C_ASYNC = 2
C_GEN = 4
C_STRICT = 8
C_NOIN = 16
C_STATIC_BLOCK = 32
C_FIELD_INIT = 64
C_PARAMS = 128
C_NOIN_MASK = 239

STRICT_RESERVED = {"implements" => true, "interface" => true, "let" => true, "package" => true, "private" => true, "protected" => true, "public" => true, "static" => true, "yield" => true}

-> js_prec_table
  t = []
  i = 0
  while i < T_COUNT
    t.push(0)
    i += 1
  t[T_NULLISH] = 1
  t[T_OROR] = 2
  t[T_ANDAND] = 3
  t[T_BITOR] = 4
  t[T_BITXOR] = 5
  t[T_BITAND] = 6
  t[T_EQ] = 7
  t[T_NE] = 7
  t[T_SEQ] = 7
  t[T_SNE] = 7
  t[T_LT] = 8
  t[T_GT] = 8
  t[T_LE] = 8
  t[T_GE] = 8
  t[T_INSTANCEOF] = 8
  t[T_IN] = 8
  t[T_SHL] = 9
  t[T_SHR] = 9
  t[T_USHR] = 9
  t[T_PLUS] = 10
  t[T_MINUS] = 10
  t[T_STAR] = 11
  t[T_SLASH] = 11
  t[T_PERCENT] = 11
  t[T_STARSTAR] = 12
  t

JS_PREC = js_prec_table()

# x: the analysis's annotation (js-aot analyze.w): the JaFunc of a function, the JaScope
# of a block, the JaRef of an identifier. (The eleventh ivar costs nothing: a JsNode was
# already an 88-byte request in a 96-byte malloc block.)
+ JsNode
  rw :kind, :pos, :fin, :str, :a, :b, :c, :d, :list, :flags, :x, :osr_fp
  -> new(@kind, @pos, @fin, @str, @a, @b, @c, @list, @flags)
    @d = nil
    @x = nil
    @osr_fp = 0

  -> has?(f)
    (@flags & f) != 0

JS_EMPTY_BLOCK = JsNode.new(:block, 0, 0, nil, nil, nil, nil, [], 0)

# A function body the parser skipped (lazy parsing): its '{' offset, the offset past its
# '}', and the parser context to resume in. Kept in the function node's c slot until
# js_lazy_parse_body fills in b on the first call.
+ JsLazyBody
  rw :pos, :fin, :ctx, :module
  -> new(@pos, @fin, @ctx, @module)

+ JsParser < JsLexer
  rw :count, :lazy, :lazy_flags, :ctx

  -> new(src, mod)
    super(src)
    @module = mod
    @ctx = mod ? C_STRICT : 0
    @count = 0
    @fn_acc = 0
    @fn_depth = 0
    @block_depth = 0
    @in_case = false
    @loop_depth = 0
    @switch_depth = 0
    @labels = []
    @lazy = false
    @lazy_flags = 0
    @skip_args = false

  # Lazy parsing: at a body's '{', skip to its '}' and leave the token after it current.
  # Returns the JsLazyBody, or nil when the skipper is unsure (parse the body normally).
  -> try_skip_body
    e = skip_body(@tstart)
    return nil if e < 0
    lz = JsLazyBody.new(@tstart, e, @ctx, @module)
    @sp -= 1 if @sp > 0
    @tt = T_RBRACE
    @tstart = e - 1
    @tend = e
    @pos = e
    next_token()
    lz

  # Is the function starting at s probably invoked immediately: `(function`, `!function`,
  # `(() =>` (V8's PIFE heuristic)? Those are parsed eagerly, since they run at once.
  -> pife?(s)
    i = s - 1
    while i >= 0
      b = @src.byte_at(i)
      if b != 32 && b != 10 && b != 9 && b != 13
        return (b == 40 || b == 33)
      i -= 1
    false

  # The body of a skipped function, parsed on its first call.
  -> parse_lazy_body(lz)
    @ctx = lz.ctx
    @fn_depth = 1
    @fn_acc = 0
    @pos = lz.pos
    @tt = -1
    next_token()
    body = parse_function_body()
    fail("Internal error: lazy function body ends at " + @prev_end.to_s + ", expected " + lz.fin.to_s, lz.pos) if @prev_end != lz.fin
    @lazy_flags = (strict?() ? F_STRICT : 0) | (@fn_acc & (F_USES_ARGS | F_HAS_EVAL))
    body

  # ---- helpers ----

  -> mk(kind, pos, str, a, b, c, list, flags)
    @count += 1
    JsNode.new(kind, pos, @prev_end, str, a, b, c, list, flags)

  -> expect(t)
    unexpected() if @tt != t
    next_token()

  -> semicolon
    if @tt == T_SEMI
      next_token()
      return nil
    return nil if @tt == T_RBRACE || @tt == T_EOF || @nl
    unexpected()

  -> name_is?(s)
    @tt == T_NAME && @value == s && !@escaped

  -> expect_name(s)
    unexpected() if !name_is?(s)
    next_token()

  -> strict?
    (@ctx & C_STRICT) != 0

  # Does the current token start an IdentifierName (identifiers and reserved words)?
  -> ident_name?
    @tt == T_NAME || (@tt >= T_BREAK && @tt <= T_KW_LAST)

  -> check_ident(name, s, is_binding, force_strict = false)
    fail("Unexpected token '" + name + "'", s) if JS_KEYWORDS.has_key?(name)
    st = force_strict || strict?()
    fail("Unexpected strict mode reserved word '" + name + "'", s) if st && STRICT_RESERVED.has_key?(name)
    fail("Unexpected eval or arguments in strict mode", s) if is_binding && st && (name == "eval" || name == "arguments")
    fail("Unexpected token 'yield'", s) if (@ctx & C_GEN) != 0 && name == "yield"
    fail("Unexpected token 'await'", s) if ((@ctx & C_ASYNC) != 0 || (@ctx & C_STATIC_BLOCK) != 0 || @module) && name == "await"
    nil

  -> check_pattern_idents(p, is_binding, force_strict = false, no_let = false)
    return nil if p == nil
    k = p.kind
    if k == :ident
      check_ident(p.str, p.pos, is_binding, force_strict)
      fail("let is disallowed as a lexically bound name", p.pos) if no_let && p.str == "let"
    elsif k == :assign_pattern || k == :rest
      check_pattern_idents(p.a, is_binding, force_strict, no_let)
    elsif k == :array_pattern
      p.list.each ->(el) check_pattern_idents(el, is_binding, force_strict, no_let) if el != nil
    elsif k == :object_pattern
      p.list.each ->(pr) check_pattern_idents(pr.kind == :rest ? pr.a : pr.b, is_binding, force_strict, no_let)
    nil

  -> collect_pat_names(p, out)
    return out if p == nil
    k = p.kind
    if k == :ident
      out.push([p.str, p.pos])
    elsif k == :assign_pattern || k == :rest
      collect_pat_names(p.a, out)
    elsif k == :array_pattern
      p.list.each ->(el) collect_pat_names(el, out) if el != nil
    elsif k == :object_pattern
      p.list.each ->(pr) collect_pat_names(pr.kind == :rest ? pr.a : pr.b, out)
    out

  -> params_simple?(params)
    i = 0
    while i < params.size
      return false if params[i].kind != :ident
      i += 1
    true

  -> check_dup_params(params)
    seen = {}
    names = []
    params.each ->(p) collect_pat_names(p, names)
    names.each ->(pr)
      fail("Duplicate parameter name '" + pr[0] + "' not allowed in this context", pr[1]) if seen.has_key?(pr[0])
      seen[pr[0]] = true
    nil

  -> is_labelled_fn?(stmt)
    return false if stmt == nil || stmt.kind != :labeled
    cur = stmt
    while cur != nil && cur.kind == :labeled
      cur = cur.a
    cur != nil && cur.kind == :function_decl

  -> node_has_await_in_async_params?(n)
    return false if n == nil
    k = n.kind
    return true if k == :await
    return true if k == :ident && n.str == "await"
    return false if k == :function
    if k == :arrow
      if n.list.is_a?(Array)
        i = 0
        while i < n.list.size
          return true if n.list[i].is_a?(JsNode) && node_has_await_in_async_params?(n.list[i])
          i += 1
      return false
    if k == :prop && (n.flags & F_COMPUTED) == 0
      return n.b.is_a?(JsNode) && node_has_await_in_async_params?(n.b)
    if k == :member && (n.flags & F_COMPUTED) == 0
      return n.a.is_a?(JsNode) && node_has_await_in_async_params?(n.a)
    if k == :class
      return true if n.a.is_a?(JsNode) && node_has_await_in_async_params?(n.a)
      if n.b.is_a?(Array)
        i = 0
        while i < n.b.size
          return true if n.b[i].is_a?(JsNode) && node_has_await_in_async_params?(n.b[i])
          i += 1
      if n.list.is_a?(Array)
        i = 0
        while i < n.list.size
          m = n.list[i]
          return true if m.is_a?(JsNode) && (m.flags & F_COMPUTED) != 0 && m.a.is_a?(JsNode) && node_has_await_in_async_params?(m.a)
          if m.is_a?(JsNode) && m.c.is_a?(Array)
            j = 0
            while j < m.c.size
              return true if m.c[j].is_a?(JsNode) && node_has_await_in_async_params?(m.c[j])
              j += 1
          i += 1
      return false
    return true if n.a.is_a?(JsNode) && node_has_await_in_async_params?(n.a)
    return true if n.b.is_a?(JsNode) && node_has_await_in_async_params?(n.b)
    return true if n.c.is_a?(JsNode) && node_has_await_in_async_params?(n.c)
    return true if n.d.is_a?(JsNode) && node_has_await_in_async_params?(n.d)
    if n.list.is_a?(Array)
      i = 0
      while i < n.list.size
        return true if n.list[i].is_a?(JsNode) && node_has_await_in_async_params?(n.list[i])
        i += 1
    if n.a.is_a?(Array)
      i = 0
      while i < n.a.size
        return true if n.a[i].is_a?(JsNode) && node_has_await_in_async_params?(n.a[i])
        i += 1
    false

  -> node_has_kind?(n, target_k)
    return false if n == nil
    k = n.kind
    return true if k == target_k
    return false if k == :function || k == :arrow
    return true if n.a.is_a?(JsNode) && node_has_kind?(n.a, target_k)
    return true if n.b.is_a?(JsNode) && node_has_kind?(n.b, target_k)
    return true if n.c.is_a?(JsNode) && node_has_kind?(n.c, target_k)
    return true if n.d.is_a?(JsNode) && node_has_kind?(n.d, target_k)
    if n.list.is_a?(Array)
      i = 0
      while i < n.list.size
        return true if n.list[i].is_a?(JsNode) && node_has_kind?(n.list[i], target_k)
        i += 1
    if n.a.is_a?(Array)
      i = 0
      while i < n.a.size
        return true if n.a[i].is_a?(JsNode) && node_has_kind?(n.a[i], target_k)
        i += 1
    false

  -> binding_ident
    unexpected() if @tt != T_NAME
    s = @tstart
    v = @value
    check_ident(v, s, true)
    next_token()
    mk(:ident, s, v, nil, nil, nil, nil, 0)

  # ---- program ----

  -> parse_program
    next_token()
    body = []
    @ctx = @ctx | C_STRICT if parse_directives(body)
    while @tt != T_EOF
      st = parse_item()
      body.push(st) if st != JS_EMPTY_BLOCK
    flags = 0
    flags = flags | F_MODULE if @module
    flags = flags | F_STRICT if strict?()
    flags = flags | (@fn_acc & (F_USES_ARGS | F_HAS_EVAL))
    mk(:program, 0, nil, nil, nil, nil, body, flags)

  # Leading string-literal statements; returns true for "use strict".
  -> parse_directives(body)
    strict = false
    octal_dir = false
    while @tt == T_STRING
      s = @tstart
      was_oct = @legacy_octal
      raw = @src.slice(@tstart + 1, @tend - @tstart - 2)
      st = parse_statement()
      body.push(st)
      if st.kind == :expr_stmt && st.a.kind == :string && st.a.pos == s && (st.a.flags & F_PAREN) == 0
        st.str = raw
        octal_dir = true if was_oct
        if raw == "use strict"
          fail("Octal escape sequences are not allowed in strict mode", s) if octal_dir
          strict = true
          @ctx = @ctx | C_STRICT
      else
        return strict
    strict

  # StatementListItem / ModuleItem
  -> parse_item
    tt = @tt
    if @module && @fn_depth == 0
      if tt == T_AT
        s = @tstart
        decs = parse_decorators()
        return parse_export_decl(decs) if @tt == T_EXPORT
        unexpected() if @tt != T_CLASS
        return parse_class(s, true, decs)
      if tt == T_IMPORT
        pk = peek()
        return parse_import_decl() if pk != T_LPAREN && pk != T_DOT
      return parse_export_decl() if tt == T_EXPORT
    parse_statement()

  # Lookahead helpers for `using` and `await using` declarations.
  -> using_decl_ahead?(in_for)
    return false if !name_is?("using")
    pk = peek()
    return false if peek_nl() || pk != T_NAME
    if in_for && peek_value() == "of"
      # `for (using of ...)` is identifier `using` in for-of UNLESS `for (using of = ...)`!
      sp = @pos
      stt = @tt
      sts = @tstart
      ste = @tend
      sv = @value
      sr = @raw
      snl = @nl
      ses = @escaped
      spe = @prev_end
      slo = @legacy_octal
      ssp = @sp
      next_token()
      is_eq = !@escaped && peek() == T_ASSIGN
      @pos = sp
      @tt = stt
      @tstart = sts
      @tend = ste
      @value = sv
      @raw = sr
      @nl = snl
      @escaped = ses
      @prev_end = spe
      @legacy_octal = slo
      @sp = ssp
      return is_eq
    true

  -> await_using_decl_ahead?
    return false if !name_is?("await")
    return false if !((@ctx & C_ASYNC) != 0 || (@module && @fn_depth == 0))
    return false if peek_nl() || peek() != T_NAME || peek_value() != "using"
    sp = @pos
    stt = @tt
    sts = @tstart
    ste = @tend
    sv = @value
    sr = @raw
    snl = @nl
    ses = @escaped
    spe = @prev_end
    slo = @legacy_octal
    ssp = @sp
    next_token()
    ok = false
    if !@nl && name_is?("using")
      pk2 = peek()
      ok = !peek_nl() && pk2 == T_NAME
    @pos = sp
    @tt = stt
    @tstart = sts
    @tend = ste
    @value = sv
    @raw = sr
    @nl = snl
    @escaped = ses
    @prev_end = spe
    @legacy_octal = slo
    @sp = ssp
    ok

  # ---- statements ----

  -> parse_single_statement(allow_sloppy_fn = false)
    tt = @tt
    s = @tstart
    if tt == T_CONST || tt == T_CLASS || tt == T_AT
      fail("Lexical declaration cannot appear in a single-statement context", s)
    if tt == T_FUNCTION
      if !allow_sloppy_fn || strict?() || peek() == T_STAR
        fail("Function declaration cannot appear in a single-statement context", s)
    if tt == T_NAME && !@escaped
      if @value == "async" && peek() == T_FUNCTION && !peek_nl()
        fail("Async function declaration cannot appear in a single-statement context", s)
      if @value == "let"
        pk = peek()
        if pk == T_LBRACK || (!peek_nl() && (pk == T_NAME || pk == T_LBRACE))
          fail("Lexical declaration cannot appear in a single-statement context", s)
      if using_decl_ahead?(false) || await_using_decl_ahead?()
        fail("Lexical declaration cannot appear in a single-statement context", s)
    parse_statement()

  -> parse_statement
    tt = @tt
    s = @tstart
    case tt
    when T_LBRACE
      return parse_block()
    when T_VAR, T_CONST
      kind = @value
      next_token()
      d = parse_var(kind, s, kind == "const")
      semicolon()
      d.fin = @prev_end
      return d
    when T_SEMI
      next_token()
      return mk(:empty, s, nil, nil, nil, nil, nil, 0)
    when T_IF
      return parse_if()
    when T_FOR
      return parse_for()
    when T_WHILE
      next_token()
      expect(T_LPAREN)
      test = parse_expression()
      expect(T_RPAREN)
      @loop_depth += 1
      body = parse_single_statement(false)
      @loop_depth -= 1
      fail("Functions cannot be declared in this context", body.pos) if is_labelled_fn?(body)
      return mk(:while, s, nil, test, body, nil, nil, 0)
    when T_DO
      next_token()
      @loop_depth += 1
      body = parse_single_statement(false)
      @loop_depth -= 1
      fail("Functions cannot be declared in this context", body.pos) if is_labelled_fn?(body)
      expect(T_WHILE)
      expect(T_LPAREN)
      test = parse_expression()
      expect(T_RPAREN)
      next_token() if @tt == T_SEMI
      return mk(:do_while, s, nil, body, test, nil, nil, 0)
    when T_RETURN
      fail("Illegal return statement", s) if @fn_depth == 0
      next_token()
      arg = nil
      if @tt != T_SEMI && @tt != T_RBRACE && @tt != T_EOF && !@nl
        arg = parse_expression()
      semicolon()
      return mk(:return, s, nil, arg, nil, nil, nil, 0)
    when T_BREAK, T_CONTINUE
      next_token()
      label = nil
      if @tt == T_NAME && !@nl
        label = @value
        check_ident(label, @tstart, false)
        next_token()
      if label == nil
        if tt == T_BREAK
          fail("Illegal break statement", s) if @loop_depth == 0 && @switch_depth == 0
        else
          fail("Illegal continue statement", s) if @loop_depth == 0
      else
        found_lbl = nil
        li = @labels.size - 1
        while li >= 0
          if @labels[li][0] == label
            found_lbl = @labels[li]
            break
          li -= 1
        fail("Undefined label '" + label + "'", s) if found_lbl == nil
        fail("Illegal continue statement: '" + label + "' does not denote an iteration statement", s) if tt == T_CONTINUE && !found_lbl[1]
      semicolon()
      return mk(tt == T_BREAK ? :break : :continue, s, label, nil, nil, nil, nil, 0)
    when T_THROW
      next_token()
      fail("Illegal newline after throw", @tstart) if @nl
      arg = parse_expression()
      semicolon()
      return mk(:throw, s, nil, arg, nil, nil, nil, 0)
    when T_TRY
      return parse_try()
    when T_SWITCH
      return parse_switch()
    when T_FUNCTION
      return parse_function(s, true, 0)
    when T_CLASS
      return parse_class(s, true)
    when T_AT
      decs = parse_decorators()
      unexpected() if @tt != T_CLASS
      return parse_class(s, true, decs)
    when T_DEBUGGER
      next_token()
      semicolon()
      return mk(:debugger, s, nil, nil, nil, nil, nil, 0)
    when T_WITH
      fail("Strict mode code may not include a with statement", s) if strict?()
      next_token()
      expect(T_LPAREN)
      obj = parse_expression()
      expect(T_RPAREN)
      body = parse_single_statement(false)
      fail("Functions cannot be declared in this context", body.pos) if is_labelled_fn?(body)
      return mk(:with, s, nil, obj, body, nil, nil, 0)
    when T_NAME
      if !@escaped
        v = @value
        if v == "let"
          pk = peek()
          if pk == T_NAME || pk == T_LBRACK || pk == T_LBRACE || (pk >= T_BREAK && pk <= T_KW_LAST && pk != T_IN && pk != T_INSTANCEOF)
            next_token()
            d = parse_var("let", s, false)
            semicolon()
            d.fin = @prev_end
            return d
        elsif v == "async"
          if peek() == T_FUNCTION && !peek_nl()
            next_token()
            return parse_function(s, true, F_ASYNC)
        elsif using_decl_ahead?(false)
          fail("'using' declaration is not allowed at the top level of a script", s) if !@module && @fn_depth == 0 && @block_depth == 0 && (@ctx & C_STATIC_BLOCK) == 0
          fail("'using' declaration is not allowed directly in a switch case", s) if @in_case
          next_token()
          d = parse_var("using", s, true)
          semicolon()
          d.fin = @prev_end
          return d
        elsif await_using_decl_ahead?()
          fail("'await using' declaration is not allowed at the top level of a script", s) if !@module && @fn_depth == 0 && @block_depth == 0 && (@ctx & C_STATIC_BLOCK) == 0
          fail("'await using' declaration is not allowed directly in a switch case", s) if @in_case
          next_token()
          next_token()
          d = parse_var("await using", s, true)
          semicolon()
          d.fin = @prev_end
          return d
    # expression statement or labelled statement
    e = parse_expression()
    if e.kind == :ident && @tt == T_COLON && (e.flags & F_PAREN) == 0
      @labels.each ->(lb) fail("Label '" + e.str + "' has already been declared", s) if lb[0] == e.str
      next_token()
      is_iter = @tt == T_FOR || @tt == T_WHILE || @tt == T_DO
      if !is_iter && @tt == T_NAME && peek() == T_COLON
        # nested label: will check when inner label sees loop
        is_iter = true
      @labels.push([e.str, is_iter])
      body = parse_single_statement(!strict?())
      @labels.pop
      return mk(:labeled, s, e.str, body, nil, nil, nil, 0)
    semicolon()
    mk(:expr_stmt, s, nil, e, nil, nil, nil, 0)

  -> parse_block
    s = @tstart
    expect(T_LBRACE)
    if @tt == T_RBRACE
      next_token()
      return JS_EMPTY_BLOCK
    save_ic = @in_case
    @in_case = false
    @block_depth += 1
    body = []
    while @tt != T_RBRACE
      unexpected() if @tt == T_EOF
      st = parse_statement()
      body.push(st) if st != JS_EMPTY_BLOCK
    @block_depth -= 1
    @in_case = save_ic
    next_token()
    mk(:block, s, nil, nil, nil, nil, body, 0)

  # After var/let/const/using/await using: declarators (no semicolon handling).
  -> parse_var(kind, s, require_init = false)
    decls = []
    is_using = kind == "using" || kind == "await using"
    no_let = kind == "let" || kind == "const" || is_using
    while true
      ds = @tstart
      target = is_using ? binding_ident() : parse_binding_target()
      check_pattern_idents(target, true, false, no_let) if no_let
      init = nil
      if @tt == T_ASSIGN
        next_token()
        init = parse_assign()
      elsif require_init || (target.kind != :ident && require_init)
        fail("Missing initializer in " + kind + " declaration", ds)
      decls.push(mk(:declarator, ds, nil, target, init, nil, nil, 0))
      break if @tt != T_COMMA
      next_token()
    mk(:var_decl, s, kind, nil, nil, nil, decls, 0)

  -> parse_if
    s = @tstart
    next_token()
    expect(T_LPAREN)
    test = parse_expression()
    expect(T_RPAREN)
    cons = parse_single_statement(!strict?())
    fail("Functions cannot be declared in this context", cons.pos) if is_labelled_fn?(cons)
    cons = mk(:block, cons.pos, nil, nil, nil, nil, [cons], 0) if cons.kind == :function_decl
    alt = nil
    if @tt == T_ELSE
      next_token()
      alt = parse_single_statement(!strict?())
      fail("Functions cannot be declared in this context", alt.pos) if is_labelled_fn?(alt)
      alt = mk(:block, alt.pos, nil, nil, nil, nil, [alt], 0) if alt.kind == :function_decl
    mk(:if, s, nil, test, cons, alt, nil, 0)

  -> parse_for
    s = @tstart
    next_token()
    is_await = false
    if name_is?("await") && ((@ctx & C_ASYNC) != 0 || (@module && @fn_depth == 0))
      is_await = true
      next_token()
    expect(T_LPAREN)
    init = nil
    if @tt != T_SEMI
      save = @ctx
      @ctx = @ctx | C_NOIN
      is_decl = @tt == T_VAR || @tt == T_CONST
      is_using_for = false
      is_await_using_for = false
      if !is_decl && name_is?("let")
        pk = peek()
        is_decl = pk == T_NAME || pk == T_LBRACK || pk == T_LBRACE
      if !is_decl && using_decl_ahead?(true)
        is_using_for = true
      elsif !is_decl && await_using_decl_ahead?()
        is_await_using_for = true
      init_async_unesc = false
      if is_decl
        ds = @tstart
        kind = @value
        next_token()
        init = parse_var(kind, ds, false)
      elsif is_using_for
        ds = @tstart
        next_token()
        init = parse_var("using", ds, false)
      elsif is_await_using_for
        ds = @tstart
        next_token()
        next_token()
        init = parse_var("await using", ds, false)
      else
        init_async_unesc = !is_await && name_is?("async")
        init = parse_expression()
      @ctx = save
      is_of = name_is?("of")
      if is_of || @tt == T_IN
        fail("Invalid for-await loop", s) if is_await && !is_of
        if !is_of && init.kind == :var_decl && (init.str == "using" || init.str == "await using")
          fail("Invalid left-hand side in for-in loop: '" + init.str + "' declaration is not allowed", init.pos)
        if init.kind != :var_decl
          fail("Invalid left-hand side in for-of loop", init.pos) if is_of && init.kind == :ident && init.str == "let" && (init.flags & F_PAREN) == 0
          fail("Invalid left-hand side in for-of loop", init.pos) if is_of && init_async_unesc && init.kind == :ident && init.str == "async" && (init.flags & F_PAREN) == 0
          fail("Invalid left-hand side in for-" + (is_of ? "of" : "in") + " loop", init.pos) if init.kind == :assign
          if !(!strict?() && init.kind == :call && (init.flags & F_OPTIONAL) == 0)
            init = to_pattern(init, false)
        elsif init.list.size != 1
          fail("Invalid left-hand side in for-" + (is_of ? "of" : "in") + " loop: must have a single binding", init.pos)
        else
          d0 = init.list[0]
          if d0.b != nil
            if is_of || init.str != "var" || strict?() || d0.a.kind != :ident
              fail("Invalid left-hand side in for-" + (is_of ? "of" : "in") + " loop: variable declaration may not have an initializer", d0.pos)
        next_token()
        right = is_of ? parse_assign() : parse_expression()
        expect(T_RPAREN)
        @loop_depth += 1
        body = parse_single_statement(false)
        @loop_depth -= 1
        fail("Functions cannot be declared in this context", body.pos) if is_labelled_fn?(body)
        n = mk(is_of ? :for_of : :for_in, s, nil, init, right, nil, nil, is_await ? F_AWAIT : 0)
        n.d = body
        return n
      fail("Invalid for-await loop", s) if is_await
      if init.kind == :var_decl && (init.str == "const" || init.str == "using" || init.str == "await using")
        init.list.each ->(d) fail("Missing initializer in " + init.str + " declaration", d.pos) if d.b == nil
    else
      fail("Invalid for-await loop", s) if is_await
    expect(T_SEMI)
    test = @tt == T_SEMI ? nil : parse_expression()
    expect(T_SEMI)
    update = @tt == T_RPAREN ? nil : parse_expression()
    expect(T_RPAREN)
    @loop_depth += 1
    body = parse_single_statement(false)
    @loop_depth -= 1
    fail("Functions cannot be declared in this context", body.pos) if is_labelled_fn?(body)
    n = mk(:for, s, nil, init, test, update, nil, 0)
    n.d = body
    n

  -> parse_try
    s = @tstart
    next_token()
    block = parse_block()
    param = nil
    handler = nil
    finalizer = nil
    if @tt == T_CATCH
      next_token()
      if @tt == T_LPAREN
        next_token()
        param = parse_binding_target()
        expect(T_RPAREN)
      handler = parse_block()
    if @tt == T_FINALLY
      next_token()
      finalizer = parse_block()
    fail("Missing catch or finally after try", @tstart) if handler == nil && finalizer == nil
    n = mk(:try, s, nil, block, param, handler, nil, 0)
    n.d = finalizer
    n

  -> parse_switch
    s = @tstart
    next_token()
    expect(T_LPAREN)
    disc = parse_expression()
    expect(T_RPAREN)
    expect(T_LBRACE)
    cases = []
    has_default = false
    @switch_depth += 1
    while @tt != T_RBRACE
      cs = @tstart
      test = nil
      if @tt == T_CASE
        next_token()
        test = parse_expression()
      elsif @tt == T_DEFAULT
        fail("More than one default clause in switch statement", cs) if has_default
        has_default = true
        next_token()
      else
        unexpected()
      expect(T_COLON)
      save_ic = @in_case
      @in_case = true
      cons = []
      while @tt != T_CASE && @tt != T_DEFAULT && @tt != T_RBRACE
        unexpected() if @tt == T_EOF
        cons.push(parse_statement())
      @in_case = save_ic
      cases.push(mk(:case, cs, nil, test, nil, nil, cons, 0))
    @switch_depth -= 1
    next_token()
    mk(:switch, s, nil, disc, nil, nil, cases, 0)

  # ---- modules ----

  # ModuleExportName: an IdentifierName or a string literal.
  -> module_name
    if @tt == T_STRING || ident_name?()
      v = @value
      next_token()
      return v
    unexpected()

  -> parse_attributes
    if @tt == T_WITH
      s = @tstart
      next_token()
      expect(T_LBRACE)
      props = []
      seen = {}
      while @tt != T_RBRACE
        ps = @tstart
        key = nil
        if @tt == T_STRING
          fail("Octal escape sequences are not allowed in strict mode", ps) if @legacy_octal && strict?()
          key = mk(:string, ps, @value, nil, nil, nil, nil, 0)
          next_token()
        elsif ident_name?()
          key = mk(:ident, ps, @value, nil, nil, nil, nil, 0)
          next_token()
        else
          unexpected()
        fail("Duplicate import attribute key '" + key.str + "'", ps) if seen.has_key?(key.str)
        seen[key.str] = true
        expect(T_COLON)
        unexpected() if @tt != T_STRING
        fail("Octal escape sequences are not allowed in strict mode", @tstart) if @legacy_octal && strict?()
        val = mk(:string, @tstart, @value, nil, nil, nil, nil, 0)
        next_token()
        props.push(mk(:prop, ps, "init", key, val, nil, nil, 0))
        break if @tt != T_COMMA
        next_token()
      expect(T_RBRACE)
      return mk(:object, s, nil, nil, nil, nil, props, 0)
    nil

  -> parse_import_decl
    s = @tstart
    next_token()
    specs = []
    source = nil
    phase = nil
    if @tt == T_STRING
      source = @value
      next_token()
    else
      if name_is?("defer") && !peek_nl() && peek() == T_STAR
        phase = "defer"
        next_token()
        ls = @tstart
        next_token()
        expect_name("as")
        local = binding_ident().str
        specs.push(mk(:import_spec, ls, local, :namespace, nil, nil, nil, 0))
        expect_name("from")
        unexpected() if @tt != T_STRING
        source = @value
        next_token()
      elsif name_is?("source") && peek() == T_NAME
        # `import source x from "mod"` iff token after x is `from`!
        sp = @pos
        stt = @tt
        sts = @tstart
        ste = @tend
        sv = @value
        sr = @raw
        snl = @nl
        ses = @escaped
        spe = @prev_end
        slo = @legacy_octal
        ssp = @sp
        next_token()
        is_src = peek() == T_NAME && peek_value() == "from"
        @pos = sp
        @tt = stt
        @tstart = sts
        @tend = ste
        @value = sv
        @raw = sr
        @nl = snl
        @escaped = ses
        @prev_end = spe
        @legacy_octal = slo
        @sp = ssp
        if is_src
          phase = "source"
          next_token()
          ls = @tstart
          local = binding_ident().str
          specs.push(mk(:import_spec, ls, local, "source", nil, nil, nil, 0))
          expect_name("from")
          unexpected() if @tt != T_STRING
          source = @value
          next_token()
        else
          ls = @tstart
          local = binding_ident().str
          specs.push(mk(:import_spec, ls, local, "default", nil, nil, nil, 0))
          if @tt == T_COMMA
            next_token()
            if @tt == T_STAR
              ls2 = @tstart
              next_token()
              expect_name("as")
              local2 = binding_ident().str
              specs.push(mk(:import_spec, ls2, local2, :namespace, nil, nil, nil, 0))
            elsif @tt == T_LBRACE
              next_token()
              while @tt != T_RBRACE
                ls2 = @tstart
                was_str = @tt == T_STRING
                was_kw = @tt >= T_BREAK && @tt <= T_KW_LAST
                imported = module_name()
                local2 = imported
                if name_is?("as")
                  next_token()
                  local2 = binding_ident().str
                else
                  fail("Imported binding must be a valid identifier", ls2) if was_str || was_kw
                  check_ident(local2, ls2, true)
                specs.push(mk(:import_spec, ls2, local2, imported, nil, nil, nil, 0))
                break if @tt != T_COMMA
                next_token()
              expect(T_RBRACE)
            else
              unexpected()
          expect_name("from")
          unexpected() if @tt != T_STRING
          source = @value
          next_token()
      else
        had_default = false
        if @tt == T_NAME
          ls = @tstart
          local = binding_ident().str
          specs.push(mk(:import_spec, ls, local, "default", nil, nil, nil, 0))
          had_default = true
          if @tt == T_COMMA
            next_token()
            unexpected() if @tt != T_STAR && @tt != T_LBRACE
        if @tt == T_STAR
          ls = @tstart
          next_token()
          expect_name("as")
          local = binding_ident().str
          specs.push(mk(:import_spec, ls, local, :namespace, nil, nil, nil, 0))
        elsif @tt == T_LBRACE
          next_token()
          while @tt != T_RBRACE
            ls = @tstart
            was_str = @tt == T_STRING
            was_kw = @tt >= T_BREAK && @tt <= T_KW_LAST
            imported = module_name()
            local = imported
            if name_is?("as")
              next_token()
              local = binding_ident().str
            else
              fail("Imported binding must be a valid identifier", ls) if was_str || was_kw
              check_ident(local, ls, true)
            specs.push(mk(:import_spec, ls, local, imported, nil, nil, nil, 0))
            break if @tt != T_COMMA
            next_token()
          expect(T_RBRACE)
        elsif !had_default
          unexpected()
        expect_name("from")
        unexpected() if @tt != T_STRING
        source = @value
        next_token()
    attrs = parse_attributes()
    semicolon()
    mk(:import_decl, s, source, phase, attrs, nil, specs, 0)

  -> parse_export_decl(decs = nil)
    s = @tstart
    next_token()
    if @tt == T_STAR
      unexpected() if decs != nil
      next_token()
      exported = nil
      if name_is?("as")
        next_token()
        exported = module_name()
      expect_name("from")
      unexpected() if @tt != T_STRING
      source = @value
      next_token()
      attrs = parse_attributes()
      semicolon()
      return mk(:export_all, s, source, exported, attrs, nil, nil, 0)
    if @tt == T_DEFAULT
      next_token()
      ds = @tstart
      decl = nil
      if @tt == T_AT
        fail("Decorators cannot appear both before and after export", @tstart) if decs != nil
        decs = parse_decorators()
        unexpected() if @tt != T_CLASS
        decl = parse_class(ds, true, decs)
      elsif @tt == T_CLASS
        decl = parse_class(ds, true, decs)
      elsif decs != nil
        unexpected()
      elsif @tt == T_FUNCTION
        decl = parse_function(ds, true, F_PAREN)
      elsif name_is?("async") && peek() == T_FUNCTION && !peek_nl()
        next_token()
        decl = parse_function(ds, true, F_ASYNC | F_PAREN)
      else
        decl = parse_assign()
        semicolon()
      return mk(:export_default, s, nil, decl, nil, nil, nil, 0)
    if @tt == T_LBRACE
      unexpected() if decs != nil
      next_token()
      specs = []
      bad_local_pos = -1
      while @tt != T_RBRACE
        ls = @tstart
        was_str = @tt == T_STRING
        was_kw = @tt >= T_BREAK && @tt <= T_KW_LAST
        local = module_name()
        bad_local_pos = ls if bad_local_pos < 0 && (was_str || was_kw)
        exported = local
        if name_is?("as")
          next_token()
          exported = module_name()
        specs.push(mk(:export_spec, ls, local, exported, nil, nil, nil, 0))
        break if @tt != T_COMMA
        next_token()
      expect(T_RBRACE)
      source = nil
      attrs = nil
      if name_is?("from")
        next_token()
        unexpected() if @tt != T_STRING
        source = @value
        next_token()
        attrs = parse_attributes()
      else
        fail("String or keyword export specifier requires 'from' clause", bad_local_pos) if bad_local_pos >= 0
      semicolon()
      n = mk(:export_named, s, nil, nil, source, nil, specs, 0)
      n.c = attrs
      return n
    decl = nil
    if @tt == T_AT
      fail("Decorators cannot appear both before and after export", @tstart) if decs != nil
      ds = @tstart
      decs = parse_decorators()
      unexpected() if @tt != T_CLASS
      decl = parse_class(ds, true, decs)
    elsif @tt == T_CLASS
      decl = parse_class(@tstart, true, decs)
    elsif decs != nil
      unexpected()
    elsif @tt == T_VAR || @tt == T_CONST || name_is?("let")
      ds = @tstart
      kind = @value
      next_token()
      decl = parse_var(kind, ds)
      semicolon()
    elsif @tt == T_FUNCTION
      decl = parse_function(@tstart, true, 0)
    elsif name_is?("async")
      ds = @tstart
      next_token()
      unexpected() if @tt != T_FUNCTION
      decl = parse_function(ds, true, F_ASYNC)
    else
      unexpected()
    mk(:export_named, s, nil, decl, nil, nil, [], 0)

  # ---- functions ----

  # At `function`. flags: F_ASYNC; F_PAREN here means "a declaration may be anonymous".
  -> parse_function(s, is_decl, flags)
    next_token()
    if @tt == T_STAR
      flags = flags | F_GENERATOR
      next_token()
    name = nil
    name_pos = @tstart
    if @tt == T_NAME
      name = @value
      # Function expression name is checked in the function's own async/gen context (not enclosing)!
      if is_decl
        check_ident(name, name_pos, true)
      else
        save_c = @ctx
        @ctx = (@ctx & C_STRICT) | ((flags & F_ASYNC) != 0 ? C_ASYNC : 0) | ((flags & F_GENERATOR) != 0 ? C_GEN : 0)
        check_ident(name, name_pos, true)
        @ctx = save_c
      next_token()
    elsif is_decl && (flags & F_PAREN) == 0
      unexpected()
    flags = flags & (F_ASYNC | F_GENERATOR)
    parse_function_rest(s, is_decl ? :function_decl : :function, name, flags, name_pos)

  # Parameters and body; the current token is '('.
  -> parse_function_rest(s, kind, name, flags, name_pos = -1)
    save_ctx = @ctx
    save_acc = @fn_acc
    save_ld = @loop_depth
    save_sd = @switch_depth
    save_lbl = @labels
    c = (@ctx & C_STRICT) | C_FUNC
    c = c | C_ASYNC if (flags & F_ASYNC) != 0
    c = c | C_GEN if (flags & F_GENERATOR) != 0
    @ctx = c | C_PARAMS
    @fn_acc = 0
    @fn_depth += 1
    @loop_depth = 0
    @switch_depth = 0
    @labels = []
    params = parse_params()
    @ctx = c
    if @lazy && @tt == T_LBRACE && !pife?(s)
      lz = try_skip_body()
      if lz != nil
        # `arguments` in a parameter default counts now; the body's uses come with it
        flags = flags | (@fn_acc & F_USES_ARGS)
        @fn_depth -= 1
        @loop_depth = save_ld
        @switch_depth = save_sd
        @labels = save_lbl
        @fn_acc = save_acc
        @ctx = save_ctx
        node = mk(kind, s, name, nil, nil, nil, params, flags)
        node.c = lz
        return node
    body = parse_function_body()
    had_strict_dir = @body_had_strict
    simple = params_simple?(params)
    fail("Illegal 'use strict' directive in function with non-simple parameter list", s) if had_strict_dir && !simple
    if strict?()
      check_ident(name, name_pos >= 0 ? name_pos : s, true, true) if name != nil
      params.each ->(p) check_pattern_idents(p, true, true)
    if strict?() || (flags & F_METHOD) != 0 || !simple
      check_dup_params(params)
    flags = flags | F_STRICT if strict?()
    flags = flags | @fn_acc
    @fn_depth -= 1
    @loop_depth = save_ld
    @switch_depth = save_sd
    @labels = save_lbl
    @fn_acc = save_acc | (@fn_acc & F_HAS_EVAL)
    @ctx = save_ctx
    mk(kind, s, name, nil, body, nil, params, flags)

  -> parse_params
    expect(T_LPAREN)
    params = []
    while @tt != T_RPAREN
      if @tt == T_ELLIPSIS
        rs = @tstart
        next_token()
        t = parse_binding_target()
        fail("Rest parameter may not have a default initializer", @tstart) if @tt == T_ASSIGN
        fail("Rest parameter may not have a trailing comma", @tstart) if @tt == T_COMMA
        params.push(mk(:rest, rs, nil, t, nil, nil, nil, 0))
        break
      params.push(parse_binding_element())
      break if @tt != T_COMMA
      next_token()
    expect(T_RPAREN)
    params

  # `{ directives statements }`; may switch the current context to strict.
  -> parse_function_body
    expect(T_LBRACE)
    save_ic = @in_case
    @in_case = false
    body = []
    @body_had_strict = parse_directives(body)
    while @tt != T_RBRACE
      unexpected() if @tt == T_EOF
      body.push(parse_item())
    @in_case = save_ic
    next_token()
    body

  # At '=>'. params are already patterns.
  -> parse_arrow_body(s, params, flags)
    next_token()
    save_ctx = @ctx
    save_ld = @loop_depth
    save_sd = @switch_depth
    save_lbl = @labels
    c = (@ctx & (C_STRICT | C_NOIN)) | C_FUNC
    c = c | C_ASYNC if (flags & F_ASYNC) != 0
    @ctx = c
    if (flags & F_ASYNC) != 0
      params.each ->(p) fail("Await expression not allowed in formal parameter", p.pos) if node_has_await_in_async_params?(p)
      params.each ->(p) check_pattern_idents(p, true)
    else
      params.each ->(p) fail("Await expression not allowed in formal parameter", p.pos) if node_has_kind?(p, :await)
    params.each ->(p) fail("Yield expression not allowed in formal parameter", p.pos) if node_has_kind?(p, :yield)
    @fn_depth += 1
    @loop_depth = 0
    @switch_depth = 0
    @labels = []
    body = nil
    lz = nil
    had_strict_dir = false
    if @tt == T_LBRACE
      @ctx = @ctx & C_NOIN_MASK
      lz = try_skip_body() if @lazy && !pife?(s)
      if lz != nil
        @fn_acc = @fn_acc | F_USES_ARGS if @skip_args
      else
        body = parse_function_body()
        had_strict_dir = @body_had_strict
    else
      body = parse_assign()
      flags = flags | F_EXPR_BODY
    fail("Illegal 'use strict' directive in function with non-simple parameter list", s) if had_strict_dir && !params_simple?(params)
    check_dup_params(params)
    if strict?()
      params.each ->(p) check_pattern_idents(p, true, true)
    flags = flags | F_STRICT if strict?() && lz == nil
    @fn_depth -= 1
    @loop_depth = save_ld
    @switch_depth = save_sd
    @labels = save_lbl
    @ctx = save_ctx
    node = mk(:arrow, s, nil, nil, body, nil, params, flags)
    node.c = lz
    node

  # Reinterpret cover-grammar expressions as arrow parameters.
  -> to_params(items)
    params = []
    items.each ->(e)
      params.push(to_pattern(e, true))
    params

  # ---- decorators & classes ----

  -> parse_decorators
    decs = []
    while @tt == T_AT
      decs.push(parse_decorator())
    decs

  -> parse_decorator
    next_token()
    if @tt == T_LPAREN
      next_token()
      save = @ctx
      @ctx = @ctx & C_NOIN_MASK
      e = parse_expression()
      @ctx = save
      expect(T_RPAREN)
      return e
    unexpected() if @tt != T_NAME
    s = @tstart
    v = @value
    check_ident(v, s, false)
    @fn_acc = @fn_acc | F_USES_ARGS if v == "arguments"
    next_token()
    e = mk(:ident, s, v, nil, nil, nil, nil, 0)
    while @tt == T_DOT
      next_token()
      prop = parse_member_name()
      e = mk(:member, s, nil, e, prop, nil, nil, 0)
    if @tt == T_LPAREN
      args = parse_args()
      e = mk(:call, s, nil, e, nil, nil, args, 0)
    e

  -> parse_class(s, is_decl, decs = nil)
    next_token()
    save_ctx = @ctx
    @ctx = @ctx | C_STRICT
    name = nil
    if @tt == T_NAME && !name_is?("extends")
      name = @value
      check_ident(name, @tstart, true, true)
      next_token()
    sup = nil
    if @tt == T_EXTENDS
      next_token()
      sup = parse_lhs()
      fail("Unexpected token '=>'", sup.pos) if sup.kind == :arrow && (sup.flags & F_PAREN) == 0
    @ctx = @ctx & C_NOIN_MASK
    expect(T_LBRACE)
    members = []
    has_ctor = false
    privs = {}
    while @tt != T_RBRACE
      if @tt == T_SEMI
        next_token()
      else
        unexpected() if @tt == T_EOF
        m = parse_class_member()
        if m.kind == :method_def || m.kind == :field_def
          st = (m.flags & F_STATIC) != 0
          comp = (m.flags & F_COMPUTED) != 0
          k = m.a
          if k.kind == :private_name
            fail("Classes may not have a private element named '#constructor'", m.pos) if k.str == "constructor"
            bit = m.kind == :field_def ? 1 : (m.str == "method" ? 1 : (st ? (m.str == "get" ? 8 : 16) : (m.str == "get" ? 2 : 4)))
            prev_b = privs[k.str]
            if prev_b != nil
              ok_pair = (prev_b == 2 && bit == 4) || (prev_b == 4 && bit == 2) || (prev_b == 8 && bit == 16) || (prev_b == 16 && bit == 8)
              fail("Identifier '#" + k.str + "' has already been declared", m.pos) if !ok_pair
              privs[k.str] = prev_b | bit
            else
              privs[k.str] = bit
          elsif !comp && (k.kind == :ident || k.kind == :string)
            fail("Classes may not have a static property named 'prototype'", m.pos) if st && k.str == "prototype"
            fail("Classes may not have a field named 'constructor'", m.pos) if m.kind == :field_def && k.str == "constructor"
            if m.kind == :method_def && !st && k.str == "constructor"
              fail("Class constructor may not be an accessor, async, or generator", m.pos) if m.str != "constructor"
              fail("A class may only have one constructor", m.pos) if has_ctor
              has_ctor = true
        members.push(m)
    next_token()
    @ctx = save_ctx
    mk(is_decl ? :class_decl : :class, s, name, sup, decs, nil, members, 0)

  # Is the token after a get/set/static/async word a property key start
  # (rather than the word itself being the key)?
  -> modifier_follows?(pk)
    pk != T_LPAREN && pk != T_ASSIGN && pk != T_SEMI && pk != T_RBRACE && pk != T_EOF && pk != T_COMMA && pk != T_COLON

  -> parse_class_member
    s = @tstart
    decs = @tt == T_AT ? parse_decorators() : nil
    flags = 0
    kind = "method"
    if name_is?("static")
      pk = peek()
      if pk == T_LBRACE
        fail("Decorators are not valid on static blocks", s) if decs != nil
        next_token()
        save_ctx = @ctx
        save_acc = @fn_acc
        save_fd = @fn_depth
        save_ld = @loop_depth
        save_sd = @switch_depth
        save_lbl = @labels
        @ctx = (@ctx & C_STRICT) | C_STATIC_BLOCK
        @fn_depth = 0
        @loop_depth = 0
        @switch_depth = 0
        @labels = []
        blk = parse_block()
        @fn_depth = save_fd
        @loop_depth = save_ld
        @switch_depth = save_sd
        @labels = save_lbl
        @fn_acc = save_acc
        @ctx = save_ctx
        return mk(:static_block, s, nil, nil, nil, nil, blk.list, F_STATIC)
      if modifier_follows?(pk)
        flags = flags | F_STATIC
        next_token()
    # a method's source text starts after `static` (MethodDefinition)
    ms = @tstart
    fnflags = 0
    if name_is?("async")
      pk = peek()
      if modifier_follows?(pk) && !peek_nl()
        fnflags = fnflags | F_ASYNC
        next_token()
    if @tt == T_STAR
      fnflags = fnflags | F_GENERATOR
      next_token()
    if fnflags == 0 && (name_is?("get") || name_is?("set"))
      pk = peek()
      if modifier_follows?(pk) && pk != T_STAR
        kind = @value
        next_token()
    is_accessor = false
    if fnflags == 0 && kind == "method" && name_is?("accessor")
      pk = peek()
      if modifier_follows?(pk) && pk != T_STAR && !peek_nl()
        is_accessor = true
        next_token()
    key = parse_property_key(true)
    flags = flags | F_COMPUTED if @key_computed
    if !is_accessor && (@tt == T_LPAREN || fnflags != 0 || kind != "method")
      if kind == "method" && fnflags == 0 && (flags & (F_STATIC | F_COMPUTED)) == 0 && (key.kind == :ident || key.kind == :string) && key.str == "constructor"
        kind = "constructor"
        fail("Decorators are not valid on constructors", s) if decs != nil
      func = parse_function_rest(ms, :function, nil, fnflags | F_METHOD)
      fail("Getter must not have any formal parameters", ms) if kind == "get" && func.list.size != 0
      fail("Setter must have exactly one formal parameter", ms) if kind == "set" && (func.list.size != 1 || func.list[0].kind == :rest)
      return mk(:method_def, s, kind, key, func, decs, nil, flags)
    value = nil
    if @tt == T_ASSIGN
      next_token()
      save_ctx = @ctx
      save_acc = @fn_acc
      save_fd = @fn_depth
      save_ld = @loop_depth
      save_sd = @switch_depth
      save_lbl = @labels
      @ctx = (@ctx & C_STRICT) | C_FIELD_INIT
      @fn_depth = 0
      @loop_depth = 0
      @switch_depth = 0
      @labels = []
      value = parse_assign()
      @fn_depth = save_fd
      @loop_depth = save_ld
      @switch_depth = save_sd
      @labels = save_lbl
      @fn_acc = save_acc
      @ctx = save_ctx
    semicolon()
    mk(:field_def, s, is_accessor ? "accessor" : nil, key, value, decs, nil, flags)

  # PropertyName or a class element name; sets @key_computed.
  -> parse_property_key(allow_private = false)
    s = @tstart
    @key_computed = false
    tt = @tt
    if tt == T_NAME || (tt >= T_BREAK && tt <= T_KW_LAST)
      v = @value
      next_token()
      return mk(:ident, s, v, nil, nil, nil, nil, 0)
    if tt == T_STRING
      fail("Octal escape sequences are not allowed in strict mode", s) if @legacy_octal && strict?()
      v = @value
      next_token()
      return mk(:string, s, v, nil, nil, nil, nil, 0)
    if tt == T_NUM
      fail("Octal literals are not allowed in strict mode", s) if @legacy_octal && strict?()
      v = @num
      next_token()
      return mk(:num, s, nil, v, nil, nil, nil, 0)
    if tt == T_BIGINT
      v = @value
      next_token()
      return mk(:bigint, s, v, nil, nil, nil, nil, 0)
    if tt == T_PRIVATE && allow_private
      v = @value
      next_token()
      return mk(:private_name, s, v, nil, nil, nil, nil, 0)
    if tt == T_LBRACK
      next_token()
      save = @ctx
      @ctx = @ctx & C_NOIN_MASK
      e = parse_assign()
      @ctx = save
      expect(T_RBRACK)
      @key_computed = true
      return e
    unexpected()

  # ---- patterns ----

  -> parse_binding_target
    tt = @tt
    return parse_array_binding() if tt == T_LBRACK
    return parse_object_binding() if tt == T_LBRACE
    binding_ident()

  -> parse_binding_element
    s = @tstart
    t = parse_binding_target()
    if @tt == T_ASSIGN
      next_token()
      save = @ctx
      @ctx = @ctx & C_NOIN_MASK
      d = parse_assign()
      @ctx = save
      return mk(:assign_pattern, s, nil, t, d, nil, nil, 0)
    t

  -> parse_array_binding
    s = @tstart
    next_token()
    elems = []
    while @tt != T_RBRACK
      if @tt == T_COMMA
        elems.push(nil)
        next_token()
      else
        if @tt == T_ELLIPSIS
          rs = @tstart
          next_token()
          t = parse_binding_target()
          elems.push(mk(:rest, rs, nil, t, nil, nil, nil, 0))
          break
        elems.push(parse_binding_element())
        break if @tt != T_COMMA
        next_token()
    expect(T_RBRACK)
    mk(:array_pattern, s, nil, nil, nil, nil, elems, 0)

  -> parse_object_binding
    s = @tstart
    next_token()
    props = []
    while @tt != T_RBRACE
      ps = @tstart
      if @tt == T_ELLIPSIS
        next_token()
        t = binding_ident()
        props.push(mk(:rest, ps, nil, t, nil, nil, nil, 0))
        break
      shorthand_ok = @tt == T_NAME
      key = parse_property_key()
      flags = @key_computed ? F_COMPUTED : 0
      value = nil
      if @tt == T_COLON
        next_token()
        value = parse_binding_element()
      else
        unexpected() if !shorthand_ok
        check_ident(key.str, ps, true)
        flags = flags | F_SHORTHAND
        value = key
        if @tt == T_ASSIGN
          next_token()
          save = @ctx
          @ctx = @ctx & C_NOIN_MASK
          d = parse_assign()
          @ctx = save
          value = mk(:assign_pattern, ps, nil, key, d, nil, nil, 0)
      props.push(mk(:prop, ps, "init", key, value, nil, nil, flags))
      break if @tt != T_COMMA
      next_token()
    expect(T_RBRACE)
    mk(:object_pattern, s, nil, nil, nil, nil, props, 0)

  # Reinterpret an expression as an assignment target (binding=false) or a
  # binding pattern (binding=true, for arrow parameters). Mutates in place.
  -> to_pattern(e, binding)
    k = e.kind
    if k == :ident
      check_ident(e.str, e.pos, binding || strict?())
      return e
    if k == :member
      fail("Invalid destructuring target", e.pos) if binding || (e.flags & F_OPTIONAL) != 0
      return e
    if k == :array && (e.flags & F_PAREN) == 0
      e.kind = :array_pattern
      elems = e.list
      i = 0
      n = elems.size
      while i < n
        x = elems[i]
        if x != nil
          if x.kind == :spread
            fail("Rest element must be last element", x.pos) if i != n - 1 || (x.flags & F_REST_TRAIL) != 0
            fail("Rest element may not have a default initializer", x.pos) if x.a.kind == :assign && x.a.str == "="
            x.kind = :rest
            x.a = to_pattern(x.a, binding)
          else
            elems[i] = to_pattern(x, binding)
        i += 1
      return e
    if k == :object && (e.flags & F_PAREN) == 0
      e.kind = :object_pattern
      props = e.list
      i = 0
      n = props.size
      while i < n
        p = props[i]
        if p.kind == :spread
          fail("Rest element must be last element", p.pos) if i != n - 1 || (p.flags & F_REST_TRAIL) != 0
          fail("Rest element may not have a default initializer", p.pos) if p.a.kind == :assign && p.a.str == "="
          p.kind = :rest
          p.a = to_pattern(p.a, binding)
        else
          fail("Invalid destructuring assignment target", p.pos) if p.str != "init" || (p.flags & F_METHOD) != 0
          p.b = to_pattern(p.b, binding)
        i += 1
      return e
    if k == :assign && e.str == "=" && (e.flags & F_PAREN) == 0
      e.kind = :assign_pattern
      e.a = to_pattern(e.a, binding)
      return e
    if k == :assign_pattern
      e.a = to_pattern(e.a, binding)
      return e
    if k == :array_pattern || k == :object_pattern
      return e
    if k == :rest
      fail("Rest element may not have a default initializer", e.pos) if e.a.kind == :assign && e.a.str == "="
      e.a = to_pattern(e.a, binding)
      return e
    fail("Invalid destructuring assignment target", e.pos)

  # ---- expressions ----

  -> parse_expression
    s = @tstart
    e = parse_assign()
    if @tt == T_COMMA
      list = [e]
      while @tt == T_COMMA
        next_token()
        list.push(parse_assign())
      e = mk(:seq, s, nil, nil, nil, nil, list, 0)
    e

  -> parse_assign
    if @tt == T_NAME && (@ctx & C_GEN) != 0 && @value == "yield" && !@escaped
      return parse_yield()
    s = @tstart
    left = parse_conditional()
    tt = @tt
    if tt >= T_ASSIGN && tt <= T_NULLISH_ASSIGN
      if left.kind == :arrow && (left.flags & F_PAREN) == 0
        return left
      if tt == T_ASSIGN
        if !(!strict?() && left.kind == :call && (left.flags & F_OPTIONAL) == 0)
          left = to_pattern(left, false)
      else
        k = left.kind
        if k != :ident && !(k == :member && (left.flags & F_OPTIONAL) == 0) && !(!strict?() && tt < T_ANDAND_ASSIGN && k == :call && (left.flags & F_OPTIONAL) == 0)
          fail("Invalid left-hand side in assignment", left.pos)
        if k == :ident
          check_ident(left.str, left.pos, strict?())
      next_token()
      right = parse_assign()
      return mk(:assign, s, JS_TOKEN_TEXT[tt], left, right, nil, nil, 0)
    left

  -> parse_yield
    s = @tstart
    fail("Yield expression not allowed in formal parameter", s) if (@ctx & C_PARAMS) != 0
    next_token()
    tt = @tt
    if @nl || tt == T_RPAREN || tt == T_RBRACK || tt == T_RBRACE || tt == T_COMMA || tt == T_SEMI || tt == T_COLON || tt == T_EOF || tt == T_QUESTION || (tt == T_TEMPLATE && @src.byte_at(@tstart) == 125) || (tt >= T_ASSIGN && tt <= T_NULLISH_ASSIGN) || (tt == T_IN && (@ctx & C_NOIN) != 0)
      return mk(:yield, s, nil, nil, nil, nil, nil, 0)
    if tt == T_STAR
      next_token()
      arg = parse_assign()
      return mk(:yield, s, nil, arg, nil, nil, nil, F_DELEGATE)
    arg = parse_assign()
    mk(:yield, s, nil, arg, nil, nil, nil, 0)

  -> parse_conditional
    s = @tstart
    test = parse_binary(0)
    if @tt == T_QUESTION
      return test if test.kind == :arrow && (test.flags & F_PAREN) == 0
      next_token()
      save = @ctx
      @ctx = @ctx & C_NOIN_MASK
      cons = parse_assign()
      @ctx = save
      expect(T_COLON)
      alt = parse_assign()
      return mk(:cond, s, nil, test, cons, alt, nil, 0)
    test

  -> parse_binary(min_prec)
    s = @tstart
    if @tt == T_PRIVATE && min_prec < JS_PREC[T_IN]
      v = @value
      next_token()
      unexpected() if @tt != T_IN || (@ctx & C_NOIN) != 0
      left = mk(:private_name, s, v, nil, nil, nil, nil, 0)
    else
      left = parse_unary()
    return left if left.kind == :arrow && (left.flags & F_PAREN) == 0
    while true
      tt = @tt
      if tt == T_REGEX
        rescan_div()
        tt = @tt
      prec = JS_PREC[tt]
      break if prec <= min_prec
      break if tt == T_IN && (@ctx & C_NOIN) != 0
      fail("Unary operator used immediately before exponentiation expression", left.pos) if tt == T_STARSTAR && (left.kind == :unary || left.kind == :await) && (left.flags & F_PAREN) == 0
      if tt == T_NULLISH && left.kind == :logical && (left.str == "&&" || left.str == "||") && (left.flags & F_PAREN) == 0
        fail("Cannot mix '??' with '&&' or '||' without parentheses", @tstart)
      if (tt == T_ANDAND || tt == T_OROR) && left.kind == :logical && left.str == "??" && (left.flags & F_PAREN) == 0
        fail("Cannot mix '??' with '&&' or '||' without parentheses", @tstart)
      next_token()
      right = tt == T_STARSTAR ? parse_binary(prec - 1) : parse_binary(prec)
      if tt == T_NULLISH && right.kind == :logical && (right.str == "&&" || right.str == "||") && (right.flags & F_PAREN) == 0
        fail("Cannot mix '??' with '&&' or '||' without parentheses", right.pos)
      if (tt == T_ANDAND || tt == T_OROR) && right.kind == :logical && right.str == "??" && (right.flags & F_PAREN) == 0
        fail("Cannot mix '??' with '&&' or '||' without parentheses", right.pos)
      if tt == T_IN && left.kind == :private_name
        fail("Unexpected private identifier", right.pos) if right.kind == :private_name
        fail("Unexpected arrow function", right.pos) if right.kind == :arrow && (right.flags & F_PAREN) == 0
      kind = (tt == T_OROR || tt == T_ANDAND || tt == T_NULLISH) ? :logical : :binary
      left = mk(kind, s, JS_TOKEN_TEXT[tt], left, right, nil, nil, 0)
    left

  -> parse_unary
    tt = @tt
    s = @tstart
    if tt == T_BANG || tt == T_MINUS || tt == T_PLUS || tt == T_TILDE || tt == T_TYPEOF || tt == T_VOID || tt == T_DELETE
      next_token()
      arg = parse_unary()
      if tt == T_DELETE
        da = arg.kind == :chain ? arg.a : arg
        fail("Private fields can not be deleted", arg.pos) if da.kind == :member && da.b.kind == :private_name
      return mk(:unary, s, JS_TOKEN_TEXT[tt], arg, nil, nil, nil, 0)
    if tt == T_INC || tt == T_DEC
      next_token()
      arg = parse_unary()
      k = arg.kind
      fail("Invalid left-hand side expression in prefix operation", arg.pos) if k != :ident && !(k == :member && (arg.flags & F_OPTIONAL) == 0) && !(!strict?() && k == :call && (arg.flags & F_OPTIONAL) == 0)
      check_ident(arg.str, arg.pos, strict?()) if k == :ident
      return mk(:update, s, JS_TOKEN_TEXT[tt], arg, nil, nil, nil, F_PREFIX)
    if tt == T_NAME && @value == "await" && !@escaped && ((@ctx & C_ASYNC) != 0 || (@module && @fn_depth == 0 && (@ctx & (C_FIELD_INIT | C_STATIC_BLOCK)) == 0))
      fail("Await expression not allowed in formal parameter", s) if (@ctx & C_PARAMS) != 0
      next_token()
      arg = parse_unary()
      return mk(:await, s, nil, arg, nil, nil, nil, 0)
    e = parse_lhs()
    if (@tt == T_INC || @tt == T_DEC) && !@nl
      return e if e.kind == :arrow && (e.flags & F_PAREN) == 0
      k = e.kind
      fail("Invalid left-hand side expression in postfix operation", e.pos) if k != :ident && !(k == :member && (e.flags & F_OPTIONAL) == 0) && !(!strict?() && k == :call && (e.flags & F_OPTIONAL) == 0)
      check_ident(e.str, e.pos, strict?()) if k == :ident
      op = JS_TOKEN_TEXT[@tt]
      next_token()
      return mk(:update, s, op, e, nil, nil, nil, 0)
    e

  # LeftHandSideExpression: new / call / member chains.
  -> parse_lhs
    s = @tstart
    e = nil
    if @tt == T_NEW
      e = parse_new()
    else
      e = parse_primary()
      return e if e.kind == :arrow && (e.flags & F_PAREN) == 0
    parse_subscripts(e, s, false)

  -> parse_new
    s = @tstart
    next_token()
    if @tt == T_DOT
      next_token()
      expect_name("target")
      return mk(:meta_property, s, "new.target", nil, nil, nil, nil, 0)
    cs = @tstart
    callee = nil
    if @tt == T_NEW
      callee = parse_new()
    elsif @tt == T_IMPORT
      if peek() == T_DOT
        callee = parse_primary()
        fail("Cannot use 'new' with import." + callee.str.to_s, cs) if callee.kind == :import_call
      else
        unexpected()
    else
      callee = parse_primary()
    callee = parse_subscripts(callee, cs, true)
    args = @tt == T_LPAREN ? parse_args() : []
    mk(:new, s, nil, callee, nil, nil, args, 0)

  -> parse_member_name
    s = @tstart
    if @tt == T_PRIVATE
      v = @value
      next_token()
      return mk(:private_name, s, v, nil, nil, nil, nil, 0)
    unexpected() if !ident_name?()
    v = @value
    next_token()
    mk(:ident, s, v, nil, nil, nil, nil, 0)

  -> parse_subscripts(e, s, no_call)
    chain = false
    while true
      tt = @tt
      if tt == T_DOT
        next_token()
        prop = parse_member_name()
        fail("Private fields cannot be accessed on super", prop.pos) if e.kind == :super && prop.kind == :private_name
        e = mk(:member, s, nil, e, prop, nil, nil, 0)
      elsif tt == T_LBRACK
        next_token()
        save = @ctx
        @ctx = @ctx & C_NOIN_MASK
        prop = parse_expression()
        @ctx = save
        expect(T_RBRACK)
        e = mk(:member, s, nil, e, prop, nil, nil, F_COMPUTED)
      elsif tt == T_LPAREN
        break if no_call
        args = parse_args()
        # (eval)(…) is still a direct eval (the grouping keeps the reference)
        if e.kind == :ident && e.str == "eval"
          @fn_acc = @fn_acc | F_HAS_EVAL
        e = mk(:call, s, nil, e, nil, nil, args, 0)
      elsif tt == T_TEMPLATE && @src.byte_at(@tstart) == 96
        fail("Invalid tagged template on optional chain", @tstart) if chain
        q = parse_template(true)
        e = mk(:tagged_template, s, nil, e, q, nil, nil, 0)
      elsif tt == T_QDOT
        fail("Invalid optional chain from new expression", @tstart) if no_call
        chain = true
        next_token()
        if @tt == T_LPAREN
          args = parse_args()
          e = mk(:call, s, nil, e, nil, nil, args, F_OPTIONAL)
        elsif @tt == T_LBRACK
          next_token()
          save = @ctx
          @ctx = @ctx & C_NOIN_MASK
          prop = parse_expression()
          @ctx = save
          expect(T_RBRACK)
          e = mk(:member, s, nil, e, prop, nil, nil, F_COMPUTED | F_OPTIONAL)
        else
          prop = parse_member_name()
          fail("Private fields cannot be accessed on super", prop.pos) if e.kind == :super && prop.kind == :private_name
          e = mk(:member, s, nil, e, prop, nil, nil, F_OPTIONAL)
      else
        break
    e = mk(:chain, s, nil, e, nil, nil, nil, 0) if chain
    e

  -> parse_args
    next_token()
    save = @ctx
    @ctx = @ctx & C_NOIN_MASK
    args = []
    while @tt != T_RPAREN
      if @tt == T_ELLIPSIS
        s = @tstart
        next_token()
        arg = parse_assign()
        args.push(mk(:spread, s, nil, arg, nil, nil, nil, 0))
      else
        args.push(parse_assign())
      break if @tt != T_COMMA
      next_token()
    @ctx = save
    expect(T_RPAREN)
    args

  -> parse_primary
    tt = @tt
    s = @tstart
    case tt
    when T_NAME
      v = @value
      if v == "async" && !@escaped
        pk = peek()
        if !peek_nl()
          if pk == T_FUNCTION
            next_token()
            return parse_function(s, false, F_ASYNC)
          if pk == T_NAME
            sp = @pos
            stt = @tt
            sts = @tstart
            ste = @tend
            sv = @value
            sr = @raw
            snl = @nl
            ses = @escaped
            spe = @prev_end
            slo = @legacy_octal
            next_token()
            if @tt == T_NAME && peek() == T_ARROW && !peek_nl()
              param = binding_ident()
              return parse_arrow_body(s, [param], F_ASYNC)
            @pos = sp
            @tt = stt
            @tstart = sts
            @tend = ste
            @value = sv
            @raw = sr
            @nl = snl
            @escaped = ses
            @prev_end = spe
            @legacy_octal = slo
          if pk == T_LPAREN
            next_token()
            callee = mk(:ident, s, v, nil, nil, nil, nil, 0)
            items = parse_cover_args()
            if @tt == T_ARROW && !@nl
              return parse_arrow_body(s, to_params(items), F_ASYNC)
            items.each ->(x)
              x.kind = :spread if x.kind == :rest
            return mk(:call, s, nil, callee, nil, nil, items, 0)
      next_token()
      if @tt == T_ARROW && !@nl
        check_ident(v, s, true)
        param = mk(:ident, s, v, nil, nil, nil, nil, 0)
        return parse_arrow_body(s, [param], 0)
      check_ident(v, s, false)
      @fn_acc = @fn_acc | F_USES_ARGS if v == "arguments"
      return mk(:ident, s, v, nil, nil, nil, nil, 0)
    when T_NUM
      fail("Octal literals are not allowed in strict mode", s) if @legacy_octal && strict?()
      v = @num
      next_token()
      return mk(:num, s, nil, v, nil, nil, nil, 0)
    when T_STRING
      fail("Octal escape sequences are not allowed in strict mode", s) if @legacy_octal && strict?()
      v = @value
      next_token()
      return mk(:string, s, v, nil, nil, nil, nil, 0)
    when T_LPAREN
      return parse_paren()
    when T_THIS
      next_token()
      return mk(:this, s, nil, nil, nil, nil, nil, 0)
    when T_FUNCTION
      return parse_function(s, false, 0)
    when T_LBRACK
      return parse_array_literal()
    when T_LBRACE
      return parse_object_literal()
    when T_NULL
      next_token()
      return mk(:null, s, nil, nil, nil, nil, nil, 0)
    when T_TRUE
      next_token()
      return mk(:true, s, nil, nil, nil, nil, nil, 0)
    when T_FALSE
      next_token()
      return mk(:false, s, nil, nil, nil, nil, nil, 0)
    when T_TEMPLATE
      return parse_template(false)
    when T_REGEX
      return regex_node()
    when T_SLASH, T_SLASH_ASSIGN
      rescan_regex()
      return regex_node()
    when T_CLASS
      return parse_class(s, false)
    when T_AT
      decs = parse_decorators()
      unexpected() if @tt != T_CLASS
      return parse_class(s, false, decs)
    when T_SUPER
      next_token()
      unexpected() if @tt != T_LPAREN && @tt != T_DOT && @tt != T_LBRACK
      return mk(:super, s, nil, nil, nil, nil, nil, 0)
    when T_BIGINT
      v = @value
      next_token()
      return mk(:bigint, s, v, nil, nil, nil, nil, 0)
    when T_IMPORT
      next_token()
      if @tt == T_DOT
        next_token()
        if name_is?("meta")
          fail("Cannot use 'import.meta' outside a module", s) if !@module
          next_token()
          return mk(:meta_property, s, "import.meta", nil, nil, nil, nil, 0)
        if name_is?("defer") || name_is?("source")
          phase = @value
          next_token()
          unexpected() if @tt != T_LPAREN
          next_token()
          save = @ctx
          @ctx = @ctx & C_NOIN_MASK
          unexpected() if @tt == T_RPAREN || @tt == T_ELLIPSIS
          src = parse_assign()
          opts = nil
          if @tt == T_COMMA
            next_token()
            if @tt != T_RPAREN
              fail("import.source() accepts only one argument", @tstart) if phase == "source"
              unexpected() if @tt == T_ELLIPSIS
              opts = parse_assign()
              next_token() if @tt == T_COMMA
          @ctx = save
          expect(T_RPAREN)
          return mk(:import_call, s, phase, src, opts, nil, nil, 0)
        unexpected()
      unexpected() if @tt != T_LPAREN
      next_token()
      save = @ctx
      @ctx = @ctx & C_NOIN_MASK
      unexpected() if @tt == T_RPAREN || @tt == T_ELLIPSIS
      src = parse_assign()
      opts = nil
      if @tt == T_COMMA
        next_token()
        if @tt != T_RPAREN
          unexpected() if @tt == T_ELLIPSIS
          opts = parse_assign()
          next_token() if @tt == T_COMMA
      @ctx = save
      expect(T_RPAREN)
      return mk(:import_call, s, nil, src, opts, nil, nil, 0)
    when T_NEW
      return parse_new()
    unexpected()

  -> regex_node
    s = @tstart
    body = @value
    flags = @raw
    next_token()
    mk(:regex, s, body, flags, nil, nil, nil, 0)

  # `( ... )`: a parenthesized expression or arrow parameters.
  -> parse_paren
    s = @tstart
    items = parse_cover_args()
    if @tt == T_ARROW && !@nl
      return parse_arrow_body(s, to_params(items), 0)
    fail("Unexpected token )", @prev_end - 1) if items.size == 0
    items.each ->(x)
      fail("Unexpected token", x.pos) if x.kind == :rest
    fail("Unexpected token )", @prev_end - 1) if @cover_trailing
    e = items.size == 1 ? items[0] : mk(:seq, s + 1, nil, nil, nil, nil, items, 0)
    e.flags = e.flags | F_PAREN
    e

  # At '(': comma-separated assignment expressions, allowing what only arrow
  # parameters may contain (a trailing `...rest`, a trailing comma, nothing).
  # Sets @cover_trailing.
  -> parse_cover_args
    next_token()
    save = @ctx
    @ctx = @ctx & C_NOIN_MASK
    items = []
    @cover_trailing = false
    while @tt != T_RPAREN
      if @tt == T_ELLIPSIS
        rs = @tstart
        next_token()
        t = parse_assign()
        items.push(mk(:rest, rs, nil, t, nil, nil, nil, 0))
        break
      items.push(parse_assign())
      break if @tt != T_COMMA
      next_token()
      @cover_trailing = true if @tt == T_RPAREN
    @ctx = save
    trailing = @cover_trailing
    expect(T_RPAREN)
    @cover_trailing = trailing
    items

  -> parse_array_literal
    s = @tstart
    next_token()
    save = @ctx
    @ctx = @ctx & C_NOIN_MASK
    elems = []
    while @tt != T_RBRACK
      if @tt == T_COMMA
        elems.push(nil)
        next_token()
      else
        sp = nil
        if @tt == T_ELLIPSIS
          es = @tstart
          next_token()
          arg = parse_assign()
          sp = mk(:spread, es, nil, arg, nil, nil, nil, 0)
          elems.push(sp)
        else
          elems.push(parse_assign())
        break if @tt != T_COMMA
        sp.flags = sp.flags | F_REST_TRAIL if sp != nil
        next_token()
    @ctx = save
    expect(T_RBRACK)
    mk(:array, s, nil, nil, nil, nil, elems, 0)

  -> parse_object_literal
    s = @tstart
    next_token()
    save = @ctx
    @ctx = @ctx & C_NOIN_MASK
    props = []
    while @tt != T_RBRACE
      sp = nil
      if @tt == T_ELLIPSIS
        es = @tstart
        next_token()
        arg = parse_assign()
        sp = mk(:spread, es, nil, arg, nil, nil, nil, 0)
        props.push(sp)
      else
        props.push(parse_object_member())
      break if @tt != T_COMMA
      sp.flags = sp.flags | F_REST_TRAIL if sp != nil
      next_token()
    @ctx = save
    expect(T_RBRACE)
    mk(:object, s, nil, nil, nil, nil, props, 0)

  -> parse_object_member
    s = @tstart
    kind = "init"
    fnflags = 0
    if name_is?("async")
      pk = peek()
      if modifier_follows?(pk) && !peek_nl()
        fnflags = F_ASYNC
        next_token()
    if @tt == T_STAR
      fnflags = fnflags | F_GENERATOR
      next_token()
    if fnflags == 0 && (name_is?("get") || name_is?("set"))
      pk = peek()
      if modifier_follows?(pk) && pk != T_STAR
        kind = @value
        next_token()
    shorthand_ok = @tt == T_NAME
    key = parse_property_key()
    flags = @key_computed ? F_COMPUTED : 0
    if @tt == T_LPAREN || fnflags != 0 || kind != "init"
      func = parse_function_rest(s, :function, nil, fnflags | F_METHOD)
      fail("Getter must not have any formal parameters", s) if kind == "get" && func.list.size != 0
      fail("Setter must have exactly one formal parameter", s) if kind == "set" && (func.list.size != 1 || func.list[0].kind == :rest)
      return mk(:prop, s, kind, key, func, nil, nil, flags | F_METHOD)
    if @tt == T_COLON
      next_token()
      value = parse_assign()
      return mk(:prop, s, "init", key, value, nil, nil, flags)
    unexpected() if !shorthand_ok
    check_ident(key.str, s, false)
    @fn_acc = @fn_acc | F_USES_ARGS if key.str == "arguments"
    value = key
    if @tt == T_ASSIGN
      # CoverInitializedName: only valid once reinterpreted as a pattern
      next_token()
      d = parse_assign()
      value = mk(:assign_pattern, s, nil, key, d, nil, nil, 0)
    mk(:prop, s, "init", key, value, nil, nil, flags | F_SHORTHAND)

  -> parse_template(tagged)
    s = @tstart
    quasis = []
    exprs = []
    while true
      unexpected() if @tt != T_TEMPLATE
      fail("Invalid escape sequence in template", @tstart) if @value == nil && !tagged
      quasis.push(mk(:quasi, @tstart, @value, @raw, nil, nil, nil, 0))
      if @tail
        next_token()
        break
      next_token()
      save = @ctx
      @ctx = @ctx & C_NOIN_MASK
      exprs.push(parse_expression())
      @ctx = save
    mk(:template, s, nil, exprs, nil, nil, quasis, 0)

# ---- utilities for consumers and tests ----

# Calls blk on every JsNode child of n (in source order).
-> js_each_child(n, blk)
  js_visit_slot(n.a, blk)
  js_visit_slot(n.b, blk)
  js_visit_slot(n.c, blk)
  js_visit_slot(n.d, blk)
  js_visit_slot(n.list, blk)

-> js_visit_slot(x, blk)
  return nil if x == nil
  if x.is_a?(JsNode)
    blk.call(x)
  elsif x.is_a?(Array)
    x.each ->(y)
      blk.call(y) if y != nil && y.is_a?(JsNode)

-> js_count_nodes(n)
  c = [1]
  js_each_child(n, ->(ch) c[0] += js_count_nodes(ch))
  c[0]

# Compact S-expression for tests and debugging.
-> js_sexp(n)
  return "nil" if n == nil
  sb = StringBuffer()
  js_sexp_into(n, sb)
  sb.to_s

-> js_sexp_into(n, sb)
  if n == nil
    sb.append("_")
    return nil
  k = n.kind
  if k == :ident
    sb.append(n.str)
    return nil
  if k == :num
    v = n.a
    if v == v.floor && v.abs < ~1000000000000000.0
      sb.append(v.to_i.to_s)
    else
      sb.append(v.to_s)
    return nil
  if k == :string
    sb.append(34.chr + n.str + 34.chr)
    return nil
  sb.append("(")
  sb.append(k.to_s)
  if n.str != nil
    sb.append(" ")
    sb.append(n.str.to_s)
  if k == :regex || k == :quasi || k == :import_spec || k == :export_spec
    sb.append(" ")
    sb.append(n.a.to_s)
  else
    js_sexp_slot(n.a, sb)
  js_sexp_slot(n.b, sb)
  js_sexp_slot(n.c, sb)
  js_sexp_slot(n.d, sb)
  if n.list != nil
    sb.append(" \[")
    first = true
    n.list.each ->(x)
      sb.append(" ") if !first
      first = false
      js_sexp_into(x, sb)
    sb.append("]")
  f = n.flags & (F_PAREN - 1)
  if f != 0
    sb.append(" #")
    sb.append(f.to_s)
  sb.append(")")

-> js_sexp_slot(x, sb)
  return nil if x == nil
  sb.append(" ")
  if x.is_a?(JsNode)
    js_sexp_into(x, sb)
  elsif x.is_a?(Array)
    sb.append("\[")
    first = true
    x.each ->(y)
      sb.append(" ") if !first
      first = false
      js_sexp_into(y, sb)
    sb.append("]")
  else
    sb.append(x.to_s)
