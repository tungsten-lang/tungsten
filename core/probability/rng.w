# Explicit seeded random streams and the small RNG protocol.

use core/stats
use core/probability/primitives

+ ProbabilityRandom
  -> .require_rng(rng)
    if rng == nil || !rng.respond_to?("random")
      raise "probability sampling needs an RNG; use Probability.rng(seed)"
    rng

  -> .random_unit(rng)
    ProbabilityRandom.require_rng(rng)
    value = rng.random.to_f
    if value != value || value < ~0.0 || value >= ~1.0
      raise "probability RNG draws must be at least zero and less than one"
    value

  -> .open_unit(rng)
    ~1.0 - ProbabilityRandom.random_unit(rng)

  -> .standard_normal(rng)
    radial_uniform = ProbabilityRandom.open_unit(rng)
    angular_uniform = ProbabilityRandom.random_unit(rng)
    radius = Math.sqrt(~-2.0 * Math.log(radial_uniform))
    radius * Math.cos(~6.283185307179586 * angular_uniform)


# Stable facade over the committed Stats mulberry32 engine.  It is replayable,
# but not cryptographic, splittable, or suitable for independent GPU streams.
+ ProbabilityRng
  ro :seed

  -> new(seed = 1)
    if !ProbabilityNumerics.integer?(seed)
      raise "probability RNG seed must be an integer"
    @seed = seed & 0xFFFFFFFF
    @seed = 1 if @seed == 0
    @engine = Stats.rng(@seed)
    self

  -> algorithm
    "mulberry32"

  -> cryptographic?
    false

  -> splittable?
    false

  -> next_u32
    @engine.next_u32

  -> random
    @engine.random

  # Unbiased integer in [0, limit) by rejection over the exact u32 stream.
  -> integer(limit)
    if !ProbabilityNumerics.integer?(limit) || limit <= 0 || limit > 4294967296
      raise "probability RNG integer limit must be in 1..4294967296"
    threshold = 4294967296 - (4294967296 % limit)
    draw = next_u32
    while draw >= threshold
      draw = next_u32
    draw % limit
