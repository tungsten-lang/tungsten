# Offline parent experiments may load exact tensors outside the campaign
# allowlist. Keep this out of the fleet: no default seeds or GPU admission.
use ../lib/metaflip/rect

-> ffbo_supported(n, m, p) (i64 i64 i64) i64
  # ffw's layout needs a leading dimension in 2..7. The rectangular header
  # has four bits per dimension; split randomness supplies at most 62 bits.
  if n < 2 || n > 7 || m < 2 || m > 15 || p < 2 || p > 15
    return 0
  if n*m > 62 || m*p > 62 || n*p > 62
    return 0
  1

-> ffbo_verify(st, n, m, p) (i64[] i64 i64 i64) i64
  if ffbo_supported(n,m,p) != 1 || ffw_valid(st) != 1
    return 0
  if st[2] != n || st[3] != ffr_pack_shape(n,m,p) || st[6] < 1 || st[6] > st[4]
    return 0
  masks = i64[3]
  masks[0] = ffr_factor_mask(n*m)
  masks[1] = ffr_factor_mask(m*p)
  masks[2] = ffr_factor_mask(n*p)
  i = 0 ## i64
  while i < st[6]
    slot = st[st[50]+i] ## i64
    if slot < 0 || slot >= st[4]
      return 0
    axis = 0 ## i64
    while axis < 3
      value = st[st[44+axis]+slot] ## i64
      if value <= 0 || (value & masks[axis]) != value
        return 0
      axis += 1
    i += 1
  words = ffw_verify_scratch_words(n,m,p) ## i64
  parity = i64[words]
  if ffw_support_tensor_error_scratch(st,st[44],st[45],st[46],st[50],st[6],n,m,p,parity,words) != 0
    return 0
  1

-> ffbo_load(st, path, n, m, p, capacity, seed, dslack) (i64[] String i64 i64 i64 i64 i64 i64) i64
  if ffbo_supported(n,m,p) != 1
    return 0 - 1
  content = read_file(path)
  if content == nil
    return 0 - 1
  if content.strip().size() == 0
    return 0 - 1
  lines = content.strip().split("\n")
  rank = ffw_parse_decimal_i64(lines[0]) ## i64
  if rank < 1 || rank > capacity || lines.size() != rank+1
    return 0 - 1
  if ffw_prepare(st,n,capacity,seed,dslack,4,1000,500) != 1
    return 0 - 1
  st[3] = ffr_pack_shape(n,m,p)
  masks = i64[3]
  masks[0] = ffr_factor_mask(n*m)
  masks[1] = ffr_factor_mask(m*p)
  masks[2] = ffr_factor_mask(n*p)
  term = i64[3]
  i = 0 ## i64
  current = 0 ## i64
  while i < rank
    fields = lines[i+1].split(" ")
    if fields.size() != 3
      return 0 - 1
    axis = 0 ## i64
    while axis < 3
      term[axis] = ffw_parse_decimal_i64(fields[axis])
      if term[axis] <= 0 || (term[axis] & masks[axis]) != term[axis]
        return 0 - 1
      axis += 1
    current = ffw_toggle(st,term[0],term[1],term[2],current)
    i += 1
  st[6] = current
  if current != rank || ffbo_verify(st,n,m,p) != 1
    return 0 - 1
  z = ffw_copy_current_to_best(st) ## i64
  current

-> ffbo_dump(st, path, n, m, p) (i64[] String i64 i64 i64) i64
  if ffbo_verify(st,n,m,p) != 1
    return 0 - 1
  body = st[6].to_s() + "\n"
  i = 0 ## i64
  while i < st[6]
    slot = st[st[50]+i] ## i64
    body = body + st[st[44]+slot].to_s() + " " + st[st[45]+slot].to_s() + " " + st[st[46]+slot].to_s() + "\n"
    i += 1
  z = write_file(path,body)
  st[6]
