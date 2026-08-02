# Counter-based Philox streams for reproducible independent-address sampling.
#
# Philox2x32-10 is splittable by a 32-bit stream identifier.  It is designed
# for parallel simulation, not for cryptographic use.  Stream independence is
# inherited from the algorithm's design and is not proven by this module.

use core/probability/primitives

+ ProbabilityCounterRng
  -> .multiply_high_low(left, right)
    # Exact 32x32 -> high/low using 16-bit limbs, avoiding a 64-bit product.
    left_low = left & 0xFFFF
    left_high = (left >> 16) & 0xFFFF
    right_low = right & 0xFFFF
    right_high = (right >> 16) & 0xFFFF
    product_low = left_low*right_low
    product_cross_left = left_high*right_low
    product_cross_right = left_low*right_high
    product_high = left_high*right_high
    middle = ((product_low >> 16) +
              (product_cross_left & 0xFFFF) +
              (product_cross_right & 0xFFFF))
    low = (((middle & 0xFFFF) << 16) | (product_low & 0xFFFF)) & 0xFFFFFFFF
    high = (product_high + (product_cross_left >> 16) +
            (product_cross_right >> 16) + (middle >> 16)) & 0xFFFFFFFF
    [high, low]

  -> .multiply_low(left, right)
    ProbabilityCounterRng.multiply_high_low(left, right)[1]

  -> .mix32(value)
    mixed = value & 0xFFFFFFFF
    mixed = mixed ^ (mixed >> 16)
    mixed = ProbabilityCounterRng.multiply_low(mixed, 0x85EBCA6B)
    mixed = mixed ^ (mixed >> 13)
    mixed = ProbabilityCounterRng.multiply_low(mixed, 0xC2B2AE35)
    (mixed ^ (mixed >> 16)) & 0xFFFFFFFF

  -> new(seed = 1, stream = 0)
    if !ProbabilityNumerics.integer?(seed) || !ProbabilityNumerics.integer?(stream)
      raise "probability counter RNG seed and stream must be integers"
    @seed = seed & 0xFFFFFFFF
    @stream = stream & 0xFFFFFFFF
    @key = ProbabilityCounterRng.mix32(
      @seed ^ ProbabilityCounterRng.mix32(@stream))
    @counter_low = 0
    @counter_high = 0
    @buffer = []
    @buffer_index = 0
    self

  -> seed
    @seed

  -> stream
    @stream

  -> counter
    [@counter_low, @counter_high]

  -> algorithm
    "philox2x32-10"

  -> cryptographic?
    false

  -> splittable?
    true

  -> split(stream)
    ProbabilityCounterRng.new(@seed, stream)

  -> generate_pair
    left = @counter_low
    right = @counter_high
    key = @key
    round = 0
    while round < 10
      product = ProbabilityCounterRng.multiply_high_low(0xD256D193, left)
      left = (product[0] ^ key ^ right) & 0xFFFFFFFF
      right = product[1]
      key = (key + 0x9E3779B9) & 0xFFFFFFFF
      round += 1
    @buffer = [left, right]
    @buffer_index = 0
    @counter_low = (@counter_low + 1) & 0xFFFFFFFF
    if @counter_low == 0
      @counter_high = (@counter_high + 1) & 0xFFFFFFFF
    self

  -> next_u32
    generate_pair if @buffer_index >= @buffer.size
    value = @buffer[@buffer_index]
    @buffer_index += 1
    value

  -> random
    next_u32 / ~4294967296.0

  -> integer(limit)
    if !ProbabilityNumerics.integer?(limit) || limit <= 0 || limit > 4294967296
      raise "probability RNG integer limit must be in 1..4294967296"
    threshold = 4294967296 - (4294967296 % limit)
    draw = next_u32
    while draw >= threshold
      draw = next_u32
    draw % limit

  -> randoms(count)
    ProbabilityNumerics.validate_count(count, "random vector size")
    result = []
    count.times -> result.push(random)
    result
