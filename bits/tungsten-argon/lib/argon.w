# Argon — manpage-driven option parser for Tungsten
#
# Feed it a manpage-formatted string (or heredoc), get a complete CLI parser.
# Options are extracted from the OPTIONS section. Short flags (-v), long flags
# (--verbose), negatable flags (--\[no-]color), and value options (-o FILE) are
# all recognized automatically from the manpage text.
#
# Parsing follows common getopt conventions:
#   * Short-flag bundling: "-abc" == "-a -b -c". A value-taking letter in a
#     bundle consumes the rest of the bundle as its value ("-ovalue" == "-o
#     value"); if it is the last letter, the next argv token is the value.
#   * Negative numbers: "-5" / "--offset -5" are values/positionals, not flags,
#     unless "5" is itself a defined short flag. Array options accept negative
#     numbers as elements and stop only at genuine flags.
#
# Usage:
#
#   cli = Argon.new(MANPAGE)
#   opts = cli.parse(ARGV)
#
#   opts.flag?(:verbose)      # => true/false
#   opts.occurrences(:verbose) # => 3 for "-vvv" (repeated flags accumulate)
#   opts.get(:out)            # => "file.wc" or nil
#   opts.get(:out, "a.out")   # => "file.wc" or "a.out"
#
# Options the manpage annotates "(env: VAR)" fall back to $VAR when absent from
# argv — resolution is command line > environment > default:
#
#   -t, --token TOKEN   API token. (env: API_TOKEN)
#   opts.get(:token)          # => argv value, else $API_TOKEN, else nil
#   opts.args                 # => \["file.w", "arg1"]
#   opts.command              # => "compile" (first positional before --)
#
# A compact usage synopsis is generated from the option and operand definitions
# (always in sync with what the parser accepts), ready to prefix error output:
#
#   cli.usage()   # => "usage: probe \[-C] \[-d] \[-o FILE] ... \[-p \[MODE]] file"
#   opts.usage()  # same, reachable from the parse result
#
# Operands named in the SYNOPSIS are reachable by name and arrive typed. Given
# "SYNOPSIS: build \[options] TARGET \[OUTPUT] \[FILE ...]":
#
#   opts.positional(:target)  # => "app"            (required operand)
#   opts.positional(:output)  # => "out.bin" or nil (\[OPTIONAL] operand)
#   opts.positional(:file)    # => \["a", "b"] or [] (NAME... variadic operand)
#   opts.missing_arguments    # => \["TARGET"]       (opt-in; not part of valid?)
#

+ Argon
  ro :name
  ro :manpage
  ro :option_defs
  ro :positional_defs

  # option_defs: array of { short:, long:, key:, takes_value:, negatable:, description: }
  # positional_defs: array of { name:, key:, required:, variadic: } from the SYNOPSIS

  -> new(@manpage)
    @name = extract_name(manpage)
    @option_defs = parse_manpage(manpage)
    @positional_defs = parse_synopsis_positionals(manpage)

  # Parse argv against the extracted option definitions.
  # Returns an Argon:Result.
  -> parse(argv)
    flags = {}
    counts = {}
    options = {}
    positional = []
    rest = []
    saw_dashdash = false
    i = 0

    while i < argv.size
      arg = argv[i]

      if saw_dashdash
        rest.push(arg)
        i = i + 1
        next

      if arg == "--"
        saw_dashdash = true
        i = i + 1
        next

      if arg.starts_with?("--no-")
        raw = arg.slice(2, arg.size)
        defn = find_long(raw)
        if !defn || defn[:negatable]
          key = replace_all(arg.slice(5, arg.size), "-", "_")
          flags[key] = false
          i = i + 1
          next

      if arg.starts_with?("--")
        raw = arg.slice(2, arg.size)

        # --key=value form
        eq = raw.index("=")
        if eq
          key = replace_all(raw.slice(0, eq), "-", "_")
          val = raw.slice(eq + 1, raw.size)
          store_option(options, key, cast_option(key, val))
          i = i + 1
          next

        key = replace_all(raw, "-", "_")
        defn = find_long(raw)

        if defn && defn[:takes_value]
          if i + 1 < argv.size()
            # Array options: consume all following non-flag args
            if defn[:array]
              i = i + 1
              vals = []
              while i < argv.size() && value_like_token?(argv[i])
                vals.push(cast(argv[i]))
                i = i + 1
              store_option(options, key, vals)
            elsif defn[:optional_value]
              next_arg = argv[i + 1]
              if value_like_token?(next_arg)
                store_option(options, key, cast_option(key, next_arg))
                i = i + 2
              else
                options[key] = true
                i = i + 1
            else
              store_option(options, key, cast_option(key, argv[i + 1]))
              i = i + 2
          else
            options[key] = true
            i = i + 1
        else
          mark_flag(flags, counts, key)
          i = i + 1
        next

      # A "-<digit>..." token is a negative number, not a short flag —
      # unless its leading digit is a defined short flag (getopt treats
      # "-5" as an option only when "5" is documented). It becomes a
      # positional here; an option expecting a value picks it up earlier
      # via value_like_token?.
      if negative_number_token?(arg)
        positional.push(arg)
        i = i + 1
        next

      # Short-flag bundle: "-abc" == "-a -b -c" (getopt bundling). Letters
      # are processed left to right. A value-taking letter consumes the REST
      # of the bundle as its value ("-ovalue" == "-o value", "-o5" == "-o 5");
      # if nothing follows it in the bundle, the next argv token is the value.
      # An unrecognized letter is recorded as a set flag — the same lenient
      # path as an unknown single short flag. (Negative numbers are handled
      # above, so a leading digit never reaches here.)
      if arg.starts_with?("-") && !arg.starts_with?("--") && arg.size() > 2
        chars = arg.slice(1, arg.size())
        ci = 0
        i = i + 1
        while ci < chars.size()
          letter = chars.slice(ci, 1)
          defn = find_short(letter)
          if defn && defn[:takes_value]
            key = defn[:key]
            remainder = chars.slice(ci + 1, chars.size())
            if remainder.size() > 0
              if defn[:array]
                store_option(options, key, [cast(remainder)])
              else
                store_option(options, key, cast_option(key, remainder))
              ci = chars.size()
            else
              if defn[:array]
                vals = []
                while i < argv.size() && value_like_token?(argv[i])
                  vals.push(cast(argv[i]))
                  i = i + 1
                store_option(options, key, vals)
              elsif defn[:optional_value]
                if i < argv.size() && value_like_token?(argv[i])
                  store_option(options, key, cast_option(key, argv[i]))
                  i = i + 1
                else
                  options[key] = true
              else
                if i < argv.size()
                  store_option(options, key, cast_option(key, argv[i]))
                  i = i + 1
                else
                  options[key] = true
              ci = chars.size()
          elsif defn
            mark_flag(flags, counts, defn[:key])
            ci = ci + 1
          else
            mark_flag(flags, counts, letter)
            ci = ci + 1
        next

      if arg.starts_with?("-") && arg.size() == 2
        short = arg.slice(1, 2)
        defn = find_short(short)

        if defn
          key = defn[:key]
          if defn[:takes_value]
            if i + 1 < argv.size()
              if defn[:array]
                i = i + 1
                vals = []
                while i < argv.size() && value_like_token?(argv[i])
                  vals.push(cast(argv[i]))
                  i = i + 1
                store_option(options, key, vals)
              elsif defn[:optional_value]
                next_arg = argv[i + 1]
                if value_like_token?(next_arg)
                  store_option(options, key, cast_option(key, next_arg))
                  i = i + 2
                else
                  options[key] = true
                  i = i + 1
              else
                store_option(options, key, cast_option(key, argv[i + 1]))
                i = i + 2
            else
              options[key] = true
              i = i + 1
          else
            mark_flag(flags, counts, key)
            i = i + 1
        else
          # Unknown short flag — treat as flag using the letter as key
          mark_flag(flags, counts, short)
          i = i + 1
        next

      positional.push(arg)
      i = i + 1

    Argon:Result.new(flags, counts, options, positional, rest, self)

  # Set a boolean flag and bump its occurrence count. Repeated flags accumulate
  # (the "-vvv" verbosity idiom); `flag?` reads the boolean, `occurrences` the
  # tally. Negations ("--no-x") set the flag false directly and are deliberately
  # not counted here.
  -> mark_flag(flags, counts, key)
    flags[key] = true
    existing = counts[key]
    if existing
      counts[key] = existing + 1
    else
      counts[key] = 1

  # Store an option value, appending to arrays for repeated array options
  -> store_option(options, key, val)
    defn = find_by_key(key)
    if defn && defn[:array]
      existing = options[key]
      if existing
        if val.is_a?(Array)
          val.each -> (v) existing.push(v)
        else
          existing.push(val)
      else
        if val.is_a?(Array)
          options[key] = val
        else
          options[key] = [val]
    else
      options[key] = val

  # Print formatted help from the manpage
  -> help
    @manpage

  # A compact, always-in-sync usage synopsis generated from the parsed option
  # and operand definitions (the argparse/getopt-style "usage:" line). Options
  # appear in manpage order, each wrapped in brackets unless "(required)":
  # value options show their metavar ("\[-o FILE]"), array options an ellipsis
  # ("\[--files FILE...]"), optional-value options a nested bracket
  # ("\[-p \[MODE]]"). Named operands from the SYNOPSIS follow, bracketed when
  # optional and suffixed "..." when variadic. Because it is derived from the
  # same defs `parse` uses, it can never drift from what the parser accepts —
  # ideal for prefixing error output.
  -> usage
    out = "usage: " + @name
    i = 0
    while i < @option_defs.size()
      out = out + " " + option_usage(@option_defs[i])
      i = i + 1
    p = 0
    while p < @positional_defs.size()
      out = out + " " + positional_usage(@positional_defs[p])
      p = p + 1
    out

  # Render one option as it appears in the usage synopsis (see `usage`).
  -> option_usage(d)
    label = usage_flag_label(d)
    inner = label
    if d[:takes_value]
      vn = d[:value_name]
      if vn == nil
        vn = "VALUE"
      if d[:array]
        inner = label + " " + vn + "..."
      elsif d[:optional_value]
        inner = label + " \[" + vn + "]"
      else
        inner = label + " " + vn
    if d[:required]
      return inner
    "\[" + inner + "]"

  # The short form ("-o") when the option has one, else the long form ("--out").
  -> usage_flag_label(d)
    if d[:short] != nil
      return "-" + d[:short]
    "--" + d[:long]

  # Render one named operand for the usage synopsis: bare when required,
  # bracketed when optional, suffixed "..." when variadic.
  -> positional_usage(d)
    s = d[:name]
    if d[:variadic]
      s = s + "..."
    if d[:required]
      return s
    "\[" + s + "]"

  # ---- Private ----

  # Replace every occurrence of `from` in `s` with `to`.
  # (Pure Tungsten so Argon also runs under the interpreter, which has no gsub.)
  -> replace_all(s, from, to)
    out = ""
    rest = s
    idx = rest.index(from)
    while idx
      out = out + rest.slice(0, idx) + to
      rest = rest.slice(idx + from.size(), rest.size())
      idx = rest.index(from)
    out + rest

  -> section_heading(line)
    stripped = line.strip()
    if stripped.size() == 0
      return nil

    if stripped.starts_with?("#")
      while stripped.starts_with?("#")
        stripped = stripped.slice(1, stripped.size()).strip()
      if stripped.size() > 0
        return stripped
      return nil

    if line == stripped && stripped == stripped.upcase() && has_heading_text?(stripped)
      return stripped

    nil

  -> has_heading_text?(text)
    i = 0
    while i < text.size()
      ch = text[i]
      if (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") || (ch >= "0" && ch <= "9")
        return true
      i = i + 1
    false

  -> section_ref_name(text)
    s = text.strip().downcase()
    out = ""
    prev_dash = false
    i = 0

    while i < s.size()
      ch = s[i]
      if (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9")
        out = out + ch
        prev_dash = false
      elsif ch == " " || ch == "-" || ch == "_"
        if out.size() > 0 && !prev_dash
          out = out + "-"
          prev_dash = true
      i = i + 1

    if out.ends_with?("-")
      out = out.slice(0, out.size() - 1)

    out

  -> option_section_ref?(ref)
    ref == "options" || ref == "flags" || ref.ends_with?("-options") || ref.ends_with?("-flags")

  -> add_bracket_refs(line, refs)
    parts = line.split(" ")
    ref = ""
    in_ref = false
    i = 0

    while i < parts.size()
      part = parts[i]
      if in_ref
        if ref.size() > 0
          ref = ref + " "
        ref = ref + part
      elsif part.starts_with?("\[")
        ref = part.slice(1, part.size())
        in_ref = true

      if in_ref && ref.ends_with?("]")
        ref = ref.slice(0, ref.size() - 1)
        key = section_ref_name(ref)
        if option_section_ref?(key)
          refs[key] = true
        ref = ""
        in_ref = false
      i = i + 1

    refs

  -> referenced_sections(text)
    refs = {}
    lines = text.split("\n")
    in_synopsis = false
    i = 0

    while i < lines.size()
      line = lines[i]
      heading = section_heading(line)

      if heading && heading.upcase() == "SYNOPSIS"
        in_synopsis = true
        i = i + 1
        next

      if in_synopsis && heading
        break

      if in_synopsis
        add_bracket_refs(line, refs)
      i = i + 1

    if refs.size() == 0
      refs["options"] = true

    refs

  # Parse the operands named in the SYNOPSIS into ordered positional defs. Uses
  # the first non-empty usage line under the SYNOPSIS heading (the canonical
  # form). Returns [] when there is no SYNOPSIS.
  -> parse_synopsis_positionals(text)
    lines = text.split("\n")
    in_synopsis = false
    usage = nil
    i = 0

    while i < lines.size()
      line = lines[i]
      heading = section_heading(line)

      if heading && heading.upcase() == "SYNOPSIS"
        in_synopsis = true
        i = i + 1
        next

      if in_synopsis && heading
        break

      if in_synopsis && usage == nil
        stripped = line.strip()
        if stripped.size() > 0
          usage = stripped
      i = i + 1

    if usage == nil
      return []
    positionals_from_usage(usage)

  # Turn a usage line ("build \[options] TARGET \[OUTPUT] \[FILE ...]") into
  # ordered positional defs. The first group is the program name and is skipped;
  # option placeholders (\[options], \[--], anything starting with "-") are
  # skipped; a lone "..." group makes the previous operand variadic.
  -> positionals_from_usage(usage)
    groups = synopsis_groups(usage)
    defs = []
    gi = 0

    while gi < groups.size()
      g = groups[gi].strip()
      if gi == 0
        gi = gi + 1
        next
      if g == "..."
        if defs.size() > 0
          last = defs[defs.size() - 1]
          last[:variadic] = true
        gi = gi + 1
        next
      d = synopsis_positional_def(g)
      if d != nil
        defs.push(d)
      gi = gi + 1

    defs

  # Split a usage line into groups, keeping a bracketed operand ("\[FILE ...]")
  # whole across the space it contains. Brackets do not nest in practice, so a
  # single open/closed flag suffices.
  -> synopsis_groups(usage)
    parts = usage.split(" ")
    groups = []
    buf = ""
    open = false
    i = 0

    while i < parts.size()
      part = parts[i]
      if part.size() > 0
        if buf.size() > 0
          buf = buf + " " + part
        else
          buf = part

        if open
          if part.ends_with?("]") || part.ends_with?(">")
            open = false
        else
          starts_bracket = part.starts_with?("\[") || part.starts_with?("<")
          closes = part.ends_with?("]") || part.ends_with?(">")
          if starts_bracket && !closes
            open = true

        if !open
          groups.push(buf)
          buf = ""
      i = i + 1

    if buf.size() > 0
      groups.push(buf)
    groups

  # Interpret one synopsis group into a positional def, or nil when it is an
  # option placeholder / separator rather than an operand. "\[NAME]" is optional,
  # "<NAME>" required, "NAME..." (or "\[NAME ...]") variadic.
  -> synopsis_positional_def(g)
    raw = g.strip()
    optional = false

    if raw.starts_with?("\[")
      optional = true
      if raw.ends_with?("]")
        raw = raw.slice(1, raw.size() - 2)
      else
        raw = raw.slice(1, raw.size() - 1)
      raw = raw.strip()
    elsif raw.starts_with?("<")
      if raw.ends_with?(">")
        raw = raw.slice(1, raw.size() - 2)
      else
        raw = raw.slice(1, raw.size() - 1)
      raw = raw.strip()

    variadic = false
    if raw.ends_with?("...")
      variadic = true
      raw = raw.slice(0, raw.size() - 3).strip()

    if raw.starts_with?("-")
      return nil
    if option_placeholder?(raw)
      return nil

    sp = raw.index(" ")
    if sp
      raw = raw.slice(0, sp)
    if raw.size() == 0
      return nil

    { name: raw, key: positional_key(raw), required: !optional, variadic: variadic }

  # Well-known "not an operand" placeholders that appear where operands do.
  -> option_placeholder?(raw)
    low = raw.downcase()
    if low == "options"
      return true
    if low == "option"
      return true
    if low == "opts"
      return true
    if low == "flags"
      return true
    if low == "flag"
      return true
    if low == "--"
      return true
    false

  # Normalize an operand name to a lookup key (downcase, "-" → "_"), matching
  # how option long-names become keys.
  -> positional_key(name)
    replace_all(name.downcase(), "-", "_")

  # Normalize an option's value placeholder ("metavar") to a bare token: strip
  # surrounding brackets/angles and a trailing ellipsis, so "\[MODE]" and "\[FILE"
  # both reduce to their operand name. Used to render usage synopses.
  -> clean_value_name(tok)
    s = tok.strip()
    while s.starts_with?("\[") || s.starts_with?("<")
      s = s.slice(1, s.size())
    while s.ends_with?("]") || s.ends_with?(">")
      s = s.slice(0, s.size() - 1)
    if s.ends_with?("...")
      s = s.slice(0, s.size() - 3)
    s.strip()

  # Pull the placeholder out of an array option's "\[NAME ...]" bracket, e.g.
  # "--files \[FILE ...]" yields "FILE". Returns nil when no bracket is present.
  -> array_value_name(line)
    bi = line.index("\[")
    if bi == nil
      return nil
    after = line.slice(bi + 1, line.size()).strip()
    sp = after.index(" ")
    if sp
      after = after.slice(0, sp)
    clean_value_name(after)

  # Auto-cast a string value: "123" → 123, "3.14" → 3.14, else string
  -> cast(val)
    if val == nil
      return nil
    s = val.to_s()
    if s.size() == 0
      return s
    # Check for decimal: digits with exactly one dot
    dot = s.index(".")
    if dot
      # Verify all chars are digits plus exactly one dot
      # (so "1.2.3" stays a string instead of truncating to 1.2)
      ok = true
      dots = 0
      start = 0
      if s.starts_with?("-")
        start = 1
      i = start
      while i < s.size()
        c = s[i]
        if c == "."
          dots = dots + 1
        elsif c < "0" || c > "9"
          ok = false
          break
        i = i + 1
      if ok && dots == 1 && s.size() > start + 1
        return s.to_f()
      return s
    # Check for integer: all digits, optionally with leading -
    ok = true
    start = 0
    if s.starts_with?("-")
      start = 1
    if s.size() <= start
      return s
    i = start
    while i < s.size()
      c = s[i]
      if c < "0" || c > "9"
        ok = false
        break
      i = i + 1
    if ok
      return s.to_i()
    s

  # Extract a "(default: VALUE)" annotation from text and cast it with the
  # same rules as parsed option values. Returns nil when absent.
  -> extract_default(text)
    di = text.index("(default:")
    if di == nil
      return nil
    after = text.slice(di + 9, text.size()).strip()
    paren = after.index(")")
    if paren == nil
      return nil
    cast(after.slice(0, paren).strip())

  # Detect a "(required)" annotation marking an option as mandatory.
  -> extract_required(text)
    text.index("(required)") != nil

  # Extract an "(env: VAR)" annotation naming the environment variable an
  # option falls back to when it is absent from argv. Returns the variable
  # name (a plain string) or nil. Same extraction shape as extract_default.
  -> extract_env(text)
    di = text.index("(env:")
    if di == nil
      return nil
    after = text.slice(di + 5, text.size()).strip()
    paren = after.index(")")
    if paren == nil
      return nil
    name = after.slice(0, paren).strip()
    if name.size() == 0
      return nil
    name

  # Extract a "(conflicts with: A, B)" / "(conflicts: A, B)" annotation naming
  # the options this one is mutually exclusive with. Names are normalized to key
  # form (leading dashes stripped, "-" → "_") so "(conflicts with: --output-format)"
  # matches the option whose key is "output_format". Returns nil when absent.
  -> extract_conflicts(text)
    di = text.index("(conflicts with:")
    marker = 16
    if di == nil
      di = text.index("(conflicts:")
      marker = 11
    if di == nil
      return nil
    after = text.slice(di + marker, text.size())
    paren = after.index(")")
    if paren == nil
      return nil
    raw = after.slice(0, paren).split(",")
    out = []
    k = 0
    while k < raw.size()
      name = raw[k].strip()
      while name.starts_with?("-")
        name = name.slice(1, name.size())
      name = replace_all(name, "-", "_")
      if name.size() > 0
        out.push(name)
      k = k + 1
    if out.size() == 0
      return nil
    out

  # Look up an environment variable's value (nil when unset). Indirection so
  # Argon:Result can reach the global env() through a plain top-level class.
  -> env_lookup(name)
    env(name)

  # Extract a "(one of: a, b, c)" / "(choices: a, b, c)" annotation into a
  # list of allowed values, cast with the same rules as parsed values so
  # numeric choices ("(choices: 1, 2, 3)") match casted integer inputs.
  # Returns nil when absent.
  -> extract_choices(text)
    di = text.index("(one of:")
    marker = 8
    if di == nil
      di = text.index("(choices:")
      marker = 9
    if di == nil
      return nil
    after = text.slice(di + marker, text.size())
    paren = after.index(")")
    if paren == nil
      return nil
    raw = after.slice(0, paren).split(",")
    out = []
    k = 0
    while k < raw.size()
      item = raw[k].strip()
      if item.size() > 0
        out.push(cast(item))
      k = k + 1
    if out.size() == 0
      return nil
    out

  # Cast a parsed value based on its option_def
  -> cast_option(key, val)
    defn = find_by_key(key)
    if defn && defn[:array]
      if val.is_a?(Array)
        casted = []
        i = 0
        while i < val.size()
          casted.push(cast(val[i]))
          i = i + 1
        return casted
      return [cast(val)]
    cast(val)

  # A "value-like" token is one an option is willing to consume as a value:
  # a plain positional, a bare "-" (stdin convention), or a negative number.
  # A genuine flag ("-v", "--out", "--") is NOT value-like and stops
  # array/optional-value consumption.
  -> value_like_token?(arg)
    if arg == "-"
      return true
    if !arg.starts_with?("-")
      return true
    negative_number_token?(arg)

  # True when `arg` is a negative number ("-5", "-5.5", "-42") rather than a
  # short flag. Following getopt, "-5" is only an option when "5" is itself a
  # defined short flag; otherwise the leading-digit token is a value/positional.
  -> negative_number_token?(arg)
    if !arg.starts_with?("-")
      return false
    if arg.size() < 2
      return false
    c = arg.slice(1, 1)
    if c >= "0" && c <= "9"
      if find_short(c)
        return false
      return true
    false

  -> find_by_key(key)
    i = 0
    while i < @option_defs.size()
      if @option_defs[i][:key] == key
        return @option_defs[i]
      i = i + 1
    nil

  -> find_short(letter)
    i = 0
    while i < @option_defs.size()
      d = @option_defs[i]
      if d[:short] == letter
        return d
      i = i + 1
    nil

  -> find_long(name)
    i = 0
    while i < @option_defs.size()
      d = @option_defs[i]
      long = d[:long]
      if long
        # Strip --\[no-] prefix for matching
        clean = replace_all(long, "\[no-]", "")
        if clean == name || long == name
          return d
      i = i + 1
    nil

  -> extract_name(text)
    # Look for NAME section: "    name -- description"
    lines = text.split("\n")
    i = 0
    while i < lines.size()
      heading = section_heading(lines[i])
      if heading == "NAME" && i + 1 < lines.size()
        name_line = lines[i + 1].strip()
        dash = name_line.index(" -- ")
        if dash
          return name_line.slice(0, dash).strip()
        return name_line
      i = i + 1
    "tungsten"

  # Parse the OPTIONS section of a manpage into structured definitions.
  #
  # Recognizes patterns like:
  #   -v
  #   --verbose
  #   -o, --out FILE
  #   --\[no-]color
  #   -e, --eval EXPRESSION
  -> parse_manpage(text)
    defs = []
    lines = text.split("\n")
    refs = referenced_sections(text)
    in_options = false
    i = 0

    while i < lines.size()
      line = lines[i]
      stripped = line.strip()
      heading = section_heading(line)
      heading_ref = nil
      if heading
        heading_ref = section_ref_name(heading)

      if heading
        in_options = option_section_ref?(heading_ref) && refs[heading_ref]
        i = i + 1
        next

      if in_options && stripped.size() > 0
        # Try to match option lines: lines starting with whitespace then -
        if stripped.starts_with?("-") || stripped.starts_with?("--")
          defn = parse_option_line(stripped)
          if defn
            # Collect description from following indented lines
            desc = ""
            j = i + 1
            while j < lines.size()
              next_line = lines[j]
              next_stripped = next_line.strip()

              # Stop at next option line or section header
              if next_stripped.starts_with?("-") && !next_stripped.starts_with?("---")
                break
              if section_heading(next_line)
                break

              # Blank line between options
              if next_stripped.size() == 0
                # Check if the line after blank is a new option
                if j + 1 < lines.size()
                  peek = lines[j + 1].strip()
                  if peek.starts_with?("-")
                    break

              if next_stripped.size() > 0
                if desc.size() > 0
                  desc = desc + " " + next_stripped
                else
                  desc = next_stripped
              j = j + 1

            defn[:description] = desc
            # Extract default: (default: VALUE). An inline default on the
            # option line itself ("-c, --connections N  Open N (default: 100)")
            # wins over one in the description lines below — the annotation
            # sitting on the option line is the most specific.
            inline_default = extract_default(stripped)
            if inline_default != nil
              defn[:default] = inline_default
            else
              below_default = extract_default(desc)
              if below_default != nil
                defn[:default] = below_default
            # Validation constraints (same extraction shape as defaults):
            # "(required)" marks the option mandatory; "(one of: a, b)" /
            # "(choices: a, b)" restricts its accepted values. An annotation
            # on the option line itself wins over one in the description.
            defn[:required] = extract_required(stripped) || extract_required(desc)
            inline_choices = extract_choices(stripped)
            if inline_choices != nil
              defn[:choices] = inline_choices
            else
              defn[:choices] = extract_choices(desc)
            # Environment-variable fallback: "(env: VAR)". As with defaults, an
            # annotation on the option line itself wins over one below it.
            inline_env = extract_env(stripped)
            if inline_env != nil
              defn[:env] = inline_env
            else
              defn[:env] = extract_env(desc)
            # Mutually exclusive options: "(conflicts with: A, B)". As with the
            # other annotations, one on the option line itself wins over one
            # sitting in the description lines below.
            inline_conflicts = extract_conflicts(stripped)
            if inline_conflicts != nil
              defn[:conflicts] = inline_conflicts
            else
              defn[:conflicts] = extract_conflicts(desc)
            defs.push(defn)

      i = i + 1

    defs

  # Parse a single option line like "-v, --verbose" or "-o, --out FILE"
  # Array options use bracket syntax: "--files [FILE ...]"
  -> parse_option_line(line)
    short = nil
    long = nil
    key = nil
    takes_value = false
    optional_value = false
    negatable = false
    array = false
    value_name = nil

    # Check for array syntax: [PLACEHOLDER ...]
    # The [no-] of a negatable flag (--\[no-]color) is not a value bracket,
    # so scan a copy with negation markers removed.
    scan = replace_all(replace_all(line, "\[no-]", ""), "\[no]", "")
    bracket = scan.index("\[")
    if bracket
      ellipsis = scan.index("...")
      if ellipsis && ellipsis > bracket
        array = true
        takes_value = true
      else
        close = scan.index("]")
        if close && close > bracket
          optional_value = true
          takes_value = true

    raw_parts = line.split(",")
    parts = []
    pi = 0
    while pi < raw_parts.size()
      parts.push(raw_parts[pi].strip())
      pi = pi + 1

    j = 0
    while j < parts.size()
      part = parts[j].strip()
      tokens = part.split(" ")
      flag = tokens[0] if tokens.size() > 0

      if flag
        if flag.starts_with?("--")
          raw = flag.slice(2, flag.size())
          if raw.starts_with?("\[no-]") || raw.starts_with?("\[no]")
            negatable = true
            raw = replace_all(replace_all(raw, "\[no-]", ""), "\[no]", "")
            long = raw
          else
            long = raw
          key = replace_all(raw, "-", "_")

          # Check for value placeholder (uppercase word after flag)
          if !array && tokens.size() > 1
            val_name = tokens[1]
            if val_name == val_name.upcase() && val_name.size() > 0
              takes_value = true
              if value_name == nil
                value_name = clean_value_name(val_name)
        elsif flag.starts_with?("-") && flag.size() == 2
          short = flag.slice(1, 2)
          if !key
            key = short

          # Check for value placeholder
          if !array && tokens.size() > 1
            val_name = tokens[1]
            if val_name == val_name.upcase() && val_name.size() > 0
              takes_value = true
              if value_name == nil
                value_name = clean_value_name(val_name)

      j = j + 1

    # Array placeholders ("--files \[FILE ...]") sit inside a bracket the token
    # scan above skips, so pull the metavar straight out of the bracket.
    if array && value_name == nil
      value_name = array_value_name(line)

    if key
      return { short: short, long: long, key: key, takes_value: takes_value, optional_value: optional_value, negatable: negatable, array: array, value_name: value_name }
    nil


# Result object returned by Argon#parse
+ Argon:Result
  ro :flags
  ro :counts
  ro :options
  ro :args
  ro :rest
  ro :parser

  -> new(@flags, @counts, @options, @args, @rest, @parser)

  # Check if a flag is set (boolean flags like --verbose, --debug)
  -> flag?(name)
    key = name.to_s()
    @flags[key] == true

  # Check if a flag is explicitly negated (--no-color)
  -> negated?(name)
    key = name.to_s()
    @flags[key] == false

  # How many times a boolean flag was supplied. "-vvv" => 3, "-v" => 1,
  # never given => 0. Repeated flags accumulate whether bundled ("-vvv"),
  # separated ("-v -v -v"), or long ("--verbose --verbose") — the common
  # verbosity-level idiom. Negations ("--no-color") do not count.
  # (Named `occurrences`, not `count`: `count` collides with the runtime's
  # Enumerable intrinsic, which would treat the symbol arg as a predicate.)
  -> occurrences(name)
    key = name.to_s()
    n = @counts[key]
    if n
      return n
    0

  # Get an option value. Resolution order is command line > environment >
  # explicit default arg > manpage default. The environment step applies only
  # to options the manpage annotates "(env: VAR)"; the raw env string is cast
  # with the same rules as a parsed value, so "8" arrives as 8.
  -> get(name, default = nil)
    key = name.to_s()
    val = @options[key]
    if val
      return val
    env_val = env_value(key)
    if env_val != nil
      return env_val
    if default != nil
      return default
    # Look up manpage default
    defs = @parser.option_defs
    i = 0
    while i < defs.size()
      d = defs[i]
      if d[:key] == key
        return d[:default]
      i = i + 1
    nil

  # The casted value of an option's "(env: VAR)" fallback variable, or nil when
  # the option declares no env fallback or the variable is unset.
  -> env_value(key)
    d = @parser.find_by_key(key)
    if d == nil
      return nil
    name = d[:env]
    if name == nil
      return nil
    raw = @parser.env_lookup(name)
    if raw == nil
      return nil
    @parser.cast(raw)

  # The first positional argument (often a command or filename)
  -> command
    if @args.size() > 0
      return @args[0]
    nil

  # Positional arguments after the first (often subcommand args)
  -> arguments
    if @args.size() > 1
      @args.slice(1, @args.size())
    else
      []

  # Everything after -- (passed through to child processes)
  -> passthrough
    @rest

  # ---- Named positional arguments (from the SYNOPSIS) ----
  #
  # The SYNOPSIS line names each operand: "build \[options] TARGET \[OUTPUT]
  # \[FILE ...]" declares `target` (required), `output` (optional), and a
  # variadic `file`. Access is by position — fixed operands consume one argv
  # positional each, left to right, and the variadic operand (conventionally
  # last) takes the rest. Values are cast with the same rules as option values,
  # so a numeric operand arrives typed.

  # An operand by name. Returns the casted value; for a variadic operand, the
  # casted list of all remaining positionals ([] when none); nil for a missing
  # non-variadic operand or an unknown name.
  -> positional(name)
    key = name.to_s()
    defs = @parser.positional_defs
    idx = 0
    i = 0
    while i < defs.size()
      d = defs[i]
      if d[:key] == key
        if d[:variadic]
          if idx < @args.size()
            return cast_positionals(@args.slice(idx, @args.size() - idx))
          return []
        if idx < @args.size()
          return @parser.cast(@args[idx])
        return nil
      if d[:variadic]
        idx = @args.size()
      else
        idx = idx + 1
      i = i + 1
    nil

  # The declared operand names, in SYNOPSIS order (deterministic).
  -> positional_names
    names = []
    defs = @parser.positional_defs
    i = 0
    while i < defs.size()
      names.push(defs[i][:key])
      i = i + 1
    names

  # Required operands the SYNOPSIS declares but argv did not supply, by name and
  # in declaration order. Opt-in like `errors`, and deliberately kept out of
  # `valid?`: argon's parsing stays lenient, so enforcing operands is the
  # caller's choice. A variadic required operand is missing only when no trailing
  # argument remains for it.
  -> missing_arguments
    missing = []
    defs = @parser.positional_defs
    consumed = 0
    supplied = @args.size()
    i = 0
    while i < defs.size()
      d = defs[i]
      if d[:required] && consumed >= supplied
        missing.push(d[:name])
      if d[:variadic]
        consumed = supplied
      else
        consumed = consumed + 1
      i = i + 1
    missing

  -> cast_positionals(list)
    out = []
    j = 0
    while j < list.size()
      out.push(@parser.cast(list[j]))
      j = j + 1
    out

  # ---- Validation ----
  #
  # Parsing itself stays lenient (unknown flags are still recorded; a value
  # option missing its value degrades to `true`). Validation is opt-in: call
  # `errors` / `valid?` to surface what the user got wrong against what the
  # manpage declares. Checks, in order:
  #   * a "(required)" option the user never supplied;
  #   * a non-optional value option left without a value;
  #   * a value outside a "(one of: …)" / "(choices: …)" set;
  #   * two "(conflicts with: …)" options supplied together;
  #   * an option the manpage never documented (a typo or stray flag).

  # A list of human-readable error strings; empty when the input is valid.
  -> errors
    errs = []
    defs = @parser.option_defs
    i = 0
    while i < defs.size()
      d = defs[i]
      key = d[:key]

      if d[:required] && !provided?(key)
        errs.push("missing required option: " + option_label(d))

      if d[:takes_value] && !d[:optional_value] && @options[key] == true
        errs.push("missing value for option: " + option_label(d))

      choices = d[:choices]
      if choices != nil && @options.has_key?(key) && @options[key] != true
        bad = first_invalid_choice(@options[key], choices)
        if bad != nil
          errs.push("invalid value for " + option_label(d) + ": " + bad.to_s() + " (expected one of: " + join_list(choices) + ")")

      i = i + 1

    # Mutually exclusive options ("(conflicts with: …)"): report each
    # conflicting pair that was supplied together, once, in a deterministic
    # (sorted) order. Declaring the conflict on either option suffices — the
    # check is symmetric, so "-v (conflicts with: quiet)" also rules out
    # supplying --quiet together with -v even if --quiet declares nothing.
    reported = {}
    c = 0
    while c < defs.size()
      d = defs[c]
      conflicts = d[:conflicts]
      if conflicts != nil && provided?(d[:key])
        ci = 0
        while ci < conflicts.size()
          other = conflicts[ci]
          od = @parser.find_by_key(other)
          if od != nil && provided?(other)
            pair = conflict_pair_label(d, od)
            if !reported.has_key?(pair)
              reported[pair] = true
              errs.push("mutually exclusive options: " + pair)
          ci = ci + 1
      c = c + 1

    unks = unknown
    u = 0
    while u < unks.size()
      errs.push("unknown option: " + unks[u])
      u = u + 1

    errs

  # True when the input satisfies every manpage-declared constraint.
  -> valid?
    errors.size() == 0

  -> error?
    errors.size() > 0

  # Options the user passed that the manpage never documented, formatted as
  # they would appear on the command line ("--frobnicate", "-z"). Sorted so the
  # result is deterministic: the names are gathered from the flags/options
  # hashes, whose iteration order the compiled runtime does not guarantee.
  -> unknown
    names = []
    collect_unknown(@flags, names)
    collect_unknown(@options, names)
    names.sort()

  # ---- Validation helpers ----

  -> provided?(key)
    @flags.has_key?(key) || @options.has_key?(key)

  -> option_label(d)
    if d[:long] != nil
      return "--" + d[:long]
    "-" + d[:short]

  # A stable "labelA and labelB" for a conflicting pair, sorted by label so the
  # message is the same whichever option's "(conflicts with: …)" triggered it.
  -> conflict_pair_label(a, b)
    la = option_label(a)
    lb = option_label(b)
    if lb < la
      return lb + " and " + la
    la + " and " + lb

  -> first_invalid_choice(val, choices)
    if val.is_a?(Array)
      j = 0
      while j < val.size()
        if !choices.include?(val[j])
          return val[j]
        j = j + 1
      return nil
    if !choices.include?(val)
      return val
    nil

  -> join_list(items)
    out = ""
    j = 0
    while j < items.size()
      if j > 0
        out = out + ", "
      out = out + items[j].to_s()
      j = j + 1
    out

  -> collect_unknown(h, names)
    ks = h.keys
    j = 0
    while j < ks.size()
      k = ks[j]
      if @parser.find_by_key(k) == nil
        label = pretty_key(k)
        if !names.include?(label)
          names.push(label)
      j = j + 1

  -> pretty_key(k)
    if k.size() == 1
      return "-" + k
    "--" + @parser.replace_all(k, "_", "-")

  # The generated usage synopsis for this CLI (delegates to the parser). Handy
  # for prefixing error output: `<< opts.usage()` then `opts.errors`.
  -> usage
    @parser.usage()

  # Print help and exit
  -> help!
    << @parser.help()
    exit 0
