# Witness-backed, bounded on-demand block/Kronecker closure. Prices advise;
# replay pins every actual leaf and full-checks it, never trusting a rank table.
use wide_binary
use wide_pairs
use pages
use ../compose

-> ffcl_key(n, m, p) (i64 i64 i64) i64
  a = n ## i64
  b = m ## i64
  c = p ## i64
  if a > b
    t = a ## i64
    a = b
    b = t
  if b > c
    t = b ## i64
    b = c
    c = t
  if a > b
    t = a ## i64
    a = b
    b = t
  (a*33+b)*33+c

-> ffcl_fields(raw) (String)
  if raw == nil
    return []
  f = raw.split(" ")
  if f.size() != 6 || f[0] != "L" || ffrf_hash_valid(f[1]) != 1
    return []
  rank = ffpk_decimal(f[2]) ## i64
  n = ffpk_decimal(f[3]) ## i64
  m = ffpk_decimal(f[4]) ## i64
  p = ffpk_decimal(f[5]) ## i64
  if rank < 1 || rank > 8000 || ffck_shape(n,m,p) == 0 || raw != "L " + f[1] + " " + rank.to_s() + " " + n.to_s() + " " + m.to_s() + " " + p.to_s()
    return []
  f

# Advisory best-body library; full rank ties remain in the main archive.
# Called only after the caller's complete tensor gate. Atomic replacement
# makes an interrupted update replayable without append-counter ambiguity.
-> ffcl_register(root, identity, rank, n, m, p) (String String i64 i64 i64 i64) i64
  if ffck_shape(n,m,p) == 0 || rank > 8000
    return 1
  if rank < 1 || ffrf_hash_valid(identity) != 1 || !File.mkdir_p(root + "/composition/closure/plans") || !File.mkdir_p(root + "/composition/closure/recipes")
    return 0
  path = root + "/composition/closure/leaves"
  raw = File.read_prefix(path,1048577)
  rows = []
  if raw != nil
    if raw.size() > 1048576 || !raw.ends_with?("\n")
      return 0
    rows = raw.strip().split("\n")
    if rows.size() < 1 || rows.size() > 5985 || rows[0] != "MFW_LIBRARY1"
      return 0
  else
    rows.push("MFW_LIBRARY1")
  key = ffcl_key(n,m,p) ## i64
  replacement = "L " + identity + " " + rank.to_s() + " " + n.to_s() + " " + m.to_s() + " " + p.to_s()
  found = 0 ## i64
  i = 1 ## i64
  while i < rows.size()
    f = ffcl_fields(rows[i])
    if f.size() != 6
      return 0
    if ffcl_key(ffpk_decimal(f[3]),ffpk_decimal(f[4]),ffpk_decimal(f[5])) == key
      if found != 0
        return 0
      if ffpk_decimal(f[2]) <= rank
        return 1
      rows[i] = replacement
      found = 1
    i += 1
  if found == 0
    if rows.size() >= 5985
      return 0
    rows.push(replacement)
  text = StringBuffer(128*rows.size()) ## recycle
  i = 0
  while i < rows.size()
    text.append(rows[i] + "\n")
    i += 1
  ffrf_atomic(path,text.to_s(),"closure-library")

-> ffcl_decimal_leaf(raw, out, n, m, p) (String i64[] i64 i64 i64) i64
  if n*m > 63 || m*p > 63 || n*p > 63
    return 0
  lines = raw.strip().split("\n")
  if lines.size() < 1
    return 0
  first = lines[0].split(" ")
  base = 1 ## i64
  field = 0 ## i64
  rank = ffpk_decimal(lines[0]) ## i64
  if first.size() == 4 && first[0] == "R"
    base = 0
    field = 1
    rank = lines.size()
  elsif lines.size() > 1 && lines[1].starts_with?("R ")
    field = 1
  stride = ffck_shape(n,m,p) ## i64
  if stride == 0 || rank < 1 || rank > 8000 || lines.size() != rank+base || out.size() < 3*stride*rank
    return 0
  i = 0 ## i64
  while i < rank
    f = lines[i+base].split(" ")
    if f.size() != 3+field || (field == 1 && f[0] != "R")
      return 0
    axis = 0 ## i64
    while axis < 3
      value = ffsc_parse_i64(f[field+axis]) ## i64
      if value <= 0 || f[field+axis] != value.to_s()
        return 0
      limb = 0 ## i64
      while limb < stride
        out[(3*i+axis)*stride+limb] = (value >> (32*limb)) & 4294967295
        limb += 1
      axis += 1
    i += 1
  ffpk_canonicalize(out,out.size(),rank,stride)

# Runtime paths are supplied by the coordinator, not baked into a binary.
# Only pinned packaged GF(2) bodies are imported; private research certificates
# and public rank-only tables are deliberately not runtime dependencies.
-> ffcl_catalog(root, runtime) (String String) i64
  if runtime == ""
    return 1
  raw = File.read_prefix(runtime + "/manifests/seeds.tsv",262145)
  if raw == nil || raw.size() > 262144
    return 0
  pin = Crypto:SHA256.hexdigest(raw)
  path = root + "/composition/closure/catalog"
  old = File.read_prefix(path,66)
  if old == pin + "\n"
    return 1
  lines = raw.strip().split("\n")
  if lines.size() < 2 || lines.size() > 1025 || lines[0] != "runtime_path\tsha256\tcurated_corpus_path"
    return 0
  out = i64[3*32*8000]
  parity = i64[32768]
  i = 1 ## i64
  while i < lines.size()
    if File.exists?(root + "/stop")
      return 0-1
    f = lines[i].split("\t")
    if f.size() != 3 || !f[0].starts_with?("lib/metaflip/seeds/gf2/matmul_") || !f[0].ends_with?("_gf2.txt") || f[0].include?("..") || ffrf_hash_valid(f[1]) != 1
      return 0
    name = f[0].slice(23,f[0].size()-23).split("_")
    if name.size() < 3 || name[0] != "matmul"
      return 0
    d = name[1].split("x")
    if d.size() != 2 && d.size() != 3
      return 0
    n = ffpk_decimal(d[0]) ## i64
    m = ffpk_decimal(d[1]) ## i64
    p = n ## i64
    if d.size() == 3
      p = ffpk_decimal(d[2])
    elsif n != m
      return 0
    body = File.read_prefix(runtime + "/" + f[0].slice(13,f[0].size()-13),1048577)
    if body == nil || body.size() > 1048576 || Crypto:SHA256.hexdigest(body) != f[1]
      return 0
    rank = ffcl_decimal_leaf(body,out,n,m,p) ## i64
    if rank < 1 || ffpk_exact(out,out.size(),rank,n,m,p,parity,parity.size(),20000000) != 1
      return 0
    blob = ffpk_blob(out,rank,n,m,p)
    identity = Crypto:SHA256.hexdigest(blob)
    if !File.mkdir_p(root + "/composition/objects") || ffrf_atomic(root + "/composition/objects/" + identity + ".tensor",blob,"closure-catalog") != 1 || ffcl_register(root,identity,rank,n,m,p) != 1
      return 0
    i += 1
  # Preserve the independently checked projected leaf already used by the
  # shared-pair arm, even if its raw catalogue parent is not cheapest.
  leaf = pair_leaf()
  j = 0 ## i64
  while j < 45
    out[j] = leaf[j]
    j += 1
  rank = ffpk_canonicalize(out,out.size(),15,1)
  if rank != 15 || ffpk_exact(out,out.size(),rank,3,2,3,parity,parity.size(),20000000) != 1
    return 0
  blob = ffpk_blob(out,rank,3,2,3)
  identity = Crypto:SHA256.hexdigest(blob)
  if ffrf_atomic(root + "/composition/objects/" + identity + ".tensor",blob,"closure-catalog") != 1 || ffcl_register(root,identity,rank,3,2,3) != 1
    return 0
  ffrf_atomic(path,pin + "\n","closure-catalog")

# Canonical keys memoize complete available-body plans. All children have
# strictly smaller volume; depth is additionally capped against corrupt data.
-> ffcl_price(n, m, p, ranks, kinds, first, second, done, depth) (i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64) i64
  key = ffcl_key(n,m,p) ## i64
  if depth > 96 || ffck_shape(n,m,p) == 0
    return 32769
  if done[key] == 1
    return ranks[key]
  a = key/1089 ## i64
  b = (key/33)%33 ## i64
  c = key%33 ## i64
  if ranks[key] == 0
    ranks[key] = a*b*c
  if a > 1
    shape = [a,b,c]
    axis = 0 ## i64
    while axis < 3
      cut = 1 ## i64
      while 2*cut <= shape[axis]
        l = [a,b,c]
        r = [a,b,c]
        l[axis] = cut
        r[axis] = shape[axis]-cut
        cost = ffcl_price(l[0],l[1],l[2],ranks,kinds,first,second,done,depth+1)+ffcl_price(r[0],r[1],r[2],ranks,kinds,first,second,done,depth+1) ## i64
        if cost < ranks[key]
          ranks[key] = cost
          kinds[key] = axis+1
          first[key] = (l[0]*33+l[1])*33+l[2]
          second[key] = (r[0]*33+r[1])*33+r[2]
        cut += 1
      axis += 1
    x = 1 ## i64
    while x <= a
      if a%x == 0
        y = 1 ## i64
        while y <= b
          if b%y == 0
            z = 1 ## i64
            while z <= c
              if c%z == 0 && x*y*z > 1 && (a / x)*(b / y)*(c / z) > 1
                cost = ffcl_price(x,y,z,ranks,kinds,first,second,done,depth+1)*ffcl_price(a / x,b / y,c / z,ranks,kinds,first,second,done,depth+1) ## i64
                if cost < ranks[key]
                  ranks[key] = cost
                  kinds[key] = 4
                  first[key] = (x*33+y)*33+z
                  second[key] = ((a / x)*33+b / y)*33+c / z
              z += 1
          y += 1
      x += 1
  done[key] = 1
  ranks[key]

-> ffcl_emit(n, m, p, ranks, kinds, first, second, leaves, records, depth) (i64 i64 i64 i64[] i64[] i64[] i64[] Array Array i64) i64
  if depth > 96 || records.size() >= 8192
    return 0
  key = ffcl_key(n,m,p) ## i64
  prefix = n.to_s() + " " + m.to_s() + " " + p.to_s() + " " + ranks[key].to_s()
  if kinds[key] == 5
    f = ffcl_fields(leaves[first[key]])
    if f.size() != 6
      return 0
    records.push("L " + prefix + " " + f[1] + " " + f[3] + " " + f[4] + " " + f[5])
  elsif kinds[key] == 0
    records.push("N " + prefix)
  else
    l = first[key] ## i64
    r = second[key] ## i64
    left = ffcl_emit(l/1089,(l/33)%33,l%33,ranks,kinds,first,second,leaves,records,depth+1) ## i64
    right = ffcl_emit(r/1089,(r/33)%33,r%33,ranks,kinds,first,second,leaves,records,depth+1) ## i64
    if left < 1 || right < 1 || records.size() >= 8192
      return 0
    records.push("B " + prefix + " " + (kinds[key]-1).to_s() + " " + left.to_s() + " " + right.to_s())
  records.size()

-> ffcl_tables(leaves, ranks, kinds, first) (Array i64[] i64[] i64[]) i64
  if leaves.size() < 1 || leaves.size() > 5985 || leaves[0] != "MFW_LIBRARY1"
    return 0
  i = 1 ## i64
  while i < leaves.size()
    f = ffcl_fields(leaves[i])
    if f.size() != 6
      return 0
    key = ffcl_key(ffpk_decimal(f[3]),ffpk_decimal(f[4]),ffpk_decimal(f[5])) ## i64
    rank = ffpk_decimal(f[2]) ## i64
    if rank <= (key/1089)*((key/33)%33)*(key%33) && (ranks[key] == 0 || rank < ranks[key])
      ranks[key] = rank
      kinds[key] = 5
      first[key] = i
    i += 1
  1

# A context freezes its plan BEFORE constructing/admitting it. Legacy source
# tickets keep their original cache key; repricing pins source AND library.
-> ffcl_plan_from(root, identity, n, m, p, before, context, raw) (String String i64 i64 i64 i64 String String)
  if ffrf_hash_valid(identity) != 1 || ffrf_hash_valid(context) != 1 || before < 1 || before > 16384 || !File.mkdir_p(root + "/composition/closure/plans")
    return ""
  path = root + "/composition/closure/plans/" + context
  old = File.read_prefix(path,66)
  if old != nil
    if old.size() != 65 || !old.ends_with?("\n") || ffrf_hash_valid(old.strip()) != 1
      return ""
    plan = File.read_prefix(root + "/composition/closure/recipes/" + old.strip(),1048577)
    if plan == nil || Crypto:SHA256.hexdigest(plan) != old.strip()
      return ""
    return plan
  if raw == nil || raw.size() > 1048576 || !raw.ends_with?("\n")
    return ""
  leaves = raw.strip().split("\n")
  if leaves.size() < 1 || leaves.size() > 5985 || leaves[0] != "MFW_LIBRARY1" || ffck_shape(n,m,p) == 0
    return ""
  ranks = i64[35937]
  kinds = i64[35937]
  first = i64[35937]
  second = i64[35937]
  done = i64[35937]
  if ffcl_tables(leaves,ranks,kinds,first) != 1
    return ""
  price = ffcl_price(n,m,p,ranks,kinds,first,second,done,0) ## i64
  rows = []
  count = 0 ## i64
  if price < before && price <= 8000
    count = ffcl_emit(n,m,p,ranks,kinds,first,second,leaves,rows,0)
    if count < 1
      return ""
  text = StringBuffer(128+128*count) ## recycle
  text.append("MFW_PLAN1 " + identity + " " + n.to_s() + " " + m.to_s() + " " + p.to_s() + " " + count.to_s() + "\n")
  i = 0 ## i64
  while i < rows.size()
    text.append(rows[i] + "\n")
    i += 1
  plan = text.to_s()
  pin = Crypto:SHA256.hexdigest(plan)
  if File.exists?(root + "/stop") || !File.mkdir_p(root + "/composition/closure/recipes") || ffrf_atomic(root + "/composition/closure/recipes/" + pin,plan,"closure-plan") != 1 || ffrf_atomic(path,pin + "\n","closure-plan") != 1
    return ""
  plan

-> ffcl_plan(root, identity, n, m, p, before) (String String i64 i64 i64 i64)
  raw = File.read_prefix(root + "/composition/closure/leaves",1048577)
  ffcl_plan_from(root,identity,n,m,p,before,identity,raw)

# Context identities are not tensor identities. The context pins the actual
# source body and immutable library snapshot; both hashes are checked on use.
-> ffcl_context(root, identity) (String String)
  raw = File.read_prefix(root + "/composition/closure/contexts/" + identity,143)
  if raw == nil || Crypto:SHA256.hexdigest(raw) != identity
    return []
  f = raw.strip().split(" ")
  if f.size() != 3 || f[0] != "MFW_AFFECT1" || ffrf_hash_valid(f[1]) != 1 || ffrf_hash_valid(f[2]) != 1 || raw != "MFW_AFFECT1 " + f[1] + " " + f[2] + "\n"
    return []
  f

-> ffcl_library(root, pin) (String String)
  if ffrf_hash_valid(pin) != 1
    return ""
  raw = File.read_prefix(root + "/composition/closure/libraries/" + pin,1048577)
  if raw == nil || raw.size() > 1048576 || !raw.ends_with?("\n") || Crypto:SHA256.hexdigest(raw) != pin
    return ""
  raw

# Coordinator-only wakeup hint. The cold child validates the whole state.
-> ffcl_pending(root) (String) i64
  if env("METAFLIP_WIDE_TRANSFORMS") == "0"
    return 0
  raw = File.read_prefix(root + "/composition/closure/leaves",1048577)
  if raw == nil
    return 0
  pin = Crypto:SHA256.hexdigest(raw)
  state = File.read_prefix(root + "/composition/closure/sweep",96)
  if state == nil
    return 1
  f = state.strip().split(" ")
  if f.size() != 3 || f[0] != "MFW_SWEEP1" || f[1] != pin
    return 1
  cursor = ffpk_decimal(f[2]) ## i64
  size = raw.strip().split("\n").size() ## i64
  if cursor < 1 || cursor > size || state != "MFW_SWEEP1 " + pin + " " + cursor.to_s() + "\n"
    return 1
  if cursor == size
    return 0
  1

-> ffcl_orient(source, rank, a, b, out) (i64[] i64 i64[] i64[] i64[]) i64
  order = i64[3]
  used = i64[3]
  i = 0 ## i64
  while i < 3
    found = 0-1 ## i64
    j = 0 ## i64
    while j < 3
      if found < 0 && used[j] == 0 && a[j] == b[i]
        found = j
      j += 1
    if found < 0
      return 0
    order[i] = found
    used[found] = 1
    i += 1
  target = i64[3]
  pair_permute(source,rank,a,order,out,target)

-> ffcl_render(root, rows, node, out, meta, work, depth) (String Array i64 i64[] i64[] i64[] i64) i64
  if depth > 96 || node < 1 || node >= rows.size() || File.exists?(root + "/stop")
    return 0
  f = rows[node].split(" ")
  if f.size() != 5 && f.size() != 8 && f.size() != 9
    return 0
  n = ffpk_decimal(f[1]) ## i64
  m = ffpk_decimal(f[2]) ## i64
  p = ffpk_decimal(f[3]) ## i64
  rank = ffpk_decimal(f[4]) ## i64
  stride = ffck_shape(n,m,p) ## i64
  if stride == 0 || rank < 1 || rank > 8000 || out.size() < 3*stride*rank
    return 0
  meta[0] = n
  meta[1] = m
  meta[2] = p
  meta[3] = rank
  if f[0] == "N" && f.size() == 5
    if rank != n*m*p
      return 0
    return ffck_naive(out,n,m,p)
  if f[0] == "L" && f.size() == 9
    if ffrf_hash_valid(f[5]) != 1
      return 0
    sn = ffpk_decimal(f[6]) ## i64
    sm = ffpk_decimal(f[7]) ## i64
    sp = ffpk_decimal(f[8]) ## i64
    ss = ffck_shape(sn,sm,sp) ## i64
    if ss == 0 || ffcl_key(sn,sm,sp) != ffcl_key(n,m,p)
      return 0
    blob = File.read_prefix(root + "/composition/objects/" + f[5] + ".tensor",12632129)
    if blob == nil || Crypto:SHA256.hexdigest(blob) != f[5]
      return 0
    source = i64[3*ss*rank]
    info = i64[4]
    parity = i64[32768]
    if ffpk_parse(blob,source,source.size(),info,info.size()) != rank || info[0] != sn || info[1] != sm || info[2] != sp
      return 0
    checked = ffpk_exact(source,source.size(),rank,sn,sm,sp,parity,parity.size(),20000000) ## i64
    if checked == 0-1
      return 0-2
    if checked != 1
      return 0
    a = i64[3]
    b = i64[3]
    a[0] = sn
    a[1] = sm
    a[2] = sp
    b[0] = n
    b[1] = m
    b[2] = p
    if ffcl_orient(source,rank,a,b,out) != 1
      return 0
    return rank
  if f[0] != "B" || f.size() != 8
    return 0
  kind = ffpk_decimal(f[5]) ## i64
  li = ffpk_decimal(f[6]) ## i64
  ri = ffpk_decimal(f[7]) ## i64
  if kind < 0 || kind > 3 || li < 1 || ri < 1 || li >= node || ri >= node
    return 0
  # Child headers are gated before allocation; no huge mutated rank/slab.
  lf = rows[li].split(" ")
  rf = rows[ri].split(" ")
  if lf.size() < 5 || rf.size() < 5
    return 0
  ls = ffck_shape(ffpk_decimal(lf[1]),ffpk_decimal(lf[2]),ffpk_decimal(lf[3])) ## i64
  rs = ffck_shape(ffpk_decimal(rf[1]),ffpk_decimal(rf[2]),ffpk_decimal(rf[3])) ## i64
  lr = ffpk_decimal(lf[4]) ## i64
  rr = ffpk_decimal(rf[4]) ## i64
  if ls == 0 || rs == 0 || lr < 1 || rr < 1 || lr >= rank || rr >= rank
    return 0
  left = i64[3*ls*lr]
  right = i64[3*rs*rr]
  lm = i64[4]
  rm = i64[4]
  lresult = ffcl_render(root,rows,li,left,lm,work,depth+1) ## i64
  if lresult < 0
    return lresult
  if lresult != lr
    return 0
  rresult = ffcl_render(root,rows,ri,right,rm,work,depth+1) ## i64
  if rresult < 0
    return rresult
  if rresult != rr
    return 0
  canonical = i64[3*stride*rank]
  cm = i64[4]
  result = ffck_binary(left,lr,lm[0],lm[1],lm[2],right,rr,rm[0],rm[1],rm[2],kind,canonical,cm,work,20000000) ## i64
  if result == 0-1
    return 0-2
  if result != rank || ffcl_key(cm[0],cm[1],cm[2]) != ffcl_key(n,m,p)
    return 0
  a = i64[3]
  b = i64[3]
  a[0] = cm[0]
  a[1] = cm[1]
  a[2] = cm[2]
  b[0] = n
  b[1] = m
  b[2] = p
  if ffcl_orient(canonical,rank,a,b,out) != 1
    return 0
  rank

-> ffcl_replay(root, identity, plan, out, meta) (String String String i64[] i64[]) i64
  if plan == "" || plan.size() > 1048576 || !plan.ends_with?("\n") || meta.size() < 4
    return 0-1
  rows = plan.strip().split("\n")
  f = rows[0].split(" ")
  if f.size() != 6 || f[0] != "MFW_PLAN1" || f[1] != identity
    return 0-1
  n = ffpk_decimal(f[2]) ## i64
  m = ffpk_decimal(f[3]) ## i64
  p = ffpk_decimal(f[4]) ## i64
  count = ffpk_decimal(f[5]) ## i64
  if ffck_shape(n,m,p) == 0 || count < 0 || count > 8192 || rows.size() != count+1 || rows[0] != "MFW_PLAN1 " + identity + " " + n.to_s() + " " + m.to_s() + " " + p.to_s() + " " + count.to_s()
    return 0-1
  meta[0] = n
  meta[1] = m
  meta[2] = p
  meta[3] = 0
  if count == 0
    return 0
  work = i64[1]
  rank = ffcl_render(root,rows,count,out,meta,work,0) ## i64
  if rank == 0-2
    return rank
  if rank < 1 || meta[0] != n || meta[1] != m || meta[2] != p
    return 0-1
  ffpk_canonicalize(out,out.size(),rank,ffpk_stride(n,m,p))
