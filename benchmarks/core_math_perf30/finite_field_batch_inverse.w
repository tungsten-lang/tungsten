# Matched scalar-vs-prefix/suffix inversion benchmark over a large prime field.

use core/algebra/finite_field

mode = ARGV[0] == nil ? "scalar" : ARGV[0]
count = ARGV[1] == nil ? 512 : ARGV[1].to_i
rounds = ARGV[2] == nil ? 200 : ARGV[2].to_i

field = FiniteField.new(1000003)
values = []
i = 0
while i < count
  values.push((i * 7919 + 17) % 1000003)
  i += 1

result = []
round = 0
t0 = clock()
while round < rounds
  if mode == "scalar"
    result = []
    i = 0
    while i < count
      result.push(field.inverse(values[i]))
      i += 1
  elsif mode == "batch"
    result = field.batch_inverse(values)
  else
    raise "mode must be scalar or batch"
  round += 1
elapsed = clock() - t0

checksum = 0
i = 0
while i < count
  raise "batch inverse mismatch" if field.multiply(values[i], result[i]) != 1
  checksum = field.add(checksum, result[i])
  i += 1

us_per_round = elapsed * ~1000000.0 / rounds.to_f()
<< mode + "\t" + count.to_s() + "\t" + rounds.to_s() + "\t" + us_per_round.to_s() + "\t" + checksum.to_s()
