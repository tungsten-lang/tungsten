# Cli - the slice of Python's argparse that the GF(2) tools use, for Tungsten.
#
# The record-hunt originals (tools/gf2_record_board.py, verify_gf2_lineage.py,
# screen_public_ternary_gf2.py, mmc_gf2_seeds.py, search_wide_projection_walks.py,
# screen_top_two_projection_children.py, screen_two_pass_basis_children.py,
# screen_neutral_basis_children.py, work/collect_chains.py, and the Ruby OptionParser
# of tools/verify_tensor.rb) declare their command lines with exactly these features,
# and this file provides no others:
#
#   value options        --lille X, --lille=X; type int / float / path; default:,
#                        required:, choices:, help:, metavar:       (add_argument)
#   flags                --verbose / -v, default false              (store_true)
#   repeatable options   --witness a --witness b                    (action append)
#   option value lists   --only a b c                               (nargs '*')
#   positionals          bundle; lists with nargs "+" or "*"        (verify_tensor.rb)
#   subcommands          seeds / walk, each with its own options    (add_subparsers)
#   exclusive groups     --digest | --replay-manifest, required or not
#   parser.error(text)   post-parse validation: usage and exit 2
#   -h / --help, the usage line and the help text laid out the way argparse lays them out
#
# The parse loop is a direct port of argparse's (Python 3.14): the same token
# classification, the same positional matching and the same error wording, checked
# against the real argparse on thousands of argument vectors (spec/gf2_support/
# cli_cases.w).  A command line is declared once and parsed into a Hash:
#
#   parser = Cli.new("gf2_record_board", description: "Scoreboard ...")
#   parser.add("--lille", required: true)
#   parser.add("--jobs", type: :int, default: 6, help: "processes")
#   parser.add("--verbose", short: "-v", action: :store_true)
#   parser.add("--witness", action: :append, required: true)
#   args = parser.parse(argv())          # exits 2 with argparse's message on error
#   args["jobs"]                         # keys are option names with "-" written "_"
#
# `parse` prints and exits, so tests use `try_parse`, which returns [args, nil, nil],
# [nil, stderr text, nil] for a usage error or [nil, nil, help text] for -h.  Run a tool
# as `tungsten run tool.w -- --help`: without the `--` the launcher keeps -h, -v and
# unknown flags for itself (a binary built with `-o` needs no `--`).
#
# Deliberate differences from argparse (none is used by the originals):
#   * unique-prefix abbreviations of long options (--lil for --lille) are not
#     accepted, as with allow_abbrev=False;
#   * set_defaults(func=...) does not exist: dispatch on args["command"];
#   * help strings are used verbatim (no %(default)s expansion) and defaults are
#     never appended to them;
#   * only ASCII digits are digits for `type: :int`;
#   * a list default is copied for every parse (argparse hands out the one list);
#   * the help width is $COLUMNS, else 80 (Python also asks the terminal).
#
# Tungsten notes that shaped the API: a signature cannot mix `*rest` with keyword
# arguments and an instance method cannot take optional parameters before `&`, so
# each `add` names one primary option (the long one) plus `short:`.

use floatx
use textx

# One mistake on the command line, worded the way argparse words it.
+ CliError < Error

# Ends a parse: -h (status 0, `message` is the help for stdout) or a usage error
# (status 2, `message` is the usage and error line for stderr).
+ CliStop < Error
  -> new(@message, @status)
  ro :status

# Text helpers with Python's str semantics where argparse needs them: int()/float()
# parsing and textwrap (widths and repr() come from Textx).
+ CliText
  -> .digit?(ch)
    ch.size == 1 && ch.ord >= 48 && ch.ord <= 57

  # Regex [^\d\W]: letters and underscore (a non-ASCII character counts as a letter).
  -> .letter?(ch)
    return true if ch.size > 1
    code = ch.ord
    (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || code == 95

  # Regex \w
  -> .word_char?(ch)
    CliText.letter?(ch) || CliText.digit?(ch)

  # Regex [\w!"'&.,?]
  -> .word_punct?(ch)
    CliText.word_char?(ch) || ch == "!" || ch == "\"" || ch == "'" || ch == "&" || ch == "." || ch == "," || ch == "?"

  # The digits of "1_000" style text: digit groups joined by single underscores.
  # nil for anything else, including the empty string.
  -> .digit_run(text)
    digits = ""
    after_digit = false
    ok = true
    text.chars.each -> (ch)
      if CliText.digit?(ch)
        digits += ch
        after_digit = true
      elsif ch == "_" && after_digit
        after_digit = false
      else
        ok = false
    ok && after_digit ? digits : nil

  # Python int(text) for ASCII text; nil when int() would refuse it.
  -> .parse_int(text)
    body = text.strip
    sign = body.starts_with?("-") ? "-" : ""
    body = body.slice(1, body.size - 1) if body.starts_with?("-") || body.starts_with?("+")
    digits = CliText.digit_run(body)
    digits == nil ? nil : (sign + digits).to_i

  # Python float(text); nil when float() would refuse it.
  -> .parse_float(text)
    begin
      Floatx.parse(text)
    rescue e: FloatxError
      nil

  # ---- textwrap ------------------------------------------------------------

  # textwrap splits a hyphenated word after the hyphen at w[q] when two letters (or
  # letter, hyphen, letter) precede it and a letter (with an optional hyphen) follows.
  -> .hyphen_break?(w, q)
    behind = q >= 2 && CliText.letter?(w[q - 2]) && CliText.letter?(w[q - 1])
    behind = q >= 3 && CliText.letter?(w[q - 3]) && w[q - 2] == "-" && CliText.letter?(w[q - 1]) if !behind
    return false if !behind
    return false if q + 1 >= w.size || !CliText.letter?(w[q + 1])
    return true if q + 2 < w.size && CliText.letter?(w[q + 2])
    q + 3 < w.size && w[q + 2] == "-" && CliText.letter?(w[q + 3])

  # End of a run of two or more "-" at pos that a word character follows, else nil.
  -> .dash_run_end(w, pos)
    stop = pos
    stop += 1 while stop < w.size && w[stop] == "-"
    (stop - pos >= 2 && stop < w.size && CliText.word_char?(w[stop])) ? stop : nil

  # Cut one space-free word into textwrap's chunks: after hyphens inside compound
  # words, and around a "--" between words.
  -> .split_word(word, out)
    w = word.chars
    pos = 0
    while pos < w.size
      if pos > 0 && w[pos] == "-" && CliText.word_punct?(w[pos - 1]) && CliText.dash_run_end(w, pos) != nil
        stop = CliText.dash_run_end(w, pos)
        out.push(w.slice(pos, stop - pos).join(""))
        pos = stop
        next
      q = pos + 1
      cut = nil
      while cut == nil
        if q < w.size && w[q] == "-" && CliText.hyphen_break?(w, q)
          cut = q + 1
        elsif q == w.size
          cut = q
        elsif w[q] == "-" && CliText.word_punct?(w[q - 1]) && CliText.dash_run_end(w, q) != nil
          cut = q
        else
          q += 1
      out.push(w.slice(pos, cut - pos).join(""))
      pos = cut

  # The words of the text, whitespace runs collapsed and the ends trimmed.
  -> .words(text)
    out = []
    current = ""
    text.chars.each -> (ch)
      code = ch.ord
      if code == 32 || (code >= 9 && code <= 13)
        out.push(current) if current != ""
        current = ""
      else
        current += ch
    out.push(current) if current != ""
    out

  # Words and the single blanks between them, cut the way textwrap cuts them.
  -> .chunks(words)
    out = []
    words.each_with_index -> (word, index)
      out.push(" ") if index > 0
      CliText.split_word(word, out)
    out

  # textwrap.wrap(text, width, initial_indent=first_indent, subsequent_indent=
  # rest_indent) with its defaults: long and hyphenated words break, and blanks at
  # the ends of a line are dropped.  Returns the lines.
  -> .wrap(text, width, first_indent, rest_indent)
    chunks = CliText.chunks(CliText.words(text))
    lines = []
    i = 0
    while i < chunks.size
      indent = lines.size > 0 ? rest_indent : first_indent
      room = width - Textx.char_count(indent)
      i += 1 if lines.size > 0 && chunks[i] == " "
      line = []
      used = 0
      while i < chunks.size && used + Textx.char_count(chunks[i]) <= room
        line.push(chunks[i])
        used += Textx.char_count(chunks[i])
        i += 1
      if i < chunks.size && Textx.char_count(chunks[i]) > room
        space_left = room < 1 ? 1 : room - used
        if space_left > 0
          pieces = chunks[i].chars
          cut = space_left
          if pieces.size > space_left
            hyphen = space_left - 1
            hyphen -= 1 while hyphen >= 0 && pieces[hyphen] != "-"
            solid = false
            pieces.slice(0, hyphen > 0 ? hyphen : 0).each -> (ch)
              solid = true if ch != "-"
            cut = hyphen + 1 if hyphen > 0 && solid
          line.push(pieces.slice(0, cut).join(""))
          chunks[i] = pieces.slice(cut, pieces.size - cut).join("")
          i += 1 if chunks[i] == ""
        elsif line.size == 0
          line.push(chunks[i])
          i += 1
      line.pop if line.size > 0 && line[line.size - 1] == " "
      lines.push(indent + line.join("")) if line.size > 0
    lines

# One declared argument: an option, a positional, a flag, the subcommand slot or -h.
+ CliAction
  ro :id, :names, :dest, :kind, :value_type, :default, :required, :nargs, :choices, :summary, :metavar
  rw :parsers

  -> new(@id, @names, @dest, @kind, @value_type, @default, @required, @nargs, @choices, @summary, @metavar)
    @parsers = nil

  -> option?
    @names.size > 0

  # Flags and -h take no value.
  -> flag?
    @kind == "store_true" || @kind == "help"

  # argparse's _get_action_name: how errors refer to this argument.
  -> name
    return @names.join("/") if option?
    return @metavar if @metavar != nil
    return @dest if @dest != nil
    "{" + @choices.join(",") + "}"

  # The metavar argparse shows: the explicit one, else {choices}, else the default.
  -> metavar_text
    return @metavar if @metavar != nil
    return "{" + @choices.join(",") + "}" if @choices != nil
    option? ? @dest.upcase : @dest

  # How the value(s) read in usage and help (argparse's _format_args).
  -> args_text
    shown = metavar_text
    return shown if @nargs == nil
    return "\[" + shown + " ...\]" if @nargs == "*"
    return shown + " \[" + shown + " ...\]" if @nargs == "+"
    shown + " ..."

  # "-v, --verbose" or "-j JOBS, --jobs JOBS": the left column of the help table
  # (a positional shows only its metavar there).
  -> invocation
    return metavar_text if !option?
    return @names.join(", ") if flag?
    @names.join(", ") + " " + args_text

  # The part in the usage line; optional arguments are bracketed unless required.
  -> usage_part(grouped, group_required)
    if !option?
      part = args_text
      part = part.slice(1, part.size - 2) if grouped && part.starts_with?("\[") && part.ends_with?("\]")
      return part
    part = flag? ? @names[0] : @names[0] + " " + args_text
    part = "\[" + part + "\]" if !(@required || group_required || grouped)
    part

# An add_mutually_exclusive_group: at most one of its options may be given.
+ CliGroup
  ro :required, :members

  -> new(@parser, @required)
    @members = []

  # Declare an option in the group (same arguments as Cli#add).
  -> add(name, opts = {})
    raise CliError.new("Cli: an exclusive group holds options only: " + name) if !name.starts_with?("-")
    member = @parser.add(name, opts)
    @members.push(member)
    member

# What Cli#subcommands returns; declare each subcommand with #command.
+ CliSubcommands
  -> new(@action, @parent)

  # Add a subcommand.  The returned Cli takes that subcommand's options; a help line
  # lists it under the parent's -h.
  -> command(name, help: nil)
    child = Cli.new(@parent.prog + " " + name)
    @action.parsers[name] = child
    @action.choices.push(name)
    @parent.list_subcommand(name, help) if help != nil
    child

# One parse of one argument list: argparse's _parse_known_args.
+ CliRun
  -> new(@parser, @args)
    @namespace = {}
    @extras = []
    @sub_extras = []
    @seen = []
    @seen_value = []
    @conflicts = []
    @pattern = []
    @option_at = {}
    @positionals = []

  # Returns [namespace, extras]; raises CliError for a usage mistake and CliStop
  # for -h or an error inside a subcommand.
  -> execute
    prepare
    last_option = classify
    start = 0
    while start <= last_option
      next_option = start
      next_option += 1 while next_option <= last_option && !@option_at.key?(next_option)
      if start != next_option
        after = consume_positionals(start)
        if after > start
          start = after
          next
        start = after
      if !@option_at.key?(start)
        @extras = @extras + @args.slice(start, next_option - start)
        start = next_option
      start = consume_optional(start)
    stop = consume_positionals(start)
    @extras = @extras + @args.slice(stop, @args.size - stop)
    finish

  # Defaults into the namespace, in declaration order, and the exclusion table.
  -> prepare
    @parser.actions.each -> (action)
      @seen.push(false)
      @seen_value.push(false)
      @conflicts.push([])
      if action.kind != "help" && !@namespace.key?(action.dest)
        @namespace[action.dest] = type(action.default) == "Array" ? action.default + [] : action.default
      @positionals.push(action) if !action.option?
    @parser.groups.each -> (group)
      group.members.each_with_index -> (member, i)
        group.members.each_with_index -> (other, j)
          @conflicts[member.id].push(other.id) if i != j

  # Mark every argument as option ("O"), value ("A") or the "--" separator ("-") and
  # remember what each option token means.  Returns the index of the last option.
  -> classify
    last_option = -1
    after_dashes = false
    @args.each_with_index -> (arg, index)
      if after_dashes
        @pattern.push("A")
      elsif arg == "--"
        @pattern.push("-")
        after_dashes = true
      else
        tuple = classify_one(arg)
        if tuple == nil
          @pattern.push("A")
        else
          @option_at[index] = tuple
          @pattern.push("O")
          last_option = index
    last_option

  # argparse's _parse_optional: nil for a value, else [action, option string,
  # separator, explicit argument]; action is nil for an unknown option.
  -> classify_one(arg)
    return nil if arg == "" || !arg.starts_with?("-")
    map = @parser.option_map
    return [map[arg], arg, nil, nil] if map.key?(arg)
    return nil if arg.size == 1
    equals = arg.index("=")
    if equals != nil
      head = arg.slice(0, equals)
      return [map[head], head, "=", arg.slice(equals + 1, arg.size - equals - 1)] if map.key?(head)
    if arg.slice(1, 1) != "-"
      short = arg.slice(0, 2)
      return [map[short], short, "", arg.slice(2, arg.size - 2)] if map.key?(short)
    return nil if negative_number?(arg)
    return nil if arg.include?(" ")
    [nil, arg, nil, nil]

  # "-5", "-.5", "-1x": a dash, an optional dot, a digit.
  -> negative_number?(arg)
    return true if CliText.digit?(arg.slice(1, 1))
    arg.slice(1, 1) == "." && CliText.digit?(arg.slice(2, 1))

  -> arg_error(action, message)
    CliError.new("argument " + action.name + ": " + message)

  # How many values the option at the front of `pattern[start..]` takes.
  -> match_argument(action, pattern, start)
    return 0 if action.flag?
    run = 0
    run += 1 while start + run < pattern.size && pattern[start + run] == "A"
    if action.nargs == nil
      raise arg_error(action, "expected one argument") if run == 0
      return 1
    raise arg_error(action, "expected at least one argument") if action.nargs == "+" && run == 0
    run

  # argparse's consume_optional: take the option at start_index and its values;
  # returns the index after them.
  -> consume_optional(start_index)
    tuple = @option_at[start_index]
    action = tuple[0]
    option_string = tuple[1]
    separator = tuple[2]
    explicit = tuple[3]
    taken = []
    stop = start_index + 1
    while true
      if action == nil
        @extras.push(@args[start_index])
        return start_index + 1
      if explicit != nil
        count = match_argument(action, ["A"], 0)
        if count == 0 && option_string.slice(1, 1) != "-" && explicit != ""
          if separator == "=" || explicit.starts_with?("-")
            raise arg_error(action, "ignored explicit argument " + Textx.repr_str(explicit))
          taken.push([action, [], option_string])
          option_string = "-" + explicit.slice(0, 1)
          if @parser.option_map.key?(option_string)
            action = @parser.option_map[option_string]
            explicit = explicit.slice(1, explicit.size - 1)
            if explicit == ""
              separator = nil
              explicit = nil
            elsif explicit.starts_with?("=")
              separator = "="
              explicit = explicit.slice(1, explicit.size - 1)
            else
              separator = ""
          else
            @extras.push("-" + explicit)
            break
        elsif count == 1
          taken.push([action, [explicit], option_string])
          break
        else
          raise arg_error(action, "ignored explicit argument " + Textx.repr_str(explicit))
      else
        count = match_argument(action, @pattern, start_index + 1)
        taken.push([action, @args.slice(start_index + 1, count), option_string])
        stop = start_index + 1 + count
        break
    taken.each -> (entry)
      take_action(entry[0], entry[1])
    stop

  # ---- positionals ---------------------------------------------------------

  # What a positional's nargs asks of the pattern, as [characters, min, max] runs:
  # argparse's regexes (-*A-*), (-*[A-]*), (-*A[A-]*) and (-*A[-AO]*).
  -> atoms_for(action)
    most = 1000000000
    return [["-", 0, most], ["A-", 0, most]] if action.nargs == "*"
    return [["-", 0, most], ["A", 1, 1], ["A-", 0, most]] if action.nargs == "+"
    return [["-", 0, most], ["A", 1, 1], ["-AO", 0, most]] if action.nargs == "parser"
    [["-", 0, most], ["A", 1, 1], ["-", 0, most]]

  # Match the atoms at pattern[pos..] the way a backtracking regex would (greedy runs,
  # giving back as needed).  Returns the run lengths, or nil.
  -> match_atoms(atoms, index, pos)
    return [] if index == atoms.size
    atom = atoms[index]
    run = 0
    while run < atom[2] && pos + run < @pattern.size && atom[0].include?(@pattern[pos + run])
      run += 1
    while run >= atom[1]
      rest = match_atoms(atoms, index + 1, pos + run)
      return [run] + rest if rest != nil
      run -= 1
    nil

  # argparse's _match_arguments_partial: how many values each leading positional
  # takes, trying all remaining positionals first and dropping them from the end
  # until the pattern fits.
  -> match_partial(start)
    count = @positionals.size
    while count >= 1
      atoms = []
      owners = []
      @positionals.slice(0, count).each_with_index -> (action, position)
        atoms_for(action).each -> (atom)
          atoms.push(atom)
          owners.push(position)
      runs = match_atoms(atoms, 0, start)
      if runs != nil
        result = []
        count.times -> (position)
          result.push(0)
        consumed = 0
        runs.each_with_index -> (run, index)
          result[owners[index]] += run
          consumed += run
        if start + consumed < @pattern.size && @pattern[start + consumed] == "O"
          result.pop while result.size > 0 && result[result.size - 1] == 0
        return result
      count -= 1
    []

  # The first "--" separator is not a value.
  -> without_first_dashes(values)
    out = []
    dropped = false
    values.each -> (value)
      if !dropped && value == "--"
        dropped = true
      else
        out.push(value)
    out

  # argparse's consume_positionals: hand values to as many positionals as fit.
  -> consume_positionals(start_index)
    counts = match_partial(start_index)
    index = start_index
    counts.each_with_index -> (count, position)
      action = @positionals[position]
      values = @args.slice(index, count)
      if action.nargs == "parser"
        values = without_first_dashes(values) if @pattern[index] == "-"
      else
        has_dashes = false
        @pattern.slice(index, count).each -> (mark)
          has_dashes = true if mark == "-"
        values = without_first_dashes(values) if has_dashes
      index += count
      take_action(action, values)
    @positionals = @positionals.slice(counts.size, @positionals.size - counts.size)
    index

  # ---- values --------------------------------------------------------------

  -> convert(action, text)
    if action.value_type == "int"
      number = CliText.parse_int(text)
      raise arg_error(action, "invalid int value: " + Textx.repr_str(text)) if number == nil
      return number
    if action.value_type == "float"
      number = CliText.parse_float(text)
      raise arg_error(action, "invalid float value: " + Textx.repr_str(text)) if number == nil
      return number
    text

  -> check_choice(action, value)
    return nil if action.choices == nil || action.choices.include?(value)
    shown = action.choices.map -> (choice)
      Textx.repr_str(choice.to_s)
    raise arg_error(action, "invalid choice: " + Textx.repr_str(value.to_s) + " (choose from " + shown.join(", ") + ")")

  # argparse's _get_values: convert and check what the argument received.
  -> get_values(action, texts)
    if texts.size == 0 && action.nargs == "*" && !action.option?
      return action.default == nil ? [] : action.default
    if texts.size == 1 && action.nargs == nil
      value = convert(action, texts[0])
      check_choice(action, value)
      return value
    values = texts.map -> (text)
      convert(action, text)
    if action.nargs == "parser"
      check_choice(action, values[0])
    else
      values.each -> (value)
        check_choice(action, value)
    values

  # argparse's take_action: mark the argument seen, refuse it beside an exclusive
  # partner already given, then store, append, print help or run the subcommand.
  -> take_action(action, texts)
    @seen[action.id] = true
    values = get_values(action, texts)
    if action.option? || texts.size > 0
      @seen_value[action.id] = true
      @conflicts[action.id].each -> (other_id)
        if @seen_value[other_id]
          raise arg_error(action, "not allowed with argument " + @parser.actions[other_id].name)
    apply(action, values)

  -> apply(action, values)
    if action.kind == "store" || action.kind == "store_true"
      @namespace[action.dest] = action.kind == "store" ? values : true
    elsif action.kind == "append"
      items = @namespace[action.dest] == nil ? [] : @namespace[action.dest] + []
      items.push(values)
      @namespace[action.dest] = items
    elsif action.kind == "help"
      raise CliStop.new(@parser.help_text, 0)
    else
      run_subcommand(action, values)

  # Parse the rest of the arguments with the chosen subcommand's parser and fold its
  # namespace into ours; what it did not recognise is reported by the outer parser.
  -> run_subcommand(action, values)
    @namespace[action.dest] = values[0]
    child = action.parsers[values[0]]
    result = child.parse_known(values.slice(1, values.size - 1))
    result[0].keys.each -> (key)
      @namespace[key] = result[0][key]
    @sub_extras = @sub_extras + result[1]

  # Required arguments and groups, string defaults of typed options, then the result.
  -> finish
    missing = []
    @parser.actions.each -> (action)
      if !@seen[action.id]
        if action.required
          missing.push(action.name)
        elsif action.value_type != "str" && action.value_type != "path" && type(action.default) == "String"
          @namespace[action.dest] = convert(action, action.default)
    raise CliError.new("the following arguments are required: " + missing.join(", ")) if missing.size > 0
    @parser.groups.each -> (group)
      if group.required
        given = false
        names = []
        group.members.each -> (member)
          given = true if @seen_value[member.id]
          names.push(member.name)
        raise CliError.new("one of the arguments " + names.join(" ") + " is required") if !given
    [@namespace, @extras + @sub_extras]

# The parser.  Declaration methods build the argument list; #parse and #try_parse run it.
+ Cli
  ro :prog, :description, :epilog, :actions, :groups, :option_map

  -> new(prog, description: nil, epilog: nil, usage: nil)
    @prog = prog
    @description = description
    @epilog = epilog
    @usage = usage
    @actions = []
    @groups = []
    @option_map = {}
    @listed = []
    help_action = CliAction.new(0, ["-h", "--help"], "help", "help", "str", nil, false, nil, nil, "show this help message and exit", nil)
    @actions.push(help_action)
    @option_map["-h"] = help_action
    @option_map["--help"] = help_action

  # Declare an argument.  A name starting with "-" is an option, anything else a
  # positional.  `opts` are keyword arguments:
  #   short:    the short spelling of an option ("-v")
  #   action:   :store (default), :store_true or :append
  #   type:     :str (default), :int, :float or :path (a String)
  #   default:, required:, choices:, help:, metavar:
  #   nargs:    nil (one value), "*" or "+"
  # Options are optional unless required: is true; positionals are required unless
  # nargs is "*".  (One options Hash rather than ten keywords: Tungsten methods with
  # that many keyword parameters miscompile.)
  -> add(name, opts = {})
    opts.keys.each -> (key)
      raise CliError.new("Cli: unknown argument option " + key.to_s) if !Cli.option_names.include?(key.to_s)
    kind = opts[:action] == nil ? "store" : opts[:action].to_s
    value_type = opts[:type] == nil ? "str" : opts[:type].to_s
    nargs = opts[:nargs]
    default = opts[:default]
    raise CliError.new("Cli: unknown action " + kind) if kind != "store" && kind != "store_true" && kind != "append"
    raise CliError.new("Cli: unknown type " + value_type) if value_type != "str" && value_type != "int" && value_type != "float" && value_type != "path"
    raise CliError.new("Cli: nargs must be nil, \"*\" or \"+\"") if nargs != nil && nargs != "*" && nargs != "+"
    names = []
    dest = name
    needed = nargs != "*"
    if name.starts_with?("-")
      names = opts[:short] == nil ? [name] : [opts[:short], name]
      dest = name.slice(name.starts_with?("--") ? 2 : 1, name.size).replace("-", "_")
      names.each -> (option_string)
        raise CliError.new("Cli: conflicting option string: " + option_string) if @option_map.key?(option_string)
      needed = opts[:required] == true
    else
      raise CliError.new("Cli: positionals are required unless nargs is \"*\"") if opts[:required] == true
    default = false if kind == "store_true" && default == nil
    created = CliAction.new(@actions.size, names, dest, kind, value_type, default, needed, nargs, opts[:choices], opts[:help], opts[:metavar])
    @actions.push(created)
    names.each -> (option_string)
      @option_map[option_string] = created
    created

  # The keyword names Cli#add accepts.
  -> .option_names
    ["short", "action", "type", "default", "required", "choices", "help", "metavar", "nargs"]

  # add_mutually_exclusive_group(required=...)
  -> exclusive(required: false)
    group = CliGroup.new(self, required)
    @groups.push(group)
    group

  # add_subparsers(dest=..., required=...): declare the commands on the result.
  -> subcommands(dest: "command", required: true)
    created = CliAction.new(@actions.size, [], dest, "subcommands", "str", nil, required, "parser", [], nil, nil)
    created.parsers = {}
    @actions.push(created)
    CliSubcommands.new(created, self)

  # A subcommand's help line, listed under the subcommand slot in -h.
  -> list_subcommand(name, help)
    @listed.push([name, help])

  # ---- parsing -------------------------------------------------------------

  # Parse without exiting: [args, nil, nil] on success, [nil, stderr_text, nil] for a
  # usage error and [nil, nil, help_text] for -h.
  -> try_parse(arguments)
    begin
      result = parse_known(arguments)
      if result[1].size > 0
        raise CliStop.new(error_text("unrecognized arguments: " + result[1].join(" ")), 2)
      [result[0], nil, nil]
    rescue e: CliStop
      e.status == 0 ? [nil, nil, e.message] : [nil, e.message, nil]

  # Parse `arguments` (argv()) into a Hash, or print help / the usage error and exit
  # (status 0 / 2).
  -> parse(arguments)
    result = try_parse(arguments)
    return result[0] if result[0] != nil
    if result[2] != nil
      print(result[2])
      exit(0)
    ccall("__w_eprint", result[1])
    exit(2)

  # argparse's parse_known_args: [namespace, unrecognised arguments].
  -> parse_known(arguments)
    begin
      CliRun.new(self, arguments).execute
    rescue e: CliError
      raise CliStop.new(error_text(e.message), 2)

  # parser.error(message) for the caller's own checks: the usage, then
  # "prog: error: message" on stderr, exit status 2.
  -> error(message)
    ccall("__w_eprint", error_text(message))
    exit(2)

  -> error_text(message)
    usage_text + @prog + ": error: " + message + "\n"

  # ---- usage and help ------------------------------------------------------

  # The width argparse wraps at: the terminal's columns ($COLUMNS, else 80) less two.
  -> .columns
    configured = env("COLUMNS")
    cols = configured == nil ? 0 : configured.to_i
    cols = 80 if cols <= 0
    cols - 2

  # argparse's get_lines: pack usage parts into lines no wider than `width`.
  -> .usage_lines(parts, indent, prefix, width)
    lines = []
    line = []
    indent_length = Textx.char_count(indent)
    line_len = prefix == nil ? indent_length - 1 : Textx.char_count(prefix) - 1
    parts.each -> (part)
      part_len = Textx.char_count(part)
      if line_len + 1 + part_len > width && line.size > 0
        lines.push(indent + line.join(" "))
        line = []
        line_len = indent_length - 1
      line.push(part)
      line_len += part_len + 1
    lines.push(indent + line.join(" ")) if line.size > 0
    lines[0] = lines[0].slice(indent_length, lines[0].size - indent_length) if prefix != nil
    lines

  # argparse's _get_actions_usage_parts: [parts, index of the first positional part].
  -> usage_parts
    group_of = {}
    @groups.each -> (group)
      group.members.each -> (member)
        group_of[member.id] = group
    used = {}
    optionals = []
    positionals = []
    @actions.each -> (action)
      if !action.option?
        positionals.push([false, [action]])
      elsif !used.key?(action.id)
        used[action.id] = true
        group = group_of[action.id]
        members = [action]
        if group != nil
          group.members.each -> (other)
            if !used.key?(other.id)
              used[other.id] = true
              members.push(other)
        optionals.push([group != nil && group.required, members])
    entries = optionals + positionals
    parts = []
    first_positional = nil
    entries.each_with_index -> (entry, index)
      first_positional = parts.size if index == optionals.size
      start = parts.size
      grouped = entry[1].size > 1
      entry[1].each -> (action)
        parts.push(action.usage_part(grouped, entry[0]))
      if grouped
        opener = entry[0] ? "(" : "\["
        parts[start] = opener + parts[start]
        (start...(parts.size - 1)).each -> (at)
          parts[at] = parts[at] + " |"
        closer = entry[0] ? ")" : "\]"
        parts[parts.size - 1] = parts[parts.size - 1] + closer
    first_positional = parts.size if first_positional == nil
    [parts, first_positional]

  # The usage line without its final newline, wrapped the way argparse wraps it.
  -> usage_block
    return "usage: " + @usage.replace("%(prog)s", @prog) if @usage != nil
    prefix = "usage: "
    parts = usage_parts
    line = ([@prog] + parts[0]).join(" ")
    width = Cli.columns
    if Textx.char_count(prefix) + Textx.char_count(line) > width
      optionals = parts[0].slice(0, parts[1])
      positionals = parts[0].slice(parts[1], parts[0].size - parts[1])
      prog_room = Textx.char_count(prefix) + Textx.char_count(@prog)
      if 4 * prog_room <= 3 * width
        indent = " " * (prog_room + 1)
        if optionals.size > 0
          lines = Cli.usage_lines([@prog] + optionals, indent, prefix, width)
          lines = lines + Cli.usage_lines(positionals, indent, nil, width)
        elsif positionals.size > 0
          lines = Cli.usage_lines([@prog] + positionals, indent, prefix, width)
        else
          lines = [@prog]
      else
        indent = " " * Textx.char_count(prefix)
        lines = Cli.usage_lines(optionals + positionals, indent, nil, width)
        lines = Cli.usage_lines(optionals, indent, nil, width) + Cli.usage_lines(positionals, indent, nil, width) if lines.size > 1
        lines = [@prog] + lines
      line = lines.join("\n")
    prefix + line

  # "usage: ..." exactly as argparse prints it, ending in a newline.
  -> usage_text
    usage_block + "\n"

  # One help-table entry: the invocation, padded to the help column when it fits,
  # else on its own line, then the wrapped help text (argparse's _format_action).
  -> help_entry(invocation, help, indent, help_position, help_width)
    pad = " " * indent
    action_width = help_position - indent - 2
    lines = help == nil ? [] : CliText.wrap(help, help_width, "", "")
    return pad + invocation + "\n" if lines.size == 0
    text = ""
    lead = 0
    if Textx.char_count(invocation) <= action_width
      text = pad + invocation + " " * (action_width - Textx.char_count(invocation)) + "  "
    else
      text = pad + invocation + "\n"
      lead = help_position
    text += " " * lead + lines[0] + "\n"
    lines.slice(1, lines.size - 1).each -> (line)
      text += " " * help_position + line + "\n"
    text

  # The help text argparse prints for -h: usage, description, the positional and
  # option tables, epilog.
  -> help_text
    width = Cli.columns
    longest = 0
    @actions.each -> (action)
      longest = [longest, Textx.char_count(action.invocation) + 2].max
    @listed.each -> (entry)
      longest = [longest, Textx.char_count(entry[0]) + 4].max
    help_position = [longest + 2, [24, [width - 20, 4].max].min].min
    help_width = [width - help_position, 11].max
    blocks = [usage_block]
    blocks.push(CliText.wrap(@description, width, "", "").join("\n")) if @description != nil && CliText.words(@description).size > 0
    [false, true].each -> (options)
      body = ""
      @actions.each -> (action)
        if action.option? == options
          body += help_entry(action.invocation, action.summary, 2, help_position, help_width)
          if action.kind == "subcommands"
            @listed.each -> (entry)
              body += help_entry(entry[0], entry[1], 4, help_position, help_width)
      heading = options ? "options:\n" : "positional arguments:\n"
      blocks.push(heading + body.slice(0, body.size - 1)) if body != ""
    blocks.push(CliText.wrap(@epilog, width, "", "").join("\n")) if @epilog != nil && CliText.words(@epilog).size > 0
    blocks.join("\n\n") + "\n"
