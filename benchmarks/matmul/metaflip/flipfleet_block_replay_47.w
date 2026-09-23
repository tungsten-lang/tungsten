use flipfleet_block_composer

-> replay_allocations(text) (String)
  parts = text.split(",")
  if parts.size() != 4
    return nil
  result = i64[4]
  i = 0 ## i64
  while i < 4
    value = parts[i].to_i() ## i64
    if value < 1
      return nil
    result[i] = value
    i += 1
  result

av = argv()
if av.size() < 9 || (av.size() - 5) % 4 != 0
  << "usage: replay-47 allocations outer output leaf dimensions and paths"
  exit(1)

n = replay_allocations(av[0])
m = replay_allocations(av[1])
p = replay_allocations(av[2])
if n == nil || m == nil || p == nil
  << "each allocation must have four positive comma-separated dimensions"
  exit(1)
outer = ffbc_load_exact(av[3], 4, 4, 4, 4096)
if outer == nil || outer.rank() != 47
  << "outer must be an exact rank-47 4x4x4 tensor"
  exit(1)

paths = []
ns = i64[0]
ms = i64[0]
ps = i64[0]
i = 5 ## i64
while i < av.size()
  ln = av[i].to_i() ## i64
  lm = av[i + 1].to_i() ## i64
  lp = av[i + 2].to_i() ## i64
  if ln < 1 || lm < 1 || lp < 1
    << "leaf dimensions must be positive"
    exit(1)
  ns.push(ln)
  ms.push(lm)
  ps.push(lp)
  paths.push(av[i + 3])
  i += 4

rank = ffbc_compose_files(av[3], 4, 4, 4, n, m, p, paths, ns, ms, ps, av[4])
if rank < 1
  << "exact block composition failed"
  exit(1)
<< "exact rank " + rank.to_s()
