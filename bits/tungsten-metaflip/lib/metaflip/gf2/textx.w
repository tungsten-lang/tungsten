# Textx: the text, ordering and counting helpers the Python originals of the
# GF(2) toolchain get from their language and standard library, with Python's
# exact semantics (f-string and %-format cases, str.split and splitlines,
# sorted with key and reverse, collections.Counter, defaultdict, statistics
# .median, zlib.crc32, the csv module with delimiter tab).
#
# Every function is here because a surveyed original uses the idiom. Paths are
# relative to bits/tungsten-metaflip/ (tools/), written `tungsten-lang/papers/...` for the
# papers repository (scripts/) or, prefixed `work/`, to the record-hunt work directory
# ~/.tungsten/metaflip/experiments/record-hunt-20260926/work/.
#
#   char_count    every width below counts code points, as Python does
#   pad_left      tools/gf2_record_board.py:229  f"{row['kind']:>15} {row['shape']:>10}"
#                 work/compare.py:41,45          f"{'shape':>10} {seed:>6} {gap:+d}"
#                 work/make_release_metadata.py:90  f"{a['bytes']:>12,}"
#   pad_right     the left-aligned twin of pad_left (`{:<W}`); no original uses it
#   zero_pad      the porting brief names zero padding ("%05d"); no original uses it
#   thousands     work/make_release_metadata.py:48,88  f"({a['bytes']:,} bytes)"
#   signed        work/compare.py:45             f"{gap:+d}"
#   hex           tools/mmc_gf2_replay.py:236    "%x %x %x\n" % t
#                 tungsten-lang/papers/scripts/ruby_verify_all.py:43  f'{a:x} {b:x} {c:x}\n'
#   parse_hex     tools/mmc_gf2_replay.py:244    int(x, 16) for the terms of an MFW1 file
#                 work/board.py:33               (String#to_i(16) saturates at 2^63-1)
#   repr_str      tungsten-lang/papers/scripts/pack_arxiv.py:62   f'{ref!r}'
#                 work/write_readmes.py:80          f'... PASS: {first!r}'
#   splitlines    tools/gf2_record_board.py:64, tools/mmc_gf2_replay.py:57,242,
#                 tools/screen_public_ternary_gf2.py:177, work/collect_chains.py:59
#   words         tools/gf2_record_board.py:69,172  s.split(), git output .split()
#                 tools/mmc_gf2_replay.py:243,244   head.split(), l.split()
#   sort_by       tools/search_wide_projection_walks.py:84-92  key=(rank, -max(..), -sum(..), sha)
#                 tools/screen_public_ternary_gf2.py:183  sorted(rows, key=..., reverse=largest_first)
#                 tools/mmc_gf2_seeds.py:162  todo.sort(key=(rank, file)), work/board.py:146
#   sorted        tools/mmc_gf2_seeds.py:101-106, tools/gf2_record_board.py:115,132,
#                 work/closure.py:33, tools/screen_public_ternary_gf2.py:79,114
#   min_by        work/iterate.py:63  min(ranks, key=lambda r: r[0])   (first minimum wins)
#                 tools/wide_composition_recipes.py:255  _, _, _, shape = min(candidates)
#   max_by        the twin of min_by (`max(..., key=)`); no original uses it
#   compare       the tuple order min_by and max_by rely on
#   median        tungsten-lang/papers/scripts/gen_results_data.py:123,126  statistics.median(...)
#   median_pair   the two middle elements median averages for an even count
#   tally         tungsten-lang/papers/scripts/prior_art_flags.py:35  Counter(f[0] for f in ...)
#                 work/write_readmes.py:69,299,300, tools/search_wide_projection_walks.py:29
#   pairs_of      d.items(), the input of sorted_items and most_common
#   most_common   tungsten-lang/papers/scripts/gen_results_data.py:55  fam.most_common()
#   sorted_items  tools/verify_gf2_lineage.py:196,199, work/write_readmes.py:73,
#                 tools/screen_top_two_projection_children.py:77  sorted(d.items())
#   setdefault    tools/mmc_gf2_replay.py:63-76, tools/gf2_record_board.py:149,
#                 work/release_index.py:16-20, work/collect_chains.py:234-247,
#                 tungsten-lang/papers/scripts/ruby_verify_all.py:82  d.setdefault(key, [0, 0])[i] += 1
#   push_to       tools/screen_public_ternary_gf2.py:98  d.setdefault(key, []).append(x)
#   add_to        tools/gf2_record_board.py:223, tools/verify_gf2_lineage.py:190
#                 counts[k] = counts.get(k, 0) + 1; tools/mmc_gf2_alg.py:540,550 defaultdict(int)
#   group_by      tungsten-lang/papers/scripts/gen_results_data.py:112  defaultdict(list) rows by code
#   crc32         tools/screen_public_ternary_gf2.py:184  zlib.crc32(seed['shape'].encode())
#   tsv_rows      csv.reader(..., delimiter='\t') behind every DictReader below
#   tsv_records   tungsten-lang/papers/scripts/gen_results_data.py:20,39,98, prior_art_flags.py:18,
#                 ruby_verify_all.py:55, work/ruby_records.py:11, work/write_readmes.py:298,
#                 work/collect_chains.py:111  csv.DictReader(open(path), delimiter='\t')
#   tsv_text      work/release_index.py:55  csv.writer(fh, delimiter='\t')  (CRLF rows)
#                 tungsten-lang/papers/scripts/prior_art_flags.py:39  ... lineterminator='\n'
#
# What Python's data model gives for free and this file has to spell out:
#  * Sizes: String#size counts bytes, Python's len counts code points.
#  * Hash keys: an Array key hashes by identity, so Counter((a, b)) and
#    d.setdefault((a, b), []) on tuples would silently split equal keys. tally,
#    setdefault, push_to, add_to and group_by refuse Array keys with a
#    TextxError (use a scalar key such as "2x3x4") instead of miscounting.
#  * Ordering: Array#sort compares Decimal values (plain float literals such as
#    0.5) by their boxed bits, so sort_by and everything built on it refuses
#    Decimal keys (PORT-BLOCKERS.md). Int, BigInt, String, Float (~0.5) and
#    Arrays of those order correctly; `<=>` and compare are correct on SCALAR
#    Decimals, which is why median_pair uses them.
#  * Integer / and % truncate toward zero here; nothing below relies on
#    Python's floor semantics.
#  * Engine: compiled code only. `tungsten run --interpret` cannot call a user
#    method with a `->` block (sort_by, sorted, min_by, max_by, group_by).
#
# Stdlib classes (Base64, File, JSON) come from the autoload table; only
# core/crypto/crc32 is used explicitly, and it defines no top-level functions.
use core/crypto/crc32
use floatx

+ TextxError < Error

+ Textx
  # ---------------------------------------------------------------------------
  # Widths, padding, integer formats
  # ---------------------------------------------------------------------------

  # Number of code points of `s` (Python len(str)); String#size counts bytes.
  -> .char_count(s) (String) i64
    view = ccall("w_string_bytes_view", s) ## u8[]
    n = view.size ## i64
    count = 0 ## i64
    i = 0 ## i64
    while i < n
      b = view[i] ## i64
      if (b & 0xC0) != 0x80
        count += 1
      i += 1
    count

  # `value` right-aligned in `width` code points, padded on the left with the
  # one-character `fill`: f"{value:>width}" (with a fill, f"{value:{fill}>{width}}").
  # Strings and integers only, so a Float never leaks Tungsten's digits into a
  # report.
  -> .pad_left(value, width, fill = " ")
    Textx.__pad_to(Textx.__text_of(value), width, fill, true)

  # `value` left-aligned in `width` code points: f"{value:<width}".
  -> .pad_right(value, width, fill = " ")
    Textx.__pad_to(Textx.__text_of(value), width, fill, false)

  # Integer `n` in decimal, at least `width` characters wide, zero-filled after
  # the sign: "%05d" % n, f"{n:05d}" ("-0042" for -42 at width 5).
  -> .zero_pad(n, width)
    text = Textx.__integer_text(n)
    negative = text.starts_with?("-")
    digits = negative ? text.slice(1, text.size - 1) : text
    zeros = width - digits.size - (negative ? 1 : 0)
    return text if zeros <= 0
    sign = negative ? "-" : ""
    sign + ("0" * zeros) + digits

  # Integer `n` with a comma between thousands: f"{n:,}" ("-1,234,567").
  -> .thousands(n)
    text = Textx.__integer_text(n)
    negative = text.starts_with?("-")
    digits = negative ? text.slice(1, text.size - 1) : text
    groups = []
    end_at = digits.size
    while end_at > 3
      groups.push(digits.slice(end_at - 3, 3))
      end_at -= 3
    groups.push(digits.slice(0, end_at))
    sign = negative ? "-" : ""
    sign + groups.reverse.join(",")

  # Integer `n` with an explicit sign: f"{n:+d}" ("+5", "-5", "+0").
  -> .signed(n)
    text = Textx.__integer_text(n)
    text.starts_with?("-") ? text : "+" + text

  # Lower-case hexadecimal of an Int or BigInt: "%x" % n, f"{n:x}" ("-ff" for -255).
  -> .hex(n)
    Textx.__check_integer(n)
    n.to_s(16)

  # int(text, 16) for any size: optional sign, optional 0x prefix, hex digits in
  # either case with single underscores between digits. No surrounding
  # whitespace (split first). String#to_i(16) saturates at 2^63-1, so the digits
  # are accumulated in 60-bit chunks and joined with shifts.
  -> .parse_hex(text) (String)
    view = ccall("w_string_bytes_view", text) ## u8[]
    n = view.size ## i64
    i = 0 ## i64
    negative = false
    if i < n && (view[i] == 43 || view[i] == 45)
      negative = view[i] == 45
      i += 1
    if i + 1 < n && view[i] == 48 && (view[i + 1] == 120 || view[i + 1] == 88)
      i += 2
      i += 1 if i < n && view[i] == 95
    value = 0
    chunk = 0 ## i64
    in_chunk = 0 ## i64
    digits = 0 ## i64
    after_digit = false
    while i < n
      b = view[i] ## i64
      digit = 0 - 1 ## i64
      if b >= 48 && b <= 57
        digit = b - 48
      elsif b >= 97 && b <= 102
        digit = b - 87
      elsif b >= 65 && b <= 70
        digit = b - 55
      elsif b == 95 && after_digit && i + 1 < n
        after_digit = false
        i += 1
        next
      if digit < 0
        raise TextxError.new("invalid hexadecimal literal: " + Textx.repr_str(text))
      chunk = (chunk << 4) | digit
      in_chunk += 1
      digits += 1
      after_digit = true
      if in_chunk == 15
        value = (value << 60) | chunk
        chunk = 0
        in_chunk = 0
      i += 1
    if digits == 0
      raise TextxError.new("invalid hexadecimal literal: " + Textx.repr_str(text))
    value = (value << (4 * in_chunk)) | chunk if in_chunk > 0
    negative ? 0 - value : value

  # Python's repr(str): the quote is ' unless the text holds ' and no ", and the
  # text is escaped as \\ \' \" \t \n \r \xNN \uNNNN \UNNNNNNNN. Non-ASCII is
  # kept when Python calls it printable. Only assigned code points are known:
  # the non-printable ones are the categories Cc, Cf, Cs, Co, Zs, Zl and Zp of
  # Unicode 16 (Python 3.14); an unassigned code point (Cn) is kept as it is,
  # where Python would escape it. Invalid UTF-8 raises TextxError.
  -> .repr_str(s) (String)
    view = ccall("w_string_bytes_view", s) ## u8[]
    n = view.size ## i64
    quote = 39 ## i64
    if s.include?("'") && !s.include?("\"")
      quote = 34
    out = StringBuffer(n + 8)
    out << quote.chr
    plain_from = 0 ## i64
    i = 0 ## i64
    while i < n
      b = view[i] ## i64
      width = 1 ## i64
      cp = b ## i64
      if b >= 0x80
        width = Textx.__utf8_length(view, i, n)
        if width == 0
          raise TextxError.new("repr_str: invalid UTF-8 at byte " + i.to_s)
        cp = Textx.__utf8_code_point(view, i, width)
      escape = ""
      if b < 0x80
        if b == quote || b == 92
          escape = "\\" + b.chr
        elsif b == 9
          escape = "\\t"
        elsif b == 10
          escape = "\\n"
        elsif b == 13
          escape = "\\r"
        elsif b < 32 || b == 127
          escape = "\\x" + Textx.__hex_digits(b, 2)
      elsif !Textx.__printable?(cp)
        if cp <= 0xFF
          escape = "\\x" + Textx.__hex_digits(cp, 2)
        elsif cp <= 0xFFFF
          escape = "\\u" + Textx.__hex_digits(cp, 4)
        else
          escape = "\\U" + Textx.__hex_digits(cp, 8)
      if escape != ""
        out << s.slice(plain_from, i - plain_from) if i > plain_from
        out << escape
        plain_from = i + width
      i += width
    out << s.slice(plain_from, n - plain_from) if n > plain_from
    out << quote.chr
    out.to_s

  # ---------------------------------------------------------------------------
  # Splitting
  # ---------------------------------------------------------------------------

  # str.splitlines(): lines without their terminators; the boundaries are
  # \n \r \r\n \v \f \x1c \x1d \x1e U+0085 U+2028 U+2029, and a final
  # terminator does not start a further, empty line.
  -> .splitlines(s) (String)
    view = ccall("w_string_bytes_view", s) ## u8[]
    n = view.size ## i64
    lines = []
    start = 0 ## i64
    i = 0 ## i64
    while i < n
      b = view[i] ## i64
      width = 0 ## i64
      if b >= 32 && b != 0xC2 && b != 0xE2
        i += 1
        next
      if b < 32
        if b == 10 || b == 11 || b == 12 || (b >= 28 && b <= 30)
          width = 1
        elsif b == 13
          width = 1
          width = 2 if i + 1 < n && view[i + 1] == 10
      elsif b == 0xC2
        width = 2 if i + 1 < n && view[i + 1] == 0x85
      elsif b == 0xE2
        if i + 2 < n && view[i + 1] == 0x80 && (view[i + 2] == 0xA8 || view[i + 2] == 0xA9)
          width = 3
      if width > 0
        lines.push(s.slice(start, i - start))
        i += width
        start = i
      else
        i += 1
    lines.push(s.slice(start, n - start)) if start < n
    lines

  # str.split() without arguments: the words between runs of whitespace (the
  # characters str.isspace() accepts), never an empty word.
  -> .words(s) (String)
    view = ccall("w_string_bytes_view", s) ## u8[]
    n = view.size ## i64
    words = []
    start = 0 - 1 ## i64
    i = 0 ## i64
    while i < n
      b = view[i] ## i64
      width = 0 ## i64
      width = Textx.__space_length(view, i, n) if b <= 32 || b >= 0x80
      if width > 0
        if start >= 0
          words.push(s.slice(start, i - start))
          start = 0 - 1
        i += width
      else
        start = i if start < 0
        i += 1
    words.push(s.slice(start, n - start)) if start >= 0
    words

  # ---------------------------------------------------------------------------
  # Ordering
  # ---------------------------------------------------------------------------

  # -1, 0 or 1 in Python's order: Arrays compare like tuples (element by
  # element, a prefix first), false sorts before true, numbers and strings use
  # <=>. Unlike kinds (a number and a String, nil, NaN) raise TextxError, as
  # Python's TypeError does; `1 <=> "a"` can abort the program instead of
  # answering nil (Real#<=> dies on the String, see PORT-BLOCKERS.md).
  -> .compare(a, b)
    if type(a) == "Array" && type(b) == "Array"
      shorter = a.size < b.size ? a.size : b.size
      i = 0
      while i < shorter
        c = Textx.compare(a[i], b[i])
        return c if c != 0
        i += 1
      return a.size <=> b.size
    kind = Textx.__order_kind(a)
    if kind == 0 || kind != Textx.__order_kind(b)
      raise TextxError.new("compare: cannot order a " + type(a) + " and a " + type(b))
    return (a ? 1 : 0) <=> (b ? 1 : 0) if kind == 3
    c = a <=> b
    raise TextxError.new("compare: cannot order NaN") if c == nil
    c

  # sorted(items, key=block, reverse=reverse): a new Array, stable, ties keep
  # their input order also when `reverse` is true (Python reverses, sorts and
  # reverses again). The block returns the key: a scalar or an Array (a tuple).
  # Decimal keys raise (see the header).
  -> .sort_by(items, reverse: false, &)
    decorated = []
    i = 0
    while i < items.size
      key = yield items[i]
      Textx.__check_sort_key(key)
      decorated.push([key, reverse ? 0 - i : i, items[i]])
      i += 1
    ordered = decorated.sort
    ordered = ordered.reverse if reverse
    ordered.map -> (entry)
      entry[2]

  # sorted(items, reverse=reverse) in the natural order of the elements.
  -> .sorted(items, reverse: false)
    Textx.sort_by(items, reverse: reverse) -> (item)
      item

  # min(items, key=block): the first element with the smallest key; nil for an
  # empty list (min(..., default=None)).
  -> .min_by(items, &block)
    Textx.__extreme_by(items, 0 - 1, block)

  # max(items, key=block): the first element with the largest key; nil for an
  # empty list.
  -> .max_by(items, &block)
    Textx.__extreme_by(items, 1, block)

  # The two middle elements of the ascending order of `values`: [m, m] for an
  # odd count, [lower, upper] for an even one. Numbers of any kind (Int, BigInt,
  # Float, Decimal) are ordered by <=>. An empty list raises TextxError
  # (statistics.median: "no median for empty data").
  -> .median_pair(values)
    raise TextxError.new("no median for empty data") if values.size == 0
    ordered = values.sort -> (a, b)
      a <=> b
    mid = ordered.size / 2
    return [ordered[mid], ordered[mid]] if ordered.size % 2 == 1
    [ordered[mid - 1], ordered[mid]]

  # statistics.median: the middle element for an odd count; for an even count
  # the Float (a + b) / 2, exactly rounded like Python's true division.
  -> .median(values)
    pair = Textx.median_pair(values)
    return pair[0] if values.size % 2 == 1
    lower = pair[0]
    upper = pair[1]
    integers = (type(lower) == "Int" || type(lower) == "BigInt") && (type(upper) == "Int" || type(upper) == "BigInt")
    return Floatx.ratio(lower + upper, 2) if integers
    (Floatx.of(lower) + Floatx.of(upper)) / Floatx.of(2)

  # ---------------------------------------------------------------------------
  # Counting and dictionaries of lists
  # ---------------------------------------------------------------------------

  # collections.Counter(items) as a Hash item => count in first-seen order.
  # Like a Counter, a missing key counts 0: read it with counts.fetch(key, 0).
  -> .tally(items)
    counts = {}
    i = 0
    while i < items.size
      Textx.add_to(counts, items[i])
      i += 1
    counts

  # d.items(): [key, value] pairs of a Hash in insertion order.
  -> .pairs_of(hash)
    pairs = []
    keys = hash.keys
    i = 0
    while i < keys.size
      pairs.push([keys[i], hash[keys[i]]])
      i += 1
    pairs

  # Counter.most_common(n): [key, count] pairs by descending count, ties in
  # first-seen order (a stable descending sort); the first `n` when given.
  -> .most_common(counts, n = nil)
    ordered = Textx.sort_by(Textx.pairs_of(counts), reverse: true) -> (pair)
      pair[1]
    return ordered if n == nil
    return [] if n <= 0
    ordered.slice(0, n)

  # sorted(d.items()): [key, value] pairs by key.
  -> .sorted_items(hash)
    Textx.sort_by(Textx.pairs_of(hash)) -> (pair)
      pair[0]

  # d.setdefault(key, default): the value under `key`, storing `default` first
  # when the key is missing.
  -> .setdefault(hash, key, default)
    Textx.__check_hash_key(key)
    hash[key] = default unless hash.has_key?(key)
    hash[key]

  # d.setdefault(key, []).append(value); returns the list.
  -> .push_to(hash, key, value)
    list = Textx.setdefault(hash, key, [])
    list.push(value)
    list

  # d[key] = d.get(key, 0) + amount (a Counter or defaultdict(int) update);
  # returns the new total.
  -> .add_to(hash, key, amount = 1)
    Textx.__check_hash_key(key)
    hash[key] = hash.fetch(key, 0) + amount
    hash[key]

  # A defaultdict(list) filled with each item appended under block(item):
  # Hash key => Array in first-seen order.
  -> .group_by(items, &)
    groups = {}
    i = 0
    while i < items.size
      item = items[i]
      key = yield item
      Textx.push_to(groups, key, item)
      i += 1
    groups

  # ---------------------------------------------------------------------------
  # Checksum
  # ---------------------------------------------------------------------------

  # zlib.crc32(s.encode()): the CRC-32 of the bytes of `s` as a non-negative Int
  # (core's Crypto:CRC32, hardware assisted where the CPU has it).
  -> .crc32(s)
    Crypto:CRC32.checksum(s)

  # ---------------------------------------------------------------------------
  # Tab-separated values (the csv module, delimiter tab, dialect excel)
  # ---------------------------------------------------------------------------

  # csv.reader(open(path), delimiter='\t') over the whole text: an Array of rows,
  # each an Array of Strings. The text is read as a text-mode file is: \r\n and
  # \r end a line (and become \n inside a quoted field). A quote opens a quoted
  # field only at the start of a field ("" inside is one "); a quote elsewhere is
  # data; text after a closing quote is appended (non-strict). A blank line is
  # the empty row [].
  -> .tsv_rows(text) (String)
    view = ccall("w_string_bytes_view", text) ## u8[]
    n = view.size ## i64
    rows = []
    fields = []
    # state: 0 start of record, 1 start of field, 2 in field, 3 in quoted
    # field, 4 after a quote inside a quoted field. `acc` holds the finished
    # parts of the field being read, `seg` where its raw part begins.
    state = 0 ## i64
    acc = ""
    seg = 0 ## i64
    i = 0 ## i64
    while i < n
      b = view[i] ## i64
      if state <= 1
        if b == 10 || b == 13
          fields.push("") if state == 1
          rows.push(fields)
          fields = []
          state = 0
          i += 1
          i += 1 if b == 13 && i < n && view[i] == 10
        elsif b == 34
          state = 3
          seg = i + 1
          i += 1
        elsif b == 9
          fields.push("")
          state = 1
          i += 1
        else
          state = 2
          seg = i
          i += 1
      elsif state == 2
        j = i ## i64
        while j < n && view[j] != 9 && view[j] != 10 && view[j] != 13
          j += 1
        fields.push(Textx.__join_field(acc, text, seg, j))
        acc = ""
        if j >= n
          i = n
          state = 0
          rows.push(fields)
          fields = []
        elsif view[j] == 9
          state = 1
          i = j + 1
        else
          rows.push(fields)
          fields = []
          state = 0
          i = j + 1
          i += 1 if view[j] == 13 && i < n && view[i] == 10
      elsif state == 3
        j = i ## i64
        while j < n && view[j] != 34 && view[j] != 13
          j += 1
        if j >= n
          fields.push(Textx.__join_field(acc, text, seg, n))
          acc = ""
          rows.push(fields)
          fields = []
          state = 0
          i = n
        elsif view[j] == 13
          acc = Textx.__join_field(acc, text, seg, j) + "\n"
          i = j + 1
          i += 1 if i < n && view[i] == 10
          seg = i
        else
          acc = Textx.__join_field(acc, text, seg, j)
          state = 4
          i = j + 1
      else
        if b == 34
          acc = acc + "\""
          state = 3
          seg = i + 1
          i += 1
        elsif b == 9
          fields.push(acc)
          acc = ""
          state = 1
          i += 1
        elsif b == 10 || b == 13
          fields.push(acc)
          acc = ""
          rows.push(fields)
          fields = []
          state = 0
          i += 1
          i += 1 if b == 13 && i < n && view[i] == 10
        else
          state = 2
          seg = i
          i += 1
    # The text ends inside a record: close it as the end of its last line would.
    if state != 0
      fields.push(state == 2 || state == 3 ? Textx.__join_field(acc, text, seg, n) : acc)
      rows.push(fields)
    rows

  # csv.DictReader(open(path), delimiter='\t'): one Hash per data row, keys in
  # header order, nil for the fields a short row lacks. Blank lines (also before
  # the header) are skipped. A row longer than the header raises TextxError where
  # DictReader files the extras under the key None.
  -> .tsv_records(text)
    rows = Textx.tsv_rows(text)
    header = nil
    records = []
    i = 0
    while i < rows.size
      row = rows[i]
      if row.size > 0
        if header == nil
          header = row
        else
          if row.size > header.size
            raise TextxError.new("tsv row " + (i + 1).to_s + " has " + row.size.to_s + " fields, the header " + header.size.to_s)
          record = {}
          j = 0
          while j < header.size
            record[header[j]] = j < row.size ? row[j] : nil
            j += 1
          records.push(record)
      i += 1
    records

  # csv.writer(fh, delimiter='\t') with QUOTE_MINIMAL: every row terminated by
  # `eol` (the writer's default is "\r\n"; prior_art_flags.py passes "\n"). A
  # field is quoted, with " doubled, when it holds a tab, a ", a CR, an LF or a
  # character of `eol`; a row of one empty field is written as "". Fields are
  # Strings, Ints or BigInts (nil is the empty field); anything else raises
  # TextxError.
  -> .tsv_text(rows, eol: "\r\n")
    specials = ["\t", "\"", "\n", "\r"]
    k = 0
    while k < eol.size
      specials.push(eol.slice(k, 1))
      k += 1
    out = StringBuffer(1024)
    i = 0
    while i < rows.size
      row = rows[i]
      if row.size == 1 && Textx.__field_text(row[0]) == ""
        out << "\"\""
      else
        j = 0
        while j < row.size
          out << "\t" if j > 0
          out << Textx.__quote_field(Textx.__field_text(row[j]), specials)
          j += 1
      out << eol
      i += 1
    out.to_s

  # ---------------------------------------------------------------------------
  # Internal helpers (the __ prefix marks them private, as in core/base64.w)
  # ---------------------------------------------------------------------------

  # `value` as text for padding: a String itself, an integer in decimal.
  -> .__text_of(value)
    return value if type(value) == "String"
    Textx.__integer_text(value)

  # `value` in decimal, or a TextxError unless it is an Int or BigInt.
  -> .__integer_text(value)
    Textx.__check_integer(value)
    value.to_s

  # Raise a TextxError unless `value` is an Int or a BigInt.
  -> .__check_integer(value)
    kind = type(value)
    raise TextxError.new("expected an Int or BigInt, got " + kind) unless kind == "Int" || kind == "BigInt"

  # `text` padded to `width` code points with the one-character `fill`.
  -> .__pad_to(text, width, fill, on_left)
    if Textx.char_count(fill) != 1
      raise TextxError.new("pad fill must be one character, got " + Textx.repr_str(fill))
    missing = width - Textx.char_count(text)
    return text if missing <= 0
    on_left ? (fill * missing) + text : text + (fill * missing)

  # `n` in lower-case hex, zero-filled to `width` digits.
  -> .__hex_digits(n, width)
    text = n.to_s(16)
    text.size >= width ? text : ("0" * (width - text.size)) + text

  # Byte length (2 to 4) of the well-formed UTF-8 sequence at view[i], else 0.
  # Encoded surrogates (ED A0..BF xx) are accepted: they carry the lone
  # surrogates of a Python str.
  -> .__utf8_length(view, i, n) (u8[] i64 i64) i64
    b = view[i] ## i64
    width = 0 ## i64
    if b >= 0xC2 && b <= 0xDF
      width = 2
    elsif b >= 0xE0 && b <= 0xEF
      width = 3
    elsif b >= 0xF0 && b <= 0xF4
      width = 4
    return 0 if width == 0 || i + width > n
    k = 1 ## i64
    while k < width
      c = view[i + k] ## i64
      return 0 if (c & 0xC0) != 0x80
      k += 1
    second = view[i + 1] ## i64
    return 0 if (b == 0xE0 && second < 0xA0) || (b == 0xF0 && second < 0x90) || (b == 0xF4 && second > 0x8F)
    width

  # The code point of the UTF-8 sequence of `width` bytes at view[i].
  -> .__utf8_code_point(view, i, width) (u8[] i64 i64) i64
    b = view[i] ## i64
    cp = b ## i64
    if width == 2
      cp = b & 0x1F
    elsif width == 3
      cp = b & 0x0F
    else
      cp = b & 0x07
    k = 1 ## i64
    while k < width
      c = view[i + k] ## i64
      cp = (cp << 6) | (c & 0x3F)
      k += 1
    cp

  # Python's str.isprintable() for one code point above U+007F: false for the
  # assigned categories Cc, Cf, Cs, Co, Zs, Zl and Zp (Unicode 16).
  -> .__printable?(cp)
    ranges = Textx.__unprintable_ranges
    k = 0
    while k < ranges.size
      return false if cp >= ranges[k] && cp <= ranges[k + 1]
      k += 2
    true

  # Flat [low, high, low, high, ...] pairs, ascending.
  -> .__unprintable_ranges
    [128, 160, 173, 173, 1536, 1541, 1564, 1564, 1757, 1757, 1807, 1807,
     2192, 2193, 2274, 2274, 5760, 5760, 6158, 6158, 8192, 8207, 8232, 8239,
     8287, 8292, 8294, 8303, 12288, 12288, 55296, 63743, 65279, 65279,
     65529, 65531, 69821, 69821, 69837, 69837, 78896, 78911, 113824, 113827,
     119155, 119162, 917505, 917505, 917536, 917631, 983040, 1048573,
     1048576, 1114109]

  # Byte length of the whitespace character str.isspace() accepts at view[i],
  # else 0: ASCII 9-13 28-32, U+0085, U+00A0, U+1680, U+2000-200A, U+2028,
  # U+2029, U+202F, U+205F, U+3000.
  -> .__space_length(view, i, n) (u8[] i64 i64) i64
    b = view[i] ## i64
    if b < 0x80
      return 1 if b == 32 || (b >= 9 && b <= 13) || (b >= 28 && b <= 31)
      return 0
    if b == 0xC2 && i + 1 < n
      c = view[i + 1] ## i64
      return 2 if c == 0x85 || c == 0xA0
    elsif b == 0xE1 && i + 2 < n
      return 3 if view[i + 1] == 0x9A && view[i + 2] == 0x80
    elsif b == 0xE2 && i + 2 < n
      c = view[i + 1] ## i64
      d = view[i + 2] ## i64
      return 3 if c == 0x80 && ((d >= 0x80 && d <= 0x8A) || d == 0xA8 || d == 0xA9 || d == 0xAF)
      return 3 if c == 0x81 && d == 0x9F
    elsif b == 0xE3 && i + 2 < n
      return 3 if view[i + 1] == 0x80 && view[i + 2] == 0x80
    0

  # 1 for a number, 2 for a String, 3 for a Boolean, 0 for anything else.
  -> .__order_kind(value)
    kind = type(value)
    return 1 if kind == "Int" || kind == "BigInt" || kind == "Float" || kind == "Decimal"
    return 2 if kind == "String"
    return 3 if kind == "Boolean"
    0

  # Raise unless `key` (and every element of an Array key) is a value Array#sort
  # orders correctly.
  -> .__check_sort_key(key)
    if type(key) == "Array"
      i = 0
      while i < key.size
        Textx.__check_sort_key(key[i])
        i += 1
    elsif type(key) == "Decimal"
      raise TextxError.new("Decimal sort keys are mis-ordered by Array#sort (see PORT-BLOCKERS.md); use an Int, a String or a Float (~x)")

  # Raise when `key` is an Array: a Hash hashes Arrays by identity, not by value.
  -> .__check_hash_key(key)
    if type(key) == "Array"
      raise TextxError.new("an Array is hashed by identity, not by value: use a scalar key such as a joined String")

  # The first element whose key is smallest (`sign` -1) or largest (`sign` 1).
  -> .__extreme_by(items, sign, block)
    best = nil
    best_key = nil
    i = 0
    while i < items.size
      key = block(items[i])
      if i == 0 || Textx.compare(key, best_key) * sign > 0
        best = items[i]
        best_key = key
      i += 1
    best

  # `acc` followed by text[start, stop): the finished part of a csv field plus
  # its raw part, without copying when there is no finished part.
  -> .__join_field(acc, text, start, stop)
    raw = text.slice(start, stop - start)
    acc == "" ? raw : acc + raw

  # A csv field as text: a String itself, an integer in decimal, nil as "".
  -> .__field_text(value)
    return "" if value == nil
    return value if type(value) == "String"
    Textx.__integer_text(value)

  # QUOTE_MINIMAL: quote `text` only when it holds one of the `specials`.
  -> .__quote_field(text, specials)
    k = 0
    while k < specials.size
      if text.include?(specials[k])
        return "\"" + text.gsub("\"", "\"\"") + "\""
      k += 1
    text

  # ---------------------------------------------------------------------------
  # Floats (exact: the digits come from floatx.w, never from Float#to_s)
  # ---------------------------------------------------------------------------

  # f"{x:.{places}f}" and "%.{places}f" % x: the exact binary value rounded half
  # to even. Ints, BigInts and Floats.
  #   tungsten-lang/papers/scripts/gen_results_data.py:67,123  f'{rel:.4f}', f'{y:.2f}'
  #   work/collect_chains.py:254                  f'{spent / 1e6:.1f} MB compressed'
  #   tungsten-lang/papers/scripts/rebuild_closure.py:75        'elapsed %.0fs' % (time.time() - t0)
  -> .fixed(x, places)
    Floatx.fixed(x, places)

  # f"{x:.{places}%}": x * 100 as a double, fixed, then "%".
  #   work/closure.py:65 f'{TOL:.1%}', work/pick_children.py:45 f"{tol:.0%}"
  -> .percent(x, places)
    Floatx.percent(x, places)

  # f"{x:g}" and "%g" % x (precision 6 unless given): fixed or exponent form,
  # trailing zeros dropped.
  #   tungsten-lang/papers/scripts/gen_results_data.py:123,126  f'{statistics.median(...):g}'
  -> .general(x, precision = 6)
    Floatx.general(x, precision)

  # float(text): the nearest double, or FloatxError for text that is not a number.
  #   work/closure.py:17 float(os.environ.get('CLOSURE_TOL', '0')),
  #   work/pick_children.py:18 float(sys.argv[4])
  -> .parse_float(text)
    Floatx.parse(text)

  # round(x, places): the double nearest the half-even rounding of x.
  #   tools/mmc_gf2_seeds.py:138 round(time.time() - t0, 2)
  -> .round(x, places)
    Floatx.round(x, places)
