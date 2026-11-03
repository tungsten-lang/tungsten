# Exact Boolean expressions: a constant XOR a sum of truth functions on named
# cuts. Equal cut keys denote the same input expressions. Different cuts stay
# independent; this over-approximation can miss an equality, never invent one.
-> wassat_byte_mask_word(width, word) (i64 i64) i64
  bits = (1 << width) - 64 * word
  return 0 if bits <= 0
  return -1 if bits >= 64
  (1 << bits) - 1

-> wassat_byte_truth_set(words, bit) (i64[] i64) i64
  words[bit / 64] |= 1 << (bit & 63)
  0

-> wassat_byte_xor_truth(dst, src) (i64[] i64[]) i64
  j = 0
  while j < 4
    dst[j] ^= src[j]; j += 1
  0

+ WassatByteExpressions
  ro :failed, :cycles, :nodes, :supports, :scheduled_gates, :scheduled_tables, :primary

  -> new(program, inputs, parent, groups, tables, nv, ng, m, stop, deadline)
    @program = program; @inputs = inputs; @parent = parent
    @groups = groups; @tables = tables; @nv = nv; @ng = ng
    @m = m; @stop = stop; @deadline = deadline
    @failed = false; @cycles = 0; @depth = 0; @scheduled_gates = 0; @scheduled_tables = 0; @primary = 0
    @producer = i64[nv + 1]; @producer_bit = i64[nv + 1]
    @memo = i64[nv + 1]; @known = i8[nv + 1]; @busy = i8[nv + 1]
    @table_cache = {}; @support_ids = {}; @support_widths = [0]
    @nodes = [[]]; @node_ids = {}; @supports = 0
    ct = wassat_byte_abs(wassat_byte_find(parent, nv + 1)); v = 1
    while v <= nv
      if (v & 1023) == 0 && wassat_byte_poll(m, stop, deadline) != 0
        @failed = true; return
      b = 8 * v
      if program[b] > 0
        rep = wassat_byte_abs(wassat_byte_find(parent, program[b + 1])); self_dep = false; j = 0
        while j < program[b + 2]
          self_dep = true if wassat_byte_abs(wassat_byte_find(parent, inputs[program[b + 3] + j])) == rep
          j += 1
        @producer[rep] = v if rep != ct && !self_dep && @producer[rep] == 0
      v += 1
    g = 0
    while g < ng
      p = 80 * g
      if groups[p + 3] == 1 << groups[p + 2]
        j = 0
        while j < groups[p + 1]
          rep = wassat_byte_abs(wassat_byte_find(parent, groups[p + 38 + j]))
          if rep != ct
            @producer[rep] = -g - 1; @producer_bit[rep] = j
          j += 1
      g += 1

  # Account conservatively for transient expression containers and keys as
  # well as retained nodes. Reaching the cap is an ordinary UNKNOWN miss.
  -> charge(bytes)
    @m[37] += bytes
    @failed = true if @m[37] > 67108864
    !@failed

  -> support(key, width)
    id = @support_ids[key]
    return id unless id == nil
    if width < 1 || width > 8 || @supports >= 10000
      @failed = true; return 0
    return 0 unless self.charge(512 + key.size * 2)
    @supports += 1
    @support_ids[key] = @supports; @support_widths.push(width)
    @supports

  -> normalize(constant, parts)
    if parts.size > 512 || !self.charge(512 + 640 * parts.size)
      @failed = true; return 0
    flat = []; c = constant
    parts.keys.sort.each -> (k)
      words = parts[k]
      if (words[0] & 1) == 1
        c ^= 1; j = 0
        while j < 4
          words[j] ^= wassat_byte_mask_word(@support_widths[k], j); j += 1
      if words[0] != 0 || words[1] != 0 || words[2] != 0 || words[3] != 0
        flat.push(k); j = 0
        while j < 4
          flat.push(words[j]); j += 1
    return c if flat.empty?
    key = flat.join(",")
    id = @node_ids[key]
    if id == nil
      if @nodes.size >= 50000
        @failed = true; return 0
      id = @nodes.size; @nodes.push(flat); @node_ids[key] = id
    2 * id + c

  -> atom(key)
    k = self.support(key, 1); words = i64[4]; words[0] = 2
    parts = {}; parts[k] = words
    self.normalize(0, parts)

  -> xor_values(es)
    return 0 unless self.charge(512 + 64 * es.size)
    c = 0; parts = {}
    es.each -> (e)
      c ^= e & 1; flat = @nodes[e / 2]; j = 0
      return 0 unless self.charge(128 * flat.size)
      while j < flat.size
        k = flat[j]; words = parts[k]
        if words == nil
          words = i64[4]; parts[k] = words
        b = 0
        while b < 4
          words[b] ^= flat[j + 1 + b]; b += 1
        j += 5
    self.normalize(c, parts)

  -> and_values(es)
    return 0 unless self.charge(512 + 256 * es.size)
    seen = {}; unique = []
    es.each -> (e)
      return 0 if e == 0 || seen[e ^ 1] == true
      if e != 1 && seen[e] != true
        seen[e] = true; unique.push(e)
    return 1 if unique.empty?
    return unique[0] if unique.size == 1
    keys = {}
    unique.each -> (e)
      flat = @nodes[e / 2]; j = 0
      while j < flat.size
        keys[flat[j]] = true; j += 5
    if keys.size == 1
      k = keys.keys[0]; words = i64[4]; b = 0
      while b < 4
        words[b] = wassat_byte_mask_word(@support_widths[k], b); b += 1
      unique.each -> (e)
        flat = @nodes[e / 2]; b = 0
        while b < 4
          x = flat[1 + b]
          x ^= wassat_byte_mask_word(@support_widths[k], b) if (e & 1) == 1
          words[b] &= x; b += 1
      parts = {}; parts[k] = words
      return self.normalize(0, parts)
    self.atom("and:[unique.sort.join(',')]")

  -> table_values(g)
    cached = @table_cache[g]
    return cached unless cached == nil
    return [] unless self.charge(8192)
    p = 80 * g; es = []; keys = {}; j = 0
    while j < @groups[p + 2]
      e = self.get(@groups[p + 70 + j]); es.push(e)
      flat = @nodes[e / 2]; k = 0
      while k < flat.size
        keys[flat[k]] = true; k += 5
      j += 1
    no = @groups[p + 1]; result = []
    if keys.empty?
      idx = 0; j = 0
      while j < es.size
        idx |= (es[j] & 1) << j; j += 1
      val = @tables[256 * g + idx]; j = 0
      while j < no
        result.push((val >> j) & 1); j += 1
    else
      shared = keys.size == 1
      if shared
        cut = keys.keys[0]
      else
        cuts = {}; es.each -> (e) cuts[e & -2] = true if e > 1
        cut_es = cuts.keys.sort
        cut = self.support("byte:[cut_es.join(',')]", cut_es.size)
      width = @support_widths[cut]; words = []; j = 0
      while j < no
        words.push(i64[4]); j += 1
      a = 0
      while a < 1 << width
        idx = 0; j = 0
        while j < es.size
          e = es[j]; bit = e & 1
          if e > 1
            if shared
              flat = @nodes[e / 2]
              bit ^= (flat[1 + a / 64] >> (a & 63)) & 1
            else
              k = 0
              while k < cut_es.size && cut_es[k] != (e & -2)
                k += 1
              bit ^= (a >> k) & 1
          idx |= bit << j; j += 1
        value = @tables[256 * g + idx]
        if value < 0
          @failed = true; return []
        j = 0
        while j < no
          wassat_byte_truth_set(words[j], a) if (value >> j) & 1 == 1
          j += 1
        a += 1
      j = 0
      while j < no
        parts = {}; parts[cut] = words[j]
        result.push(self.normalize(0, parts)); j += 1
    @scheduled_tables += 1; @table_cache[g] = result
    result

  -> get(lit)
    if @depth >= 512
      @failed = true; return 0
    @depth += 1
    value = self.get_inner(lit)
    @depth -= 1
    value

  -> get_inner(lit)
    if @failed || wassat_byte_poll(@m, @stop, @deadline) != 0
      @failed = true; return 0
    rep = wassat_byte_find(@parent, lit); ct = wassat_byte_find(@parent, @nv + 1)
    return rep == ct ? 1 : 0 if wassat_byte_abs(rep) == wassat_byte_abs(ct)
    v = wassat_byte_abs(rep)
    if @known[v] == 1
      e = @memo[v]
    elsif @busy[v] == 1
      @cycles += 1; @failed = true; return 0
    else
      @busy[v] = 1; producer = @producer[v]
      if producer == 0
        e = self.atom("input:[v]"); @primary += 1
      elsif producer < 0
        g = -producer - 1; bit = @producer_bit[v]
        out = self.table_values(g)
        if @failed || out.size <= bit
          @failed = true; return 0
        e = out[bit]
        e ^= 1 if wassat_byte_find(@parent, @groups[80 * g + 38 + bit]) < 0
      else
        b = 8 * producer; es = []; j = 0
        while j < @program[b + 2]
          es.push(self.get(@inputs[@program[b + 3] + j])); j += 1
        if @program[b] == 1
          e = self.and_values(es)
        elsif @program[b] == 2
          e = self.xor_values(es) ^ (@program[b + 4] & 1)
        else
          terms = []; a = 0
          while a < 1 << es.size
            if (@program[b + 4] >> a) & 1 == 1
              args = []; j = 0
              while j < es.size
                args.push(es[j] ^ (((a >> j) & 1) == 1 ? 0 : 1)); j += 1
              terms.push(self.and_values(args) ^ 1)
            a += 1
          e = self.and_values(terms) ^ 1
        e ^= 1 if wassat_byte_find(@parent, @program[b + 1]) < 0
        @scheduled_gates += 1
      @busy[v] = 0; @known[v] = 1; @memo[v] = e
    rep > 0 ? e : e ^ 1
