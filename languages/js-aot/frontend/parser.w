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

# parser context bits
C_FUNC = 1
C_ASYNC = 2
C_GEN = 4
C_STRICT = 8
C_NOIN = 16
C_NOIN_MASK = 15

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

+ JsNode
  rw :kind, :pos, :fin, :str, :a, :b, :c, :d, :list, :flags
  -> new(@kind, @pos, @fin, @str, @a, @b, @c, @list, @flags)
    @d = nil

  -> has?(f)
    (@flags & f) != 0

# A function body the parser skipped (lazy parsing): its '{' offset, the offset past its
# '}', and the parser context to resume in. Kept in the function node's c slot until
# js_lazy_parse_body fills in b on the first call.
+ JsLazyBody
  rw :pos, :fin, :ctx, :module
  -> new(@pos, @fin, @ctx, @module)

+ JsParser < JsLexer
  rw :count, :lazy, :lazy_flags

  -> new(src, mod)
    super(src)
    @module = mod
    @ctx = mod ? C_STRICT : 0
    @count = 0
    @fn_acc = 0
    @fn_depth = 0
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

  -> binding_ident
    unexpected() if @tt != T_NAME
    s = @tstart
    v = @value
    next_token()
    mk(:ident, s, v, nil, nil, nil, nil, 0)

  # ---- program ----

  -> parse_program
    next_token()
    body = []
    @ctx = @ctx | C_STRICT if parse_directives(body)
    while @tt != T_EOF
      body.push(parse_item())
    flags = 0
    flags = flags | F_MODULE if @module
    flags = flags | F_STRICT if strict?()
    flags = flags | (@fn_acc & (F_USES_ARGS | F_HAS_EVAL))
    mk(:program, 0, nil, nil, nil, nil, body, flags)

  # Leading string-literal statements; returns true for "use strict".
  -> parse_directives(body)
    strict = false
    while @tt == T_STRING
      s = @tstart
      raw = @src.slice(@tstart + 1, @tend - @tstart - 2)
      st = parse_statement()
      body.push(st)
      if st.kind == :expr_stmt && st.a.kind == :string && st.a.pos == s && (st.a.flags & F_PAREN) == 0
        st.str = raw
        if raw == "use strict"
          strict = true
          @ctx = @ctx | C_STRICT
      else
        return strict
    strict

  # StatementListItem / ModuleItem
  -> parse_item
    tt = @tt
    if tt == T_IMPORT && @module
      pk = peek()
      return parse_import_decl() if pk != T_LPAREN && pk != T_DOT
    return parse_export_decl() if tt == T_EXPORT && @module
    parse_statement()

  # ---- statements ----

  -> parse_statement
    tt = @tt
    s = @tstart
    case tt
    when T_LBRACE
      return parse_block()
    when T_VAR, T_CONST
      kind = @value
      next_token()
      d = parse_var(kind, s)
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
      body = parse_statement()
      return mk(:while, s, nil, test, body, nil, nil, 0)
    when T_DO
      next_token()
      body = parse_statement()
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
        next_token()
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
      body = parse_statement()
      return mk(:with, s, nil, obj, body, nil, nil, 0)
    when T_NAME
      if !@escaped
        v = @value
        if v == "let"
          pk = peek()
          if pk == T_NAME || pk == T_LBRACK || pk == T_LBRACE || (pk >= T_BREAK && pk <= T_KW_LAST && pk != T_IN && pk != T_INSTANCEOF)
            next_token()
            d = parse_var("let", s)
            semicolon()
            d.fin = @prev_end
            return d
        elsif v == "async"
          if peek() == T_FUNCTION && !peek_nl()
            next_token()
            return parse_function(s, true, F_ASYNC)
    # expression statement or labelled statement
    e = parse_expression()
    if e.kind == :ident && @tt == T_COLON && (e.flags & F_PAREN) == 0
      next_token()
      body = parse_statement()
      return mk(:labeled, s, e.str, body, nil, nil, nil, 0)
    semicolon()
    mk(:expr_stmt, s, nil, e, nil, nil, nil, 0)

  -> parse_block
    s = @tstart
    expect(T_LBRACE)
    body = []
    while @tt != T_RBRACE
      unexpected() if @tt == T_EOF
      body.push(parse_statement())
    next_token()
    mk(:block, s, nil, nil, nil, nil, body, 0)

  # After var/let/const: declarators (no semicolon handling).
  -> parse_var(kind, s)
    decls = []
    while true
      ds = @tstart
      target = parse_binding_target()
      init = nil
      if @tt == T_ASSIGN
        next_token()
        init = parse_assign()
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
    cons = parse_statement()
    alt = nil
    if @tt == T_ELSE
      next_token()
      alt = parse_statement()
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
      if !is_decl && name_is?("let")
        pk = peek()
        is_decl = pk == T_NAME || pk == T_LBRACK || pk == T_LBRACE
      if is_decl
        ds = @tstart
        kind = @value
        next_token()
        init = parse_var(kind, ds)
      else
        init = parse_expression()
      @ctx = save
      is_of = name_is?("of")
      if is_of || @tt == T_IN
        if init.kind != :var_decl
          init = to_pattern(init, false)
        elsif init.list.size != 1
          fail("Invalid left-hand side in for-" + (is_of ? "of" : "in") + " loop: must have a single binding", init.pos)
        next_token()
        right = is_of ? parse_assign() : parse_expression()
        expect(T_RPAREN)
        body = parse_statement()
        n = mk(is_of ? :for_of : :for_in, s, nil, init, right, nil, nil, is_await ? F_AWAIT : 0)
        n.d = body
        return n
    expect(T_SEMI)
    test = @tt == T_SEMI ? nil : parse_expression()
    expect(T_SEMI)
    update = @tt == T_RPAREN ? nil : parse_expression()
    expect(T_RPAREN)
    body = parse_statement()
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
    while @tt != T_RBRACE
      cs = @tstart
      test = nil
      if @tt == T_CASE
        next_token()
        test = parse_expression()
      elsif @tt == T_DEFAULT
        next_token()
      else
        unexpected()
      expect(T_COLON)
      cons = []
      while @tt != T_CASE && @tt != T_DEFAULT && @tt != T_RBRACE
        unexpected() if @tt == T_EOF
        cons.push(parse_statement())
      cases.push(mk(:case, cs, nil, test, nil, nil, cons, 0))
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
    if @tt == T_WITH || (name_is?("assert") && !@nl)
      next_token()
      return parse_object_literal()
    nil

  -> parse_import_decl
    s = @tstart
    next_token()
    specs = []
    source = nil
    if @tt == T_STRING
      source = @value
      next_token()
    else
      if @tt == T_NAME
        ls = @tstart
        local = @value
        next_token()
        specs.push(mk(:import_spec, ls, local, "default", nil, nil, nil, 0))
        next_token() if @tt == T_COMMA
      if @tt == T_STAR
        ls = @tstart
        next_token()
        expect_name("as")
        local = binding_ident().str
        specs.push(mk(:import_spec, ls, local, "*", nil, nil, nil, 0))
      elsif @tt == T_LBRACE
        next_token()
        while @tt != T_RBRACE
          ls = @tstart
          imported = module_name()
          local = imported
          if name_is?("as")
            next_token()
            local = binding_ident().str
          specs.push(mk(:import_spec, ls, local, imported, nil, nil, nil, 0))
          break if @tt != T_COMMA
          next_token()
        expect(T_RBRACE)
      expect_name("from")
      unexpected() if @tt != T_STRING
      source = @value
      next_token()
    attrs = parse_attributes()
    semicolon()
    mk(:import_decl, s, source, nil, attrs, nil, specs, 0)

  -> parse_export_decl
    s = @tstart
    next_token()
    if @tt == T_STAR
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
      if @tt == T_FUNCTION
        decl = parse_function(ds, true, F_PAREN)
      elsif @tt == T_CLASS
        decl = parse_class(ds, true)
      elsif name_is?("async") && peek() == T_FUNCTION && !peek_nl()
        next_token()
        decl = parse_function(ds, true, F_ASYNC | F_PAREN)
      else
        decl = parse_assign()
        semicolon()
      return mk(:export_default, s, nil, decl, nil, nil, nil, 0)
    if @tt == T_LBRACE
      next_token()
      specs = []
      while @tt != T_RBRACE
        ls = @tstart
        local = module_name()
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
      semicolon()
      n = mk(:export_named, s, nil, nil, source, nil, specs, 0)
      n.c = attrs
      return n
    decl = nil
    if @tt == T_VAR || @tt == T_CONST || name_is?("let")
      ds = @tstart
      kind = @value
      next_token()
      decl = parse_var(kind, ds)
      semicolon()
    elsif @tt == T_FUNCTION
      decl = parse_function(@tstart, true, 0)
    elsif @tt == T_CLASS
      decl = parse_class(@tstart, true)
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
    if @tt == T_NAME
      name = @value
      next_token()
    elsif is_decl && (flags & F_PAREN) == 0
      unexpected()
    flags = flags & (F_ASYNC | F_GENERATOR)
    parse_function_rest(s, is_decl ? :function_decl : :function, name, flags)

  # Parameters and body; the current token is '('.
  -> parse_function_rest(s, kind, name, flags)
    save_ctx = @ctx
    save_acc = @fn_acc
    c = (@ctx & C_STRICT) | C_FUNC
    c = c | C_ASYNC if (flags & F_ASYNC) != 0
    c = c | C_GEN if (flags & F_GENERATOR) != 0
    @ctx = c
    @fn_acc = 0
    @fn_depth += 1
    params = parse_params()
    if @lazy && @tt == T_LBRACE && !pife?(s)
      lz = try_skip_body()
      if lz != nil
        # `arguments` in a parameter default counts now; the body's uses come with it
        flags = flags | (@fn_acc & F_USES_ARGS)
        @fn_depth -= 1
        @fn_acc = save_acc
        @ctx = save_ctx
        node = mk(kind, s, name, nil, nil, nil, params, flags)
        node.c = lz
        return node
    body = parse_function_body()
    flags = flags | F_STRICT if strict?()
    flags = flags | @fn_acc
    @fn_depth -= 1
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
    body = []
    parse_directives(body)
    while @tt != T_RBRACE
      unexpected() if @tt == T_EOF
      body.push(parse_item())
    next_token()
    body

  # At '=>'. params are already patterns.
  -> parse_arrow_body(s, params, flags)
    next_token()
    save_ctx = @ctx
    c = (@ctx & (C_STRICT | C_NOIN)) | C_FUNC
    c = c | C_ASYNC if (flags & F_ASYNC) != 0
    @ctx = c
    @fn_depth += 1
    body = nil
    lz = nil
    if @tt == T_LBRACE
      @ctx = @ctx & C_NOIN_MASK
      lz = try_skip_body() if @lazy && !pife?(s)
      if lz != nil
        @fn_acc = @fn_acc | F_USES_ARGS if @skip_args
      else
        body = parse_function_body()
    else
      body = parse_assign()
      flags = flags | F_EXPR_BODY
    flags = flags | F_STRICT if strict?() && lz == nil
    @fn_depth -= 1
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

  # ---- classes ----

  -> parse_class(s, is_decl)
    next_token()
    name = nil
    if @tt == T_NAME && !name_is?("extends")
      name = @value
      next_token()
    sup = nil
    if @tt == T_EXTENDS
      next_token()
      sup = parse_lhs()
    save_ctx = @ctx
    @ctx = @ctx | C_STRICT
    @ctx = @ctx & C_NOIN_MASK
    expect(T_LBRACE)
    members = []
    while @tt != T_RBRACE
      if @tt == T_SEMI
        next_token()
      else
        unexpected() if @tt == T_EOF
        members.push(parse_class_member())
    next_token()
    @ctx = save_ctx
    mk(is_decl ? :class_decl : :class, s, name, sup, nil, nil, members, 0)

  # Is the token after a get/set/static/async word a property key start
  # (rather than the word itself being the key)?
  -> modifier_follows?(pk)
    pk != T_LPAREN && pk != T_ASSIGN && pk != T_SEMI && pk != T_RBRACE && pk != T_EOF && pk != T_COMMA && pk != T_COLON

  -> parse_class_member
    s = @tstart
    flags = 0
    kind = "method"
    if name_is?("static")
      pk = peek()
      if pk == T_LBRACE
        next_token()
        save_ctx = @ctx
        save_acc = @fn_acc
        @ctx = (@ctx & C_STRICT) | C_FUNC
        @fn_depth += 1
        blk = parse_block()
        @fn_depth -= 1
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
      if modifier_follows?(pk)
        kind = @value
        next_token()
    key = parse_property_key()
    flags = flags | F_COMPUTED if @key_computed
    if @tt == T_LPAREN || fnflags != 0 || kind != "method"
      if kind == "method" && (flags & (F_STATIC | F_COMPUTED)) == 0 && (key.kind == :ident || key.kind == :string) && key.str == "constructor"
        kind = "constructor"
      func = parse_function_rest(ms, :function, nil, fnflags | F_METHOD)
      return mk(:method_def, s, kind, key, func, nil, nil, flags)
    value = nil
    if @tt == T_ASSIGN
      next_token()
      save_ctx = @ctx
      save_acc = @fn_acc
      @ctx = (@ctx & C_STRICT) | C_FUNC
      @fn_depth += 1
      value = parse_assign()
      @fn_depth -= 1
      @fn_acc = save_acc
      @ctx = save_ctx
    semicolon()
    mk(:field_def, s, nil, key, value, nil, nil, flags)

  # PropertyName or a class element name; sets @key_computed.
  -> parse_property_key
    s = @tstart
    @key_computed = false
    tt = @tt
    if tt == T_NAME || (tt >= T_BREAK && tt <= T_KW_LAST)
      v = @value
      next_token()
      return mk(:ident, s, v, nil, nil, nil, nil, 0)
    if tt == T_STRING
      v = @value
      next_token()
      return mk(:string, s, v, nil, nil, nil, nil, 0)
    if tt == T_NUM
      v = @num
      next_token()
      return mk(:num, s, nil, v, nil, nil, nil, 0)
    if tt == T_BIGINT
      v = @value
      next_token()
      return mk(:bigint, s, v, nil, nil, nil, nil, 0)
    if tt == T_PRIVATE
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
            fail("Rest element must be last element", x.pos) if i != n - 1
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
          fail("Rest element must be last element", p.pos) if i != n - 1
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
    if k == :assign_pattern || k == :array_pattern || k == :object_pattern
      return e
    if k == :rest
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
        left = to_pattern(left, false)
      else
        k = left.kind
        if k != :ident && !(k == :member && (left.flags & F_OPTIONAL) == 0)
          fail("Invalid left-hand side in assignment", left.pos)
      next_token()
      right = parse_assign()
      return mk(:assign, s, JS_TOKEN_TEXT[tt], left, right, nil, nil, 0)
    left

  -> parse_yield
    s = @tstart
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
      next_token()
      right = tt == T_STARSTAR ? parse_binary(prec - 1) : parse_binary(prec)
      kind = (tt == T_OROR || tt == T_ANDAND || tt == T_NULLISH) ? :logical : :binary
      left = mk(kind, s, JS_TOKEN_TEXT[tt], left, right, nil, nil, 0)
    left

  -> parse_unary
    tt = @tt
    s = @tstart
    if tt == T_BANG || tt == T_MINUS || tt == T_PLUS || tt == T_TILDE || tt == T_TYPEOF || tt == T_VOID || tt == T_DELETE
      next_token()
      arg = parse_unary()
      return mk(:unary, s, JS_TOKEN_TEXT[tt], arg, nil, nil, nil, 0)
    if tt == T_INC || tt == T_DEC
      next_token()
      arg = parse_unary()
      k = arg.kind
      fail("Invalid left-hand side expression in prefix operation", arg.pos) if k != :ident && k != :member
      return mk(:update, s, JS_TOKEN_TEXT[tt], arg, nil, nil, nil, F_PREFIX)
    if tt == T_NAME && @value == "await" && !@escaped && ((@ctx & C_ASYNC) != 0 || (@module && @fn_depth == 0))
      next_token()
      arg = parse_unary()
      return mk(:await, s, nil, arg, nil, nil, nil, 0)
    e = parse_lhs()
    if (@tt == T_INC || @tt == T_DEC) && !@nl
      return e if e.kind == :arrow && (e.flags & F_PAREN) == 0
      k = e.kind
      fail("Invalid left-hand side expression in postfix operation", e.pos) if k != :ident && k != :member
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
            next_token()
            param = binding_ident()
            unexpected() if @tt != T_ARROW || @nl
            return parse_arrow_body(s, [param], F_ASYNC)
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
        param = mk(:ident, s, v, nil, nil, nil, nil, 0)
        return parse_arrow_body(s, [param], 0)
      @fn_acc = @fn_acc | F_USES_ARGS if v == "arguments"
      return mk(:ident, s, v, nil, nil, nil, nil, 0)
    when T_NUM
      v = @num
      next_token()
      return mk(:num, s, nil, v, nil, nil, nil, 0)
    when T_STRING
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
        expect_name("meta")
        return mk(:meta_property, s, "import.meta", nil, nil, nil, nil, 0)
      unexpected() if @tt != T_LPAREN
      next_token()
      save = @ctx
      @ctx = @ctx & C_NOIN_MASK
      src = parse_assign()
      opts = nil
      if @tt == T_COMMA
        next_token()
        if @tt != T_RPAREN
          opts = parse_assign()
          next_token() if @tt == T_COMMA
      @ctx = save
      expect(T_RPAREN)
      return mk(:import_call, s, nil, src, opts, nil, nil, 0)
    when T_NEW
      return parse_new()
    when T_PRIVATE
      v = @value
      next_token()
      unexpected() if @tt != T_IN
      return mk(:private_name, s, v, nil, nil, nil, nil, 0)
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
        if @tt == T_ELLIPSIS
          es = @tstart
          next_token()
          arg = parse_assign()
          elems.push(mk(:spread, es, nil, arg, nil, nil, nil, 0))
        else
          elems.push(parse_assign())
        break if @tt != T_COMMA
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
      if @tt == T_ELLIPSIS
        es = @tstart
        next_token()
        arg = parse_assign()
        props.push(mk(:spread, es, nil, arg, nil, nil, nil, 0))
      else
        props.push(parse_object_member())
      break if @tt != T_COMMA
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
      if modifier_follows?(pk)
        kind = @value
        next_token()
    shorthand_ok = @tt == T_NAME
    key = parse_property_key()
    flags = @key_computed ? F_COMPUTED : 0
    if @tt == T_LPAREN || fnflags != 0 || kind != "init"
      func = parse_function_rest(s, :function, nil, fnflags | F_METHOD)
      return mk(:prop, s, kind, key, func, nil, nil, flags | F_METHOD)
    if @tt == T_COLON
      next_token()
      value = parse_assign()
      return mk(:prop, s, "init", key, value, nil, nil, flags)
    unexpected() if !shorthand_ok
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
