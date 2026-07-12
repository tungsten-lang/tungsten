# IPv6 — heap-backed 128-bit address with native CIDR and classification logic.
+ IPv6
  # WNetAddr's leading `type` byte is implicit for generic-bucket classes;
  # this source-visible layout begins at the C struct's `len` field.
  - data (WNetAddr)
      u8     len
      u8     prefix
      u8     _pad
      u8[16] bytes
      u8[12] _pad2

  -> .parse(text)
    ccall("w_ipv6_parse", text)

  -> to_s
    ccall("w_to_s", self)

  -> inspect
    self.to_s

  -> prefix
    raw = $prefix
    raw == 255 ? nil : raw

  -> cidr?
    $prefix != 255

  -> with_prefix(prefix = nil)
    if prefix != nil
      raw = ccall_nobox("w_numeric_to_i64", prefix) ## i64
      if raw > 128
        raise "IPv6 prefix must be between 0 and 128"
    # Allocation and byte copying remain a storage boundary; validation and
    # prefix semantics live here in the source-defined method.
    ccall("w_ipv6_storage_clone", self, prefix)

  -> byte(index)
    raw_index = ccall_nobox("w_numeric_to_i64", index) ## i64
    if raw_index < 0 || raw_index > 15
      return nil
    return $bytes[raw_index]

  -> [](index)
    self.byte(index)

  -> bytes
    out = []
    i = 0
    while i < 16
      out.push($bytes[i])
      i += 1
    out

  -> network
    raw_prefix = $prefix ## i64
    effective = (raw_prefix == 255 ? 128 : raw_prefix) ## i64
    b0 = $bytes[0] ## i64
    b1 = $bytes[1] ## i64
    b2 = $bytes[2] ## i64
    b3 = $bytes[3] ## i64
    b4 = $bytes[4] ## i64
    b5 = $bytes[5] ## i64
    b6 = $bytes[6] ## i64
    b7 = $bytes[7] ## i64
    b8 = $bytes[8] ## i64
    b9 = $bytes[9] ## i64
    b10 = $bytes[10] ## i64
    b11 = $bytes[11] ## i64
    b12 = $bytes[12] ## i64
    b13 = $bytes[13] ## i64
    b14 = $bytes[14] ## i64
    b15 = $bytes[15] ## i64
    word0 = ((b0 << 24) | (b1 << 16) | (b2 << 8) | b3) ## i64
    word1 = ((b4 << 24) | (b5 << 16) | (b6 << 8) | b7) ## i64
    word2 = ((b8 << 24) | (b9 << 16) | (b10 << 8) | b11) ## i64
    word3 = ((b12 << 24) | (b13 << 16) | (b14 << 8) | b15) ## i64

    bits = effective ## i64
    if bits <= 0
      word0 = 0
    elsif bits < 32
      word0 = word0 & ((0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF)
    bits = effective - 32
    if bits <= 0
      word1 = 0
    elsif bits < 32
      word1 = word1 & ((0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF)
    bits = effective - 64
    if bits <= 0
      word2 = 0
    elsif bits < 32
      word2 = word2 & ((0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF)
    bits = effective - 96
    if bits <= 0
      word3 = 0
    elsif bits < 32
      word3 = word3 & ((0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF)

    # Allocation/copying remains a storage boundary. Four u32 words avoid the
    # temporary generic Array that the source-level mask loop originally used.
    ccall("w_ipv6_storage_from_words", word0, word1, word2, word3, raw_prefix)

  -> include?(address)
    if !ccall("w_netaddr_ipv6_p", address)
      return false
    candidate = address ## IPv6
    raw_prefix = $prefix ## i64
    effective = (raw_prefix == 255 ? 128 : raw_prefix) ## i64
    i = 0
    while i < 16
      bits = (effective - i * 8) ## i64
      mask = 0 ## i64
      if bits >= 8
        mask = 0xFF
      elsif bits > 0
        mask = (0xFF << (8 - bits)) & 0xFF
      self_byte = $bytes[i] ## i64
      candidate_byte = candidate$bytes[i] ## i64
      if (self_byte & mask) != (candidate_byte & mask)
        return false
      i += 1
    true

  -> contains?(address)
    self.include?(address)

  -> unspecified?
    i = 0
    while i < 16
      if $bytes[i] != 0
        return false
      i += 1
    true

  -> loopback?
    i = 0
    while i < 15
      if $bytes[i] != 0
        return false
      i += 1
    return $bytes[15] == 1

  -> multicast?
    $bytes[0] == 0xFF

  -> link_local?
    $bytes[0] == 0xFE && ($bytes[1] & 0xC0) == 0x80

  -> unique_local?
    ($bytes[0] & 0xFE) == 0xFC

  -> private?
    self.unique_local?

  -> global?
    first = $bytes[0] ## i64
    if first == 0xFF || (first == 0xFE && ($bytes[1] & 0xC0) == 0x80) || (first & 0xFE) == 0xFC
      return false
    # All remaining exclusions (unspecified and loopback) start with a zero
    # byte. Ordinary global addresses take this fast path; the rare 00::/8
    # case uses straight-line loads so it does not pay a byte-at-a-time loop.
    if first != 0
      return true
    middle = ($bytes[1] | $bytes[2] | $bytes[3] | $bytes[4] |
              $bytes[5] | $bytes[6] | $bytes[7] | $bytes[8] |
              $bytes[9] | $bytes[10] | $bytes[11] | $bytes[12] |
              $bytes[13] | $bytes[14]) ## i64
    if middle != 0
      return true
    last = $bytes[15] ## i64
    last > 1
