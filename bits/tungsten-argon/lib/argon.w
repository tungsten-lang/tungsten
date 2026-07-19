# Argon — manpage-driven option parser for Tungsten
#
# Feed it a manpage-formatted string (or heredoc), get a complete CLI parser.
# Options are extracted from the OPTIONS section. Short flags (-v), long flags
# (--verbose), negatable flags (--\[no-]color), and value options (-o FILE) are
# all recognized automatically from the manpage text.
#
# Usage:
#
#   cli = Argon.new(MANPAGE)
#   opts = cli.parse(ARGV)
#
#   opts.flag?(:verbose)      # => true/false
#   opts.get(:out)            # => "file.wc" or nil
#   opts.get(:out, "a.out")   # => "file.wc" or "a.out"
#   opts.args                 # => \["file.w", "arg1"]
#   opts.command              # => "compile" (first positional before --)
#

+ Argon
  ro :name
  ro :manpage
  ro :option_defs

  # option_defs: array of { short:, long:, key:, takes_value:, negatable:, description: }

  -> new(@manpage)
    @name = extract_name(manpage)
    @option_defs = parse_manpage(manpage)

  # Parse argv against the extracted option definitions.
  # Returns an Argon:Result.
  -> parse(argv)
    flags = {}
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
              while i < argv.size() && !argv[i].starts_with?("-")
                vals.push(cast(argv[i]))
                i = i + 1
              store_option(options, key, vals)
            elsif defn[:optional_value]
              next_arg = argv[i + 1]
              if next_arg != "--" && !next_arg.starts_with?("-")
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
          flags[key] = true
          i = i + 1
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
                while i < argv.size() && !argv[i].starts_with?("-")
                  vals.push(cast(argv[i]))
                  i = i + 1
                store_option(options, key, vals)
              elsif defn[:optional_value]
                next_arg = argv[i + 1]
                if next_arg != "--" && !next_arg.starts_with?("-")
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
            flags[key] = true
            i = i + 1
        else
          # Unknown short flag — treat as flag using the letter as key
          flags[short] = true
          i = i + 1
        next

      positional.push(arg)
      i = i + 1

    Argon:Result.new(flags, options, positional, rest, self)

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
            # Extract default from description: (default: VALUE)
            di = desc.index("(default:")
            if di
              after = desc.slice(di + 9, desc.size()).strip()
              paren = after.index(")")
              if paren
                defn[:default] = cast(after.slice(0, paren).strip())
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
        elsif flag.starts_with?("-") && flag.size() == 2
          short = flag.slice(1, 2)
          if !key
            key = short

          # Check for value placeholder
          if !array && tokens.size() > 1
            val_name = tokens[1]
            if val_name == val_name.upcase() && val_name.size() > 0
              takes_value = true

      j = j + 1

    if key
      return { short: short, long: long, key: key, takes_value: takes_value, optional_value: optional_value, negatable: negatable, array: array }
    nil


# Result object returned by Argon#parse
+ Argon:Result
  ro :flags
  ro :options
  ro :args
  ro :rest
  ro :parser

  -> new(@flags, @options, @args, @rest, @parser)

  # Check if a flag is set (boolean flags like --verbose, --debug)
  -> flag?(name)
    key = name.to_s()
    @flags[key] == true

  # Check if a flag is explicitly negated (--no-color)
  -> negated?(name)
    key = name.to_s()
    @flags[key] == false

  # Get an option value. Falls back to the manpage default if present.
  -> get(name, default = nil)
    key = name.to_s()
    val = @options[key]
    if val
      return val
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

  # Print help and exit
  -> help!
    << @parser.help()
    exit 0
