# tungsten fmt — light source normalizer (Tungsten-native)
#
# Usage: tungsten fmt [-w] <file.w ...>
#
# Normalizes trailing whitespace and final newlines. Full AST pretty-print
# (the Ruby Formatter) is not yet ported; this keeps the command available
# without a Ruby dependency.

args = argv()
write_in_place = false
files = []
i = 0
while i < args.size
  a = args[i]
  if a == "-w"
    write_in_place = true
  elsif a == "-h" || a == "--help"
    << "Usage: tungsten fmt [-w] <file.w ...>"
    << ""
    << "  -w   write result back to each file (default: print to stdout)"
    exit(0)
  else
    files.push(a)
  i = i + 1

if files.size == 0
  << "Usage: tungsten fmt [-w] <file.w ...>"
  exit(1)

-> format_source(source)
  lines = source.split("\n")
  out = StringBuffer(source.size + 16)
  li = 0
  # Drop trailing empty lines, then re-add a single final newline
  end = lines.size
  while end > 0 && lines[end - 1].strip == ""
    end = end - 1
  while li < end
    line = lines[li]
    # rstrip trailing spaces/tabs
    while line.size > 0
      last = line.slice(line.size - 1, 1)
      if last == " " || last == "\t"
        line = line.slice(0, line.size - 1)
      else
        break
    out << line
    out << "\n"
    li = li + 1
  out.to_s

fi = 0
while fi < files.size
  f = files[fi]
  if !system("test -f '" + f.gsub("'", "'\\''") + "'")
    << "tungsten fmt: not found: " + f
    exit(1)
  source = read_file(f)
  formatted = format_source(source)
  if write_in_place
    if formatted != source
      write_file(f, formatted)
      << "formatted " + f
  else
    tmp = "/tmp/tungsten-fmt-out-" + fi.to_s + ".w"
    write_file(tmp, formatted)
    system("cat '" + tmp + "'; rm -f '" + tmp + "'")
  fi = fi + 1
