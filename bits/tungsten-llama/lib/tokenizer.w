# BPE tokenizer loaded from GGUF metadata or HuggingFace tokenizer.json.
#
# qwen3 is a GPT-2-style BPE tokenizer (model="gpt2", pre="qwen2"):
#   - vocab: 151936 tokens. GGUF stores them as `tokenizer.ggml.tokens`
#     strings; tokenizer.json as a `model.vocab` map of {token → id}.
#     Bytes 0-32, 127-160, 173 are escaped via the GPT-2 byte→unicode
#     mapping (e.g. space → 'Ġ' = U+0120) so every token is a printable
#     UTF-8 string with no embedded NUL. The byte-level form is identical
#     in both encodings, so encode/decode work without a representation
#     conversion at the token-string level.
#   - merges: 151387 BPE merge rules. GGUF: `tokenizer.ggml.merges` array
#     of "a b" strings. tokenizer.json: `model.merges` array of [a,b] pairs.
#     Lower index = higher priority during encoding.
#   - special ids: bos/eos/pad. GGUF stashes them as scalar metadata;
#     tokenizer.json puts them in `added_tokens` with content + id.
#
# The qwen2 pretokenizer regex is implemented as a hand-rolled scanner
# (`pretokenize`) over the pattern's seven alternatives, with Unicode
# L/M/N category tables generated into tokenizer_categories.w. Validated
# against HF `tokenizers` on a 2842-string multilingual corpus
# (scripts/bench/check placed under scratchpad during bring-up).

use tungsten-llama/bin_reader
use tungsten-llama/tokenizer_categories

in Tungsten:Llama

# Internal shim: a hash-backed object that quacks like a GGUF for the
# Tokenizer constructor. Lets `from_tokenizer_json` reuse the same
# instance setup without an alternate `new` overload.
+ TokenizerSource
  rw :metadata

  -> new(@metadata)

# Encode a Unicode codepoint as a UTF-8 string. Wraps the raw ccall so
# args are boxed through the normal call convention (calling ccall
# directly from the tokenizer was passing :raw_int literals which the
# C side then sees as unboxed.)
fn cp_to_utf8_char(cp)
  ccall("w_string_from_codepoint", cp)

# Build a one-byte string from a raw byte (0..255). Concatenating these
# yields valid UTF-8 only if the caller emits bytes in proper sequence
# (which decode does — each output byte comes from cp_to_byte and is
# the original input byte). Used by decode so multi-byte UTF-8 chars
# round-trip without double-framing.
fn byte_to_str(b)
  ccall("w_string_from_byte", b)

# Binary search over a flattened [start, end] codepoint range table.
fn tok_in_ranges(cp, table)
  lo = 0
  hi = table.size() / 2 - 1
  while lo <= hi
    mid = (lo + hi) / 2
    if cp < table[mid * 2]
      hi = mid - 1
    elsif cp > table[mid * 2 + 1]
      lo = mid + 1
    else
      return true
  false

fn tok_is_letter(cp)
  tok_in_ranges(cp, TOK_CAT_L)

fn tok_is_mark(cp)
  tok_in_ranges(cp, TOK_CAT_M)

fn tok_is_number(cp)
  tok_in_ranges(cp, TOK_CAT_N)

# Onig \s: ASCII whitespace + NEL/NBSP + Unicode space separators.
fn tok_is_ws(cp)
  return true if cp == 32 || (cp >= 9 && cp <= 13)
  return true if cp == 0x85 || cp == 0xA0 || cp == 0x1680
  return true if cp >= 0x2000 && cp <= 0x200A
  return true if cp == 0x2028 || cp == 0x2029 || cp == 0x202F || cp == 0x205F || cp == 0x3000
  false

fn tok_is_crlf(cp)
  cp == 13 || cp == 10

+ Tokenizer
  rw :tokens          # Array(String), id → token
  rw :merges          # Array(String) of "a b" merge rules
  rw :merge_rank      # Hash{String → i32} where key="a b", value=rank
  rw :token_id        # Hash{String → i32} reverse vocab lookup
  rw :bos_id
  rw :eos_id
  rw :pad_id
  rw :byte_to_uchar   # Array(String) length 256 — byte → UTF-8 char string
  rw :cp_to_byte      # Hash{int → int} unicode codepoint → original byte

  -> new(gguf)
    @tokens = gguf.metadata["tokenizer.ggml.tokens"]
    @merges = gguf.metadata["tokenizer.ggml.merges"]
    @bos_id = gguf.metadata["tokenizer.ggml.bos_token_id"]
    @eos_id = gguf.metadata["tokenizer.ggml.eos_token_id"]
    @pad_id = gguf.metadata["tokenizer.ggml.padding_token_id"]
    build_merge_rank()
    build_token_index()
    build_byte_unicode()

  # Load a packed BPE tokenizer (see tokenizer_pack.py).
  #
  # Packed format (all little-endian):
  #   magic        4 bytes "TBPE"
  #   vocab_count  u32
  #   merges_count u32
  #   added_count  u32
  #   bos_id       i32   (-1 = none)
  #   eos_id       i32
  #   pad_id       i32
  #   vocab        vocab_count × { u32 id, u16 len, len × u8 token_bytes }
  #   merges       merges_count × { u16 a_len, a_len × u8, u16 b_len, b_len × u8 }
  #   added        added_count × { u32 id, u16 len, len × u8 token_bytes }
  #
  # The packed form exists because the pure-Tungsten JSON parser
  # (core/json) is O(N²) in memory on `s.chars[pos]` and OOMs on the
  # 11 MB tokenizer.json. Convert once with bits/tungsten-llama/scripts/
  # tokenizer_pack.py — the caller (REPL, build step) is responsible
  # for ensuring the packed cache exists before invoking the server.
  -> .from_packed_tokenizer(path)
    raw = read_file(path)
    bs = ByteSlice.new(raw)
    r = BinReader.new(bs)

    magic = bs.byte_at(0).to_s + "," + bs.byte_at(1).to_s + "," + bs.byte_at(2).to_s + "," + bs.byte_at(3).to_s
    if magic != "84,66,80,69"   # "TBPE"
      raise "Tokenizer.from_packed_tokenizer: bad magic in " + path
    r.skip(4)

    vocab_count  = r.read_u32
    merges_count = r.read_u32
    added_count  = r.read_u32
    bos_id_raw   = r.read_i32
    eos_id_raw   = r.read_i32
    pad_id_raw   = r.read_i32

    bos_id = nil
    eos_id = nil
    pad_id = nil
    if bos_id_raw >= 0
      bos_id = bos_id_raw
    if eos_id_raw >= 0
      eos_id = eos_id_raw
    if pad_id_raw >= 0
      pad_id = pad_id_raw

    # Compute max id so we can size the tokens array up front.
    # Vocab + added IDs are bounded by their explicit id fields.
    tokens = []

    i = 0
    while i < vocab_count
      id   = r.read_u32
      blen = r.read_u16
      str  = r.read_string(blen)
      while tokens.size <= id
        tokens.push("")
      tokens[id] = str
      i = i + 1

    merges = []
    i = 0
    while i < merges_count
      a_len = r.read_u16
      a     = r.read_string(a_len)
      b_len = r.read_u16
      b     = r.read_string(b_len)
      merges.push(a + " " + b)
      i = i + 1

    i = 0
    while i < added_count
      id   = r.read_u32
      blen = r.read_u16
      str  = r.read_string(blen)
      while tokens.size <= id
        tokens.push("")
      tokens[id] = str
      i = i + 1

    metadata = {
      "tokenizer.ggml.tokens": tokens,
      "tokenizer.ggml.merges": merges,
      "tokenizer.ggml.bos_token_id": bos_id,
      "tokenizer.ggml.eos_token_id": eos_id,
      "tokenizer.ggml.padding_token_id": pad_id
    }
    Tokenizer.new(TokenizerSource.new(metadata))

  -> build_merge_rank
    @merge_rank = {}
    i = 0
    while i < @merges.size()
      @merge_rank[@merges[i]] = i
      i = i + 1

  -> build_token_index
    @token_id = {}
    i = 0
    while i < @tokens.size()
      @token_id[@tokens[i]] = i
      i = i + 1

  # GPT-2 byte→unicode: bytes 33-126, 161-172, 174-255 map to themselves
  # (printable in latin-1); the rest get codepoints 256..323. The result
  # is then double-encoded as Latin-1 — qwen3's GGUF stores token strings
  # such that each byte of the GPT-2 UTF-8 representation appears as its
  # own Latin-1 character. Example: GPT-2 'Ġ' = U+0120 → UTF-8 [C4 A0]
  # → stored string has codepoints [0xC4, 0xA0] → bytes [C3 84 C2 A0].
  -> build_byte_unicode
    @byte_to_uchar = []
    @cp_to_byte = {}
    next_remap = 256
    b = 0
    while b < 256
      if (b >= 33 && b <= 126) || (b >= 161 && b <= 172) || (b >= 174 && b <= 255)
        cp = b
      else
        cp = next_remap
        next_remap = next_remap + 1
      # Build the qwen3-stored representation of this GPT-2 codepoint:
      # UTF-8 encode to bytes, then emit each byte as a Latin-1 char.
      sb = StringBuffer(4)
      if cp < 128
        sb << cp_to_utf8_char(cp)
      else
        sb << cp_to_utf8_char(0xC0 | (cp >> 6))
        sb << cp_to_utf8_char(0x80 | (cp & 0x3F))
      @byte_to_uchar.push(sb.to_s)
      @cp_to_byte[cp] = b
      b = b + 1

  # Convert a byte string to its GPT-2 byte-unicode representation
  # (one unicode codepoint per input byte). Returns an array of
  # single-codepoint strings, ready for BPE merging.
  -> bytes_to_chars(s)
    out = []
    bytes = s.bytes.to_a
    i = 0
    while i < bytes.size()
      out.push(@byte_to_uchar[bytes[i]])
      i = i + 1
    out

  # Apply BPE merges to a single chunk (already in byte-unicode form).
  # Greedy: repeatedly find the lowest-rank adjacent pair, merge it.
  #
  # Nil-marking variant (cf. languages/openai/tokenizer.w bpe_encode_chunk):
  # instead of rebuilding the parts array on every merge (O(n) per step),
  # we mark merged-out elements as nil and skip them in subsequent scans.
  # The scan walks "live" pairs by advancing past nils. Final compaction
  # at the end strips the nils.
  -> bpe(chars)
    n = chars.size()
    return chars if n < 2

    # Fast path: 2-char chunk. One possible merge to check.
    if n == 2
      key = chars[0] + " " + chars[1]
      if @merge_rank[key] != nil
        return [chars[0] + chars[1]]
      return chars

    parts = []
    i = 0
    while i < n
      parts.push(chars[i])
      i = i + 1

    loop
      best_rank = 1000000000
      best_idx = -1
      best_next_idx = -1
      best_merged = nil

      i = 0
      while i < n && parts[i] == nil
        i = i + 1
      break if i >= n

      j = i + 1
      while j < n
        if parts[j] != nil
          key = parts[i] + " " + parts[j]
          r = @merge_rank[key]
          if r != nil && r < best_rank
            best_rank = r
            best_idx = i
            best_next_idx = j
            best_merged = parts[i] + parts[j]
          i = j
        j = j + 1

      break if best_idx == -1

      parts[best_idx] = best_merged
      parts[best_next_idx] = nil

    out = []
    i = 0
    while i < n
      out.push(parts[i]) if parts[i] != nil
      i = i + 1
    out

  # Best-effort encode: whitespace-aware split (each non-space run with
  # an optional leading space stays together), then byte-unicode + BPE
  # per chunk, then vocab lookup. Does NOT implement the full qwen2
  # regex pretokenizer.
  -> encode(text)
    out = []
    # tokenizer.json declares an NFC normalizer ahead of the pretokenizer.
    chunks = pretokenize(text.nfc)
    i = 0
    while i < chunks.size()
      chars = bytes_to_chars(chunks[i])
      pieces = bpe(chars)
      j = 0
      while j < pieces.size()
        id = @token_id[pieces[j]]
        if id == nil
          raise "Tokenizer.encode: unknown piece '" + pieces[j] + "' from chunk '" + chunks[i] + "'"
        out.push(id)
        j = j + 1
      i = i + 1
    out

  # The qwen2 pretokenizer, scanned by hand over codepoints. Pattern:
  #   (?i:'s|'t|'re|'ve|'m|'ll|'d)              r1 contraction
  #   [^\r\n L N]? [L M]+                     r2 (optional 1-cp prefix) word
  #   N                                          r3 single digit/number
  #   ' '? [^ws L M N]+ [\r\n]*                r4 punctuation run
  #   ws* [\r\n]+                              r5 whitespace ending in newlines
  #   ws+ (?!non-ws)                             r6 trailing ws (leaves 1 for next)
  #   ws+                                        r7
  # Alternatives are leftmost-first, exactly as Onig evaluates them; r5's
  # backtracking reduces to "match through the LAST newline run inside the
  # whitespace run", r6's to "all but the final space before a word".
  -> pretokenize(text)
    bytes = text.bytes.to_a
    nb = bytes.size()
    cps = []
    offs = []
    i = 0
    while i < nb
      b = bytes[i]
      offs.push(i)
      if b < 0x80
        cps.push(b)
        i = i + 1
      elsif b < 0xE0 && i + 1 < nb
        cps.push(((b & 0x1F) << 6) | (bytes[i + 1] & 0x3F))
        i = i + 2
      elsif b < 0xF0 && i + 2 < nb
        cps.push(((b & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F))
        i = i + 3
      elsif i + 3 < nb
        cps.push(((b & 0x07) << 18) | ((bytes[i + 1] & 0x3F) << 12) | ((bytes[i + 2] & 0x3F) << 6) | (bytes[i + 3] & 0x3F))
        i = i + 4
      else
        cps.push(b)
        i = i + 1
    offs.push(nb)
    nc = cps.size()

    chunks = []
    p = 0
    while p < nc
      cp = cps[p]
      e = -1
      # r1: contraction (ASCII apostrophe + s/t/d/m/re/ve/ll, any case)
      if cp == 39 && p + 1 < nc
        c1 = cps[p + 1] | 32
        if c1 == 115 || c1 == 116 || c1 == 100 || c1 == 109
          e = p + 2
        elsif p + 2 < nc
          c2 = cps[p + 2] | 32
          if (c1 == 114 && c2 == 101) || (c1 == 118 && c2 == 101) || (c1 == 108 && c2 == 108)
            e = p + 3
      # r2: optional non-CR/LF/L/N prefix + [L M]+
      if e < 0
        w = p
        if cp != 13 && cp != 10 && !tok_is_letter(cp) && !tok_is_number(cp)
          w = p + 1
        if w < nc && (tok_is_letter(cps[w]) || tok_is_mark(cps[w]))
          w = w + 1
          while w < nc && (tok_is_letter(cps[w]) || tok_is_mark(cps[w]))
            w = w + 1
          e = w
      # r3: single number cp
      if e < 0 && tok_is_number(cp)
        e = p + 1
      # r4: optional space + [^ws L M N]+ + CR/LF run
      if e < 0
        w = p
        if cp == 32
          w = p + 1
        f = w
        while f < nc && !tok_is_ws(cps[f]) && !tok_is_letter(cps[f]) && !tok_is_mark(cps[f]) && !tok_is_number(cps[f])
          f = f + 1
        if f > w
          while f < nc && tok_is_crlf(cps[f])
            f = f + 1
          e = f
      # r5/r6/r7: whitespace forms
      if e < 0 && tok_is_ws(cp)
        q = p
        while q < nc && tok_is_ws(cps[q])
          q = q + 1
        # r5: through the end of the LAST CR/LF run inside the ws run
        k = q - 1
        while k >= p && !tok_is_crlf(cps[k])
          k = k - 1
        if k >= p
          e = k + 1
        elsif q >= nc
          e = q            # r6 at end of text
        elsif q - p >= 2
          e = q - 1        # r6: leave the final space for the next token
        else
          e = q            # r7: single whitespace before non-ws
      if e < 0
        e = p + 1          # unclassifiable cp: emit alone (matches r4 shape)
      sb = StringBuffer(offs[e] - offs[p])
      j = offs[p]
      while j < offs[e]
        sb << byte_to_str(bytes[j])
        j = j + 1
      chunks.push(sb.to_s)
      p = e
    chunks

  # Decode token ids → UTF-8 string. Reverses the qwen3 double-encoding:
  #   raw bytes → first UTF-8 decode → "GPT-2 utf8 bytes" (each codepoint
  #   < 256, representing one byte of the GPT-2 utf8 form) → second UTF-8
  #   decode → GPT-2 codepoints → cp_to_byte → original input bytes.
  # Each output byte is emitted as a one-byte string via byte_to_str; the
  # concatenation reconstructs the original (UTF-8) input verbatim, so
  # multi-byte chars like ´í´ round-trip cleanly.
  -> decode(ids)
    raw_sb = StringBuffer(256)
    i = 0
    while i < ids.size()
      raw_sb << @tokens[ids[i]]
      i = i + 1
    raw = raw_sb.to_s
    bytes = raw.bytes.to_a

    # First decode: raw UTF-8 → array of "GPT-2 utf8 bytes"
    g_bytes = []
    i = 0
    n = bytes.size()
    while i < n
      b = bytes[i]
      if b < 128
        g_bytes.push(b)
        i = i + 1
      else
        b2 = bytes[i + 1]
        g_bytes.push(((b & 0x1F) << 6) | (b2 & 0x3F))
        i = i + 2

    # Second decode: GPT-2 utf8 bytes → GPT-2 codepoints → cp_to_byte → output bytes
    out = StringBuffer(g_bytes.size())
    i = 0
    n = g_bytes.size()
    while i < n
      b = g_bytes[i]
      if b < 128
        orig = @cp_to_byte[b]
        if orig != nil
          out << byte_to_str(orig)
        i = i + 1
      else
        b2 = g_bytes[i + 1]
        cp = ((b & 0x1F) << 6) | (b2 & 0x3F)
        orig = @cp_to_byte[cp]
        if orig != nil
          out << byte_to_str(orig)
        i = i + 2
    out.to_s
