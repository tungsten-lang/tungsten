# Temperature + multinomial sampling over a Metal logits buffer.
#
# Wraps an xorshift64 RNG and a CPU-side softmax-then-sample pass.
# CPU-side is fine: reading 151936 logits from a shared MTLBuffer is
# ~3 ms, the softmax is another few ms, and the cumulative-walk pick
# is bounded by O(n_vocab). All small relative to the ~400 ms forward
# step that produced the logits.

in Tungsten:Llama

# Single-step xorshift64 — wrapped to avoid escaping the i48 boxed-int
# range (Tungsten ints are 48-bit). Mask after each shift.
fn xorshift64(state)
  s = state ^ ((state << 13) & 0xFFFFFFFFFFFF)
  s = s ^ (s >> 7)
  s = s ^ ((s << 17) & 0xFFFFFFFFFFFF)
  s & 0xFFFFFFFFFFFF

+ Sampler
  rw :state         # i64 RNG state (xorshift64)
  rw :temperature   # f32; 0.0 means greedy argmax
  rw :top_k         # i32; 0 means full-vocab sampling, K > 0 restricts to
                    # the K highest-logit tokens (helps avoid repetition
                    # loops at moderate temperatures).

  -> new(temperature, top_k, seed)
    @temperature = temperature
    @top_k = top_k
    @state = seed
    if @state == 0
      @state = 1   # xorshift breaks on 0

  # Generate a uniform float in [0, 1).
  -> next_uniform
    @state = xorshift64(@state)
    # 24 bits of randomness → float in [0, 1) without precision loss
    bits = @state & 0xFFFFFF
    bits * (~1.0 / ~16777216.0)

  # Pick a token from logits_buf (n_vocab f32s).
  #   T == 0: greedy argmax (top_k is ignored).
  #   T  > 0, top_k == 0: softmax over the full vocab.
  #   T  > 0, top_k > 0:  restrict to the top_k highest logits, softmax
  #                       within that set, sample.
  -> sample(logits_buf, n_vocab)
    if @temperature == ~0.0
      return argmax(logits_buf, n_vocab)
    if @top_k > 0 && @top_k < n_vocab
      return sample_top_k(logits_buf, n_vocab)
    sample_full(logits_buf, n_vocab)

  -> sample_full(logits_buf, n_vocab)
    scaled = []
    max_l = ~-1000000000.0
    inv_t = ~1.0 / @temperature
    i = 0
    while i < n_vocab
      v = metal_buffer_read_f32(logits_buf, i) * inv_t
      scaled.push(v)
      if v > max_l
        max_l = v
      i = i + 1
    sum_e = ~0.0
    i = 0
    while i < n_vocab
      e = Math.exp(scaled[i] - max_l)
      scaled[i] = e
      sum_e = sum_e + e
      i = i + 1
    threshold = next_uniform() * sum_e
    cumulative = ~0.0
    i = 0
    while i < n_vocab
      cumulative = cumulative + scaled[i]
      if cumulative > threshold
        return i
      i = i + 1
    n_vocab - 1

  # Top-K sampling: pull the K highest scaled logits in a single O(n_vocab)
  # pass, then softmax those K and sample.
  -> sample_top_k(logits_buf, n_vocab)
    inv_t = ~1.0 / @temperature
    k = @top_k
    selected_idx = []
    selected_val = []
    min_val = ~1000000000.0
    min_pos = 0
    i = 0
    while i < k
      v = metal_buffer_read_f32(logits_buf, i) * inv_t
      selected_idx.push(i)
      selected_val.push(v)
      if v < min_val
        min_val = v
        min_pos = i
      i = i + 1
    while i < n_vocab
      v = metal_buffer_read_f32(logits_buf, i) * inv_t
      if v > min_val
        selected_idx[min_pos] = i
        selected_val[min_pos] = v
        min_val = v
        j = 0
        while j < k
          vj = selected_val[j]
          if vj < min_val
            min_val = vj
            min_pos = j
          j = j + 1
      i = i + 1
    max_v = selected_val[0]
    i = 1
    while i < k
      if selected_val[i] > max_v
        max_v = selected_val[i]
      i = i + 1
    sum_e = ~0.0
    i = 0
    while i < k
      e = Math.exp(selected_val[i] - max_v)
      selected_val[i] = e
      sum_e = sum_e + e
      i = i + 1
    threshold = next_uniform() * sum_e
    cumulative = ~0.0
    i = 0
    while i < k
      cumulative = cumulative + selected_val[i]
      if cumulative > threshold
        return selected_idx[i]
      i = i + 1
    selected_idx[k - 1]

  -> argmax(logits_buf, n_vocab)
    best = 0
    best_v = metal_buffer_read_f32(logits_buf, 0)
    i = 1
    while i < n_vocab
      v = metal_buffer_read_f32(logits_buf, i)
      if v > best_v
        best_v = v
        best = i
      i = i + 1
    best
