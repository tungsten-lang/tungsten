# Regex — a homegrown regular-expression engine, written in Tungsten.
#
# No external dependency (no oniguruma/PCRE): a pattern is parsed to an AST,
# compiled to a small instruction program, and matched by a backtracking VM —
# the classic Thompson/Pike construction (Russ Cox, "Regular Expression
# Matching: the Virtual Machine Approach"). SPLIT gives backtracking; SAVE
# records capture-group boundaries.
#
# UTF-8 / codepoints: the subject and pattern are decoded to Char WValues
# (String#codes). A Char carries the codepoint in its HIGH bits — so a raw `==`
# and `<` order by codepoint, and `[a-z]`/`[5-z]`/`[α-ω]` ranges sort correctly
# across Unicode categories — and the \d (bit0), \w (bit1), \s (bit2) class flags
# at the LSB, so `char & 1/2/4` is a single, Unicode-correct, branchless test.
# The VM compares Chars directly and masks the flags; the codepoint is `>> 25`.
#
#   r = Regex.new("(\\d+)-(\\d+)")
#   r.match("call 12-34 now")   => ["12-34", "12", "34"]   (group 0 + captures)
#   r.match?("nope")            => false
#
+ Regex
  # ── instruction opcodes ──
  OP_CHAR  = 1   # a = literal lexint to match
  OP_ANY   = 2   # any codepoint except newline
  OP_CLASS = 3   # a = {neg:, ranges: [[lo_lex, hi_lex],…], sets: ["d","w","s",…]}
  OP_MATCH = 4
  OP_JMP   = 5   # a = target pc
  OP_SPLIT = 6   # a = pc tried first, b = pc tried on backtrack
  OP_SAVE  = 7   # a = capture slot
  OP_BOL   = 8   # ^  (start, or after \n)
  OP_EOL   = 9   # $  (end, or before \n)
  OP_WORDB = 10  # a = 1 for \b, 0 for \B
  OP_FLAG  = 11  # a = flag bit (\d\w\s), b = 1 to negate — fast path for a lone
                 # shorthand class (avoids the general OP_CLASS indirection)
  OP_MARK  = 12  # a = guard slot — record sp at the top of a nullable-body loop
  OP_GUARD = 13  # a = guard slot — fail this path if sp == the marked sp (the
                 # loop body consumed nothing). Stops (a*)* etc. from looping
                 # forever on empty matches (which otherwise overflows the stack).
  OP_REP_G = 14  # greedy X* over a single consuming op. a = body-op pc (read as a
  OP_REP_L = 15  # match template, never fallen into), b = continuation pc. Consumes
                 # all matches in a tight loop, then backtracks by position — depth-1
                 # instead of one recursive run() frame per repetition. _L is lazy.

  # Char classflag bits at the LSB (must match the runtime Char layout).
  FLAG_D = 1     # \d
  FLAG_W = 2     # \w
  FLAG_S = 4     # \s

  # Special characters that .escape backslash-protects.
  SPECIALS = "\\.^$|?*+()\[]{}"

  -> new(@source, @opts = nil, @lang = nil)
    # Flat parallel program arrays (faster than an array of [op,a,b] tuples):
    # @op[pc] opcode, @a[pc] first operand (literal Char / class / target / slot),
    # @b[pc] second operand (the SPLIT alternate target).
    @op = []
    @a = []
    @b = []
    @ngroup = 1                 # group 0 is the whole match
    @nguard = 0                 # progress-guard slots for nullable-body loops
    @nl = clex("\n")            # the newline Char, for . ^ $
    ast = parse_pattern(@source)
    emit(OP_SAVE, 0, 0)
    compile_node(ast)
    emit(OP_SAVE, 1, 0)
    emit(OP_MATCH, 0, 0)
    @ncap = @ngroup
    @subj_key = nil             # last subject decoded into @subj (decode cache)
    compute_prefilter()         # first-char prefilter (depends only on the program)

  -> source
    @source

  # The Char WValue of a single-character string. Char has the codepoint in the
  # high bits (so == and < order by codepoint) and \d\w\s at the LSB.
  -> clex(ch)
    ch.codes()[0]

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
  -> emit(op, a, b)
    @op.push(op)
    @a.push(a)
    @b.push(b)
    @op.size() - 1

  # ── recursive-descent parser → AST (hashes keyed by :k) ──
  # Parses over the pattern's CHARS (syntax decisions stay char-based); literal
  # and class-range chars are converted to lexints (clex) as the AST is built.
  -> parse_pattern(pat)
    @p = pat.chars()
    @i = 0
    parse_alt()

  -> at_end?
    @i >= @p.size()

  -> peek
    if @i < @p.size()
      return @p[@i]
    nil

  -> advance
    c = @p[@i]
    @i = @i + 1
    c

  -> parse_alt
    opts = [parse_seq()]
    while peek() == "|"
      advance()
      opts.push(parse_seq())
    if opts.size() == 1
      return opts[0]
    {k: :alt, opts: opts}

  -> parse_seq
    items = []
    while !at_end?() && peek() != "|" && peek() != ")"
      items.push(parse_repeat())
    {k: :seq, items: items}

  -> parse_repeat
    atom = parse_atom()
    c = peek()
    if c == "*"
      advance()
      return {k: :star, child: atom, greedy: lazy?()}
    if c == "+"
      advance()
      return {k: :plus, child: atom, greedy: lazy?()}
    if c == "?"
      advance()
      return {k: :opt, child: atom, greedy: lazy?()}
    if c == "{"
      rep = parse_brace(atom)
      if rep != nil
        return rep
    atom

  -> lazy?
    if peek() == "?"
      advance()
      return false
    true

  # {n} {n,} {n,m} — returns a :rep node, or nil if it's a literal `{`.
  -> parse_brace(atom)
    save = @i
    advance()                    # consume {
    lo = parse_int()
    if lo == nil
      @i = save
      return nil
    hi = lo
    if peek() == ","
      advance()
      hi = parse_int()           # nil → unbounded
    if peek() != "}"
      @i = save
      return nil
    advance()                    # consume }
    {k: :rep, min: lo, max: hi, child: atom, greedy: lazy?()}

  -> parse_int
    digits = ""
    while !at_end?() && peek() >= "0" && peek() <= "9"
      digits = digits + advance()
    if digits.size() == 0
      return nil
    digits.to_i()

  -> parse_atom
    c = advance()
    if c == "("
      return parse_group()
    if c == "\["
      return parse_class()
    if c == "."
      return {k: :any}
    if c == "^"
      return {k: :bol}
    if c == "$"
      return {k: :eol}
    if c == "\\"
      return parse_escape()
    {k: :lit, x: clex(c)}

  -> parse_group
    cap = -1
    if peek() == "?"
      advance()
      advance()                  # consume the ?: (assume non-capturing form)
    else
      cap = @ngroup
      @ngroup = @ngroup + 1
    child = parse_alt()
    if peek() == ")"
      advance()
    {k: :group, child: child, cap: cap}

  # \d \w \s \D \W \S \b \B \n \t \r and escaped literals.
  -> parse_escape
    c = advance()
    if c == "d" || c == "w" || c == "s" || c == "D" || c == "W" || c == "S"
      return {k: :class, neg: false, ranges: [], sets: [c]}
    if c == "b"
      return {k: :wordb, wb: true}
    if c == "B"
      return {k: :wordb, wb: false}
    if c == "n"
      return {k: :lit, x: clex("\n")}
    if c == "t"
      return {k: :lit, x: clex("\t")}
    if c == "r"
      return {k: :lit, x: clex("\r")}
    {k: :lit, x: clex(c)}

  # [abc] [a-z] [^...] with \d \w \s shorthands inside.
  -> parse_class
    neg = false
    if peek() == "^"
      advance()
      neg = true
    ranges = []
    sets = []
    while !at_end?() && peek() != "]"
      c = advance()
      if c == "\\"
        e = advance()
        if e == "d" || e == "w" || e == "s" || e == "D" || e == "W" || e == "S"
          sets.push(e)
          next
        c = class_escape_char(e)
      if peek() == "-" && @i + 1 < @p.size() && @p[@i + 1] != "]"
        advance()                # consume -
        hi = advance()
        if hi == "\\"
          hi = class_escape_char(advance())
        ranges.push([clex(c), clex(hi)])
      else
        ranges.push([clex(c), clex(c)])
    if peek() == "]"
      advance()
    {k: :class, neg: neg, ranges: ranges, sets: sets}

  -> class_escape_char(e)
    if e == "n"
      return "\n"
    if e == "t"
      return "\t"
    if e == "r"
      return "\r"
    e

  # If `node` is a lone \d \w \s \D \W \S (one set, no ranges, not negated),
  # return [flag_bit, negate] for the OP_FLAG fast path; else nil.
  -> lone_flag_class(node)
    if node[:neg] || node[:ranges].size() != 0 || node[:sets].size() != 1
      return nil
    s = node[:sets][0]
    if s == "d"
      return [FLAG_D, 0]
    if s == "D"
      return [FLAG_D, 1]
    if s == "w"
      return [FLAG_W, 0]
    if s == "W"
      return [FLAG_W, 1]
    if s == "s"
      return [FLAG_S, 0]
    if s == "S"
      return [FLAG_S, 1]
    nil

  # ── compile AST → flat @op/@a/@b program (backpatched SPLIT/JMP targets) ──
  -> compile_node(node)
    k = node[:k]
    if k == :lit
      emit(OP_CHAR, node[:x], 0)
    elsif k == :any
      emit(OP_ANY, 0, 0)
    elsif k == :class
      f = lone_flag_class(node)
      if f != nil
        emit(OP_FLAG, f[0], f[1])
      else
        emit(OP_CLASS, node, 0)
    elsif k == :bol
      emit(OP_BOL, 0, 0)
    elsif k == :eol
      emit(OP_EOL, 0, 0)
    elsif k == :wordb
      v = 0
      if node[:wb]
        v = 1
      emit(OP_WORDB, v, 0)
    elsif k == :seq
      items = node[:items]
      i = 0
      while i < items.size()
        compile_node(items[i])
        i = i + 1
    elsif k == :group
      if node[:cap] >= 0
        emit(OP_SAVE, node[:cap] * 2, 0)
        compile_node(node[:child])
        emit(OP_SAVE, node[:cap] * 2 + 1, 0)
      else
        compile_node(node[:child])
    elsif k == :alt
      compile_alt(node[:opts])
    elsif k == :star
      compile_star(node[:child], node[:greedy])
    elsif k == :plus
      compile_plus(node[:child], node[:greedy])
    elsif k == :opt
      compile_opt(node[:child], node[:greedy])
    elsif k == :rep
      compile_rep(node)

  -> compile_alt(opts)
    if opts.size() == 1
      compile_node(opts[0])
      return
    s = emit(OP_SPLIT, 0, 0)
    @a[s] = @op.size()
    compile_node(opts[0])
    j = emit(OP_JMP, 0, 0)
    @b[s] = @op.size()
    rest = []
    i = 1
    while i < opts.size()
      rest.push(opts[i])
      i = i + 1
    compile_alt(rest)
    @a[j] = @op.size()

  # Can `node` match the empty string? A quantified nullable body needs a
  # progress guard, or an empty iteration loops forever (and overflows the
  # recursive VM's stack). Consuming atoms are non-nullable; zero-width
  # assertions and *, ?, {0,…} are nullable; composites fold over children.
  -> nullable?(node)
    k = node[:k]
    if k == :lit || k == :any || k == :class
      return false
    if k == :star || k == :opt
      return true
    if k == :bol || k == :eol || k == :wordb
      return true
    if k == :plus || k == :group
      return nullable?(node[:child])
    if k == :seq
      items = node[:items]
      i = 0
      while i < items.size()
        if !nullable?(items[i])
          return false
        i = i + 1
      return true
    if k == :alt
      opts = node[:opts]
      i = 0
      while i < opts.size()
        if nullable?(opts[i])
          return true
        i = i + 1
      return false
    if k == :rep
      return node[:min] == 0 || nullable?(node[:child])
    false

  # A child that compiles to exactly one consuming opcode (literal, ., or a
  # class — incl. \d\w\s). Such a quantifier never needs the empty-loop guard
  # and can use the fused OP_REP fast path instead of a recursive SPLIT loop.
  -> single_consuming?(node)
    k = node[:k]
    k == :lit || k == :any || k == :class

  -> compile_star(child, greedy)
    if single_consuming?(child)
      # OP_REP_? <body> after:  — the body op sits right after OP_REP as a match
      # template (a = body pc), and the continuation is body+1 (b = after).
      op = OP_REP_G
      if !greedy
        op = OP_REP_L
      rep = emit(op, 0, 0)
      body = @op.size()
      compile_node(child)
      @a[rep] = body
      @b[rep] = @op.size()
      return
    if nullable?(child)
      g = @nguard
      @nguard = @nguard + 1
      l1 = @op.size()
      s = emit(OP_SPLIT, 0, 0)
      emit(OP_MARK, g, 0)
      compile_node(child)
      emit(OP_GUARD, g, 0)
      emit(OP_JMP, l1, 0)
      l3 = @op.size()
      set_split(s, l1 + 1, l3, greedy)
      return
    l1 = @op.size()
    s = emit(OP_SPLIT, 0, 0)
    compile_node(child)
    emit(OP_JMP, l1, 0)
    l3 = @op.size()
    set_split(s, l1 + 1, l3, greedy)

  # X+ ≡ X X*. The mandatory first X is emitted before the loop (so the prefix
  # scan still sees it); the repeating tail reuses compile_star. For a single
  # consuming op that tail is the fused OP_REP; for a nullable child it is the
  # guarded star.
  -> compile_plus(child, greedy)
    if single_consuming?(child) || nullable?(child)
      compile_node(child)
      compile_star(child, greedy)
      return
    l1 = @op.size()
    compile_node(child)
    s = emit(OP_SPLIT, 0, 0)
    set_split(s, l1, @op.size(), greedy)

  -> compile_opt(child, greedy)
    s = emit(OP_SPLIT, 0, 0)
    @a[s] = @op.size()
    compile_node(child)
    set_split(s, @a[s], @op.size(), greedy)

  -> compile_rep(node)
    lo = node[:min]
    hi = node[:max]
    child = node[:child]
    greedy = node[:greedy]
    i = 0
    while i < lo
      compile_node(child)
      i = i + 1
    if hi == nil
      compile_star(child, greedy)
    else
      extra = hi - lo
      i = 0
      while i < extra
        compile_opt(child, greedy)
        i = i + 1

  -> set_split(s, pref, alt, greedy)
    if greedy
      @a[s] = pref
      @b[s] = alt
    else
      @a[s] = alt
      @b[s] = pref

  # ── matcher (all int ops over the Char array) ──

  # Prefilter: the set of characters a match can begin with, computed ONCE from
  # the program (it depends only on the pattern) and used to skip subject
  # positions that can't start a match — instead of running and failing the
  # whole VM at each one. Generalizes a single-char pin to a set + flag mask, so
  # alternations (foo|bar) and class/flag-prefixed patterns get a prefilter too.
  #   @pf_kind 0 none · 1 single char · 2 flag mask · 3 set (+ optional flag mask)
  # The leading run of fixed literal characters every match must begin with
  # (consecutive OP_CHARs, following through the zero-width SAVE/MARK/GUARD that
  # group boundaries emit). [] if the pattern doesn't start with a literal.
  -> literal_prefix
    lit = []
    pc = 0
    while pc < @op.size()
      op = @op[pc]
      if op == OP_CHAR
        lit.push(@a[pc])
        pc = pc + 1
      elsif op == OP_SAVE || op == OP_MARK || op == OP_GUARD
        pc = pc + 1
      else
        pc = @op.size()
    lit

  # Sunday quick-search bad-character skip table: for the char that sits one
  # past the window, how far the prefix can jump. skip[c] = len-j for the last
  # j with lit[j]==c, else len+1 (looked up as a nil default).
  -> build_skip(lit)
    len = lit.size()
    skip = {}
    j = 0
    while j < len
      skip[(lit[j] >> 25) & 2097151] = len - j   # key by codepoint int, not the Char WValue
      j = j + 1
    skip

  -> compute_prefilter
    @pf_kind = 0
    @pf_char = 0
    @pf_flag = 0
    @pf_set = []
    @pf_lit = []
    @pf_skip = nil
    # A literal prefix of 4+ chars is the strongest prefilter (Boyer-Moore /
    # Sunday skip): big jumps amortize the per-candidate compare + skip-table
    # lookup. Shorter prefixes fall through to the single-char/set scan, whose
    # one-char-per-position test is cheaper than the skip machinery (measured:
    # a 3-char literal is faster on the single-char pin).
    lit = literal_prefix()
    if lit.size() >= 4
      @pf_lit = lit
      @pf_skip = build_skip(lit)
      @pf_kind = 4
      return
    @cf_ok = true            # false ⇒ a start char we can't enumerate (. [..] $ \B-class)
    @cf_empty = false        # true ⇒ the pattern can match the empty string at start
    seen = []
    i = 0
    while i < @op.size()
      seen.push(false)
      i = i + 1
    collect_first(0, seen)
    if @cf_empty || !@cf_ok
      return
    if @pf_set.size() == 0 && @pf_flag == 0
      return                 # nothing enumerable (e.g. anchor-only) — no prefilter
    if @pf_flag != 0 && @pf_set.size() == 0
      @pf_kind = 2
      @pf_char = @pf_flag
    elsif @pf_flag == 0 && @pf_set.size() == 1
      @pf_kind = 1
      @pf_char = @pf_set[0]
    else
      @pf_kind = 3

  # Epsilon-closure walk from `pc`, accumulating the first consuming characters
  # into @pf_set (literals) and @pf_flag (OR of \d\w\s masks). Follows the
  # zero-width assertions ^ and \b through to the next real char (so ^abc still
  # pins 'a'). Bails (@cf_ok=false) on . [..] $ or a negated flag — chars it
  # can't enumerate — and flags @cf_empty if a MATCH is reachable with no
  # consuming op (the pattern can match empty, so every position is a candidate).
  -> collect_first(pc, seen)
    if seen[pc]
      return
    seen[pc] = true
    op = @op[pc]
    if op == OP_SAVE || op == OP_MARK || op == OP_GUARD || op == OP_BOL || op == OP_WORDB
      collect_first(pc + 1, seen)
    elsif op == OP_JMP
      collect_first(@a[pc], seen)
    elsif op == OP_SPLIT
      collect_first(@a[pc], seen)
      collect_first(@b[pc], seen)
    elsif op == OP_REP_G || op == OP_REP_L
      collect_first(@a[pc], seen)    # the loop body (a start char)
      collect_first(@b[pc], seen)    # the continuation (zero-iteration case)
    elsif op == OP_CHAR
      @pf_set.push(@a[pc])
    elsif op == OP_FLAG
      if @b[pc] == 0
        @pf_flag = @pf_flag | @a[pc]
      else
        @cf_ok = false               # negated \D\W\S — enumerating is infeasible
    elsif op == OP_MATCH
      @cf_empty = true
    else
      @cf_ok = false                 # OP_ANY / OP_CLASS / OP_EOL

  # Does this Char satisfy the prefilter set (membership or a flag bit)?
  -> pf_set_match(ch)
    if @pf_flag != 0 && (ch & @pf_flag) != 0
      return true
    i = 0
    while i < @pf_set.size()
      if @pf_set[i] == ch
        return true
      i = i + 1
    false

  # Advance `start` to the next subject position that could begin a match.
  -> pf_advance(start, n)
    k = @pf_kind
    if k == 1
      return ccall("w_regex_scan_char", @subj, start, n, (@pf_char >> 25) & 2097151)
    elsif k == 2
      return ccall("w_regex_scan_flag", @subj, start, n, @pf_char)
    elsif k == 3
      while start < n && !pf_set_match(@subj[start])
        start = start + 1
    elsif k == 4
      return pf_bm_search(start, n)
    start

  # Sunday quick-search for the literal prefix: align at i, compare; on a miss
  # jump by skip[char one past the window] (len+1 when that char isn't in the
  # prefix). Returns the next candidate position, or n if none remain.
  -> pf_bm_search(start, n)
    lit = @pf_lit
    llen = lit.size()
    i = start
    while i + llen <= n
      j = 0
      while j < llen && @subj[i + j] == lit[j]
        j = j + 1
      if j == llen
        return i
      nxt = i + llen
      if nxt >= n
        return n
      sk = @pf_skip[(@subj[nxt] >> 25) & 2097151]
      if sk == nil
        sk = llen + 1
      i = i + sk
    n

  # Returns [whole, cap1, cap2, …] for the leftmost match, or nil.
  -> match(subject)
    # Decode cache: codepoint-decode the subject only when it changed. Repeated
    # matches against the same string (scan, multi-pattern, re-match) reuse the
    # array. The key compare is an O(1) bit-equality for the same object
    # (w_eq short-circuits a==b), so the common case pays nothing.
    if subject != @subj_key
      @subj = subject.codes()
      @subj_key = subject
    n = @subj.size()
    @guard = []                 # entry sp per nullable-loop guard slot
    i = 0
    while i < @nguard
      @guard.push(-1)
      i = i + 1
    start = 0
    while start <= n
      start = pf_advance(start, n)
      if @pf_kind != 0 && start >= n
        return nil              # no remaining candidate start positions
      saved = make_saved()
      e = run(0, start, saved)
      if e >= 0
        return build_result(saved)
      start = start + 1
    nil

  -> match?(subject)
    match(subject) != nil

  -> make_saved
    s = []
    i = 0
    while i < @ncap * 2
      s.push(-1)
      i = i + 1
    s

  # Build each group's text from the matched lexint span (codepoint = lx >> 8),
  # so we never re-decode the whole subject.
  -> build_result(saved)
    out = []
    g = 0
    while g < @ncap
      a = saved[g * 2]
      b = saved[g * 2 + 1]
      if a >= 0 && b >= 0
        out.push(span_str(a, b))
      else
        out.push(nil)
      g = g + 1
    out

  # Materialize the match span [a, b) — a window into the decoded codepoint
  # array — as a UTF-8 string in one allocation. The runtime walks the Char
  # WValues directly (codepoint in bits 25-45), so this is O(b-a) with a single
  # buffer instead of the old O(n^2) per-codepoint concatenation.
  -> span_str(a, b)
    ccall("w_string_from_codes", @subj, a, b - a)

  # Backtracking VM: returns the end position on success, or -1.
  -> run(pc, sp, saved)
    n = @subj.size()
    while true
      op = @op[pc]
      if op == OP_CHAR
        if sp < n && @subj[sp] == @a[pc]
          pc = pc + 1
          sp = sp + 1
        else
          return -1
      elsif op == OP_FLAG
        hit = sp < n && (@subj[sp] & @a[pc]) != 0
        if @b[pc] == 1
          hit = sp < n && !hit
        if hit
          pc = pc + 1
          sp = sp + 1
        else
          return -1
      elsif op == OP_ANY
        if sp < n && @subj[sp] != @nl
          pc = pc + 1
          sp = sp + 1
        else
          return -1
      elsif op == OP_CLASS
        if sp < n && class_match?(@a[pc], @subj[sp])
          pc = pc + 1
          sp = sp + 1
        else
          return -1
      elsif op == OP_REP_G
        # Greedy X*: consume every match in a tight loop, then try the
        # continuation from the longest match down — depth-1, not one recursive
        # frame per repetition. @a = body template pc, @b = continuation pc.
        tpc = @a[pc]
        e = sp
        while e < n && consume_at?(tpc, @subj[e])
          e = e + 1
        cont = @b[pc]
        pos = e
        while pos >= sp
          r = run(cont, pos, saved)
          if r >= 0
            return r
          pos = pos - 1
        return -1
      elsif op == OP_REP_L
        # Lazy X*: shortest match first.
        tpc = @a[pc]
        e = sp
        while e < n && consume_at?(tpc, @subj[e])
          e = e + 1
        cont = @b[pc]
        pos = sp
        while pos <= e
          r = run(cont, pos, saved)
          if r >= 0
            return r
          pos = pos + 1
        return -1
      elsif op == OP_MATCH
        return sp
      elsif op == OP_JMP
        pc = @a[pc]
      elsif op == OP_SPLIT
        r = run(@a[pc], sp, saved)
        if r >= 0
          return r
        pc = @b[pc]
      elsif op == OP_SAVE
        slot = @a[pc]
        old = saved[slot]
        saved[slot] = sp
        r = run(pc + 1, sp, saved)
        if r >= 0
          return r
        saved[slot] = old
        return -1
      elsif op == OP_MARK
        g = @a[pc]
        old = @guard[g]
        @guard[g] = sp
        r = run(pc + 1, sp, saved)
        if r >= 0
          return r
        @guard[g] = old
        return -1
      elsif op == OP_GUARD
        if sp == @guard[@a[pc]]
          return -1
        pc = pc + 1
      elsif op == OP_BOL
        if sp == 0 || @subj[sp - 1] == @nl
          pc = pc + 1
        else
          return -1
      elsif op == OP_EOL
        if sp == n || @subj[sp] == @nl
          pc = pc + 1
        else
          return -1
      elsif op == OP_WORDB
        b = at_word_boundary?(sp)
        want = @a[pc] == 1
        if b == want
          pc = pc + 1
        else
          return -1
      else
        return -1

  -> at_word_boundary?(sp)
    before = sp > 0 && word_lex?(@subj[sp - 1])
    after = sp < @subj.size() && word_lex?(@subj[sp])
    before != after

  -> word_lex?(lx)
    (lx & FLAG_W) != 0

  # Apply a single consuming opcode (the body of a fused OP_REP) as a match
  # test against one Char, without advancing — mirrors run()'s consuming cases.
  -> consume_at?(pc, ch)
    op = @op[pc]
    if op == OP_CHAR
      return ch == @a[pc]
    if op == OP_FLAG
      hit = (ch & @a[pc]) != 0
      if @b[pc] == 1
        return !hit
      return hit
    if op == OP_ANY
      return ch != @nl
    if op == OP_CLASS
      return class_match?(@a[pc], ch)
    false

  -> class_match?(cls, lx)
    # Membership is a disjunction over ranges and shorthand sets, so the answer
    # is known on the FIRST hit — return immediately instead of scanning the
    # rest. `neg` flips the verdict once: a member of [^…] is a non-match.
    neg = cls[:neg]
    ranges = cls[:ranges]
    i = 0
    while i < ranges.size()
      if lx >= ranges[i][0] && lx <= ranges[i][1]
        return !neg
      i = i + 1
    sets = cls[:sets]
    i = 0
    while i < sets.size()
      if set_match?(sets[i], lx)
        return !neg
      i = i + 1
    neg

  # \d \w \s and their negations — a single flag-bit test on the lexint.
  -> set_match?(s, lx)
    if s == "d"
      return (lx & FLAG_D) != 0
    if s == "D"
      return (lx & FLAG_D) == 0
    if s == "w"
      return (lx & FLAG_W) != 0
    if s == "W"
      return (lx & FLAG_W) == 0
    if s == "s"
      return (lx & FLAG_S) != 0
    if s == "S"
      return (lx & FLAG_S) == 0
    false
