# ConvPolicy: a residual causal temporal convolutional network (TCN) on
# proprioception, the learned half of a convolutional keyframe controller.
#
# Keyframes (Chunk#knot) are a linear convolutional decoder: the command is
# a sparse train of knot impulses (a contraction vector, a velocity vector
# and an acceleration vector at each keyframe) run through a transposed 1-D
# convolution whose kernel is the quintic Hermite basis. ConvPolicy is the
# feedback half: every tick it reads a window of the body's sensation through
# a few dilated causal convolutions and adds a correction to the commanded
# contraction vector, on top of the chunks and their corrections and under
# the reflexes (Skill#after calls `apply`). Its last layer starts at zero, so
# an untrained policy adds exactly nothing and the controller is the
# hand-authored one; training (playground/convkf.py) moves it from there.
#
# Input channels (pair-per-joint bodies, one pos muscle per joint), each
# normalised as (x - tcn_mu<i>) / tcn_sd<i>:
#
#   c of every joint's pos muscle        body.joints order
#   cdot of the same muscles
#   l_foot_contact, r_foot_contact
#   com height, com vx, com vz
#   torso pitch, torso pitch rate
#
# Layers: `tcn_layers` causal convolutions of kernel `tcn_kernel` and
# dilation `tcn_dil<l>` (default 2, 6, 18 ticks: a 53-tick, 212 ms window at
# 4 ms ticks), `tcn_hidden` channels, tanh; from the second on each adds its
# output to its input (residual blocks). A 1 x 1 head maps the last hidden
# layer to one offset per output muscle, clamped to +-tcn_max. Before the
# first tick every layer's history holds its first input (a body at rest).
#
# Weights come from the params file as `tcn_w<k>`, flat, in order: per
# layer W[out][in][tap] then b[out] (tap k - 1 is the current tick, tap j
# reads (k - 1 - j) * dilation ticks back, PyTorch Conv1d's layout), then the
# head's W[out][hidden] and b[out]. Missing weights are zero.
# `tcn_trace` 1 emits the offsets each tick as a `tcn:` command token (2
# also the normalised inputs as `tcnx:`), for playground/convkf.py's parity
# test against its numpy mirror.

+ CausalConv
  ro :nin
  ro :nout
  -> new(@nin, @nout, @k, @d, @w, @b)
    @len = (@k - 1) * @d + 1
    @hist = (0...(@len * @nin)).map -> ~0.0
    @pos = 0
    @primed = false

  -> step(x)
    if !@primed
      s = 0
      while s < @len
        i = 0
        while i < @nin
          @hist[s * @nin + i] = x[i]
          i += 1
        s += 1
      @primed = true
    @pos = (@pos + 1) % @len
    i = 0
    while i < @nin
      @hist[@pos * @nin + i] = x[i]
      i += 1
    y = []
    o = 0
    while o < @nout
      acc = @b[o]
      i = 0
      while i < @nin
        j = 0
        while j < @k
          slot = (@pos - (@k - 1 - j) * @d + @len) % @len
          acc = acc + @w[(o * @nin + i) * @k + j] * @hist[slot * @nin + i]
          j += 1
        i += 1
      y.push(acc)
      o += 1
    y

+ ConvPolicy
  ro :weight_count
  ro :outputs
  -> new(@body, params, @outputs)
    @params = params
    @joints = @body.joints
    @nin = 2 * @joints.size + 7
    hidden = setting("tcn_hidden", ~8.0).to_i
    kern = setting("tcn_kernel", ~3.0).to_i
    nl = setting("tcn_layers", ~3.0).to_i
    @max = setting("tcn_max", ~0.3)
    @trace = setting("tcn_trace", ~0.0)
    @mu = []
    @sd = []
    i = 0
    while i < @nin
      @mu.push(setting("tcn_mu" + i.to_s, ~0.0))
      @sd.push(setting("tcn_sd" + i.to_s, ~1.0))
      i += 1
    @next = 0
    @layers = []
    nin = @nin
    dil = 2
    l = 0
    while l < nl
      d = setting("tcn_dil" + (l + 1).to_s, dil * ~1.0).to_i
      @layers.push(layer(nin, hidden, kern, d))
      nin = hidden
      dil = dil * 3
      l += 1
    @head = layer(hidden, @outputs.size, 1, 1)
    @weight_count = @next

  -> setting(name, default)
    return @params[name] if @params.key?(name)
    default

  # The next n weights of the flat vector.
  -> take(n)
    out = []
    i = 0
    while i < n
      out.push(setting("tcn_w" + @next.to_s, ~0.0))
      @next += 1
      i += 1
    out

  -> layer(nin, nout, k, d)
    w = take(nout * nin * k)
    b = take(nout)
    CausalConv.new(nin, nout, k, d, w, b)

  -> features(f)
    x = []
    @joints.each ->(j) x.push(f.c(@body.pos_index(j)))
    @joints.each ->(j) x.push(f.cdot(@body.pos_index(j)))
    x.push(f.get("l_foot_contact"))
    x.push(f.get("r_foot_contact"))
    x.push(f.at("com_pos", 2))
    x.push(f.at("com_vel", 0))
    x.push(f.at("com_vel", 2))
    x.push(f.torso_pitch)
    x.push(f.torso_pitch_rate)
    i = 0
    while i < @nin
      x[i] = (x[i] - @mu[i]) / @sd[i]
      i += 1
    x

  # One tick: normalised inputs through the layers and the head; returns the
  # clamped offsets (one per output muscle).
  -> step(x)
    h = @layers[0].step(x).map -> Math.tanh(item)
    l = 1
    while l < @layers.size
      z = @layers[l].step(h)
      i = 0
      while i < h.size
        h[i] = h[i] + Math.tanh(z[i])
        i += 1
      l += 1
    y = @head.step(h)
    i = 0
    while i < y.size
      y[i] = @max if y[i] > @max
      y[i] = ~0.0 - @max if y[i] < ~0.0 - @max
      i += 1
    y

  # Add this tick's correction to the command (call from Skill#after).
  -> apply(frame, ctl)
    x = features(frame)
    ctl.emit("tcnx:" + x.join(",")) if @trace > ~1.5
    y = step(x)
    i = 0
    while i < @outputs.size
      ctl.add_offset(@outputs[i], y[i])
      i += 1
    ctl.emit("tcn:" + y.join(",")) if @trace > ~0.5
    y
