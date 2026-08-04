# Whole-language `r +/-= x * word` workload for the GLM-12 fusion audit.
# Each accumulator is initialized from literal-only arithmetic so the
# fail-closed mutate-if-unique analysis may prove its old value dies at the
# compound assignment.  The subtraction cases prefill outside the timed
# region and remain positive for every iteration.

-> emit_result(workload, limbs, n, elapsed, check)
  << (workload + "\t" + limbs.to_s() + "\t" + n.to_s() + "\t" +
      (elapsed * ~1000000000.0 / n.to_f()).to_s() + "\t" + check.to_s())

-> addmul_1(n)
  r = (1 << 61) + 17
  x = (1 << 58) + 12345
  i = 0 ## i64
  t0 = clock()
  while i < n
    r += x * 3
    i += 1
  check = r % 1000000007
  emit_result("addmul", 1, n, clock() - t0, check)

-> addmul_16(n)
  r = (1 << 1021) + 17
  x = (1 << 1018) + 12345
  i = 0 ## i64
  t0 = clock()
  while i < n
    r += x * 3
    i += 1
  check = r % 1000000007
  emit_result("addmul", 16, n, clock() - t0, check)

-> addmul_256(n)
  r = (1 << 16381) + 17
  x = (1 << 16378) + 12345
  i = 0 ## i64
  t0 = clock()
  while i < n
    r += x * 3
    i += 1
  check = r % 1000000007
  emit_result("addmul", 256, n, clock() - t0, check)

-> submul_1(n)
  r = (1 << 61) + 17
  x = (1 << 58) + 12345
  r += x * (3 * n + 1)
  i = 0 ## i64
  t0 = clock()
  while i < n
    r -= x * 3
    i += 1
  check = r % 1000000007
  emit_result("submul", 1, n, clock() - t0, check)

-> submul_16(n)
  r = (1 << 1021) + 17
  x = (1 << 1018) + 12345
  r += x * (3 * n + 1)
  i = 0 ## i64
  t0 = clock()
  while i < n
    r -= x * 3
    i += 1
  check = r % 1000000007
  emit_result("submul", 16, n, clock() - t0, check)

-> submul_256(n)
  r = (1 << 16381) + 17
  x = (1 << 16378) + 12345
  r += x * (3 * n + 1)
  i = 0 ## i64
  t0 = clock()
  while i < n
    r -= x * 3
    i += 1
  check = r % 1000000007
  emit_result("submul", 256, n, clock() - t0, check)

args = argv()
workload = args.size() > 0 ? args[0] : "addmul"
limbs = args.size() > 1 ? args[1].to_i() : 16
n = args.size() > 2 ? args[2].to_i() : 100000

if workload == "addmul"
  if limbs == 1
    addmul_1(n)
  elsif limbs == 16
    addmul_16(n)
  elsif limbs == 256
    addmul_256(n)
  else
    raise "linear_word_loops: unsupported limb count"
elsif workload == "submul"
  if limbs == 1
    submul_1(n)
  elsif limbs == 16
    submul_16(n)
  elsif limbs == 256
    submul_256(n)
  else
    raise "linear_word_loops: unsupported limb count"
else
  raise "linear_word_loops: unknown workload"
