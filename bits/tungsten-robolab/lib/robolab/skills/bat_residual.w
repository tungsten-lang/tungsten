# BatConvResidual (batting round 2): the fixed features of the Codex challenger's zero-initialised temporal residual
# (GptTemporalResidual, lib/robolab/skills/gpt_temporal.w in the Codex worktree: two causal separable convolutions at 50 Hz over
# muscle-group contraction / velocity / acceleration / jerk and six task sensors, fixed projections, tanh-like squash), reimplemented
# on robolab's SDK with the same architecture and the same fixed numbers, so a readout trained on one can be tried on the other.
# Here it only provides the five features [1, f1 .. f4]; BatPowerSkill#temporal_residual holds the readout (tc0-tc19, zero =
# no residual) and applies the result as joint offsets on the knots' reflex target.
#
# Inputs (22): for each of 4 muscle groups (muscle index mod 4, as the Codex module has it) the mean of clip(2c - 1), clip(cdot / 5),
# clip(accel / 100), clip(jerk / 2000), then six task sensors clipped to +-1. Layer 1: the last 3 samples (weights .5 .3 .2) through a
# 4 x 22 projection, squash. Layer 2: hidden samples 0, 2, 4 ticks back (weights .5 .3 .2) through a 4 x 4 mix, squash.
+ BatConvResidual
  ro :feats
  -> new
    @proj = [~-0.075742, ~-0.160814, ~-0.267182, ~0.459288, ~-0.503121, ~0.203481, ~-0.532079, ~-0.132835, ~-0.407105, ~0.504682, ~0.300213, ~0.254511, ~-0.175751, ~0.522433, ~-0.019728, ~-0.089879, ~0.035673, ~-0.267919, ~-0.397566, ~0.247536, ~-0.300111, ~-0.20026, ~-0.254387, ~-0.071873, ~0.10022, ~0.049688, ~0.543067, ~0.349385, ~-0.425184, ~-0.046856, ~0.033094, ~0.308051, ~-0.305408, ~-0.454062, ~-0.383822, ~0.092069, ~0.221747, ~-0.51271, ~-0.345451, ~0.198317, ~0.354997, ~0.230415, ~0.040928, ~-0.175654, ~-0.128537, ~0.07857, ~-0.071113, ~0.39595, ~-0.40625, ~-0.080815, ~0.412259, ~-0.140669, ~0.143273, ~-0.208738, ~-0.290345, ~-0.079816, ~-0.442956, ~0.482603, ~0.514361, ~-0.288987, ~-0.169145, ~-0.37308, ~0.17345, ~-0.272803, ~0.166861, ~-0.336768, ~0.293925, ~0.489662, ~-0.213637, ~0.134088, ~-0.452508, ~0.298226, ~-0.426803, ~-0.47835, ~0.361035, ~-0.415704, ~0.058165, ~-0.245611, ~-0.46925, ~0.511635, ~-0.549921, ~-0.236655, ~0.016017, ~0.209911, ~-0.340624, ~-0.217195, ~-0.062675, ~-0.284665]
    @mix = [~0.717546, ~-0.933305, ~-0.719459, ~0.294269, ~-1.022432, ~0.479291, ~-0.227153, ~1.034226, ~0.478913, ~-0.561076, ~0.297013, ~0.656701, ~1.172786, ~-0.946464, ~-0.151709, ~0.240772]
    @feats = [~1.0, ~0.0, ~0.0, ~0.0, ~0.0]
    reset

  -> reset
    @hist = []
    @hidden = []
    @pv = nil
    @pa = nil
    @last = ~-1.0
    @feats = [~1.0, ~0.0, ~0.0, ~0.0, ~0.0]
    self

  -> clip(x)
    return ~-1.0 if x < ~-1.0
    return ~1.0 if x > ~1.0
    x

  -> squash(x)
    x / (~1.0 + x.abs)

  -> sample(hist, delay, channel)
    k = hist.size - 1 - delay
    k = 0 if k < 0
    hist[k][channel]

  # Every 20 ms: push the inputs, run the two layers, leave the features in feats.
  -> update(f, sensors)
    return nil if @last >= ~0.0 && f.t - @last < ~0.0199
    elapsed = ~0.02
    elapsed = f.t - @last if @last >= ~0.0
    @last = f.t
    x = (0...22).map ->(i) ~0.0
    counts = [~0.0, ~0.0, ~0.0, ~0.0]
    rates = []
    accels = []
    i = 0
    while i < f.muscle_count
      v = f.cdot(i)
      a = ~0.0
      j = ~0.0
      if @pv != nil
        a = (v - @pv[i]) / elapsed
        j = (a - @pa[i]) / elapsed
      rates.push(v)
      accels.push(a)
      g = i % 4
      counts[g] = counts[g] + ~1.0
      x[g * 4] = x[g * 4] + clip(~2.0 * f.c(i) - ~1.0)
      x[g * 4 + 1] = x[g * 4 + 1] + clip(v / ~5.0)
      x[g * 4 + 2] = x[g * 4 + 2] + clip(a / ~100.0)
      x[g * 4 + 3] = x[g * 4 + 3] + clip(j / ~2000.0)
      i += 1
    @pv = rates
    @pa = accels
    i = 0
    while i < 16
      x[i] = x[i] / counts[i / 4] if counts[i / 4] > ~0.0
      i += 1
    i = 0
    while i < 6
      x[16 + i] = clip(sensors[i])
      i += 1
    @hist.push(x)
    @hist.shift if @hist.size > 3
    h = []
    o = 0
    while o < 4
      s = ~0.0
      i = 0
      while i < 22
        v = ~0.5 * sample(@hist, 0, i) + ~0.3 * sample(@hist, 1, i) + ~0.2 * sample(@hist, 2, i)
        s = s + @proj[o * 22 + i] * v
        i += 1
      h.push(squash(s))
      o += 1
    @hidden.push(h)
    @hidden.shift if @hidden.size > 5
    fs = [~1.0]
    o = 0
    while o < 4
      s = ~0.0
      i = 0
      while i < 4
        v = ~0.5 * sample(@hidden, 0, i) + ~0.3 * sample(@hidden, 2, i) + ~0.2 * sample(@hidden, 4, i)
        s = s + @mix[o * 4 + i] * v
        i += 1
      fs.push(squash(s))
      o += 1
    @feats = fs
    nil
