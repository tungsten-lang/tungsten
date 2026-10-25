# Allocation-bounded proof scanners.
#
# The original parser split the complete proof into lines, split every line
# into token Strings, then retained every parsed step until replay began.  A
# certificate is naturally a stream: only the current literals and hint chain
# have to be live.  These scanners operate directly on a borrowed u8[] view
# (a String or mmap) and expose one record at a time.
#
# Text accepts WRAT 1, LRAT and DRAT.  The packed WRATB 1 form is:
#
#   "WRATB" 0x01
#   uvarint(first_addition_id)
#   records...
#   0x00
#
#   addition: 0x01, zigzag(literals)..., 0,
#                    zigzag(delta hints)+1..., 0
#   deletion: 0x02, zigzag(delta ids)+1..., 0
#
# Addition ids are implicit and sequential.  Hint deltas start at the current
# addition id; deletion deltas start at the most recent addition id.  Each
# later delta starts at the preceding referenced id.  The +1 reserves zero as
# a list terminator while still permitting repeated ids.

use core/mmap

WRATB_MAGIC_SIZE = 6

# Shared read-only accessors consumed by WratChecker#check_stream.
+ WratProofScanner
  ro :format, :version, :kind, :id, :lits, :hints, :records, :size

  -> bytesize
    @size

  ro :peak_record_literals, :peak_record_hints, :literal_tokens, :hint_tokens

  -> hinted?
    @format != "drat"

  -> count_record
    @records += 1
    lsize = @lits.size
    hsize = @hints.size
    @literal_tokens += lsize
    @hint_tokens += hsize
    @peak_record_literals = lsize if lsize > @peak_record_literals
    @peak_record_hints = hsize if hsize > @peak_record_hints

# Text WRAT/LRAT/DRAT scanner over a byte-indexed source.
+ WratTextProof < WratProofScanner
  ro :bytes, :pos, :line, :line_start, :line_end, :cursor

  -> new(@bytes)
    @size = @bytes.size
    @pos = 0
    @line = 0
    @line_start = 0
    @line_end = 0
    @cursor = 0
    @kind = ""
    @id = 0
    @lits = []
    @hints = []
    @records = 0
    @literal_tokens = 0
    @hint_tokens = 0
    @peak_record_literals = 0
    @peak_record_hints = 0
    @format = "drat"
    @version = 0
    self.detect_format

  -> whitespace?(b)
    b == 32 || (b >= 9 && b <= 13 && b != 10)

  -> skip_space
    bytes = @bytes
    c = @cursor
    le = @line_end
    while c < le
      b = bytes[c]
      break unless b == 32 || (b >= 9 && b <= 13 && b != 10)
      c += 1
    @cursor = c

  -> at_line_end?
    self.skip_space
    @cursor >= @line_end

  -> fail_parse(message)
    raise "proof line [@line]: [message]"

  # Advance to the next nonblank, non-comment line.  Comments are recognized
  # only when `c` is the first non-whitespace byte, matching DIMACS/WRAT.
  -> find_data_line
    bytes = @bytes
    sz = @size
    pos = @pos
    line = @line
    found = false
    while pos < sz && !found
      ls = pos
      le = pos
      while le < sz && bytes[le] != 10
        le += 1
      pos = le < sz ? le + 1 : le
      line += 1

      i = ls
      while i < le
        b = bytes[i]
        break unless b == 32 || (b >= 9 && b <= 13 && b != 10)
        i += 1
      found = i < le && bytes[i] != 99
      if found || pos >= sz
        @line_start = ls
        @line_end = le
    @pos = pos
    @line = line
    found

  -> byte_word?(at, a, b, c, d)
    room = at + 4 <= @line_end
    room && @bytes[at] == a && @bytes[at + 1] == b && @bytes[at + 2] == c && @bytes[at + 3] == d

  -> read_integer
    bytes = @bytes
    c = @cursor
    le = @line_end
    while c < le
      b = bytes[c]
      break unless b == 32 || (b >= 9 && b <= 13 && b != 10)
      c += 1
    if c >= le
      @cursor = c
      self.fail_parse("expected an integer")

    sign = 1
    b = bytes[c]
    if b == 45 || b == 43
      sign = -1 if b == 45
      c += 1
    if c >= le
      @cursor = c
      self.fail_parse("sign is not followed by digits")

    value = 0
    digits = 0
    while c < le
      b = bytes[c]
      break unless b >= 48 && b <= 57
      value = value * 10 + b - 48
      digits += 1
      c += 1
    @cursor = c
    self.fail_parse("expected decimal digits") if digits == 0
    if c < le
      b = bytes[c]
      unless b == 32 || (b >= 9 && b <= 13 && b != 10)
        self.fail_parse("invalid byte after integer")
    sign < 0 ? 0 - value : value

  -> deletion_marker?
    self.skip_space
    return false if @cursor >= @line_end || @bytes[@cursor] != 100
    after = @cursor + 1
    after >= @line_end || self.whitespace?(@bytes[after])

  -> consume_deletion_marker
    self.fail_parse("expected deletion marker") unless self.deletion_marker?
    @cursor += 1

  -> read_zero_terminated(into)
    terminated = false
    while !self.at_line_end? && !terminated
      value = self.read_integer
      if value == 0
        terminated = true
      else
        into.push(value)
    self.fail_parse("unterminated integer list") unless terminated

  -> parse_header
    @cursor = @line_start
    self.skip_space
    unless self.byte_word?(@cursor, 119, 114, 97, 116)
      self.fail_parse("malformed WRAT header")
    @cursor += 4
    if @cursor < @line_end && !self.whitespace?(@bytes[@cursor])
      self.fail_parse("malformed WRAT header")
    version = self.read_integer
    self.fail_parse("unsupported WRAT version [version]") unless version == 1
    self.fail_parse("trailing bytes after WRAT header") unless self.at_line_end?
    @format = "wrat"
    @version = version

  -> detect_unheaded_format
    @cursor = @line_start
    self.skip_space
    if self.deletion_marker?
      @format = "drat"
      return

    self.read_integer
    self.skip_space
    if self.deletion_marker?
      @format = "lrat"
      @version = 1
      return

    zeros = 0
    while !self.at_line_end?
      zeros += 1 if self.read_integer == 0
    @format = zeros >= 2 ? "lrat" : "drat"
    @version = @format == "lrat" ? 1 : 0

  -> detect_format
    if self.find_data_line
      @cursor = @line_start
      self.skip_space
      if self.byte_word?(@cursor, 119, 114, 97, 116)
        self.parse_header
      else
        self.detect_unheaded_format
        # Revisit the first proof line during advance.
        @pos = @line_start
        @line -= 1
    else
      @format = "drat"

  -> parse_hinted_line
    @cursor = @line_start
    @id = self.read_integer
    self.fail_parse("proof ids must be positive") if @id <= 0
    @lits = []
    @hints.pop while @hints.size > 0

    if self.deletion_marker?
      @kind = "d"
      self.consume_deletion_marker
      self.read_zero_terminated(@hints)
    else
      @kind = "a"
      self.read_zero_terminated(@lits)
      self.read_zero_terminated(@hints)
    self.fail_parse("trailing tokens after record") unless self.at_line_end?

  -> parse_drat_line
    @cursor = @line_start
    @id = 0
    @lits = []
    @hints.pop while @hints.size > 0
    if self.deletion_marker?
      @kind = "d"
      self.consume_deletion_marker
    else
      @kind = "a"
    self.read_zero_terminated(@lits)
    self.fail_parse("trailing tokens after record") unless self.at_line_end?

  -> advance
    return false unless self.find_data_line
    if @format == "drat"
      self.parse_drat_line
    else
      self.parse_hinted_line
    self.count_record
    true

# Packed WRATB scanner.  It shares the same per-record surface as text.
+ WratBinaryProof < WratProofScanner
  ro :bytes, :pos, :next_id, :ended

  -> new(@bytes)
    @size = @bytes.size
    self.fail_binary("truncated header") if @size < WRATB_MAGIC_SIZE
    if @bytes[0] != 87 || @bytes[1] != 82 || @bytes[2] != 65 || @bytes[3] != 84 || @bytes[4] != 66 || @bytes[5] != 1
      self.fail_binary("bad magic or unsupported version")

    @pos = WRATB_MAGIC_SIZE
    @next_id = self.read_uvarint
    self.fail_binary("first addition id must be positive") if @next_id <= 0
    @format = "wratb"
    @version = 1
    @kind = ""
    @id = 0
    @lits = []
    @hints = []
    @records = 0
    @literal_tokens = 0
    @hint_tokens = 0
    @peak_record_literals = 0
    @peak_record_hints = 0
    @ended = false

  -> fail_binary(message)
    raise "packed proof byte [@pos || 0]: [message]"

  -> read_uvarint
    bytes = @bytes
    pos = @pos
    sz = @size
    value = 0
    shift = 0
    more = true
    while more
      if pos >= sz
        @pos = pos
        self.fail_binary("truncated varint")
      byte = bytes[pos]
      pos += 1
      value = value | ((byte & 127) << shift)
      more = (byte & 128) != 0
      shift += 7
      if shift > 63 && more
        @pos = pos
        self.fail_binary("varint exceeds 63 bits")
    @pos = pos
    value

  -> zigzag_decode(value)
    (value & 1) == 0 ? (value >> 1) : 0 - ((value + 1) >> 1)

  -> read_literal_list(out)
    done = false
    while !done
      code = self.read_uvarint
      if code == 0
        done = true
      else
        lit = self.zigzag_decode(code)
        self.fail_binary("zero literal has a nonzero encoding") if lit == 0
        out.push(lit)
    out

  -> read_reference_list(out, origin)
    previous = origin
    done = false
    while !done
      code = self.read_uvarint
      if code == 0
        done = true
      else
        delta = self.zigzag_decode(code - 1)
        cid = previous - delta
        self.fail_binary("decoded clause id must be positive") if cid <= 0
        out.push(cid)
        previous = cid
    out

  -> advance
    return false if @ended
    self.fail_binary("missing end marker") if @pos >= @size
    tag = @bytes[@pos]
    @pos += 1

    if tag == 0
      @ended = true
      self.fail_binary("trailing bytes after end marker") if @pos != @size
      return false
    elsif tag == 1
      @kind = "a"
      @id = @next_id
      @next_id += 1
      @lits = []
      self.read_literal_list(@lits)
      @hints.pop while @hints.size > 0
      self.read_reference_list(@hints, @id)
    elsif tag == 2
      @kind = "d"
      @id = 0
      @lits = []
      @hints.pop while @hints.size > 0
      self.read_reference_list(@hints, @next_id - 1)
    else
      self.fail_binary("unknown record tag [tag]")
    self.count_record
    true

-> wrat_binary_magic?(bytes)
  return false if bytes.size < WRATB_MAGIC_SIZE
  bytes[0] == 87 && bytes[1] == 82 && bytes[2] == 65 && bytes[3] == 84 && bytes[4] == 66 && bytes[5] == 1

-> wrat_scanner_for_bytes(bytes)
  wrat_binary_magic?(bytes) ? WratBinaryProof.new(bytes) : WratTextProof.new(bytes)

-> wrat_scanner_for_text(text)
  bytes = ccall("w_string_bytes_view", text) ## u8[]
  wrat_scanner_for_bytes(bytes)

-> wrat_scanner_for_mmap(mapping)
  wrat_scanner_for_bytes(mapping.as_u8)
