# 64-bit wyhash helpers shared by compiler passes and LLVM emission.

-> wyhash_read_u32(bytes, offset)
  result = 0 ## u64
  i = 0
  while i < 4
    b = bytes[offset + i] ## u64
    result = result | (b << (i * 8))
    i += 1
  result

-> wyhash_read_u64(bytes, offset)
  result = 0 ## u64
  i = 0
  while i < 8
    b = bytes[offset + i] ## u64
    result = result | (b << (i * 8))
    i += 1
  result

-> wyhash_mix_u64(a, b)
  au = a ## u64
  bu = b ## u64
  a128 = au ## u128
  b128 = bu ## u128
  prod = a128 * b128 ## u128
  lo = prod ## u64
  hi = prod >> 64 ## u128
  hi64 = hi ## u64
  lo ^ hi64

-> wyhash64_string(text)
  bytes = text.bytes()
  len = bytes.size()
  s0 = 0xa0761d6478bd642f ## u64
  s1 = 0xe7037ed1a0b428db ## u64
  s2 = 0x8ebc6af09c88c6e3 ## u64
  s3 = 0x589965cc75374cc3 ## u64
  seed = 0x1234567890abcdef ## u64
  a = 0 ## u64
  b = 0 ## u64

  if len <= 16
    if len >= 4
      head_offset = (len >> 3) << 2
      tail_offset = len - 4
      tail_head_offset = len - 4 - head_offset
      a = (wyhash_read_u32(bytes, 0) << 32) | wyhash_read_u32(bytes, head_offset)
      b = (wyhash_read_u32(bytes, tail_offset) << 32) | wyhash_read_u32(bytes, tail_head_offset)
    elsif len > 0
      first = bytes[0] ## u64
      middle = bytes[len >> 1] ## u64
      last = bytes[len - 1] ## u64
      a = (first << 16) | (middle << 8) | last
      b = 0 ## u64
    else
      a = 0 ## u64
      b = 0 ## u64
  else
    i = len
    offset = 0
    if i > 48
      s0v = seed ## u64
      s1v = seed ## u64
      s2v = seed ## u64
      while i > 48
        d0 = wyhash_read_u64(bytes, offset)
        d1 = wyhash_read_u64(bytes, offset + 8)
        d2 = wyhash_read_u64(bytes, offset + 16)
        d3 = wyhash_read_u64(bytes, offset + 24)
        d4 = wyhash_read_u64(bytes, offset + 32)
        d5 = wyhash_read_u64(bytes, offset + 40)
        s0v = wyhash_mix_u64(d0 ^ s1, d1 ^ s0v)
        s1v = wyhash_mix_u64(d2 ^ s2, d3 ^ s1v)
        s2v = wyhash_mix_u64(d4 ^ s3, d5 ^ s2v)
        offset += 48
        i -= 48
      seed = s0v ^ s1v ^ s2v
    while i > 16
      d0 = wyhash_read_u64(bytes, offset)
      d1 = wyhash_read_u64(bytes, offset + 8)
      seed = wyhash_mix_u64(d0 ^ s1, d1 ^ seed)
      offset += 16
      i -= 16
    a = wyhash_read_u64(bytes, offset + i - 16)
    b = wyhash_read_u64(bytes, offset + i - 8)

  len_u64 = len ## u64
  wyhash_mix_u64(s1 ^ len_u64, wyhash_mix_u64(a ^ s1, b ^ seed))

-> u64_hex(value)
  u = value ## u64
  hex_chars = "0123456789abcdef"
  out = StringBuffer(16)
  shift = 60
  while shift >= 0
    out << hex_chars.slice((u >> shift) & 15, 1)
    shift -= 4
  out.to_s()

-> wyhash64_hex_string(text)
  u64_hex(wyhash64_string(text))
