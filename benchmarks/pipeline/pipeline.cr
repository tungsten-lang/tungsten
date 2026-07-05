# Fused map-filter-reduce pipeline benchmark (Crystal, idiomatic eager).
#
# Like Ruby, the natural select.map.sum spelling — but Crystal compiles
# to native code, so it shows what an AOT-compiled allocating pipeline
# costs versus Tungsten's fused (zero-allocation) one.
#
# Each rep uses a shifted range (1+r .. N+r) so the work can't be hoisted.
# N/REPS from argv (defaults 1_000_000 / 100), matching every language.

n    = (ARGV[0]? || "1000000").to_i
reps = (ARGV[1]? || "100").to_i

total = 0_u64
reps.times do |r|
  total += (1 + r..n + r).select(&.even?).map { |x| x.to_u64 * x.to_u64 }.sum
end

puts total
