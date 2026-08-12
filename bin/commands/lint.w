# tungsten lint — deterministic, read-only source checks
#
# The compiler remains the authority for syntax, lowering, types, and GPU
# preflight. This command adds a deliberately small source-hygiene layer with
# stable codes. It never writes the files it inspects.

use core/json

ROOT = capture("cd \"[__DIR__]/../..\" && pwd").strip
COMPILER = ROOT + "/bin/tungsten-compiler"
KNOWN_CODES = ["LINT_TRAILING_WHITESPACE", "LINT_TAB_INDENT", "LINT_FINAL_NEWLINE"]

-> shq(value)
  "'" + value.gsub("'", "'\\''") + "'"

-> eputs(message)
  ccall("w_eputs", message)

-> sh(command)
  process_args = ["/bin/sh", "-c", command]
  Process.spawn(process_args).wait

-> known_code?(code)
  i = 0
  while i < KNOWN_CODES.size
    if KNOWN_CODES[i] == code
      return true
    i = i + 1
  false

-> usage
  << "Usage: tungsten lint \[options\] FILE.w|DIRECTORY ..."
  << ""
  << "Run the stage-2 checker plus deterministic source-hygiene rules."
  << "Directories are searched recursively; build, vendor, and .git are skipped."
  << "Source files are never modified."
  << ""
  << "Options:"
  << "  --format text|json       diagnostic format (default: text)"
  << "  --json                   shorthand for --format json"
  << "  --severity CODE=LEVEL    LEVEL is off, warning, or error"
  << "  --warnings-as-errors     promote every warning to an error"
  << "  -h, --help               show this help"

-> usage_error(message, format)
  if format == "json"
    << JSON.encode({rt: "lint", code: "LINT_USAGE", severity: "error", message: message})
  else
    eputs("tungsten lint: " + message)
  exit(2)

-> parse_override(spec, severities, format)
  pieces = spec.split("=")
  if pieces.size != 2
    usage_error("--severity expects CODE=off|warning|error", format)
  code = pieces[0].strip.upcase
  level = pieces[1].strip.downcase
  if !known_code?(code)
    usage_error("unknown lint code '" + code + "'", format)
  if level != "off" && level != "warning" && level != "error"
    usage_error("invalid severity '" + level + "' for " + code, format)
  severities[code] = level

-> apply_override_list(value, severities, format)
  if value == nil || value.strip == ""
    return
  override_parts = value.split(",")
  i = 0
  while i < override_parts.size
    parse_override(override_parts[i], severities, format)
    i = i + 1

-> effective_severity(code, severities, warnings_as_errors)
  level = severities[code]
  if level == nil
    level = "warning"
  if warnings_as_errors && level == "warning"
    return "error"
  level

-> emit_diagnostic(format, file, row, col, code, severity, message)
  if format == "json"
    << JSON.encode({rt: "lint", code: code, severity: severity, message: message, file: file, row: row, col: col})
  else
    << file + ":" + row.to_s + ":" + col.to_s + ": " + severity + "[" + code + "]: " + message

args = argv()
format = "text"
warnings_as_errors = false
severities = {}
inputs = []

# Environment defaults are applied before flags so command-line overrides win.
env_format = env("TUNGSTEN_LINT_FORMAT")
if env_format != nil && env_format.strip != ""
  format = env_format.strip.downcase
env_overrides = env("TUNGSTEN_LINT_SEVERITIES")

i = 0
while i < args.size
  arg = args[i]
  if arg == "-h" || arg == "--help"
    usage()
    exit(0)
  elsif arg == "--json"
    format = "json"
  elsif arg == "--warnings-as-errors"
    warnings_as_errors = true
  elsif arg == "--format"
    i = i + 1
    if i >= args.size
      usage_error("--format needs a value", format)
    format = args[i].downcase
  elsif arg.starts_with?("--format=")
    format = arg.slice(9, arg.size - 9).downcase
  elsif arg == "--severity"
    i = i + 1
    if i >= args.size
      usage_error("--severity needs CODE=LEVEL", format)
    parse_override(args[i], severities, format)
  elsif arg.starts_with?("--severity=")
    parse_override(arg.slice(11, arg.size - 11), severities, format)
  elsif arg.starts_with?("-")
    usage_error("unknown option '" + arg + "' (try --help)", format)
  else
    inputs.push(arg)
  i = i + 1

if format != "text" && format != "json"
  usage_error("unsupported format '" + format + "' (supported: text, json)", "text")
apply_override_list(env_overrides, severities, format)

# Reapply explicit flags after the environment. This second pass is small and
# makes the precedence unambiguous without retaining an extra override array.
i = 0
while i < args.size
  if args[i] == "--severity"
    i = i + 1
    parse_override(args[i], severities, format)
  elsif args[i].starts_with?("--severity=")
    parse_override(args[i].slice(11, args[i].size - 11), severities, format)
  i = i + 1

if inputs.size == 0
  usage_error("missing FILE.w or DIRECTORY (try --help)", format)

files = []
i = 0
while i < inputs.size
  input = inputs[i]
  if sh("test -f " + shq(input)) == 0
    files.push(input)
  elsif sh("test -d " + shq(input)) == 0
    find = "find " + shq(input) + " -type d \\( -name .git -o -name build -o -name vendor \\) -prune -o -type f -name '*.w' -print | LC_ALL=C sort"
    found = capture(find).split("\n")
    j = 0
    while j < found.size
      if found[j] != ""
        files.push(found[j])
      j = j + 1
  else
    usage_error("path not found: " + input, format)
  i = i + 1

if files.size == 0
  usage_error("no .w files found", format)

# Sort and de-duplicate all input paths, including overlaps between explicit
# files and recursively searched directories. Keep this in-process so linting
# a large tree cannot overflow the shell's argument-size limit.
sorted = files.sort
files = []
i = 0
while i < sorted.size
  if sorted[i] != "" && (files.size == 0 || files[files.size - 1] != sorted[i])
    files.push(sorted[i])
  i = i + 1

tmp_dir = capture("mktemp -d ${TMPDIR:-/tmp}/tungsten-lint.XXXXXX").strip
if tmp_dir == ""
  usage_error("could not create a temporary directory", format)

has_error = false
file_index = 0
while file_index < files.size
  file = files[file_index]
  check_output = tmp_dir + "/check-" + file_index.to_s
  prefix = format == "json" ? "TUNGSTEN_ERROR_FORMAT=json " : "NO_COLOR=1 "
  check_command = prefix + shq(COMPILER) + " check " + shq(file) + " >" + shq(check_output) + " 2>&1"
  check_status = sh(check_command)
  if check_status != 0
    has_error = true
    output = read_file(check_output)
    if output != ""
      # The compiler owns its diagnostic schema and stable E_* code. In JSON
      # mode it emits one machine-readable object; text mode retains snippets.
      << output.strip

  source = read_file(file)
  lines = source.split("\n")
  row_index = 0
  while row_index < lines.size
    line = lines[row_index]

    # Tabs are permitted in strings/comments but not as indentation. Inspect
    # only the leading whitespace prefix so the rule has no lexical false
    # positives.
    col_index = 0
    saw_indent_tab = false
    tab_col = 0
    while col_index < line.size
      char = line.slice(col_index, 1)
      if char == "\t"
        if !saw_indent_tab
          saw_indent_tab = true
          tab_col = col_index + 1
      elsif char != " "
        break
      col_index = col_index + 1
    if saw_indent_tab
      severity = effective_severity("LINT_TAB_INDENT", severities, warnings_as_errors)
      if severity != "off"
        emit_diagnostic(format, file, row_index + 1, tab_col, "LINT_TAB_INDENT", severity, "use spaces for indentation")
        if severity == "error"
          has_error = true

    # Report the first byte in the trailing run, once per source line.
    end_index = line.size
    while end_index > 0
      char = line.slice(end_index - 1, 1)
      break if char != " " && char != "\t"
      end_index = end_index - 1
    if end_index < line.size
      severity = effective_severity("LINT_TRAILING_WHITESPACE", severities, warnings_as_errors)
      if severity != "off"
        emit_diagnostic(format, file, row_index + 1, end_index + 1, "LINT_TRAILING_WHITESPACE", severity, "remove trailing whitespace")
        if severity == "error"
          has_error = true

    row_index = row_index + 1

  if source.size > 0 && source.slice(source.size - 1, 1) != "\n"
    severity = effective_severity("LINT_FINAL_NEWLINE", severities, warnings_as_errors)
    if severity != "off"
      final_line = lines.size
      final_col = lines.size == 0 ? 1 : lines[lines.size - 1].size + 1
      emit_diagnostic(format, file, final_line, final_col, "LINT_FINAL_NEWLINE", severity, "add a final newline")
      if severity == "error"
        has_error = true

  file_index = file_index + 1

sh("rm -rf " + shq(tmp_dir))
exit(has_error ? 1 : 0)
