# Whole-language destination-reuse benchmark for compound bitwise and shift
# assignment. Each receiver is seeded from literal-only arithmetic in this
# scope, which is the compiler's fail-closed ownership proof. The GMP twin
# retains one mpz_t destination across the same loop.

-> run_compound(workload, limbs, n)
  r = 0 ## big
  if limbs == 2
    r = (1 << 127) + (1 << 126) + 0x123456789abcdef
  elsif limbs == 4
    r = (1 << 255) + (1 << 254) + 0x123456789abcdef
  elsif limbs == 8
    r = (1 << 511) + (1 << 510) + 0x123456789abcdef
  elsif limbs == 16
    r = (1 << 1023) + (1 << 1022) + 0x123456789abcdef
  elsif limbs == 32
    r = (1 << 2047) + (1 << 2046) + 0x123456789abcdef
  elsif limbs == 64
    r = (1 << 4095) + (1 << 4094) + 0x123456789abcdef
  elsif limbs == 128
    r = (1 << 8191) + (1 << 8190) + 0x123456789abcdef
  elsif limbs == 256
    r = (1 << 16383) + (1 << 16382) + 0x123456789abcdef
  else
    raise "compound_bitwise_loops: unsupported limb count"

  top = limbs * 64 - 1
  mask = (1 << top) + (1 << (top - 2)) + 0xf0f0f0f0f0f0f0f
  i = 0 ## i64
  t0 = clock()
  if workload == "and"
    while i < n
      r &= mask
      i += 1
  elsif workload == "or"
    while i < n
      r |= mask
      i += 1
  elsif workload == "xor"
    while i < n
      r ^= mask
      i += 1
  elsif workload == "shift"
    while i < n
      r <<= 13
      r >>= 13
      i += 1
  else
    raise "compound_bitwise_loops: unknown workload"
  elapsed = clock() - t0
  check = r % 1000000007
  << ("compound\t" + workload + "\t" + limbs.to_s() + "\t" + n.to_s() +
      "\t" + (elapsed * ~1000000000.0 / n.to_f()).to_s() + "\t" +
      check.to_s())

args = argv()
workload = args.size() > 0 ? args[0] : "and"
limbs = args.size() > 1 ? args[1].to_i() : 16
n = args.size() > 2 ? args[2].to_i() : 100000
run_compound(workload, limbs, n)
