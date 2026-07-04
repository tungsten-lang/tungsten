# wit — W Interactive Tungsten
#
# The Tungsten REPL. Evaluates expressions, formats results, detects
# code completeness for multiline input, and provides auto-indentation.

# Block-opening keywords that expect an indented body
BLOCK_OPENERS = ["if", "elsif", "else", "while", "until", "with", "module", "begin", "rescue", "ensure", "case", "when", "unless", "always"]

# Keywords that close one block and open another at the same level
DEDENT_KEYWORDS = ["else", "elsif", "rescue", "ensure", "when"]

KEYWORDS = ["if", "else", "elsif", "while", "until", "with", "case", "when", "module", "return", "break", "next", "continue", "true", "false", "nil", "begin", "rescue", "ensure", "raise", "use", "self", "super", "yield", "unless", "trait", "always", "redo", "retry", "in"]

# ANSI color codes
RESET  = "\e\[0m"
BOLD   = "\e\[1m"
DIM    = "\e\[2m"
RED    = "\e\[31m"
GREEN  = "\e\[32m"
YELLOW = "\e\[33m"
CYAN   = "\e\[36m"
MAGENTA = "\e\[35m"
WHITE  = "\e\[37m"
BRIGHT_RED     = "\e\[91m"
BRIGHT_MAGENTA = "\e\[95m"
BRIGHT_CYAN    = "\e\[96m"
BRIGHT_YELLOW  = "\e\[93m"

# Syntax-highlight palette as 256-color ANSI, vim-style: keyword-like groups
# share one Statement tone (#905678 = 96), the rest get their own ctermfg-style
# values. (There is no shipped vim colorscheme file; this palette is the source.)
HL_COMMENT = "\e\[3;38;5;96m"    # Comment   — italic 96
HL_KEYWORD = "\e\[1;38;5;96m"    # Keyword/Statement/Operator/Define — bold 96
HL_STRING  = "\e\[1;38;5;249m"   # String    — bold 249
HL_NUMBER  = "\e\[1;38;5;131m"   # Number    — bold 131
HL_BOOL    = "\e\[1;38;5;149m"   # Boolean   — bold 149
HL_TYPE    = "\e\[1;38;5;60m"    # Type/ClassName/Identifier — bold 60
HL_CONST   = "\e\[1;38;5;179m"   # Constant/Symbol/nil/self   — bold 179

# Keywords (Tungsten + the C subset that shows up in runtime intrinsics).
HL_KEYWORDS = ["if", "else", "elsif", "unless", "case", "when", "then", "while", "until", "do", "begin", "rescue", "ensure", "return", "break", "continue", "next", "use", "load", "require", "trait", "is", "as", "in", "and", "not", "or", "xor", "super", "yield", "raise", "error", "throw", "module", "with", "always", "redo", "retry", "fn", "ro", "rw", "wo", "static", "for", "switch", "const", "struct", "typedef", "sizeof", "goto", "default", "union", "enum", "extern", "inline", "volatile", "unsigned", "signed", "void", "int", "char", "size_t", "uint8_t", "int64_t", "uint64_t", "uint32_t", "int32_t", "bool"]

# Date-inspector tables (port of inspection.rb's date scene — `? <date>`).
INSP_DAY_NAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
INSP_MONTH_NAMES = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
INSP_CAL_WEEKDAYS = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

+ REPL
  -> new(@interpreter = nil, @jit_mode = false, @hot_mode = false)
    @session_log = []
    @history = []
    @jit_counter = 0
    @hot_defs = {}
    @hot_stmts = []
    @last_scrub_src = ""
    @scrub_lines = 0
    @ins_buf = nil
    @ins_count = 0
    @last_inspect_lines = 0
    @scrub_jumpback = 0
    @stdlib_methods = nil

  -> start
    # Survive runtime faults (div-by-zero, type errors): route die() through the
    # catchable begin/rescue path so a fault ends one line, not the session.
    ccall("w_enable_catchable_die")
    load_history()
    print_banner()
    # Enable raw mode once for the whole session (no-op when stdin isn't a tty,
    # so piped/redirected input keeps cooked line reads). Restored on exit.
    ccall("w_term_raw_enable")
    repl_loop()
    ccall("w_term_raw_disable")
    save_history()
    << RESET

  # ── Banner ──────────────────────────────────────────────────────

  -> print_banner
    # Version comes from the repo-root VERSION file via the bin/tungsten
    # wrapper's TUNGSTEN_VERSION export (single source of truth, #12).
    v = env("TUNGSTEN_VERSION")
    if v == nil || v == ""
      v = "dev"
    << BOLD + YELLOW + "✶ Tungsten" + RESET + " " + DIM + "v" + v + RESET
    << DIM + "  ? help · ? EXPR inspect · :help NAME docs · Tab complete · Ctrl+D exit" + RESET
    << ""

  -> prompt
    MAGENTA + "wit" + RESET + ">" + " "

  -> continuation_prompt
    DIM + "  ·  " + RESET

  # ── Main loop ──────────────────────────────────────────────────

  -> repl_loop
    buffer = ""
    continuing = false

    while true
      if continuing
        p = continuation_prompt()
      else
        p = prompt()

      line = read_line(p)
      if line == nil
        << ""
        return
      if line.size() > 0
        record_history(line)

      buffer = buffer + line + "\n"

      if code_complete?(buffer)
        input = buffer.strip()
        buffer = ""
        continuing = false

        if input.size() == 0
          # Blank Enter always re-enters scrub mode on the LAST command (Bret
          # Victor token scrubber) — dials + arrows tweak it live. If the prior
          # command was `? expr`, @scrub_jumpback is the line count of that
          # inspection, so the scrub jumps the cursor BACK up over it and
          # repaints in place instead of printing a second copy below.
          jb = @scrub_jumpback
          @scrub_jumpback = 0
          enter_scrub_mode(@last_scrub_src, jb)
          next
        # Any non-blank command invalidates a pending in-place jumpback.
        @scrub_jumpback = 0
        if input == "?"
          print_shortcuts()
          next
        if input.starts_with?("?")
          # `? expr` inspects the expression (evaluate + show the value), like
          # the Ruby REPL. Scrubbing is blank-Enter / `scrub`, not `?` — but the
          # inspected expression becomes the scrub target, and its on-screen line
          # count is remembered so a following blank Enter scrubs it in place.
          inspect_expr = input.slice(1, input.size() - 1).strip()
          handle_inspect(inspect_expr)
          @last_scrub_src = inspect_expr
          # +2: jump back over the inspection AND the `wit> ? …` command line
          # itself, so the scrub repaints starting on that prompt line.
          @scrub_jumpback = @last_inspect_lines + 2
          next
        if input == ":help" || input.starts_with?(":help ")
          show_help(input.slice(5, input.size() - 5).strip())
          next
        if input == "/paste"
          handle_paste()
          next
        if input.starts_with?("show-method ")
          show_method(input.slice(12, input.size()).strip())
          next
        if input == "scrub"
          enter_scrub_mode(@last_scrub_src, 0)
          next
        if input.starts_with?("scrub ")
          enter_scrub_mode(input.slice(6, input.size() - 6).strip(), 0)
          next

        # Track EVERY evaluated command as the scrub target, so blank-Enter
        # always re-opens the actual last command (not a stale field-ful one).
        @last_scrub_src = input
        evaluate_and_display(input)
      else
        continuing = true

  # ── Line input ─────────────────────────────────────────────────
  # On a tty we drive a raw-mode editor (history recall, backspace); piped /
  # redirected input falls back to cooked line reads so scripts still work.

  -> read_line(p)
    ccall("w_print", p)
    tty = ccall("w_isatty_stdin")
    if tty != true
      return ccall("w_read_line_stdin")
    raw_edit(p)

  -> record_history(line)
    n = @history.size()
    if n == 0 || @history[n - 1] != line
      @history.push(line)

  # ── History persistence (~/.tungsten_history) ──────────────────
  # Single-line entries joined by newlines; loaded on start, saved (last 1000)
  # on exit. Multiline blocks are stored as their constituent lines, which is
  # enough for arrow-key recall of the common single-line case.

  -> history_path
    home = env("HOME")
    if home == nil
      return nil
    home + "/.tungsten_history"

  -> load_history
    path = history_path()
    if path == nil
      return
    content = read_file(path)
    if content == nil
      return
    lines = content.split("\n")
    i = 0
    while i < lines.size()
      l = lines[i]
      if l.size() > 0
        @history.push(l)
      i = i + 1

  -> save_history
    path = history_path()
    if path == nil
      return
    first = 0
    if @history.size() > 1000
      first = @history.size() - 1000
    out = ""
    i = first
    while i < @history.size()
      out = out + @history[i] + "\n"
      i = i + 1
    write_file(path, out)

  # Redraw the whole line and park the cursor at column `pos`. Reprinting the
  # prompt + line after \r + clear-to-EOL handles inserts, deletes, and
  # history swaps uniformly (the input is plain ASCII, so size == columns).
  -> refresh(p, line, pos)
    ccall("w_print", "\r" + "\e\[K")
    ccall("w_print", p)
    ccall("w_print", line)
    back = line.size() - pos
    i = 0
    while i < back
      ccall("w_print", "\e\[D")
      i = i + 1

  # Raw keypress loop with a movable cursor. Returns the entered line, "" on
  # Ctrl-C (cancel), or nil on Ctrl-D/EOF at an empty line (exit). Supports
  # insert/delete at the cursor, Left/Right, Home/End, and Up/Down history.
  -> raw_edit(p)
    line = ""
    pos = 0
    hist_pos = @history.size()
    saved = ""
    while true
      k = ccall("w_read_key")
      if k == -1
        return nil
      if k == 4
        if line.size() == 0
          return nil
      elsif k == 13 || k == 10
        ccall("w_print", "\n")
        return line
      elsif k == 3
        ccall("w_print", "^C\n")
        return ""
      elsif k == 1
        pos = 0
        refresh(p, line, pos)
      elsif k == 5
        pos = line.size()
        refresh(p, line, pos)
      elsif k == 9
        comp = complete_word(line, pos)
        if comp != nil
          line = comp[0]
          pos = comp[1]
          refresh(p, line, pos)
      elsif k == 127 || k == 8
        if pos > 0
          line = line.slice(0, pos - 1) + line.slice(pos, line.size())
          pos = pos - 1
          refresh(p, line, pos)
      elsif k == 27
        k2 = ccall("w_read_key")
        if k2 == 91 || k2 == 79
          k3 = ccall("w_read_key")
          if k3 == 65
            if hist_pos > 0
              if hist_pos == @history.size()
                saved = line
              hist_pos = hist_pos - 1
              line = @history[hist_pos]
              pos = line.size()
              refresh(p, line, pos)
          elsif k3 == 66
            if hist_pos < @history.size()
              hist_pos = hist_pos + 1
              if hist_pos == @history.size()
                line = saved
              else
                line = @history[hist_pos]
              pos = line.size()
              refresh(p, line, pos)
          elsif k3 == 67
            if pos < line.size()
              pos = pos + 1
              ccall("w_print", "\e\[C")
          elsif k3 == 68
            if pos > 0
              pos = pos - 1
              ccall("w_print", "\e\[D")
          elsif k3 == 72
            pos = 0
            refresh(p, line, pos)
          elsif k3 == 70
            pos = line.size()
            refresh(p, line, pos)
      elsif k >= 32 && k < 127
        ch = k.chr()
        line = line.slice(0, pos) + ch + line.slice(pos, line.size())
        pos = pos + 1
        refresh(p, line, pos)
      elsif k >= 0xC2 && k <= 0xF4
        # UTF-8 lead byte: assemble the sequence (continuation bytes arrive
        # back-to-back) into one codepoint and insert it as one char — so
        # Σ, ∫, ², °F, ¢ can be typed at the prompt. Previously every byte
        # >= 127 was silently dropped, making Unicode literals untypeable in
        # the raw-mode editor. pos/slice are byte-based: advance by ch.size().
        n = 2
        cp = k & 0x1F
        if k >= 0xF0
          n = 4
          cp = k & 0x07
        elsif k >= 0xE0
          n = 3
          cp = k & 0x0F
        j = 1
        ok = true
        while j < n
          kc = ccall("w_read_key")
          if kc < 0x80 || kc > 0xBF
            ok = false
            break
          cp = (cp << 6) | (kc & 0x3F)
          j = j + 1
        if ok && cp >= 0x80
          ch = cp.chr()
          line = line.slice(0, pos) + ch + line.slice(pos, line.size())
          pos = pos + ch.size()
          refresh(p, line, pos)

  # ── Tab completion ─────────────────────────────────────────────
  # Complete the identifier ending at the cursor against keywords + names the
  # session knows (defined functions and assigned variables in --hot). A single
  # match fills in; multiple matches fill the shared prefix. NOTE: slice(a, b)
  # is (start, LENGTH) — slice(k, 1) is one char, slice(a, b - a) is [a, b).

  -> ident_char?(c)
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_".include?(c)

  -> completion_candidates
    cands = []
    i = 0
    while i < KEYWORDS.size()
      cands.push(KEYWORDS[i])
      i = i + 1
    dk = @hot_defs.keys()
    j = 0
    while j < dk.size()
      cands.push(dk[j])
      j = j + 1
    s = 0
    while s < @hot_stmts.size()
      nm = hot_assign_name(@hot_stmts[s].strip())
      if nm != nil
        cands.push(nm)
      s = s + 1
    cands

  -> common_prefix(matches)
    pre = matches[0]
    i = 1
    while i < matches.size()
      m = matches[i]
      k = 0
      while k < pre.size() && k < m.size() && pre.slice(k, 1) == m.slice(k, 1)
        k = k + 1
      pre = pre.slice(0, k)
      i = i + 1
    pre

  # Returns [new_line, new_pos] on a completion, or nil for no change.
  -> complete_word(line, pos)
    start = pos
    while start > 0 && ident_char?(line.slice(start - 1, 1))
      start = start - 1
    partial = line.slice(start, pos - start)
    if partial.size() == 0
      return nil
    matches = []
    # Receiver context: completing right after a `.` draws from the stdlib
    # method pool instead of keywords/session names ("ask a value what it can do").
    if start > 0 && line.slice(start - 1, 1) == "."
      cands = stdlib_method_candidates()
    else
      cands = completion_candidates()
    i = 0
    while i < cands.size()
      if cands[i].starts_with?(partial) && cands[i] != partial
        matches.push(cands[i])
      i = i + 1
    if matches.size() == 0
      return nil
    fill = common_prefix(matches)
    if fill.size() <= partial.size()
      return nil
    suffix = fill.slice(partial.size(), fill.size() - partial.size())
    new_line = line.slice(0, pos) + suffix + line.slice(pos, line.size())
    [new_line, pos + suffix.size()]

  # ── Shortcuts ──────────────────────────────────────────────────

  -> print_shortcuts
    << BOLD + "Shortcuts:" + RESET
    << "  ?             " + DIM + "show this help" + RESET
    << "  ? EXPR        " + DIM + "inspect EXPR — value + typed breakdown (try ? 2026-12-25)" + RESET
    << "  ? Σ(2x⁷+3x²)  " + DIM + "sum a polynomial (blank Enter scrubs it live); ? ∫(x², 0..2) plots + shades the AUC" + RESET
    << "  :help NAME    " + DIM + "stdlib docs — class summary, or Class#method source" + RESET
    << "  Tab           " + DIM + "complete keywords, your names, and stdlib methods after a dot" + RESET
    << "  Enter         " + DIM + "blank line live-scrubs the last expr (or type `scrub`) — dials + arrows, q exits" + RESET
    << "  /paste        " + DIM + "multiline paste mode (end with /end)" + RESET
    << "  show-method   " + DIM + "print a method's source (show-method String#split)" + RESET
    << "  Ctrl+D        " + DIM + "exit" + RESET
    << ""
    << DIM + "  flags: --jit compiles each line natively · --hot hot-reloads the session" + RESET
    << ""

  # ── :help — stdlib docs, pure lookup (#15) ─────────────────────
  # `:help Array` prints the class's one-line summary, read from the class
  # source header — the same line doc/CORE.md's summaries are generated from —
  # plus the source path. `:help Class#method` delegates to show-method.

  -> show_help(name)
    if name == nil || name.size() == 0
      << DIM + "  usage: :help Array   or   :help String#split" + RESET
      return
    if name.include?("#")
      show_method(name)
      return
    if @interpreter == nil
      << BRIGHT_RED + "  :help needs the interpreter" + RESET
      return
    file = @interpreter.class_file(name)
    if file == nil
      << DIM + "  no stdlib class named " + RESET + CYAN + name + RESET + DIM + "  (try :help Array, or :help String#split)" + RESET
      return
    src = read_file(file)
    if src == nil
      << BRIGHT_RED + "  cannot read " + file + RESET
      return
    << DIM + "  # " + name + "  ·  " + file + RESET
    summary = class_header_summary(src, name)
    if summary != nil
      << "  " + summary
    else
      << DIM + "  (no header summary in the source)" + RESET

  # First SUBSTANTIVE comment line of a file header — the same rule
  # scripts/gen_core_doc.rb uses for the CORE.md summary: skip a bare
  # "ClassName" (or "ClassName trait") title line, @-metadata, and URLs.
  -> class_header_summary(src, name)
    lines = src.split("\n")
    i = 0
    while i < lines.size()
      line = lines[i].strip()
      if line.starts_with?("#")
        text = line.slice(1, line.size() - 1).strip()
        if text.size() > 0 && !skip_summary_line?(text, name)
          return text
      elsif line.size() > 0
        return nil
      i = i + 1
    nil

  -> skip_summary_line?(text, name)
    # Exact match on the title line (core headers write the class name
    # verbatim, e.g. `# Array`); the generator also folds case, but neither
    # lowercase nor downcase round-trips in this interpreter context.
    if text == name || text == name + " trait"
      return true
    if text.starts_with?("@") || text.starts_with?("http://") || text.starts_with?("https://")
      return true
    false

  # ── Stdlib method completion (#14) ─────────────────────────────
  # After a `.` the completion pool becomes the union of stdlib method names,
  # gathered lazily (once per session) by scanning the `-> name` definitions of
  # every class in the interpreter's autoload registry — the same manifest that
  # drives core autoloading, so new stdlib classes appear automatically.

  -> stdlib_method_candidates
    if @stdlib_methods != nil
      return @stdlib_methods
    seen = {}
    if @interpreter != nil
      reg = @interpreter.autoload_registry()
      ks = reg.keys()
      i = 0
      while i < ks.size()
        src = read_file("core/" + reg[ks[i]] + ".w")
        if src != nil
          collect_method_names(src, seen)
        i = i + 1
    @stdlib_methods = seen.keys()
    @stdlib_methods

  -> collect_method_names(src, seen)
    lines = src.split("\n")
    i = 0
    while i < lines.size()
      line = lines[i].strip()
      if line.starts_with?("-> ")
        name = method_name_of(line.slice(3, line.size() - 3))
        if name != nil && name.size() > 0
          seen[name] = true
      i = i + 1

  # The identifier at the start of a `-> ` definition: letters/digits/_ plus a
  # trailing ? or !. Stops at `(`, `/N` arity, space, or an operator name.
  -> method_name_of(text)
    out = ""
    i = 0
    while i < text.size()
      c = text.slice(i, 1)
      if ident_char?(c)
        out = out + c
      elsif (c == "?" || c == "!") && out.size() > 0
        return out + c
      else
        return out
      i = i + 1
    out

  # ── Scrub mode (Bret Victor-style token scrubber) ──────────────
  # Live-edit the numeric fields of an expression and watch the value update.
  # Each scrubbable field maps to a Stream Deck + dial (page of 4; press a dial
  # to page) AND to the keyboard: ←→/h l select, ↑↓/+-/[] nudge, q/Enter exit.
  # Input is multiplexed (keyboard + dials) by w_input_poll; the session already
  # owns raw mode, so scrub never touches termios.

  -> scrub_digit?(c)
    c >= "0" && c <= "9"

  -> scrub_ident?(c)
    (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9") || c == "_"

  # True if src[pos .. pos+k-1] are all ASCII digits.
  -> scrub_digits_at?(src, pos, k)
    if pos + k > src.size()
      return false
    j = 0
    while j < k
      if !scrub_digit?(src.slice(pos + j, 1))
        return false
      j = j + 1
    true

  # If a date/datetime/month literal starts at i, return [len, ftype]
  # (1=date YYYY-MM-DD, 2=datetime …Thh:mm:ss, 3=month YYYY-MM); else nil.
  # Year-anchored so it never false-matches `2026 - 12` arithmetic.
  -> scrub_datelike(src, i)
    n = src.size()
    if !scrub_digits_at?(src, i, 4)
      return nil
    if i + 4 >= n || src.slice(i + 4, 1) != "-"
      return nil
    if !scrub_digits_at?(src, i + 5, 2)
      return nil
    # YYYY-MM present. A following "-DD" makes it a date (else a month literal).
    if i + 7 < n && src.slice(i + 7, 1) == "-" && scrub_digits_at?(src, i + 8, 2)
      if i + 10 < n && scrub_digit?(src.slice(i + 10, 1))
        return nil                              # YYYY-MM-DDD → not a date
      if i + 13 < n && src.slice(i + 10, 1) == "T" && scrub_digits_at?(src, i + 11, 2) && src.slice(i + 13, 1) == ":"
        e = i + 11                              # extend over the hh:mm:ss component
        while e < n && (scrub_digit?(src.slice(e, 1)) || src.slice(e, 1) == ":")
          e = e + 1
        return [e - i, 2]
      return [10, 1]
    if i + 7 < n && scrub_digit?(src.slice(i + 7, 1))
      return nil                                # YYYY-MMM → not a month
    return [7, 3]

  # Detect an IPv4 literal a.b.c.d (each octet 1-3 digits) starting at `i`.
  # Returns [octet_spans, total_len] where octet_spans is a list of [start, len]
  # (one per octet), or nil. Lets the scrubber expose all four octets as fields.
  -> scrub_ipv4(src, i)
    n = src.size()
    octets = []
    pos = i
    k = 0
    while k < 4
      ds = pos
      while pos < n && pos - ds < 3 && scrub_digit?(src.slice(pos, 1))
        pos = pos + 1
      if pos == ds
        return nil
      octets.push([ds, pos - ds])
      if k < 3
        if pos >= n || src.slice(pos, 1) != "."
          return nil
        pos = pos + 1
      k = k + 1
    # Boundary: a.b.c.d must not run into another digit/dot/ident char.
    if pos < n
      nc = src.slice(pos, 1)
      if scrub_digit?(nc) || nc == "." || scrub_ident?(nc)
        return nil
    [octets, pos - i]

  # Scrubbable fields as [start, len, ftype]: ftype 0 = numeric (int/decimal),
  # 1 = date, 2 = datetime, 3 = month, 4 = IPv4 octet (clamped 0-255). Date-shaped
  # and IPv4 literals are matched specially (calendar rollover / per-octet); else
  # a plain numeric span (skipping numbers inside identifiers (x2) or colors (#ff0)).
  -> scrub_field_spans(src)
    spans = []
    n = src.size()
    i = 0
    while i < n
      c = src.slice(i, 1)
      if !scrub_digit?(c)
        i = i + 1
      else
        embedded = false
        if i > 0
          p = src.slice(i - 1, 1)
          if scrub_ident?(p) || p == "#"
            embedded = true
        if embedded
          j = i
          while j < n && scrub_digit?(src.slice(j, 1))
            j = j + 1
          i = j
        else
          dl = scrub_datelike(src, i)
          ip = nil
          if dl == nil
            ip = scrub_ipv4(src, i)
          if dl != nil
            spans.push([i, dl[0], dl[1]])
            i = i + dl[0]
          elsif ip != nil
            octets = ip[0]
            oi = 0
            while oi < octets.size()
              oct = octets[oi]
              spans.push([oct[0], oct[1], 4])
              oi = oi + 1
            i = i + ip[1]
          else
            start = i
            j = i
            seen_dot = false
            while j < n
              cj = src.slice(j, 1)
              if scrub_digit?(cj)
                j = j + 1
              elsif cj == "." && !seen_dot && j + 1 < n && scrub_digit?(src.slice(j + 1, 1))
                seen_dot = true
                j = j + 1
              else
                break
            # Grow backward over a directly-adjacent UNARY minus (no accumulating
            # "---"), but leave a binary subtraction (`1 - 2`, space) alone.
            span_start = start
            if start > 0 && src.slice(start - 1, 1) == "-"
              bk = start - 2
              while bk >= 0 && src.slice(bk, 1) == " "
                bk = bk - 1
              prev = " "
              if bk >= 0
                prev = src.slice(bk, 1)
              if bk < 0 || prev == "(" || prev == "+" || prev == "-" || prev == "*" || prev == "/" || prev == "," || prev == "="
                span_start = start - 1
            spans.push([span_start, j - span_start, 0])
            i = j
    spans

  -> scrub_field_count(src)
    scrub_field_spans(src).size()

  # Nudge field [start,len,ftype] by `delta` steps at magnitude `mag`
  # (0 small, 1 medium, 2 large). Numeric fields scale ×1/×10/×100; date-shaped
  # fields nudge by day/month/year with calendar rollover (w_date_scrub).
  -> scrub_apply(src, field, delta, mag)
    start = field[0]
    flen = field[1]
    ftype = field[2]
    text = src.slice(start, flen)
    if ftype == 0
      mult = 1
      if mag == 1
        mult = 10
      elsif mag == 2
        mult = 100
      step = delta * mult
      dot = str_index(text, ".")
      if dot < 0
        v = text.to_i() + step
        rep = v.to_s()
      else
        ipart = text.slice(0, dot)
        fpart = text.slice(dot, flen - dot)
        v = ipart.to_i() + step
        rep = v.to_s() + fpart
    elsif ftype == 4
      # IPv4 octet — scale like a numeric field but clamp to 0-255.
      mult = 1
      if mag == 1
        mult = 10
      elsif mag == 2
        mult = 100
      v = text.to_i() + delta * mult
      if v < 0
        v = 0
      if v > 255
        v = 255
      rep = v.to_s()
    else
      rep = ccall("w_date_scrub", "" + text, mag, delta)
    src.slice(0, start) + rep + src.slice(start + flen, src.size() - (start + flen))

  -> scrub_nxt(cur, count)
    if count == 0
      return 0
    (cur + 1) % count

  -> scrub_prv(cur, count)
    if count == 0
      return 0
    (cur - 1 + count) % count

  -> scrub_highlight(src, spans, cursor)
    sp = spans[cursor]
    st = sp[0]
    ln = sp[1]
    src.slice(0, st) + "\e\[7m" + src.slice(st, ln) + "\e\[0m" + src.slice(st + ln, src.size() - (st + ln))

  -> scrub_eval(src)
    begin
      v = @interpreter.run("_ = (" + src + ")")
      return format_value(v)
    rescue e
      return DIM + "(incomplete)" + RESET

  # Repaint the scrub view IN PLACE: a header line (the source with the selected
  # field reverse-highlighted + key hints) followed by the FULL live inspection
  # of the scrubbed value (result/type/scene/breakdown), re-rendered each nudge.
  -> redraw_scrub(src, spans, cursor)
    shown = scrub_highlight(src, spans, cursor)
    body = build_inspect(src)
    if @scrub_lines > 1
      k = 0
      while k < @scrub_lines - 1
        ccall("w_print", "\e\[A")
        k = k + 1
    ccall("w_print", "\r\e\[J")
    # The header re-renders the ORIGINAL command line (prompt + `? ` + the
    # expression) with the selected field highlighted, so scrubbing edits the
    # chars you typed at the prompt in place — not a separate `scrub>` copy.
    header = prompt() + "? " + shown + "   " + DIM + "↑↓/dial nudge · \[ \] { } bigger (mo/yr) · ←→ select · q" + RESET
    ccall("w_print", header + "\r\n" + body)
    @scrub_lines = 1 + scrub_count_lines(body)
    ccall("w_flush")

  # `? expr` — inspect: evaluate the expression and show its value + runtime
  # type (like the Ruby REPL's inspection query). Does NOT scrub.
  -> handle_inspect(expr)
    if expr == nil || expr.size() == 0
      print_shortcuts()
      return
    @ins_count = 0
    if math_inspect(expr)
      @last_inspect_lines = @ins_count
      return
    begin
      v = @interpreter.run("_ = (" + expr + ")")
      @ins_count = 0
      render_inspect(v, type(v))
      @last_inspect_lines = @ins_count
    rescue e
      << BRIGHT_RED + "  error: " + RESET + e.to_s()

  # Emit one inspection line — printed directly for a one-shot `? expr`, or
  # captured into @ins_buf (raw-mode \r\n line ends) so the scrub loop can
  # repaint the whole inspection IN PLACE as the value is nudged. @ins_count
  # tracks the printed line total (so blank-Enter can jump back over it).
  -> ins(s)
    @ins_count = @ins_count + 1
    if @ins_buf == nil
      << s
    else
      @ins_buf = @ins_buf + s + "\r\n"

  # Emit a multi-line C-built block (color/ip4 scene, breakdown fields), trailing
  # newline stripped; the buffered form converts embedded \n → \r\n.
  -> ins_block(s)
    n = s.size()
    if n > 0 && s.slice(n - 1, 1) == "\n"
      s = s.slice(0, n - 1)
    @ins_count = @ins_count + scrub_count_lines(s)
    if @ins_buf == nil
      << s
    else
      @ins_buf = @ins_buf + scrub_crlf(s) + "\r\n"

  -> scrub_crlf(s)
    out = ""
    i = 0
    n = s.size()
    while i < n
      c = s.slice(i, 1)
      if c == "\n"
        out = out + "\r\n"
      else
        out = out + c
      i = i + 1
    out

  -> scrub_count_lines(s)
    c = 1
    i = 0
    n = s.size()
    while i < n
      if s.slice(i, 1) == "\n"
        c = c + 1
      i = i + 1
    c

  # Render the full inspection (result/type header + per-type scene + universal
  # breakdown) via ins(), so the same code serves `? expr` and the scrub repaint.
  -> render_inspect(v, tn)
    ins(DIM + "  result   " + RESET + insp_value_label(v, tn))
    ins(DIM + "  type     " + RESET + insp_type_label(tn))
    if tn == "Date"
      inspect_date_scene(v)
    if tn == "Color"
      ins_block(ccall("w_color_scene", v))
    if tn == "IPv4"
      ins_block(ccall("w_ip4_scene", v))
    insp_breakdown(v)

  # Build the inspection of `src` as one \r\n-joined string (no trailing newline)
  # for the in-place scrub repaint; "(incomplete)" if `src` doesn't evaluate.
  -> build_inspect(src)
    begin
      # Math scenes (Σ/∫) render themselves — including the AUC plot — so the
      # scrub repaint redraws the whole scene as the polynomial is nudged.
      @ins_buf = ""
      if math_inspect(src)
        body = @ins_buf
        @ins_buf = nil
        n = body.size()
        if n >= 2 && body.slice(n - 2, 2) == "\r\n"
          body = body.slice(0, n - 2)
        return body
      @ins_buf = nil
      v = @interpreter.run("_ = (" + src + ")")
      @ins_buf = ""
      render_inspect(v, type(v))
      body = @ins_buf
      @ins_buf = nil
      n = body.size()
      if n >= 2 && body.slice(n - 2, 2) == "\r\n"
        body = body.slice(0, n - 2)
      return body
    rescue e
      @ins_buf = nil
      return DIM + "  (incomplete)" + RESET

  # ── `? Σ(…)` / `? ∫(…)` — math inspection scenes ────────────────────────
  # `? Σ(2x⁷ + 3x²)` sums over a default x = 1..10 (labeled as such);
  # explicit bounds via `? Σ(poly, 1..100)`. `? ∫(x², 0..2)` also renders a
  # braille plot of the curve with the area under it shaded. Everything goes
  # through ins()/ins_block, so the one-shot `?` and the blank-Enter scrub
  # repaint share the scene — scrubbing a coefficient redraws the plot live.

  -> math_inspect(src)
    t = src.strip()
    # Prefix-detect Σ( / ∫( with size-consistent arithmetic — these are multi-
    # byte codepoints, so never slice by fixed counts around them.
    # (named mfn, not fn: `fn` is a stage-0 C VM keyword and can't be a local)
    mfn = ""
    if t.starts_with?("Σ(")
      mfn = "Σ"
    elsif t.starts_with?("∫(")
      mfn = "∫"
    else
      return false
    if !t.ends_with?(")")
      return false
    plen = mfn.size() + 1
    inner = t.slice(plen, t.size() - plen - 1)
    parts = math_split_top_comma(inner)
    poly = parts[0].strip()
    range_text = parts[1]
    defaulted = false
    if range_text == nil
      if mfn == "∫"
        ins(BRIGHT_RED + "  ∫ needs bounds: ? ∫(x², 0..2)" + RESET)
        return true
      range_text = "1..10"
      defaulted = true
    else
      range_text = range_text.strip()
    v = nil
    begin
      v = @interpreter.run("_ = (" + mfn + "(" + poly + ", " + range_text + "))")
    rescue e
      ins(BRIGHT_RED + "  error: " + RESET + e.to_s())
      return true
    var = math_bound_var(poly)
    if var == nil
      var = "x"
    note = ""
    if defaulted
      note = DIM + "   (default range — try Σ(" + poly + ", 1..100))" + RESET
    ins(DIM + "  result   " + RESET + BOLD + format_value(v) + RESET)
    ins(DIM + "  over     " + RESET + var + " = " + range_text + note)
    if mfn == "∫"
      math_plot_auc(poly, var, range_text)
    true

  # Split `inner` at its last top-level comma → [before, after-or-nil].
  -> math_split_top_comma(inner)
    depth = 0
    cut = 0 - 1
    i = 0
    while i < inner.size()
      c = inner.slice(i, 1)
      if c == "(" || c == "\["
        depth = depth + 1
      elsif c == ")" || c == "]"
        depth = depth - 1
      elsif c == "," && depth == 0
        cut = i
      i = i + 1
    if cut < 0
      return [inner, nil]
    [inner.slice(0, cut), inner.slice(cut + 1, inner.size() - cut - 1)]

  # The single distinct lowercase single-letter identifier in `poly`, or nil.
  -> math_bound_var(poly)
    seen = nil
    i = 0
    while i < poly.size()
      c = poly.slice(i, 1)
      if c >= "a" && c <= "z"
        before = " "
        if i > 0
          before = poly.slice(i - 1, 1)
        after = " "
        if i + 1 < poly.size()
          after = poly.slice(i + 1, 1)
        if !ident_char?(before) && !ident_char?(after)
          if seen != nil && seen != c
            return nil
          seen = c
      i = i + 1
    seen

  # Braille dot mask for (px 0-1, py 0-3) inside one cell.
  -> braille_bit(px, py)
    if px == 0
      if py == 0
        return 0x01
      elsif py == 1
        return 0x02
      elsif py == 2
        return 0x04
      return 0x40
    if py == 0
      return 0x08
    elsif py == 1
      return 0x10
    elsif py == 2
      return 0x20
    0x80

  # Plot `poly` over the range and shade the area between the curve and the
  # x-axis (the AUC) with braille dots. Sampling re-evaluates the polynomial
  # through the interpreter at 64 x positions built from the ORIGINAL bound
  # texts (integer-bound ranges stay float-clean via .to_f).
  -> math_plot_auc(poly, var, range_text)
    dots_w = 64
    dots_h = 24
    bounds = range_text.split("..")
    if bounds.size() != 2
      return nil
    a_text = bounds[0].strip()
    b_text = bounds[1].strip()
    # Reversed bounds (mid-scrub, or typed that way): plot the swapped interval
    # and say so — the value above already carries the sign convention.
    a_probe = nil
    b_probe = nil
    begin
      a_probe = @interpreter.run("_ = ((" + a_text + ").to_f)")
      b_probe = @interpreter.run("_ = ((" + b_text + ").to_f)")
    rescue e
      ins(DIM + "  (plot unavailable: bounds not numeric)" + RESET)
      return nil
    if a_probe > b_probe
      t_text = a_text
      a_text = b_text
      b_text = t_text
      ins(DIM + "  (bounds reversed — plotting " + a_text + ".." + b_text + "; value is negated)" + RESET)
    ys = []
    col = 0
    while col < dots_w
      sample_src = var + " = (" + a_text + ").to_f + " + col.to_s() + " * ((" + b_text + ") - (" + a_text + ")).to_f / " + (dots_w - 1).to_s() + "\n_ = (" + poly + ")"
      y = nil
      begin
        y = @interpreter.run(sample_src)
      rescue e
        ins(DIM + "  (plot unavailable: " + e.to_s() + ")" + RESET)
        return nil
      if type(y) != "Float" && type(y) != "Int"
        ins(DIM + "  (plot unavailable: non-numeric sample)" + RESET)
        return nil
      ys.push(y.to_f)
      col = col + 1
    ymin = ~0.0
    ymax = ~0.0
    i = 0
    while i < dots_w
      if ys[i] < ymin
        ymin = ys[i]
      if ys[i] > ymax
        ymax = ys[i]
      i = i + 1
    span = ymax - ymin
    if span <= ~0.0
      span = ~1.0
    cells_w = dots_w / 2
    cells_h = dots_h / 4
    cells = []
    i = 0
    while i < cells_w * cells_h
      cells.push(0)
      i = i + 1
    zero_dy = dots_h - 1 - (((~0.0 - ymin) / span) * (dots_h - 1)).to_i
    col = 0
    while col < dots_w
      dy = dots_h - 1 - (((ys[col] - ymin) / span) * (dots_h - 1)).to_i
      lo = dy
      hi = zero_dy
      if lo > hi
        lo = zero_dy
        hi = dy
      d = lo
      while d <= hi
        idx = (d / 4) * cells_w + (col / 2)
        cells[idx] = cells[idx] | braille_bit(col % 2, d % 4)
        d = d + 1
      col = col + 1
    ins("")
    r = 0
    while r < cells_h
      line = "  "
      cx = 0
      while cx < cells_w
        line = line + (0x2800 + cells[r * cells_w + cx]).chr
        cx = cx + 1
      r = r + 1
      ins(CYAN + line + RESET)
    pad_n = cells_w - a_text.size() - b_text.size()
    if pad_n < 1
      pad_n = 1
    ins(DIM + "  " + a_text + (" " * pad_n) + b_text + RESET)
    nil

  # ── Rich `? <date>` inspector (port of inspection.rb's date scene) ──────
  # Renders the long-date header, season rail, Day/Week stats, the month
  # calendar with the day boxed, and a holiday ASCII-art panel — using the
  # Phase-1 date intrinsics (year/month/day/wday/day_of_year/cweek/days_in_month)
  # plus the name tables above (core/date.w's bodied strftime isn't loadable
  # yet). Layout is codepoint-aware (DATE_SCENE_WIDTH=80, right column=42).

  -> insp_pad(n)
    if n <= 0
      return ""
    " " * n

  -> insp_pad2(n)
    if n < 10
      return "0" + n.to_s()
    n.to_s()

  # Visible length: strip \e[…m sequences, count codepoints (not bytes).
  -> insp_vlen(s)
    out = ""
    i = 0
    n = s.size()
    while i < n
      c = s.slice(i, 1)
      if c == "\e"
        while i < n && s.slice(i, 1) != "m"
          i = i + 1
        i = i + 1
      else
        out = out + c
        i = i + 1
    out.chars().size()

  -> insp_ansi(text, code)
    "\e\[" + code + "m" + text + "\e\[0m"

  -> insp_ordinal(day)
    m100 = day % 100
    if m100 >= 11 && m100 <= 13
      return "th"
    m10 = day % 10
    if m10 == 1
      return "st"
    if m10 == 2
      return "nd"
    if m10 == 3
      return "rd"
    "th"

  -> insp_season_idx(mo, dy)
    md = mo * 100 + dy
    if md >= 320 && md <= 620
      return 0
    if md >= 621 && md <= 921
      return 1
    if md >= 922 && md <= 1220
      return 2
    3

  -> insp_season_rail(idx)
    if idx == 0
      return "\[✿\] ☀  ☙  ❄"
    if idx == 1
      return "✿ \[☀\] ☙  ❄"
    if idx == 2
      return "✿  ☀ \[☙\] ❄"
    "✿  ☀  ☙ \[❄\]"

  # Holiday name (no icon) for the subheader, or "" if none. Fixed-date only
  # for now (floating MLK/Easter/Thanksgiving deferred).
  -> insp_holiday(mo, dy)
    if mo == 1 && dy == 1
      return "New Year's Day"
    if mo == 2 && dy == 14
      return "Valentine's Day"
    if mo == 3 && dy == 14
      return "Pi Day"
    if mo == 3 && dy == 17
      return "St. Patrick's Day"
    if mo == 6 && dy == 19
      return "Juneteenth"
    if mo == 7 && dy == 4
      return "Independence Day"
    if mo == 10 && dy == 31
      return "Halloween"
    if mo == 12 && dy == 25
      return "Christmas"
    if mo == 12 && dy == 31
      return "New Year's Eve"
    ""

  -> insp_christmas_tree
    g = "32"
    [insp_ansi(" o", "31") + "--" + insp_ansi("o", "33") + "--" + insp_ansi("o", "32") + "--" + insp_ansi("o", "36") + "--" + insp_ansi("o", "35") + "--" + insp_ansi("o", "31") + "--" + insp_ansi("o", "33") + "--" + insp_ansi("o", "32"),
     "                         " + insp_ansi("*", "33"),
     "                        " + insp_ansi("/_\\", g),
     "                       " + insp_ansi("/_", g) + insp_ansi("o", "31") + insp_ansi("_\\", g),
     "                      " + insp_ansi("/_", g) + insp_ansi("o", "33") + insp_ansi("_", g) + insp_ansi("o", "31") + insp_ansi("_\\", g),
     "                     " + insp_ansi("/_", g) + insp_ansi("o", "31") + insp_ansi("_", g) + insp_ansi("o", "33") + insp_ansi("_", g) + insp_ansi("o", "36") + insp_ansi("_\\", g),
     "                    " + insp_ansi("/_________\\", g),
     "                        " + insp_ansi("|_|", "38;5;94")]

  -> insp_fourth_of_july
    r = "31"
    w = "37"
    b = "34"
    ["  " + insp_ansi("\\|/", r) + "           " + insp_ansi("\\|/", w) + "                " + insp_ansi("\\|/", b),
     " " + insp_ansi("--", r) + insp_ansi("+", w) + insp_ansi("--", r) + "        " + insp_ansi("--", w) + insp_ansi("+", r) + insp_ansi("--", w) + "              " + insp_ansi("--", b) + insp_ansi("+", w) + insp_ansi("--", b),
     "  " + insp_ansi("/|\\", r) + "           " + insp_ansi("/|\\", w) + "                " + insp_ansi("/|\\", b)]

  -> insp_holiday_art(mo, dy)
    if mo == 12 && dy == 25
      return insp_christmas_tree()
    if mo == 7 && dy == 4
      return insp_fourth_of_july()
    []

  # Splice `text` over buf[col, len(text)] (ASCII-only buffer → byte == col).
  -> insp_splice(buf, col, text)
    tl = text.size()
    buf.slice(0, col) + text + buf.slice(col + tl, buf.size() - (col + tl))

  # Month calendar lines (33 wide), the current day boxed with [DD].
  -> insp_calendar(wday1, curday, dim)
    lines = []
    hdr = ""
    wi = 0
    while wi < 7
      hdr = hdr + INSP_CAL_WEEKDAYS[wi]
      if wi < 6
        hdr = hdr + "   "
      wi = wi + 1
    lines.push(hdr)
    lines.push("-" * 33)
    buf = " " * 33
    wd = wday1
    d = 1
    while d <= dim
      col = wd * 5
      text = insp_pad2(d)
      buf = insp_splice(buf, col, text)
      if d == curday
        if col == 0
          buf = insp_splice(buf, 0, "\[" + text + "\]")
        else
          buf = insp_splice(buf, col - 1, "\[")
          buf = insp_splice(buf, col + 2, "\]")
      if wd == 6
        lines.push(insp_rstrip(buf))
        buf = " " * 33
      d = d + 1
      wd = wd + 1
      if wd > 6
        wd = 0
    if insp_rstrip(buf).size() > 0
      lines.push(insp_rstrip(buf))
    # A 5-week month leaves the calendar one date-row shorter than a 6-week one
    # (and than the 8-line holiday art); pad a trailing blank so the block lines
    # up. lines = header + separator + week rows, so 5 weeks ⇒ size 7.
    if lines.size() == 7
      lines.push("")
    lines

  -> insp_rstrip(s)
    n = s.size()
    while n > 0 && s.slice(n - 1, 1) == " "
      n = n - 1
    s.slice(0, n)

  -> insp_iso(yr, mo, dy)
    yr.to_s() + "-" + insp_pad2(mo) + "-" + insp_pad2(dy)

  -> insp_header(yr, mo, dy, wd, yday, cwk, isleap)
    title = INSP_DAY_NAMES[wd] + ", " + INSP_MONTH_NAMES[mo - 1] + " " + dy.to_s() + insp_ordinal(dy) + ", " + yr.to_s()
    diy = 365
    if isleap
      diy = 366
    daywk = "\[Day " + yday.to_s() + "/" + diy.to_s() + "\] Week " + cwk.to_s()
    rail = insp_season_rail(insp_season_idx(mo, dy))
    statscol = 80 - insp_vlen(daywk)
    seasoncol = (80 - insp_vlen(rail)) / 2 + 4
    leftb = insp_vlen(title) + 2
    rightb = statscol - insp_vlen(rail) - 2
    if seasoncol < leftb
      seasoncol = leftb
    if seasoncol > rightb
      seasoncol = rightb
    line = title
    line = line + insp_pad(seasoncol - insp_vlen(line)) + rail
    line = line + insp_pad(statscol - insp_vlen(line)) + daywk
    line

  -> insp_scene_cols(left, right)
    if right == ""
      return left
    left + insp_pad(42 - insp_vlen(left)) + right

  # WValue bit-field breakdown panel (port of inspection.rb format_wvalue_
  # breakdown + packed_breakdown for a date). Raw hex/binary come from the
  # runtime (w_value_hex16/bin64) to avoid i64 sign issues on the 0xFFFE top
  # bits; the field values reuse the date intrinsics.
  -> insp_ljust(s, w)
    out = s
    while out.size() < w
      out = out + " "
    out

  -> insp_group(s, n)
    out = ""
    i = 0
    len = s.size()
    while i < len
      if i > 0
        out = out + " "
      out = out + s.slice(i, n)
      i = i + n
    out

  -> insp_hline(label, value)
    "  " + insp_ljust(label, 8) + " " + value

  -> insp_fline(label, brange, raw, meaning)
    line = "  " + insp_ljust(label, 8) + " " + insp_ljust(brange, 12) + " " + insp_ljust(raw, 18)
    if meaning != ""
      line = line + " " + meaning
    insp_rstrip(line)

  # Universal WValue breakdown panel for any value: u0x header + grouped hex +
  # grouped binary + the per-tag field rows (decoded in C by w_value_fields to
  # avoid i64 sign issues on the high bits).
  -> insp_breakdown(v)
    hex16 = ccall("w_value_hex16", v)
    bin64 = ccall("w_value_bin64", v)
    # Fold the raw u0x form into the hex row (in parens after the grouped
    # nibbles) instead of a standalone header line above it.
    ins(insp_hline("hex", insp_group(hex16, 4) + " (u0x" + hex16 + ")"))
    ins(insp_hline("binary", insp_group(bin64, 16)))
    ins_block(ccall("w_value_fields", v))

  # result label: dates show their iso form, everything else its normal print.
  -> insp_value_label(v, tn)
    if tn == "Date"
      return insp_iso(v.year, v.month, v.day)
    format_value(v)

  # type label: Tungsten-specific packed types get the Tungsten:: prefix
  # (mirrors inspection.rb inspection_type_label / value.class.name).
  -> insp_type_label(tn)
    if tn in ("Date" "Datetime" "DateTime" "Month" "Time" "Rational" "Decimal" "Currency" "Quantity" "Color" "IPv4" "IP4" "CIDR4" "UUID")
      return "Tungsten::" + tn
    tn

  # The date SCENE only (header / season rail / calendar / art). The result+type
  # header and the u0x breakdown are now universal (handle_inspect/insp_breakdown).
  -> inspect_date_scene(v)
    yr = v.year
    mo = v.month
    dy = v.day
    wd = v.wday
    yday = v.day_of_year
    cwk = v.cweek
    dim = v.days_in_month
    isleap = v.leap?
    wday1 = ((wd - (dy - 1)) % 7 + 7) % 7
    ins("")
    ins(insp_header(yr, mo, dy, wd, yday, cwk, isleap))
    # Always emit the holiday subheader line — blank when it isn't a holiday —
    # so the calendar stays put and the scrub line count is constant as the date
    # crosses in/out of a holiday (mirrors inspection.rb's date_scene_subheader).
    ins(insp_holiday(mo, dy))
    ins("")
    cal = insp_calendar(wday1, dy, dim)
    art = insp_holiday_art(mo, dy)
    maxl = cal.size()
    if art.size() > maxl
      maxl = art.size()
    i = 0
    while i < maxl
      l = ""
      if i < cal.size()
        l = cal[i]
      r = ""
      if i < art.size()
        r = art[i]
      ins(insp_scene_cols(l, r))
      i = i + 1
    ins("")

  # jumpback > 0 means the prior `? expr` inspection (that many lines) is right
  # above the prompt; move the cursor up over it so the scrub repaints in place.
  -> enter_scrub_mode(expr, jumpback)
    if expr == nil || expr.size() == 0
      << DIM + "  nothing to scrub — evaluate an expression with a number, or: scrub <expr>" + RESET
      return
    spans = scrub_field_spans(expr)
    if spans.size() == 0
      # No scrubbable fields — fall back to plain inspection (evaluate + show).
      << DIM + "  =>" + RESET + " " + scrub_eval(expr)
      return
    dev = ccall("w_hid_streamdeck_open")
    src = expr
    cursor = spans.size() - 1
    page = 0
    @scrub_lines = 0
    if jumpback > 0
      k = 0
      while k < jumpback
        ccall("w_print", "\e\[A")
        k = k + 1
    ccall("w_print", "\e\[?25l")
    begin
      redraw_scrub(src, spans, cursor)
      while true
        ev = ccall("w_input_poll", 50)
        step = 0
        mag = 0
        moved = false
        if ev == -2
          break
        elsif ev == -1
          step = 0
        elsif ev < 256
          if ev == 27
            k2 = ccall("w_input_poll", 8)
            k3 = ccall("w_input_poll", 8)
            if k2 == 91
              if k3 == 68
                cursor = scrub_prv(cursor, spans.size())
                moved = true
              elsif k3 == 67
                cursor = scrub_nxt(cursor, spans.size())
                moved = true
              elsif k3 == 65
                step = 1
              elsif k3 == 66
                step = -1
              else
                break
            else
              break
          elsif ev == 113 || ev == 13 || ev == 10 || ev == 3 || ev == 4
            break
          elsif ev == 43 || ev == 61
            step = 1
          elsif ev == 45
            step = -1
          elsif ev == 93
            step = 1
            mag = 1
          elsif ev == 91
            step = -1
            mag = 1
          elsif ev == 125
            step = 1
            mag = 2
          elsif ev == 123
            step = -1
            mag = 2
          elsif ev == 104
            cursor = scrub_prv(cursor, spans.size())
            moved = true
          elsif ev == 108
            cursor = scrub_nxt(cursor, spans.size())
            moved = true
        else
          dkind = ev >> 16
          didx = (ev >> 8) & 255
          lo = ev & 255
          if dkind == 1
            delta = lo
            if lo >= 128
              delta = lo - 256
            field = page * 4 + didx
            if field < spans.size()
              cursor = field
              step = delta
          elsif dkind == 2
            if lo == 1
              pc = (spans.size() + 3) / 4
              page = (page + 1) % pc
              base = page * 4
              if base >= spans.size()
                base = spans.size() - 1
              cursor = base
              moved = true
        if step != 0
          sp = spans[cursor]
          src = scrub_apply(src, sp, step, mag)
          spans = scrub_field_spans(src)
          if cursor >= spans.size()
            cursor = spans.size() - 1
          redraw_scrub(src, spans, cursor)
        elsif moved
          redraw_scrub(src, spans, cursor)
    ensure
      ccall("w_print", "\e\[?25h")
      if dev != nil
        ccall("w_hid_streamdeck_close", dev)
    ccall("w_print", "\r\n")
    @last_scrub_src = src
    # Re-arm the jumpback so a SECOND blank Enter re-scrubs this same frame in
    # place (jump back over the frame + the trailing prompt line) instead of
    # reprinting it below. Cleared by any non-blank command.
    @scrub_jumpback = @scrub_lines + 1

  # ── Paste mode ─────────────────────────────────────────────────
  # Read verbatim lines until `/end`, then evaluate them as one block.
  # Useful for pasting a class/method that spans many lines.

  -> handle_paste
    << DIM + "  paste mode — end with /end" + RESET
    pasted = ""
    while true
      ccall("w_print", continuation_prompt())
      l = ccall("w_read_line_stdin")
      if l == nil
        break
      if l.strip() == "/end"
        break
      pasted = pasted + l + "\n"
    if pasted.strip().size() > 0
      evaluate_and_display(pasted.strip())

  # ── Code completeness detection ────────────────────────────────

  -> code_complete?(buffer)
    stripped = buffer.strip()
    if stripped.size() == 0
      return true

    lines = buffer.split("\n")

    # Two consecutive blank lines → force submit
    if lines.size() >= 3
      l1 = lines[lines.size() - 1].strip()
      l2 = lines[lines.size() - 2].strip()
      l3 = lines[lines.size() - 3].strip()
      if l1.size() == 0 && l2.size() == 0 && l3.size() == 0
        return true

    # Unmatched brackets/parens
    opens = 0
    closes = 0
    i = 0
    while i < stripped.size()
      ch = stripped.slice(i, 1)  # slice is (start, LENGTH): one char, not slice(i, i+1)
      if ch in ("(" "\[" "{")
        opens = opens + 1
      if ch in (")" "]" "}")
        closes = closes + 1
      i = i + 1
    if opens > closes
      return false

    # Find last non-blank line
    last_nonblank = nil
    j = lines.size() - 1
    while j >= 0
      if lines[j].strip().size() > 0
        last_nonblank = lines[j]
        break
      j = j - 1

    if last_nonblank == nil
      return true

    last_stripped = last_nonblank.strip()

    # Block-opening keyword → need indented body
    if starts_with_block_opener?(last_stripped)
      return false

    # -> (function def) or + ClassName (class def)
    if last_stripped.starts_with?("->")
      return false
    if last_stripped.starts_with?("+ ") && last_stripped.size() > 2
      return false

    # Ends with -> (block passed to method)
    if last_stripped.ends_with?("->")
      return false

    # Last meaningful line is indented → still inside a block body
    if last_nonblank.starts_with?("  ") || last_nonblank.starts_with?("\t")
      return false

    true

  -> starts_with_block_opener?(line)
    i = 0
    while i < BLOCK_OPENERS.size()
      kw = BLOCK_OPENERS[i]
      if line.starts_with?(kw)
        # Make sure it's a word boundary (keyword is whole line or followed by space/paren)
        if line.size() == kw.size()
          return true
        next_ch = line.slice(kw.size(), 1)  # one char (slice is start,LENGTH)
        if next_ch in (" " "(")
          return true
      i = i + 1
    false

  # ── Auto-indentation ───────────────────────────────────────────

  -> calc_indent(prev_line)
    if prev_line == nil
      return 0

    # Count leading spaces on previous line
    prev_indent = 0
    k = 0
    while k < prev_line.size()
      if prev_line.slice(k, 1) == " "  # one char (slice is start,LENGTH)
        prev_indent = prev_indent + 1
      else
        break
      k = k + 1

    prev_stripped = prev_line.strip()
    if opens_block?(prev_stripped)
      return prev_indent + 2

    prev_indent

  -> opens_block?(stripped)
    if starts_with_block_opener?(stripped)
      return true
    if stripped.starts_with?("->")
      return true
    if stripped.starts_with?("+ ") && stripped.size() > 2
      return true
    if stripped.ends_with?("->")
      return true
    false

  # ── Evaluation ─────────────────────────────────────────────────

  -> evaluate_and_display(input)
    if @hot_mode == true
      hot_eval_and_display(input)
      return

    result = nil
    error = nil

    begin
      single = input.split("\n").size() == 1 && !starts_with_block_opener?(input.strip())
      if @jit_mode == true && single
        jr = jit_eval(input.strip())
        if jr != nil
          result = jr[0]
        else
          result = @interpreter.run("_ = (" + input + ")")
      elsif single
        result = @interpreter.run("_ = (" + input + ")")
      else
        result = @interpreter.run(input)
    rescue e
      error = e

    if error
      # Same formatters as the compiler driver (#16): structured compile errors
      # get the header/location treatment, plain runtime strings the clean
      # `error:` line — and both honor NO_COLOR/CLICOLOR/isatty.
      if type(error) == "Hash" && error[:rt] == :compile_error
        << format_compile_error(error)
      else
        << format_runtime_error(error.to_s())
    else
      formatted = format_value(result)
      << DIM + "  =>" + RESET + " " + formatted

  # ── JIT eval (--jit) ───────────────────────────────────────────
  # Compile one expression to a native dylib and call it, instead of
  # tree-walking. Returns [result] on success, nil on any failure (caller
  # falls back to the interpreter). v0: numeric results only, and session
  # state does not persist across snippets (each line is its own unit).

  -> jit_eval(expr)
    # Unique dylib path per line: dlopen caches by pathname, so reusing one
    # path returns the first line's stale image even after dlclose.
    @jit_counter = @jit_counter + 1
    base = "/tmp/wit_jit_" + @jit_counter.to_s()
    write_file(base + ".w", "-> jit_line\n  " + expr + "\n")
    ll = emit_ir(base + ".w", false, false, "raw", nil, false, nil, true)
    if ll == nil
      return nil
    compile_and_call(base, ll)

  # Compile emitted IR to native and invoke jit_line. Prefers the in-memory
  # Mach-O loader (w_jit_load_object: no dlopen, so no ~120ms dyld closure floor
  # on macOS — ~17ms/line vs ~170ms); falls back to the dlopen dylib path on any
  # unsupported relocation, link failure, or non-macOS platform. The fallback is
  # what makes the fast path safe: it can only ever be faster or transparently
  # equivalent. Returns [result] on success, nil on failure.
  -> compile_and_call(base, ll)
    obj = base + ".o"
    system("clang -O2 -c " + ll + " -o " + obj + " 2>/dev/null")
    f = ccall("w_jit_load_object", obj, "jit_line")
    if f != nil
      return [ccall("w_dlcall", f)]
    # Fallback: thin dylib (no runtime.a — w_int/etc. resolve from the
    # -export_dynamic host at dlopen) + the meta-table fn scan.
    dylib = base + ".dylib"
    system("clang -O2 " + ll + " -dynamiclib -undefined dynamic_lookup -o " + dylib + " 2>/dev/null")
    h = ccall("w_dlopen", dylib)
    if h == nil
      return nil
    dlf = ccall("w_dlfind_fn", h, "jit_line")
    if dlf == nil
      return nil
    [ccall("w_dlcall", dlf)]

  # ── Hot-reload eval (--hot) ────────────────────────────────────
  # Erlang-flavored: definitions accumulate across the session (keyed by name,
  # so redefining one swaps it), and an expression compiles the whole live
  # program — all current definitions plus the expression — to native and runs
  # it. Unlike --jit, state (the set of definitions) persists, and a redefined
  # function is picked up by the next call (hot reload).

  # Extract the clean leading identifier after `-> `/`+ ` (only [A-Za-z0-9_],
  # stopping at the first other char). Excluding stray chars keeps the name
  # deterministic so redefining a fn truly replaces it — a duplicate definition
  # reaching the compiler HANGS it.
  -> hot_def_name(s)
    rest = s.slice(2, s.size()).strip()
    name = ""
    i = 0
    while i < rest.size()
      c = rest.slice(i, 1)  # one char (slice is start,LENGTH, not start,end)
      if "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_".include?(c)
        name = name + c
      else
        return name
      i = i + 1
    name

  # Is `s` a simple assignment `name = expr` (bare-identifier LHS, single `=`)?
  # Splitting on " = " excludes ==/<=/>=/!= (no space-equals-space match) and
  # the LHS check excludes field/index/call targets. Returns the name or nil.
  -> hot_assign_name(s)
    parts = s.split(" = ")
    if parts.size() < 2
      return nil
    lhs = parts[0].strip()
    if lhs.size() == 0
      return nil
    if lhs.include?(" ") || lhs.include?(".") || lhs.include?("\[") || lhs.include?("(")
      return nil
    lhs

  -> hot_eval_and_display(input)
    s = input.strip()
    if s.starts_with?("->") || (s.starts_with?("+ ") && s.size() > 2)
      name = hot_def_name(s)
      @hot_defs[name] = input
      << DIM + "  defined " + RESET + CYAN + name + RESET
      return

    aname = hot_assign_name(s)
    if aname != nil
      @hot_stmts.push(input)
      << DIM + "  set " + RESET + CYAN + aname + RESET
      return

    begin
      r = hot_run(s)
      if r == nil
        << BRIGHT_RED + "  hot: compile failed" + RESET
      else
        << DIM + "  =>" + RESET + " " + format_value(r[0])
    rescue e
      << BRIGHT_RED + "  error: " + e.to_s() + RESET

  -> hot_run(expr)
    @jit_counter = @jit_counter + 1
    base = "/tmp/wit_hot_" + @jit_counter.to_s()
    # Definitions stay top-level (fns need no startup init). Assignments are
    # replayed as LOCAL statements inside jit_line — a snippet dylib's top-level
    # code lives in main(), which we never call, so it must run in the fn we do.
    # Dedup defs by their actual fn name (last wins) before emitting: a
    # duplicate definition in the generated source HANGS the compiler, and
    # accumulated/garbled keys can collide, so re-key here as a hard safety net.
    seen = {}
    order = []
    keys = @hot_defs.keys()
    i = 0
    while i < keys.size()
      v = @hot_defs[keys[i]]
      nm = hot_def_name(v.strip())
      if seen[nm] == nil
        order.push(nm)
      seen[nm] = v
      i = i + 1
    src = ""
    o = 0
    while o < order.size()
      src = src + seen[order[o]] + "\n\n"
      o = o + 1
    src = src + "-> jit_line\n"
    j = 0
    while j < @hot_stmts.size()
      src = src + "  " + @hot_stmts[j].strip() + "\n"
      j = j + 1
    src = src + "  " + expr + "\n"
    write_file(base + ".w", src)
    ll = emit_ir(base + ".w", false, false, "raw", nil, false, nil, true)
    if ll == nil
      return nil
    compile_and_call(base, ll)

  # ── Value formatting ───────────────────────────────────────────

  -> format_value(value, depth = 0)
    if value == nil
      return DIM + "nil" + RESET
    if value == true
      return MAGENTA + "true" + RESET
    if value == false
      return MAGENTA + "false" + RESET
    t = type(value)
    if t == "Integer"
      return MAGENTA + value.to_s() + RESET
    if t == "Float"
      return CYAN + value.to_s() + RESET
    if t == "Decimal"
      return CYAN + value.to_s() + RESET
    if t == "Currency" || t == "Quantity"
      return GREEN + value.to_s() + RESET
    if t == "String"
      return WHITE + "\"" + value + "\"" + RESET
    if t == "Symbol"
      return YELLOW + ":" + value.to_s() + RESET
    if t == "Range"
      return CYAN + value.to_s() + RESET
    if t == "Class"
      return MAGENTA + value.to_s() + RESET
    if t == "Array"
      return format_array(value, depth)
    if t == "Hash"
      return format_hash(value, depth)
    WHITE + value.to_s() + RESET

  -> format_array(arr, depth)
    if arr.size() == 0
      return DIM + "\[\]" + RESET
    if depth >= 2 || arr.size() > 20
      return DIM + "\[" + RESET + arr.size().to_s() + " items" + DIM + "]" + RESET

    parts = []
    i = 0
    while i < arr.size()
      parts.push(format_value(arr[i], depth + 1))
      i = i + 1
    DIM + "\[" + RESET + parts.join(DIM + ", " + RESET) + DIM + "]" + RESET

  -> format_hash(hash, depth)
    # The interpreter represents some runtime values as tagged hashes
    # ({rt: :range, from:, to:, exclusive:}); render those, not their guts.
    if hash[:rt] == :range
      op = ".."
      if hash[:exclusive] == true
        op = "..."
      return CYAN + hash[:from].to_s() + op + hash[:to].to_s() + RESET
    if hash[:rt] == :class
      # Match the compiled path's class rendering (bare name, magenta) so
      # 1.class displays identically across --wit / --jit / --hot.
      return MAGENTA + hash[:name].to_s() + RESET
    if hash[:rt] == :method
      return DIM + "method" + RESET

    if hash.size() == 0
      return DIM + "{}" + RESET
    if depth >= 2 || hash.size() > 8
      return DIM + "{" + RESET + hash.size().to_s() + " entries" + DIM + "}" + RESET

    keys = hash.keys()
    vals = hash.values()
    parts = []
    i = 0
    while i < keys.size()
      pair = CYAN + keys[i].to_s() + RESET + DIM + ": " + RESET + format_value(vals[i], depth + 1)
      parts.push(pair)
      i = i + 1
    DIM + "{" + RESET + parts.join(DIM + ", " + RESET) + DIM + "}" + RESET

  # ── show-method Class#method ───────────────────────────────────
  # Introspect a stdlib/user method: resolve it through the interpreter (which
  # autoloads the defining core file), then print its .w source by reading the
  # file and capturing the def + its dedented body. Works in --wit/--jit/--hot
  # (the interpreter instance is present in every mode for introspection).
  -> show_method(arg)
    parts = arg.split("#")
    if parts.size() < 2
      << BRIGHT_RED + "  usage: show-method Class#method" + RESET + DIM + "  (e.g. show-method String#split)" + RESET
      return
    cls = parts[0].strip()
    meth = parts[1].strip()
    if @interpreter == nil
      << BRIGHT_RED + "  show-method needs the interpreter" + RESET
      return
    file = @interpreter.class_file(cls)
    if file == nil
      << BRIGHT_RED + "  unknown class " + RESET + CYAN + cls + RESET
      return
    src = read_file(file)
    if src == nil
      << BRIGHT_RED + "  cannot read " + file + RESET
      return
    body = capture_method_source(src, meth)
    if body == nil
      # Not in the .w file at all — likely a pure runtime intrinsic.
      if !show_runtime_impl(cls, meth)
        << DIM + "  " + RESET + CYAN + cls + "#" + meth + RESET + DIM + " not found in " + file + " — inherited, or a different name" + RESET
      return
    << DIM + "  # " + cls + "#" + meth + "  ·  " + file + RESET
    << highlight(body)
    if !body.include?("\n")
      # Bodyless declaration → the real implementation is a runtime C intrinsic.
      if !show_runtime_impl(cls, meth)
        << DIM + "  (no .w body — runtime intrinsic; C handler not located by name)" + RESET

  # Print a method's runtime C implementation from runtime.c, if we can locate
  # the IC handler `w_ic_<prefix>_<meth>`. Returns true if printed. Most stdlib
  # methods are intrinsics dispatched through per-type inline-cache tables; the
  # handler is named after the method (a few are aliased, e.g. size→length).
  -> show_runtime_impl(cls, meth)
    c = runtime_method_c_source(cls, meth)
    if c == nil
      return false
    << DIM + "  ── runtime intrinsic (runtime/runtime.c) ──" + RESET
    << highlight(c)
    true

  -> ic_prefix(cls)
    if cls == "Integer"
      return "int"
    if cls == "StringBuffer"
      return "strbuf"
    cls.downcase()

  -> runtime_method_c_source(cls, meth)
    src = read_file("runtime/runtime.c")
    if src == nil
      return nil
    prefix = ic_prefix(cls)
    fname = "w_ic_" + prefix + "_" + meth
    # Fast path: the handler is named after the method (split, upcase, map, …).
    if src.include?("WValue " + fname + "(")
      return extract_c_function(src, fname)
    # Alias path: the handler name differs from the method (e.g. size→length).
    # Resolve via the IC table: `[N].name = WN_<meth>` → the Nth table entry.
    aliased = resolve_ic_fn(src, prefix, meth)
    if aliased != nil
      return extract_c_function(src, aliased)
    nil

  # Map an intrinsic method to its C handler when the names differ, via the IC
  # table: find the slot index from `w_ic_<prefix>_table[N].name = WN_<meth>`,
  # then read that slot's function from the `{0, w_ic_<prefix>_<fn>}` array.
  -> resolve_ic_fn(src, prefix, meth)
    lines = src.split("\n")
    marker = "w_ic_" + prefix + "_table["
    tail = "].name = WN_" + meth + ";"
    idx = -1
    i = 0
    while i < lines.size()
      l = lines[i].strip()
      if l.starts_with?(marker) && l.include?(tail)
        mid = l.slice(marker.size(), l.size())
        nstr = ""
        k = 0
        while k < mid.size() && "0123456789".include?(mid.slice(k, 1))
          nstr = nstr + mid.slice(k, 1)
          k = k + 1
        if nstr.size() > 0
          idx = nstr.to_i()
        break
      i = i + 1
    if idx < 0
      return nil
    arr_hdr = "WICEntry w_ic_" + prefix + "_table[] = {"
    fns = []
    in_arr = false
    i = 0
    while i < lines.size()
      l = lines[i].strip()
      if !in_arr
        if l.include?(arr_hdr)
          in_arr = true
      elsif l.starts_with?("};")
        break
      elsif l.starts_with?("{0, ")
        rest = l.slice(4, l.size())
        nm = ""
        k = 0
        while k < rest.size() && rest.slice(k, 1) != "}"
          nm = nm + rest.slice(k, 1)
          k = k + 1
        fns.push(nm.strip())
      i = i + 1
    if idx >= fns.size()
      return nil
    fns[idx]

  # Capture a C function definition by name: from its `… WValue <fn>(… {` line
  # to the matching closing brace (brace-counted).
  -> extract_c_function(src, fname)
    lines = src.split("\n")
    i = 0
    while i < lines.size()
      line = lines[i]
      if line.include?("WValue " + fname + "(")
        out = line
        depth = brace_delta(line)
        j = i + 1
        while j < lines.size() && depth > 0
          out = out + "\n" + lines[j]
          depth = depth + brace_delta(lines[j])
          j = j + 1
        return out
      i = i + 1
    nil

  -> brace_delta(line)
    d = 0
    k = 0
    while k < line.size()
      c = line.slice(k, 1)
      if c == "{"
        d = d + 1
      elsif c == "}"
        d = d - 1
      k = k + 1
    d

  # Find a `-> meth` def line in `src` and return it plus its indented body,
  # terminated at the first non-blank line that dedents to the def's level.
  -> capture_method_source(src, meth)
    lines = src.split("\n")
    i = 0
    while i < lines.size()
      line = lines[i]
      if method_def_line?(line.strip(), meth)
        indent = leading_spaces(line)
        out = line
        pending = ""        # buffer blank lines; only keep them if more body follows
        j = i + 1
        while j < lines.size()
          l = lines[j]
          if l.strip().size() == 0
            pending = pending + "\n" + l
          elsif leading_spaces(l) > indent
            out = out + pending + "\n" + l
            pending = ""
          else
            break           # dedent → end of method (drop trailing blanks)
          j = j + 1
        return out
      i = i + 1
    nil

  # True if `stripped` is `-> meth` followed by a name boundary ((, space, /, or
  # end) — so "split" matches `-> split(...)`/`-> split/1` but not `-> splitter`.
  -> method_def_line?(stripped, meth)
    if !stripped.starts_with?("-> ")
      return false
    rest = stripped.slice(3, stripped.size())
    if !rest.starts_with?(meth)
      return false
    after = rest.slice(meth.size(), 1)
    after == "" || after == "(" || after == " " || after == "/"

  -> leading_spaces(line)
    n = 0
    while n < line.size() && line.slice(n, 1) == " "
      n = n + 1
    n

  # ── Syntax highlighting (vim-tungsten palette) ─────────────────
  # Tokenize source and wrap each token in 256-color ANSI. Handles both .w
  # (# comments) and C (// and /* */ comments) so show-method can colorize the
  # .w declaration and the runtime intrinsic alike.
  -> highlight(src)
    out = ""
    lines = src.split("\n")
    in_block = false
    li = 0
    while li < lines.size()
      res = highlight_line(lines[li], in_block)
      out = out + res[0]
      in_block = res[1]
      if li < lines.size() - 1
        out = out + "\n"
      li = li + 1
    out

  # Highlight one line given whether we start inside a /* */ block; returns
  # [colored_line, still_in_block].
  -> highlight_line(line, in_block)
    out = ""
    i = 0
    n = line.size()
    while i < n
      if in_block
        rest = line.slice(i, n - i)
        close = str_index(rest, "*/")
        if close < 0
          return [out + HL_COMMENT + rest + RESET, true]
        out = out + HL_COMMENT + rest.slice(0, close + 2) + RESET
        i = i + close + 2
        in_block = false
      else
        c = line.slice(i, 1)
        c2 = ""
        if i + 1 < n
          c2 = line.slice(i + 1, 1)
        if c == "/" && c2 == "*"
          in_block = true              # next iteration consumes the block from i
        elsif (c == "/" && c2 == "/") || c == "#"
          return [out + HL_COMMENT + line.slice(i, n - i) + RESET, false]
        elsif c == "\""
          j = i + 1
          while j < n && line.slice(j, 1) != "\""
            if line.slice(j, 1) == "\\"
              j = j + 1
            j = j + 1
          if j < n
            j = j + 1                  # include closing quote
          out = out + HL_STRING + line.slice(i, j - i) + RESET
          i = j
        elsif c >= "0" && c <= "9"
          j = i
          while j < n && num_char?(line.slice(j, 1))
            j = j + 1
          out = out + HL_NUMBER + line.slice(i, j - i) + RESET
          i = j
        elsif word_start?(c)
          j = i + 1
          while j < n && word_char?(line.slice(j, 1))
            j = j + 1
          out = out + colorize_word(line.slice(i, j - i))
          i = j
        elsif op_char?(c)
          j = i
          while j < n && op_char?(line.slice(j, 1))
            j = j + 1
          out = out + HL_KEYWORD + line.slice(i, j - i) + RESET   # Operator → 96
          i = j
        else
          out = out + c
          i = i + 1
    [out, in_block]

  -> op_char?(c)
    c == "+" || c == "-" || c == "*" || c == "/" || c == "%" || c == "=" || c == "<" || c == ">" || c == "!" || c == "&" || c == "|" || c == "^" || c == "~"

  -> num_char?(c)
    (c >= "0" && c <= "9") || (c >= "a" && c <= "f") || (c >= "A" && c <= "F") || c == "." || c == "x" || c == "_"

  -> word_start?(c)
    (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_" || c == "@"

  -> word_char?(c)
    (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9") || c == "_"

  # Color a single word token per the vim-tungsten groups.
  -> colorize_word(word)
    if HL_KEYWORDS.include?(word)
      return HL_KEYWORD + word + RESET
    if word == "true" || word == "false"
      return HL_BOOL + word + RESET
    if word == "nil" || word == "self" || word == "NULL"
      return HL_CONST + word + RESET
    if word.starts_with?("@")
      return HL_TYPE + word + RESET            # @ivars → Identifier (60)
    fc = word.slice(0, 1)
    if all_caps?(word) && word.size() > 1
      return HL_CONST + word + RESET           # CONSTANTS
    if fc >= "A" && fc <= "Z"
      return HL_TYPE + word + RESET            # ClassName / WValue
    word                                       # default identifier — no color

  -> all_caps?(word)
    k = 0
    while k < word.size()
      c = word.slice(k, 1)
      if !((c >= "A" && c <= "Z") || (c >= "0" && c <= "9") || c == "_")
        return false
      k = k + 1
    true

  # First index of `sub` in `s`, or -1.
  -> str_index(s, sub)
    if sub.size() == 0
      return 0
    limit = s.size() - sub.size()
    i = 0
    while i <= limit
      if s.slice(i, sub.size()) == sub
        return i
      i = i + 1
    -1
