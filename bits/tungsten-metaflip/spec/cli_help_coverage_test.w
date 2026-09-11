# Every CLI option the fleet accepts must be documented by --help, and every
# option --help mentions must be accepted.  Both sides are read statically
# from lib/metaflip/fleet.w so this check needs no built binary.
use core/system

failures = 0 ## i64

# Options the cycle driver passes to its own re-exec; never user-facing.
internal_options = ["--rect-portfolio-child", "--cycle-position", "--cycle-deadline-ms"]

-> help_starts_with_dash(word) (String) i64
  if word == ""
    return 0
  if (" " + word).include?(" -")
    return 1
  0

-> help_bare_option(word) (String)
  if word == nil || word == ""
    return ""
  parts = word.split(",")
  if parts.size() < 1
    return ""
  parts[0]

-> help_before_paren(word) (String)
  if word == nil || word == ""
    return ""
  parts = word.split(")")
  if parts.size() < 1
    return ""
  parts[0]

-> help_quoted(line) (String)
  parts = line.split("\"")
  if parts.size() < 2
    return ""
  parts[1]

source = read_file(__DIR__ + "/../lib/metaflip/fleet.w")
if source == nil
  << "FAIL cannot read lib/metaflip/fleet.w"
  exit(1)

accepted = []
help_lines = []
lines = source.split("\n")
i = 0 ## i64
in_usage = 0 ## i64
while i < lines.size()
  line = lines[i]
  stripped = line.strip()
  if stripped.include?("-> ffn_print_usage(")
    in_usage = 1
  else
    if in_usage == 1 && line != "" && !("x" + line).include?("x  ")
      in_usage = 0
  if stripped.include?("value_options = \[") || stripped.include?("switch_options = \[") || stripped.include?("value_options.push(\"") || stripped.include?("switch_options.push(\"")
    quoted = stripped.split("\"")
    q = 1 ## i64
    while q < quoted.size()
      if help_starts_with_dash(quoted[q]) == 1
        accepted.push(quoted[q])
      q += 2
  if in_usage == 1 && stripped.include?("<< \"")
    help_lines.push(help_quoted(stripped))
  i += 1

if accepted.size() < 30
  << "FAIL expected the option tables in fleet.w, found " + accepted.size().to_s() + " options"
  exit(1)

help = help_lines.join("\n") + "\n"

# 1. Every accepted option appears in the usage text.
i = 0
while i < accepted.size()
  option = accepted[i]
  documented = help.include?(option + " ") || help.include?(option + ",") || help.include?(option + "\n") || help.include?(option + ")")
  if !internal_options.include?(option) && !documented
    << "FAIL accepted option not in --help: " + option
    failures += 1
  i += 1

# 2. Every option the usage text names is accepted.
i = 0
while i < help_lines.size()
  words = help_lines[i].split(" ")
  w = 0 ## i64
  while w < words.size()
    word = help_bare_option(help_before_paren(words[w]))
    if help_starts_with_dash(word) == 1 && word != "-" && word != "--"
      if !accepted.include?(word)
        << "FAIL --help names an option the parser does not accept: " + word
        failures += 1
    w += 1
  i += 1

if failures > 0
  << "metaflip cli help coverage: " + failures.to_s() + " failure(s)"
  exit(1)

<< "metaflip cli help coverage: ok (" + accepted.size().to_s() + " options)"
