use core/regex/unicode
use core/regex/prefilter
use core/regex/matcher_fast
use core/regex/vm_linear

# Regex — a homegrown regular-expression engine, written in Tungsten.
#
# No external dependency (no oniguruma/PCRE): a pattern is parsed to a compact
# integer AST arena, compiled to a flat instruction program, and matched by a
# backtracking VM — the classic Thompson/Pike construction (Russ Cox, "Regular
# Expression Matching: the Virtual Machine Approach"). SPLIT gives backtracking;
# SAVE records capture-group boundaries.
#
# Orchestrator for core/regex/ (module-split pattern; the use order is the
# dependency chain):
#   unicode       case-folding, property tables, character classes, MatchData spans
#   prefilter     AST length/nullability analysis, jump/split passes, prefilter setup
#   matcher_fast  raw ASCII precheck, capture fast-paths, match_exact?, scan/gsub/split
#   vm_linear     prefilter advance, linear1/linear2 VM loops, repetition scanners
+ Regex
  # ── instruction opcodes ──
  OP_CHAR    = 1   # a = literal lexint to match
  OP_ANY     = 2   # any codepoint except newline (unless /m)
  OP_CLASS   = 3   # a = index in @classes
  OP_MATCH   = 4
  OP_JMP     = 5   # a = target pc
  OP_SPLIT   = 6   # a = pc tried first, b = pc tried on backtrack
  OP_SAVE    = 7   # a = capture slot
  OP_BOL     = 8   # ^  (start, or after \n)
  OP_EOL     = 9   # $  (end, or before \n)
  OP_WORDB   = 10  # a = 1 for \b, 0 for \B
  OP_FLAG    = 11  # a = flag bit (\d\w\s), b = 1 to negate
  OP_MARK    = 12  # a = guard slot — record sp at the top of a nullable-body loop
  OP_GUARD   = 13  # a = guard slot — fail if sp == marked sp
  OP_REP_G   = 14  # greedy X* over a single consuming op (a = body pc, b = cont pc)
  OP_REP_L   = 15  # lazy X*? over a single consuming op
  OP_REP_NB  = 16  # non-backtracking greedy X* (possessive)
  OP_RANGE   = 17  # non-negated single character range [lo..hi]: a = lo, b = hi
  OP_ICASE   = 18  # case-insensitive literal pair: a = lo_lex, b = hi_lex
  OP_CAT     = 19  # Unicode General Category / property bitmask: a = mask, b = neg
  OP_ANCHOR  = 20  # a = 1 (\A), 2 (\z), 3 (\Z), 4 (\G)
  OP_BACKREF = 21  # a = capture group index, b = 1 if ignore_case else 0
  OP_CALL       = 22  # a = target subroutine pc, b = group index
  OP_RET        = 23  # return from subroutine call
  OP_SPECIAL    = 24  # a = 1 (\R linebreak), 2 (\X extended grapheme cluster)
  OP_ASSERT     = 25  # a = after_pc, b = (min_len << 20) | (max_enc << 4) | kind (1=?, 2=!, 3=<=, 4=<!, 5=>)
  OP_ASSERT_END = 26  # a = 1 (lookbehind: check sp == @lookb_target), 0 (lookahead/atomic)
  OP_DET_SPLIT  = 27  # deterministic branch: if subj[sp] matches ops[a], consume and jump to a + 1; else jump to b

  # ── compact AST node kinds (stored in @ast_k/@ast_a/@ast_b/@ast_c/@ast_next) ──
  AST_LIT     = 1  # a = lexint
  AST_ICASE   = 2  # a = lo_lex, b = hi_lex
  AST_CAT     = 3  # a = mask, b = neg
  AST_ANY     = 4  # a = 1 if multiline (dot matches \n) else 0
  AST_CLASS   = 5  # a = index in @classes
  AST_BOL     = 6
  AST_EOL     = 7
  AST_ANCHOR  = 8  # a = mode (1=\A, 2=\z, 3=\Z, 4=\G)
  AST_KEEP    = 9
  AST_SPECIAL = 10 # a = mode (1=\R, 2=\X)
  AST_BACKREF = 11 # a = group_idx (>0) or -(ref_names_idx + 1) (<0)
  AST_SUBCALL = 12 # a = group_idx (>=0) or -(ref_names_idx + 1) (<0)
  AST_WORDB   = 13 # a = 1 (\b) or 0 (\B)
  AST_SEQ     = 14 # a = head child id (linked via @ast_next), b = count
  AST_GROUP   = 15 # a = child id, b = cap (-1 for non-capturing)
  AST_ALT     = 16 # a = head option id (linked via @ast_next), b = count
  AST_STAR    = 17 # a = child id, b = mode (0=lazy, 1=greedy, 2=possessive)
  AST_PLUS    = 18 # a = child id, b = mode (0=lazy, 1=greedy, 2=possessive)
  AST_OPT     = 19 # a = child id, b = mode (0=lazy, 1=greedy)
  AST_REP     = 20 # a = child id, b = min, c = (max < 0 ? -1 : max) * 2 + greedy
  AST_FLAG    = 21 # a = flag_bit, b = neg (1/0)
  AST_RANGE   = 22 # a = lo_lex, b = hi_lex
  AST_LOOK    = 23 # a = child id, b = kind (1=(?=), 2=(?!), 3=(?<=), 4=(?<!), 5=(?>))

  # Char classflag bits at the LSB (must match the runtime Char layout).
  FLAG_D = 1     # \d
  FLAG_W = 2     # \w
  FLAG_S = 4     # \s
  CHAR_PAYLOAD_MASK = 70368744177663 # (1 << 46) - 1; strip WValue tag/subtype

  # Special characters that .escape backslash-protects.
  SPECIALS = "\\.^$|?*+()\[]{}"

  @@last_subj_str = nil
  @@last_subj = nil
  @@last_subj_len = 0
  @@last_saved = nil
  @@last_ncap = 0
  @@last_group_names = nil
  @@literal_cache = nil
  @@ascii_lex = nil
  @@ast_k = nil
  @@ast_a = nil
  @@ast_b = nil
  @@ast_c = nil
  @@ast_next = nil
  @@group_asts = nil
  @@parse_p = nil
  @@pf_set = nil
  @@pf_seen = nil
  @@emit_op = nil
  @@emit_a = nil
  @@emit_b = nil
  @@empty_prefix = nil
  @@prop_lex_ranges = nil

  -> .ensure_ascii_lex
    if @@ascii_lex == nil
      tbl = i64[128]
      cp = 0 ## i64
      while cp < 128
        tbl[cp] = wvalue_bits(ccall("w_char_new", cp)) & 70368744177663
        cp = cp + 1
      @@ascii_lex = tbl
      @@ast_k = i64[64]
      @@ast_a = i64[64]
      @@ast_b = i64[64]
      @@ast_c = i64[64]
      @@ast_next = i64[64]
      @@group_asts = i64[32]
      @@parse_p = i64[64]
      @@pf_set = i64[64]
      @@pf_seen = i64[64]
      @@emit_op = i64[64]
      @@emit_a = i64[64]
      @@emit_b = i64[64]
      @@empty_prefix = i64[0]
    @@ascii_lex

  -> .literal(source, opts = nil)
    if @@literal_cache == nil
      @@literal_cache = {}
    key = (opts == nil || opts == "") ? source : source + "\0" + opts
    rx = @@literal_cache[key]
    if rx == nil
      rx = Regex.new(source, opts)
      @@literal_cache[key] = rx
    rx

  -> .span_from(subj, a, b)
    ccall("w_string_from_codes", subj, a, b - a)

  -> .span_from_str(subj_str, subj, a_in, b_in)
    a = a_in ## i64
    b = b_in ## i64
    if a >= b
      return ""
    if subj_str != nil
      s_str = subj_str ## string
      if s_str.ascii?()
        return s_str.slice(a, b - a)
    ccall("w_string_from_codes", subj, a_in, b_in - a_in)

  -> .last_match(key = nil)
    if @@last_saved == nil
      return nil
    saved = @@last_saved ## i64[]
    ncap = @@last_ncap ## i64
    offs = i64[ncap * 2]
    i = 0 ## i64
    while i < ncap * 2
      offs[i] = saved[i]
      i = i + 1
    gnames = @@last_group_names != nil ? @@last_group_names : {}
    subj_copy = __regex_copy_subj_if_needed(@@last_subj, @@last_subj_str, @@last_subj_len)
    m = RegexMatch.new(subj_copy, offs, gnames, @@last_subj_str, 0, 0, 0, 0)
    if key == nil
      return m
    m[key]

  -> .capture(index)
    if @@last_saved == nil
      return nil
    if (index ## i64) == 1000000
      return Regex.last_match()
    __regex_last_capture(index, @@last_saved, @@last_ncap, @@last_subj_str, @@last_subj, @@last_subj_len)

  -> new(@source, @opts = nil, @lang = nil)
    Regex.ensure_ascii_lex()
    @op = @@emit_op
    @a = @@emit_a
    @b = @@emit_b
    @op_len = 0
    @ast_k = @@ast_k
    @ast_a = @@ast_a
    @ast_b = @@ast_b
    @ast_c = @@ast_c
    @ast_next = @@ast_next
    @ast_len = 0
    @classes = nil
    @cls_bm = nil
    @cls_bm_len = 0
    @ref_names = nil
    @group_names = nil
    @group_asts = @@group_asts
    @subcalls = nil
    @ngroup = 1                 # group 0 is the whole match
    @nguard = 0                 # progress-guard slots for nullable-body loops
    @ascii_only = true
    @has_backref = false
    @has_subcall = false
    # Empty subcall stack is also needed by ordinary recursive VM spills.
    @cs_top = -1
    @has_pos_anchor = false
    @ignore_case = false
    @multiline = false
    @extended = false
    if @opts != nil && @opts != ""
      @ignore_case = @opts.include?("i")
      @multiline = @opts.include?("m")
      @extended = @opts.include?("x")
    tbl = @@ascii_lex ## i64[]
    @nl = tbl[10]               # the newline Char, for ^ $
    @nl_any = @multiline ? -1 : @nl
    ast = parse_pattern(@source) ## i64
    ga = @group_asts ## i64[]
    ga[0] = ast
    emit(OP_SAVE, 0, 0)
    compile_node(ast)
    emit(OP_SAVE, 1, 0)
    emit(OP_MATCH, 0, 0)
    if @has_subcall
      compile_subroutines()
    op_n = @op_len ## i64
    eop = @op ## i64[]
    ea = @a ## i64[]
    eb = @b ## i64[]
    ops_out = i64[op_n]
    a_out = i64[op_n]
    b_out = i64[op_n]
    oi = 0 ## i64
    while oi < op_n
      ops_out[oi] = eop[oi]
      a_out[oi] = ea[oi]
      b_out[oi] = eb[oi]
      oi = oi + 1
    @op = ops_out
    @a = a_out
    @b = b_out
    @ncap = @ngroup
    @saved = nil
    @guard = nil
    @memo = nil
    @memo_gen = 0
    @subj_buf = nil
    @subj = nil
    @subj_len = 0
    @subj_ascii = 0
    @subj_key = nil             # last subject decoded into @subj (decode cache)
    @search_from = 0
    @lookb_target = -1
    @linear = 0
    @pure_lit = 0
    @pf_exact_match = 0
    @cap_fast_kind = 0
    @lit_anchored = 0
    @pf_lit_str = nil
    @pf_lit_len = 0
    @pf_lit_bytes = 0
    @pf_lit_ptr = 0
    @pf_set_len = 0
    @lead_rep_nb = 0
    @scan_flag_mask = 0
    @lead_after_char = -1
    @lead_after_str = nil
    @req_char = find_required_lit(ast)
    compute_prefilter()         # first-char prefilter (depends only on the program)
    @ast_k = nil
    @ast_a = nil
    @ast_b = nil
    @ast_c = nil
    @ast_next = nil
    @group_asts = nil
    @p = nil

  ro :source

  -> ascii_only?
    @ascii_only

  -> options
    @opts == nil ? "" : @opts

  -> to_s
    @source

  -> new_ast(k_in, a_in, b_in, c_in)
    id = @ast_len ## i64
    ak = @ast_k ## i64[]
    if id >= ak.size()
      ast_ctx = [@ast_k, @ast_a, @ast_b, @ast_c, @ast_next]
      __regex_new_ast(k_in, a_in, b_in, c_in, ast_ctx, id)
      @ast_k = ast_ctx[0]
      @ast_a = ast_ctx[1]
      @ast_b = ast_ctx[2]
      @ast_c = ast_ctx[3]
      @ast_next = ast_ctx[4]
      @@ast_k = @ast_k
      @@ast_a = @ast_a
      @@ast_b = @ast_b
      @@ast_c = @ast_c
      @@ast_next = @ast_next
      @ast_len = id + 1
      return id
    aa = @ast_a ## i64[]
    ab = @ast_b ## i64[]
    ac = @ast_c ## i64[]
    an = @ast_next ## i64[]
    ak[id] = k_in ## i64
    aa[id] = a_in ## i64
    ab[id] = b_in ## i64
    ac[id] = c_in ## i64
    an[id] = -1
    @ast_len = id + 1
    id

  -> intern_ref_name(name)
    if @ref_names == nil
      @ref_names = []
    @ref_names.push(name)
    0 - @ref_names.size()

  # Convert a codepoint integer to its 46-bit untagged Char payload.
  -> clex_cp(cp_in)
    cp = cp_in ## i64
    if cp >= 0 && cp < 128
      tbl = @@ascii_lex ## i64[]
      return tbl[cp]
    @ascii_only = false
    __regex_clex_raw(cp)

  -> clex(ch)
    clex_cp(ch.ord())

  # Case-folding partner codepoint (e.g. 'A' <-> 'a', 'α' <-> 'Α'), or `cp` if none.
  -> fold_pair_cp(cp_in)
    cp = cp_in ## i64
    if cp >= 128
      @ascii_only = false
    __regex_fold_pair_cp(cp)

  -> downcase_cp(cp_in)
    cp = cp_in ## i64
    if cp >= 128
      @ascii_only = false
    __regex_downcase_cp(cp)

  -> upcase_cp(cp_in)
    cp = cp_in ## i64
    if cp >= 128
      @ascii_only = false
    __regex_upcase_cp(cp)

  -> downcase_lex_cp(lx_in)
    __regex_downcase_lex_cp(lx_in)

  # ── escaping (used by String#to_regex) ──
  -> .escape(str)
    __regex_escape_str(str, SPECIALS)

  -> .needs_escaping?(str)
    __regex_needs_escaping(str, SPECIALS)

  # ── instruction emit + backpatch ──
  -> emit(op_in, a_in, b_in)
    emit_ctx = [@op, @a, @b, nil]
    emit_state = i64[2]
    emit_state[0] = @op_len ## i64
    id = __regex_emit(op_in, a_in, b_in, emit_ctx, emit_state)
    @op = emit_ctx[0]
    @a = emit_ctx[1]
    @b = emit_ctx[2]
    @@emit_op = @op
    @@emit_a = @a
    @@emit_b = @b
    @op_len = emit_state[0]
    id

  # ── recursive-descent parser → compact integer AST arena ──
  -> parse_pattern(pat)
    pos_box = i64[2]
    pos_box[0] = 0
    pos_box[1] = @ascii_only ? 1 : 0
    p = __regex_decode_pattern(pat, @@parse_p, pos_box)
    @@parse_p = p
    @p = p
    @plen = pos_box[0]
    @ascii_only = pos_box[1] != 0
    @i = 0
    parse_alt()

  -> at_end?
    (@i ## i64) >= (@plen ## i64)

  -> peek_cp
    p = @p ## i64[]
    i = @i ## i64
    if i < (@plen ## i64)
      return p[i]
    -1

  -> advance_cp
    p = @p ## i64[]
    i = @i ## i64
    c = p[i] ## i64
    @i = i + 1
    c

  -> slice_pattern_cps(start_in, len_in)
    __regex_slice_pattern_cps(@p, start_in, len_in)

  # In /x (free-spacing) mode, skip unescaped whitespace and #...\n comments
  # outside of character classes.
  -> skip_ext
    if !@extended
      return nil
    p = @p ## i64[]
    n = @plen ## i64
    i = @i ## i64
    while i < n
      c = p[i] ## i64
      if c == 32 || (c >= 9 && c <= 13)
        i = i + 1
      elsif c == 35
        i = i + 1
        while i < n && p[i] != 10
          i = i + 1
      else
        break
    @i = i
    nil

  -> parse_alt
    first = parse_seq() ## i64
    if peek_cp() != 124
      return first
    head = first
    tail = first
    cnt = 1 ## i64
    ast_next = @ast_next ## i64[]
    while peek_cp() == 124
      advance_cp()
      opt = parse_seq() ## i64
      ast_next = @ast_next ## i64[]
      ast_next[tail] = opt
      tail = opt
      cnt = cnt + 1
    new_ast(AST_ALT, head, cnt, 0)

  -> parse_seq
    head = -1 ## i64
    tail = -1 ## i64
    cnt = 0 ## i64
    p = @p ## i64[]
    plen = @plen ## i64
    tbl = @@ascii_lex ## i64[]
    while true
      if @extended
        skip_ext()
      cur_i = @i ## i64
      if cur_i >= plen
        break
      c = p[cur_i] ## i64
      if c == 124 || c == 41
        break
      item = -1 ## i64
      if !@extended && !@ignore_case && c >= 0 && c < 128 && c != 40 && c != 91 && c != 46 && c != 94 && c != 36 && c != 92
        nxt_c = (cur_i + 1 < plen ? p[cur_i + 1] : -1) ## i64
        if nxt_c != 42 && nxt_c != 43 && nxt_c != 63 && nxt_c != 123
          @i = cur_i + 1
          item = new_ast(AST_LIT, tbl[c], 0, 0) ## i64
      if item < 0
        item = parse_repeat() ## i64
      if head < 0
        head = item
      else
        ast_next = @ast_next ## i64[]
        ast_next[tail] = item
      tail = item
      cnt = cnt + 1
    if cnt == 1
      return head
    new_ast(AST_SEQ, head, cnt, 0)

  -> parse_repeat
    atom = parse_atom() ## i64
    if @extended
      skip_ext()
    c = peek_cp() ## i64
    if c == 42
      advance_cp()
      g = lazy_int() ## i64
      if g == 2 && !single_consuming?(atom)
        return new_ast(AST_LOOK, new_ast(AST_STAR, atom, 1, 0), 5, 0)
      return new_ast(AST_STAR, atom, g, 0)
    if c == 43
      advance_cp()
      g = lazy_int() ## i64
      if g == 2 && !single_consuming?(atom)
        return new_ast(AST_LOOK, new_ast(AST_PLUS, atom, 1, 0), 5, 0)
      return new_ast(AST_PLUS, atom, g, 0)
    if c == 63
      advance_cp()
      g = lazy_int() ## i64
      if g == 2
        return new_ast(AST_LOOK, new_ast(AST_OPT, atom, 1, 0), 5, 0)
      return new_ast(AST_OPT, atom, g, 0)
    if c == 123
      rep = parse_brace(atom) ## i64
      if rep >= 0
        return rep
    atom

  # Returns 0 for lazy ('?'), 2 for possessive ('+'), 1 for greedy (default).
  -> lazy_int
    if @extended
      skip_ext()
    c = peek_cp() ## i64
    if c == 63
      advance_cp()
      return 0
    if c == 43
      advance_cp()
      return 2
    1

  # {n} {n,} {n,m} — returns an AST_REP node id, or -1 if it's a literal `{`.
  -> parse_brace(atom_in)
    save = @i ## i64
    advance_cp()                 # consume {
    lo = parse_int() ## i64
    if lo < 0
      @i = save
      return -1
    hi = lo
    if peek_cp() == 44
      advance_cp()
      hi = parse_int() ## i64    # -1 → unbounded
    if peek_cp() != 125
      @i = save
      return -1
    advance_cp()                 # consume }
    g = lazy_int() ## i64
    g1 = g == 0 ? 0 : 1
    c_enc = hi < 0 ? (0 - 2 + g1) : (hi * 2 + g1)
    rep_node = new_ast(AST_REP, atom_in, lo, c_enc)
    if g == 2
      return new_ast(AST_LOOK, rep_node, 5, 0)
    rep_node

  -> parse_int
    val = 0 ## i64
    count = 0 ## i64
    while !at_end?()
      c = peek_cp() ## i64
      if c >= 48 && c <= 57
        val = val * 10 + (c - 48)
        count = count + 1
        advance_cp()
      else
        break
    if count == 0
      return -1
    val

  -> parse_atom
    c = advance_cp() ## i64
    if c == 40
      return parse_group()
    if c == 91
      return parse_class()
    if c == 46
      return new_ast(AST_ANY, @multiline ? 1 : 0, 0, 0)
    if c == 94
      return new_ast(AST_BOL, 0, 0, 0)
    if c == 36
      return new_ast(AST_EOL, 0, 0, 0)
    if c == 92
      return parse_escape()
    make_lit_node(c)

  -> make_lit_node(cp_in)
    cp = cp_in ## i64
    if @ignore_case
      alt = fold_pair_cp(cp) ## i64
      if alt != cp
        lo = cp < alt ? cp : alt
        hi = cp < alt ? alt : cp
        return new_ast(AST_ICASE, clex_cp(lo), clex_cp(hi), 0)
    new_ast(AST_LIT, clex_cp(cp), 0, 0)

  -> parse_group
    saved_ic = @ignore_case
    saved_ml = @multiline
    saved_ex = @extended
    state = i64[7]
    state[0] = @i ## i64
    state[1] = -1
    state[2] = 0
    state[3] = @ngroup ## i64
    state[4] = @ignore_case ? 1 : 0
    state[5] = @multiline ? 1 : 0
    state[6] = @extended ? 1 : 0
    hdr = __regex_parse_group_header(@p, @plen, state, @source, @group_names)
    @i = state[0]
    @ignore_case = state[4] != 0
    @multiline = state[5] != 0
    @extended = state[6] != 0
    @nl_any = @multiline ? -1 : @nl
    if hdr[0] == 1
      return new_ast(AST_SEQ, -1, 0, 0)
    @group_names = hdr[1]
    cap = state[1] ## i64
    look_kind = state[2] ## i64
    @ngroup = state[3]
    child = parse_alt() ## i64
    if peek_cp() == 41
      advance_cp()
    @ignore_case = saved_ic
    @multiline = saved_ml
    @extended = saved_ex
    @nl_any = @multiline ? -1 : @nl
    if look_kind > 0
      return new_ast(AST_LOOK, child, look_kind, 0)
    if cap >= 0
      gasts = @group_asts ## i64[]
      if cap >= gasts.size()
        gcap = gasts.size() * 2
        while gcap <= cap
          gcap = gcap * 2
        gasts2 = i64[gcap]
        gi = 0 ## i64
        while gi < gasts.size()
          gasts2[gi] = gasts[gi]
          gi = gi + 1
        @group_asts = gasts2
        @@group_asts = gasts2
        gasts = gasts2
      gasts[cap] = child
    new_ast(AST_GROUP, child, cap, 0)

  -> hex_val(cp_in)
    __regex_hex_val(cp_in)

  -> parse_hex_fixed(max_digits, exact)
    pos_box = i64[2]
    pos_box[0] = @i ## i64
    val = __regex_parse_hex_fixed(@p, @plen, pos_box, max_digits, exact)
    @i = pos_box[0]
    val

  # Read a delimited name `<name>` or `'name'` for \k<...> and \g<...>.
  -> parse_bracketed_ref(kind_ch)
    pos_box = i64[2]
    pos_box[0] = @i ## i64
    name = __regex_parse_bracketed_ref(kind_ch, @p, @plen, pos_box, @source)
    @i = pos_box[0]
    name

  # Parse a single-character escape sequence after `\`, returning its codepoint
  # (>= 0), or -1 if `e` is not a single-codepoint escape.
  -> parse_escape_cp(e_in)
    pos_box = i64[2]
    pos_box[0] = @i ## i64
    val = __regex_parse_escape_cp(e_in, @p, @plen, pos_box)
    @i = pos_box[0]
    val

  # Parse \u{HEX ...} into an i64[] of codepoint integers.
  -> parse_u_braced_cps
    pos_box = i64[2]
    pos_box[0] = @i ## i64
    cps = __regex_parse_u_braced_cps(@p, @plen, pos_box)
    @i = pos_box[0]
    cps

  # Full escape parser for standalone atoms.
  -> parse_escape
    e = advance_cp() ## i64
    if e == 100
      return new_ast(AST_FLAG, FLAG_D, 0, 0)
    if e == 119
      return new_ast(AST_FLAG, FLAG_W, 0, 0)
    if e == 115
      return new_ast(AST_FLAG, FLAG_S, 0, 0)
    if e == 68
      return new_ast(AST_FLAG, FLAG_D, 1, 0)
    if e == 87
      return new_ast(AST_FLAG, FLAG_W, 1, 0)
    if e == 83
      return new_ast(AST_FLAG, FLAG_S, 1, 0)
    if e == 104 || e == 72
      hr = i64[6]
      hr[0] = clex_cp(48)
      hr[1] = clex_cp(57)
      hr[2] = clex_cp(65)
      hr[3] = clex_cp(70)
      hr[4] = clex_cp(97)
      hr[5] = clex_cp(102)
      return make_class_ast(e == 72 ? 1 : 0, 0, 0, 0, 0, hr)
    if e == 98
      return new_ast(AST_WORDB, 1, 0, 0)
    if e == 66
      return new_ast(AST_WORDB, 0, 0, 0)
    if e == 65
      return new_ast(AST_ANCHOR, 1, 0, 0)
    if e == 122
      return new_ast(AST_ANCHOR, 2, 0, 0)
    if e == 90
      return new_ast(AST_ANCHOR, 3, 0, 0)
    if e == 71
      @has_pos_anchor = true
      return new_ast(AST_ANCHOR, 4, 0, 0)
    if e == 75
      return new_ast(AST_KEEP, 0, 0, 0)
    if e == 82
      @ascii_only = false
      return new_ast(AST_SPECIAL, 1, 0, 0)
    if e == 88
      @ascii_only = false
      return new_ast(AST_SPECIAL, 2, 0, 0)
    if e == 112 || e == 80
      return parse_unicode_property(e == 80)
    if e >= 49 && e <= 57
      idx = e - 48
      while !at_end?() && peek_cp() >= 48 && peek_cp() <= 57
        nxt = idx * 10 + (peek_cp() - 48)
        if nxt < @ngroup
          idx = nxt
          advance_cp()
        else
          break
      @has_backref = true
      return new_ast(AST_BACKREF, idx, 0, 0)
    if e == 107
      name = parse_bracketed_ref("k")
      @has_backref = true
      return new_ast(AST_BACKREF, intern_ref_name(name), 0, 0)
    if e == 103
      name = parse_bracketed_ref("g")
      @has_subcall = true
      return new_ast(AST_SUBCALL, intern_ref_name(name), 0, 0)
    if e == 117 && peek_cp() == 123
      cps = parse_u_braced_cps() ## i64[]
      if cps.size() == 1
        return make_lit_node(cps[0])
      head = -1 ## i64
      tail = -1 ## i64
      ci = 0 ## i64
      while ci < cps.size()
        item = make_lit_node(cps[ci]) ## i64
        if head < 0
          head = item
        else
          ast_next = @ast_next ## i64[]
          ast_next[tail] = item
        tail = item
        ci = ci + 1
      return new_ast(AST_SEQ, head, cps.size(), 0)
    cp = parse_escape_cp(e) ## i64
    if cp >= 0
      return make_lit_node(cp)
    make_lit_node(e)

  -> normalize_prop_name(raw)
    __regex_normalize_prop_name(raw)

  -> resolve_prop_cat_mask(norm)
    __regex_resolve_prop_cat_mask(norm)

  -> resolve_prop_cp_ranges(norm)
    __regex_resolve_prop_cp_ranges(norm)

  -> read_prop_spec(neg_in)
    pos_box = i64[2]
    pos_box[0] = @i ## i64
    pos_box[1] = @ascii_only ? 1 : 0
    spec = __regex_read_prop_spec(neg_in, @p, @plen, pos_box, @source)
    @i = pos_box[0]
    @ascii_only = pos_box[1] != 0
    spec

  -> parse_unicode_property(neg_in)
    if @@prop_lex_ranges == nil
      @@prop_lex_ranges = {}
    spec = read_prop_spec(neg_in)
    pos_box = i64[2]
    pos_box[0] = @i ## i64
    pos_box[1] = @ascii_only ? 1 : 0
    res = __regex_resolve_unicode_prop(spec, @ignore_case, @@prop_lex_ranges, @@ascii_lex, pos_box)
    @ascii_only = pos_box[1] != 0
    rk = res[0] ## i64
    if rk == 5
      return make_class_ast(res[1], 0, 0, 0, 0, res[3])
    new_ast(rk, res[1], res[2], 0)

  # [abc] [a-z] [^...] with \d \w \s \h \p{...} \xNN \uNNNN \u{...} inside.
  -> parse_class
    pos_box = i64[2]
    pos_box[0] = @i ## i64
    pos_box[1] = @ascii_only ? 1 : 0
    res = __regex_parse_class_body(@p, @plen, pos_box, @source, @ignore_case, @@ascii_lex)
    @i = pos_box[0]
    @ascii_only = pos_box[1] != 0
    make_class_ast(res[0], res[1], res[2], res[3], res[4], res[5])

  -> push_class_single(ranges_in, cp_in)
    pos_box = i64[2]
    pos_box[1] = @ascii_only ? 1 : 0
    __regex_push_class_single(ranges_in, cp_in, @ignore_case, @@ascii_lex, pos_box)
    @ascii_only = pos_box[1] != 0

  -> make_class_ast(neg_in, pos_f_in, neg_f_in, pos_cat_in, neg_cat_in, ranges_in)
    out = i64[3]
    if __regex_simplify_class_ast(neg_in, pos_f_in, neg_f_in, pos_cat_in, neg_cat_in, ranges_in, out)
      return new_ast(out[0], out[1], out[2], 0)
    if @classes == nil
      @classes = []
      @cls_bm = i64[24]
    cbm = @cls_bm ## i64[]
    cbase = @cls_bm_len ## i64
    if cbase + 6 > cbm.size()
      cbm2 = i64[cbm.size() * 2]
      ci_b = 0 ## i64
      while ci_b < cbase
        cbm2[ci_b] = cbm[ci_b]
        ci_b = ci_b + 1
      @cls_bm = cbm2
      cbm = cbm2
    cls_arr = __regex_build_class_entry(neg_in, pos_f_in, neg_f_in, pos_cat_in, neg_cat_in, ranges_in, @@ascii_lex, cbm, cbase)
    @cls_bm_len = cbase + 6
    @classes.push(cls_arr)
    new_ast(AST_CLASS, (cbase / 6) ## i64, 0, 0)

  # Resolve a group reference (positive Int or negative ref_names index) to group index.
  -> resolve_group_ref(ref_in)
    __regex_resolve_group_ref(ref_in, @ngroup, @ref_names, @group_names)

  # ── compile AST → flat @op/@a/@b program ──
  -> compile_node(node_in)
    if @subcalls == nil
      @subcalls = []
    emit_ctx = [@op, @a, @b, @subcalls]
    emit_state = i64[2]
    emit_state[0] = @op_len ## i64
    emit_state[1] = @nguard ## i64
    __regex_compile_node(node_in, emit_ctx, emit_state, @ast_k, @ast_a, @ast_b, @ast_c, @ast_next, @nl, @ignore_case, @ngroup, @ref_names, @group_names)
    @op = emit_ctx[0]
    @a = emit_ctx[1]
    @b = emit_ctx[2]
    @@emit_op = @op
    @@emit_a = @a
    @@emit_b = @b
    @op_len = emit_state[0]
    @nguard = emit_state[1]

  -> ast_length_bounds(node_in)
    __regex_ast_length_bounds(node_in, @ast_k, @ast_a, @ast_b, @ast_c, @ast_next)

  -> compile_subroutines
    emit_ctx = [@op, @a, @b, @subcalls]
    emit_state = i64[2]
    emit_state[0] = @op_len ## i64
    emit_state[1] = @nguard ## i64
    __regex_compile_subroutines(emit_ctx, emit_state, @group_asts, @ast_k, @ast_a, @ast_b, @ast_c, @ast_next, @nl, @ignore_case, @ngroup, @ref_names, @group_names)
    @op = emit_ctx[0]
    @a = emit_ctx[1]
    @b = emit_ctx[2]
    @@emit_op = @op
    @@emit_a = @a
    @@emit_b = @b
    @op_len = emit_state[0]
    @nguard = emit_state[1]

  -> nullable?(node_in)
    __regex_nullable(node_in, @ast_k, @ast_a, @ast_b, @ast_next)

  -> single_consuming?(node_in)
    __regex_single_consuming(node_in, @ast_k)

  -> compile_alt(head_in)
    compile_node(head_in)

  -> compile_star(child, mode_in)
    compile_node(child)

  -> compile_plus(child, mode_in)
    compile_node(child)

  -> compile_opt(child, greedy)
    compile_node(child)

  -> compile_rep(child_in, lo_in, c_enc_in)
    compile_node(child_in)

  -> set_split(s_in, pref_in, alt_in, greedy)
    __regex_set_split(s_in, pref_in, alt_in, greedy, [@op, @a, @b])

  -> find_required_lit(node_in)
    __regex_find_required_lit(node_in, @ast_k, @ast_a, @ast_b, @ast_next)

  # ── matcher (all int ops over the Char array) ──

  -> literal_prefix
    anchored_box = i64[1]
    lit = __regex_literal_prefix(@op, @a, @b, @@empty_prefix, @multiline, anchored_box)
    @lit_anchored = anchored_box[0]
    lit

  -> branch_can_start_with?(pc_in, ch_in, depth_in)
    __regex_branch_can_start_with(pc_in, ch_in, depth_in, @op, @a, @b)

  -> can_upgrade_rep_nb?(tpc_in, npc_in, depth_in)
    __regex_can_upgrade_rep_nb(tpc_in, npc_in, depth_in, @op, @a, @b, @nl, @cls_bm, @classes)

  -> compute_prefilter
    ops = @op ## i64[]
    args_a = @a ## i64[]
    branches = @b ## i64[]
    op_n = ops.size() ## i64
    __regex_optimize_ops(ops, args_a, branches, @nl, @cls_bm, @classes)
    if !@has_pos_anchor && op_n >= 4 && ops[0] == 7 && args_a[0] == 0 && ops[2] == 16 && args_a[2] == 3 && branches[2] == 4
      if ops[1] == ops[3] && args_a[1] == args_a[3] && branches[1] == branches[3]
        @lead_rep_nb = 1
        if op_n == 6 && ops[1] == 11 && branches[1] == 0
          @scan_flag_mask = args_a[1]
        if op_n > 4 && ops[4] == 1 && !consume_at?(1, args_a[4])
          @lead_after_char = args_a[4]
    elsif !@has_pos_anchor && op_n >= 6 && ops[0] == 7 && args_a[0] == 0 && ops[1] == 7 && args_a[1] == 2 && ops[3] == 16 && args_a[3] == 4 && branches[3] == 5 && ops[5] == 7 && args_a[5] == 3
      if ops[2] == ops[4] && args_a[2] == args_a[4] && branches[2] == branches[4]
        @lead_rep_nb = 2
        if op_n > 6 && ops[6] == 1 && !consume_at?(2, args_a[6])
          @lead_after_char = args_a[6]
    elsif !@has_pos_anchor && op_n == 8 && ops[1] == 16 && ops[2] == 11 && branches[2] == 0 && ops[3] == 1 && ops[4] == 16 && ops[5] == 11 && branches[5] == 0 && (args_a[3] & args_a[2]) == 0 && (args_a[3] & args_a[5]) == 0
      @cap_fast_kind = -1
    @linear = __regex_analyze_linear_mode(ops, args_a, branches, @has_subcall)
    if @linear == 2 && @ncap == 2 && op_n == 10 && ops[0] == 7 && args_a[0] == 0 && ops[1] == 7 && args_a[1] == 2 && ops[2] == 11 && branches[2] == 0 && ops[3] == 16 && args_a[3] == 4 && branches[3] == 5 && ops[4] == 11 && args_a[4] == args_a[2] && branches[4] == 0 && ops[5] == 7 && args_a[5] == 3 && ops[6] == 1 && ops[7] == 21 && args_a[7] == 1 && branches[7] == 0 && ops[8] == 7 && args_a[8] == 1 && ops[9] == 4
      @linear = 1
      if @lit_anchored == 0
        @pf_exact_match = 16
    @pf_kind = 0
    @pf_char = 0
    @pf_flag = 0
    @pf_set = nil
    @pf_lit = nil
    lit = literal_prefix()
    if lit.size() >= 2
      @pf_lit = lit
      @pf_kind = 4
      p_lit = lit.size() ## i64
      if @ncap == 1
        if @lit_anchored == 0 && op_n == p_lit + 3
          @pure_lit = 1
        elsif @lit_anchored == 1 && op_n == p_lit + 4
          @pure_lit = 2
        elsif @lit_anchored == 1 && op_n == p_lit + 5 && ops[op_n - 3] == 20 && args_a[op_n - 3] == 2
          @pure_lit = 3
        if @pure_lit != 0
          @pf_lit_len = p_lit
          if @ascii_only && @source.ascii?() && @source.size() == p_lit
            @pf_lit_str = @source
          else
            @pf_lit_str = Regex.span_from(lit, 0, p_lit)
          @pf_lit_bytes = ccall_nobox("w_string_byte_length", @pf_lit_str) ## i64
          if (@pf_lit_bytes ## i64) >= 6
            @pf_lit_ptr = ccall_nobox("w_string_data_ptr", @pf_lit_str) ## i64
      elsif @ncap == 2 && @lit_anchored == 0 && op_n == p_lit + 8 && ops[0] == 7 && args_a[0] == 0 && ops[p_lit + 1] == 7 && args_a[p_lit + 1] == 2 && ops[p_lit + 2] == 11 && branches[p_lit + 2] == 0 && ops[p_lit + 3] == 16 && args_a[p_lit + 3] == p_lit + 4 && branches[p_lit + 3] == p_lit + 5 && ops[p_lit + 4] == 11 && args_a[p_lit + 4] == args_a[p_lit + 2] && branches[p_lit + 4] == 0 && ops[p_lit + 5] == 7 && args_a[p_lit + 5] == 3 && ops[p_lit + 6] == 7 && args_a[p_lit + 6] == 1 && ops[p_lit + 7] == 4
        @cap_fast_kind = 1
        @pf_lit_len = p_lit
        @pf_char = lit[0]
        @pf_flag = lit[p_lit - 1]
      return nil
    seen = @@pf_seen ## i64[]
    if op_n > seen.size()
      cap = seen.size() ## i64
      while cap < op_n
        cap = cap * 2
      seen = i64[cap]
      @@pf_seen = seen
    si0 = 0 ## i64
    while si0 < op_n
      seen[si0] = 0
      si0 = si0 + 1
    state = i64[15]
    state[0] = 1
    __regex_collect_first(0, seen, ops, args_a, branches, @@pf_set, @cls_bm, @classes, @ascii_only, state)
    if state[1] != 0 || state[0] == 0
      return nil
    @pf_set = __regex_classify_prefilter(ops, args_a, branches, @@pf_set, state, @lit_anchored, @lead_rep_nb, @lead_after_char, @linear, @ncap, @ascii_only)
    @pf_kind = state[0]
    @pf_char = state[1]
    @pf_flag = state[2]
    if state[3] != 0
      @pf_exact_match = state[3]
    if state[4] != 0
      @cap_fast_kind = state[4]

  -> collect_second_ascii(pc_in, depth_in, bm_in)
    __regex_collect_second_ascii(pc_in, depth_in, bm_in, @op, @a, @b)

  -> collect_first(pc_in, seen_in)
    __regex_collect_first(pc_in, seen_in, @op, @a, @b, @@pf_set, @cls_bm, @classes, @ascii_only, i64[15])

  # Decode subject into an i64[] of 46-bit Char payloads in pure Tungsten.
  # For ASCII strings, reuses @subj_buf via @@ascii_lex with zero heap allocations.
  -> decode_subject(subject)
    state = i64[2]
    buf = __regex_decode_subject(subject, @subj_buf, @@ascii_lex, state)
    @subj_len = state[0]
    @subj_ascii = state[1]
    if state[1] == 1
      @subj_buf = buf
    buf

  -> find_saved(subject)
    find_saved_from(subject, 0, 1)

  -> find_saved_from(subject, from_in, save_mode)
    start = from_in ## i64
    smode = save_mode ## i64
    @search_from = start
    if @saved == nil
      @saved = make_saved()
    saved = @saved ## i64[]
    if @pure_lit != 0 && @ascii_only
      pl_res = __regex_pure_lit_find(subject, start, @pure_lit, @pf_lit_str, @pf_lit_len, saved) ## i64
      if pl_res != -2
        if pl_res < 0
          if smode == 1
            @@last_saved = nil
            @@last_subj_str = nil
          return nil
        @subj_ascii = 1
        if smode == 1
          @@last_subj_str = subject
          @@last_subj = nil
          @@last_subj_len = pl_res
          @@last_saved = saved
          @@last_ncap = 1
          @@last_group_names = @group_names
        return saved
    pf_kind = @pf_kind ## i64
    pf_char = @pf_char ## i64
    pf_flag = @pf_flag ## i64
    pfs89 = (pf_kind == 8 || pf_kind == 9) ? (@pf_set ## i64[]) : saved
    req_char = @req_char ## i64
    lead_after_char = @lead_after_char ## i64
    if subject != @subj_key
      if subject.ascii?() && (((wvalue_bits(subject) & -2) >> 1) & 7) >= 6
        start = __regex_ascii_raw_precheck(subject, start, pf_kind, pf_char, pf_flag, @pf_lit, pfs89, req_char, @@ascii_lex) ## i64
        if start < 0
          if smode == 1
            @@last_saved = nil
            @@last_subj_str = nil
          return nil
        if pf_kind == 4 && @pure_lit == 1
          @subj_ascii = 1
          if smode != 0
            plen_raw = (@pf_lit ## i64[]).size() ## i64
            saved[0] = start
            saved[1] = start + plen_raw
            if smode == 1
              @@last_subj_str = subject
              @@last_subj = nil
              @@last_subj_len = ccall_nobox("w_string_byte_length", subject) ## i64
              @@last_saved = saved
              @@last_ncap = 1
              @@last_group_names = @group_names
          return saved
      @subj = decode_subject(subject)
      @subj_key = subject
    subj = @subj ## i64[]
    n = @subj_len ## i64
    subj_ascii = @subj_ascii ## i64
    ops = @op ## i64[]
    args_a = @a ## i64[]
    branches = @b ## i64[]
    if (@cap_fast_kind ## i64) > 0
      if __regex_cap_fast_match(@cap_fast_kind, subj, n, start, saved, args_a, @pf_lit_len, pf_char, pf_flag, @pf_lit)
        if smode == 1
          @@last_subj_str = subject
          @@last_subj = subj
          @@last_subj_len = n
          @@last_saved = saved
          @@last_ncap = (@cap_fast_kind ## i64) == 2 ? 4 : 2
          @@last_group_names = @group_names
        return saved
      if smode == 1
        @@last_saved = nil
        @@last_subj_str = nil
      return nil
    cls_bm = @cls_bm != nil ? (@cls_bm ## i64[]) : subj
    nl = @nl ## i64
    linear = @linear ## i64
    lead_rep_nb = @lead_rep_nb ## i64
    max_start = (@lit_anchored == 1 ? 0 : n) ## i64
    req_checked = req_char < 0 || pf_kind == 4
    if linear != 1
      if linear == 0 && @nguard > 0
        if @guard == nil
          @guard = i64[@nguard]
        guard = @guard ## i64[]
        gn = @nguard ## i64
        gi = 0 ## i64
        while gi < gn
          guard[gi] = -1
          gi = gi + 1
        if !@has_backref && !@has_subcall
          needed = gn * (n + 1)
          if @memo == nil || @memo.size() < needed
            @memo = i64[needed]
      sn = saved.size() ## i64
      si = 0 ## i64
      while si < sn
        saved[si] = -1
        si = si + 1
    pf_set = pf_kind == 3 ? (@pf_set ## i64[]) : subj
    pf_set_n = (pf_kind == 3 ? pf_set.size() : 0) ## i64
    pf_lit = pf_kind == 4 ? (@pf_lit ## i64[]) : subj
    pf_lit_n = (pf_kind == 4 ? pf_lit.size() : 0) ## i64
    limit = n - pf_lit_n
    first = 0 ## i64
    last = 0 ## i64
    if pf_kind == 4 && pf_lit_n > 0
      first = pf_lit[0] ## i64
      last = pf_lit[pf_lit_n - 1] ## i64
    pc = 0 ## i64
    sp = 0 ## i64
    lead_e = -1 ## i64
    orig_lead_e = -1 ## i64
    la_res = 0 ## i64
    while start <= max_start
      lead_e = -1
      if lead_after_char >= 0
        la_res = __regex_lead_after_advance(subj, n, subj_ascii, start, smode, lead_after_char, lead_rep_nb, ops, args_a, branches, cls_bm, @classes) ## i64
        if la_res < 0
          if smode == 1
            @@last_saved = nil
            @@last_subj_str = nil
          return nil
        if (la_res & 1) == 0
          start = la_res >> 1
          next
        start = la_res >> 31
        lead_e = (la_res >> 1) & 1073741823
      elsif pf_kind != 0
        start = __regex_prefilter_advance(subj, n, subj_ascii, start, max_start, pf_kind, pf_char, pf_flag, pfs89, pf_set, pf_set_n, pf_lit, pf_lit_n, limit, first, last) ## i64
        if start < 0
          if smode == 1
            @@last_saved = nil
            @@last_subj_str = nil
          return nil
        if pf_kind == 4 && @pure_lit == 1
          if smode != 0
            saved[0] = start
            saved[1] = start + pf_lit_n
            if smode == 1
              @@last_subj_str = subject
              @@last_subj = subj
              @@last_subj_len = n
              @@last_saved = saved
              @@last_ncap = 1
              @@last_group_names = @group_names
          return saved
      orig_lead_e = lead_e
      if linear == 1
        lead_e = __regex_run_linear1(subj, n, subj_ascii, start, smode, lead_after_char, lead_rep_nb, lead_e, ops, args_a, branches, cls_bm, @classes, saved, nl, @search_from) ## i64
        if lead_e == -10
          if smode == 1
            @@last_subj_str = subject
            @@last_subj = subj
            @@last_subj_len = n
            @@last_saved = saved
            @@last_ncap = @ncap
            @@last_group_names = @group_names
          return saved
      elsif linear == 2
        lead_e = __regex_run_linear2(subj, n, subj_ascii, start, smode, lead_after_char, lead_rep_nb, lead_e, ops, args_a, branches, cls_bm, @classes, saved, nl, @search_from) ## i64
        if lead_e == -10
          if smode == 1
            @@last_subj_str = subject
            @@last_subj = subj
            @@last_subj_len = n
            @@last_saved = saved
            @@last_ncap = @ncap
            @@last_group_names = @group_names
          return saved
      if linear == 0 || lead_e == -20
        if lead_e == -20
          lead_e = orig_lead_e
        if @nguard > 0 && !@has_backref && !@has_subcall
          @memo_gen = @memo_gen + 1
        if @has_subcall
          @cs_ret = i64[0]
          @cs_par = i64[0]
          @cs_grp = i64[0]
          @cs_ost = i64[0]
          @cs_top = -1
        if lead_after_char >= 0
          saved[0] = start
          if lead_rep_nb == 2
            saved[2] = start
            saved[3] = lead_e
            pc = 7
          else
            pc = 5
          sp = lead_e + 1
        else
          pc = 0
          sp = start
        if run(pc, sp, saved) >= 0
          if smode == 1
            @@last_subj_str = subject
            @@last_subj = subj
            @@last_subj_len = n
            @@last_saved = saved
            @@last_ncap = @ncap
            @@last_group_names = @group_names
          return saved
      if !req_checked
        req_checked = true
        if req_char >= 0 && pf_kind != 4
          rpos = n - 1
          while rpos > start && subj[rpos] != req_char
            rpos = rpos - 1
          if rpos <= start
            if smode == 1
              @@last_saved = nil
              @@last_subj_str = nil
            return nil
          max_start = rpos
      if lead_e > start && !@has_backref
        start = lead_e + 1
      else
        start = start + 1
    if smode == 1
      @@last_saved = nil
      @@last_subj_str = nil
    nil

  # Compatibility API: group 0 followed by numbered captures.
  -> match(subject)
    sv_tag = wvalue_bits(subject) ## i64
    if ((sv_tag >> 48) != -7 || (sv_tag & 1) != 0) && type(subject) != "String"
      @@last_saved = nil
      @@last_subj_str = nil
      return nil
    saved = find_saved_from(subject, 0, 1)
    if saved == nil
      return nil
    build_result(saved)

  # Structured capture API. Numbered and named lookup share the same saved
  # slots, and every reported offset is a half-open Unicode codepoint span.
  -> match_data(subject)
    sv_tag = wvalue_bits(subject) ## i64
    if ((sv_tag >> 48) != -7 || (sv_tag & 1) != 0) && type(subject) != "String"
      @@last_saved = nil
      @@last_subj_str = nil
      return nil
    saved = find_saved_from(subject, 0, 1)
    if saved == nil
      return nil
    nc = @ncap ## i64
    if nc <= 4 && (@@last_subj_len ## i64) < 2097150
      sv = saved ## i64[]
      p0 = ((nc << 42) | (((sv[0] + 1) & 2097151) << 21) | ((sv[1] + 1) & 2097151)) ## i64
      p1 = (nc >= 2 ? ((((sv[2] + 1) & 2097151) << 21) | ((sv[3] + 1) & 2097151)) : 0) ## i64
      p2 = 0 ## i64
      p3 = 0 ## i64
      if nc >= 3
        p2 = ((((sv[4] + 1) & 2097151) << 21) | ((sv[5] + 1) & 2097151)) ## i64
        if nc >= 4
          p3 = ((((sv[6] + 1) & 2097151) << 21) | ((sv[7] + 1) & 2097151)) ## i64
      return RegexMatch.new((@subj_ascii ## i64) == 1 ? nil : @subj, nil, @group_names, subject, p0, p1, p2, p3)
    if (@linear ## i64) == 1
      @saved = i64[nc * 2]
      return RegexMatch.new((@subj_ascii ## i64) == 1 ? nil : @subj, saved, @group_names, subject, 0, 0, 0, 0)
    RegexMatch.new((@subj_ascii ## i64) == 1 ? nil : @subj, build_offsets(saved), @group_names, subject, 0, 0, 0, 0)

  -> match?(subject)
    sv_tag = wvalue_bits(subject) ## i64
    if ((sv_tag >> 48) != -7 || (sv_tag & 1) != 0) && type(subject) != "String"
      @@last_saved = nil
      @@last_subj_str = nil
      return false
    lit_mode = @pure_lit ## i64
    if lit_mode != 0
      return __regex_pure_lit_match_p(subject, sv_tag, lit_mode, @pf_lit_str, @pf_lit_ptr, @pf_lit_bytes)
    if (@pf_exact_match ## i64) != 0
      return match_exact?(subject)
    find_saved_from(subject, 0, 0) != nil

  -> match_exact?(subject)
    if subject != @subj_key
      @subj = decode_subject(subject)
      @subj_key = subject
    res = __regex_match_exact_fast(@pf_exact_match, @subj, @subj_len, @subj_ascii, @op, @a, @b, @pf_set, @pf_char, @pf_flag, @cls_bm, @classes, @lead_after_char) ## i64
    if res >= 0
      return res == 1
    find_saved_from(subject, 0, 0) != nil

  -> =~(subject)
    sv_tag = wvalue_bits(subject) ## i64
    if ((sv_tag >> 48) != -7 || (sv_tag & 1) != 0) && type(subject) != "String"
      @@last_saved = nil
      @@last_subj_str = nil
      return false
    find_saved_from(subject, 0, 1) != nil

  -> ===(subject)
    sv_tag = wvalue_bits(subject) ## i64
    if ((sv_tag >> 48) != -7 || (sv_tag & 1) != 0) && type(subject) != "String"
      @@last_saved = nil
      @@last_subj_str = nil
      return false
    find_saved_from(subject, 0, 1) != nil

  # Structured match starting at a codepoint offset — String#scan's engine.
  -> match_data_from(subject, from)
    sv_tag = wvalue_bits(subject) ## i64
    if ((sv_tag >> 48) != -7 || (sv_tag & 1) != 0) && type(subject) != "String"
      @@last_saved = nil
      @@last_subj_str = nil
      return nil
    saved = find_saved_from(subject, from, 1)
    if saved == nil
      return nil
    nc = @ncap ## i64
    if nc <= 4 && (@@last_subj_len ## i64) < 2097150
      sv = saved ## i64[]
      p0 = (nc << 42) | (((sv[0] + 1) & 2097151) << 21) | ((sv[1] + 1) & 2097151)
      p1 = nc >= 2 ? ((((sv[2] + 1) & 2097151) << 21) | ((sv[3] + 1) & 2097151)) : 0
      p2 = nc >= 3 ? ((((sv[4] + 1) & 2097151) << 21) | ((sv[5] + 1) & 2097151)) : 0
      p3 = nc >= 4 ? ((((sv[6] + 1) & 2097151) << 21) | ((sv[7] + 1) & 2097151)) : 0
      return RegexMatch.new((@subj_ascii ## i64) == 1 ? nil : @subj, nil, @group_names, subject, p0, p1, p2, p3)
    if (@linear ## i64) == 1
      @saved = i64[nc * 2]
      return RegexMatch.new((@subj_ascii ## i64) == 1 ? nil : @subj, saved, @group_names, subject, 0, 0, 0, 0)
    RegexMatch.new((@subj_ascii ## i64) == 1 ? nil : @subj, build_offsets(saved), @group_names, subject, 0, 0, 0, 0)

  # Fast all-matches collector for String#scan without intermediate RegexMatch allocations.
  -> scan_all(subject)
    out = []
    sv_tag = wvalue_bits(subject) ## i64
    if ((sv_tag >> 48) != -7 || (sv_tag & 1) != 0) && type(subject) != "String"
      return out
    s_str = subject ## string
    mask = @scan_flag_mask ## i64
    if mask != 0
      if subject != @subj_key
        @subj = decode_subject(subject)
        @subj_key = subject
      return __regex_scan_flag_fast(s_str, @subj, @subj_len, (@subj_ascii ## i64) == 1, mask)
    is_ascii = s_str.ascii?()
    sc_pos = 0 ## i64
    ncap = @ncap ## i64
    while true
      saved = find_saved_from(subject, sc_pos, 2)
      if saved == nil
        break
      sv = saved ## i64[]
      b0 = sv[0] ## i64
      e0 = sv[1] ## i64
      if ncap > 1
        caps = []
        g = 1 ## i64
        while g < ncap
          ga = sv[g * 2] ## i64
          gb = sv[g * 2 + 1] ## i64
          if ga >= 0 && gb >= 0
            caps.push(is_ascii ? s_str.slice(ga, gb - ga) : span_str(ga, gb))
          else
            caps.push(nil)
          g = g + 1
        out.push(caps)
      else
        out.push(is_ascii ? s_str.slice(b0, e0 - b0) : span_str(b0, e0))
      if e0 == b0
        sc_pos = e0 + 1
      else
        sc_pos = e0
    out

  # Replace first regex match in subject with replacement string.
  -> sub(subject, replacement)
    sv_tag = wvalue_bits(subject) ## i64
    if ((sv_tag >> 48) != -7 || (sv_tag & 1) != 0) && type(subject) != "String"
      return subject
    saved = find_saved_from(subject, 0, 2)
    if saved == nil
      return subject
    sv = saved ## i64[]
    b0 = sv[0] ## i64
    e0 = sv[1] ## i64
    s_str = subject ## string
    if s_str.ascii?()
      slen_a = s_str.size() ## i64
      return s_str.slice(0, b0) + replacement + s_str.slice(e0, slen_a - e0)
    span_str(0, b0) + replacement + span_str(e0, @subj_len)

  # Replace all non-overlapping regex matches in subject with replacement string.
  -> gsub(subject, replacement)
    sv_tag = wvalue_bits(subject) ## i64
    if ((sv_tag >> 48) != -7 || (sv_tag & 1) != 0) && type(subject) != "String"
      return subject
    s_str = subject ## string
    mask = @scan_flag_mask ## i64
    if mask != 0
      if subject != @subj_key
        @subj = decode_subject(subject)
        @subj_key = subject
      return __regex_gsub_flag_fast(subject, s_str, replacement, @subj, @subj_len, (@subj_ascii ## i64) == 1, mask)
    is_ascii = s_str.ascii?()
    saved = find_saved_from(subject, 0, 2)
    if saved == nil
      return subject
    last_end = 0 ## i64
    sc_pos = 0 ## i64
    slen = is_ascii ? (s_str.size() ## i64) : (@subj_len ## i64)
    sb = StringBuffer(slen + 16)
    while true
      sv = saved ## i64[]
      b0 = sv[0] ## i64
      e0 = sv[1] ## i64
      if b0 > last_end
        if is_ascii
          sb.append(s_str.slice(last_end, b0 - last_end))
        else
          sb.append(span_str(last_end, b0))
      sb.append(replacement)
      last_end = e0
      if e0 == b0
        sc_pos = e0 + 1
      else
        sc_pos = e0
      if sc_pos > slen
        break
      saved = find_saved_from(subject, sc_pos, 2)
      if saved == nil
        break
    if last_end < slen
      if is_ascii
        sb.append(s_str.slice(last_end, slen - last_end))
      else
        sb.append(span_str(last_end, slen))
    sb.to_s()

  # Split subject around matches of this regex.
  -> split(subject)
    out = []
    sv_tag = wvalue_bits(subject) ## i64
    if ((sv_tag >> 48) != -7 || (sv_tag & 1) != 0) && type(subject) != "String"
      return out
    s_str = subject ## string
    if (@cap_fast_kind ## i64) == -1
      if subject != @subj_key
        @subj = decode_subject(subject)
        @subj_key = subject
      return __regex_split_delim_fast(s_str, @subj, @subj_len, (@subj_ascii ## i64) == 1, @a)
    is_ascii = s_str.ascii?()
    saved = find_saved_from(subject, 0, 2)
    if saved == nil
      out.push(subject)
      return out
    last_end = 0 ## i64
    sc_pos = 0 ## i64
    slen = is_ascii ? (s_str.size() ## i64) : (@subj_len ## i64)
    while true
      sv = saved ## i64[]
      b0 = sv[0] ## i64
      e0 = sv[1] ## i64
      if e0 == b0 && b0 == last_end
        sc_pos = e0 + 1
      else
        out.push(is_ascii ? s_str.slice(last_end, b0 - last_end) : span_str(last_end, b0))
        last_end = e0
        if e0 == b0
          sc_pos = e0 + 1
        else
          sc_pos = e0
      if sc_pos > slen
        break
      saved = find_saved_from(subject, sc_pos, 2)
      if saved == nil
        break
    out.push(is_ascii ? s_str.slice(last_end, slen - last_end) : span_str(last_end, slen))
    out

  -> make_saved
    n = (@ncap * 2) ## i64
    s = i64[n]
    i = 0 ## i64
    while i < n
      s[i] = -1
      i = i + 1
    s

  -> build_result(saved_in)
    saved = saved_in ## i64[]
    ncap = @ncap ## i64
    out = []
    g = 0 ## i64
    while g < ncap
      a = saved[g * 2] ## i64
      b = saved[g * 2 + 1] ## i64
      if a >= 0 && b >= 0
        out.push(span_str(a, b))
      else
        out.push(nil)
      g = g + 1
    out

  -> build_offsets(saved_in)
    saved = saved_in ## i64[]
    n = saved.size() ## i64
    out = i64[n]
    i = 0 ## i64
    while i < n
      out[i] = saved[i]
      i = i + 1
    out

  -> span_str(a, b)
    Regex.span_from_str(@subj_key != nil ? @subj_key : @@last_subj_str, @subj, a, b)

  # Backtracking VM: returns the end position on success, or -1.
  -> run(pc_in, sp_in, saved_in)
    vm_state = i64[2]
    vm_state[0] = @lookb_target ## i64
    vm_state[1] = @has_subcall ? (@cs_top ## i64) : -1
    cs_ctx = @has_subcall ? [@cs_ret, @cs_par, @cs_grp, @cs_ost] : nil
    r = __regex_vm_run(pc_in, sp_in, saved_in, @subj, @subj_len, @subj_ascii, @op, @a, @b, @guard, @cls_bm, @classes, @nl, @search_from, @ncap, @has_backref, @has_subcall, @memo, @memo_gen, cs_ctx, vm_state) ## i64
    @lookb_target = vm_state[0]
    if @has_subcall
      @cs_ret = cs_ctx[0]
      @cs_par = cs_ctx[1]
      @cs_grp = cs_ctx[2]
      @cs_ost = cs_ctx[3]
      @cs_top = vm_state[1]
    r

  -> eval_lookbehind(pc_in, sp_in, saved_in)
    run(pc_in, sp_in, saved_in) >= 0

  -> run_assert_cap(pc_in, sp_in, saved_in)
    run(pc_in, sp_in, saved_in)

  -> match_backref(g_in, icase_in, sp_in, saved_in)
    __regex_match_backref(g_in, icase_in, sp_in, saved_in, @subj, @subj_len)

  -> match_special(mode_in, sp_in)
    __regex_match_special(mode_in, sp_in, @subj, @subj_len)

  -> at_word_boundary?(sp_in)
    subj = @subj ## i64[]
    sp = sp_in ## i64
    n = @subj_len ## i64
    (sp > 0 && (subj[sp - 1] & 2) != 0) != (sp < n && (subj[sp] & 2) != 0)

  -> word_lex?(lx_in)
    ((lx_in ## i64) & 2) != 0

  -> cat_match?(mask_in, neg_in, ch_in)
    __regex_cat_match(mask_in, neg_in, ch_in)

  -> consume_at?(pc_in, ch_in)
    __regex_consume_at(pc_in, ch_in, @op, @a, @b, @cls_bm, @classes)

  -> class_match_slow?(c_in, lx_in)
    __regex_class_match_slow(c_in, lx_in)

  -> class_match?(cls_in, lx_in)
    __regex_class_match(cls_in, lx_in, @cls_bm, @classes)

  -> set_match?(s, lx_in)
    __regex_set_match(s, lx_in)

# RegexMatch — structured numbered/named captures and codepoint spans.
+ RegexMatch
  -> new(@subj, @offsets, @name_to_group, @subject, @p0, @p1, @p2, @p3)
    nil

  -> group_index(key)
    __regex_match_group_index(key, @name_to_group)

  -> span_str(a_in, b_in)
    a = a_in ## i64
    b = b_in ## i64
    if a >= b
      return ""
    if @subj == nil
      s_str = @subject ## string
      return s_str.slice(a, b - a)
    Regex.span_from(@subj, a, b)

  -> string
    if @subject != nil
      return @subject
    slen = @subj != nil ? ((@subj ## i64[]).size() ## i64) : 0
    span_str(0, slen)

  -> pre_match
    a = self.begin_offset(0)
    if a == nil
      return nil
    span_str(0, a)

  -> post_match
    b = self.end_offset(0)
    if b == nil
      return nil
    if @subj != nil
      slen = (@subj ## i64[]).size() ## i64
    else
      s_str = @subject ## string
      slen = s_str.size() ## i64
    span_str(b, slen)

  -> [](key)
    kbits = wvalue_bits(key) ## i64
    ktag = (kbits >> 48) ## i64
    idx = 0 ## i64
    if ktag == -6
      idx = key ## i64
    elsif ktag == -7 && (kbits & 1) == 0
      if @name_to_group == nil
        return nil
      ntg = @name_to_group ## hash
      index = ntg[key]
      if index == nil
        return nil
      idx = index ## i64
    else
      index = group_index(key)
      if index == nil
        return nil
      idx = index ## i64
    if @offsets == nil
      p0 = @p0 ## i64
      ng = (p0 >> 42) ## i64
      if idx < 0
        idx = idx + ng
      if idx < 0 || idx >= ng
        return nil
      pk = (idx == 0 ? p0 : (idx == 1 ? (@p1 ## i64) : (idx == 2 ? (@p2 ## i64) : (@p3 ## i64)))) ## i64
      a = (((pk >> 21) & 2097151) - 1) ## i64
      b = ((pk & 2097151) - 1) ## i64
    else
      offs = @offsets ## i64[]
      ng = (offs.size() >> 1) ## i64
      if idx < 0
        idx = idx + ng
      if idx < 0 || idx >= ng
        return nil
      a = offs[idx * 2] ## i64
      b = offs[idx * 2 + 1] ## i64
    if a < 0 || b < 0
      return nil
    if a >= b
      return ""
    if @subj == nil
      s_str = @subject ## string
      return s_str.slice(a, b - a)
    Regex.span_from(@subj, a, b)

  -> offset(key)
    index = group_index(key)
    if index == nil
      return nil
    idx = index ## i64
    if @offsets == nil
      p0 = @p0 ## i64
      ng = (p0 >> 42) ## i64
      if idx < 0
        idx = idx + ng
      if idx < 0 || idx >= ng
        return nil
      pk = (idx == 0 ? p0 : (idx == 1 ? (@p1 ## i64) : (idx == 2 ? (@p2 ## i64) : (@p3 ## i64)))) ## i64
      a = (((pk >> 21) & 2097151) - 1) ## i64
      b = ((pk & 2097151) - 1) ## i64
    else
      offs = @offsets ## i64[]
      ng = offs.size() >> 1
      if idx < 0
        idx = idx + ng
      if idx < 0 || idx >= ng
        return nil
      a = offs[idx * 2] ## i64
      b = offs[idx * 2 + 1] ## i64
    if a < 0 || b < 0
      return nil
    [a, b]

  -> begin_offset(key = 0)
    index = group_index(key)
    if index == nil
      return nil
    idx = index ## i64
    if @offsets == nil
      p0 = @p0 ## i64
      ng = (p0 >> 42) ## i64
      if idx < 0
        idx = idx + ng
      if idx < 0 || idx >= ng
        return nil
      pk = (idx == 0 ? p0 : (idx == 1 ? (@p1 ## i64) : (idx == 2 ? (@p2 ## i64) : (@p3 ## i64)))) ## i64
      a = (((pk >> 21) & 2097151) - 1) ## i64
    else
      offs = @offsets ## i64[]
      ng = offs.size() >> 1
      if idx < 0
        idx = idx + ng
      if idx < 0 || idx >= ng
        return nil
      a = offs[idx * 2] ## i64
    if a < 0
      return nil
    a

  -> end_offset(key = 0)
    index = group_index(key)
    if index == nil
      return nil
    idx = index ## i64
    if @offsets == nil
      p0 = @p0 ## i64
      ng = (p0 >> 42) ## i64
      if idx < 0
        idx = idx + ng
      if idx < 0 || idx >= ng
        return nil
      pk = (idx == 0 ? p0 : (idx == 1 ? (@p1 ## i64) : (idx == 2 ? (@p2 ## i64) : (@p3 ## i64)))) ## i64
      b = ((pk & 2097151) - 1) ## i64
    else
      offs = @offsets ## i64[]
      ng = offs.size() >> 1
      if idx < 0
        idx = idx + ng
      if idx < 0 || idx >= ng
        return nil
      b = offs[idx * 2 + 1] ## i64
    if b < 0
      return nil
    b

  -> match
    self[0]

  -> size
    if @offsets == nil
      return (@p0 ## i64) >> 42
    offs = @offsets ## i64[]
    offs.size() >> 1

  -> captures
    out = []
    i = 1
    n = self.size()
    while i < n
      out.push(self[i])
      i = i + 1
    out

  -> names
    if @name_to_group == nil
      return []
    @name_to_group.keys()

  -> named_captures
    out = {}
    ns = self.names()
    i = 0
    while i < ns.size()
      name = ns[i]
      out[name] = self[name]
      i = i + 1
    out

  -> named_offsets
    out = {}
    ns = self.names()
    i = 0
    while i < ns.size()
      name = ns[i]
      out[name] = self.offset(name)
      i = i + 1
    out

  -> to_a
    out = []
    i = 0
    n = self.size()
    while i < n
      out.push(self[i])
      i = i + 1
    out

  -> to_s
    self.match()
