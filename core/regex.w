# Regex — a homegrown regular-expression engine, written in Tungsten.
#
# No external dependency (no oniguruma/PCRE): a pattern is parsed to a compact
# integer AST arena, compiled to a flat instruction program, and matched by a
# backtracking VM — the classic Thompson/Pike construction (Russ Cox, "Regular
# Expression Matching: the Virtual Machine Approach"). SPLIT gives backtracking;
# SAVE records capture-group boundaries.
#
# UTF-8 / codepoints: String#codes decodes each character to a tagged Char word.
# The regex VM strips only the tag/subtype bits and keeps its 46-bit payload in
# an i64[]: the codepoint remains in bits 25-45, so raw `==` and `<` order by
# codepoint, while the \d (bit0), \w (bit1), \s (bit2), General Category
# (bits 3-7), printable (bit 23), and emoji (bit 24) flags remain O(1) bit
# tests. Keeping the payload below 2^46 also prevents typed-array reads from
# promoting tagged Char words to BigInt in the hot loop.
#
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
    subj_copy = nil
    if @@last_subj != nil && (@@last_subj_str == nil || !@@last_subj_str.ascii?())
      n = @@last_subj_len ## i64
      sc = i64[n]
      si = 0 ## i64
      src = @@last_subj ## i64[]
      while si < n
        sc[si] = src[si]
        si = si + 1
      subj_copy = sc
    m = RegexMatch.new(subj_copy, offs, gnames, @@last_subj_str, 0, 0, 0, 0)
    if key == nil
      return m
    m[key]

  -> .capture(index)
    if @@last_saved == nil
      return nil
    idx = index ## i64
    if idx == 1000000
      return Regex.last_match()
    saved = @@last_saved ## i64[]
    ncap = @@last_ncap ## i64
    if idx == 1000001
      a = saved[0] ## i64
      if a < 0
        return nil
      return Regex.span_from_str(@@last_subj_str, @@last_subj, 0, a)
    if idx == 1000002
      b = saved[1] ## i64
      if b < 0
        return nil
      return Regex.span_from_str(@@last_subj_str, @@last_subj, b, @@last_subj_len)
    if idx == 1000003
      g = ncap - 1
      while g >= 1
        ga = saved[g * 2] ## i64
        gb = saved[g * 2 + 1] ## i64
        if ga >= 0 && gb >= 0
          return Regex.span_from_str(@@last_subj_str, @@last_subj, ga, gb)
        g = g - 1
      return nil
    if idx < 0 || idx >= ncap
      return nil
    a = saved[idx * 2] ## i64
    b = saved[idx * 2 + 1] ## i64
    if a < 0 || b < 0
      return nil
    Regex.span_from_str(@@last_subj_str, @@last_subj, a, b)

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
      cap = ak.size() * 2
      ak2 = i64[cap]
      aa2 = i64[cap]
      ab2 = i64[cap]
      ac2 = i64[cap]
      an2 = i64[cap]
      aa0 = @ast_a ## i64[]
      ab0 = @ast_b ## i64[]
      ac0 = @ast_c ## i64[]
      an0 = @ast_next ## i64[]
      i = 0 ## i64
      while i < id
        ak2[i] = ak0_v = ak[i]
        aa2[i] = aa0[i]
        ab2[i] = ab0[i]
        ac2[i] = ac0[i]
        an2[i] = an0[i]
        i = i + 1
      @ast_k = ak2
      @ast_a = aa2
      @ast_b = ab2
      @ast_c = ac2
      @ast_next = an2
      @@ast_k = ak2
      @@ast_a = aa2
      @@ast_b = ab2
      @@ast_c = ac2
      @@ast_next = an2
      ak = ak2
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
    wvalue_bits(ccall("w_char_new", cp)) & 70368744177663

  -> clex(ch)
    clex_cp(ch.ord())

  # Case-folding partner codepoint (e.g. 'A' <-> 'a', 'α' <-> 'Α'), or `cp` if none.
  -> fold_pair_cp(cp_in)
    cp = cp_in ## i64
    if cp >= 65 && cp <= 90
      return cp + 32
    if cp >= 97 && cp <= 122
      return cp - 32
    if cp < 128
      return cp
    lx = clex_cp(cp) ## i64
    cat = (lx >> 3) & 31
    if cat != 0 && cat != 1 && cat != 2
      return cp
    raw = (lx >> 10) & 511
    delta = raw >= 256 ? raw - 512 : raw
    if delta == 0 || delta == -256
      return cp
    cp + delta

  -> downcase_cp(cp_in)
    cp = cp_in ## i64
    if cp >= 65 && cp <= 90
      return cp + 32
    if cp < 128
      return cp
    lx = clex_cp(cp) ## i64
    cat = (lx >> 3) & 31
    if cat != 0 && cat != 2
      return cp
    raw = (lx >> 10) & 511
    delta = raw >= 256 ? raw - 512 : raw
    if delta == 0 || delta == -256
      return cp
    cp + delta

  -> upcase_cp(cp_in)
    cp = cp_in ## i64
    if cp >= 97 && cp <= 122
      return cp - 32
    if cp < 128
      return cp
    lx = clex_cp(cp) ## i64
    cat = (lx >> 3) & 31
    if cat == 2
      return cp - 1
    if cat != 1
      return cp
    raw = (lx >> 10) & 511
    delta = raw >= 256 ? raw - 512 : raw
    if delta == 0 || delta == -256
      return cp
    cp + delta

  -> downcase_lex_cp(lx_in)
    lx = lx_in ## i64
    cp = (lx >> 25) & 2097151
    cat = (lx >> 3) & 31
    if cat != 0 && cat != 2
      return cp
    raw = (lx >> 10) & 511
    delta = raw >= 256 ? raw - 512 : raw
    if delta == 0 || delta == -256
      return cp
    cp + delta

  # ── escaping (used by String#to_regex) ──
  -> .escape(str)
    out = ""
    cs = str.chars()
    i = 0
    while i < cs.size()
      c = cs[i]
      if SPECIALS.include?(c)
        out = out + "\\" + c
      else
        out = out + c
      i = i + 1
    out

  -> .needs_escaping?(str)
    cs = str.chars()
    i = 0
    while i < cs.size()
      if SPECIALS.include?(cs[i])
        return true
      i = i + 1
    false

  # ── instruction emit + backpatch ──
  -> emit(op_in, a_in, b_in)
    id = @op_len ## i64
    ops = @op ## i64[]
    if id >= ops.size()
      cap = (ops.size() * 2) ## i64
      ops2 = i64[cap]
      aa2 = i64[cap]
      bb2 = i64[cap]
      aa0 = @a ## i64[]
      bb0 = @b ## i64[]
      i = 0 ## i64
      while i < id
        ops2[i] = ops[i]
        aa2[i] = aa0[i]
        bb2[i] = bb0[i]
        i = i + 1
      @op = ops2
      @a = aa2
      @b = bb2
      @@emit_op = ops2
      @@emit_a = aa2
      @@emit_b = bb2
      ops = ops2
    aa = @a ## i64[]
    bb = @b ## i64[]
    ops[id] = op_in ## i64
    aa[id] = a_in ## i64
    bb[id] = b_in ## i64
    @op_len = id + 1
    id

  # ── recursive-descent parser → compact integer AST arena ──
  -> parse_pattern(pat)
    p = @@parse_p ## i64[]
    if pat.ascii?()
      pv = (wvalue_bits(pat) & -2) ## i64
      pmode = (pv >> 1) & 7
      if pmode <= 5
        i = 0 ## i64
        while i < pmode
          p[i] = (pv >> (4 + 8 * i)) & 255
          i = i + 1
        @p = p
        @plen = pmode
      else
        n = ccall_nobox("w_string_byte_length", pat) ## i64
        if n > p.size()
          cap = p.size() ## i64
          while cap < n
            cap = cap * 2
          p = i64[cap]
          @@parse_p = p
        ptr = ccall_nobox("w_string_data_ptr", pat) ## i64
        i = 0 ## i64
        while i < n
          p[i] = raw_load_u8(ptr, i)
          i = i + 1
        @p = p
        @plen = n
    else
      @ascii_only = false
      codes = pat.codes() ## i64[]
      n = codes.size() ## i64
      if n > p.size()
        cap = p.size() ## i64
        while cap < n
          cap = cap * 2
        p = i64[cap]
        @@parse_p = p
      i = 0 ## i64
      while i < n
        p[i] = (codes[i] >> 25) & 2097151
        i = i + 1
      @p = p
      @plen = n
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
    p = @p ## i64[]
    s = start_in ## i64
    e = s + (len_in ## i64)
    out = ""
    while s < e
      out = out + Char.new(p[s]).to_s()
      s = s + 1
    out

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
    cap = -1 ## i64
    look_kind = 0 ## i64
    saved_ic = @ignore_case
    saved_ml = @multiline
    saved_ex = @extended
    if peek_cp() == 63
      advance_cp()
      form = advance_cp() ## i64
      if form == 61
        look_kind = 1            # (?=...) positive lookahead
      elsif form == 33
        look_kind = 2            # (?!...) negative lookahead
      elsif form == 62
        look_kind = 5            # (?>...) atomic group
      elsif form == 35
        while !at_end?() && peek_cp() != 41
          advance_cp()
        if peek_cp() == 41
          advance_cp()
        return new_ast(AST_SEQ, -1, 0, 0)
      elsif form == 60
        if peek_cp() == 61
          advance_cp()
          look_kind = 3          # (?<=...) positive lookbehind
        elsif peek_cp() == 33
          advance_cp()
          look_kind = 4          # (?<!...) negative lookbehind
        else
          nstart = @i ## i64
          if at_end?()
            raise "invalid named regex capture"
          fc = peek_cp() ## i64
          if !((fc >= 97 && fc <= 122) || (fc >= 65 && fc <= 90) || fc == 95)
            raise "invalid named regex capture"
          while !at_end?() && peek_cp() != 62
            nc = advance_cp() ## i64
            if !((nc >= 97 && nc <= 122) || (nc >= 65 && nc <= 90) || (nc >= 48 && nc <= 57) || nc == 95)
              raise "invalid named regex capture"
          nlen = (@i ## i64) - nstart
          if peek_cp() != 62 || nlen == 0
            raise "invalid named regex capture"
          advance_cp()
          name = @source.ascii?() ? @source.slice(nstart, nlen) : slice_pattern_cps(nstart, nlen)
          if @group_names == nil
            @group_names = {}
          elsif @group_names.has_key?(name)
            raise "duplicate named regex capture: " + name
          cap = @ngroup ## i64
          @ngroup = cap + 1
          @group_names[name] = cap
      elsif form == 105 || form == 109 || form == 120 || form == 45
        neg_flag = false
        cur_f = form
        while true
          if cur_f == 45
            neg_flag = true
          elsif cur_f == 105
            @ignore_case = !neg_flag
          elsif cur_f == 109
            @multiline = !neg_flag
            @nl_any = @multiline ? -1 : @nl
          elsif cur_f == 120
            @extended = !neg_flag
          else
            raise "unsupported regex group flag: " + Char.new(cur_f).to_s()
          if peek_cp() == 41
            advance_cp()
            return new_ast(AST_SEQ, -1, 0, 0)
          if peek_cp() == 58
            advance_cp()
            break
          if at_end?()
            raise "unterminated inline flag group in regex"
          cur_f = advance_cp() ## i64
      elsif form != 58
        raise "unsupported regex group form: ?" + Char.new(form).to_s()
    else
      cap = @ngroup ## i64
      @ngroup = cap + 1
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
    c = cp_in ## i64
    if c >= 48 && c <= 57
      return c - 48
    if c >= 65 && c <= 70
      return c - 55
    if c >= 97 && c <= 102
      return c - 87
    -1

  -> parse_hex_fixed(max_digits, exact)
    val = 0 ## i64
    cnt = 0 ## i64
    while cnt < max_digits && !at_end?()
      hv = hex_val(peek_cp()) ## i64
      if hv < 0
        break
      val = (val << 4) | hv
      advance_cp()
      cnt = cnt + 1
    if exact && cnt != max_digits
      raise "invalid hex/unicode escape in regex"
    if cnt == 0
      raise "invalid hex escape in regex"
    val

  # Read a delimited name `<name>` or `'name'` for \k<...> and \g<...>.
  -> parse_bracketed_ref(kind_ch)
    if at_end?()
      raise "unterminated \\" + kind_ch + " reference in regex"
    open = advance_cp() ## i64
    close = 0 ## i64
    if open == 60
      close = 62
    elsif open == 39
      close = 39
    else
      raise "expected '<' or \"'\" after \\" + kind_ch + " in regex"
    nstart = @i ## i64
    while !at_end?() && peek_cp() != close
      advance_cp()
    nlen = (@i ## i64) - nstart
    if peek_cp() != close || nlen == 0
      raise "unterminated \\" + kind_ch + " reference in regex"
    advance_cp()
    @source.ascii?() ? @source.slice(nstart, nlen) : slice_pattern_cps(nstart, nlen)

  # Parse a single-character escape sequence after `\`, returning its codepoint
  # (>= 0), or -1 if `e` is not a single-codepoint escape.
  -> parse_escape_cp(e_in)
    e = e_in ## i64
    if e == 110
      return 10                  # \n (LF)
    if e == 116
      return 9                   # \t (TAB)
    if e == 114
      return 13                  # \r (CR)
    if e == 97
      return 7                   # \a (BEL, 0x07)
    if e == 101
      return 27                  # \e (ESC, 0x1B)
    if e == 102
      return 12                  # \f (FF, 0x0C)
    if e == 118
      return 11                  # \v (VT, 0x0B)
    if e == 48
      val = 0 ## i64
      cnt = 0 ## i64
      while cnt < 2 && !at_end?()
        oc = peek_cp() ## i64
        if oc >= 48 && oc <= 55
          val = (val << 3) | (oc - 48)
          advance_cp()
          cnt = cnt + 1
        else
          break
      return val
    if e == 120
      if peek_cp() == 123
        advance_cp()
        val = parse_hex_fixed(6, false)
        if peek_cp() != 125
          raise "unterminated \\x{...} escape in regex"
        advance_cp()
        return val
      return parse_hex_fixed(2, false)
    if e == 117
      if peek_cp() != 123
        return parse_hex_fixed(4, true)
      return -1
    if e == 99 || (e == 67 && peek_cp() == 45)
      if e == 67
        advance_cp()
      if at_end?()
        raise "incomplete \\c control escape in regex"
      x = advance_cp() ## i64
      if x == 92 && !at_end?()
        x = advance_cp() ## i64
      if x == 63
        return 127
      return x & 31
    -1

  # Parse \u{HEX ...} into an i64[] of codepoint integers.
  -> parse_u_braced_cps
    advance_cp()                 # consume '{'
    cps = i64[0]
    while !at_end?()
      while !at_end?() && (peek_cp() == 32 || peek_cp() == 9)
        advance_cp()
      if peek_cp() == 125
        break
      cp = parse_hex_fixed(6, false)
      cps.push(cp)
      while !at_end?() && (peek_cp() == 32 || peek_cp() == 9)
        advance_cp()
      if peek_cp() == 125
        break
    if peek_cp() != 125 || cps.size() == 0
      raise "invalid \\u{...} escape in regex"
    advance_cp()                 # consume '}'
    cps

  # Full escape parser for standalone atoms.
  -> parse_escape
    e = advance_cp() ## i64
    # Shorthand character classes: \d \w \s \D \W \S -> direct AST_FLAG (zero allocs!)
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
    # Hex digit shorthands: \h \H
    if e == 104 || e == 72
      hr = i64[6]
      hr[0] = clex_cp(48)
      hr[1] = clex_cp(57)
      hr[2] = clex_cp(65)
      hr[3] = clex_cp(70)
      hr[4] = clex_cp(97)
      hr[5] = clex_cp(102)
      return make_class_ast(e == 72 ? 1 : 0, 0, 0, 0, 0, hr)
    # Word boundaries: \b \B
    if e == 98
      return new_ast(AST_WORDB, 1, 0, 0)
    if e == 66
      return new_ast(AST_WORDB, 0, 0, 0)
    # String / match anchors and keep: \A \z \Z \G \K
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
    # Unicode linebreak \R and extended grapheme cluster \X
    if e == 82
      @ascii_only = false
      return new_ast(AST_SPECIAL, 1, 0, 0)
    if e == 88
      @ascii_only = false
      return new_ast(AST_SPECIAL, 2, 0, 0)
    # Unicode properties: \p{...} and \P{...}
    if e == 112 || e == 80
      return parse_unicode_property(e == 80)
    # Numbered backreferences: \1 .. \9
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
    # Named backreference: \k<name> or \k'name'
    if e == 107
      name = parse_bracketed_ref("k")
      @has_backref = true
      return new_ast(AST_BACKREF, intern_ref_name(name), 0, 0)
    # Subexpression / subroutine call: \g<name> or \g'name'
    if e == 103
      name = parse_bracketed_ref("g")
      @has_subcall = true
      return new_ast(AST_SUBCALL, intern_ref_name(name), 0, 0)
    # \u{HEX ...} (one or more space-separated codepoints)
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
    s = ""
    cs = raw.chars()
    i = 0
    while i < cs.size()
      c = cs[i]
      if c != " " && c != "\t" && c != "_" && c != "-"
        s = s + c.downcase()
      i = i + 1
    if s.starts_with?("generalcategory=")
      s = s.slice(16, s.size() - 16)
    elsif s.starts_with?("gc=")
      s = s.slice(3, s.size() - 3)
    elsif s.starts_with?("script=")
      s = s.slice(7, s.size() - 7)
    elsif s.starts_with?("sc=")
      s = s.slice(3, s.size() - 3)
    elsif s.starts_with?("block=")
      s = "in" + s.slice(6, s.size() - 6)
    elsif s.starts_with?("blk=")
      s = "in" + s.slice(4, s.size() - 4)
    elsif s.starts_with?("is") && s.size() > 2
      s = s.slice(2, s.size() - 2)
    s

  -> resolve_prop_cat_mask(norm)
    case norm
    when "lu", "uppercaseletter", "upper", "uppercase" then 1
    when "ll", "lowercaseletter", "lower", "lowercase" then 2
    when "lt", "titlecaseletter" then 4
    when "lm", "modifierletter" then 8
    when "lo", "otherletter" then 16
    when "lc", "casedletter" then 7
    when "l", "letter", "alpha", "alphabetic" then 31
    when "nd", "decimalnumber", "digit" then 32
    when "nl", "letternumber" then 64
    when "no", "othernumber" then 128
    when "n", "number" then 224
    when "alnum" then 63
    when "zs", "spaceseparator" then 256
    when "zl", "lineseparator" then 512
    when "zp", "paragraphseparator" then 1024
    when "z", "separator" then 1792
    when "mn", "nonspacingmark" then 2048
    when "mc", "spacingmark" then 4096
    when "me", "enclosingmark" then 8192
    when "m", "mark", "combiningmark" then 14336
    when "pc", "connectorpunctuation" then 16384
    when "pd", "dashpunctuation" then 32768
    when "ps", "openpunctuation" then 65536
    when "pe", "closepunctuation" then 131072
    when "pi", "initialpunctuation", "initialquotepunctuation" then 262144
    when "pf", "finalpunctuation", "finalquotepunctuation" then 524288
    when "po", "otherpunctuation" then 1048576
    when "p", "punct", "punctuation" then 2080768
    when "sm", "mathsymbol" then 2097152
    when "sc", "currencysymbol" then 4194304
    when "sk", "modifiersymbol" then 8388608
    when "so", "othersymbol" then 16777216
    when "s", "symbol" then 31457280
    when "cc", "control", "cntrl" then 33554432
    when "cf", "format" then 67108864
    when "cs", "surrogate" then 134217728
    when "co", "privateuse" then 268435456
    when "cn", "unassigned" then 536870912
    when "c", "other" then 1040187392
    when "assigned" then 536870911
    when "graph" then 33554175
    when "emoji" then 1073741824
    when "print" then 2147483648
    else 0

  -> resolve_prop_cp_ranges(norm)
    case norm
    when "ascii", "inbasiclatin", "basiclatin"
      [[0, 127]]
    when "any"
      [[0, 1114111]]
    when "xdigit", "hexdigit"
      [[48, 57], [65, 70], [97, 102]]
    when "blank"
      [[9, 9], [32, 32], [160, 160], [5760, 5760], [8192, 8202], [8239, 8239], [8287, 8287], [12288, 12288]]
    when "space", "whitespace"
      [[9, 13], [32, 32], [133, 133], [160, 160], [5760, 5760], [8192, 8202], [8232, 8233], [8239, 8239], [8287, 8287], [12288, 12288]]
    when "latin", "latn"
      [[65, 90], [97, 122], [170, 170], [186, 186], [192, 214], [216, 246], [248, 696], [736, 740], [7424, 7461], [7468, 7516], [7522, 7525], [7531, 7679], [7680, 7935], [8305, 8305], [8319, 8319], [8336, 8348], [8490, 8491], [8498, 8498], [8526, 8526], [8544, 8584], [11360, 11391], [42786, 42887], [42891, 43007], [43824, 43866], [43872, 43880], [64256, 64262], [65313, 65338], [65345, 65370]]
    when "greek", "grek"
      [[880, 883], [885, 887], [890, 893], [895, 895], [900, 906], [908, 908], [910, 929], [931, 993], [1008, 1023], [7462, 7466], [7517, 7521], [7526, 7530], [7936, 8190], [8486, 8486], [43877, 43877], [65856, 65934], [119296, 119365]]
    when "cyrillic", "cyrl", "incyrillic"
      [[1024, 1156], [1159, 1327], [7296, 7304], [7467, 7467], [7544, 7544], [11744, 11775], [42560, 42655], [65070, 65071]]
    when "arabic", "arab", "inarabic"
      [[1536, 1791], [1872, 1919], [2160, 2207], [2208, 2303], [64336, 65023], [65136, 65279], [69216, 69246], [126464, 126719]]
    when "hebrew", "hebr", "inhebrew"
      [[1425, 1479], [1488, 1514], [1519, 1524], [64285, 64310], [64312, 64316], [64318, 64318], [64320, 64321], [64323, 64324], [64326, 64335]]
    when "devanagari", "deva", "indevanagari"
      [[2304, 2431], [43232, 43263], [72448, 72457]]
    when "thai", "inthai"
      [[3585, 3642], [3648, 3675]]
    when "hiragana", "hira", "inhiragana"
      [[12353, 12438], [12445, 12447], [110593, 110879], [110898, 110898], [110928, 110930], [127488, 127488]]
    when "katakana", "kana", "inkatakana"
      [[12449, 12538], [12541, 12543], [12784, 12799], [13008, 13054], [13056, 13143], [65382, 65391], [65393, 65437], [110576, 110592], [110880, 110882], [110933, 110933], [110948, 110951]]
    when "han", "hani", "incjkunifiedideographs", "cjkunifiedideographs"
      [[11904, 11929], [11931, 12019], [12032, 12245], [12293, 12293], [12295, 12295], [12321, 12329], [12344, 12347], [13312, 19903], [19968, 40959], [63744, 64109], [64112, 64217], [131072, 173791], [173824, 177977], [177984, 178205], [178208, 183969], [183984, 191456], [191472, 192093], [194560, 195101], [196608, 201546], [201552, 205743]]
    when "hangul", "hang", "inhangulsyllables", "hangulsyllables"
      [[4352, 4607], [12334, 12335], [12593, 12686], [12800, 12830], [12896, 12926], [43360, 43388], [44032, 55203], [55216, 55238], [55243, 55291], [65440, 65470], [65474, 65479], [65482, 65487], [65490, 65495], [65498, 65500]]
    when "inlatin1supplement", "latin1supplement"
      [[128, 255]]
    when "inlatinextendeda", "latinextendeda"
      [[256, 383]]
    when "inlatinextendedb", "latinextendedb"
      [[384, 591]]
    when "inipaextensions", "ipaextensions"
      [[592, 687]]
    when "inspacingmodifierletters", "spacingmodifierletters"
      [[688, 767]]
    when "incombiningdiacriticalmarks", "combiningdiacriticalmarks"
      [[768, 879]]
    when "ingreekandcoptic", "greekandcoptic"
      [[880, 1023]]
    when "ingeneralpunctuation", "generalpunctuation"
      [[8192, 8303]]
    when "insuperscriptsandsubscripts", "superscriptsandsubscripts"
      [[8304, 8351]]
    when "incurrencysymbols", "currencysymbols"
      [[8352, 8399]]
    when "inletterlikesymbols", "letterlikesymbols"
      [[8448, 8527]]
    when "innumberforms", "numberforms"
      [[8528, 8591]]
    when "inarrows", "arrows"
      [[8592, 8703]]
    when "inmathematicaloperators", "mathematicaloperators"
      [[8704, 8959]]
    when "inmiscellaneoustechnical", "miscellaneoustechnical"
      [[8960, 9215]]
    when "inboxdrawing", "boxdrawing"
      [[9472, 9599]]
    when "inblockelements", "blockelements"
      [[9600, 9631]]
    when "ingeometricshapes", "geometricshapes"
      [[9632, 9727]]
    when "inmiscellaneoussymbols", "miscellaneoussymbols"
      [[9728, 9983]]
    when "indingbats", "dingbats"
      [[9984, 10175]]
    when "incjksymbolsandpunctuation", "cjksymbolsandpunctuation"
      [[12288, 12351]]
    when "inprivateusearea", "privateusearea"
      [[57344, 63743]]
    when "inhalfwidthandfullwidthforms", "halfwidthandfullwidthforms"
      [[65280, 65519]]
    when "inmiscellaneoussymbolsandpictographs", "miscellaneoussymbolsandpictographs"
      [[127744, 128511]]
    when "inemoticons", "emoticons"
      [[128512, 128591]]
    when "intransportandmapsymbols", "transportandmapsymbols"
      [[128640, 128767]]
    when "insupplementalsymbolsandpictographs", "supplementalsymbolsandpictographs"
      [[129280, 129535]]
    else
      nil

  -> read_prop_spec(neg_in)
    neg = neg_in
    raw = ""
    if peek_cp() == 123
      advance_cp()
      nstart = @i ## i64
      while !at_end?() && peek_cp() != 125
        advance_cp()
      nlen = (@i ## i64) - nstart
      if peek_cp() != 125 || nlen == 0
        raise "unterminated \\p{...} property in regex"
      advance_cp()
      raw = @source.ascii?() ? @source.slice(nstart, nlen) : slice_pattern_cps(nstart, nlen)
    elsif !at_end?()
      raw = Char.new(advance_cp()).to_s()
    else
      raise "incomplete \\p property in regex"
    if raw.starts_with?("^")
      neg = !neg
      raw = raw.slice(1, raw.size() - 1)
    norm = normalize_prop_name(raw)
    if !(norm == "ascii" || norm == "inbasiclatin" || norm == "basiclatin") || neg
      @ascii_only = false
    [norm, neg, raw]

  -> parse_unicode_property(neg_in)
    spec = read_prop_spec(neg_in)
    norm = spec[0]
    neg = spec[1]
    raw = spec[2]
    if norm == "word"
      return new_ast(AST_FLAG, FLAG_W, neg ? 1 : 0, 0)
    cat_mask = resolve_prop_cat_mask(norm) ## i64
    if cat_mask != 0
      if @ignore_case && (cat_mask == 1 || cat_mask == 2 || cat_mask == 4)
        cat_mask = 7
      return new_ast(AST_CAT, cat_mask, neg ? 1 : 0, 0)
    if @@prop_lex_ranges == nil
      @@prop_lex_ranges = {}
    range_cache = @@prop_lex_ranges ## Hash
    cached = range_cache[norm]
    if cached != nil
      cached_ranges = cached ## i64[]
      if !neg && cached_ranges.size() == 2
        return new_ast(AST_RANGE, cached_ranges[0], cached_ranges[1], 0)
      return make_class_ast(neg ? 1 : 0, 0, 0, 0, 0, cached_ranges)
    cp_ranges = resolve_prop_cp_ranges(norm)
    if cp_ranges != nil
      if !neg && cp_ranges.size() == 1
        p0 = cp_ranges[0]
        r0_lex = clex_cp(p0[0]) ## i64
        r1_lex = clex_cp(p0[1]) ## i64
        flat1 = i64[2]
        flat1[0] = r0_lex
        flat1[1] = r1_lex
        range_cache[norm] = flat1
        return new_ast(AST_RANGE, r0_lex, r1_lex, 0)
      flat = i64[cp_ranges.size() * 2]
      ri = 0 ## i64
      best_ri = 0 ## i64
      best_span = -1 ## i64
      while ri < cp_ranges.size()
        pair = cp_ranges[ri]
        lo_p = pair[0] ## i64
        hi_p = pair[1] ## i64
        span_p = (hi_p - lo_p) + (lo_p < 1150 ? 10000 : (lo_p < 55296 ? 5000 : 0))
        if span_p > best_span
          best_span = span_p
          best_ri = ri
        flat[ri * 2] = clex_cp(lo_p)
        flat[ri * 2 + 1] = clex_cp(hi_p)
        ri = ri + 1
      if best_ri > 0
        t0 = flat[0]
        t1 = flat[1]
        flat[0] = flat[best_ri * 2]
        flat[1] = flat[best_ri * 2 + 1]
        flat[best_ri * 2] = t0
        flat[best_ri * 2 + 1] = t1
      range_cache[norm] = flat
      return make_class_ast(neg ? 1 : 0, 0, 0, 0, 0, flat)
    raise "unknown Unicode property in regex: " + raw

  # [abc] [a-z] [^...] with \d \w \s \h \p{...} \xNN \uNNNN \u{...} inside.
  -> parse_class
    neg = 0 ## i64
    if peek_cp() == 94
      advance_cp()
      neg = 1
    ranges = i64[0]
    pos_f = 0 ## i64
    neg_f = 0 ## i64
    pos_cat = 0 ## i64
    neg_cat = 0 ## i64
    while !at_end?() && peek_cp() != 93
      c = advance_cp() ## i64
      if c == 92
        e = advance_cp() ## i64
        if e == 100
          pos_f = pos_f | FLAG_D
          next
        if e == 119
          pos_f = pos_f | FLAG_W
          next
        if e == 115
          pos_f = pos_f | FLAG_S
          next
        if e == 68
          neg_f = neg_f | FLAG_D
          next
        if e == 87
          neg_f = neg_f | FLAG_W
          next
        if e == 83
          neg_f = neg_f | FLAG_S
          next
        if e == 104
          ranges.push(clex_cp(48))
          ranges.push(clex_cp(57))
          ranges.push(clex_cp(65))
          ranges.push(clex_cp(70))
          ranges.push(clex_cp(97))
          ranges.push(clex_cp(102))
          next
        if e == 72
          ranges.push(clex_cp(0))
          ranges.push(clex_cp(47))
          ranges.push(clex_cp(58))
          ranges.push(clex_cp(64))
          ranges.push(clex_cp(71))
          ranges.push(clex_cp(96))
          ranges.push(clex_cp(103))
          ranges.push(clex_cp(1114111))
          next
        if e == 112 || e == 80
          spec = read_prop_spec(e == 80)
          pnorm = spec[0]
          pneg = spec[1]
          praw = spec[2]
          if pnorm == "word"
            if pneg
              neg_f = neg_f | FLAG_W
            else
              pos_f = pos_f | FLAG_W
            next
          cm = resolve_prop_cat_mask(pnorm) ## i64
          if cm != 0
            if @ignore_case && (cm == 1 || cm == 2 || cm == 4)
              cm = 7
            if pneg
              neg_cat = neg_cat | cm
            else
              pos_cat = pos_cat | cm
            next
          cpr = resolve_prop_cp_ranges(pnorm)
          if cpr == nil
            raise "unknown Unicode property in regex class: " + praw
          if !pneg
            ri = 0
            while ri < cpr.size()
              pair = cpr[ri]
              ranges.push(clex_cp(pair[0]))
              ranges.push(clex_cp(pair[1]))
              ri = ri + 1
          else
            cur = 0 ## i64
            ri = 0
            while ri < cpr.size()
              pair = cpr[ri]
              lo_r = pair[0] ## i64
              hi_r = pair[1] ## i64
              if cur < lo_r
                ranges.push(clex_cp(cur))
                ranges.push(clex_cp(lo_r - 1))
              cur = hi_r + 1
              ri = ri + 1
            if cur <= 1114111
              ranges.push(clex_cp(cur))
              ranges.push(clex_cp(1114111))
          next
        if e == 117 && peek_cp() == 123
          cps = parse_u_braced_cps() ## i64[]
          if cps.size() == 1 && peek_cp() == 45
            c = cps[0]
          else
            ci = 0 ## i64
            while ci < cps.size()
              push_class_single(ranges, cps[ci])
              ci = ci + 1
            next
        else
          ecp = parse_escape_cp(e) ## i64
          if ecp >= 0
            c = ecp
          elsif e == 98
            c = 8
          else
            c = e
      if peek_cp() == 45 && @i + 1 < @plen && @p[@i + 1] != 93
        advance_cp()
        hi = advance_cp() ## i64
        if hi == 92
          he = advance_cp() ## i64
          if he == 117 && peek_cp() == 123
            hcps = parse_u_braced_cps() ## i64[]
            hi = hcps[0]
          else
            hecp = parse_escape_cp(he) ## i64
            hi = hecp >= 0 ? hecp : he
        if @ignore_case && (fold_pair_cp(c) != c || fold_pair_cp(hi) != hi)
          ranges.push(clex_cp(downcase_cp(c)))
          ranges.push(clex_cp(downcase_cp(hi)))
          ranges.push(clex_cp(upcase_cp(c)))
          ranges.push(clex_cp(upcase_cp(hi)))
        else
          ranges.push(clex_cp(c))
          ranges.push(clex_cp(hi))
      else
        push_class_single(ranges, c)
    if peek_cp() == 93
      advance_cp()
    make_class_ast(neg, pos_f, neg_f, pos_cat, neg_cat, ranges)

  -> push_class_single(ranges_in, cp_in)
    ranges = ranges_in ## i64[]
    cp = cp_in ## i64
    if @ignore_case
      alt = fold_pair_cp(cp) ## i64
      if alt != cp
        lx1 = clex_cp(cp)
        lx2 = clex_cp(alt)
        ranges.push(lx1)
        ranges.push(lx1)
        ranges.push(lx2)
        ranges.push(lx2)
        return nil
    lx = clex_cp(cp)
    ranges.push(lx)
    ranges.push(lx)

  -> make_class_ast(neg_in, pos_f_in, neg_f_in, pos_cat_in, neg_cat_in, ranges_in)
    neg = neg_in ## i64
    pos_f = pos_f_in ## i64
    neg_f = neg_f_in ## i64
    pos_cat = pos_cat_in ## i64
    neg_cat = neg_cat_in ## i64
    ranges = ranges_in ## i64[]
    rn = ranges.size() ## i64
    # Fast specialized opcodes when possible
    if neg == 0 && pos_f == 0 && neg_f == 0 && pos_cat == 0 && neg_cat == 0 && rn == 2
      if ranges[0] == ranges[1]
        return new_ast(AST_LIT, ranges[0], 0, 0)
      return new_ast(AST_RANGE, ranges[0], ranges[1], 0)
    if rn == 0 && pos_f == 0 && neg_f == 0
      if pos_cat != 0 && neg_cat == 0
        return new_ast(AST_CAT, pos_cat, neg, 0)
      if pos_cat == 0 && neg_cat != 0
        return new_ast(AST_CAT, neg_cat, neg == 1 ? 0 : 1, 0)
    if rn == 0 && pos_cat == 0 && neg_cat == 0
      if (pos_f == 1 || pos_f == 2 || pos_f == 4) && neg_f == 0
        return new_ast(AST_FLAG, pos_f, neg, 0)
      if (neg_f == 1 || neg_f == 2 || neg_f == 4) && pos_f == 0
        return new_ast(AST_FLAG, neg_f, neg == 1 ? 0 : 1, 0)
    # Build @classes entry + flat 128-bit ASCII membership bitmap in @cls_bm
    # (4 x 32-bit chunks per class: 0..31, 32..63, 64..95, 96..127).
    cls_arr = i64[5 + rn]
    cls_arr[0] = neg
    cls_arr[1] = pos_f
    cls_arr[2] = neg_f
    cls_arr[3] = pos_cat
    cls_arr[4] = neg_cat
    ri = 0 ## i64
    while ri < rn
      cls_arr[5 + ri] = ranges[ri]
      ri = ri + 1
    bm0 = 0 ## i64
    bm1 = 0 ## i64
    bm2 = 0 ## i64
    bm3 = 0 ## i64
    one = 1 ## i64
    if (pos_f & 4) == 0 && neg_f == 0 && pos_cat == 0 && neg_cat == 0
      if (pos_f & 1) != 0
        bm1 = bm1 | 67043328
      if (pos_f & 2) != 0
        bm1 = bm1 | 67043328
        bm2 = bm2 | 2281701374
        bm3 = bm3 | 134217726
      ri = 0
      while ri < rn
        lo_cp = (ranges[ri] >> 25) & 2097151
        if lo_cp < 128
          hi_cp = (ranges[ri + 1] >> 25) & 2097151
          if hi_cp > 127
            hi_cp = 127
          if (lo_cp >> 5) == (hi_cp >> 5)
            cnt = hi_cp - lo_cp + 1
            bit = cnt >= 32 ? 4294967295 : (((one << cnt) - 1) << (lo_cp & 31))
            blk = lo_cp >> 5
            if blk == 0
              bm0 = bm0 | bit
            elsif blk == 1
              bm1 = bm1 | bit
            elsif blk == 2
              bm2 = bm2 | bit
            else
              bm3 = bm3 | bit
          else
            cp = lo_cp
            while cp <= hi_cp
              sh = cp & 31
              bit = one << sh
              blk = cp >> 5
              if blk == 0
                bm0 = bm0 | bit
              elsif blk == 1
                bm1 = bm1 | bit
              elsif blk == 2
                bm2 = bm2 | bit
              else
                bm3 = bm3 | bit
              cp = cp + 1
        ri = ri + 2
      if neg == 1
        bm0 = bm0 ^ 4294967295
        bm1 = bm1 ^ 4294967295
        bm2 = bm2 ^ 4294967295
        bm3 = bm3 ^ 4294967295
    else
      tbl = @@ascii_lex ## i64[]
      cp = 0 ## i64
      while cp < 128
        lx = tbl[cp] ## i64
        if class_match_slow?(cls_arr, lx)
          sh = cp & 31
          bit = one << sh
          blk = cp >> 5
          if blk == 0
            bm0 = bm0 | bit
          elsif blk == 1
            bm1 = bm1 | bit
          elsif blk == 2
            bm2 = bm2 | bit
          else
            bm3 = bm3 | bit
        cp = cp + 1
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
    cbm[cbase] = bm0
    cbm[cbase + 1] = bm1
    cbm[cbase + 2] = bm2
    cbm[cbase + 3] = bm3
    if neg == 0 && rn >= 2
      cbm[cbase + 4] = ranges[0]
      cbm[cbase + 5] = ranges[1]
    else
      cbm[cbase + 4] = 1
      cbm[cbase + 5] = 0
    @cls_bm_len = cbase + 6
    @classes.push(cls_arr)
    new_ast(AST_CLASS, (cbase / 6) ## i64, 0, 0)

  # Resolve a group reference (positive Int or negative ref_names index) to group index.
  -> resolve_group_ref(ref_in)
    ref = ref_in ## i64
    if ref >= 0
      if ref >= @ngroup
        raise "invalid group reference: " + ref.to_s()
      return ref
    s = @ref_names[0 - ref - 1]
    if s == "0"
      return 0
    cs = s.chars()
    all_digits = cs.size() > 0
    i = 0
    while i < cs.size()
      if cs[i] < "0" || cs[i] > "9"
        all_digits = false
        break
      i = i + 1
    if all_digits
      idx = s.to_i()
      if idx < 0 || idx >= @ngroup
        raise "invalid numbered group reference: " + s
      return idx
    if @group_names != nil && @group_names.has_key?(s)
      return @group_names[s]
    raise "undefined named group reference: " + s

  # ── compile AST → flat @op/@a/@b program ──
  -> compile_node(node_in)
    node = node_in ## i64
    if node < 0
      return nil
    ast_k = @ast_k ## i64[]
    ast_a = @ast_a ## i64[]
    ast_b = @ast_b ## i64[]
    ast_c = @ast_c ## i64[]
    ast_next = @ast_next ## i64[]
    k = ast_k[node] ## i64
    a = ast_a[node] ## i64
    b = ast_b[node] ## i64
    c = ast_c[node] ## i64
    if k == AST_LIT
      emit(OP_CHAR, a, 0)
    elsif k == AST_ICASE
      emit(OP_ICASE, a, b)
    elsif k == AST_CAT
      emit(OP_CAT, a, b)
    elsif k == AST_ANY
      emit(OP_ANY, a == 1 ? -1 : @nl, 0)
    elsif k == AST_FLAG
      emit(OP_FLAG, a, b)
    elsif k == AST_RANGE
      emit(OP_RANGE, a, b)
    elsif k == AST_CLASS
      emit(OP_CLASS, a, 0)
    elsif k == AST_BOL
      emit(OP_BOL, 0, 0)
    elsif k == AST_EOL
      emit(OP_EOL, 0, 0)
    elsif k == AST_ANCHOR
      emit(OP_ANCHOR, a, 0)
    elsif k == AST_KEEP
      emit(OP_SAVE, 0, 0)
    elsif k == AST_SPECIAL
      emit(OP_SPECIAL, a, 0)
    elsif k == AST_BACKREF
      g = resolve_group_ref(a) ## i64
      if g <= 0
        raise "invalid backreference group"
      emit(OP_BACKREF, g, @ignore_case ? 1 : 0)
    elsif k == AST_SUBCALL
      g = resolve_group_ref(a) ## i64
      call_pc = emit(OP_CALL, 0, g)
      if @subcalls == nil
        @subcalls = []
      @subcalls.push([call_pc, g])
    elsif k == AST_WORDB
      emit(OP_WORDB, a, 0)
    elsif k == AST_SEQ
      cur = a
      while cur >= 0
        compile_node(cur)
        cur = ast_next[cur] ## i64
    elsif k == AST_GROUP
      if b >= 0
        emit(OP_SAVE, b * 2, 0)
        compile_node(a)
        emit(OP_SAVE, b * 2 + 1, 0)
      else
        compile_node(a)
    elsif k == AST_LOOK
      if b == 5
        ak = ast_k[a] ## i64
        if ak == AST_PLUS && ast_b[a] == 1 && single_consuming?(ast_a[a])
          compile_plus(ast_a[a], 2)
          return nil
        if ak == AST_STAR && ast_b[a] == 1 && single_consuming?(ast_a[a])
          compile_star(ast_a[a], 2)
          return nil
      min_l = 0 ## i64
      max_e = 0 ## i64
      if b == 3 || b == 4
        bnds = ast_length_bounds(a) ## i64
        min_l = bnds >> 16
        max_e = bnds & 65535
      enc = (min_l << 20) | (max_e << 4) | b
      apc = emit(OP_ASSERT, 0, enc) ## i64
      compile_node(a)
      emit(OP_ASSERT_END, (b == 3 || b == 4) ? 1 : 0, 0)
      aa_l = @a ## i64[]
      aa_l[apc] = @op_len ## i64
    elsif k == AST_ALT
      compile_alt(a)
    elsif k == AST_STAR
      compile_star(a, b)
    elsif k == AST_PLUS
      compile_plus(a, b)
    elsif k == AST_OPT
      compile_opt(a, b != 0)
    elsif k == AST_REP
      compile_rep(a, b, c)

  # Returns (min_len << 16) | max_enc, where max_enc == 65535 means unbounded.
  -> ast_length_bounds(node_in)
    node = node_in ## i64
    if node < 0
      return 0
    ast_k = @ast_k ## i64[]
    ast_a = @ast_a ## i64[]
    ast_b = @ast_b ## i64[]
    ast_c = @ast_c ## i64[]
    ast_next = @ast_next ## i64[]
    k = ast_k[node] ## i64
    if k == AST_LIT || k == AST_ICASE || k == AST_CAT || k == AST_ANY || k == AST_CLASS || k == AST_FLAG || k == AST_RANGE
      return 65537
    if k == AST_BOL || k == AST_EOL || k == AST_ANCHOR || k == AST_WORDB || k == AST_KEEP
      return 0
    if k == AST_LOOK
      if ast_b[node] == 5
        return ast_length_bounds(ast_a[node])
      return 0
    if k == AST_GROUP
      return ast_length_bounds(ast_a[node])
    if k == AST_SEQ
      sum_min = 0 ## i64
      sum_max = 0 ## i64
      cur = ast_a[node] ## i64
      while cur >= 0
        cb = ast_length_bounds(cur) ## i64
        cmin = cb >> 16
        cmax = cb & 65535
        sum_min = sum_min + cmin
        if sum_min > 65534
          sum_min = 65534
        if sum_max == 65535 || cmax == 65535
          sum_max = 65535
        else
          sum_max = sum_max + cmax
          if sum_max > 65534
            sum_max = 65535
        cur = ast_next[cur] ## i64
      return (sum_min << 16) | sum_max
    if k == AST_ALT
      cur = ast_a[node] ## i64
      if cur < 0
        return 0
      fb = ast_length_bounds(cur) ## i64
      best_min = fb >> 16
      best_max = fb & 65535
      cur = ast_next[cur] ## i64
      while cur >= 0
        cb = ast_length_bounds(cur) ## i64
        cmin = cb >> 16
        cmax = cb & 65535
        if cmin < best_min
          best_min = cmin
        if best_max == 65535 || cmax == 65535
          best_max = 65535
        elsif cmax > best_max
          best_max = cmax
        cur = ast_next[cur] ## i64
      return (best_min << 16) | best_max
    if k == AST_OPT
      cb = ast_length_bounds(ast_a[node]) ## i64
      return cb & 65535
    if k == AST_STAR
      return 65535
    if k == AST_PLUS
      cb = ast_length_bounds(ast_a[node]) ## i64
      return ((cb >> 16) << 16) | 65535
    if k == AST_REP
      cb = ast_length_bounds(ast_a[node]) ## i64
      cmin = cb >> 16
      cmax = cb & 65535
      lo = ast_b[node] ## i64
      hi = (ast_c[node] ## i64) >> 1
      rmin = lo * cmin
      if rmin > 65534
        rmin = 65534
      rmax = 65535 ## i64
      if hi >= 0 && cmax < 65535
        rmax = hi * cmax
        if rmax > 65534
          rmax = 65535
      return (rmin << 16) | rmax
    if k == AST_SPECIAL
      return 131071
    65535

  -> compile_subroutines
    sub_pcs = {}
    gasts = @group_asts ## i64[]
    sci = 0
    while sci < @subcalls.size()
      entry = @subcalls[sci]
      call_pc = entry[0] ## i64
      g = entry[1] ## i64
      if !sub_pcs.has_key?(g)
        sub_pcs[g] = @op_len ## i64
        if g > 0
          emit(OP_SAVE, g * 2, 0)
          compile_node(gasts[g])
          emit(OP_SAVE, g * 2 + 1, 0)
        else
          compile_node(gasts[0])
        emit(OP_RET, 0, 0)
      aa_s = @a ## i64[]
      bb_s = @b ## i64[]
      aa_s[call_pc] = sub_pcs[g] ## i64
      bb_s[call_pc] = g
      sci = sci + 1

  -> compile_alt(head_in)
    cur = head_in ## i64
    ast_next = @ast_next ## i64[]
    nxt = ast_next[cur] ## i64
    if nxt < 0
      compile_node(cur)
      return nil
    s = emit(OP_SPLIT, 0, 0) ## i64
    aa_a = @a ## i64[]
    aa_a[s] = @op_len ## i64
    compile_node(cur)
    j = emit(OP_JMP, 0, 0) ## i64
    bb_a = @b ## i64[]
    bb_a[s] = @op_len ## i64
    compile_alt(nxt)
    aa_a = @a ## i64[]
    aa_a[j] = @op_len ## i64

  -> nullable?(node_in)
    node = node_in ## i64
    if node < 0
      return true
    ast_k = @ast_k ## i64[]
    ast_a = @ast_a ## i64[]
    ast_b = @ast_b ## i64[]
    ast_next = @ast_next ## i64[]
    k = ast_k[node] ## i64
    if k == AST_LIT || k == AST_ICASE || k == AST_CAT || k == AST_ANY || k == AST_CLASS || k == AST_FLAG || k == AST_RANGE || k == AST_SPECIAL
      return false
    if k == AST_STAR || k == AST_OPT
      return true
    if k == AST_BOL || k == AST_EOL || k == AST_WORDB || k == AST_ANCHOR || k == AST_KEEP || k == AST_BACKREF || k == AST_SUBCALL
      return true
    if k == AST_LOOK
      if ast_b[node] == 5
        return nullable?(ast_a[node])
      return true
    if k == AST_PLUS || k == AST_GROUP
      return nullable?(ast_a[node])
    if k == AST_SEQ
      cur = ast_a[node] ## i64
      while cur >= 0
        if !nullable?(cur)
          return false
        cur = ast_next[cur] ## i64
      return true
    if k == AST_ALT
      cur = ast_a[node] ## i64
      while cur >= 0
        if nullable?(cur)
          return true
        cur = ast_next[cur] ## i64
      return false
    if k == AST_REP
      return ast_b[node] == 0 || nullable?(ast_a[node])
    false

  -> single_consuming?(node_in)
    node = node_in ## i64
    if node < 0
      return false
    ast_k = @ast_k ## i64[]
    k = ast_k[node] ## i64
    k == AST_LIT || k == AST_ICASE || k == AST_CAT || k == AST_ANY || k == AST_CLASS || k == AST_FLAG || k == AST_RANGE

  -> compile_star(child, mode_in)
    mode = mode_in ## i64
    greedy = mode != 0
    if single_consuming?(child)
      op = OP_REP_G
      if mode == 0
        op = OP_REP_L
      elsif mode == 2
        op = OP_REP_NB
      rep = emit(op, 0, 0) ## i64
      body = @op_len ## i64
      compile_node(child)
      aa_r = @a ## i64[]
      bb_r = @b ## i64[]
      aa_r[rep] = body
      bb_r[rep] = @op_len ## i64
      return nil
    if nullable?(child)
      g = @nguard ## i64
      @nguard = g + 1
      l1 = @op_len ## i64
      s = emit(OP_SPLIT, 0, 0) ## i64
      emit(OP_MARK, g, 0)
      compile_node(child)
      emit(OP_GUARD, g, 0)
      emit(OP_JMP, l1, 0)
      l3 = @op_len ## i64
      set_split(s, l1 + 1, l3, greedy)
      return nil
    l1 = @op_len ## i64
    s = emit(OP_SPLIT, 0, 0) ## i64
    compile_node(child)
    emit(OP_JMP, l1, 0)
    l3 = @op_len ## i64
    set_split(s, l1 + 1, l3, greedy)

  -> compile_plus(child, mode_in)
    mode = mode_in ## i64
    if single_consuming?(child) || nullable?(child)
      compile_node(child)
      compile_star(child, mode)
      return nil
    l1 = @op_len ## i64
    compile_node(child)
    s = emit(OP_SPLIT, 0, 0) ## i64
    set_split(s, l1, @op_len ## i64, mode != 0)

  -> compile_opt(child, greedy)
    s = emit(OP_SPLIT, 0, 0) ## i64
    l1 = @op_len ## i64
    compile_node(child)
    set_split(s, l1, @op_len ## i64, greedy)

  -> compile_rep(child_in, lo_in, c_enc_in)
    child = child_in ## i64
    lo = lo_in ## i64
    c_enc = c_enc_in ## i64
    greedy = (c_enc & 1) != 0
    hi = c_enc >> 1
    i = 0 ## i64
    while i < lo
      compile_node(child)
      i = i + 1
    if hi < 0
      compile_star(child, greedy ? 1 : 0)
    else
      extra = hi - lo
      i = 0
      while i < extra
        compile_opt(child, greedy)
        i = i + 1

  -> set_split(s_in, pref_in, alt_in, greedy)
    s = s_in ## i64
    pref = pref_in ## i64
    alt = alt_in ## i64
    aa = @a ## i64[]
    bb = @b ## i64[]
    if greedy
      aa[s] = pref
      bb[s] = alt
    else
      aa[s] = alt
      bb[s] = pref

  -> find_required_lit(node_in)
    node = node_in ## i64
    if node < 0
      return -1
    ast_k = @ast_k ## i64[]
    ast_a = @ast_a ## i64[]
    ast_b = @ast_b ## i64[]
    ast_next = @ast_next ## i64[]
    k = ast_k[node] ## i64
    if k == AST_LIT
      return ast_a[node]
    if k == AST_GROUP || k == AST_PLUS
      return find_required_lit(ast_a[node])
    if k == AST_LOOK && (ast_b[node] == 1 || ast_b[node] == 5)
      return find_required_lit(ast_a[node])
    if k == AST_REP && ast_b[node] >= 1
      return find_required_lit(ast_a[node])
    if k == AST_SEQ
      cur = ast_a[node] ## i64
      best = -1 ## i64
      while cur >= 0
        r = find_required_lit(cur) ## i64
        if r >= 0
          best = r
        cur = ast_next[cur] ## i64
      return best
    -1

  # ── matcher (all int ops over the Char array) ──

  -> literal_prefix
    lit = @@empty_prefix ## i64[]
    ops = @op ## i64[]
    aa = @a ## i64[]
    bb = @b ## i64[]
    op_n = ops.size() ## i64
    pc = 0 ## i64
    @lit_anchored = 0
    while pc < op_n
      op = ops[pc] ## i64
      if op == OP_CHAR
        if lit.size() == 0
          lit = i64[0]
        lit.push(aa[pc])
        pc = pc + 1
      elsif op == OP_SAVE || op == OP_MARK || op == OP_GUARD
        pc = pc + 1
      elsif lit.size() == 0 && ((op == OP_ANCHOR && aa[pc] == 1) || (op == OP_BOL && !@multiline))
        @lit_anchored = 1
        pc = pc + 1
      elsif op == OP_ASSERT && (bb[pc] & 15) == 5
        pc = pc + 1
      elsif op == OP_ASSERT_END && aa[pc] == 0
        pc = pc + 1
      else
        pc = op_n
    lit

  -> branch_can_start_with?(pc_in, ch_in, depth_in)
    depth = depth_in ## i64
    if depth > 8
      return true
    ops = @op ## i64[]
    args_a = @a ## i64[]
    branches = @b ## i64[]
    op_n = ops.size() ## i64
    pc = pc_in ## i64
    ch = ch_in ## i64
    while pc < op_n
      op = ops[pc] ## i64
      if op == 7 || op == 12 || op == 13
        pc = pc + 1
      elsif op == 5
        pc = args_a[pc] ## i64
      elsif op == 1
        return args_a[pc] == ch
      elsif op == 18
        return args_a[pc] == ch || branches[pc] == ch
      elsif op == 17
        return ch >= args_a[pc] && ch <= branches[pc]
      elsif op == 11
        if branches[pc] == 0
          return (ch & args_a[pc]) != 0
        return (ch & args_a[pc]) == 0
      elsif op == 6 || op == 27
        tpc_b = args_a[pc] ## i64
        top_b = ops[tpc_b] ## i64
        if top_b == 1
          if args_a[tpc_b] == ch
            return true
        elsif top_b == 18
          if args_a[tpc_b] == ch || branches[tpc_b] == ch
            return true
        elsif branch_can_start_with?(tpc_b, ch, depth + 1)
          return true
        pc = branches[pc] ## i64
      else
        return true
    true

  -> can_upgrade_rep_nb?(tpc_in, npc_in, depth_in)
    if depth_in > 4
      return false
    ops = @op ## i64[]
    args_a = @a ## i64[]
    branches = @b ## i64[]
    tpc = tpc_in ## i64
    npc = npc_in ## i64
    while npc < ops.size() && ops[npc] == 7 && args_a[npc] != 0
      npc = npc + 1
    if npc >= ops.size()
      return false
    nop = ops[npc] ## i64
    if nop == 4 || (nop == 26 && args_a[npc] == 0)
      return true
    if nop == 20 && args_a[npc] == 2
      return true
    if nop == 9 && !consume_at?(tpc, @nl)
      return true
    if nop == 1
      return !consume_at?(tpc, args_a[npc])
    if nop == 18
      return !consume_at?(tpc, args_a[npc]) && !consume_at?(tpc, branches[npc])
    if nop == 25 && (branches[npc] & 15) == 1 && npc + 1 < ops.size() && ops[npc + 1] == 1
      return !consume_at?(tpc, args_a[npc + 1])
    if nop == 11 && branches[npc] == 0 && ops[tpc] == 11 && branches[tpc] == 0
      m1 = args_a[tpc] ## i64
      m2 = args_a[npc] ## i64
      return (m1 & m2) == 0 && ((m1 | m2) & 4) != 0
    if nop == 6
      return can_upgrade_rep_nb?(tpc, args_a[npc], depth_in + 1) && can_upgrade_rep_nb?(tpc, branches[npc], depth_in + 1)
    false

  -> compute_prefilter
    ops = @op ## i64[]
    args_a = @a ## i64[]
    branches = @b ## i64[]
    op_n = ops.size() ## i64
    jpc = (op_n - 1) ## i64
    while jpc >= 0
      jop = ops[jpc] ## i64
      if jop == 5
        jt = args_a[jpc] ## i64
        while jt < op_n && ops[jt] == 5 && args_a[jt] != jt
          jt = args_a[jt] ## i64
        args_a[jpc] = jt
      elsif jop == 6
        jt = args_a[jpc] ## i64
        while jt < op_n && ops[jt] == 5 && args_a[jt] != jt
          jt = args_a[jt] ## i64
        args_a[jpc] = jt
        jb = branches[jpc] ## i64
        while jb < op_n && ops[jb] == 5 && args_a[jb] != jb
          jb = args_a[jb] ## i64
        branches[jpc] = jb
      jpc = jpc - 1
    opc = 0 ## i64
    while opc < op_n
      if ops[opc] == 14
        if can_upgrade_rep_nb?(args_a[opc], branches[opc], 0)
          ops[opc] = 16
      elsif ops[opc] == 6 && args_a[opc] > opc && branches[opc] > opc
        tpc_s = args_a[opc] ## i64
        bpc_s = branches[opc] ## i64
        top_s = ops[tpc_s] ## i64
        if top_s == 1 && !branch_can_start_with?(bpc_s, args_a[tpc_s], 0)
          ops[opc] = 27
        elsif top_s == 18 && !branch_can_start_with?(bpc_s, args_a[tpc_s], 0) && !branch_can_start_with?(bpc_s, branches[tpc_s], 0)
          ops[opc] = 27
      opc = opc + 1
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
    @linear = 1
    if @has_subcall
      @linear = 0
    nsplit = 0 ## i64
    nsave = 0 ## i64
    n_rep_g = 0 ## i64
    save_after_rep_g = false
    has_back_jmp = false
    has_bref = false
    has_assert = false
    lpc = 0 ## i64
    while lpc < op_n
      lop = ops[lpc] ## i64
      if lop == 15 || lop == 12 || lop == 22 || lop == 23 || lop == 24 || lop == 26
        @linear = 0
      elsif lop == 14
        n_rep_g = n_rep_g + 1
      elsif lop == 25
        tpc_l = args_a[lpc] ## i64
        kind_l = (branches[lpc] & 15) ## i64
        if kind_l >= 1 && kind_l <= 4 && ((tpc_l == lpc + 3 && ops[lpc + 1] == 1 && ops[lpc + 2] == 26) || (tpc_l == lpc + 4 && ops[lpc + 1] == 1 && ops[lpc + 2] == 1 && ops[lpc + 3] == 26))
          has_assert = true
          lpc = tpc_l - 1
        else
          @linear = 0
      elsif lop == 21
        has_bref = true
      elsif lop == 5 && args_a[lpc] <= lpc
        @linear = 0
      elsif lop == 6
        if args_a[lpc] <= lpc || branches[lpc] <= lpc
          has_back_jmp = true
        nsplit = nsplit + 1
      elsif lop == 7
        nsave = nsave + 1
        if n_rep_g > 0 && (lpc != op_n - 2 || args_a[lpc] != 1)
          save_after_rep_g = true
      lpc = lpc + 1
    if n_rep_g > 1 || save_after_rep_g
      @linear = 0
    elsif n_rep_g == 1 && (nsplit > 0 || has_back_jmp || has_bref || has_assert)
      @linear = 0
    elsif @linear == 1 && (nsplit > 0 || has_back_jmp || has_bref)
      if !has_assert && nsplit <= 16 && nsave <= 6
        @linear = 2
      else
        @linear = 0
    if @linear == 2 && @ncap == 2 && op_n == 10 && ops[0] == 7 && args_a[0] == 0 && ops[1] == 7 && args_a[1] == 2 && ops[2] == 11 && branches[2] == 0 && ops[3] == 16 && args_a[3] == 4 && branches[3] == 5 && ops[4] == 11 && args_a[4] == args_a[2] && branches[4] == 0 && ops[5] == 7 && args_a[5] == 3 && ops[6] == 1 && ops[7] == 21 && args_a[7] == 1 && branches[7] == 0 && ops[8] == 7 && args_a[8] == 1 && ops[9] == 4
      @linear = 1
      if @lit_anchored == 0
        @pf_exact_match = 16
    @pf_kind = 0
    @pf_char = 0
    @pf_flag = 0
    @pf_bm0 = 0
    @pf_bm1 = 0
    @pf_bm2 = 0
    @pf_bm3 = 0
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
    @cf_ok = true
    @cf_empty = false
    @pf_range_cnt = 0
    @pf_lo = 0
    @pf_hi = 0
    @pf_cat_cnt = 0
    @pf_cat_mask = 0
    @pf_cat_neg = 0
    @pf_cls_cnt = 0
    @pf_set_len = 0
    pfs_buf = @@pf_set ## i64[]
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
    collect_first(0, seen)
    pfs_buf = @@pf_set ## i64[]
    pfs_len = @pf_set_len ## i64
    if @cf_empty || !@cf_ok
      return nil
    if op_n >= 5 && ops[0] == 7 && args_a[0] == 0 && ops[1] == 25 && (branches[1] & 15) == 3 && args_a[1] == 4 && ops[2] == 1 && ops[3] == 26
      @pf_kind = 10
      @pf_char = args_a[2]
      if @lit_anchored == 0 && ops[4] == 11 && branches[4] == 0 && ((op_n == 7 && ops[5] == 7 && ops[6] == 4) || (op_n == 9 && ops[5] == 16 && args_a[5] == 6 && branches[5] == 7 && ops[6] == 11 && args_a[6] == args_a[4] && branches[6] == 0 && ops[7] == 7 && ops[8] == 4))
        @pf_exact_match = 14
      return nil
    if @pf_cls_cnt > 0
      if pfs_len == 0 && @pf_flag == 0 && @pf_range_cnt == 0 && @pf_cat_cnt == 0 && @lead_after_char < 0
        bm8 = i64[4]
        bm8[0] = @pf_bm0
        bm8[1] = @pf_bm1
        bm8[2] = @pf_bm2
        bm8[3] = @pf_bm3
        @pf_set = bm8
        @pf_char = (@pf_bm0 | @pf_bm1 | @pf_bm2 | @pf_bm3) ## i64
        @pf_kind = 8
        if @lit_anchored == 0 && (op_n == 4 || (@lead_rep_nb == 1 && op_n == 6))
          @pf_exact_match = 2
      elsif @lit_anchored == 0 && @lead_after_char >= 0 && @lead_rep_nb == 1 && @linear == 1 && @ascii_only && op_n == 15 && ops[1] == 3 && ops[5] == 3 && ops[6] == 16 && ops[7] == 3 && args_a[5] == args_a[7] && ops[8] == 1 && ops[9] == 3 && ops[10] == 3 && args_a[9] == args_a[10] && ops[11] == 16 && ops[12] == 3 && args_a[9] == args_a[12] && ops[13] == 7 && ops[14] == 4
        @pf_exact_match = 5
      elsif @lit_anchored == 0 && @lead_after_char >= 0 && @lead_rep_nb == 1 && @linear == 1 && @ascii_only && op_n == 10 && ops[1] == 3 && ops[4] == 1 && ops[5] == 17 && ops[6] == 16 && args_a[6] == 7 && branches[6] == 8 && ops[7] == 17 && args_a[7] == args_a[5] && branches[7] == branches[5] && ops[8] == 7 && ops[9] == 4
        @pf_exact_match = 12
      return nil
    if @pf_cat_cnt > 0
      if @pf_cat_cnt == 1 && pfs_len == 0 && @pf_flag == 0 && @pf_range_cnt == 0
        @pf_kind = 7
        @pf_char = @pf_cat_mask
        @pf_flag = @pf_cat_neg
        if @lit_anchored == 0 && op_n == 7 && ops[1] == 19 && ops[2] == 19 && ops[3] == 16 && args_a[3] == 4 && branches[3] == 5 && ops[4] == 19 && args_a[4] == args_a[2] && branches[4] == branches[2] && branches[1] == 0 && branches[2] == 0 && args_a[1] < 1073741824 && args_a[2] < 1073741824
          @pf_exact_match = 4
      return nil
    if @pf_range_cnt > 0
      if @pf_range_cnt == 1 && pfs_len == 0 && @pf_flag == 0
        @pf_kind = 5
        @pf_char = @pf_lo
        @pf_flag = @pf_hi
        if @lit_anchored == 0 && (op_n == 4 || (@lead_rep_nb == 1 && op_n == 6))
          @pf_exact_match = 3
      return nil
    if pfs_len == 0 && @pf_flag == 0
      return nil
    if @pf_flag != 0 && pfs_len == 0
      @pf_kind = 2
      @pf_char = @pf_flag
      if @lit_anchored == 0 && (op_n == 4 || (@lead_rep_nb == 1 && op_n == 6))
        @pf_exact_match = 1
      elsif @lit_anchored == 0 && @lead_rep_nb == 1 && op_n == 9 && ops[1] == 11 && branches[1] == 0 && ops[4] == 25 && args_a[4] == 7 && (branches[4] & 15) == 1 && ops[5] == 1 && ops[6] == 26 && args_a[6] == 0 && ops[7] == 7 && ops[8] == 4 && (args_a[5] & args_a[1]) == 0
        @pf_exact_match = 9
      elsif @lit_anchored == 0 && @lead_rep_nb == 1 && op_n == 10 && ops[1] == 11 && branches[1] == 0 && ops[4] == 25 && args_a[4] == 8 && (branches[4] & 15) == 2 && ops[5] == 1 && ops[6] == 1 && ops[7] == 26 && args_a[7] == 0 && ops[8] == 7 && ops[9] == 4
        @pf_exact_match = 10
      elsif @lit_anchored == 0 && op_n == 10 && ops[0] == 7 && ops[1] == 25 && args_a[1] == 4 && (branches[1] & 15) == 4 && ops[2] == 1 && ops[3] == 26 && ops[4] == 10 && args_a[4] == 1 && ops[5] == 11 && args_a[5] == 1 && branches[5] == 0 && ops[6] == 16 && args_a[6] == 7 && branches[6] == 8 && ops[7] == 11 && args_a[7] == 1 && branches[7] == 0 && ops[8] == 7 && ops[9] == 4
        @pf_exact_match = 11
      elsif @lit_anchored == 0 && @lead_rep_nb == 1 && ops[1] == 11 && branches[1] == 0 && ops[4] == 1 && (args_a[4] & args_a[1]) == 0 && ops[5] == 11 && branches[5] == 0 && ((op_n == 8 && ops[6] == 7 && ops[7] == 4) || (op_n == 10 && ops[6] == 16 && args_a[6] == 7 && branches[6] == 8 && ops[7] == 11 && args_a[7] == args_a[5] && branches[7] == 0 && ops[8] == 7 && ops[9] == 4))
        @pf_exact_match = 15
      elsif @lit_anchored == 0 && @linear == 1 && op_n >= 5 && ops[0] == 7 && ops[op_n - 2] == 7 && ops[op_n - 1] == 4
        if @ncap == 4 && op_n == 19 && ops[1] == 7 && args_a[1] == 2 && ops[2] == 11 && args_a[2] == 1 && branches[2] == 0 && ops[3] == 11 && args_a[3] == 1 && branches[3] == 0 && ops[4] == 11 && args_a[4] == 1 && branches[4] == 0 && ops[5] == 11 && args_a[5] == 1 && branches[5] == 0 && ops[6] == 7 && args_a[6] == 3 && ops[7] == 1 && ops[8] == 7 && args_a[8] == 4 && ops[9] == 11 && args_a[9] == 1 && branches[9] == 0 && ops[10] == 11 && args_a[10] == 1 && branches[10] == 0 && ops[11] == 7 && args_a[11] == 5 && ops[12] == 1 && ops[13] == 7 && args_a[13] == 6 && ops[14] == 11 && args_a[14] == 1 && branches[14] == 0 && ops[15] == 11 && args_a[15] == 1 && branches[15] == 0 && ops[16] == 7 && args_a[16] == 7 && args_a[17] == 1
          @cap_fast_kind = 2
        ok8 = true
        mi8 = 1 ## i64
        end8 = (op_n - 2) ## i64
        while mi8 < end8
          mop8 = ops[mi8] ## i64
          if mop8 != 1 && !(mop8 == 11 && branches[mi8] == 0)
            ok8 = false
            break
          mi8 = mi8 + 1
        if ok8
          @pf_exact_match = 8
    elsif @pf_flag == 0 && pfs_len == 1
      @pf_kind = 1
      @pf_char = pfs_buf[0]
    else
      if @pf_flag == 0
        all_ascii = true
        bm0 = 0 ## i64
        bm1 = 0 ## i64
        bm2 = 0 ## i64
        bm3 = 0 ## i64
        one = 1 ## i64
        si = 0 ## i64
        while si < pfs_len
          scp = (pfs_buf[si] >> 25) & 2097151
          if scp >= 128
            all_ascii = false
            break
          sh = scp & 31
          bit = one << sh
          blk = scp >> 5
          if blk == 0
            bm0 = bm0 | bit
          elsif blk == 1
            bm1 = bm1 | bit
          elsif blk == 2
            bm2 = bm2 | bit
          else
            bm3 = bm3 | bit
          si = si + 1
        if all_ascii
          bm9 = i64[40]
          bm9[0] = bm0
          bm9[1] = bm1
          bm9[2] = bm2
          bm9[3] = bm3
          bm9[4] = 0
          bm9[5] = 0
          bm9[6] = 0
          bm9[7] = 0
          if collect_second_ascii(0, 0, bm9)
            @pf_set = bm9
            @pf_char = (bm0 | bm1 | bm2 | bm3) ## i64
            @pf_flag = (bm9[4] | bm9[5] | bm9[6] | bm9[7]) ## i64
            @pf_kind = 9
            if @lit_anchored == 0 && @linear == 1 && ops[0] == 7 && ops[op_n - 2] == 7 && ops[op_n - 1] == 4
              ok6 = true
              has1 = false
              has18 = false
              mi6 = 1 ## i64
              end6 = (op_n - 2) ## i64
              while mi6 < end6
                mop6 = ops[mi6] ## i64
                if mop6 == 27
                  if args_a[mi6] != mi6 + 1
                    ok6 = false
                    break
                elsif mop6 == 5
                  if args_a[mi6] != end6
                    ok6 = false
                    break
                elsif mop6 == 1
                  has1 = true
                elsif mop6 == 18
                  if (args_a[mi6] | 1074233368) != (branches[mi6] | 1074233368)
                    ok6 = false
                    break
                  has18 = true
                else
                  ok6 = false
                  break
                mi6 = mi6 + 1
              if ok6 && (has1 != has18)
                b_idx = 8 ## i64
                while b_idx < 40
                  bm9[b_idx] = 0
                  b_idx = b_idx + 1
                bpc = 1 ## i64
                uniq6 = true
                while bpc < end6
                  if ops[bpc] == 27
                    spc6 = bpc + 1
                    epc6 = (branches[bpc] - 1) ## i64
                    bpc = branches[bpc] ## i64
                  else
                    spc6 = bpc
                    epc6 = end6
                    bpc = end6
                  c6_idx = 8 + ((args_a[spc6] >> 25) & 31)
                  if bm9[c6_idx] != 0 || epc6 - spc6 < 2
                    uniq6 = false
                    break
                  bm9[c6_idx] = (epc6 << 16) | spc6
                if uniq6
                  @pf_exact_match = (has1 ? 6 : 7) ## i64
            return nil
          if pfs_len == 2
            @pf_kind = 6
            @pf_char = pfs_buf[0]
            @pf_flag = pfs_buf[1]
            return nil
          @pf_bm0 = bm0
          @pf_bm1 = bm1
          @pf_bm2 = bm2
          @pf_bm3 = bm3
          @pf_set = bm9
          @pf_char = (bm0 | bm1 | bm2 | bm3) ## i64
          @pf_kind = 8
          return nil
      if @pf_flag == 0 && pfs_len == 2
        @pf_kind = 6
        @pf_char = pfs_buf[0]
        @pf_flag = pfs_buf[1]
        return nil
      pfs_copy = i64[pfs_len]
      si_copy = 0 ## i64
      while si_copy < pfs_len
        pfs_copy[si_copy] = pfs_buf[si_copy]
        si_copy = si_copy + 1
      @pf_set = pfs_copy
      @pf_kind = 3

  -> collect_second_ascii(pc_in, depth_in, bm_in)
    depth = depth_in ## i64
    if depth > 16
      return false
    ops = @op ## i64[]
    args_a = @a ## i64[]
    branches = @b ## i64[]
    bm = bm_in ## i64[]
    op_n = ops.size() ## i64
    pc = pc_in ## i64
    while pc < op_n
      op = ops[pc] ## i64
      if op == 7
        pc = pc + 1
      elsif op == 5
        pc = args_a[pc] ## i64
      elsif op == 6 || op == 27
        if !collect_second_ascii(args_a[pc], depth + 1, bm)
          return false
        pc = branches[pc] ## i64
      elsif op == 1 || op == 18
        pc2 = pc + 1
        while pc2 < op_n && (ops[pc2] == 7 || ops[pc2] == 5)
          if ops[pc2] == 5
            pc2 = args_a[pc2] ## i64
          else
            pc2 = pc2 + 1
        if pc2 >= op_n
          return false
        op2 = ops[pc2] ## i64
        one = 1 ## i64
        if op2 == 1
          cp2 = (args_a[pc2] >> 25) & 2097151
          if cp2 >= 128
            return false
          blk2 = 4 + (cp2 >> 5)
          bm[blk2] = bm[blk2] | (one << (cp2 & 31))
          return true
        if op2 == 18
          cp2a = (args_a[pc2] >> 25) & 2097151
          cp2b = (branches[pc2] >> 25) & 2097151
          if cp2a >= 128 || cp2b >= 128
            return false
          blk2a = 4 + (cp2a >> 5)
          blk2b = 4 + (cp2b >> 5)
          bm[blk2a] = bm[blk2a] | (one << (cp2a & 31))
          bm[blk2b] = bm[blk2b] | (one << (cp2b & 31))
          return true
        return false
      else
        return false
    false

  -> collect_first(pc_in, seen_in)
    ops = @op ## i64[]
    args_a = @a ## i64[]
    branches = @b ## i64[]
    seen = seen_in ## i64[]
    pc = pc_in ## i64
    while true
      if seen[pc] != 0
        return nil
      seen[pc] = 1
      op = ops[pc] ## i64
      if op == 7 || op == 12 || op == 13 || op == 8 || op == 10
        pc = pc + 1
      elsif op == 20 && (args_a[pc] == 1 || args_a[pc] == 4)
        pc = pc + 1
      elsif op == 25
        if (branches[pc] & 15) == 5
          pc = pc + 1
        else
          pc = args_a[pc] ## i64
      elsif op == 26 && args_a[pc] == 0
        pc = pc + 1
      elsif op == 5
        pc = args_a[pc] ## i64
      elsif op == 6 || op == 27 || op == 14 || op == 15 || op == 16
        collect_first(args_a[pc], seen)
        pc = branches[pc] ## i64
      elsif op == 1
        pfs = @@pf_set ## i64[]
        pfl = @pf_set_len ## i64
        if pfl < pfs.size()
          pfs[pfl] = args_a[pc]
          @pf_set_len = pfl + 1
        else
          @cf_ok = false
        return nil
      elsif op == 18
        pfs = @@pf_set ## i64[]
        pfl = @pf_set_len ## i64
        if pfl + 1 < pfs.size()
          pfs[pfl] = args_a[pc]
          pfs[pfl + 1] = branches[pc]
          @pf_set_len = pfl + 2
        else
          @cf_ok = false
        return nil
      elsif op == 11
        if branches[pc] == 0
          @pf_flag = (@pf_flag ## i64) | args_a[pc]
        else
          @cf_ok = false
        return nil
      elsif op == 3
        if @ascii_only && @cls_bm != nil
          cbm = @cls_bm ## i64[]
          cbase = (args_a[pc] ## i64) * 6
          @pf_bm0 = (@pf_bm0 ## i64) | cbm[cbase]
          @pf_bm1 = (@pf_bm1 ## i64) | cbm[cbase + 1]
          @pf_bm2 = (@pf_bm2 ## i64) | cbm[cbase + 2]
          @pf_bm3 = (@pf_bm3 ## i64) | cbm[cbase + 3]
          @pf_cls_cnt = (@pf_cls_cnt ## i64) + 1
        else
          cls_cf = @classes[args_a[pc]] ## i64[]
          if cls_cf[0] == 0 && cls_cf[1] == 0 && cls_cf[2] == 0 && cls_cf[3] == 0 && cls_cf[4] == 0 && cls_cf.size() >= 7
            c_min = cls_cf[5] ## i64
            c_max = cls_cf[6] ## i64
            cri = 7 ## i64
            while cri < cls_cf.size()
              if cls_cf[cri] < c_min
                c_min = cls_cf[cri]
              if cls_cf[cri + 1] > c_max
                c_max = cls_cf[cri + 1]
              cri = cri + 2
            if @pf_range_cnt == 0
              @pf_lo = c_min
              @pf_hi = c_max
              @pf_range_cnt = 1
            elsif c_min != @pf_lo || c_max != @pf_hi
              @pf_range_cnt = 2
              @cf_ok = false
          else
            @cf_ok = false
        return nil
      elsif op == 17
        if @pf_range_cnt == 0
          @pf_lo = args_a[pc]
          @pf_hi = branches[pc]
          @pf_range_cnt = 1
        elsif args_a[pc] != @pf_lo || branches[pc] != @pf_hi
          @pf_range_cnt = 2
          @cf_ok = false
        return nil
      elsif op == 19
        if @pf_cat_cnt == 0
          @pf_cat_mask = args_a[pc]
          @pf_cat_neg = branches[pc]
          @pf_cat_cnt = 1
        elsif args_a[pc] != @pf_cat_mask || branches[pc] != @pf_cat_neg
          @pf_cat_cnt = 2
          @cf_ok = false
        return nil
      elsif op == 4
        @cf_empty = true
        return nil
      else
        @cf_ok = false
        return nil

  # Decode subject into an i64[] of 46-bit Char payloads in pure Tungsten.
  # For ASCII strings, reuses @subj_buf via @@ascii_lex with zero heap allocations.
  -> decode_subject(subject)
    if subject.ascii?()
      @subj_ascii = 1
      sv = (wvalue_bits(subject) & -2) ## i64
      smode = (sv >> 1) & 7
      if @subj_buf == nil
        @subj_buf = i64[64]
      buf = @subj_buf ## i64[]
      tbl = @@ascii_lex ## i64[]
      if smode <= 5
        i = 0 ## i64
        while i < smode
          buf[i] = tbl[(sv >> (4 + 8 * i)) & 255]
          i = i + 1
        @subj_len = smode
        return buf
      n = ccall_nobox("w_string_byte_length", subject) ## i64
      if n > buf.size()
        cap = buf.size() ## i64
        while cap < n
          cap = cap * 2
        buf = i64[cap]
        @subj_buf = buf
      ptr = ccall_nobox("w_string_data_ptr", subject) ## i64
      i = 0 ## i64
      while i < n
        buf[i] = tbl[raw_load_u8(ptr, i)]
        i = i + 1
      @subj_len = n
      return buf
    @subj_ascii = 0
    codes = subject.codes() ## i64[]
    n = codes.size() ## i64
    i = 0 ## i64
    while i < n
      codes[i] = codes[i] & 70368744177663
      i = i + 1
    @subj_len = n
    codes

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
      s_str_p = subject ## string
      if s_str_p.ascii?()
        @subj_ascii = 1
        if @pure_lit == 1
          pos = s_str_p.index(@pf_lit_str ## string, start)
          if pos == nil
            if smode == 1
              @@last_saved = nil
              @@last_subj_str = nil
            return nil
          s0_lit = pos ## i64
          saved[0] = s0_lit
          saved[1] = s0_lit + (@pf_lit_len ## i64)
          if smode == 1
            @@last_subj_str = subject
            @@last_subj = nil
            @@last_subj_len = s_str_p.size()
            @@last_saved = saved
            @@last_ncap = 1
            @@last_group_names = @group_names
          return saved
        if start > 0
          if smode == 1
            @@last_saved = nil
            @@last_subj_str = nil
          return nil
        ok_lit = @pure_lit == 2 ? s_str_p.starts_with?(@pf_lit_str) : (s_str_p == @pf_lit_str)
        if !ok_lit
          if smode == 1
            @@last_saved = nil
            @@last_subj_str = nil
          return nil
        saved[0] = 0
        saved[1] = @pf_lit_len ## i64
        if smode == 1
          @@last_subj_str = subject
          @@last_subj = nil
          @@last_subj_len = s_str_p.size()
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
      # Fast cold-ASCII pre-check on raw bytes before decoding @subj_buf:
      # rejects non-matching strings, advances start to the first candidate,
      # and completes pure-literal matches without decoding @subj_buf at all!
      if subject.ascii?() && (((wvalue_bits(subject) & -2) >> 1) & 7) >= 6
        n_ascii = ccall_nobox("w_string_byte_length", subject) ## i64
        ptr = ccall_nobox("w_string_data_ptr", subject) ## i64
        if pf_kind == 4
          pf_lit_raw = @pf_lit ## i64[]
          plen_raw = pf_lit_raw.size() ## i64
          lim_raw = n_ascii - plen_raw
          f_cp = (pf_lit_raw[0] >> 25) & 2097151
          l_cp = (pf_lit_raw[plen_raw - 1] >> 25) & 2097151
          if f_cp >= 128 || l_cp >= 128
            if smode == 1
              @@last_saved = nil
              @@last_subj_str = nil
            return nil
          ri = start
          start = n_ascii
          while ri <= lim_raw
            if raw_load_u8(ptr, ri) == f_cp && raw_load_u8(ptr, ri + plen_raw - 1) == l_cp
              rj = 1 ## i64
              while rj < plen_raw - 1 && raw_load_u8(ptr, ri + rj) == ((pf_lit_raw[rj] >> 25) & 2097151)
                rj = rj + 1
              if rj >= plen_raw - 1
                start = ri
                break
            ri = ri + 1
          if start >= n_ascii
            if smode == 1
              @@last_saved = nil
              @@last_subj_str = nil
            return nil
          if @pure_lit == 1
            @subj_ascii = 1
            if smode != 0
              saved[0] = start
              saved[1] = start + plen_raw
              if smode == 1
                @@last_subj_str = subject
                @@last_subj = nil
                @@last_subj_len = n_ascii
                @@last_saved = saved
                @@last_ncap = 1
                @@last_group_names = @group_names
            return saved
        elsif pf_kind == 1
          pf_cp = (pf_char >> 25) & 2097151
          while start < n_ascii && raw_load_u8(ptr, start) != pf_cp
            start = start + 1
          if start >= n_ascii
            if smode == 1
              @@last_saved = nil
              @@last_subj_str = nil
            return nil
        elsif pf_kind == 10
          pf_cp = (pf_char >> 25) & 2097151
          if start == 0
            start = 1
          while start < n_ascii && raw_load_u8(ptr, start - 1) != pf_cp
            start = start + 1
          if start >= n_ascii
            if smode == 1
              @@last_saved = nil
              @@last_subj_str = nil
            return nil
        elsif pf_kind == 6
          c1_cp = (pf_char >> 25) & 2097151
          c2_cp = (pf_flag >> 25) & 2097151
          while start < n_ascii
            b0 = raw_load_u8(ptr, start) ## i64
            if b0 == c1_cp || b0 == c2_cp
              break
            start = start + 1
          if start >= n_ascii
            if smode == 1
              @@last_saved = nil
              @@last_subj_str = nil
            return nil
        elsif pf_kind == 5
          lo_cp = (pf_char >> 25) & 2097151
          hi_cp = (pf_flag >> 25) & 2097151
          while start < n_ascii
            b0 = raw_load_u8(ptr, start) ## i64
            if b0 >= lo_cp && b0 <= hi_cp
              break
            start = start + 1
          if start >= n_ascii
            if smode == 1
              @@last_saved = nil
              @@last_subj_str = nil
            return nil
        elsif pf_kind == 7 && pf_char < 1073741824
          tbl_pf = @@ascii_lex ## i64[]
          while start < n_ascii
            b0 = raw_load_u8(ptr, start) ## i64
            if (((pf_char >> ((tbl_pf[b0] >> 3) & 31)) & 1) != pf_flag)
              break
            start = start + 1
          if start >= n_ascii
            if smode == 1
              @@last_saved = nil
              @@last_subj_str = nil
            return nil
        elsif pf_kind == 8
          while start < n_ascii
            b0 = raw_load_u8(ptr, start) ## i64
            if ((pfs89[b0 >> 5] >> (b0 & 31)) & 1) != 0
              break
            start = start + 1
          if start >= n_ascii
            if smode == 1
              @@last_saved = nil
              @@last_subj_str = nil
            return nil
        elsif pf_kind == 9
          lim9_r = n_ascii - 1
          while start < lim9_r
            b0 = raw_load_u8(ptr, start) ## i64
            if ((pfs89[b0 >> 5] >> (b0 & 31)) & 1) != 0
              b1 = raw_load_u8(ptr, start + 1) ## i64
              if ((pfs89[4 + (b1 >> 5)] >> (b1 & 31)) & 1) != 0
                break
            start = start + 1
          if start >= lim9_r
            if smode == 1
              @@last_saved = nil
              @@last_subj_str = nil
            return nil
        if req_char >= 0 && pf_kind != 4
          req_cp = (req_char >> 25) & 2097151
          if req_cp >= 128
            if smode == 1
              @@last_saved = nil
              @@last_subj_str = nil
            return nil
          ri = n_ascii - 1
          while ri >= start && raw_load_u8(ptr, ri) != req_cp
            ri = ri - 1
          if ri < start
            if smode == 1
              @@last_saved = nil
              @@last_subj_str = nil
            return nil
      @subj = decode_subject(subject)
      @subj_key = subject
    subj = @subj ## i64[]
    n = @subj_len ## i64
    subj_ascii = @subj_ascii ## i64
    ops = @op ## i64[]
    args_a = @a ## i64[]
    branches = @b ## i64[]
    if (@cap_fast_kind ## i64) > 0
      if (@cap_fast_kind ## i64) == 2
        sep1_c = args_a[7] ## i64
        sep2_c = args_a[12] ## i64
        stop_c = (n - 10) ## i64
        while start <= stop_c
          if subj[start + 4] == sep1_c
            if subj[start + 7] == sep2_c
              digs_c = (subj[start] & subj[start + 1] & subj[start + 2] & subj[start + 3] & subj[start + 5] & subj[start + 6] & subj[start + 8] & subj[start + 9]) ## i64
              if (digs_c & 1) != 0
                saved[0] = start
                saved[1] = start + 10
                saved[2] = start
                saved[3] = start + 4
                saved[4] = start + 5
                saved[5] = start + 7
                saved[6] = start + 8
                saved[7] = start + 10
                if smode == 1
                  @@last_subj_str = subject
                  @@last_subj = subj
                  @@last_subj_len = n
                  @@last_saved = saved
                  @@last_ncap = 4
                  @@last_group_names = @group_names
                return saved
          start = start + 1
        if smode == 1
          @@last_saved = nil
          @@last_subj_str = nil
        return nil
      plen_c = @pf_lit_len ## i64
      cmask_c = args_a[plen_c + 2] ## i64
      stop_c1 = (n - plen_c - 1) ## i64
      while start <= stop_c1
        if subj[start + plen_c - 1] == pf_flag
          if subj[start] == pf_char
            if (subj[start + plen_c] & cmask_c) != 0
              j_c = 1 ## i64
              if plen_c > 2
                pf_lit_c = @pf_lit ## i64[]
                while j_c < plen_c - 1
                  if subj[start + j_c] != pf_lit_c[j_c]
                    break
                  j_c = j_c + 1
              if j_c >= plen_c - 1
                cap_b = (start + plen_c) ## i64
                cap_e = (cap_b + 1) ## i64
                while cap_e + 3 < n
                  if (subj[cap_e] & subj[cap_e + 1] & subj[cap_e + 2] & subj[cap_e + 3] & cmask_c) == 0
                    break
                  cap_e = cap_e + 4
                while cap_e < n
                  if (subj[cap_e] & cmask_c) == 0
                    break
                  cap_e = cap_e + 1
                saved[0] = start
                saved[1] = cap_e
                saved[2] = cap_b
                saved[3] = cap_e
                if smode == 1
                  @@last_subj_str = subject
                  @@last_subj = subj
                  @@last_subj_len = n
                  @@last_saved = saved
                  @@last_ncap = 2
                  @@last_group_names = @group_names
                return saved
        start = start + 1
      if smode == 1
        @@last_saved = nil
        @@last_subj_str = nil
      return nil
    cls_bm = @cls_bm != nil ? (@cls_bm ## i64[]) : subj
    bm0 = 0 ## i64
    bm1 = 0 ## i64
    bm2 = 0 ## i64
    bm3 = 0 ## i64
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
    ch = 0 ## i64
    cp = 0 ## i64
    blk = 0 ## i64
    bm = 0 ## i64
    j = 0 ## i64
    limit = n - pf_lit_n
    first = 0 ## i64
    last = 0 ## i64
    if pf_kind == 4 && pf_lit_n > 0
      first = pf_lit[0] ## i64
      last = pf_lit[pf_lit_n - 1] ## i64
    i = 0 ## i64
    pc = 0 ## i64
    sp = 0 ## i64
    op = 0 ## i64
    mask = 0 ## i64
    tpc = 0 ## i64
    top = 0 ## i64
    e = 0 ## i64
    want = 0 ## i64
    cidx = 0 ## i64
    slot = 0 ## i64
    nop = 0 ## i64
    old = 0 ## i64
    u_cnt = 0 ## i64
    u_s0 = 0 ## i64
    u_v0 = 0 ## i64
    u_s1 = 0 ## i64
    u_v1 = 0 ## i64
    u_s2 = 0 ## i64
    u_v2 = 0 ## i64
    u_s3 = 0 ## i64
    u_v3 = 0 ## i64
    b_cnt = 0 ## i64
    b_pc0 = 0 ## i64
    b_sp0 = 0 ## i64
    b_u0 = 0 ## i64
    b_pc1 = 0 ## i64
    b_sp1 = 0 ## i64
    b_u1 = 0 ## i64
    b_pc2 = 0 ## i64
    b_sp2 = 0 ## i64
    b_u2 = 0 ## i64
    b_pc3 = 0 ## i64
    b_sp3 = 0 ## i64
    b_u3 = 0 ## i64
    tu = 0 ## i64
    lead_e = -1 ## i64
    at_pos = 0 ## i64
    s0 = 0 ## i64
    rg_pos = -1 ## i64
    rg_sp = 0 ## i64
    rg_cont = 0 ## i64
    while start <= max_start
      lead_e = -1
      if lead_after_char >= 0
        at_pos = start + 1
        while at_pos + 3 < n
          if subj[at_pos] == lead_after_char
            break
          if subj[at_pos + 1] == lead_after_char
            at_pos = at_pos + 1
            break
          if subj[at_pos + 2] == lead_after_char
            at_pos = at_pos + 2
            break
          if subj[at_pos + 3] == lead_after_char
            at_pos = at_pos + 3
            break
          at_pos = at_pos + 4
        while at_pos < n && subj[at_pos] != lead_after_char
          at_pos = at_pos + 1
        if at_pos >= n
          if smode == 1
            @@last_saved = nil
            @@last_subj_str = nil
          return nil
        s0 = at_pos
        tpc = (lead_rep_nb == 2 ? 4 : 3) ## i64
        top = ops[tpc] ## i64
        if top == 3
          cidx = (args_a[tpc] ## i64) * 6
          if smode == 0 && lead_rep_nb == 1
            ch = subj[s0 - 1] ## i64
            if subj_ascii == 1
              if ((cls_bm[cidx + (ch >> 30)] >> ((ch >> 25) & 31)) & 1) != 0
                s0 = s0 - 1
            else
              cp = (ch >> 25) & 2097151
              if cp < 128
                if ((cls_bm[cidx + (cp >> 5)] >> (cp & 31)) & 1) != 0
                  s0 = s0 - 1
              elsif (ch >= cls_bm[cidx + 4] && ch <= cls_bm[cidx + 5]) || class_match_slow?(@classes[args_a[tpc]], ch)
                s0 = s0 - 1
          elsif subj_ascii == 1
            bm0 = cls_bm[cidx] ## i64
            bm1 = cls_bm[cidx + 1] ## i64
            bm2 = cls_bm[cidx + 2] ## i64
            bm3 = cls_bm[cidx + 3] ## i64
            while s0 > start
              ch = subj[s0 - 1] ## i64
              blk = ch >> 30
              if blk < 2
                bm = (blk == 0 ? bm0 : bm1) ## i64
              else
                bm = (blk == 2 ? bm2 : bm3) ## i64
              if ((bm >> ((ch >> 25) & 31)) & 1) == 0
                break
              s0 = s0 - 1
          else
            bm2 = cls_bm[cidx + 4] ## i64
            bm3 = cls_bm[cidx + 5] ## i64
            while s0 > start
              ch = subj[s0 - 1] ## i64
              cp = (ch >> 25) & 2097151
              if cp < 128
                if ((cls_bm[cidx + (cp >> 5)] >> (cp & 31)) & 1) == 0
                  break
              elsif !(ch >= bm2 && ch <= bm3) && !class_match_slow?(@classes[args_a[tpc]], ch)
                break
              s0 = s0 - 1
        elsif top == 11
          mask = args_a[tpc] ## i64
          if branches[tpc] == 0
            if smode == 0 && lead_rep_nb == 1
              if (subj[s0 - 1] & mask) != 0
                s0 = s0 - 1
            else
              while s0 > start && (subj[s0 - 1] & mask) != 0
                s0 = s0 - 1
          else
            while s0 > start && (subj[s0 - 1] & mask) == 0
              s0 = s0 - 1
        elsif top == 17
          want = args_a[tpc] ## i64
          mask = branches[tpc] ## i64
          while s0 > start && subj[s0 - 1] >= want && subj[s0 - 1] <= mask
            s0 = s0 - 1
        else
          while s0 > start && consume_at?(tpc, subj[s0 - 1])
            s0 = s0 - 1
        if s0 == at_pos
          start = at_pos + 1
          next
        start = s0
        lead_e = at_pos
      elsif pf_kind != 0
        if pf_kind == 2
          while start <= max_start && (subj[start] & pf_char) == 0
            start = start + 1
        elsif pf_kind == 1
          while start <= max_start && subj[start] != pf_char
            start = start + 1
        elsif pf_kind == 10
          if start == 0
            start = 1
          while start <= max_start && subj[start - 1] != pf_char
            start = start + 1
        elsif pf_kind == 6
          while start <= max_start && subj[start] != pf_char && subj[start] != pf_flag
            start = start + 1
        elsif pf_kind == 8
          if subj_ascii == 1
            while start <= max_start
              ch = subj[start] ## i64
              if ((pf_char >> ((ch >> 25) & 31)) & 1) != 0 && ((pfs89[ch >> 30] >> ((ch >> 25) & 31)) & 1) != 0
                break
              start = start + 1
          else
            while start <= max_start
              ch = (subj[start] >> 25) & 2097151
              if ch < 128 && ((pf_char >> (ch & 31)) & 1) != 0 && ((pfs89[ch >> 5] >> (ch & 31)) & 1) != 0
                break
              start = start + 1
        elsif pf_kind == 9
          lim9_m = (max_start < n - 1 ? max_start : (n - 1)) ## i64
          if subj_ascii == 1 && start <= lim9_m
            ch = (subj[start] >> 25) & 31
            while start + 3 <= lim9_m
              cp = (subj[start + 1] >> 25) & 31
              blk = (subj[start + 2] >> 25) & 31
              bm = (subj[start + 3] >> 25) & 31
              j = (subj[start + 4] >> 25) & 31
              if ((((pf_char >> ch) & (pf_flag >> cp)) | ((pf_char >> cp) & (pf_flag >> blk)) | ((pf_char >> blk) & (pf_flag >> bm)) | ((pf_char >> bm) & (pf_flag >> j))) & 1) != 0
                break
              ch = j
              start = start + 4
            while start <= lim9_m
              cp = (subj[start + 1] >> 25) & 31
              if (((pf_char >> ch) & (pf_flag >> cp)) & 1) != 0
                break
              ch = cp
              start = start + 1
          elsif subj_ascii == 0
            while start <= lim9_m
              ch = (subj[start] >> 25) & 2097151
              if ch < 128 && ((pf_char >> (ch & 31)) & 1) != 0
                cp = (subj[start + 1] >> 25) & 2097151
                if cp < 128 && ((pf_flag >> (cp & 31)) & 1) != 0
                  break
              start = start + 1
          if start > lim9_m
            start = n
        elsif pf_kind == 3
          while start <= max_start
            ch = subj[start] ## i64
            if pf_flag != 0 && (ch & pf_flag) != 0
              break
            j = 0
            while j < pf_set_n && pf_set[j] != ch
              j = j + 1
            if j < pf_set_n
              break
            start = start + 1
        elsif pf_kind == 4
          i = start
          start = max_start + 1
          while i <= limit
            if subj[i] == first && subj[i + pf_lit_n - 1] == last
              j = 1
              while j < pf_lit_n - 1 && subj[i + j] == pf_lit[j]
                j = j + 1
              if j >= pf_lit_n - 1
                start = i
                break
            i = i + 1
          if start <= max_start && @pure_lit == 1
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
        elsif pf_kind == 5
          while start <= max_start && (subj[start] < pf_char || subj[start] > pf_flag)
            start = start + 1
        elsif pf_kind == 7
          if pf_char < 1073741824
            if pf_flag == 0
              while start <= max_start && ((pf_char >> ((subj[start] >> 3) & 31)) & 1) == 0
                start = start + 1
            else
              while start <= max_start && ((pf_char >> ((subj[start] >> 3) & 31)) & 1) != 0
                start = start + 1
          else
            while start <= max_start && !cat_match?(pf_char, pf_flag, subj[start])
              start = start + 1
        if start > max_start || start >= n
          if smode == 1
            @@last_saved = nil
            @@last_subj_str = nil
          return nil
      if linear == 1
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
        rg_pos = -1
        while true
          while true
            op = ops[pc] ## i64
            if op == 11
              mask = args_a[pc] ## i64
              if branches[pc] == 0
                if sp < n && (subj[sp] & mask) != 0
                  pc = pc + 1
                  sp = sp + 1
                  while ops[pc] == 11 && branches[pc] == 0 && sp < n && (subj[sp] & args_a[pc]) != 0
                    pc = pc + 1
                    sp = sp + 1
                else
                  break
              else
                if sp < n && (subj[sp] & mask) == 0
                  pc = pc + 1
                  sp = sp + 1
                else
                  break
            elsif op == 1
              if sp < n && subj[sp] == args_a[pc]
                pc = pc + 1
                sp = sp + 1
                while ops[pc] == 1
                  if sp < n && subj[sp] == args_a[pc]
                    pc = pc + 1
                    sp = sp + 1
                  else
                    pc = -1
                    break
                if pc < 0
                  break
                if ops[pc] == 5
                  pc = args_a[pc] ## i64
              else
                break
            elsif op == 7
              saved[args_a[pc]] = sp
              pc = pc + 1
              while ops[pc] == 7
                saved[args_a[pc]] = sp
                pc = pc + 1
            elsif op == 4
              if smode == 1
                @@last_subj_str = subject
                @@last_subj = subj
                @@last_subj_len = n
                @@last_saved = saved
                @@last_ncap = @ncap
                @@last_group_names = @group_names
              return saved
            elsif op == 18
              if sp < n && (subj[sp] == args_a[pc] || subj[sp] == branches[pc])
                pc = pc + 1
                sp = sp + 1
                while ops[pc] == 18
                  if sp < n && (subj[sp] == args_a[pc] || subj[sp] == branches[pc])
                    pc = pc + 1
                    sp = sp + 1
                  else
                    pc = -1
                    break
                if pc < 0
                  break
                if ops[pc] == 5
                  pc = args_a[pc] ## i64
              else
                break
            elsif op == 27
              if sp >= n
                while ops[pc] == 27
                  pc = branches[pc] ## i64
              else
                ch = subj[sp] ## i64
                while ops[pc] == 27
                  tpc = args_a[pc] ## i64
                  top = ops[tpc] ## i64
                  if top == 1
                    if ch == args_a[tpc]
                      sp = sp + 1
                      pc = tpc + 1
                      break
                  elsif ch == args_a[tpc] || ch == branches[tpc]
                    sp = sp + 1
                    pc = tpc + 1
                    break
                  pc = branches[pc] ## i64
            elsif op == 17
              if sp < n && subj[sp] >= args_a[pc] && subj[sp] <= branches[pc]
                pc = pc + 1
                sp = sp + 1
              else
                break
            elsif op == 19
              if sp < n
                want = args_a[pc] ## i64
                mask = branches[pc] ## i64
                if want < 1073741824
                  if (((want >> ((subj[sp] >> 3) & 31)) & 1) != mask)
                    pc = pc + 1
                    sp = sp + 1
                  else
                    break
                elsif cat_match?(want, mask, subj[sp])
                  pc = pc + 1
                  sp = sp + 1
                else
                  break
              else
                break
            elsif op == 16 || op == 14
              if op == 16 && smode == 0 && ops[branches[pc] + 1] == 4 && ops[branches[pc]] == 7
                return saved
              tpc = args_a[pc] ## i64
              top = ops[tpc] ## i64
              e = sp
              if top == 11
                mask = args_a[tpc] ## i64
                if branches[tpc] == 0
                  while e < n && (subj[e] & mask) != 0
                    e = e + 1
                else
                  while e < n && (subj[e] & mask) == 0
                    e = e + 1
              elsif top == 17
                want = args_a[tpc] ## i64
                mask = branches[tpc] ## i64
                while e < n && subj[e] >= want && subj[e] <= mask
                  e = e + 1
              elsif top == 1
                want = args_a[tpc] ## i64
                while e < n && subj[e] == want
                  e = e + 1
              elsif top == 18
                want = args_a[tpc] ## i64
                mask = branches[tpc] ## i64
                while e < n && (subj[e] == want || subj[e] == mask)
                  e = e + 1
              elsif top == 19
                want = args_a[tpc] ## i64
                mask = branches[tpc] ## i64
                if want < 1073741824 && mask == 0
                  while e < n && ((want >> ((subj[e] >> 3) & 31)) & 1) != 0
                    e = e + 1
                else
                  while e < n && cat_match?(want, mask, subj[e])
                    e = e + 1
              elsif top == 2
                want = args_a[tpc] ## i64
                while e < n && subj[e] != want
                  e = e + 1
              elsif top == 3
                cidx = (args_a[tpc] ## i64) * 6
                if subj_ascii == 1
                  bm0 = cls_bm[cidx] ## i64
                  bm1 = cls_bm[cidx + 1] ## i64
                  bm2 = cls_bm[cidx + 2] ## i64
                  bm3 = cls_bm[cidx + 3] ## i64
                  while e < n
                    ch = subj[e] ## i64
                    blk = ch >> 30
                    if blk < 2
                      bm = (blk == 0 ? bm0 : bm1) ## i64
                    else
                      bm = (blk == 2 ? bm2 : bm3) ## i64
                    if ((bm >> ((ch >> 25) & 31)) & 1) == 0
                      break
                    e = e + 1
                else
                  bm2 = cls_bm[cidx + 4] ## i64
                  bm3 = cls_bm[cidx + 5] ## i64
                  while e < n
                    ch = subj[e] ## i64
                    cp = (ch >> 25) & 2097151
                    if cp < 128
                      if ((cls_bm[cidx + (cp >> 5)] >> (cp & 31)) & 1) == 0
                        break
                    elsif !(ch >= bm2 && ch <= bm3) && !class_match_slow?(@classes[args_a[tpc]], ch)
                      break
                    e = e + 1
              if op == 16
                if (lead_rep_nb == 1 && pc == 2) || (lead_rep_nb == 2 && pc == 3)
                  lead_e = e
                sp = e
                pc = branches[pc] ## i64
              else
                rg_cont = branches[pc] ## i64
                rg_sp = sp
                rg_pos = e
                if ops[rg_cont] == 1
                  want = args_a[rg_cont] ## i64
                  if rg_pos == n
                    rg_pos = rg_pos - 1
                  while rg_pos >= rg_sp && subj[rg_pos] != want
                    rg_pos = rg_pos - 1
                  if rg_pos < rg_sp
                    break
                  sp = rg_pos + 1
                  pc = rg_cont + 1
                  rg_pos = rg_pos - 1
                else
                  sp = rg_pos
                  pc = rg_cont
                  rg_pos = rg_pos - 1
            elsif op == 3
              if sp < n
                ch = subj[sp] ## i64
                cidx = (args_a[pc] ## i64) * 6
                if subj_ascii == 1
                  if ((cls_bm[cidx + (ch >> 30)] >> ((ch >> 25) & 31)) & 1) != 0
                    pc = pc + 1
                    sp = sp + 1
                  else
                    break
                else
                  cp = (ch >> 25) & 2097151
                  if cp < 128
                    if ((cls_bm[cidx + (cp >> 5)] >> (cp & 31)) & 1) != 0
                      pc = pc + 1
                      sp = sp + 1
                    else
                      break
                  elsif (ch >= cls_bm[cidx + 4] && ch <= cls_bm[cidx + 5]) || class_match_slow?(@classes[args_a[pc]], ch)
                    pc = pc + 1
                    sp = sp + 1
                  else
                    break
              else
                break
            elsif op == 25
              want = branches[pc] ## i64
              top = want & 15
              tpc = args_a[pc] ## i64
              if tpc == pc + 3
                ch = args_a[pc + 1] ## i64
                if top == 1
                  if sp < n && subj[sp] == ch
                    pc = tpc
                  else
                    break
                elsif top == 2
                  if sp >= n || subj[sp] != ch
                    pc = tpc
                  else
                    break
                elsif top == 3
                  if sp > 0 && subj[sp - 1] == ch
                    pc = tpc
                  else
                    break
                else
                  if sp == 0 || subj[sp - 1] != ch
                    pc = tpc
                  else
                    break
              else
                ch = args_a[pc + 1] ## i64
                mask = args_a[pc + 2] ## i64
                if top == 1
                  if sp + 1 < n && subj[sp] == ch && subj[sp + 1] == mask
                    pc = tpc
                  else
                    break
                elsif top == 2
                  if sp + 1 >= n || subj[sp] != ch || subj[sp + 1] != mask
                    pc = tpc
                  else
                    break
                elsif top == 3
                  if sp >= 2 && subj[sp - 2] == ch && subj[sp - 1] == mask
                    pc = tpc
                  else
                    break
                else
                  if sp < 2 || subj[sp - 2] != ch || subj[sp - 1] != mask
                    pc = tpc
                  else
                    break
            elsif op == 2
              if sp < n && subj[sp] != args_a[pc]
                pc = pc + 1
                sp = sp + 1
              else
                break
            elsif op == 8
              if sp == 0 || subj[sp - 1] == nl
                pc = pc + 1
              else
                break
            elsif op == 9
              if sp == n || subj[sp] == nl
                pc = pc + 1
              else
                break
            elsif op == 20
              want = args_a[pc] ## i64
              if want == 1
                if sp == 0
                  pc = pc + 1
                else
                  break
              elsif want == 2
                if sp == n
                  pc = pc + 1
                else
                  break
              elsif want == 3
                if sp == n || (sp + 1 == n && subj[sp] == nl)
                  pc = pc + 1
                else
                  break
              elsif want == 4
                if sp == @search_from
                  pc = pc + 1
                else
                  break
              else
                break
            elsif op == 10
              if ((sp > 0 ? (subj[sp - 1] & 2) : 0) != (sp < n ? (subj[sp] & 2) : 0))
                if args_a[pc] != 1
                  break
              elsif args_a[pc] == 1
                break
              pc = pc + 1
            elsif op == 21
              slot = (args_a[pc] ## i64) * 2
              want = saved[slot] ## i64
              mask = saved[slot + 1] ## i64
              e = mask - want
              if want < 0 || mask < 0 || sp + e > n
                break
              j = 0
              while j < e && subj[sp + j] == subj[want + j]
                j = j + 1
              if j >= e
                sp = sp + e
                pc = pc + 1
              else
                break
            elsif op == 5
              pc = args_a[pc] ## i64
            else
              break
          if rg_pos < rg_sp
            break
          if ops[rg_cont] == 1
            want = args_a[rg_cont] ## i64
            while rg_pos >= rg_sp && subj[rg_pos] != want
              rg_pos = rg_pos - 1
            if rg_pos < rg_sp
              break
            sp = rg_pos + 1
            pc = rg_cont + 1
            rg_pos = rg_pos - 1
          else
            sp = rg_pos
            pc = rg_cont
            rg_pos = rg_pos - 1
      elsif linear == 2
        if lead_after_char >= 0
          u_s0 = 0
          u_v0 = saved[0] ## i64
          saved[0] = start
          if lead_rep_nb == 2
            u_cnt = 3
            u_s1 = 2
            u_v1 = saved[2] ## i64
            saved[2] = start
            u_s2 = 3
            u_v2 = saved[3] ## i64
            saved[3] = lead_e
            pc = 7
          else
            u_cnt = 1
            pc = 5
          sp = lead_e + 1
        else
          pc = 0
          sp = start
          u_cnt = 0
        b_cnt = 0
        while true
          op = ops[pc] ## i64
          if op == 1
            if sp < n && subj[sp] == args_a[pc]
              pc = pc + 1
              sp = sp + 1
            else
              pc = -1
          elsif op == 18
            if sp < n && (subj[sp] == args_a[pc] || subj[sp] == branches[pc])
              pc = pc + 1
              sp = sp + 1
            else
              pc = -1
          elsif op == 11
            mask = args_a[pc] ## i64
            if branches[pc] == 0
              if sp < n && (subj[sp] & mask) != 0
                pc = pc + 1
                sp = sp + 1
              else
                pc = -1
            else
              if sp < n && (subj[sp] & mask) == 0
                pc = pc + 1
                sp = sp + 1
              else
                pc = -1
          elsif op == 17
            if sp < n && subj[sp] >= args_a[pc] && subj[sp] <= branches[pc]
              pc = pc + 1
              sp = sp + 1
            else
              pc = -1
          elsif op == 19
            if sp < n && cat_match?(args_a[pc], branches[pc], subj[sp])
              pc = pc + 1
              sp = sp + 1
            else
              pc = -1
          elsif op == 16
            tpc = args_a[pc] ## i64
            top = ops[tpc] ## i64
            e = sp
            if top == 11
              mask = args_a[tpc] ## i64
              if branches[tpc] == 0
                while e < n && (subj[e] & mask) != 0
                  e = e + 1
              else
                while e < n && (subj[e] & mask) == 0
                  e = e + 1
            elsif top == 17
              want = args_a[tpc] ## i64
              mask = branches[tpc] ## i64
              while e < n && subj[e] >= want && subj[e] <= mask
                e = e + 1
            elsif top == 1
              want = args_a[tpc] ## i64
              while e < n && subj[e] == want
                e = e + 1
            elsif top == 18
              want = args_a[tpc] ## i64
              mask = branches[tpc] ## i64
              while e < n && (subj[e] == want || subj[e] == mask)
                e = e + 1
            elsif top == 19
              want = args_a[tpc] ## i64
              mask = branches[tpc] ## i64
              if want < 1073741824 && mask == 0
                while e < n && ((want >> ((subj[e] >> 3) & 31)) & 1) != 0
                  e = e + 1
              else
                while e < n && cat_match?(want, mask, subj[e])
                  e = e + 1
            elsif top == 2
              want = args_a[tpc] ## i64
              while e < n && subj[e] != want
                e = e + 1
            elsif top == 3
              cidx = (args_a[tpc] ## i64) * 6
              if subj_ascii == 1
                while e < n
                  ch = subj[e] ## i64
                  if ((cls_bm[cidx + (ch >> 30)] >> ((ch >> 25) & 31)) & 1) == 0
                    break
                  e = e + 1
              else
                bm2 = cls_bm[cidx + 4] ## i64
                bm3 = cls_bm[cidx + 5] ## i64
                while e < n
                  ch = subj[e] ## i64
                  cp = (ch >> 25) & 2097151
                  if cp < 128
                    if ((cls_bm[cidx + (cp >> 5)] >> (cp & 31)) & 1) == 0
                      break
                  elsif !(ch >= bm2 && ch <= bm3) && !class_match_slow?(@classes[args_a[tpc]], ch)
                    break
                  e = e + 1
            if (lead_rep_nb == 1 && pc == 2) || (lead_rep_nb == 2 && pc == 3)
              lead_e = e
            sp = e
            pc = branches[pc] ## i64
          elsif op == 7
            slot = args_a[pc] ## i64
            nop = ops[pc + 1] ## i64
            if nop == 4
              saved[slot] = sp
              if smode == 1
                @@last_subj_str = subject
                @@last_subj = subj
                @@last_subj_len = n
                @@last_saved = saved
                @@last_ncap = @ncap
                @@last_group_names = @group_names
              return saved
            if nop == 7 && ops[pc + 2] == 4
              saved[slot] = sp
              saved[args_a[pc + 1]] = sp
              if smode == 1
                @@last_subj_str = subject
                @@last_subj = subj
                @@last_subj_len = n
                @@last_saved = saved
                @@last_ncap = @ncap
                @@last_group_names = @group_names
              return saved
            if nop == 1 && (sp >= n || subj[sp] != args_a[pc + 1])
              pc = -1
            elsif u_cnt < 4
              old = saved[slot] ## i64
              if u_cnt == 0
                u_s0 = slot
                u_v0 = old
              elsif u_cnt == 1
                u_s1 = slot
                u_v1 = old
              elsif u_cnt == 2
                u_s2 = slot
                u_v2 = old
              else
                u_s3 = slot
                u_v3 = old
              u_cnt = u_cnt + 1
              saved[slot] = sp
              pc = pc + 1
            else
              saved[slot] = sp
              if run(pc + 1, sp, saved) >= 0
                if smode == 1
                  @@last_subj_str = subject
                  @@last_subj = subj
                  @@last_subj_len = n
                  @@last_saved = saved
                  @@last_ncap = @ncap
                  @@last_group_names = @group_names
                return saved
              pc = -1
          elsif op == 6
            tpc = args_a[pc] ## i64
            top = ops[tpc] ## i64
            if (top == 1 && (sp >= n || subj[sp] != args_a[tpc])) || (top == 7 && ops[tpc + 1] == 1 && (sp >= n || subj[sp] != args_a[tpc + 1]))
              pc = branches[pc] ## i64
            elsif b_cnt < 4
              if b_cnt == 0
                b_pc0 = branches[pc] ## i64
                b_sp0 = sp
                b_u0 = u_cnt
              elsif b_cnt == 1
                b_pc1 = branches[pc] ## i64
                b_sp1 = sp
                b_u1 = u_cnt
              elsif b_cnt == 2
                b_pc2 = branches[pc] ## i64
                b_sp2 = sp
                b_u2 = u_cnt
              else
                b_pc3 = branches[pc] ## i64
                b_sp3 = sp
                b_u3 = u_cnt
              b_cnt = b_cnt + 1
              pc = tpc
            else
              if run(tpc, sp, saved) >= 0
                if smode == 1
                  @@last_subj_str = subject
                  @@last_subj = subj
                  @@last_subj_len = n
                  @@last_saved = saved
                  @@last_ncap = @ncap
                  @@last_group_names = @group_names
                return saved
              pc = branches[pc] ## i64
          elsif op == 27
            tpc = args_a[pc] ## i64
            if sp < n
              ch = subj[sp] ## i64
              top = ops[tpc] ## i64
              if top == 1
                if ch == args_a[tpc]
                  sp = sp + 1
                  pc = tpc + 1
                else
                  pc = branches[pc] ## i64
              elsif ch == args_a[tpc] || ch == branches[tpc]
                sp = sp + 1
                pc = tpc + 1
              else
                pc = branches[pc] ## i64
            else
              pc = branches[pc] ## i64
          elsif op == 5
            pc = args_a[pc] ## i64
          elsif op == 4
            if smode == 1
              @@last_subj_str = subject
              @@last_subj = subj
              @@last_subj_len = n
              @@last_saved = saved
              @@last_ncap = @ncap
              @@last_group_names = @group_names
            return saved
          elsif op == 21
            slot = (args_a[pc] ## i64) * 2
            want = saved[slot] ## i64
            mask = saved[slot + 1] ## i64
            if want < 0 || mask < 0 || sp + (mask - want) > n
              pc = -1
            elsif branches[pc] == 0
              j = 0
              e = mask - want
              while j < e && subj[sp + j] == subj[want + j]
                j = j + 1
              if j >= e
                sp = sp + e
                pc = pc + 1
              else
                pc = -1
            else
              e = match_backref(args_a[pc], 1, sp, saved) ## i64
              if e >= 0
                sp = e
                pc = pc + 1
              else
                pc = -1
          elsif op == 3
            if sp < n
              ch = subj[sp] ## i64
              cidx = (args_a[pc] ## i64) * 6
              cp = (ch >> 25) & 2097151
              if cp < 128
                if ((cls_bm[cidx + (cp >> 5)] >> (cp & 31)) & 1) != 0
                  pc = pc + 1
                  sp = sp + 1
                else
                  pc = -1
              elsif (ch >= cls_bm[cidx + 4] && ch <= cls_bm[cidx + 5]) || class_match_slow?(@classes[args_a[pc]], ch)
                pc = pc + 1
                sp = sp + 1
              else
                pc = -1
            else
              pc = -1
          elsif op == 2
            if sp < n && subj[sp] != args_a[pc]
              pc = pc + 1
              sp = sp + 1
            else
              pc = -1
          elsif op == 8
            if sp == 0 || subj[sp - 1] == nl
              pc = pc + 1
            else
              pc = -1
          elsif op == 9
            if sp == n || subj[sp] == nl
              pc = pc + 1
            else
              pc = -1
          elsif op == 20
            want = args_a[pc] ## i64
            if want == 1
              if sp == 0
                pc = pc + 1
              else
                pc = -1
            elsif want == 2
              if sp == n
                pc = pc + 1
              else
                pc = -1
            elsif want == 3
              if sp == n || (sp + 1 == n && subj[sp] == nl)
                pc = pc + 1
              else
                pc = -1
            elsif want == 4
              if sp == @search_from
                pc = pc + 1
              else
                pc = -1
            else
              pc = -1
          elsif op == 10
            if at_word_boundary?(sp)
              if args_a[pc] != 1
                pc = -1
              else
                pc = pc + 1
            elsif args_a[pc] == 1
              pc = -1
            else
              pc = pc + 1
          else
            pc = -1
          if pc < 0
            if b_cnt > 0
              b_cnt = b_cnt - 1
              if b_cnt == 0
                pc = b_pc0
                sp = b_sp0
                tu = b_u0
              elsif b_cnt == 1
                pc = b_pc1
                sp = b_sp1
                tu = b_u1
              elsif b_cnt == 2
                pc = b_pc2
                sp = b_sp2
                tu = b_u2
              else
                pc = b_pc3
                sp = b_sp3
                tu = b_u3
              while u_cnt > tu
                u_cnt = u_cnt - 1
                if u_cnt == 0
                  saved[u_s0] = u_v0
                elsif u_cnt == 1
                  saved[u_s1] = u_v1
                elsif u_cnt == 2
                  saved[u_s2] = u_v2
                else
                  saved[u_s3] = u_v3
            else
              while u_cnt > 0
                u_cnt = u_cnt - 1
                if u_cnt == 0
                  saved[u_s0] = u_v0
                elsif u_cnt == 1
                  saved[u_s1] = u_v1
                elsif u_cnt == 2
                  saved[u_s2] = u_v2
                else
                  saved[u_s3] = u_v3
              break
      else
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
      s_str = subject ## string
      if lit_mode == 1
        return s_str.index(@pf_lit_str ## string) != nil
      if lit_mode == 2
        p_ptr = @pf_lit_ptr ## i64
        p_len = @pf_lit_bytes ## i64
        if p_ptr != 0 && ((sv_tag >> 1) & 7) >= 6
          if (ccall_nobox("w_string_byte_length", subject) ## i64) < p_len
            return false
          s_ptr = ccall_nobox("w_string_data_ptr", subject) ## i64
          si_p = 0 ## i64
          while si_p + 3 < p_len
            if raw_load_u8(s_ptr, si_p) != raw_load_u8(p_ptr, si_p) || raw_load_u8(s_ptr, si_p + 1) != raw_load_u8(p_ptr, si_p + 1) || raw_load_u8(s_ptr, si_p + 2) != raw_load_u8(p_ptr, si_p + 2) || raw_load_u8(s_ptr, si_p + 3) != raw_load_u8(p_ptr, si_p + 3)
              return false
            si_p = si_p + 4
          while si_p < p_len
            if raw_load_u8(s_ptr, si_p) != raw_load_u8(p_ptr, si_p)
              return false
            si_p = si_p + 1
          return true
        return s_str.starts_with?(@pf_lit_str)
      return s_str == @pf_lit_str
    if (@pf_exact_match ## i64) != 0
      return match_exact?(subject)
    find_saved_from(subject, 0, 0) != nil

  -> match_exact?(subject)
    if subject != @subj_key
      @subj = decode_subject(subject)
      @subj_key = subject
    subj = @subj ## i64[]
    n = @subj_len ## i64
    subj_ascii = @subj_ascii ## i64
    i = 0 ## i64
    kind = @pf_exact_match ## i64
    if (kind == 6 || kind == 7) && subj_ascii == 1
      args_a = @a ## i64[]
      bm9 = @pf_set ## i64[]
      pf1 = @pf_char ## i64
      pf2 = @pf_flag ## i64
      m_ic = (kind == 7 ? 1074233368 : 0) ## i64
      lim6 = (n - 1) ## i64
      s6 = 0 ## i64
      if s6 >= lim6
        return false
      ch6 = ((subj[0] >> 25) & 31) ## i64
      cp6 = 0 ## i64
      while s6 < lim6
        while s6 < lim6
          cp6 = ((subj[s6 + 1] >> 25) & 31) ## i64
          if (((pf1 >> ch6) & (pf2 >> cp6)) & 1) != 0
            break
          ch6 = cp6
          s6 = s6 + 1
        if s6 >= lim6
          return false
        ent6 = bm9[8 + ch6] ## i64
        pc6 = (ent6 & 65535) ## i64
        end_pc = (ent6 >> 16) ## i64
        sp6 = (s6 + (end_pc - pc6)) ## i64
        if sp6 <= n && (subj[sp6 - 1] | m_ic) == (args_a[end_pc - 1] | m_ic) && (subj[s6] | m_ic) == (args_a[pc6] | m_ic)
          pc6 = pc6 + 1
          k6 = (s6 + 1) ## i64
          end_mid = (end_pc - 1) ## i64
          while pc6 < end_mid && (subj[k6] | m_ic) == (args_a[pc6] | m_ic)
            pc6 = pc6 + 1
            k6 = k6 + 1
          if pc6 >= end_mid
            return true
        ch6 = cp6
        s6 = s6 + 1
      return false
    if kind == 8
      ops = @op ## i64[]
      args_a = @a ## i64[]
      end8 = (ops.size() - 2) ## i64
      plen8 = (end8 - 1) ## i64
      lim8 = (n - plen8) ## i64
      m8 = @pf_char ## i64
      if end8 == 11
        if ops[5] == 1
          if ops[8] == 1
            sep1_8 = args_a[5] ## i64
            sep2_8 = args_a[8] ## i64
            while i <= lim8
              if subj[i + 4] == sep1_8
                if subj[i + 7] == sep2_8
                  if (subj[i] & subj[i + 1] & subj[i + 2] & subj[i + 3] & subj[i + 5] & subj[i + 6] & subj[i + 8] & subj[i + 9] & m8) != 0
                    return true
              i = i + 1
            return false
      while i <= lim8
        if (subj[i] & m8) != 0
          pc8 = 2 ## i64
          while pc8 < end8
            ch8 = subj[i + pc8 - 1] ## i64
            if ops[pc8] == 11
              if (ch8 & args_a[pc8]) == 0
                break
            elsif ch8 != args_a[pc8]
              break
            pc8 = pc8 + 1
          if pc8 >= end8
            return true
        i = i + 1
      return false
    if kind >= 9
      if kind == 9
        args_a = @a ## i64[]
        ch9 = args_a[5] ## i64
        m9 = args_a[1] ## i64
        i = 1 ## i64
        while i + 3 < n
          if subj[i] == ch9 || subj[i + 1] == ch9 || subj[i + 2] == ch9 || subj[i + 3] == ch9
            if subj[i] == ch9 && (subj[i - 1] & m9) != 0
              return true
            if subj[i + 1] == ch9 && (subj[i] & m9) != 0
              return true
            if subj[i + 2] == ch9 && (subj[i + 1] & m9) != 0
              return true
            if subj[i + 3] == ch9 && (subj[i + 2] & m9) != 0
              return true
          i = i + 4
        while i < n
          if subj[i] == ch9 && (subj[i - 1] & m9) != 0
            return true
          i = i + 1
        return false
      if kind == 10
        args_a = @a ## i64[]
        m10 = args_a[1] ## i64
        c1_10 = args_a[5] ## i64
        c2_10 = args_a[6] ## i64
        skip2_10 = (((c1_10 | c2_10) & m10) == 0 ? 2 : 1) ## i64
        while i < n
          if (subj[i] & m10) != 0
            i = i + 1
            while i < n && (subj[i] & m10) != 0
              i = i + 1
            if i + 1 >= n || subj[i] != c1_10 || subj[i + 1] != c2_10
              return true
            i = i + skip2_10
          else
            i = i + 1
        return false
      if kind == 11
        args_a = @a ## i64[]
        c11 = args_a[2] ## i64
        m11 = args_a[5] ## i64
        while i < n
          if (subj[i] & m11) != 0
            if i == 0 || (subj[i - 1] != c11 && (subj[i - 1] & 2) == 0)
              return true
            i = i + 1
            while i < n && (subj[i] & 2) != 0
              i = i + 1
          else
            i = i + 1
        return false
      if kind == 14
        args_a = @a ## i64[]
        c14 = @pf_char ## i64
        m14 = args_a[4] ## i64
        lim14 = (n - 1) ## i64
        while i + 3 < lim14
          if subj[i] == c14 || subj[i + 1] == c14 || subj[i + 2] == c14 || subj[i + 3] == c14
            if subj[i] == c14 && (subj[i + 1] & m14) != 0
              return true
            if subj[i + 1] == c14 && (subj[i + 2] & m14) != 0
              return true
            if subj[i + 2] == c14 && (subj[i + 3] & m14) != 0
              return true
            if subj[i + 3] == c14 && (subj[i + 4] & m14) != 0
              return true
          i = i + 4
        while i < lim14
          if subj[i] == c14 && (subj[i + 1] & m14) != 0
            return true
          i = i + 1
        return false
      if kind == 15
        args_a = @a ## i64[]
        m1_15 = args_a[1] ## i64
        sep15 = args_a[4] ## i64
        m2_15 = args_a[5] ## i64
        lim15 = (n - 1) ## i64
        i = 1 ## i64
        while i + 3 < lim15
          if subj[i] == sep15 || subj[i + 1] == sep15 || subj[i + 2] == sep15 || subj[i + 3] == sep15
            if subj[i] == sep15 && (subj[i - 1] & m1_15) != 0 && (subj[i + 1] & m2_15) != 0
              return true
            if subj[i + 1] == sep15 && (subj[i] & m1_15) != 0 && (subj[i + 2] & m2_15) != 0
              return true
            if subj[i + 2] == sep15 && (subj[i + 1] & m1_15) != 0 && (subj[i + 3] & m2_15) != 0
              return true
            if subj[i + 3] == sep15 && (subj[i + 2] & m1_15) != 0 && (subj[i + 4] & m2_15) != 0
              return true
          i = i + 4
        while i < lim15
          if subj[i] == sep15 && (subj[i - 1] & m1_15) != 0 && (subj[i + 1] & m2_15) != 0
            return true
          i = i + 1
        return false
      if kind == 16
        args_a = @a ## i64[]
        m16 = args_a[2] ## i64
        sep16 = args_a[6] ## i64
        lim16 = (n - 1) ## i64
        at16 = 1 ## i64
        while at16 < lim16
          while at16 + 3 < lim16
            if subj[at16] == sep16 || subj[at16 + 1] == sep16 || subj[at16 + 2] == sep16 || subj[at16 + 3] == sep16
              break
            at16 = at16 + 4
          while at16 < lim16 && subj[at16] != sep16
            at16 = at16 + 1
          if at16 >= lim16
            return false
          if (subj[at16 - 1] & m16) != 0
            s16 = (at16 - 1) ## i64
            while s16 > 0 && (subj[s16 - 1] & m16) != 0
              s16 = s16 - 1
            while s16 < at16
              len16 = (at16 - s16) ## i64
              if at16 + len16 < n
                k16 = 0 ## i64
                while k16 < len16 && subj[s16 + k16] == subj[at16 + 1 + k16]
                  k16 = k16 + 1
                if k16 >= len16
                  return true
              s16 = s16 + 1
          at16 = at16 + 1
        return false
      if kind == 12 && subj_ascii == 1
        args_a = @a ## i64[]
        branches = @b ## i64[]
        cbm12 = @cls_bm ## i64[]
        sep12 = args_a[4] ## i64
        c0_12 = (args_a[1] ## i64) * 6
        lo12 = args_a[5] ## i64
        hi12 = branches[5] ## i64
        lim12 = (n - 1) ## i64
        i = 1 ## i64
        while i < lim12
          if subj[i] == sep12
            ch_n12 = subj[i + 1] ## i64
            if ch_n12 >= lo12 && ch_n12 <= hi12
              ch_p12 = subj[i - 1] ## i64
              if ((cbm12[c0_12 + (ch_p12 >> 30)] >> ((ch_p12 >> 25) & 31)) & 1) != 0
                return true
          i = i + 1
        return false
    if kind == 1
      mask = @pf_char ## i64
      while i < n
        if (subj[i] & mask) != 0
          return true
        i = i + 1
      return false
    if kind == 2
      if subj_ascii != 1
        return find_saved_from(subject, 0, 0) != nil
      bm = @pf_set ## i64[]
      m32 = @pf_char ## i64
      while i < n
        ch = subj[i] ## i64
        if ((m32 >> ((ch >> 25) & 31)) & 1) != 0 && ((bm[ch >> 30] >> ((ch >> 25) & 31)) & 1) != 0
          return true
        i = i + 1
      return false
    if kind == 3
      lo = @pf_char ## i64
      hi = @pf_flag ## i64
      if @classes == nil
        while i < n
          ch = subj[i] ## i64
          if ch >= lo && ch <= hi
            return true
          i = i + 1
        return false
      cbm = @cls_bm ## i64[]
      rlo = cbm[4] ## i64
      rhi = cbm[5] ## i64
      while i < n
        ch = subj[i] ## i64
        if ch >= lo && ch <= hi
          if (ch >= rlo && ch <= rhi) || class_match_slow?(@classes[0], ch)
            return true
        i = i + 1
      return false
    if kind == 4
      m1 = @pf_char ## i64
      m2 = @a[2] ## i64
      lim = (n - 1) ## i64
      while i < lim
        if (((m1 >> ((subj[i] >> 3) & 31)) & (m2 >> ((subj[i + 1] >> 3) & 31))) & 1) != 0
          return true
        i = i + 1
      return false
    if kind == 5 && subj_ascii == 1
      cbm5 = @cls_bm ## i64[]
      args_a = @a ## i64[]
      lead_ch = @lead_after_char ## i64
      dot_ch = args_a[8] ## i64
      c0_b = (args_a[1] ## i64) * 6
      c1_b = (args_a[5] ## i64) * 6
      c2_b = (args_a[9] ## i64) * 6
      b1_0 = cbm5[c1_b] ## i64
      b1_1 = cbm5[c1_b + 1] ## i64
      b1_2 = cbm5[c1_b + 2] ## i64
      b1_3 = cbm5[c1_b + 3] ## i64
      at_pos = 1 ## i64
      while at_pos < n
        while at_pos + 3 < n
          if subj[at_pos] == lead_ch || subj[at_pos + 1] == lead_ch || subj[at_pos + 2] == lead_ch || subj[at_pos + 3] == lead_ch
            break
          at_pos = at_pos + 4
        while at_pos < n && subj[at_pos] != lead_ch
          at_pos = at_pos + 1
        if at_pos >= n
          return false
        ch_prev = subj[at_pos - 1] ## i64
        if ((cbm5[c0_b + (ch_prev >> 30)] >> ((ch_prev >> 25) & 31)) & 1) != 0
          e = (at_pos + 1) ## i64
          while e < n
            ch = subj[e] ## i64
            blk = (ch >> 30) ## i64
            if blk < 2
              bm_cur = (blk == 0 ? b1_0 : b1_1) ## i64
            else
              bm_cur = (blk == 2 ? b1_2 : b1_3) ## i64
            if ((bm_cur >> ((ch >> 25) & 31)) & 1) == 0
              break
            e = e + 1
          if e > at_pos + 1 && e + 2 < n && subj[e] == dot_ch
            c_t1 = subj[e + 1] ## i64
            c_t2 = subj[e + 2] ## i64
            if ((cbm5[c2_b + (c_t1 >> 30)] >> ((c_t1 >> 25) & 31)) & 1) != 0 && ((cbm5[c2_b + (c_t2 >> 30)] >> ((c_t2 >> 25) & 31)) & 1) != 0
              return true
        at_pos = at_pos + 1
      return false
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
      subj = @subj ## i64[]
      n = @subj_len ## i64
      is_ascii_f = (@subj_ascii ## i64) == 1
      i = 0 ## i64
      while i < n
        while i < n && (subj[i] & mask) == 0
          i = i + 1
        if i >= n
          break
        b0_f = i ## i64
        i = i + 1
        while i < n && (subj[i] & mask) != 0
          i = i + 1
        out.push(is_ascii_f ? s_str.slice(b0_f, i - b0_f) : Regex.span_from(subj, b0_f, i))
      return out
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
      subj = @subj ## i64[]
      n = @subj_len ## i64
      is_ascii_f = (@subj_ascii ## i64) == 1
      i = 0 ## i64
      while i < n && (subj[i] & mask) == 0
        i = i + 1
      if i >= n
        return subject
      sb_f = StringBuffer(n + 16)
      last_f = 0 ## i64
      while i < n
        if i > last_f
          if is_ascii_f
            if i - last_f == 1
              sb_f.append(wvalue_from_bits((-1_970_324_836_974_590 | (((subj[last_f] >> 25) & 255) << 4)) ## i64))
            else
              sb_f.append(s_str.slice(last_f, i - last_f))
          else
            sb_f.append(Regex.span_from(subj, last_f, i))
        i = i + 1
        while i < n && (subj[i] & mask) != 0
          i = i + 1
        sb_f.append(replacement)
        last_f = i
        while i < n && (subj[i] & mask) == 0
          i = i + 1
      if last_f < n
        if is_ascii_f
          if n - last_f == 1
            sb_f.append(wvalue_from_bits((-1_970_324_836_974_590 | (((subj[last_f] >> 25) & 255) << 4)) ## i64))
          else
            sb_f.append(s_str.slice(last_f, n - last_f))
        else
          sb_f.append(Regex.span_from(subj, last_f, n))
      return sb_f.to_s()
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
      args_s = @a ## i64[]
      m1_s = args_s[2] ## i64
      delim_s = args_s[3] ## i64
      m2_s = args_s[5] ## i64
      if subject != @subj_key
        @subj = decode_subject(subject)
        @subj_key = subject
      subj = @subj ## i64[]
      n = @subj_len ## i64
      is_ascii_s = (@subj_ascii ## i64) == 1
      last_s = 0 ## i64
      i_s = 0 ## i64
      while i_s < n
        while i_s < n && subj[i_s] != delim_s
          i_s = i_s + 1
        if i_s >= n
          break
        b0_s = i_s ## i64
        while b0_s > last_s && (subj[b0_s - 1] & m1_s) != 0
          b0_s = b0_s - 1
        e0_s = (i_s + 1) ## i64
        while e0_s < n && (subj[e0_s] & m2_s) != 0
          e0_s = e0_s + 1
        if is_ascii_s
          if b0_s - last_s == 1
            out.push(wvalue_from_bits((-1_970_324_836_974_590 | (((subj[last_s] >> 25) & 255) << 4)) ## i64))
          else
            out.push(s_str.slice(last_s, b0_s - last_s))
        else
          out.push(span_str(last_s, b0_s))
        last_s = e0_s
        i_s = e0_s
      if is_ascii_s
        if n - last_s == 1
          out.push(wvalue_from_bits((-1_970_324_836_974_590 | (((subj[last_s] >> 25) & 255) << 4)) ## i64))
        else
          out.push(s_str.slice(last_s, n - last_s))
      else
        out.push(span_str(last_s, n))
      return out
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
    subj = @subj ## i64[]
    n = @subj_len ## i64
    ops = @op ## i64[]
    args_a = @a ## i64[]
    branches = @b ## i64[]
    guard = @guard ## i64[]
    saved = saved_in ## i64[]
    nl = @nl ## i64
    pc = pc_in ## i64
    sp = sp_in ## i64
    u_cnt = 0 ## i64
    u_s0 = 0 ## i64
    u_v0 = 0 ## i64
    u_s1 = 0 ## i64
    u_v1 = 0 ## i64
    u_s2 = 0 ## i64
    u_v2 = 0 ## i64
    u_s3 = 0 ## i64
    u_v3 = 0 ## i64
    b_cnt = 0 ## i64
    b_pc0 = 0 ## i64
    b_sp0 = 0 ## i64
    b_u0 = 0 ## i64
    b_pc1 = 0 ## i64
    b_sp1 = 0 ## i64
    b_u1 = 0 ## i64
    b_pc2 = 0 ## i64
    b_sp2 = 0 ## i64
    b_u2 = 0 ## i64
    b_pc3 = 0 ## i64
    b_sp3 = 0 ## i64
    b_u3 = 0 ## i64
    tu = 0 ## i64
    res = -1 ## i64
    op = 0 ## i64
    mask = 0 ## i64
    tpc = 0 ## i64
    top = 0 ## i64
    e = 0 ## i64
    want = 0 ## i64
    cidx = 0 ## i64
    cont = 0 ## i64
    pos = 0 ## i64
    r = 0 ## i64
    slot = 0 ## i64
    nop = 0 ## i64
    old = 0 ## i64
    g = 0 ## i64
    while true
      op = ops[pc] ## i64
      if op == 1
        if sp < n && subj[sp] == args_a[pc]
          pc = pc + 1
          sp = sp + 1
        else
          pc = -1
      elsif op == 18
        if sp < n && (subj[sp] == args_a[pc] || subj[sp] == branches[pc])
          pc = pc + 1
          sp = sp + 1
        else
          pc = -1
      elsif op == 11
        mask = args_a[pc] ## i64
        if branches[pc] == 0
          if sp < n && (subj[sp] & mask) != 0
            pc = pc + 1
            sp = sp + 1
          else
            pc = -1
        else
          if sp < n && (subj[sp] & mask) == 0
            pc = pc + 1
            sp = sp + 1
          else
            pc = -1
      elsif op == 2
        if sp < n && subj[sp] != args_a[pc]
          pc = pc + 1
          sp = sp + 1
        else
          pc = -1
      elsif op == 3
        if sp < n && class_match?(args_a[pc], subj[sp])
          pc = pc + 1
          sp = sp + 1
        else
          pc = -1
      elsif op == 17
        if sp < n && subj[sp] >= args_a[pc] && subj[sp] <= branches[pc]
          pc = pc + 1
          sp = sp + 1
        else
          pc = -1
      elsif op == 19
        if sp < n && cat_match?(args_a[pc], branches[pc], subj[sp])
          pc = pc + 1
          sp = sp + 1
        else
          pc = -1
      elsif op == 16
        tpc = args_a[pc] ## i64
        top = ops[tpc] ## i64
        e = sp
        if top == 11
          mask = args_a[tpc] ## i64
          if branches[tpc] == 0
            while e < n && (subj[e] & mask) != 0
              e = e + 1
          else
            while e < n && (subj[e] & mask) == 0
              e = e + 1
        elsif top == 17
          want = args_a[tpc] ## i64
          mask = branches[tpc] ## i64
          while e < n && subj[e] >= want && subj[e] <= mask
            e = e + 1
        elsif top == 1
          want = args_a[tpc] ## i64
          while e < n && subj[e] == want
            e = e + 1
        elsif top == 18
          want = args_a[tpc] ## i64
          mask = branches[tpc] ## i64
          while e < n && (subj[e] == want || subj[e] == mask)
            e = e + 1
        elsif top == 19
          want = args_a[tpc] ## i64
          mask = branches[tpc] ## i64
          while e < n && cat_match?(want, mask, subj[e])
            e = e + 1
        elsif top == 2
          want = args_a[tpc] ## i64
          while e < n && subj[e] != want
            e = e + 1
        elsif top == 3
          cidx = args_a[tpc] ## i64
          while e < n && class_match?(cidx, subj[e])
            e = e + 1
        sp = e
        pc = branches[pc] ## i64
      elsif op == 14
        tpc = args_a[pc] ## i64
        top = ops[tpc] ## i64
        e = sp
        if top == 11
          mask = args_a[tpc] ## i64
          if branches[tpc] == 0
            while e < n && (subj[e] & mask) != 0
              e = e + 1
          else
            while e < n && (subj[e] & mask) == 0
              e = e + 1
        elsif top == 17
          want = args_a[tpc] ## i64
          mask = branches[tpc] ## i64
          while e < n && subj[e] >= want && subj[e] <= mask
            e = e + 1
        elsif top == 1
          want = args_a[tpc] ## i64
          while e < n && subj[e] == want
            e = e + 1
        elsif top == 18
          want = args_a[tpc] ## i64
          mask = branches[tpc] ## i64
          while e < n && (subj[e] == want || subj[e] == mask)
            e = e + 1
        elsif top == 19
          want = args_a[tpc] ## i64
          mask = branches[tpc] ## i64
          while e < n && cat_match?(want, mask, subj[e])
            e = e + 1
        elsif top == 2
          want = args_a[tpc] ## i64
          while e < n && subj[e] != want
            e = e + 1
        elsif top == 3
          cidx = args_a[tpc] ## i64
          while e < n && class_match?(cidx, subj[e])
            e = e + 1
        cont = branches[pc] ## i64
        pos = e
        if ops[cont] == 1
          want = args_a[cont] ## i64
          if pos == n
            pos = pos - 1
          while pos >= sp
            if subj[pos] == want
              r = run(cont + 1, pos + 1, saved) ## i64
              if r >= 0
                return r
            pos = pos - 1
        else
          while pos >= sp
            r = run(cont, pos, saved) ## i64
            if r >= 0
              return r
            pos = pos - 1
        pc = -1
      elsif op == 15
        tpc = args_a[pc] ## i64
        top = ops[tpc] ## i64
        e = sp
        if top == 11
          mask = args_a[tpc] ## i64
          if branches[tpc] == 0
            while e < n && (subj[e] & mask) != 0
              e = e + 1
          else
            while e < n && (subj[e] & mask) == 0
              e = e + 1
        elsif top == 17
          want = args_a[tpc] ## i64
          mask = branches[tpc] ## i64
          while e < n && subj[e] >= want && subj[e] <= mask
            e = e + 1
        elsif top == 1
          want = args_a[tpc] ## i64
          while e < n && subj[e] == want
            e = e + 1
        elsif top == 18
          want = args_a[tpc] ## i64
          mask = branches[tpc] ## i64
          while e < n && (subj[e] == want || subj[e] == mask)
            e = e + 1
        elsif top == 19
          want = args_a[tpc] ## i64
          mask = branches[tpc] ## i64
          while e < n && cat_match?(want, mask, subj[e])
            e = e + 1
        elsif top == 2
          want = args_a[tpc] ## i64
          while e < n && subj[e] != want
            e = e + 1
        elsif top == 3
          cidx = args_a[tpc] ## i64
          while e < n && class_match?(cidx, subj[e])
            e = e + 1
        cont = branches[pc] ## i64
        pos = sp
        if ops[cont] == 1
          want = args_a[cont] ## i64
          while pos <= e
            if pos < n && subj[pos] == want
              r = run(cont + 1, pos + 1, saved) ## i64
              if r >= 0
                return r
            pos = pos + 1
        else
          while pos <= e
            r = run(cont, pos, saved) ## i64
            if r >= 0
              return r
            pos = pos + 1
        pc = -1
      elsif op == 4
        return sp
      elsif op == 26
        if args_a[pc] == 0 || sp == @lookb_target
          return sp
        pc = -1
      elsif op == 25
        if @ncap == 1
          want = branches[pc] ## i64
          top = want & 15
          if top == 1
            if run(pc + 1, sp, saved) >= 0
              pc = args_a[pc] ## i64
            else
              pc = -1
          elsif top == 2
            if run(pc + 1, sp, saved) >= 0
              pc = -1
            else
              pc = args_a[pc] ## i64
          elsif top == 5
            e = run(pc + 1, sp, saved) ## i64
            if e >= 0
              sp = e
              pc = args_a[pc] ## i64
            else
              pc = -1
          else
            if eval_lookbehind(pc, sp, saved)
              pc = args_a[pc] ## i64
            else
              pc = -1
        else
          r = run_assert_cap(pc, sp, saved) ## i64
          if r >= 0
            return r
          pc = -1
      elsif op == 27
        tpc = args_a[pc] ## i64
        if sp < n
          want = subj[sp] ## i64
          top = ops[tpc] ## i64
          if top == 1
            if want == args_a[tpc]
              sp = sp + 1
              pc = tpc + 1
            else
              pc = branches[pc] ## i64
          elsif want == args_a[tpc] || want == branches[tpc]
            sp = sp + 1
            pc = tpc + 1
          else
            pc = branches[pc] ## i64
        else
          pc = branches[pc] ## i64
      elsif op == 5
        pc = args_a[pc] ## i64
      elsif op == 6
        tpc = args_a[pc] ## i64
        top = ops[tpc] ## i64
        if (top == 1 && (sp >= n || subj[sp] != args_a[tpc])) || (top == 7 && ops[tpc + 1] == 1 && (sp >= n || subj[sp] != args_a[tpc + 1]))
          pc = branches[pc] ## i64
        elsif !@has_subcall && b_cnt < 4
          if b_cnt == 0
            b_pc0 = branches[pc] ## i64
            b_sp0 = sp
            b_u0 = u_cnt
          elsif b_cnt == 1
            b_pc1 = branches[pc] ## i64
            b_sp1 = sp
            b_u1 = u_cnt
          elsif b_cnt == 2
            b_pc2 = branches[pc] ## i64
            b_sp2 = sp
            b_u2 = u_cnt
          else
            b_pc3 = branches[pc] ## i64
            b_sp3 = sp
            b_u3 = u_cnt
          b_cnt = b_cnt + 1
          pc = tpc
        else
          old = @cs_top ## i64
          r = run(tpc, sp, saved) ## i64
          if r >= 0
            return r
          @cs_top = old
          pc = branches[pc] ## i64
      elsif op == 7
        slot = args_a[pc] ## i64
        nop = ops[pc + 1] ## i64
        if nop == 4
          saved[slot] = sp
          return sp
        if nop == 7 && ops[pc + 2] == 4
          saved[slot] = sp
          saved[args_a[pc + 1]] = sp
          return sp
        if nop == 1 && (sp >= n || subj[sp] != args_a[pc + 1])
          pc = -1
        else
          old = saved[slot] ## i64
          if u_cnt < 4
            if u_cnt == 0
              u_s0 = slot
              u_v0 = old
            elsif u_cnt == 1
              u_s1 = slot
              u_v1 = old
            elsif u_cnt == 2
              u_s2 = slot
              u_v2 = old
            else
              u_s3 = slot
              u_v3 = old
            u_cnt = u_cnt + 1
            saved[slot] = sp
            pc = pc + 1
          else
            saved[slot] = sp
            r = run(pc + 1, sp, saved) ## i64
            if r >= 0
              return r
            saved[slot] = old
            pc = -1
      elsif op == 12
        g = args_a[pc] ## i64
        if !@has_backref && !@has_subcall
          memo = @memo ## i64[]
          midx = g * (n + 1) + sp
          if memo[midx] == @memo_gen
            pc = -1
          else
            memo[midx] = @memo_gen
            old = guard[g] ## i64
            guard[g] = sp
            r = run(pc + 1, sp, saved) ## i64
            if r >= 0
              return r
            guard[g] = old
            pc = -1
        else
          old = guard[g] ## i64
          guard[g] = sp
          r = run(pc + 1, sp, saved) ## i64
          if r >= 0
            return r
          guard[g] = old
          pc = -1
      elsif op == 13
        g = args_a[pc] ## i64
        if sp == guard[g]
          pc = -1
        else
          pc = pc + 1
      elsif op == 8
        if sp == 0 || subj[sp - 1] == nl
          pc = pc + 1
        else
          pc = -1
      elsif op == 9
        if sp == n || subj[sp] == nl
          pc = pc + 1
        else
          pc = -1
      elsif op == 20
        want = args_a[pc] ## i64
        if want == 1
          if sp == 0
            pc = pc + 1
          else
            pc = -1
        elsif want == 2
          if sp == n
            pc = pc + 1
          else
            pc = -1
        elsif want == 3
          if sp == n || (sp + 1 == n && subj[sp] == nl)
            pc = pc + 1
          else
            pc = -1
        elsif want == 4
          if sp == @search_from
            pc = pc + 1
          else
            pc = -1
        else
          pc = -1
      elsif op == 21
        g = args_a[pc] ## i64
        want = branches[pc] ## i64
        e = match_backref(g, want, sp, saved) ## i64
        if e >= 0
          sp = e
          pc = pc + 1
        else
          pc = -1
      elsif op == 22
        tpc = args_a[pc] ## i64
        g = branches[pc] ## i64
        cs_ret = @cs_ret ## i64[]
        cs_par = @cs_par ## i64[]
        cs_grp = @cs_grp ## i64[]
        cs_ost = @cs_ost ## i64[]
        cs_ret.push(pc + 1)
        cs_par.push(@cs_top)
        cs_grp.push(g)
        if g > 0 && saved[g * 2] >= 0 && saved[g * 2 + 1] < 0
          cs_ost.push(saved[g * 2])
        else
          cs_ost.push(-1)
        @cs_top = cs_ret.size() - 1
        pc = tpc
      elsif op == 23
        top = @cs_top ## i64
        if top < 0
          return sp
        cs_ret = @cs_ret ## i64[]
        cs_par = @cs_par ## i64[]
        cs_grp = @cs_grp ## i64[]
        cs_ost = @cs_ost ## i64[]
        g = cs_grp[top] ## i64
        want = cs_ost[top] ## i64
        if g > 0 && want >= 0
          old = saved[g * 2] ## i64
          e = saved[g * 2 + 1] ## i64
          saved[g * 2] = want
          saved[g * 2 + 1] = -1
          @cs_top = cs_par[top]
          r = run(cs_ret[top], sp, saved) ## i64
          if r >= 0
            return r
          saved[g * 2] = old
          saved[g * 2 + 1] = e
          @cs_top = top
          pc = -1
        else
          @cs_top = cs_par[top]
          pc = cs_ret[top] ## i64
      elsif op == 24
        want = args_a[pc] ## i64
        e = match_special(want, sp) ## i64
        if e >= 0
          sp = e
          pc = pc + 1
        else
          pc = -1
      elsif op == 10
        if at_word_boundary?(sp)
          if args_a[pc] != 1
            pc = -1
          else
            pc = pc + 1
        elsif args_a[pc] == 1
          pc = -1
        else
          pc = pc + 1
      else
        pc = -1
      if pc < 0
        if b_cnt > 0
          b_cnt = b_cnt - 1
          if b_cnt == 0
            pc = b_pc0
            sp = b_sp0
            tu = b_u0
          elsif b_cnt == 1
            pc = b_pc1
            sp = b_sp1
            tu = b_u1
          elsif b_cnt == 2
            pc = b_pc2
            sp = b_sp2
            tu = b_u2
          else
            pc = b_pc3
            sp = b_sp3
            tu = b_u3
          while u_cnt > tu
            u_cnt = u_cnt - 1
            if u_cnt == 0
              saved[u_s0] = u_v0
            elsif u_cnt == 1
              saved[u_s1] = u_v1
            elsif u_cnt == 2
              saved[u_s2] = u_v2
            else
              saved[u_s3] = u_v3
        else
          break
    if u_cnt >= 4
      saved[u_s3] = u_v3
    if u_cnt >= 3
      saved[u_s2] = u_v2
    if u_cnt >= 2
      saved[u_s1] = u_v1
    if u_cnt >= 1
      saved[u_s0] = u_v0
    res

  -> eval_lookbehind(pc_in, sp_in, saved_in)
    pc = pc_in ## i64
    sp = sp_in ## i64
    saved = saved_in ## i64[]
    enc = @b[pc] ## i64
    kind = enc & 15
    min_l = enc >> 20
    max_e = (enc >> 4) & 65535
    hi_s = sp - min_l
    if hi_s < 0
      return kind == 4
    lo_s = max_e == 65535 ? 0 : (sp - max_e)
    if lo_s < 0
      lo_s = 0
    old_t = @lookb_target ## i64
    @lookb_target = sp
    if kind == 3
      s = lo_s
      while s <= hi_s
        if run(pc + 1, s, saved) == sp
          @lookb_target = old_t
          return true
        s = s + 1
      @lookb_target = old_t
      return false
    s = hi_s
    while s >= lo_s
      if run(pc + 1, s, saved) == sp
        @lookb_target = old_t
        return false
      s = s - 1
    @lookb_target = old_t
    true

  -> run_assert_cap(pc_in, sp_in, saved_in)
    pc = pc_in ## i64
    sp = sp_in ## i64
    saved = saved_in ## i64[]
    after_pc = @a[pc] ## i64
    enc = @b[pc] ## i64
    kind = enc & 15
    snap = build_offsets(saved)
    sn = saved.size() ## i64
    if kind == 1
      if run(pc + 1, sp, saved) >= 0
        r = run(after_pc, sp, saved) ## i64
        if r >= 0
          return r
      i = 0 ## i64
      while i < sn
        saved[i] = snap[i]
        i = i + 1
      return -1
    if kind == 2
      if run(pc + 1, sp, saved) >= 0
        i = 0 ## i64
        while i < sn
          saved[i] = snap[i]
          i = i + 1
        return -1
      return run(after_pc, sp, saved)
    if kind == 5
      e = run(pc + 1, sp, saved) ## i64
      if e >= 0
        r = run(after_pc, e, saved) ## i64
        if r >= 0
          return r
      i = 0 ## i64
      while i < sn
        saved[i] = snap[i]
        i = i + 1
      return -1
    if eval_lookbehind(pc, sp, saved)
      if kind == 4
        i = 0 ## i64
        while i < sn
          saved[i] = snap[i]
          i = i + 1
      r = run(after_pc, sp, saved) ## i64
      if r >= 0
        return r
    i = 0 ## i64
    while i < sn
      saved[i] = snap[i]
      i = i + 1
    -1

  -> match_backref(g_in, icase_in, sp_in, saved_in)
    saved = saved_in ## i64[]
    g = g_in ## i64
    sp = sp_in ## i64
    a = saved[g * 2] ## i64
    b = saved[g * 2 + 1] ## i64
    if a < 0 || b < 0
      return -1
    len = b - a
    n = @subj_len ## i64
    if sp + len > n
      return -1
    subj = @subj ## i64[]
    i = 0 ## i64
    if icase_in == 0
      while i < len
        if subj[sp + i] != subj[a + i]
          return -1
        i = i + 1
    else
      while i < len
        c1 = subj[sp + i] ## i64
        c2 = subj[a + i] ## i64
        if c1 != c2 && downcase_lex_cp(c1) != downcase_lex_cp(c2)
          return -1
        i = i + 1
    sp + len

  -> match_special(mode_in, sp_in)
    mode = mode_in ## i64
    sp = sp_in ## i64
    n = @subj_len ## i64
    if sp >= n
      return -1
    subj = @subj ## i64[]
    ch = subj[sp] ## i64
    cp = (ch >> 25) & 2097151
    if mode == 1
      if cp == 13
        if sp + 1 < n && ((subj[sp + 1] >> 25) & 2097151) == 10
          return sp + 2
        return sp + 1
      if (cp >= 10 && cp <= 12) || cp == 133 || cp == 8232 || cp == 8233
        return sp + 1
      return -1
    if cp == 13
      if sp + 1 < n && ((subj[sp + 1] >> 25) & 2097151) == 10
        return sp + 2
      return sp + 1
    if cp == 10
      return sp + 1
    e = sp + 1
    while e < n
      nx = subj[e] ## i64
      ncat = (nx >> 3) & 31
      ncp = (nx >> 25) & 2097151
      if (ncat >= 11 && ncat <= 13) || ncp == 65038 || ncp == 65039 || (ncp >= 127995 && ncp <= 127999)
        e = e + 1
      elsif ncp == 8205 && e + 1 < n
        e = e + 2
      else
        break
    e

  -> at_word_boundary?(sp_in)
    subj = @subj ## i64[]
    sp = sp_in ## i64
    n = @subj_len ## i64
    before = sp > 0 && (subj[sp - 1] & 2) != 0
    after = sp < n && (subj[sp] & 2) != 0
    before != after

  -> word_lex?(lx_in)
    lx = lx_in ## i64
    (lx & 2) != 0

  -> cat_match?(mask_in, neg_in, ch_in)
    mask = mask_in ## i64
    ch = ch_in ## i64
    hit = ((mask >> ((ch >> 3) & 31)) & 1) != 0
    if !hit && mask >= 1073741824
      if (mask & 1073741824) != 0 && (ch & 16777216) != 0
        hit = true
      elsif (mask & 2147483648) != 0 && (ch & 8388608) != 0
        hit = true
    if neg_in == 1
      return !hit
    hit

  -> consume_at?(pc_in, ch_in)
    ops = @op ## i64[]
    args_a = @a ## i64[]
    branches = @b ## i64[]
    pc = pc_in ## i64
    ch = ch_in ## i64
    op = ops[pc] ## i64
    if op == 1
      return ch == args_a[pc]
    if op == 18
      return ch == args_a[pc] || ch == branches[pc]
    if op == 11
      hit = (ch & args_a[pc]) != 0
      if branches[pc] == 1
        return !hit
      return hit
    if op == 2
      return ch != args_a[pc]
    if op == 3
      return class_match?(args_a[pc], ch)
    if op == 17
      return ch >= args_a[pc] && ch <= branches[pc]
    if op == 19
      return cat_match?(args_a[pc], branches[pc], ch)
    false

  # Full character-class match used for non-ASCII chars and at compile time to
  # populate the 128-bit ASCII bitmap in c[5] (0..63) and c[6] (64..127).
  -> class_match_slow?(c_in, lx_in)
    c = c_in ## i64[]
    lx = lx_in ## i64
    neg = c[0] == 1
    pos_f = c[1] ## i64
    if pos_f != 0 && (lx & pos_f) != 0
      return !neg
    neg_f = c[2] ## i64
    if neg_f != 0
      if (neg_f & 1) != 0 && (lx & 1) == 0
        return !neg
      if (neg_f & 2) != 0 && (lx & 2) == 0
        return !neg
      if (neg_f & 4) != 0 && (lx & 4) == 0
        return !neg
    pos_cat = c[3] ## i64
    if pos_cat != 0 && cat_match?(pos_cat, 0, lx)
      return !neg
    neg_cat = c[4] ## i64
    if neg_cat != 0 && cat_match?(neg_cat, 1, lx)
      return !neg
    n = c.size() ## i64
    i = 5 ## i64
    while i < n
      if lx >= c[i] && lx <= c[i + 1]
        return !neg
      i = i + 2
    neg

  # Hot runtime character-class match: O(1) bit-shift for all ASCII characters!
  -> class_match?(cls_in, lx_in)
    cidx = (cls_in ## i64) * 6
    lx = lx_in ## i64
    cp = (lx >> 25) & 2097151
    cbm = @cls_bm ## i64[]
    if cp < 128
      return ((cbm[cidx + (cp >> 5)] >> (cp & 31)) & 1) != 0
    if lx >= cbm[cidx + 4] && lx <= cbm[cidx + 5]
      return true
    class_match_slow?(@classes[cls_in], lx)

  -> set_match?(s, lx_in)
    lx = lx_in ## i64
    if s == "d"
      return (lx & 1) != 0
    if s == "D"
      return (lx & 1) == 0
    if s == "w"
      return (lx & 2) != 0
    if s == "W"
      return (lx & 2) == 0
    if s == "s"
      return (lx & 4) != 0
    if s == "S"
      return (lx & 4) == 0
    false

# RegexMatch — structured numbered/named captures and codepoint spans.
+ RegexMatch
  -> new(@subj, @offsets, @name_to_group, @subject, @p0, @p1, @p2, @p3)
    nil

  -> group_index(key)
    kbits = wvalue_bits(key) ## i64
    ktag = (kbits >> 48) ## i64
    if ktag == -6
      return key
    if ktag == -7
      if @name_to_group == nil
        return nil
      ntg = @name_to_group ## Hash
      if (kbits & 1) == 0
        return ntg[key]
      return ntg[key.to_s]
    kind = type(key)
    if kind == "Int" || kind == "Integer" || kind == "BigInt"
      return key
    if kind == "String"
      if @name_to_group == nil
        return nil
      return (@name_to_group ## hash)[key]
    if kind == "Symbol"
      if @name_to_group == nil
        return nil
      return (@name_to_group ## hash)[key.to_s]
    nil

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
