# Polynomial ranged-sum benchmark — multi-term polynomials (Ruby, BigInt).
#
# Ruby's Integer auto-promotes to Bignum, so like Python it computes the
# CORRECT values but must iterate — O(N·REPS) per polynomial. Run with
# --yjit for the fairest interpreter speed.
#
# N/REPS from argv (defaults 1_000_000 / 100), matching every language.

n    = (ARGV[0] || "1000000").to_i
reps = (ARGV[1] || "100").to_i

t1 = t2 = t3 = t7 = t20 = 0
reps.times do |r|
  lo = 1 + r
  hi = n + r
  (lo..hi).each do |x|
    t1  += 2 * x + 3
    t2  += 5 * x**2 - 3 * x + 1
    t3  += 4 * x**3 - 2 * x**2 + 7 * x - 5
    t7  += 92 * x**7 + 13 * x**3 - 5 * x + 8
    t20 += x**20 + 17 * x**13 - 4 * x**5 + 2 * x + 9
  end
end

puts t1
puts t2
puts t3
puts t7
puts t20
