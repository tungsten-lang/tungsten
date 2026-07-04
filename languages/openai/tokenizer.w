# OpenAI BPE Tokenizer (o200k_base)
#
# Implements the tiktoken BPE encoding algorithm used by GPT-4o/4.1.
# Loads the o200k_base vocabulary (199,998 mergeable tokens) and
# encodes text by:
#   1. Splitting input into chunks via a simplified regex
#   2. Converting each chunk to UTF-8 bytes
#   3. Iteratively merging the lowest-ranked adjacent byte pair
#   4. Mapping final byte sequences to token IDs
#
# Usage:
#   use ./tokenizer
#   tok = load_tokenizer("languages/openai/o200k_base.tiktoken")
#   ids = encode(tok, "Hello world!")
#   text = decode(tok, ids)

# ── Base64 decode ─────────────────────────────────────────────────────

fn b64_char_value(c)
  case c
  when :-0..:-9 then return c - :-0 + 52
  when :-A..:-Z then return c - :-A
  when :-a..:-z then return c - :-a + 26
  when :-+      then return 62
  when :-/      then return 63
  else
    0

-> base64_decode(s)
  bytes = u8[2400000]  # Pre-allocate a large byte array
  chars = s.bytes()

  i = 0
  len = chars.size()
  while i < len
    # Read 4 base64 chars → 3 bytes
    a = b64_char_value(chars[i])
    b = b64_char_value(chars[i + 1])

    bytes.push((a << 2) | (b >> 4))

    if i + 2 < len && chars[i + 2] != 61   # 61 = '='
      c = b64_char_value(chars[i + 2])
      bytes.push(((b & 15) << 4) | (c >> 2))
      if i + 3 < len && chars[i + 3] != 61
        d = b64_char_value(chars[i + 3])
        bytes.push(((c & 3) << 6) | d)

    i += 4
  bytes

# ── Vocabulary loading ────────────────────────────────────────────────

# Pre-built single-byte hex keys — avoids allocating a 2-char string
# per byte in the BPE hot loop. There are only 256 possible values.
hex_chars = "0123456789abcdef"
byte_keys = w64[256]

0...256 -> (bk_i)
  sb = StringBuffer(2)
  sb << hex_chars[(bk_i >> 4) & 0xF]
  sb << hex_chars[bk_i & 0xF]
  byte_keys.push(sb.to_s)

# Convert a byte array to a hex string key for hash lookup.
-> bytes_to_key(bytes)
  if bytes.size() == 1
    return byte_keys[bytes[0]]
  sb = StringBuffer(bytes.size() * 2)
  i = 0
  blen = bytes.size()
  while i < blen
    sb << byte_keys[bytes[i]]
    i += 1
  sb.to_s

# Build a hex key from a byte range (no intermediate slice).
## i64: start, length, i
-> bytes_to_key_range(all_bytes, start, length)
  if length == 1
    return byte_keys[all_bytes[start]]

  # ## reuse: sb buffer never escapes; to_s() copies into a new string.
  sb = StringBuffer(length * 2) ## reuse

  0...size -> (i)
    sb << byte_keys[all_bytes[start + i]]

  sb.to_s

# Packed i64 key format for byte sequences up to 7 bytes long:
#   bits 63-56: length (1-7)
#   bits 55-48: byte 0
#   bits 47-40: byte 1
#   ...
#   bits 7-0:   byte 6
#
# Merging packed keys: (len_A+len_B << 56) | (A_payload | (B_payload >> (len_A*8)))
# where *_payload = key & 0x00FFFFFFFFFFFFFF.

-> packed_from_bytes(bytes)
  n = bytes.size()

  return -1 if n < 1 || n > 7

  key = n << 56

  0...n -> (i)
    key = key | (bytes[i] << ((6 - i) * 8))

  key

## i64: start, length
-> packed_from_range(all_bytes, start, length)
  return -1 if length < 1 || length > 7

  key = length << 56

  0...size -> (i)
    key = key | (all_bytes[start + i] << ((6 - i) * 8))

  key

-> packed_merge(a, b)
  # Merge two packed keys if total length ≤ 7. Returns -1 if too long.
  a_len = (a >> 56) & 0xFF
  b_len = (b >> 56) & 0xFF
  tot = a_len + b_len

  return -1 if tot > 7

  a_pay = a & 0x00FFFFFFFFFFFFFF
  b_pay = b & 0x00FFFFFFFFFFFFFF

  (tot << 56) | a_pay | (b_pay >> (a_len * 8))

-> load_tokenizer(path)
  source = read_file(path)
  lines = source.split("\n")

  # token_to_rank: hex_key → rank (for encoding)
  # rank_to_bytes: rank → raw byte array (for decoding)
  token_to_rank = {}
  rank_to_bytes = w64[200000]

  lines.each -> (line)
    if line.size() > 0
      # Parse "base64 rank"
      parts = line.split(" ")
      b64 = parts[0]
      rank = parts[1].to_i()

      # Decode base64 → bytes, build hex key for hash
      raw_bytes = base64_decode(b64)
      key = bytes_to_key(raw_bytes)

      token_to_rank[key] = rank
      rank_to_bytes.push(raw_bytes)

  # Build single-byte fast-lookup table: byte → rank (or -1 if not a
  # single-token byte). Used to skip BPE and cache entirely for
  # length-1 chunks.
  byte_rank = i64[256]
  bk_i = 0
  while bk_i < 256
    r = token_to_rank[byte_keys[bk_i]]
    if r == nil
      byte_rank.push(-1)
    else
      byte_rank.push(r)
    bk_i += 1

  { token_to_rank: token_to_rank, rank_to_bytes: rank_to_bytes, byte_rank: byte_rank, size: rank_to_bytes.size, ucd: nil }

-> load_unicode(tok, ucd_path)
  tok[:ucd] = load_unicode_table(ucd_path)
  tok

# ── BPE encoding ──────────────────────────────────────────────────────

# BPE-encode a byte range within a shared byte array. Appends token IDs
# to `out_ids` directly to avoid intermediate array allocation.
#
# Uses nil-marking instead of array rebuild: merged right elements are
# set to nil and skipped in subsequent scans. This avoids allocating a
# new array on every merge step.
## i64: start, length, i, j, plen, min_rank, min_idx, next_i
-> bpe_encode_chunk(all_bytes, start, length, token_to_rank, out_ids)
  parts = w64[length] ## reuse
  i = 0
  while i < length
    parts.push(byte_keys[all_bytes[start + i]])
    i += 1

  plen = parts.size()

  loop
    min_rank = -1
    min_idx = -1
    min_merged = nil
    i = 0
    next_i = -1

    while i < plen && parts[i] == nil
      i += 1

    break if i >= plen

    j = i + 1
    while j < plen
      if parts[j] != nil
        merged = parts[i] + parts[j]
        rank = token_to_rank[merged]
        if rank != nil
          if min_rank == -1 || rank < min_rank
            min_rank = rank
            min_idx = i
            next_i = j
            min_merged = merged
        i = j
      j += 1

    break if min_idx == -1

    parts[min_idx] = min_merged
    parts[next_i] = nil

  i = 0
  while i < plen
    if parts[i] != nil
      rank = token_to_rank[parts[i]]
      out_ids.push(rank) if rank != nil
    i += 1

# ── Unicode metadata table ────────────────────────────────────────────
#
# languages/unicode.codepoints is a flat u16[0x110000] array — one entry
# per Unicode codepoint. Each u16 packs:
#
#   bits 7-3:  category (5 bits, matches W_CAT_* enum in wvalue.h)
#   bits 2-0:  utf8_len - 1 (0=1 byte, 1=2 bytes, 2=3 bytes, 3=4 bytes)
#   bits 15-8: flags (emoji, ascii, printable, etc.)
#
# Category values (from wvalue.h):
#   0-4:   Letter (Lu Ll Lt Lm Lo)     — matches \p{L}
#   5-7:   Number (Nd Nl No)           — matches \p{N}
#   8-10:  Separator (Zs Zl Zp)        — whitespace
#   11-13: Mark (Mn Mc Me)             — matches \p{M}
#   14-20: Punctuation (Pc..Po)
#   21-24: Symbol (Sm Sc Sk So)
#   25-29: Other (Cc Cf Cs Co Cn)

# ── Codepoint metadata extraction from w_box_char i64 values ──────────
#
# String.codes() now returns a typed i64[] of w_box_char values.
# Each i64 packs codepoint + Unicode metadata from the built-in table:
#   bits 0-20:  codepoint (21 bits)
#   bits 21-22: utf8_len - 1
#   bits 23-27: category (W_CAT_* enum)

-> v_cp(v)
  v & 0x1FFFFF

-> v_category(v)
  (v >> 23) & 0x1F

-> v_utf8_len(v)
  ((v >> 21) & 0x3) + 1

-> cp_is_letter_cat(cat)
  cat <= 4

-> cp_is_number_cat(cat)
  cat >= 5 && cat <= 7

-> cp_is_space_cat(cat)
  cat >= 8 && cat <= 10

-> cp_is_newline(cp)
  cp == 10 || cp == 13

# ── Pre-tokenizer (Unicode-aware) ─────────────────────────────────────
#
# Implements the o200k_base regex split using Unicode categories from
# the codepoint table. The regex alternatives (simplified):
#
#   1. [^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]*[\p{Ll}\p{Lm}\p{Lo}\p{M}]+
#      ('s|'t|'re|'ve|'m|'ll|'d)?
#   2. [^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]+[\p{Ll}...]*
#      ('s|'t|'re|'ve|'m|'ll|'d)?
#   3. \p{N}{1,3}
#   4.  ?[^\s\p{L}\p{N}]+[\r\n/]*
#   5. \s*[\r\n]+
#   6. \s+(?!\S)
#   7. \s+

-> byte_span(codes, from_pos, to_pos)
  n = 0
  k = from_pos
  while k < to_pos
    n += v_utf8_len(codes[k])
    k += 1
  n

-> pre_tokenize(text)
  # Returns parallel arrays (offsets, lengths) — byte offsets into the
  # source text, not heap-allocated slice strings. The BPE pass reads
  # bytes directly from a shared byte array, avoiding 2 heap allocations
  # per chunk.
  chunk_offsets = []
  chunk_lengths = []
  codes = text.codes()
  len = codes.size()
  pos = 0

  # Build byte-offset map: code_pos → byte_pos.
  # ## reuse: local to pre_tokenize, never escapes (consumed below, not
  # referenced by the returned dict).
  byte_offsets = [] ## reuse
  bi = 0
  ci = 0
  while ci < len
    byte_offsets.push(bi)
    bi += v_utf8_len(codes[ci])
    ci += 1
  byte_offsets.push(bi)

  while pos < len
    v = codes[pos]
    cp = v_cp(v)
    cat = v_category(v)
    letter = cat <= 4
    number = cat >= 5 && cat <= 7
    space = cat >= 8 && cat <= 10
    newline = cp == 10 || cp == 13

    # Rule 5: \s*[\r\n]+ — newline sequences with optional leading whitespace
    if newline || (space && pos + 1 < len && cp_is_newline(v_cp(codes[pos + 1])))
      start = pos
      while pos < len && cp_is_space_cat(v_category(codes[pos]))
        pos += 1
      while pos < len && cp_is_newline(v_cp(codes[pos]))
        pos += 1
      chunk_offsets.push(byte_offsets[start])
      chunk_lengths.push(byte_offsets[pos] - byte_offsets[start])
      next

    # Rules 6/7: \s+ — whitespace runs (not before a word/number)
    if space && !letter && !number
      # Space before a word/number falls through to the word/number rules
      at_word = pos + 1 < len && (cp_is_letter_cat(v_category(codes[pos + 1])) || cp_is_number_cat(v_category(codes[pos + 1])))
      if !at_word
        start = pos
        while pos < len && cp_is_space_cat(v_category(codes[pos]))
          pos += 1
        chunk_offsets.push(byte_offsets[start])
        chunk_lengths.push(byte_offsets[pos] - byte_offsets[start])
        next

    # Rules 1/2: optional non-LN-non-newline + letters (with CamelCase)
    # Match if we start with a letter/mark, OR with any non-LN-non-newline
    # char followed by a letter/mark. Tiktoken's regex: `[^\r\n\p{L}\p{N}]?`
    # allows leading space, punctuation, symbols, etc. — not just space.
    mark = cat >= 11 && cat <= 13
    leading_ok = letter || mark || (!number && !newline && pos + 1 < len && (cp_is_letter_cat(v_category(codes[pos + 1])) || (v_category(codes[pos + 1]) >= 11 && v_category(codes[pos + 1]) <= 13)))
    if leading_ok
      start = pos
      # Optional leading non-LN-non-newline char
      if !letter && !mark && !number && !newline
        pos += 1
      # Consume upper-like + mark* (Lu=0, Lt=2, Lm=3, Lo=4, M=11-13)
      while pos < len
        c = v_category(codes[pos])
        upper_like = c == 0 || c == 2 || c == 3 || c == 4 || (c >= 11 && c <= 13)
        if !upper_like
          break
        pos += 1
      # Consume lower-like + mark* (Ll=1, Lm=3, Lo=4, M=11-13)
      while pos < len
        c = v_category(codes[pos])
        lower_like = c == 1 || c == 3 || c == 4 || (c >= 11 && c <= 13)
        if !lower_like
          break
        pos += 1
      # Check for contraction: 's 't 're 've 'm 'll 'd
      if pos < len && v_cp(codes[pos]) == :-'
        next_pos = pos + 1
        if next_pos < len
          nc = v_cp(codes[next_pos])
          if nc == :-s || nc == :-t || nc == :-m || nc == :-d
            pos = next_pos + 1
          elsif nc == :-r && next_pos + 1 < len && v_cp(codes[next_pos + 1]) == :-e
            pos = next_pos + 2
          elsif nc == :-v && next_pos + 1 < len && v_cp(codes[next_pos + 1]) == :-e
            pos = next_pos + 2
          elsif nc == :-l && next_pos + 1 < len && v_cp(codes[next_pos + 1]) == :-l
            pos = next_pos + 2
      if pos > start
        chunk_offsets.push(byte_offsets[start])
        chunk_lengths.push(byte_offsets[pos] - byte_offsets[start])
        next

    # Rule 3: \p{N}{1,3} — digit groups
    if number || (cp == 32 && pos + 1 < len && cp_is_number_cat(v_category(codes[pos + 1])))
      start = pos
      if cp == 32
        pos += 1
      count = 0
      while pos < len && cp_is_number_cat(v_category(codes[pos])) && count < 3
        pos += 1
        count += 1
      chunk_offsets.push(byte_offsets[start])
      chunk_lengths.push(byte_offsets[pos] - byte_offsets[start])
      next

    # Rule 4:  ?[^\s\p{L}\p{N}]+[\r\n/]* — punctuation/symbol runs
    if !letter && !number && !newline
      start = pos
      pos += 1
      while pos < len
        c2_cat = v_category(codes[pos])
        if cp_is_letter_cat(c2_cat) || cp_is_number_cat(c2_cat) || cp_is_space_cat(c2_cat) || cp_is_newline(v_cp(codes[pos]))
          break
        pos += 1
      # Consume trailing \r\n/
      while pos < len && (cp_is_newline(v_cp(codes[pos])) || v_cp(codes[pos]) == :-/)
        pos += 1
      chunk_offsets.push(byte_offsets[start])
      chunk_lengths.push(byte_offsets[pos] - byte_offsets[start])
      next

    # Fallback: single codepoint
    chunk_offsets.push(byte_offsets[pos])
    chunk_lengths.push(byte_offsets[pos + 1] - byte_offsets[pos])
    pos += 1

  {offsets: chunk_offsets, lengths: chunk_lengths}

# ── Public API ────────────────────────────────────────────────────────

-> encode(tok, text)
  # Shared resources — allocated once, reused for every chunk
  all_bytes = text.bytes()
  chunks = pre_tokenize(text)
  offsets = chunks[:offsets]
  lengths = chunks[:lengths]
  token_to_rank = tok[:token_to_rank]
  byte_rank = tok[:byte_rank]

  # Chunk cache — repeated chunks (" ", "\n", ", ", " the", "int", etc.)
  # skip BPE entirely on cache hit. Cache keyed by hex-encoded bytes.
  # ## reuse_drain: cache never escapes encode(); on reset, iterate values
  # and recycle each chunk_ids array to the pool. Fixes the leak where
  # thousands of per-call chunk_ids arrays accumulate on the heap.
  cache = {} ## reuse_drain

  ids = []
  n = offsets.size()
  i = 0
  while i < n
    off = offsets[i]
    l = lengths[i]

    # Single-byte fast path: direct byte→rank lookup, no BPE, no cache
    if l == 1
      r = byte_rank[all_bytes[off]]
      if r >= 0
        ids.push(r)
        i += 1
        next

    # Multi-byte path with cache
    if l <= 16
      ckey = bytes_to_key_range(all_bytes, off, l)
      cached = cache[ckey]
      if cached != nil
        k = 0
        while k < cached.size()
          ids.push(cached[k])
          k += 1
      else
        chunk_ids = []
        bpe_encode_chunk(all_bytes, off, l, token_to_rank, chunk_ids)
        cache[ckey] = chunk_ids
        k = 0
        while k < chunk_ids.size()
          ids.push(chunk_ids[k])
          k += 1
    else
      bpe_encode_chunk(all_bytes, off, l, token_to_rank, ids)
    i += 1
  ids

-> decode(tok, ids)
  sb = StringBuffer(ids.size() * 4)
  i = 0
  while i < ids.size()
    id = ids[i]
    if id >= 0 && id < tok[:rank_to_bytes].size()
      raw = tok[:rank_to_bytes][id]
      j = 0
      while j < raw.size()
        sb << raw[j].chr
        j += 1
    i += 1
  sb.to_s

-> count_tokens(tok, text)
  encode(tok, text).size()

# ── Parallel encoding ─────────────────────────────────────────────────
#
# Partitions chunks into num_workers contiguous ranges. Each goroutine
# gets a thread-local ids[] and a thread-local chunk cache — no sharing,
# no contention on the hot path. Main thread concatenates results in
# worker-index order to preserve output ordering.
#
# Shared read-only: all_bytes, offsets, lengths, token_to_rank, byte_rank.
# Per-worker: local_ids, local_cache.

# Worker body: encodes chunks [start_idx, end_idx) into its own ids array.
-> encode_chunk_range(start_idx, end_idx, all_bytes, offsets, lengths, token_to_rank, byte_rank)
  local_ids = []
  local_cache = {} ## reuse_drain
  k = start_idx
  while k < end_idx
    off = offsets[k]
    l = lengths[k]

    if l == 1
      r = byte_rank[all_bytes[off]]
      if r >= 0
        local_ids.push(r)
        k += 1
        next

    if l <= 16
      ckey = bytes_to_key_range(all_bytes, off, l)
      cached = local_cache[ckey]
      if cached != nil
        j = 0
        while j < cached.size()
          local_ids.push(cached[j])
          j += 1
      else
        chunk_ids = []
        bpe_encode_chunk(all_bytes, off, l, token_to_rank, chunk_ids)
        local_cache[ckey] = chunk_ids
        j = 0
        while j < chunk_ids.size()
          local_ids.push(chunk_ids[j])
          j += 1
    else
      bpe_encode_chunk(all_bytes, off, l, token_to_rank, local_ids)
    k += 1
  local_ids

# Shared-cache worker: stripe-locked hash cache shared across goroutines.
# Stripes reduce contention — each bucket has its own atomic spin lock.
# Bucket inserts are exclusive; bucket reads hold the lock for the dict
# lookup then release before iterating the returned chunk_ids array
# (safe because chunk_ids is never mutated after insert).
-> encode_chunk_range_shared(start_idx, end_idx, all_bytes, offsets, lengths, token_to_rank, byte_rank, stripe_locks, stripe_buckets, num_stripes)
  local_ids = []
  k = start_idx
  while k < end_idx
    off = offsets[k]
    l = lengths[k]

    if l == 1
      r = byte_rank[all_bytes[off]]
      if r >= 0
        local_ids.push(r)
        k += 1
        next

    if l <= 16
      ckey = bytes_to_key_range(all_bytes, off, l)

      # Route to stripe via low bits of byte range (fast, no extra hash)
      h = (off + l) % num_stripes
      lock = stripe_locks[h]
      bucket = stripe_buckets[h]

      # Acquire stripe lock (spin on CAS 0→1).
      spin = 0
      while !lock.cas(0, 1)
        spin = spin + 1
      cached = bucket[ckey]
      lock.set(0)

      if cached != nil
        j = 0
        while j < cached.size()
          local_ids.push(cached[j])
          j += 1
      else
        chunk_ids = []
        bpe_encode_chunk(all_bytes, off, l, token_to_rank, chunk_ids)

        # Publish to shared cache under lock. Another worker may have
        # inserted concurrently; overwriting is harmless (same key →
        # same result).
        spin2 = 0
        while !lock.cas(0, 1)
          spin2 = spin2 + 1
        bucket[ckey] = chunk_ids
        lock.set(0)

        j = 0
        while j < chunk_ids.size()
          local_ids.push(chunk_ids[j])
          j += 1
    else
      bpe_encode_chunk(all_bytes, off, l, token_to_rank, local_ids)
    k += 1
  local_ids

-> encode_parallel(tok, text, num_workers)
  all_bytes = text.bytes()
  chunks = pre_tokenize(text)
  offsets = chunks[:offsets]
  lengths = chunks[:lengths]
  token_to_rank = tok[:token_to_rank]
  byte_rank = tok[:byte_rank]

  n = offsets.size()

  # Enqueue one work item per partition; spawn num_workers goroutines
  # that each pull one item and send their local_ids back.
  work = Channel.new(num_workers)
  results = Channel.new(num_workers)

  w = 0
  while w < num_workers
    ws = (n * w) / num_workers
    we = (n * (w + 1)) / num_workers
    work.send({idx: w, start: ws, end: we})
    w += 1

  w = 0
  while w < num_workers
    go ->
      msg = work.recv()
      local_ids = encode_chunk_range(msg[:start], msg[:end], all_bytes, offsets, lengths, token_to_rank, byte_rank)
      results.send({idx: msg[:idx], ids: local_ids})
    w += 1

  # Collect into per-worker slots to preserve chunk ordering.
  # ## reuse: slots is a local accumulator; entries are copied into `ids`
  # before this function returns, so slots itself never escapes.
  slots = [] ## reuse
  sp = 0
  while sp < num_workers
    slots.push(nil)
    sp += 1

  got = 0
  while got < num_workers
    msg = results.recv()
    slots[msg[:idx]] = msg[:ids]
    got += 1

  # Concat in worker-index order.
  ids = []
  s = 0
  while s < num_workers
    local = slots[s]
    k = 0
    while k < local.size()
      ids.push(local[k])
      k += 1
    s += 1
  ids

# Parallel encode with a SHARED stripe-locked chunk cache. Each bucket
# has its own atomic spin lock (bitlock pattern). Unlike encode_parallel
# (per-worker cache, cache fragmentation), common chunks are BPE'd once
# across all workers.
-> encode_parallel_shared(tok, text, num_workers)
  all_bytes = text.bytes()
  chunks = pre_tokenize(text)
  offsets = chunks[:offsets]
  lengths = chunks[:lengths]
  token_to_rank = tok[:token_to_rank]
  byte_rank = tok[:byte_rank]

  n = offsets.size()

  # 64 stripes = low collision probability at ≤16 workers. Each stripe
  # has an Atomic(i64) used as a spin lock (bit 0 = held).
  num_stripes = 64
  stripe_locks = []
  stripe_buckets = []
  ss = 0
  while ss < num_stripes
    stripe_locks.push(Atomic.new(0))
    stripe_buckets.push({})
    ss += 1

  work = Channel.new(num_workers)
  results = Channel.new(num_workers)

  w = 0
  while w < num_workers
    ws = (n * w) / num_workers
    we = (n * (w + 1)) / num_workers
    work.send({idx: w, start: ws, end: we})
    w += 1

  w = 0
  while w < num_workers
    go ->
      msg = work.recv()
      local_ids = encode_chunk_range_shared(msg[:start], msg[:end], all_bytes, offsets, lengths, token_to_rank, byte_rank, stripe_locks, stripe_buckets, num_stripes)
      results.send({idx: msg[:idx], ids: local_ids})
    w += 1

  # ## reuse: same as encode_parallel — slots is local, consumed before return.
  slots = [] ## reuse
  sp = 0
  while sp < num_workers
    slots.push(nil)
    sp += 1

  got = 0
  while got < num_workers
    msg = results.recv()
    slots[msg[:idx]] = msg[:ids]
    got += 1

  ids = []
  s = 0
  while s < num_workers
    local = slots[s]
    k = 0
    while k < local.size()
      ids.push(local[k])
      k += 1
    s += 1
  ids
