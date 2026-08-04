# End-to-end modular accumulation with a compile-time 2^k modulus.
# Each function spells the modulus literally so the candidate compiler can
# use its modular context; the opt-out compiler evaluates the identical source
# through ordinary shift plus general modulo.

-> bench64(n)
  r = ((1 << 65) + 123456789) ## big
  bump = (1 << 63) + 987654321
  i = 0 ## i64
  t0 = clock()
  while i < n
    r += bump
    r %= 1 << 64
    i += 1
  t1 = clock()
  c = r % 1000000007
  << "modpow2_64\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

-> bench65(n)
  r = ((1 << 66) + 123456789) ## big
  bump = (1 << 64) + 987654321
  i = 0 ## i64
  t0 = clock()
  while i < n
    r += bump
    r %= 1 << 65
    i += 1
  t1 = clock()
  c = r % 1000000007
  << "modpow2_65\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

-> bench127(n)
  r = ((1 << 128) + 123456789) ## big
  bump = (1 << 126) + 987654321
  i = 0 ## i64
  t0 = clock()
  while i < n
    r += bump
    r %= 1 << 127
    i += 1
  t1 = clock()
  c = r % 1000000007
  << "modpow2_127\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

-> bench128(n)
  r = ((1 << 129) + 123456789) ## big
  bump = (1 << 127) + 987654321
  i = 0 ## i64
  t0 = clock()
  while i < n
    r += bump
    r %= 1 << 128
    i += 1
  t1 = clock()
  c = r % 1000000007
  << "modpow2_128\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

-> bench129(n)
  r = ((1 << 130) + 123456789) ## big
  bump = (1 << 128) + 987654321
  i = 0 ## i64
  t0 = clock()
  while i < n
    r += bump
    r %= 1 << 129
    i += 1
  t1 = clock()
  c = r % 1000000007
  << "modpow2_129\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

-> bench256(n)
  r = ((1 << 257) + 123456789) ## big
  bump = (1 << 255) + 987654321
  i = 0 ## i64
  t0 = clock()
  while i < n
    r += bump
    r %= 1 << 256
    i += 1
  t1 = clock()
  c = r % 1000000007
  << "modpow2_256\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

-> bench1024(n)
  r = ((1 << 1025) + 123456789) ## big
  bump = (1 << 1023) + 987654321
  i = 0 ## i64
  t0 = clock()
  while i < n
    r += bump
    r %= 1 << 1024
    i += 1
  t1 = clock()
  c = r % 1000000007
  << "modpow2_1024\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

-> bench4096(n)
  r = ((1 << 4097) + 123456789) ## big
  bump = (1 << 4095) + 987654321
  i = 0 ## i64
  t0 = clock()
  while i < n
    r += bump
    r %= 1 << 4096
    i += 1
  t1 = clock()
  c = r % 1000000007
  << "modpow2_4096\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

args = argv()
workload = args.size() > 0 ? args[0] : "modpow2_128"
n = args.size() > 1 ? args[1].to_i() : 1000000

if workload == "modpow2_64"
  bench64(n)
elsif workload == "modpow2_65"
  bench65(n)
elsif workload == "modpow2_127"
  bench127(n)
elsif workload == "modpow2_128"
  bench128(n)
elsif workload == "modpow2_129"
  bench129(n)
elsif workload == "modpow2_256"
  bench256(n)
elsif workload == "modpow2_1024"
  bench1024(n)
elsif workload == "modpow2_4096"
  bench4096(n)
else
  << "unknown workload: " + workload
  exit 2
