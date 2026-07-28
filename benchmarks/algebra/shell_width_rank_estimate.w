# CPU reference for the shell-width quartic's prime-trace rank estimator.
#
# This deliberately uses Curve#point_count rather than the optional @gpu
# kernel from the research program.  The dense finite-field fiber kernel is
# exact and gives a portable baseline for any Metal/CUDA implementation.
#
#   bin/tungsten compile benchmarks/algebra/shell_width_rank_estimate.w \
#     --out /tmp/shell-width-rank-estimate
#   /tmp/shell-width-rank-estimate 4000

use algebra

C ⊂ ℙ²_ℚ (B, S, Z) : 16B³Z + 48BS²Z − 3S⁴ + 8S³Z + 162S²Z² + 729Z⁴ = 0

bound = ARGV.size > 0 ? ARGV[0].to_i : 4000
bad_primes = [2, 3, 13]
sum = ~0.0
last_prime = 0

(5...bound).each -> (prime)
  if prime.prime? && !bad_primes.include?(prime)
    trace = C.reduce(prime).frobenius_trace
    logarithm = Math.log(prime + ~0.0)
    sum += (trace + ~0.0) * logarithm / (prime + ~0.0)
    last_prime = prime

if last_prime == 0
  raise "rank-estimate bound contains no good prime"

logarithm = Math.log(last_prime + ~0.0)
estimate = ~0.5 - sum / logarithm
<< "x=" + last_prime.to_s + " S=" + sum.to_s + " rhat=" + estimate.to_s
