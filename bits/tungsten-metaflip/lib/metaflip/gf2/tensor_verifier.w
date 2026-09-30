# Independent GF(2) reconstruction of matrix-multiplication tensor certificates:
# the library half of tools/verify_tensor.w, a port of tools/verify_tensor.rb
# (module MetaflipTensorVerifier) with the same names, messages and output.
#
#   TensorVerifier.dimensions(shape)              "NxMxP" -> [n, m, p]
#   TensorVerifier.infer_shape(path)              the deepest NxMxP path component
#   TensorVerifier.expand_path(path)              File.expand_path (lexical, no symlinks)
#   TensorVerifier.read(text, n, m, p)            certificate text -> Packed (raises)
#   TensorVerifier.verify_text(text, n, m, p, gate, strict)   -> record Hash
#   TensorVerifier.verify(path, n, m, p, gate, strict)        -> record Hash + :path
#   TensorVerifier.main(args)                     -> [status, stdout, stderr]
#
# `read` accepts exactly what verify_tensor.rb accepts, in the same order of
# checks, so it raises the same first message for a bad file:
#
#   * blank lines, `#` comment lines and surrounding whitespace (NUL, \t, \n,
#     \v, \f, \r, space) are ignored; CRLF is fine;
#   * MFW1: header `MFW1 n m p rank`, then rank rows of three lowercase hex
#     words (any order, any number of leading zeros, no `R` prefix);
#   * checkpoint: an all-digit line giving the rank, then rows of three decimal
#     words, each row optionally prefixed by `R`;
#   * curated corpus rows: no header at all, every row prefixed by `R`.
#
# Each factor must be nonzero and narrower than its matrix. The scheme is then
# checked by the gate(s) chosen with `gate` (:dense, :sparse or :both, see
# packed.w) and the record is {exact, shape, rank, density, sha256}, the SHA-256
# being that of the file's bytes exactly as given.
#
# With `strict` the certificate must instead be canonical MFW1 (the format of
# Scheme.parse, the acceptance rule of read_blob in the Python tooling): sorted,
# duplicate-free, lowercase hex without leading zeros, LF only, no comments.
#
# Parity with the originals (same records over the 1,087-tensor record-hunt
# corpus, same verdicts and messages over mutated and randomly damaged copies)
# is measured by spec/verify_tensor_parity_test.py; spec/verify_tensor_test.w
# pins the messages, the option parser and the JSON layout.

use core/file
use scheme

+ Metaflip:Gf2:TensorVerifier
  # ---- byte classes (typed, shared by the scanners) ---------------------------

  # Ruby String#strip whitespace: NUL, \t, \n, \v, \f, \r, space.
  -> .strippable(b) (i64) i64
    if b == 0 || b == 32 || (b >= 9 && b <= 13)
      return 1
    0

  # Ruby String#split whitespace: space, \t, \n, \v, \f, \r (not NUL).
  -> .spacer(b) (i64) i64
    if b == 32 || (b >= 9 && b <= 13)
      return 1
    0

  # ---- lines and words (typed) -------------------------------------------------

  -> .count_byte(text, ptr, byte) (String i64 i64) i64
    size = text.size ## i64
    total = 0 ## i64
    i = 0 ## i64
    while i < size
      if Metaflip:Gf2:Bits.byte(text, ptr, i) == byte
        total += 1
      i += 1
    total

  # Ruby: text.lines.map(&:strip).reject { |l| l.empty? || l.start_with?("#") }.
  # Writes the [start, stop) bounds of the k-th kept line to out[2k], out[2k+1]
  # and returns the number of kept lines. out needs 2 * (newlines + 1) entries.
  -> .split_lines(text, ptr, out) (String i64 i64[]) i64
    size = text.size ## i64
    count = 0 ## i64
    pos = 0 ## i64
    while pos < size
      stop = pos ## i64
      while stop < size && Metaflip:Gf2:Bits.byte(text, ptr, stop) != 10
        stop += 1
      first = pos ## i64
      last = stop ## i64
      while first < last && Metaflip:Gf2:TensorVerifier.strippable(Metaflip:Gf2:Bits.byte(text, ptr, first)) == 1
        first += 1
      while last > first && Metaflip:Gf2:TensorVerifier.strippable(Metaflip:Gf2:Bits.byte(text, ptr, last - 1)) == 1
        last -= 1
      if last > first && Metaflip:Gf2:Bits.byte(text, ptr, first) != 35
        out[2 * count] = first
        out[2 * count + 1] = last
        count += 1
      pos = stop + 1
    count

  # Ruby: text[first, last).split. Writes the bounds of the first `limit` words
  # to out and returns how many words there are in total.
  -> .split_words(text, ptr, first, last, out, limit) (String i64 i64 i64 i64[] i64) i64
    count = 0 ## i64
    i = first ## i64
    while i < last
      while i < last && Metaflip:Gf2:TensorVerifier.spacer(Metaflip:Gf2:Bits.byte(text, ptr, i)) == 1
        i += 1
      if i >= last
        break
      start = i ## i64
      while i < last && Metaflip:Gf2:TensorVerifier.spacer(Metaflip:Gf2:Bits.byte(text, ptr, i)) == 0
        i += 1
      if count < limit
        out[2 * count] = start
        out[2 * count + 1] = i
      count += 1
    count

  # ---- numbers (typed) ---------------------------------------------------------

  # 1 when text[first, last) is non-empty and all decimal digits.
  -> .digits?(text, ptr, first, last) (String i64 i64 i64) i64
    if last <= first
      return 0
    i = first ## i64
    while i < last
      b = Metaflip:Gf2:Bits.byte(text, ptr, i) ## i64
      if b < 48 || b > 57
        return 0
      i += 1
    1

  # 1 when text[first, last) is non-empty and all lowercase hex digits.
  -> .hex_digits?(text, ptr, first, last) (String i64 i64 i64) i64
    if last <= first
      return 0
    if Metaflip:Gf2:Bits.hex_run(text, ptr, first, last) == last
      return 1
    0

  # The decimal digits text[first, last), saturating at 2^62 (any such value is
  # far beyond every shape and term count that could match it).
  -> .decimal_value(text, ptr, first, last) (String i64 i64 i64) i64
    value = 0 ## i64
    i = first ## i64
    while i < last
      value = value * 10 + (Metaflip:Gf2:Bits.byte(text, ptr, i) - 48)
      if value > 4611686018427387904
        return 4611686018427387904
      i += 1
    value

  # 1 when text[first, last) matches /\A[1-9][0-9]*\z/.
  -> .positive_decimal?(text, ptr, first, last) (String i64 i64 i64) i64
    if Metaflip:Gf2:TensorVerifier.digits?(text, ptr, first, last) == 0
      return 0
    if Metaflip:Gf2:Bits.byte(text, ptr, first) == 48
      return 0
    1

  # Hex word -> limbs at out[base, base + words). 0 when the value is nonzero
  # and below 2^width, 1 when it is zero or too wide (out is zeroed on entry).
  -> .hex_factor(text, ptr, first, last, out, base, words, width) (String i64 i64 i64 i64[] i64 i64 i64) i64
    i = first ## i64
    while i < last && Metaflip:Gf2:Bits.byte(text, ptr, i) == 48
      i += 1
    if i >= last
      return 1
    if last - i > 16 * words
      return 1
    stop = last ## i64
    j = 0 ## i64
    while stop > i
      start = stop - 16 ## i64
      if start < i
        start = i
      out[base + j] = Metaflip:Gf2:Bits.hex_limb(text, ptr, start, stop)
      j += 1
      stop = start
    top_bits = width - 64 * (words - 1) ## i64
    if top_bits < 64 && (out[base + words - 1] >> top_bits) != 0
      return 1
    0

  # Decimal word -> limbs, same contract as hex_factor. The multiply-add runs on
  # 32-bit halves so no intermediate leaves the positive i64 range.
  -> .dec_factor(text, ptr, first, last, out, base, words, width) (String i64 i64 i64 i64[] i64 i64 i64) i64
    i = first ## i64
    while i < last && Metaflip:Gf2:Bits.byte(text, ptr, i) == 48
      i += 1
    if i >= last
      return 1
    used = 0 ## i64
    while i < last
      carry = Metaflip:Gf2:Bits.byte(text, ptr, i) - 48 ## i64
      q = 0 ## i64
      while q < used
        limb = out[base + q] ## i64
        lo = (limb & 4294967295) * 10 + carry ## i64
        hi = ((limb >> 32) & 4294967295) * 10 + (lo >> 32) ## i64
        out[base + q] = ((hi & 4294967295) << 32) | (lo & 4294967295)
        carry = hi >> 32
        q += 1
      if carry != 0
        if used >= words
          return 1
        out[base + used] = carry
        used += 1
      i += 1
    top_bits = width - 64 * (words - 1) ## i64
    if top_bits < 64 && (out[base + words - 1] >> top_bits) != 0
      return 1
    0

  # ---- shapes and paths ---------------------------------------------------------

  # Ruby: "2x2x2x".split("x") drops trailing empty fields.
  -> .split_x(text)
    parts = text.split("x")
    while parts.size > 0 && parts[parts.size - 1] == ""
      parts.pop
    parts

  -> .digit_word?(word)
    Metaflip:Gf2:TensorVerifier.positive_decimal?(word, Metaflip:Gf2:Bits.text_ptr(word), 0, word.size) == 1

  # "NxMxP" (positive decimals) -> [n, m, p]; anything else raises.
  -> .dimensions(shape)
    parts = Metaflip:Gf2:TensorVerifier.split_x(shape)
    ok = parts.size == 3
    if ok
      ok = Metaflip:Gf2:TensorVerifier.digit_word?(parts[0]) && Metaflip:Gf2:TensorVerifier.digit_word?(parts[1]) && Metaflip:Gf2:TensorVerifier.digit_word?(parts[2])
    raise "expected shape NxMxP" if !ok
    dims = parts.map -> (part) part.to_i
    raise "shape too large: [shape]" if dims[0] * dims[1] > 1048576 || dims[1] * dims[2] > 1048576 || dims[0] * dims[2] > 1048576
    dims

  # File.expand_path: absolute, `.`/`..`/`//` collapsed lexically, ~ expanded,
  # relative names resolved against the working directory.
  -> .expand_path(path)
    full = path
    if path == "~" || path.starts_with?("~/")
      full = env("HOME") + path.slice(1, path.size - 1)
    elsif !path.starts_with?("/")
      full = file_pwd() + "/" + path
    parts = []
    full.split("/").each -> (segment)
      if segment == ".."
        parts.pop if parts.size > 0
      elsif segment != "" && segment != "."
        parts.push(segment)
    "/" + parts.join("/")

  -> .shape_component?(segment)
    return false if Metaflip:Gf2:TensorVerifier.count_byte(segment, Metaflip:Gf2:Bits.text_ptr(segment), 120) != 2
    parts = segment.split("x")
    parts.size == 3 && Metaflip:Gf2:TensorVerifier.digit_word?(parts[0]) && Metaflip:Gf2:TensorVerifier.digit_word?(parts[1]) && Metaflip:Gf2:TensorVerifier.digit_word?(parts[2])

  # The deepest path component that reads NxMxP.
  -> .infer_shape(path)
    segments = Metaflip:Gf2:TensorVerifier.expand_path(path).split("/")
    i = segments.size - 1
    while i >= 0
      return segments[i] if Metaflip:Gf2:TensorVerifier.shape_component?(segments[i])
      i -= 1
    raise "cannot infer shape for [path]; pass --shape NxMxP"

  # Checks and converts the three words of one certificate row (spans[2*skip ...],
  # `count` words in the row, hex when kind == 1, decimal otherwise) into term t
  # of the limb arrays. dims = [n, m, p, wu, wv, ww]. 0 = stored, 1 = not
  # exactly three words of the right alphabet, 2 = a factor is zero or wide.
  -> .row_status(text, ptr, spans, count, skip, kind, ulimbs, vlimbs, wlimbs, t, dims) (String i64 i64[] i64 i64 i64 i64[] i64[] i64[] i64 i64[]) i64
    if count != 3
      return 1
    f = 0 ## i64
    while f < 3
      first = spans[2 * (skip + f)] ## i64
      last = spans[2 * (skip + f) + 1] ## i64
      good = Metaflip:Gf2:TensorVerifier.digits?(text, ptr, first, last) ## i64
      if kind == 1
        good = Metaflip:Gf2:TensorVerifier.hex_digits?(text, ptr, first, last)
      if good == 0
        return 1
      f += 1
    bad = 0 ## i64
    n = dims[0] ## i64
    m = dims[1] ## i64
    p = dims[2] ## i64
    first = spans[2 * skip] ## i64
    last = spans[2 * skip + 1] ## i64
    if kind == 1
      bad += Metaflip:Gf2:TensorVerifier.hex_factor(text, ptr, first, last, ulimbs, t * dims[3], dims[3], n * m)
    else
      bad += Metaflip:Gf2:TensorVerifier.dec_factor(text, ptr, first, last, ulimbs, t * dims[3], dims[3], n * m)
    first = spans[2 * (skip + 1)]
    last = spans[2 * (skip + 1) + 1]
    if kind == 1
      bad += Metaflip:Gf2:TensorVerifier.hex_factor(text, ptr, first, last, vlimbs, t * dims[4], dims[4], m * p)
    else
      bad += Metaflip:Gf2:TensorVerifier.dec_factor(text, ptr, first, last, vlimbs, t * dims[4], dims[4], m * p)
    first = spans[2 * (skip + 2)]
    last = spans[2 * (skip + 2) + 1]
    if kind == 1
      bad += Metaflip:Gf2:TensorVerifier.hex_factor(text, ptr, first, last, wlimbs, t * dims[5], dims[5], n * p)
    else
      bad += Metaflip:Gf2:TensorVerifier.dec_factor(text, ptr, first, last, wlimbs, t * dims[5], dims[5], n * p)
    if bad != 0
      return 2
    0

  # ---- the certificate reader ----------------------------------------------------

  # Certificate text -> Packed for shape n x m x p, checking everything
  # verify_tensor.rb checks before the tensor itself, in its order.
  -> .read(text, n, m, p)
    raise "non-positive shape" if n < 1 || m < 1 || p < 1
    ptr = Metaflip:Gf2:Bits.text_ptr(text)
    lines = i64[2 * (Metaflip:Gf2:TensorVerifier.count_byte(text, ptr, 10) + 1)]
    words = i64[10]
    begin
      Metaflip:Gf2:TensorVerifier.read_rows(text, ptr, lines, words, n, m, p)
    ensure
      Metaflip:Gf2:Bits.release(lines)
      Metaflip:Gf2:Bits.release(words)

  # The body of `read`: lines is scratch for the kept-line bounds, words for the
  # bounds of the words of one line.
  -> .read_rows(text, ptr, lines, words, n, m, p)
    count = Metaflip:Gf2:TensorVerifier.split_lines(text, ptr, lines)
    raise "empty tensor certificate" if count == 0
    first = lines[0]
    last = lines[1]
    packed = last - first >= 4 && text.slice(first, 4) == "MFW1"
    header = packed || Metaflip:Gf2:TensorVerifier.digits?(text, ptr, first, last) == 1
    rank = 0
    body = 0
    if packed
      fields = Metaflip:Gf2:TensorVerifier.split_words(text, ptr, first, last, words, 5)
      ok = fields == 5 && words[1] - words[0] == 4
      if ok
        (1...5).each -> (f)
          ok = false if Metaflip:Gf2:TensorVerifier.positive_decimal?(text, ptr, words[2 * f], words[2 * f + 1]) == 0
      raise "malformed MFW1 header" if !ok
      raise "MFW1 shape mismatch" if Metaflip:Gf2:TensorVerifier.decimal_value(text, ptr, words[2], words[3]) != n || Metaflip:Gf2:TensorVerifier.decimal_value(text, ptr, words[4], words[5]) != m || Metaflip:Gf2:TensorVerifier.decimal_value(text, ptr, words[6], words[7]) != p
      rank = Metaflip:Gf2:TensorVerifier.decimal_value(text, ptr, words[8], words[9])
      body = 1
    elsif header
      rank = Metaflip:Gf2:TensorVerifier.decimal_value(text, ptr, first, last)
      body = 1
    else
      rank = count
    raise "wrong term count" if rank < 1 || count - body != rank
    scheme = Metaflip:Gf2:Packed.new(n, m, p, rank)
    dims = i64[6]
    dims[0] = n
    dims[1] = m
    dims[2] = p
    dims[3] = scheme.wu
    dims[4] = scheme.wv
    dims[5] = scheme.ww
    kind = 0
    kind = 1 if packed
    begin
      t = 0
      while t < rank
        first = lines[2 * (body + t)]
        last = lines[2 * (body + t) + 1]
        total = Metaflip:Gf2:TensorVerifier.split_words(text, ptr, first, last, words, 4)
        skip = 0
        prefixed = words[1] - words[0] == 1 && Metaflip:Gf2:Bits.byte(text, ptr, words[0]) == 82
        skip = 1 if prefixed
        raise "R prefix in MFW1" if packed && prefixed
        raise "missing rank header or R prefix" if !header && !prefixed
        status = Metaflip:Gf2:TensorVerifier.row_status(text, ptr, words, total - skip, skip, kind, scheme.ulimbs, scheme.vlimbs, scheme.wlimbs, t, dims)
        raise "malformed factor triple at term [t]" if status == 1
        raise "zero or out-of-bounds factor at term [t]" if status == 2
        t += 1
    rescue failure
      scheme.release
      raise failure
    Metaflip:Gf2:Bits.release(dims)
    scheme

  # ---- verification ----------------------------------------------------------------

  -> .record(shape, rank, density, sha256)
    {exact: true, shape: shape, rank: rank, density: density, sha256: sha256}

  # n, m, p may be nil in strict mode (the header then names the shape).
  -> .verify_text(text, n, m, p, gate = :both, strict = false)
    if strict
      expect = nil
      expect = [n, m, p] if n != nil
      scheme = Metaflip:Gf2:Scheme.parse(text, expect)
      begin
        bad = scheme.defect(gate)
        raise bad.message if bad != nil
        Metaflip:Gf2:TensorVerifier.record("[scheme.n]x[scheme.m]x[scheme.p]", scheme.rank, scheme.density, Digest.sha256(text))
      ensure
        scheme.release
    else
      packed = Metaflip:Gf2:TensorVerifier.read(text, n, m, p)
      begin
        bad = packed.defect(gate)
        raise bad.message if bad != nil
        Metaflip:Gf2:TensorVerifier.record("[n]x[m]x[p]", packed.rank, packed.density, Digest.sha256(text))
      ensure
        packed.release

  -> .verify(path, n, m, p, gate = :both, strict = false)
    text = read_file(path)
    raise "No such file or directory @ rb_sysopen - [path]" if text == nil
    result = nil
    begin
      result = Metaflip:Gf2:TensorVerifier.verify_text(text, n, m, p, gate, strict)
    ensure
      Metaflip:Gf2:Bits.release(text)
    result[:path] = Metaflip:Gf2:TensorVerifier.expand_path(path)
    result

  # ---- command line ------------------------------------------------------------------

  -> .usage
    lines = ["Usage: verify_tensor.w \[--shape NxMxP\] \[--gate dense|sparse|both\] \[--strict\] \[--batch LISTFILE\] \[--keep-going\] CERTIFICATE...",
             "        --shape SHAPE", "        --gate GATE", "        --strict", "        --batch LISTFILE", "        --keep-going"]
    lines.join("\n") + "\n"

  # JSON string literal as JSON.generate writes it: escape `"`, `\` and control
  # characters, pass every other byte through.
  -> .json_string(text)
    out = StringBuffer()
    out.append("\"")
    start = 0
    i = 0
    size = text.size
    while i < size
      b = text.byte_at(i)
      if b == 34 || b == 92 || b < 32
        out.append(text.slice(start, i - start))
        if b == 34
          out.append("\\\"")
        elsif b == 92
          out.append("\\\\")
        elsif b == 8
          out.append("\\b")
        elsif b == 12
          out.append("\\f")
        elsif b == 10
          out.append("\\n")
        elsif b == 13
          out.append("\\r")
        elsif b == 9
          out.append("\\t")
        else
          out.append("\\u00" + (b < 16 ? "0" : "") + b.to_s(16))
        start = i + 1
      i += 1
    out.append(text.slice(start, size - start))
    out.append("\"")
    out.to_s

  # JSON.pretty_generate of the array of records.
  -> .pretty_json(records)
    out = StringBuffer()
    out.append("\[\n")
    records.each_with_index -> (record, index)
      out.append("  {\n")
      out.append("    \"exact\": true,\n")
      out.append("    \"shape\": " + Metaflip:Gf2:TensorVerifier.json_string(record[:shape]) + ",\n")
      out.append("    \"rank\": " + record[:rank].to_s + ",\n")
      out.append("    \"density\": " + record[:density].to_s + ",\n")
      out.append("    \"sha256\": " + Metaflip:Gf2:TensorVerifier.json_string(record[:sha256]) + ",\n")
      out.append("    \"path\": " + Metaflip:Gf2:TensorVerifier.json_string(record[:path]) + "\n")
      out.append(index + 1 < records.size ? "  },\n" : "  }\n")
    out.append("\]\n")
    out.to_s

  # The long options with their argument arity (1 = takes a value).
  -> .options
    [["--shape", 1], ["--gate", 1], ["--strict", 0], ["--batch", 1], ["--keep-going", 0], ["--help", 0], ["--version", 0]]

  # OptionParser-style completion of a long option name to its unique match.
  -> .complete(name)
    exact = nil
    matches = []
    Metaflip:Gf2:TensorVerifier.options.each -> (entry)
      exact = entry if entry[0] == name
      matches.push(entry) if entry[0].starts_with?(name)
    return exact if exact != nil
    raise "invalid option: [name]" if matches.size == 0
    raise "ambiguous option: [name]" if matches.size > 1
    matches[0]

  # verify_tensor.w [options] CERTIFICATE... -> [status, stdout, stderr].
  # Like verify_tensor.rb: all records or the first failure, and a failing run
  # prints `Tensor verification failed: MESSAGE` on stderr with status 1.
  # --keep-going verifies every certificate, printing the records of the good
  # ones and one failure line per bad one.
  -> .main(args)
    begin
      shape = nil
      gate = :both
      strict = false
      keep_going = false
      batch = nil
      paths = []
      i = 0
      only_paths = false
      while i < args.size
        arg = args[i]
        i += 1
        if only_paths || arg == "-" || !arg.starts_with?("-")
          paths.push([arg, nil])
        elsif arg == "--"
          only_paths = true
        else
          name = arg
          value = nil
          if arg.starts_with?("--")
            equals = Metaflip:Gf2:Scheme.find_byte(arg, 0, 61)
            if equals > 0
              name = arg.slice(0, equals)
              value = arg.slice(equals + 1, arg.size - equals - 1)
            entry = Metaflip:Gf2:TensorVerifier.complete(name)
            name = entry[0]
            if entry[1] == 1 && value == nil
              raise "missing argument: [name]" if i >= args.size
              value = args[i]
              i += 1
            raise "needless argument: [arg]" if entry[1] == 0 && value != nil
          elsif arg == "-h"
            name = "--help"
          elsif arg == "-v"
            name = "--version"
          else
            raise "invalid option: [arg]"
          if name == "--help"
            return [0, Metaflip:Gf2:TensorVerifier.usage, ""]
          if name == "--version"
            return [1, "", "verify_tensor.w: version unknown\n"]
          if name == "--shape"
            Metaflip:Gf2:TensorVerifier.dimensions(value)
            shape = value
          if name == "--gate"
            raise "invalid argument: --gate [value]" if value != "dense" && value != "sparse" && value != "both"
            gate = value.to_sym
          strict = true if name == "--strict"
          keep_going = true if name == "--keep-going"
          batch = value if name == "--batch"
      if batch != nil
        listing = read_file(batch)
        raise "No such file or directory @ rb_sysopen - [batch]" if listing == nil
        listing.split("\n").each -> (raw)
          line = raw
          line = line.slice(0, line.size - 1) if line.size > 0 && line.byte_at(line.size - 1) == 13
          if line != "" && !line.starts_with?("#")
            tab = Metaflip:Gf2:Scheme.find_byte(line, 0, 9)
            if tab >= 0
              paths.push([line.slice(0, tab), line.slice(tab + 1, line.size - tab - 1)])
            else
              paths.push([line, nil])
      raise "provide at least one certificate" if paths.size == 0
      records = []
      failures = ""
      paths.each -> (entry)
        path = entry[0]
        begin
          dims = nil
          if entry[1] != nil
            dims = Metaflip:Gf2:TensorVerifier.dimensions(entry[1])
          elsif shape != nil
            dims = Metaflip:Gf2:TensorVerifier.dimensions(shape)
          elsif !strict
            dims = Metaflip:Gf2:TensorVerifier.dimensions(Metaflip:Gf2:TensorVerifier.infer_shape(path))
          if dims == nil
            records.push(Metaflip:Gf2:TensorVerifier.verify(path, nil, nil, nil, gate, strict))
          else
            records.push(Metaflip:Gf2:TensorVerifier.verify(path, dims[0], dims[1], dims[2], gate, strict))
        rescue failure
          raise failure if !keep_going
          failures = failures + "Tensor verification failed: [path]: [failure]\n"
      status = 0
      status = 1 if failures != ""
      [status, Metaflip:Gf2:TensorVerifier.pretty_json(records), failures]
    rescue failure
      [1, "", "Tensor verification failed: [failure]\n"]
