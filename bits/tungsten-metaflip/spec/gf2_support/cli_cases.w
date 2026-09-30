# Cases for lib/metaflip/gf2/cli.w, run by spec/gf2_support_test.w as gf2_cli_cases(t).
#
# The oracle is Python's argparse (3.14).  spec/fixtures/gf2_support/cli/
# gen_cli_goldens.py builds thirteen parser shapes (nine are the declarations of the
# record-hunt tools; four exercise short options, star positionals, a usage override and
# exclusive groups), parses argument vectors with each, and records what argparse
# answered: the namespace, or the exact usage and error text, or the help text.  Here the
# same shapes are built from the same parsers.json with Cli and every vector must give
# the same answer, byte for byte.  GF2_CLI_GOLDEN=DIR reads a larger set made by
# `gen_cli_goldens.py --random N --soup N --widths --out DIR` (the evidence runs);
# GF2_VERBOSE=1 prints the agreement counts.
use core/env
use core/file
use ../../lib/metaflip/gf2/cli
use ../../lib/metaflip/gf2/jsonx

-> cli_note(text)
  << text if env("GF2_VERBOSE") != nil && env("GF2_VERBOSE") != ""

# The fixture directory.  Compiled, __DIR__ is this file's directory; the interpreter
# gives the main file's directory (relative when run from the bit root), so both
# layouts are tried.  GF2_CLI_FIXTURES names it explicitly.
-> cli_fixture_dir
  found = nil
  [env("GF2_CLI_FIXTURES"), __DIR__ + "/../fixtures/gf2_support/cli", __DIR__ + "/fixtures/gf2_support/cli"].each -> (path)
    found = path if found == nil && path != nil && path != "" && File.exists?(path + "/parsers.json")
  raise "cli fixtures not found (set GF2_CLI_FIXTURES)" if found == nil
  file_expand_path(found)

-> cli_golden_dir
  configured = env("GF2_CLI_GOLDEN")
  configured == nil || configured == "" ? cli_fixture_dir : configured

-> cli_read_json(name)
  Jsonx.loads(read_file(cli_golden_dir + "/" + name))

# The options Hash Cli#add takes, from one entry of parsers.json.
-> cli_options(entry)
  opts = {}
  ["short", "type", "action", "required", "default", "nargs", "choices", "help", "metavar"].each -> (key)
    opts[key.to_sym] = entry[key] if entry.key?(key)
  opts

-> cli_declare(parser, entries, groups)
  entries.each -> (entry)
    if entry.key?("subcommands")
      table = entry["subcommands"]
      holder = parser.subcommands(dest: table["dest"], required: table["required"])
      table["commands"].each -> (command)
        child = holder.command(command["name"], help: command["help"])
        cli_declare(child, command["args"], [])
    else
      target = entry.key?("group") ? groups[entry["group"]] : parser
      target.add(entry["name"], cli_options(entry))

-> cli_build(spec)
  parser = Cli.new(spec["prog"], description: spec["description"], epilog: spec["epilog"], usage: spec["usage"])
  groups = []
  if spec.key?("groups")
    spec["groups"].each -> (group)
      groups.push(parser.exclusive(required: group["required"]))
  cli_declare(parser, spec["args"], groups)
  parser

# The usage block of a help text: everything before the first blank line.
-> cli_usage_of(help)
  help.slice(0, help.index("\n\n") + 1)

-> cli_same_namespace(actual, expected)
  return false if actual.keys != expected.keys
  same = true
  actual.keys.each -> (key)
    same = false if actual[key] != expected[key]
  same

# What argparse printed for one vector, as the (args, error text, help text) triple
# Cli#try_parse returns.
-> cli_expected(golden, vector)
  return [vector["ns"], nil, nil] if vector["k"] == "ok"
  return [nil, nil, golden["help"][vector["u"]]] if vector["k"] == "help"
  [nil, cli_usage_of(golden["help"][vector["u"]]) + vector["u"] + ": error: " + vector["e"] + "\n", nil]

-> cli_agree(actual, expected)
  return actual[0] != nil && cli_same_namespace(actual[0], expected[0]) if expected[0] != nil
  actual[0] == nil && actual[1] == expected[1] && actual[2] == expected[2]

-> gf2_cli_golden_cases(t)
  specs = cli_read_json("parsers.json")
  golden = cli_read_json("golden.json")
  parsers = {}
  specs.each -> (spec)
    parsers[spec["id"]] = cli_build(spec)
  agree = 0
  golden["cases"].each -> (vector)
    actual = parsers[vector["p"]].try_parse(vector["a"])
    expected = cli_expected(golden, vector)
    if cli_agree(actual, expected)
      agree += 1
    else
      t.eq("argparse parity: " + vector["p"] + " " + vector["a"].join(" | "), actual, expected)
  t.eq("every argument vector agrees with argparse", agree, golden["cases"].size)
  cli_note("cli: " + agree.to_s + " of " + golden["cases"].size.to_s + " argument vectors agree with argparse")
  # usage and help of every parser, at the default width
  specs.each -> (spec)
    parser = parsers[spec["id"]]
    t.eq("usage: " + spec["prog"], parser.usage_text, cli_usage_of(golden["help"][spec["prog"]]))
    t.eq("help: " + spec["prog"], parser.help_text, golden["help"][spec["prog"]])

-> gf2_cli_width_cases(t)
  specs = cli_read_json("parsers.json")
  widths = cli_read_json("widths.json")
  by_id = {}
  specs.each -> (spec)
    by_id[spec["id"]] = spec
  total = 0
  widths.keys.each -> (columns)
    Env.set("COLUMNS", columns)
    widths[columns].keys.each -> (id)
      parser = cli_build(by_id[id])
      t.eq("usage at " + columns + " columns: " + id, parser.usage_text, cli_usage_of(widths[columns][id]))
      t.eq("help at " + columns + " columns: " + id, parser.help_text, widths[columns][id])
      total += 2
  Env.delete("COLUMNS")
  cli_note("cli: " + total.to_s + " usage/help texts checked at narrow widths")

-> gf2_cli_wrap_cases(t)
  cases = cli_read_json("wrap.json")
  agree = 0
  cases.each -> (vector)
    lines = CliText.wrap(vector["t"], vector["w"], " " * vector["f"], " " * vector["r"])
    if lines == vector["l"]
      agree += 1
    else
      t.eq("textwrap: width " + vector["w"].to_s + " " + vector["t"], lines, vector["l"])
  t.eq("every wrap case agrees with textwrap", agree, cases.size)
  cli_note("cli: " + agree.to_s + " of " + cases.size.to_s + " textwrap cases agree")

-> gf2_cli_number_cases(t)
  numbers = cli_read_json("numbers.json")
  numbers["int"].each -> (pair)
    t.eq("int(" + Textx.repr_str(pair[0]) + ")", CliText.parse_int(pair[0]), pair[1])
  numbers["float"].each -> (pair)
    expected = pair[1]
    actual = CliText.parse_float(pair[0])
    if expected == "inf" || expected == "-inf" || expected == "nan"
      t.eq("float(" + Textx.repr_str(pair[0]) + ") is " + expected, actual.to_s, expected)
    else
      t.eq("float(" + Textx.repr_str(pair[0]) + ")", actual, expected)

# ---- the declaration API itself ---------------------------------------------------------

# The message Cli#add raises for a bad declaration, nil when it accepts it.
-> cli_add_error(parser, name, opts)
  begin
    parser.add(name, opts)
    nil
  rescue e
    e.to_s

-> gf2_cli_api_cases(t)
  parser = Cli.new("tool", description: "Does a thing.")
  parser.add("--count", type: :int, default: 2, help: "how many")
  parser.add("--name", required: true)
  parser.add("--loud", short: "-l", action: :store_true)
  parser.add("--tag", action: :append)
  parser.add("--rate", type: :float)
  parser.add("--mode", choices: ["fast", "slow"], metavar: "MODE")
  parser.add("file")
  ok = parser.try_parse(["--name", "n", "f", "-l", "--tag", "a", "--tag=b", "--rate", "2.5"])
  t.eq("a parse returns \[args, nil, nil\]", [ok[1], ok[2]], [nil, nil])
  t.eq("keys follow the declaration order, help excluded", ok[0].keys, ["count", "name", "loud", "tag", "rate", "mode", "file"])
  t.eq("defaults and values", ok[0], {"count" => 2, "name" => "n", "loud" => true, "tag" => ["a", "b"], "rate" => "2.5".to_f, "mode" => nil, "file" => "f"})
  bare = parser.try_parse(["--name", "n", "f"])
  t.eq("flags default to false, append and unset options to nil", [bare[0]["loud"], bare[0]["tag"], bare[0]["rate"]], [false, nil, nil])
  t.eq("--opt=value and short flags", parser.try_parse(["--name=n", "f", "-l"])[0]["loud"], true)
  t.eq("an int option converts", parser.try_parse(["--name", "n", "f", "--count", "12"])[0]["count"], 12)
  t.eq("a big int stays exact", parser.try_parse(["--name", "n", "f", "--count", "123456789012345678901234567890"])[0]["count"], 123456789012345678901234567890)
  failure = parser.try_parse(["f"])
  t.eq("a usage error returns \[nil, stderr text, nil\]", [failure[0], failure[2]], [nil, nil])
  t.eq("the error text is the usage then the message", failure[1], parser.usage_text + "tool: error: the following arguments are required: --name\n")
  t.eq("error_text is what parser.error prints", parser.error_text("boom"), parser.usage_text + "tool: error: boom\n")
  helped = parser.try_parse(["-h"])
  t.eq("-h returns \[nil, nil, help text\]", [helped[0], helped[1], helped[2] == parser.help_text], [nil, nil, true])
  t.eq("--help too", parser.try_parse(["--help"])[2], parser.help_text)
  t.eq("a bad choice", parser.try_parse(["--name", "n", "f", "--mode", "warp"])[1], parser.usage_text + "tool: error: argument --mode: invalid choice: 'warp' (choose from 'fast', 'slow')\n")
  t.eq("a bad float", parser.try_parse(["--name", "n", "f", "--rate", "fast"])[1], parser.usage_text + "tool: error: argument --rate: invalid float value: 'fast'\n")
  t.eq("a missing value", parser.try_parse(["--name"])[1], parser.usage_text + "tool: error: argument --name: expected one argument\n")
  t.eq("usage shows required options bare, the rest bracketed, positionals last", parser.usage_text, "usage: tool \[-h\] \[--count COUNT\] --name NAME \[-l\] \[--tag TAG\] \[--rate RATE\]\n            \[--mode MODE\]\n            file\n")
  # declaration mistakes are refused when made, not when a user hits them
  t.eq("a repeated option string", cli_add_error(parser, "--count", {}), "Cli: conflicting option string: --count")
  t.eq("an unknown keyword", cli_add_error(parser, "--x", {colour: :red}), "Cli: unknown argument option colour")
  t.eq("an unknown type", cli_add_error(parser, "--x", {type: :complex}), "Cli: unknown type complex")
  t.eq("an unknown action", cli_add_error(parser, "--x", {action: :store_false}), "Cli: unknown action store_false")
  t.eq("a required positional", cli_add_error(parser, "last", {required: true}), "Cli: positionals are required unless nargs is \"*\"")
  t.eq("a bad nargs", cli_add_error(parser, "--x", {nargs: "?"}), "Cli: nargs must be nil, \"*\" or \"+\"")
  lists = Cli.new("lists")
  lists.add("--item", action: :append, default: [])
  first = lists.try_parse([])[0]
  first["item"].push("mutated")
  t.eq("a list default is not shared between parses", lists.try_parse([])[0]["item"], [])
  # exclusive groups and subcommands through the same API
  choice = Cli.new("pick")
  group = choice.exclusive(required: true)
  group.add("--left")
  group.add("--right", type: :int)
  t.eq("a group member is accepted alone", choice.try_parse(["--right", "3"])[0], {"left" => nil, "right" => 3})
  t.eq("two members conflict", choice.try_parse(["--left", "a", "--right", "3"])[1], choice.usage_text + "pick: error: argument --right: not allowed with argument --left\n")
  t.eq("a required group needs one", choice.try_parse([])[1], choice.usage_text + "pick: error: one of the arguments --left --right is required\n")
  t.eq("the group is one usage item", choice.usage_text, "usage: pick \[-h\] (--left LEFT | --right RIGHT)\n")
  tree = Cli.new("tree")
  commands = tree.subcommands(dest: "cmd")
  grow = commands.command("grow", help: "make it bigger")
  grow.add("--by", type: :int, default: 1)
  commands.command("prune")
  t.eq("a subcommand parses its own options", tree.try_parse(["grow", "--by", "4"])[0], {"cmd" => "grow", "by" => 4})
  t.eq("a subcommand without options", tree.try_parse(["prune"])[0], {"cmd" => "prune"})
  t.eq("no subcommand is an error", tree.try_parse([])[1], tree.usage_text + "tree: error: the following arguments are required: cmd\n")
  t.eq("an unknown subcommand", tree.try_parse(["dig"])[1], tree.usage_text + "tree: error: argument cmd: invalid choice: 'dig' (choose from 'grow', 'prune')\n")
  t.eq("a subcommand error names the subcommand's usage", tree.try_parse(["grow", "--by", "x"])[1], grow.usage_text + "tree grow: error: argument --by: invalid int value: 'x'\n")
  t.eq("the subcommand slot is listed with its help", tree.help_text, "usage: tree \[-h\] {grow,prune} ...\n\npositional arguments:\n  {grow,prune}\n    grow        make it bigger\n\noptions:\n  -h, --help    show this help message and exit\n")

# ---- exit status and streams, only visible from a process ------------------------------------

-> cli_shell_quote(text)
  "'" + text.replace("'", "'\\''") + "'"

# Run the driver program (the option set of gf2_record_board.py) with `arguments`;
# returns [exit status, stdout, stderr].
-> cli_run_driver(arguments)
  configured = env("TUNGSTEN")
  tungsten = configured == nil || configured == "" ? file_expand_path(__DIR__ + "/../../../../bin/tungsten") : configured
  scratch = capture("mktemp -d").strip
  quoted = arguments.map -> (argument)
    cli_shell_quote(argument)
  command = "cd " + cli_shell_quote(cli_fixture_dir) + " && " + cli_shell_quote(tungsten) + " run driver.w -- " + quoted.join(" ")
  command += " > " + cli_shell_quote(scratch + "/out") + " 2> " + cli_shell_quote(scratch + "/err") + "; echo \"EXIT=$?\""
  status = capture(command).strip
  result = [status.slice(5, status.size - 5).to_i, read_file(scratch + "/out"), read_file(scratch + "/err")]
  system("rm -rf " + cli_shell_quote(scratch))
  result

-> gf2_cli_process_cases(t)
  cli_read_json("process.json").each -> (vector)
    result = cli_run_driver(vector["a"])
    label = vector["a"].join(" ")
    t.eq("process exit status: " + label, result[0], vector["code"])
    t.eq("process stdout: " + label, result[1], vector["stdout"])
    t.eq("process stderr: " + label, result[2], vector["stderr"])

-> gf2_cli_cases(t)
  gf2_cli_golden_cases(t)
  gf2_cli_width_cases(t)
  gf2_cli_wrap_cases(t)
  gf2_cli_number_cases(t)
  gf2_cli_api_cases(t)
  gf2_cli_process_cases(t)
