# Tungsten strings are immutable UTF-8 byte sequences. `size` and `length`
# report bytes; `[]` indexes Unicode code points, using direct O(1) byte access
# when the representation's ASCII bit is set. `slice(start, length)` remains a
# raw byte slice for parsers and codecs.
#
# ASCII literals ('...') accept ASCII bytes only and have no escapes or
# interpolation. They use this same String class: ASCII is a content property
# (a flag every representation carries), so ASCII-only double-quoted and
# dynamically built strings share the same fast paths.
#
# Content views, from raw to rendered:
#
#   String
#   ├─ bytes       lazy StringBytes       O(1) size/[] raw byte reads
#   ├─ codepoints  lazy StringCodepoints  streams the UTF-8 decoder
#   ├─ characters  lazy StringCharacters  single-code-point Strings
#   ├─ graphemes   lazy StringGraphemes   UAX #29 extended clusters
#   └─ lines       lazy StringLines       trailing newlines included
#
# Unicode normalization (nfc/nfd/nfkc/nfkd) implements UAX #15 over
# generated Unicode 16.0.0 tables — see scripts/gen_unicode_tables.py, which
# validates the exact algorithms against Python's unicodedata before
# emitting runtime/unicode_tables.c. Grapheme clustering implements UAX #29
# (GB1-GB13 + GB9c Indic conjuncts), validated against the full UCD
# GraphemeBreakTest.
#
# Some graphemes are composed of multiple code points, and not every code
# point is a grapheme (combining marks, ZWJ). Grapheme is derived from the
# Greek γράφω gráphō ("write"); a glyph is the visual rendering of one.
#
# This file is autoloaded for virtually every program (the 0xF9 String/Symbol
# type-class registration), so bodies here stay dependency-light: methods
# reference only the lazy-view classes and the runtime via ccall — never
# heavyweight core classes.
#
# @author Erik Peterson
+ String
  # Strings and Symbols share runtime dispatch key 0xF9. String WValues
  # already have bit 0 clear; Symbol WValues use that bit as their only type
  # distinction. This is identity for every String storage mode and the exact
  # historical Symbol -> String conversion. Rope receivers are flattened at
  # the established dispatch boundary before this body runs.
  -> to_s
    wvalue_from_bits($value & -2)

  # String modes 0..5 store their byte count directly in bits 1..3. Modes 6
  # and 7 are slab/heap strings and are only constructed for non-empty data;
  # rope receivers are flattened before String type-class dispatch. Therefore
  # mode 0 is exactly the canonical empty string (and empty symbol) encoding.
  -> empty?
    ($value & 14) == 0

  # Preserve the runtime's canonical byte-count boundary, then reproduce
  # w_int exactly. The current result is u32-sized, but the full signed-i48
  # check keeps this source body correct if String storage grows later.
  -> size
    n = ccall_nobox("w_string_byte_length", self) ## i64
    if n >= -140_737_488_355_328 && n <= 140_737_488_355_327
      tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
      mask = 0xFFFFFFFFFFFF ## i64
      return wvalue_from_bits((tag | (n & mask)) ## i64)
    ccall("w_int", n)

  # Keep both aliases independently dispatchable. Forwarding length to size
  # would add another public method lookup to this leaf operation.
  -> length
    n = ccall_nobox("w_string_byte_length", self) ## i64
    if n >= -140_737_488_355_328 && n <= 140_737_488_355_327
      tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
      mask = 0xFFFFFFFFFFFF ## i64
      return wvalue_from_bits((tag | (n & mask)) ## i64)
    ccall("w_int", n)

  # ASCII case transforms, ported from the former runtime IC handlers.
  # Inline-mode receivers (modes 0..5: length in bits 1..3, byte i at bits
  # 4+8i) transform entirely in registers — no allocation at all, where the
  # C handler malloc'd even for "a". Slab/heap receivers walk the raw bytes
  # into one u8[n+1] buffer whose storage the result String then steals
  # (w_string_take_byte_array), matching the C handler's single-buffer
  # cost. Multibyte UTF-8 (bytes >= 0x80) passes through untouched, and a
  # Symbol receiver yields a String (bit 0 cleared), byte-identical to the
  # former C loops.
  -> swapcase
    sw_v = ($value & -2) ## i64
    sw_mode = (sw_v >> 1) & 7
    if sw_mode <= 5
      sw_i = 0
      while sw_i < sw_mode
        sw_sh = 4 + 8 * sw_i
        sw_b = (sw_v >> sw_sh) & 0xFF
        if (sw_b >= 97 && sw_b <= 122) || (sw_b >= 65 && sw_b <= 90)
          sw_v = sw_v ^ (32 << sw_sh)
        sw_i += 1
      return wvalue_from_bits(sw_v)
    sw_n = ccall_nobox("w_string_byte_length", self) ## i64
    sw_out = u8[sw_n + 1]
    sw_src = ccall_nobox("w_string_data_ptr", self) ## i64
    sw_dst = ccall_nobox("w_u8_live_data_ptr", sw_out) ## i64
    sw_i = 0
    while sw_i < sw_n
      sw_b = raw_load_u8(sw_src, sw_i) ## i64
      if sw_b >= 97 && sw_b <= 122
        sw_b -= 32
      elsif sw_b >= 65 && sw_b <= 90
        sw_b += 32
      raw_store_u8(sw_dst, sw_i, sw_b)
      sw_i += 1
    ccall("w_string_take_byte_array", sw_out, sw_n)

  # First byte upcased, every later byte downcased — the former C handler's
  # exact ASCII semantics ("hello World" -> "Hello world").
  -> capitalize
    cp_v = ($value & -2) ## i64
    cp_mode = (cp_v >> 1) & 7
    if cp_mode <= 5
      cp_i = 0
      while cp_i < cp_mode
        cp_sh = 4 + 8 * cp_i
        cp_b = (cp_v >> cp_sh) & 0xFF
        if cp_i == 0 && cp_b >= 97 && cp_b <= 122
          cp_v = cp_v ^ (32 << cp_sh)
        elsif cp_i > 0 && cp_b >= 65 && cp_b <= 90
          cp_v = cp_v ^ (32 << cp_sh)
        cp_i += 1
      return wvalue_from_bits(cp_v)
    cp_n = ccall_nobox("w_string_byte_length", self) ## i64
    cp_out = u8[cp_n + 1]
    cp_src = ccall_nobox("w_string_data_ptr", self) ## i64
    cp_dst = ccall_nobox("w_u8_live_data_ptr", cp_out) ## i64
    cp_i = 0
    while cp_i < cp_n
      cp_b = raw_load_u8(cp_src, cp_i) ## i64
      if cp_i == 0 && cp_b >= 97 && cp_b <= 122
        cp_b -= 32
      elsif cp_i > 0 && cp_b >= 65 && cp_b <= 90
        cp_b += 32
      raw_store_u8(cp_dst, cp_i, cp_b)
      cp_i += 1
    ccall("w_string_take_byte_array", cp_out, cp_n)

  # Reverse by CODEPOINT (multibyte UTF-8 sequences keep their byte order),
  # ported from the former C IC handler. Inline receivers (<= 5 bytes)
  # rebuild the reversed payload directly in $value bits — no allocation;
  # slab/heap receivers walk raw bytes into one u8[n+1] buffer the result
  # steals. The lead byte gives each codepoint's length (0xF0+ = 4, 0xE0+ =
  # 3, 0xC0+ = 2, else 1), clamped to the remaining bytes exactly as the C
  # loop did, so malformed tails degrade identically.
  -> reverse
    rv_v = ($value & -2) ## i64
    rv_mode = (rv_v >> 1) & 7
    if rv_mode <= 5
      rv_res = 0 ## i64
      rv_i = 0
      rv_w = rv_mode
      while rv_i < rv_mode
        rv_b0 = (rv_v >> (4 + 8 * rv_i)) & 0xFF
        rv_clen = 1
        if rv_b0 >= 240
          rv_clen = 4
        elsif rv_b0 >= 224
          rv_clen = 3
        elsif rv_b0 >= 192
          rv_clen = 2
        if rv_clen > rv_mode - rv_i
          rv_clen = rv_mode - rv_i
        rv_w -= rv_clen
        rv_k = 0
        while rv_k < rv_clen
          rv_byte = (rv_v >> (4 + 8 * (rv_i + rv_k))) & 0xFF
          rv_res = rv_res | (rv_byte << (4 + 8 * (rv_w + rv_k)))
          rv_k += 1
        rv_i += rv_clen
      rv_base = (rv_v & -281474976710641) ## i64  # keep tag(48-63) + low nibble(0-3), clear payload
      return wvalue_from_bits((rv_base | rv_res) ## i64)
    # Slab/heap: delegate the codepoint walk to C, which reverses on a single
    # malloc + intern. Building a Tungsten u8[] here would add a WArray-header
    # allocation per call that pushes long strings over budget vs the former
    # handler; the inline fast path above already wins the common short case.
    ccall("w_string_reverse", self)

  # Split into an Array of single-codepoint Strings, ported from the former C
  # IC handler. Each codepoint is at most 4 bytes, so every element is built
  # directly as an inline-mode String in register bits (tag 0xFFF9 | len<<1 |
  # bytes) — no per-character heap allocation, where the C handler called
  # w_string per char. Source bytes come through one borrowed u8[] view
  # (w_string_bytes_view; inline receivers get an owned copy). Lead byte gives
  -> chars
    ccall("w_string_chars", self)

  # Lazy byte view: construction is O(1) and copies nothing. StringBytes is
  # an indexed Enumerable (`size`/`[]` are O(1) reads via byte_at), so
  # subscripting callers keep Array-shaped access without materializing an
  # Array; use to_a for a concrete Array. Multibyte UTF-8 yields its
  # individual bytes.
  -> bytes
    StringBytes.new(self)

  # Eager Array of raw byte values — StringBytes#to_a's native materializer
  # (the pre-view `bytes` body). Inline receivers (<= 5 bytes) read straight
  # from $value bits; slab/heap read through the raw data pointer. Each byte
  # pushes as an immediate Int.
  -> __bytes_array
    by_v = ($value & -2) ## i64
    by_mode = (by_v >> 1) & 7
    out = []
    if by_mode <= 5
      by_i = 0
      while by_i < by_mode
        out.push((by_v >> (4 + 8 * by_i)) & 0xFF)
        by_i += 1
      return out
    by_n = ccall_nobox("w_string_byte_length", self) ## i64
    by_p = ccall_nobox("w_string_data_ptr", self) ## i64
    by_i = 0
    while by_i < by_n
      out.push(raw_load_u8(by_p, by_i))
      by_i += 1
    out

  # Lazy code-point view (Ints). Streaming Enumerable: combinators consume
  # the UTF-8 decoder on demand; to_a materializes.
  -> codepoints
    StringCodepoints.new(self)

  # Lazy single-code-point String view. Streaming Enumerable; the eager
  # `chars` above remains for callers that want a concrete Array in one call.
  -> characters
    StringCharacters.new(self)

  # ASCII uppercase (a-z -> A-Z); bytes >= 0x80 pass through, so multibyte
  # UTF-8 is unchanged — the former C handler's w_string_ascii_case(_, 1)
  # semantics. Inline receivers flip case bits in $value (zero alloc); slab/
  # heap transform into one u8[n+1] buffer the result steals. Same shape as
  # swapcase, one-directional.
  -> upcase
    uc_v = ($value & -2) ## i64
    uc_mode = (uc_v >> 1) & 7
    if uc_mode <= 5
      uc_i = 0
      while uc_i < uc_mode
        uc_sh = 4 + 8 * uc_i
        uc_b = (uc_v >> uc_sh) & 0xFF
        if uc_b >= 97 && uc_b <= 122
          uc_v = uc_v ^ (32 << uc_sh)
        uc_i += 1
      return wvalue_from_bits(uc_v)
    uc_n = ccall_nobox("w_string_byte_length", self) ## i64
    uc_out = u8[uc_n + 1]
    uc_src = ccall_nobox("w_string_data_ptr", self) ## i64
    uc_dst = ccall_nobox("w_u8_live_data_ptr", uc_out) ## i64
    uc_i = 0
    while uc_i < uc_n
      uc_b = raw_load_u8(uc_src, uc_i) ## i64
      if uc_b >= 97 && uc_b <= 122
        uc_b -= 32
      raw_store_u8(uc_dst, uc_i, uc_b)
      uc_i += 1
    ccall("w_string_take_byte_array", uc_out, uc_n)

  # ASCII lowercase (A-Z -> a-z); mirror of upcase.
  -> downcase
    dc_v = ($value & -2) ## i64
    dc_mode = (dc_v >> 1) & 7
    if dc_mode <= 5
      dc_i = 0
      while dc_i < dc_mode
        dc_sh = 4 + 8 * dc_i
        dc_b = (dc_v >> dc_sh) & 0xFF
        if dc_b >= 65 && dc_b <= 90
          dc_v = dc_v ^ (32 << dc_sh)
        dc_i += 1
      return wvalue_from_bits(dc_v)
    dc_n = ccall_nobox("w_string_byte_length", self) ## i64
    dc_out = u8[dc_n + 1]
    dc_src = ccall_nobox("w_string_data_ptr", self) ## i64
    dc_dst = ccall_nobox("w_u8_live_data_ptr", dc_out) ## i64
    dc_i = 0
    while dc_i < dc_n
      dc_b = raw_load_u8(dc_src, dc_i) ## i64
      if dc_b >= 65 && dc_b <= 90
        dc_b += 32
      raw_store_u8(dc_dst, dc_i, dc_b)
      dc_i += 1
    ccall("w_string_take_byte_array", dc_out, dc_n)

  # Padding / alignment. Width is measured in BYTES (like size), so these
  # align ASCII exactly — the dominant use (tables, columns, CLI output). A
  # multi-byte `pad` is repeated then truncated to the exact fill width, and
  # a receiver already at/over `width` is returned unchanged (Ruby semantics).
  -> lpad(width, pad = " ")
    pl_n = size
    if pl_n >= width
      return to_s
    pl_need = width - pl_n
    pl_fill = (pad * pl_need).slice(0, pl_need)
    pl_fill + to_s

  -> rpad(width, pad = " ")
    pr_n = size
    if pr_n >= width
      return to_s
    pr_need = width - pr_n
    pr_fill = (pad * pr_need).slice(0, pr_need)
    to_s + pr_fill

  # Center within `width`; when the total padding is odd the extra byte goes
  # on the right, matching Ruby String#center.
  -> center(width, pad = " ")
    ce_n = size
    if ce_n >= width
      return to_s
    ce_total = width - ce_n
    ce_left = ce_total / 2
    ce_right = ce_total - ce_left
    ce_lf = (pad * ce_left).slice(0, ce_left)
    ce_rf = (pad * ce_right).slice(0, ce_right)
    ce_lf + to_s + ce_rf

  # Remove every character that appears in `set` (Ruby String#delete). `set`
  # is a character SET, not a substring — "hello".delete("lo") -> "he".
  # Codepoint-based via chars, so multibyte content is preserved.
  -> delete(set)
    del_out = StringBuffer(size)
    self.chars.each -> (c)
      if !set.include?(c)
        del_out << c
    del_out.to_s

  # Collapse runs of the same character to one (Ruby String#squeeze):
  # "aaabbbcc" -> "abc".
  -> squeeze
    sq_out = StringBuffer(size)
    sq_prev = nil
    self.chars.each -> (c)
      if c != sq_prev
        sq_out << c
      sq_prev = c
    sq_out.to_s

  # Squeeze only runs of characters that appear in `set`
  # ("aaabbb".squeeze("a") -> "abbb").
  -> squeeze(set)
    sqs_out = StringBuffer(size)
    sqs_prev = nil
    self.chars.each -> (c)
      if !(c == sqs_prev && set.include?(c))
        sqs_out << c
      sqs_prev = c
    sqs_out.to_s

  # Translate characters: each character in `from` maps to the one at the same
  # position in `to`; a shorter `to` repeats its last character, an empty `to`
  # deletes (Ruby String#tr). Literal character lists only — the range (a-z)
  # and negation (^x) shorthands are not yet supported.
  -> tr(from, to)
    tr_from = from.chars
    tr_to = to.chars
    tr_out = StringBuffer(size)
    self.chars.each -> (c)
      tr_idx = -1
      tr_fi = 0
      while tr_fi < tr_from.size
        if tr_from[tr_fi] == c
          tr_idx = tr_fi
          tr_fi = tr_from.size
        else
          tr_fi += 1
      if tr_idx < 0
        tr_out << c
      elsif tr_to.size > 0
        tr_ti = tr_idx
        if tr_ti >= tr_to.size
          tr_ti = tr_to.size - 1
        tr_out << tr_to[tr_ti]
    tr_out.to_s

  # True when every byte is ASCII (< 0x80). Inline receivers derive it from
  # the payload high bits in-register (bits 11/19/27/35/43); slab, heap, and
  # rope representations carry a stored ASCII flag maintained by the runtime
  # constructors, read through one ccall.
  -> ascii?
    as_v = ($value & -2) ## i64
    as_mode = (as_v >> 1) & 7
    if as_mode <= 5
      return (as_v & 0x0000080808080800) == 0
    ccall_nobox("w_string_is_ascii", self) == 1

  # True for the empty string or all-ASCII-whitespace content (space and
  # \t \n \v \f \r, bytes 9-13). Any other byte — multibyte UTF-8 included —
  # is not blank.
  -> blank?
    bl_n = ccall_nobox("w_string_byte_length", self) ## i64
    bl_i = 0
    while bl_i < bl_n
      bl_b = self.byte_at(bl_i)
      if bl_b != 32 && (bl_b < 9 || bl_b > 13)
        return false
      bl_i += 1
    true

  # O(1) byte accessor: the byte value (Int 0-255) at a byte offset, or nil
  # out of bounds. Negative indices count from the end. Bytes, not code
  # points — `[]` is the code-point subscript.
  -> byte_at(index)
    ba_v = ($value & -2) ## i64
    ba_mode = (ba_v >> 1) & 7
    ba_i = index
    if ba_mode <= 5
      if ba_i < 0
        ba_i += ba_mode
      if ba_i < 0 || ba_i >= ba_mode
        return nil
      return (ba_v >> (4 + 8 * ba_i)) & 0xFF
    ba_n = ccall_nobox("w_string_byte_length", self) ## i64
    if ba_i < 0
      ba_i += ba_n
    if ba_i < 0 || ba_i >= ba_n
      return nil
    ba_p = ccall_nobox("w_string_data_ptr", self) ## i64
    raw_load_u8(ba_p, ba_i)

  # Yield each byte (Int 0-255) in order; returns self. Without a block,
  # returns the lazy StringBytes view. Inline receivers read straight from
  # $value bits; slab/heap receivers stream through the raw data pointer.
  -> each_byte(&block)
    if !block?
      return StringBytes.new(self)
    eb_v = ($value & -2) ## i64
    eb_mode = (eb_v >> 1) & 7
    if eb_mode <= 5
      eb_i = 0
      while eb_i < eb_mode
        block((eb_v >> (4 + 8 * eb_i)) & 0xFF)
        eb_i += 1
      return self
    eb_n = ccall_nobox("w_string_byte_length", self) ## i64
    eb_p = ccall_nobox("w_string_data_ptr", self) ## i64
    eb_i = 0
    while eb_i < eb_n
      block(raw_load_u8(eb_p, eb_i))
      eb_i += 1
    self

  # Yield each Unicode code point (Int) in order; returns self. Without a
  # block, returns the lazy StringCodepoints view. The lead byte gives each
  # sequence's length (0xF0+ = 4, 0xE0+ = 3, 0xC0+ = 2, else 1), clamped to
  # the remaining bytes, so malformed tails degrade exactly like the
  # runtime's other UTF-8 walkers (see reverse).
  -> each_codepoint(&block)
    if !block?
      return StringCodepoints.new(self)
    ecp_n = ccall_nobox("w_string_byte_length", self) ## i64
    ecp_i = 0
    while ecp_i < ecp_n
      ecp_b0 = self.byte_at(ecp_i)
      ecp_len = 1
      ecp_cp = ecp_b0
      if ecp_b0 >= 240
        ecp_len = 4
        ecp_cp = ecp_b0 & 7
      elsif ecp_b0 >= 224
        ecp_len = 3
        ecp_cp = ecp_b0 & 15
      elsif ecp_b0 >= 192
        ecp_len = 2
        ecp_cp = ecp_b0 & 31
      if ecp_len > ecp_n - ecp_i
        ecp_len = ecp_n - ecp_i
      ecp_k = 1
      while ecp_k < ecp_len
        ecp_cp = (ecp_cp << 6) | (self.byte_at(ecp_i + ecp_k) & 63)
        ecp_k += 1
      block(ecp_cp)
      ecp_i += ecp_len
    self

  # Yield each line in order, TRAILING NEWLINE INCLUDED (Ruby String#lines
  # semantics); a final unterminated line is yielded as-is. Returns self.
  # Without a block, returns the lazy StringLines view.
  -> each_line(&block)
    if !block?
      return StringLines.new(self)
    el_n = ccall_nobox("w_string_byte_length", self) ## i64
    el_start = 0
    el_i = 0
    while el_i < el_n
      if self.byte_at(el_i) == 10
        block(self.slice(el_start, el_i - el_start + 1))
        el_start = el_i + 1
      el_i += 1
    if el_start < el_n
      block(self.slice(el_start, el_n - el_start))
    self

  # Eager Array of lines (trailing newlines included).
  -> lines
    ln_out = []
    self.each_line -> (l)
      ln_out.push(l)
    ln_out

  # Substring containment — the scaffold's alias for include?, kept as a
  # direct IC hop.
  -> contains?(sub)
    include?(sub)

  # Levenshtein edit distance between self and other, by code point.
  # Two rolling rows of the classic dynamic-programming matrix.
  -> levenshtein(other)
    lv_s = self.codepoints.to_a
    lv_t = other.codepoints.to_a
    if lv_s.size == 0
      return lv_t.size
    if lv_t.size == 0
      return lv_s.size
    lv_n = lv_t.size
    prev = (0..lv_n).to_a
    curr = Array.new(lv_n + 1, 0)
    lv_i = 0
    while lv_i < lv_s.size
      curr[0] = lv_i + 1
      lv_j = 0
      while lv_j < lv_n
        lv_cost = 1
        if lv_s[lv_i] == lv_t[lv_j]
          lv_cost = 0
        lv_ins = curr[lv_j] + 1
        lv_del = prev[lv_j + 1] + 1
        lv_sub = prev[lv_j] + lv_cost
        lv_m = lv_ins
        if lv_del < lv_m
          lv_m = lv_del
        if lv_sub < lv_m
          lv_m = lv_sub
        curr[lv_j + 1] = lv_m
        lv_j += 1
      lv_swap = prev
      prev = curr
      curr = lv_swap
      lv_i += 1
    prev[lv_n]

  # Yield each character (a single-code-point String) in order; returns
  # self. Without a block, returns the lazy StringCharacters view. Same
  # clamped lead-byte walk as each_codepoint; slices stay byte-exact.
  -> each_character(&block)
    if !block?
      return StringCharacters.new(self)
    ech_n = ccall_nobox("w_string_byte_length", self) ## i64
    ech_i = 0
    while ech_i < ech_n
      ech_b0 = self.byte_at(ech_i)
      ech_len = 1
      if ech_b0 >= 240
        ech_len = 4
      elsif ech_b0 >= 224
        ech_len = 3
      elsif ech_b0 >= 192
        ech_len = 2
      if ech_len > ech_n - ech_i
        ech_len = ech_n - ech_i
      block(self.slice(ech_i, ech_len))
      ech_i += ech_len
    self

  # ---- Unicode normalization (UAX #15) --------------------------------

  # Canonical composition. ASCII receivers (flag-checked in the runtime)
  # and invalid UTF-8 return identity.
  -> nfc
    nf_form = 0 ## i64
    ccall("w_string_normalize", self, nf_form)

  # Canonical decomposition.
  -> nfd
    nf_form = 1 ## i64
    ccall("w_string_normalize", self, nf_form)

  # Compatibility composition.
  -> nfkc
    nf_form = 2 ## i64
    ccall("w_string_normalize", self, nf_form)

  # Compatibility decomposition.
  -> nfkd
    nf_form = 3 ## i64
    ccall("w_string_normalize", self, nf_form)

  -> normalize(form = :c)
    case form
    when :c
      nfc
    when :d
      nfd
    when :kc
      nfkc
    when :kd
      nfkd
    else
      raise "normalize: unknown form [form] (use :c, :d, :kc, or :kd)"

  # Canonical equivalence: equal after NFC. `==` stays exact byte equality.
  -> canonically_equivalent?(other)
    nfc == other.nfc

  # ---- Grapheme clusters (UAX #29) ------------------------------------

  # Yield each extended grapheme cluster (String) in order; returns self.
  # Without a block, returns the lazy StringGraphemes view. Combining
  # sequences, Hangul jamo runs, emoji ZWJ sequences, flags, and Indic
  # conjuncts each arrive as one cluster.
  -> each_grapheme(&block)
    if !block?
      return StringGraphemes.new(self)
    eg_n = ccall_nobox("w_string_byte_length", self) ## i64
    eg_i = 0 ## i64
    while eg_i < eg_n
      eg_e = ccall_nobox("w_string_grapheme_next", self, eg_i) ## i64
      block(self.slice(eg_i, eg_e - eg_i))
      eg_i = eg_e
    self

  # Lazy grapheme-cluster view. `chars`/`characters` walk code points;
  # graphemes cluster what a reader perceives as one character.
  -> graphemes
    StringGraphemes.new(self)

  # ---- Pattern scanning ------------------------------------------------

  # All non-overlapping matches, in order (Ruby String#scan). A String
  # pattern collects literal occurrences; a Regex pattern yields the match
  # text, or the captures Array when the pattern has groups. Empty matches
  # advance one code point. The body dispatches dynamically so this file
  # never autoloads the regex engine itself.
  -> scan(pattern)
    out = []
    if type(pattern) == "String"
      sc_len = pattern.size
      if sc_len == 0
        return out
      sc_n = ccall_nobox("w_string_byte_length", self) ## i64
      sc_i = 0
      while sc_i + sc_len <= sc_n
        if self.slice(sc_i, sc_len) == pattern
          out.push(pattern.to_s)
          sc_i += sc_len
        else
          sc_i += 1
      return out
    if ccall_nobox("w_is_native_regex", pattern) == 1
      return ccall("w_regex_scan", pattern, self)
    sc_pos = 0
    loop
      m = pattern.match_data_from(self, sc_pos)
      if m == nil
        break
      if m.size > 1
        out.push(m.captures)
      else
        out.push(m.match)
      sc_end = m.end_offset(0)
      if sc_end == m.begin_offset(0)
        sc_pos = sc_end + 1
      else
        sc_pos = sc_end
    out

  # ---- Mathematical alphanumerics -------------------------------------

  # Replace ASCII letters (and digits, where the target block has them)
  # with their Mathematical Alphanumeric Symbols equivalents, including the
  # Letterlike Symbols exceptions (script H is U+210B, not the reserved
  # U+1D4A3 slot, and so on). Styles combine per the Unicode chart:
  # bold pairs with italic, script, fraktur, or sansserif; italic pairs
  # with sansserif; double_struck and monospace stand alone.
  -> astralize(bold: false, italic: false, script: false, fraktur: false, double_struck: false, sansserif: false, monospace: false)
    if italic && (script || fraktur || monospace || double_struck)
      raise "astralize: italic combines only with bold or sansserif"
    if bold && monospace
      raise "astralize: bold cannot combine with monospace"
    if bold && double_struck
      raise "astralize: bold cannot combine with double_struck"
    az_fams = 0
    if script
      az_fams += 1
    if fraktur
      az_fams += 1
    if double_struck
      az_fams += 1
    if sansserif
      az_fams += 1
    if monospace
      az_fams += 1
    if az_fams > 1
      raise "astralize: pick at most one of script, fraktur, double_struck, sansserif, monospace"
    az_style = 0
    if monospace
      az_style = 13
    elsif double_struck
      az_style = 8
    elsif script
      az_style = bold ? 5 : 4
    elsif fraktur
      az_style = bold ? 7 : 6
    elsif sansserif
      if bold && italic
        az_style = 12
      elsif bold
        az_style = 10
      elsif italic
        az_style = 11
      else
        az_style = 9
    elsif bold && italic
      az_style = 3
    elsif bold
      az_style = 1
    elsif italic
      az_style = 2
    if az_style == 0
      return to_s
    az_out = StringBuffer(size * 4)
    self.each_codepoint -> (cp)
      az_out << __astral_cp(cp, az_style).chr
    az_out.to_s

  # One code point through the astralize style map. Style ids: 1 bold,
  # 2 italic, 3 bold-italic, 4 script, 5 bold-script, 6 fraktur,
  # 7 bold-fraktur, 8 double-struck, 9 sans, 10 sans-bold, 11 sans-italic,
  # 12 sans-bold-italic, 13 monospace. The exception arms are exactly the
  # reserved holes in the U+1D400 block (verified against Unicode 16 names).
  -> __astral_cp(cp, style)
    if cp >= 65 && cp <= 90
      if style == 4
        case cp
        when 66
          return 0x212C
        when 69
          return 0x2130
        when 70
          return 0x2131
        when 72
          return 0x210B
        when 73
          return 0x2110
        when 76
          return 0x2112
        when 77
          return 0x2133
        when 82
          return 0x211B
      elsif style == 6
        case cp
        when 67
          return 0x212D
        when 72
          return 0x210C
        when 73
          return 0x2111
        when 82
          return 0x211C
        when 90
          return 0x2128
      elsif style == 8
        case cp
        when 67
          return 0x2102
        when 72
          return 0x210D
        when 78
          return 0x2115
        when 80
          return 0x2119
        when 81
          return 0x211A
        when 82
          return 0x211D
        when 90
          return 0x2124
      az_upper = [0x1D400, 0x1D434, 0x1D468, 0x1D49C, 0x1D4D0, 0x1D504, 0x1D56C, 0x1D538, 0x1D5A0, 0x1D5D4, 0x1D608, 0x1D63C, 0x1D670]
      return az_upper[style - 1] + (cp - 65)
    if cp >= 97 && cp <= 122
      if style == 2 && cp == 104
        return 0x210E
      if style == 4
        case cp
        when 101
          return 0x212F
        when 103
          return 0x210A
        when 111
          return 0x2134
      az_lower = [0x1D41A, 0x1D44E, 0x1D482, 0x1D4B6, 0x1D4EA, 0x1D51E, 0x1D586, 0x1D552, 0x1D5BA, 0x1D5EE, 0x1D622, 0x1D656, 0x1D68A]
      return az_lower[style - 1] + (cp - 97)
    if cp >= 48 && cp <= 57
      if style == 1
        return 0x1D7CE + (cp - 48)
      if style == 8
        return 0x1D7D8 + (cp - 48)
      if style == 9
        return 0x1D7E2 + (cp - 48)
      if style == 10
        return 0x1D7EC + (cp - 48)
      if style == 13
        return 0x1D7F6 + (cp - 48)
    cp

  # ---- Inflections -----------------------------------------------------

  # snake_case (or kebab-case / spaced words) to CamelCase.
  -> camelize
    cm_out = StringBuffer(size)
    cm_up = true
    self.chars.each -> (c)
      if c == "_" || c == "-" || c == " "
        cm_up = true
      elsif cm_up
        cm_out << c.upcase
        cm_up = false
      else
        cm_out << c
    cm_out.to_s

  # CamelCase to snake_case, splitting acronym runs at the last capital
  # ("HTTPServer" -> "http_server"); dashes normalize to underscores.
  -> underscore
    us_chars = self.chars
    us_out = StringBuffer(size + 8)
    us_n = us_chars.size
    us_i = 0
    while us_i < us_n
      us_c = us_chars[us_i]
      us_o = us_c.ord
      if us_o >= 65 && us_o <= 90
        us_prev = 0
        if us_i > 0
          us_prev = us_chars[us_i - 1].ord
        us_next = 0
        if us_i + 1 < us_n
          us_next = us_chars[us_i + 1].ord
        us_prev_soft = (us_prev >= 97 && us_prev <= 122) || (us_prev >= 48 && us_prev <= 57)
        us_prev_upper = us_prev >= 65 && us_prev <= 90
        us_next_lower = us_next >= 97 && us_next <= 122
        if us_i > 0 && (us_prev_soft || (us_prev_upper && us_next_lower))
          us_out << "_"
        us_out << (us_o + 32).chr
      elsif us_c == "-"
        us_out << "_"
      else
        us_out << us_c
      us_i += 1
    us_out.to_s

  # Alias for underscore (one dispatch hop; cosmetic spelling).
  -> snakecase
    underscore

  -> dasherize
    replace("_", "-")

  # "employee_salary" -> "Employee salary".
  -> humanize
    replace("_", " ").capitalize

  # ASCII approximation: NFKD-decompose, drop combining marks, fold the
  # common Latin letters with no decomposition (æ ø ß đ ħ ı ł œ þ ð ŧ),
  # normalize typographic punctuation, and substitute `replacement` for
  # whatever non-ASCII remains.
  -> transliterate(replacement = "?")
    tl_out = StringBuffer(size)
    nfkd.each_codepoint -> (cp)
      if cp < 128
        tl_out << cp.chr
      elsif (cp >= 0x300 && cp <= 0x36F) || (cp >= 0x1AB0 && cp <= 0x1AFF) || (cp >= 0x1DC0 && cp <= 0x1DFF) || (cp >= 0x20D0 && cp <= 0x20FF) || (cp >= 0xFE20 && cp <= 0xFE2F)
        tl_out << ""
      else
        tl_f = __translit_fold(cp)
        if tl_f == nil
          tl_out << replacement
        else
          tl_out << tl_f
    tl_out.to_s

  -> __translit_fold(cp)
    case cp
    when 0xC6
      "AE"
    when 0xE6
      "ae"
    when 0xD0
      "D"
    when 0xF0
      "d"
    when 0xD8
      "O"
    when 0xF8
      "o"
    when 0xDE
      "TH"
    when 0xFE
      "th"
    when 0xDF
      "ss"
    when 0x110
      "D"
    when 0x111
      "d"
    when 0x126
      "H"
    when 0x127
      "h"
    when 0x131
      "i"
    when 0x141
      "L"
    when 0x142
      "l"
    when 0x152
      "OE"
    when 0x153
      "oe"
    when 0x166
      "T"
    when 0x167
      "t"
    when 0x2018
      "'"
    when 0x2019
      "'"
    when 0x201C
      "\""
    when 0x201D
      "\""
    when 0x2013
      "-"
    when 0x2014
      "-"
    when 0x2026
      "..."
    when 0xAB
      "\""
    when 0xBB
      "\""
    else
      nil

  # URL slug: transliterate, lowercase, collapse every non-alphanumeric run
  # to one separator, and trim separators from both ends.
  -> parameterize(separator = "-")
    pa_src = transliterate("").downcase
    pa_out = StringBuffer(size)
    pa_pending = false
    pa_started = false
    pa_src.each_byte -> (b)
      if (b >= 97 && b <= 122) || (b >= 48 && b <= 57)
        if pa_pending && pa_started
          pa_out << separator
        pa_pending = false
        pa_started = true
        pa_out << b.chr
      else
        pa_pending = true
    pa_out.to_s

  # Scaffold-canonical case names (single delegation hop; downcase/upcase
  # remain the primary spellings).
  -> lowercase
    downcase

  -> uppercase
    upcase

  -> includes?(sub)
    include?(sub)

  # Compile a Regex that matches this string LITERALLY (metacharacters
  # escaped), through the native engine constructor — no source-regex
  # autoload from this file.
  -> to_regex
    rx_out = StringBuffer(size * 2)
    self.each_character -> (c)
      rx_o = c.ord
      if rx_o == 94 || rx_o == 36 || rx_o == 46 || rx_o == 124 || rx_o == 63 || rx_o == 42 || rx_o == 43 || rx_o == 40 || rx_o == 41 || rx_o == 91 || rx_o == 93 || rx_o == 123 || rx_o == 125 || rx_o == 92
        rx_out << "\\"
      rx_out << c
    ccall("w_regex_new", rx_out.to_s, "")

  # Resolve a registered class by name ("Array".constantize.new). Only
  # classes compiled into the running binary can resolve — an AOT program
  # has no runtime load path — so an unknown or unlinked name raises.
  -> constantize
    cz = ccall("w_class_by_name", self)
    if cz == nil
      raise "constantize: uninitialized or unlinked constant [self]"
    cz

  # Functional index write: the code point at `index` replaced by `value`,
  # returned as a mutable StringBuffer (the receiver is immutable — take
  # .to_s for a String, or keep editing the buffer). Negative indices count
  # from the end; out of range raises.
  -> []=(index, value)
    ia_n = 0
    self.each_codepoint -> (cp)
      ia_n += 1
    ia_i = index
    if ia_i < 0
      ia_i += ia_n
    if ia_i < 0 || ia_i >= ia_n
      raise "[]=: index [index] out of range for [ia_n]-code-point string"
    ia_out = StringBuffer(size + value.size)
    ia_k = 0
    self.each_character -> (c)
      if ia_k == ia_i
        ia_out << value
      else
        ia_out << c
      ia_k += 1
    ia_out

# ---- Native (runtime IC) surface --------------------------------------
# Dispatched by C handlers in w_ic_string_table (see
# scripts/check-core-dispatch-contracts.rb for the authoritative list):
#   [] << =~ append codes concat ends_with? gsub include? index lchs length
#   ltrim match? ord prepend repeat replace rindex rtrim size slice split
#   starts_with? strip to_d to_f to_i to_sym valid_utf8?
#
# ---- Operators ---------------------------------------------------------
# `a ≈ b` (canonical equivalence) is handled by the runtime approx-compare:
# w_approx_eq NFC-normalizes String/Symbol operands (see runtime.c), so the
# operator and canonically_equivalent? agree.
#
# ---- Wishlist ----------------------------------------------------------
# Declared in earlier designs, still unimplemented:
#   each_paragraph, indexes, seek, to_a/to_args/to_b/to_c/to_m/to_r,
#   trim(pattern), is Comparable/Printable/Debuggable conformances
