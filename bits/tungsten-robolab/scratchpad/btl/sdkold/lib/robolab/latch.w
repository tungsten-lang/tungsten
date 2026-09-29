# Latch: a condition on sensation that ends (or releases) a chunk.
#
# Movements are chunked, and the joins between chunks are where sensation
# matters: a stride's push-off begins when the foot is loaded, a swing
# commits when the ball is close, a dribble push starts when the palm feels
# the ball. A latch is checked every tick with the current frame and the
# time spent in the chunk; `min` guards against firing too early (e.g. a
# lingering contact from the previous step).

+ Latch
  ro :label
  -> new(@label, @test)
    @min = ~0.0

  -> after_min(seconds)
    @min = seconds
    self

  -> fired?(frame, elapsed, ctl)
    return false if elapsed < @min
    @test.call(frame, elapsed, ctl)

  -> .after(seconds)
    Latch.new("after", ->(f, e, c) e >= seconds)

  -> .contact(name, threshold = ~0.05)
    Latch.new("contact:" + name, ->(f, e, c) f.get(name + "_contact") > threshold)

  -> .release(name, threshold = ~0.02)
    Latch.new("release:" + name, ->(f, e, c) f.get(name + "_contact") <= threshold)

  -> .above(sensor, k, value)
    Latch.new(sensor + ">", ->(f, e, c) f.at(sensor, k) > value)

  -> .below(sensor, k, value)
    Latch.new(sensor + "<", ->(f, e, c) f.at(sensor, k) < value)

  # Arbitrary predicate callback(frame, elapsed, controller) -> bool.
  -> .test(label, callback)
    Latch.new(label, callback)

  -> .any(latches)
    Latch.new("any", ->(f, e, c) latches.any? -> item.fired?(f, e, c))

  -> .all(latches)
    Latch.new("all", ->(f, e, c) latches.all? -> item.fired?(f, e, c))
