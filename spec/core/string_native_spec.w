# Native String method dispatch and representation-invariant regressions.

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

# Canonical inline empty plus every operation here that can produce a
# zero-length result must converge on that same mode-0 representation.
check("literal empty", "".empty?, true)
check("inline nonempty", "a".empty?, false)
check("inline max", "12345".empty?, false)
check("slab", "123456".empty?, false)
check("slab long", "a slab-backed string".empty?, false)
check("slice empty", "abc".slice(99, 3).empty?, true)
check("repeat empty", ("abc" * 0).empty?, true)
check("strip empty", "   ".strip.empty?, true)
check("upcase empty", "".upcase.empty?, true)
check("downcase empty", "".downcase.empty?, true)
check("capitalize empty", "".capitalize.empty?, true)

# w_str_append deliberately creates heap strings even for short non-empty
# results; repeat creates a long heap string. Both must reject empty?.
heap_short = "".concat("h")
heap_long = "h" * 80
check("short heap", heap_short.empty?, false)
check("long heap", heap_long.empty?, false)

# A concatenation above the short-string threshold is a rope. Runtime dispatch
# flattens it before invoking the native String method.
rope_left = "l" * 40
rope_right = "r" * 40
rope = rope_left + rope_right
check("rope", rope.empty?, false)

# Symbols share String's 0xF9 representation and historically shared its IC.
check("empty symbol", "".to_sym.empty?, true)
check("nonempty symbol", "x".to_sym.empty?, false)

-> check_byte_length(name, value, want)
  check("[name] size", value.size, want)
  check("[name] length", value.length, want)
  # The removed native IC ignored surplus arguments; source dispatch retains
  # that public compatibility behavior.
  check("[name] size extras", value.size(1, 2), want)
  check("[name] length extras", value.length(1, 2), want)

check_byte_length("inline empty", "", 0)
check_byte_length("inline UTF-8 bytes", "é", 2)
check_byte_length("slab UTF-8 bytes", "ééé", 6)
check_byte_length("heap", heap_long, 80)
check_byte_length("rope", rope, 80)
check_byte_length("inline symbol", "sym".to_sym, 3)
check_byte_length("slab symbol", "symbol".to_sym, 6)
check_byte_length("heap symbol", heap_long.to_sym, 80)

# String/Symbol#to_s is the exact low-bit clear shared by the 0xF9 runtime
# representation. Check identity for every String storage tier and exact
# Symbol -> String bits for both supported Symbol tiers.
inline_values = ["", "a", "12345"]
slab_values = ["123456", "a slab-backed string"]
heap_values = ["".concat("h"), "h" * 80]

si = 0
while si < inline_values.size
  value = inline_values[si]
  check("inline to_s content", value.to_s, value)
  check("inline to_s identity", wvalue_bits(value.to_s), wvalue_bits(value))
  si += 1

si = 0
while si < slab_values.size
  value = slab_values[si]
  check("slab to_s content", value.to_s, value)
  check("slab to_s identity", wvalue_bits(value.to_s), wvalue_bits(value))
  si += 1

si = 0
while si < heap_values.size
  value = heap_values[si]
  check("heap to_s content", value.to_s, value)
  check("heap to_s identity", wvalue_bits(value.to_s), wvalue_bits(value))
  si += 1

to_s_rope = ("l" * 40) + ("r" * 41)
rope_first = to_s_rope.to_s
rope_second = to_s_rope.to_s
check("rope to_s content", rope_first, ("l" * 40) + ("r" * 41))
check("rope to_s cached flat identity", wvalue_bits(rope_first), wvalue_bits(rope_second))
check("rope to_s String result", type(rope_first), "String")

inline_symbol = "abc".to_sym
slab_symbol = "symbol-slab".to_sym
check("inline symbol to_s content", inline_symbol.to_s, "abc")
check("inline symbol bit clear", wvalue_bits(inline_symbol.to_s), wvalue_bits(inline_symbol) & -2)
check("slab symbol to_s content", slab_symbol.to_s, "symbol-slab")
check("slab symbol bit clear", wvalue_bits(slab_symbol.to_s), wvalue_bits(slab_symbol) & -2)
check("symbol to_s result type", type(slab_symbol.to_s), "String")


# ascii? consumes the representation's ASCII property: derived from payload
# high bits for inline receivers, the stored flag for slab/heap/rope.
check("ascii? inline empty", "".ascii?, true)
check("ascii? inline ascii", "abc".ascii?, true)
check("ascii? inline utf8", "é".ascii?, false)
check("ascii? slab ascii", "slab-ascii-literal".ascii?, true)
check("ascii? slab utf8", "slab-with-é-inside".ascii?, false)
check("ascii? heap ascii", ("h" * 80).ascii?, true)
check("ascii? heap utf8", ("é" * 40).ascii?, false)
check("ascii? rope ascii", (("l" * 40) + ("r" * 40)).ascii?, true)
check("ascii? rope utf8", (("l" * 40) + ("é" * 20)).ascii?, false)
check("ascii? single-quoted literal", 'plain ascii'.ascii?, true)
check("ascii? symbol", "sym".to_sym.ascii?, true)
check("ascii? symbol utf8", "é".to_sym.ascii?, false)

# byte_at: O(1) byte reads, negative indices, nil out of bounds.
check("byte_at inline", "abc".byte_at(1), 98)
check("byte_at inline negative", "abc".byte_at(-1), 99)
check("byte_at inline oob", "abc".byte_at(3), nil)
check("byte_at inline oob negative", "abc".byte_at(-4), nil)
check("byte_at heap", ("h" * 80).byte_at(79), 104)
check("byte_at utf8 raw byte", "é".byte_at(0), 195)
check("byte_at symbol", "abc".to_sym.byte_at(0), 97)

# bytes is a lazy StringBytes view: O(1) size/[] plus Enumerable.
bv = "hél".bytes
check("bytes view type", type(bv), "StringBytes")
check("bytes view size", bv.size, 4)
check("bytes view index", bv[0], 104)
check("bytes view utf8 tail", bv[3], 108)
check("bytes view to_a", bv.to_a, [104, 195, 169, 108])
check("bytes view eq array", bv == [104, 195, 169, 108], true)
check("bytes view neq array", bv == [104, 195, 169], false)
bsum = 0
"abc".bytes.each -> (b)
  bsum += b
check("bytes view each", bsum, 294)
bmapped = "abc".bytes.map -> (b)
  b + 1
check("bytes view map", bmapped, [98, 99, 100])
check("bytes heap to_a size", ("h" * 80).bytes.to_a.size, 80)

# codepoints / characters are streaming lazy views.
cv = "aé日".codepoints
check("codepoints view type", type(cv), "StringCodepoints")
check("codepoints to_a", cv.to_a, [97, 233, 26085])
check("codepoints size", "aé日".codepoints.size, 3)
check("codepoints first", "aé日".codepoints.first, 97)
hv = "aé日".characters
check("characters view type", type(hv), "StringCharacters")
check("characters to_a join", hv.to_a.join("|"), "a|é|日")
check("characters size", "aé日".characters.size, 3)
check("characters heap", (("é" * 30) + "x").characters.size, 31)

# each_* yield in order and return self; blockless returns the lazy view.
cps = []
"aé".each_codepoint -> (cp)
  cps.push(cp)
check("each_codepoint block", cps, [97, 233])
chs = []
"aé".each_character -> (c)
  chs.push(c)
check("each_character block", chs.join(""), "aé")
ebs = []
"ab".each_byte -> (b)
  ebs.push(b)
check("each_byte block", ebs, [97, 98])
check("each_byte blockless", type("ab".each_byte), "StringBytes")
check("each_codepoint blockless", type("ab".each_codepoint), "StringCodepoints")
check("each_character blockless", type("ab".each_character), "StringCharacters")

# blank?
check("blank? empty", "".blank?, true)
check("blank? spaces", "   ".blank?, true)
check("blank? mixed whitespace", " \t\r\n ".blank?, true)
check("blank? text", " a ".blank?, false)
check("blank? utf8", "é".blank?, false)
check("blank? symbol", "".to_sym.blank?, true)

# each_line / lines keep trailing newlines; final unterminated line as-is.
lls = []
"a\nbb\n\nc".each_line -> (l)
  lls.push(l)
check("each_line blocks", lls, ["a\n", "bb\n", "\n", "c"])
check("lines eager", "a\nb\n".lines, ["a\n", "b\n"])
check("lines no trailing", "ab".lines, ["ab"])
check("lines empty", "".lines, [])
check("each_line blockless", type("a\nb".each_line), "StringLines")
check("lines view size", "a\nb".each_line.size, 2)

# contains? — scaffold alias for include?.
check("contains? true", "hello".contains?("ell"), true)
check("contains? false", "hello".contains?("z"), false)

# levenshtein — code-point edit distance.
check("levenshtein classic", "kitten".levenshtein("sitting"), 3)
check("levenshtein empty", "".levenshtein("abc"), 3)
check("levenshtein same", "abc".levenshtein("abc"), 0)
check("levenshtein utf8", "café".levenshtein("cafe"), 1)

<< "string_native_spec: all checks passed"
