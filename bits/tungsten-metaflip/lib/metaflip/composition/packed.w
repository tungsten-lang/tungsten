# Exact GF(2) cold-path tensors. Little-endian 32-bit limbs, term-major
# ((term*3+axis)*stride+limb); unlike the live walker, factors may exceed u64.
# Gates check reported slab lengths before access, as in the native walker.
# Callers must pass the actual allocated lengths, including parity scratch.
-> ffpk_stride(n, m, p) (i64 i64 i64) i64
  if n < 1 || m < 1 || p < 1 || n > 1024 || m > 1024 || p > 1024
    return 0
  width = n*m ## i64
  if m*p > width
    width = m*p
  if n*p > width
    width = n*p
  if width > 1024
    return 0
  (width+31)/32

-> ffpk_width(n, m, p, axis) (i64 i64 i64 i64) i64
  if axis == 0
    return n*m
  if axis == 1
    return m*p
  n*p

-> ffpk_ctz(word) (i64) i64
  if word <= 0
    return 32
  shift = 0 ## i64
  if (word & 65535) == 0
    word = word >> 16
    shift += 16
  if (word & 255) == 0
    word = word >> 8
    shift += 8
  if (word & 15) == 0
    word = word >> 4
    shift += 4
  if (word & 3) == 0
    word = word >> 2
    shift += 2
  if (word & 1) == 0
    shift += 1
  shift

-> ffpk_valid(data, words, rank, n, m, p) (i64[] i64 i64 i64 i64 i64) i64
  stride = ffpk_stride(n, m, p) ## i64
  if stride == 0 || rank < 1 || rank > 16384 || words < 3*stride*rank
    return 0
  t = 0 ## i64
  while t < rank
    axis = 0 ## i64
    while axis < 3
      width = ffpk_width(n, m, p, axis) ## i64
      nonzero = 0 ## i64
      limb = 0 ## i64
      while limb < stride
        value = data[(t*3+axis)*stride+limb] ## i64
        bits = width-32*limb ## i64
        if bits < 0
          bits = 0
        if bits > 32
          bits = 32
        if value < 0 || value >= (1 << bits)
          return 0
        nonzero = nonzero | value
        limb += 1
      if nonzero == 0
        return 0
      axis += 1
    t += 1
  1

# Full coefficient check, including off-support entries, one U-fiber at a
# time. Scratch is bc*ceil(ac/32), not the entire six-index tensor. A positive
# XOR-work budget counts nonzero W limbs and yields -1 on exhaustion, NEVER
# a verified result. Zero-limb XORs are omitted, not unchecked coefficients:
# every fiber entry, including off-support zeros, is still compared below.
-> ffpk_exact(data, words, rank, n, m, p, scratch, scratch_words, budget) (i64[] i64 i64 i64 i64 i64 i64[] i64 i64) i64
  if ffpk_valid(data, words, rank, n, m, p) != 1
    return 0
  stride = ffpk_stride(n, m, p) ## i64
  wlimbs = (n*p+31)/32 ## i64
  vlimbs = (m*p+31)/32 ## i64
  count = m*p*wlimbs ## i64
  if scratch_words < count
    return 0
  used = 0 ## i64
  a = 0 ## i64
  while a < n*m
    j = 0 ## i64
    while j < count
      scratch[j] = 0
      j += 1
    t = 0 ## i64
    while t < rank
      if ((data[3*t*stride+a/32] >> (a%32)) & 1) != 0
        wmask = 0 ## i64
        k = 0 ## i64
        while k < wlimbs
          if data[(3*t+2)*stride+k] != 0
            wmask = wmask | (1 << k)
          k += 1
        vb = 0 ## i64
        while vb < vlimbs
          value = data[(3*t+1)*stride+vb] ## i64
          while value != 0
            b = 32*vb+ffpk_ctz(value) ## i64
            active = wmask ## i64
            while active != 0
              used += 1
              if budget > 0 && used > budget
                return 0-1
              k = ffpk_ctz(active)
              scratch[b*wlimbs+k] = scratch[b*wlimbs+k] ^ data[(3*t+2)*stride+k]
              active = active & (active-1)
            value = value & (value-1)
          vb += 1
      t += 1
    k = 0 ## i64
    while k < p
      b = (a%m)*p+k ## i64
      c = (a / m)*p+k ## i64
      scratch[b*wlimbs+c/32] = scratch[b*wlimbs+c/32] ^ (1 << (c%32))
      k += 1
    j = 0
    while j < count
      if scratch[j] != 0
        return 0
      j += 1
    a += 1
  1

-> ffpk_compare(data, left, right, stride) (i64[] i64 i64 i64) i64
  axis = 0 ## i64
  while axis < 3
    limb = stride-1 ## i64
    while limb >= 0
      a = data[(3*left+axis)*stride+limb] ## i64
      b = data[(3*right+axis)*stride+limb] ## i64
      if a < b
        return 0-1
      if a > b
        return 1
      limb -= 1
    axis += 1
  0

-> ffpk_swap(data, left, right, stride) (i64[] i64 i64 i64) i64
  i = 0 ## i64
  while i < 3*stride
    value = data[3*left*stride+i] ## i64
    data[3*left*stride+i] = data[3*right*stride+i]
    data[3*right*stride+i] = value
    i += 1
  1

# In-place heapsort: bounded memory and no adversarial recursion depth.
-> ffpk_sift(data, root, size, stride) (i64[] i64 i64 i64) i64
  while 2*root+1 < size
    child = 2*root+1 ## i64
    if child+1 < size && ffpk_compare(data, child, child+1, stride) < 0
      child += 1
    if ffpk_compare(data, root, child, stride) >= 0
      break
    z = ffpk_swap(data, root, child, stride) ## i64
    root = child
  1

-> ffpk_canonicalize(data, words, rank, stride) (i64[] i64 i64 i64) i64
  if stride < 1 || stride > 32 || rank < 0 || rank > 16384 || words < rank*3*stride
    return 0-1
  i = rank/2 ## i64
  while i > 0
    i -= 1
    z = ffpk_sift(data, i, rank, stride) ## i64
  i = rank-1
  while i > 0
    z = ffpk_swap(data, 0, i, stride) ## i64
    z = ffpk_sift(data, 0, i, stride)
    i -= 1
  output = 0 ## i64
  i = 0
  while i < rank
    end_at = i+1 ## i64
    while end_at < rank && ffpk_compare(data, i, end_at, stride) == 0
      end_at += 1
    nonzero = 1 ## i64
    axis = 0 ## i64
    while axis < 3
      value = 0 ## i64
      limb = 0 ## i64
      while limb < stride
        value = value | data[(i*3+axis)*stride+limb]
        limb += 1
      if value == 0
        nonzero = 0
      axis += 1
    if (end_at-i)%2 == 1 && nonzero == 1
      k = 0 ## i64
      while k < 3*stride
        data[output*3*stride+k] = data[i*3*stride+k]
        k += 1
      output += 1
    i = end_at
  output

# MFW1 is canonical lowercase hexadecimal with no leading zeroes. Shape and
# the complete sorted term set are included; this is not a hull/score key.
-> ffpk_blob(data, rank, n, m, p) (i64[] i64 i64 i64 i64)
  stride = ffpk_stride(n, m, p) ## i64
  text = StringBuffer(64+rank*3*(8*stride+1)) ## recycle
  text.append("MFW1 " + n.to_s() + " " + m.to_s() + " " + p.to_s() + " " + rank.to_s() + "\n")
  digits = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]
  t = 0 ## i64
  while t < rank
    axis = 0 ## i64
    while axis < 3
      nibble = 8*stride-1 ## i64
      started = 0 ## i64
      while nibble >= 0
        value = (data[(3*t+axis)*stride+nibble/8] >> (4*(nibble%8))) & 15 ## i64
        if value != 0 || started != 0 || nibble == 0
          text.append(digits[value])
          started = 1
        nibble -= 1
      if axis == 2
        text.append("\n")
      else
        text.append(" ")
      axis += 1
    t += 1
  text.to_s()

-> ffpk_decimal(value) (String) i64
  if value.size() < 1 || value.size() > 10 || (value.size() > 1 && value.byte_at(0) == 48)
    return 0-1
  out = 0 ## i64
  i = 0 ## i64
  while i < value.size()
    digit = value.byte_at(i)-48 ## i64
    if digit < 0 || digit > 9
      return 0-1
    out = out*10+digit
    i += 1
  out

# Strict canonical MFW1 reader, for checked cold-path artifacts. A successful
# parse validates limbs/order, NOT the tensor identity. Failure may clobber
# the scratch destination, so callers must never admit it without both gates.
-> ffpk_parse(raw, data, words, meta, meta_words) (String i64[] i64 i64[] i64) i64
  if raw.size() < 16 || raw.size() > 12632128 || meta_words < 4
    return 0-1
  end_header = 0 ## i64
  while end_header < raw.size() && end_header < 64 && raw.byte_at(end_header) != 10
    end_header += 1
  if end_header >= 64 || end_header >= raw.size()
    return 0-1
  header = raw.slice(0, end_header).split(" ")
  if header.size() != 5 || header[0] != "MFW1"
    return 0-1
  n = ffpk_decimal(header[1]) ## i64
  m = ffpk_decimal(header[2]) ## i64
  p = ffpk_decimal(header[3]) ## i64
  rank = ffpk_decimal(header[4]) ## i64
  stride = ffpk_stride(n, m, p) ## i64
  if stride == 0 || rank < 1 || rank > 16384 || words < 3*stride*rank
    return 0-1
  if raw.slice(0, end_header) != "MFW1 " + n.to_s() + " " + m.to_s() + " " + p.to_s() + " " + rank.to_s()
    return 0-1
  i = 0 ## i64
  while i < 3*stride*rank
    data[i] = 0
    i += 1
  cursor = end_header+1 ## i64
  t = 0 ## i64
  while t < rank
    axis = 0 ## i64
    while axis < 3
      first = cursor ## i64
      separator = 32 ## i64
      if axis == 2
        separator = 10
      while cursor < raw.size() && raw.byte_at(cursor) != separator && cursor-first <= 8*stride
        cursor += 1
      length = cursor-first ## i64
      if cursor >= raw.size() || length < 1 || length > 8*stride || raw.byte_at(first) == 48
        return 0-1
      i = 0
      while i < length
        byte = raw.byte_at(first+i) ## i64
        digit = byte-48 ## i64
        if byte >= 97 && byte <= 102
          digit = byte-87
        elsif byte < 48 || byte > 57
          return 0-1
        nibble = length-1-i ## i64
        index = (3*t+axis)*stride+nibble/8 ## i64
        data[index] = data[index] | (digit << (4*(nibble%8)))
        i += 1
      cursor += 1
      axis += 1
    if t > 0 && ffpk_compare(data, t-1, t, stride) >= 0
      return 0-1
    t += 1
  if cursor != raw.size() || ffpk_valid(data, words, rank, n, m, p) != 1
    return 0-1
  meta[0] = n
  meta[1] = m
  meta[2] = p
  meta[3] = rank
  rank
