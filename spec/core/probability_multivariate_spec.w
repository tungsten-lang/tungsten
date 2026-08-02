# Multivariate Normal, SPD factorization, batching, and conditioning contracts.

use probability

-> mv_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> mv_close?(got, want, tolerance = ~1.0e-11)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  scale = want
  scale = ~0.0 - scale if scale < ~0.0
  scale = ~1.0 if scale < ~1.0
  difference <= tolerance*scale

distribution = Probability.multivariate_normal(
  [~1.0, ~-2.0], [[~4.0, ~1.0], [~1.0, ~9.0]])

mv_check("dimension", distribution.dimension == 2)
mv_check("support",
         distribution.support.contains?([~0.0, ~1.0]) &&
         !distribution.support.contains?([~0.0]))
mv_check("cholesky.reconstruct",
         mv_close?(distribution.cholesky[0][0], ~2.0) &&
         mv_close?(distribution.cholesky[1][0], ~0.5) &&
         mv_close?(distribution.cholesky[1][1], ~2.958039891549808))
mv_check("logdet", mv_close?(distribution.log_determinant, Math.log(~35.0)))
mv_check("logpdf.reference",
         mv_close?(distribution.log_prob([~1.0, ~-2.0]),
                   ~-3.615551097154052, ~2.0e-13))
mv_check("mahalanobis",
         mv_close?(distribution.mahalanobis_squared([~3.0, ~-1.0]),
                   ~1.0285714285714285))
batch = distribution.log_probabilities([[~1.0, ~-2.0], [~3.0, ~-1.0]])
mv_check("batch", batch.size == 2 && batch[0] > batch[1])

marginal = distribution.marginal([1])
mv_check("marginal", marginal.dimension == 1 &&
         marginal.mean[0] == ~-2.0 && marginal.covariance[0][0] == ~9.0)

conditional = distribution.condition([0], [~3.0])
mv_check("conditional.mean",
         mv_close?(conditional.mean[0], ~-1.5))
mv_check("conditional.covariance",
         mv_close?(conditional.covariance[0][0], ~8.75))

image = distribution.affine([[~1.0, ~2.0]], [~3.0])
mv_check("affine", image.dimension == 1 &&
         image.mean[0] == ~0.0 && image.covariance[0][0] == ~44.0)

left = distribution.samples(8, Probability.rng(2026))
right = distribution.samples(8, Probability.rng(2026))
replay = true
i = 0
while i < left.size
  j = 0
  while j < left[i].size
    replay = false if left[i][j] != right[i][j]
    j += 1
  i += 1
mv_check("sampling.replay", replay)
mv_check("sampling.vector",
         mv_close?(left[0][0], ~0.20771623305969789, ~2.0e-13) &&
         mv_close?(left[0][1], ~-5.398848612287702, ~2.0e-13))

bad_symmetry = false
begin
  Probability.multivariate_normal([~0.0, ~0.0],
    [[~1.0, ~0.1], [~0.2, ~1.0]])
rescue error
  bad_symmetry = error.to_s.include?("symmetric")
mv_check("failure.symmetry", bad_symmetry)

bad_spd = false
begin
  Probability.multivariate_normal([~0.0, ~0.0],
    [[~1.0, ~2.0], [~2.0, ~1.0]])
rescue error
  bad_spd = error.to_s.include?("positive definite")
mv_check("failure.spd", bad_spd)

bad_dimension = false
begin
  distribution.log_prob([~1.0])
rescue error
  bad_dimension = error.to_s.include?("wrong dimension")
mv_check("failure.dimension", bad_dimension)

<< "probability_multivariate_spec: all checks passed"
