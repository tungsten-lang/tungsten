# tungsten fmt — AST source formatter (Tungsten-native)
#
# Usage: tungsten fmt [-w] <file.w ...>
#
use ../../compiler/lib/formatter

args = argv()
write_in_place = false
files = []
i = 0
while i < args.size
  a = args[i]
  if a == "-w"
    write_in_place = true
  elsif a == "-h" || a == "--help"
    << "Usage: tungsten fmt \[-w\] <file.w ...>"
    << ""
    << "  -w   write result back to each file (default: print to stdout)"
    exit(0)
  else
    files.push(a)
  i = i + 1

if files.size == 0
  << "Usage: tungsten fmt \[-w\] <file.w ...>"
  exit(1)

fi = 0
while fi < files.size
  f = files[fi]
  if !system("test -f '" + f.gsub("'", "'\\''") + "'")
    << "tungsten fmt: not found: " + f
    exit(1)
  source = read_file(f)
  formatted = format_tungsten_source(source, f)
  if write_in_place
    if formatted != source
      write_file(f, formatted)
      << "formatted " + f
  else
    tmp = "/tmp/tungsten-fmt-out-" + fi.to_s + ".w"
    write_file(tmp, formatted)
    system("cat '" + tmp + "'; rm -f '" + tmp + "'")
  fi = fi + 1
