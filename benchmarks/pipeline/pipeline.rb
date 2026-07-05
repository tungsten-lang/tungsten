# Fused map-filter-reduce pipeline benchmark (Ruby, idiomatic eager).
#
# The natural Ruby spelling — select.map.sum — materializes two
# intermediate arrays per pass (the filtered range, then the squares).
# This is exactly the allocation Tungsten's fusion elides; the
# benchmark measures that cost honestly against the idiom people write.
#
# Each rep uses a shifted range (1+r .. N+r) so the work can't be hoisted.
# N/REPS from argv (defaults 1_000_000 / 100), matching every language.

N    = (ARGV[0] || 1_000_000).to_i
REPS = (ARGV[1] || 100).to_i

total = 0
REPS.times do |r|
  total += (1 + r..N + r).select(&:even?).map { |x| x * x }.sum
end

puts total
