# tungsten symbolicate — resolve __wy_ symbols via a .sidemap file
#
# Usage:
#   tungsten symbolicate SIDEMAP tokens...
#   tungsten symbolicate SIDEMAP < backtrace.txt

args = argv()

help = false
if args.size == 0
  help = true
elsif args[0] == "-h"
  help = true
elsif args[0] == "--help"
  help = true

if help
  << "Usage: tungsten symbolicate SIDEMAP token..."
  << "       tungsten symbolicate SIDEMAP < backtrace.txt"
  << ""
  << "Resolves compact __wy_ symbols using a compiler .sidemap file."
  exit(0)

sidemap_path = args[0]
qpath = sidemap_path.replace("'", "'\\''")
if !system("test -f '" + qpath + "'")
  << "tungsten symbolicate: sidemap not found: " + sidemap_path
  exit(1)

text = read_file(sidemap_path)
data = JSON.parse(text)
hash_entries = data["hashes"]
if hash_entries == nil
  << "tungsten symbolicate: sidemap missing hashes key"
  exit(1)

symbol_entries = {}
hk = hash_entries.keys
hi = 0
while hi < hk.size
  h = hk[hi]
  entry = hash_entries[h]
  if entry != nil
    if entry["symbol"] != nil
      symbol_entries[entry["symbol"]] = [h, entry]
  hi = hi + 1

-> display_name(original)
  klass = original["class"]
  method = original["method"]
  kind = original["kind"]
  symbol = original["symbol"]
  name = nil
  if klass != nil && klass != "" && method != nil && method != ""
    sep = "#"
    if kind == "static_method"
      sep = "."
    elsif kind == "static_wrapper"
      sep = "."
    name = klass.to_s + sep + method.to_s
  elsif method != nil && method != ""
    name = method.to_s
  else
    name = symbol.to_s
  file = original["file"]
  line = original["line"]
  if file != nil && file != "" && line != nil
    return name + " (" + file.to_s + ":" + line.to_s + ")"
  name

-> is_hex_char(ch)
  if ch >= "a" && ch <= "f"
    return true
  if ch >= "0" && ch <= "9"
    return true
  if ch == "_"
    return true
  false

-> lookup(token, hash_entries, symbol_entries)
  normalized = token
  if token.include?("__wy_")
    idx = token.index("__wy_")
    if idx != nil && idx > 0
      normalized = token.slice(idx, token.size - idx)
  pair = symbol_entries[normalized]
  hash = nil
  entry = nil
  if pair != nil
    hash = pair[0]
    entry = pair[1]
  elsif normalized.size == 16
    if hash_entries[normalized] != nil
      hash = normalized
      entry = hash_entries[normalized]
      normalized = entry["symbol"]
  if entry == nil
    return token + " => <unknown>"
  originals = entry["originals"]
  parts = []
  if originals != nil
    oi = 0
    while oi < originals.size
      parts.push(display_name(originals[oi]))
      oi = oi + 1
  normalized.to_s + " " + hash.to_s + " => " + parts.join("; ")

tokens = []
ti = 1
while ti < args.size
  tokens.push(args[ti])
  ti = ti + 1

if tokens.size == 0
  line = gets()
  if line == nil
    << "Usage: tungsten symbolicate SIDEMAP token..."
    exit(1)
  while line != nil
    # Tungsten exposes the right-trim operation as String#rtrim. `rstrip` is
    # Ruby-only and made the native profiler path fail precisely when reading
    # a backtrace from stdin.
    << line.rtrim
    i = 0
    while i < line.size
      if i + 5 <= line.size && line.slice(i, 5) == "__wy_"
        j = i + 5
        while j < line.size
          ch = line.slice(j, 1)
          if !is_hex_char(ch)
            break
          j = j + 1
        tok = line.slice(i, j - i)
        << "    " + lookup(tok, hash_entries, symbol_entries)
        i = j
      else
        i = i + 1
    line = gets()
else
  ti = 0
  while ti < tokens.size
    << lookup(tokens[ti], hash_entries, symbol_entries)
    ti = ti + 1
