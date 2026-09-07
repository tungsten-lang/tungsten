# Exact offline two-factor fusion. This is a bounded proposal-family join,
# not a rank oracle, and every retained whole scheme needs tensor admission.
require_relative "leaf_delta_collisions"
require_relative "cancellation_patterns"

module MetaflipCofactorMergers
  module_function

  def normalize(terms, axis)
    raise "invalid factor axis" unless axis.is_a?(Integer) && axis.between?(0, 2)
    raise "invalid nonzero terms" unless terms.respond_to?(:each) && terms.all? do |term|
      term.is_a?(Array) && term.length == 3 && term.all? { |v| v.is_a?(Integer) && v.positive? && v.bit_length <= 256 }
    end
    other = (0..2).to_a - [axis]
    result = Hash.new(0)
    terms.each { |t| result[other.map { |a| t[a] }.freeze] ^= t[axis] }
    result.reject { |_, v| v.zero? }
  end

  def materialize(map, axis)
    raise "invalid factor axis" unless axis.is_a?(Integer) && axis.between?(0, 2)
    other = (0..2).to_a - [axis]
    map.map do |key, value|
      term = [0, 0, 0]
      term[axis] = value
      other.each_with_index { |a, i| term[a] = key[i] }
      term
    end
  end

  def merge(left, right)
    result = left.dup
    right.each { |key, value| result[key] = result.fetch(key, 0) ^ value }
    result.reject { |_, value| value.zero? }
  end

  def pair_index(left, right)
    [left, right].each do |pool|
      raise "invalid cofactor pool" unless pool.is_a?(Array) && !pool.empty? && pool.all? do |map|
        map.is_a?(Hash) && map.all? do |key, value|
          key.is_a?(Array) && key.length == 2 && (key + [value]).all? { |v| v.is_a?(Integer) && v.positive? && v.bit_length <= 256 }
        end
      end
    end
    lindex = Hash.new { |h, key| h[key] = [] }
    rindex = Hash.new { |h, key| h[key] = [] }
    left.each_with_index { |map, i| map.each { |key, value| lindex[key] << [i, value] } }
    right.each_with_index { |map, j| map.each { |key, value| rindex[key] << [j, value] } }
    savings = Hash.new(0)
    common = lindex.keys & rindex.keys
    common.each do |key|
      lindex[key].product(rindex[key]).each do |(i, u), (j, v)|
        savings[i * right.length + j] += u == v ? 2 : 1
      end
    end
    [savings, { possible_pairs: left.length * right.length, collision_pairs: savings.length,
      common_keys: common.length, left_states: left.length, right_states: right.length }]
  end

  def minimum_index(left, right, savings)
    a = left.each_index.min_by { |i| [left[i].length, i] }
    b = right.each_index.min_by { |j| [right[j].length, j] }
    best = [left[a].length + right[b].length, a, b]
    savings.each do |packed, saved|
      i, j = packed.divmod(right.length)
      candidate = [left[i].length + right[j].length - saved, i, j]
      best = candidate if (candidate <=> best) == -1
    end
    best
  end

  # Exact minimum of |normalize(L_i + R_j)|. Common keys save one term;
  # equal remaining factors save two. Pairs without any common key need not
  # be expanded: the two independently shortest maps give their lower bound.
  def best_pair(left, right)
    savings, counts = pair_index(left, right)
    best = minimum_index(left, right, savings)
    rank, i, j = best
    result = merge(left[i], right[j])
    raise "cofactor join score mismatch" unless rank == result.length
    counts.merge(rank: rank, indices: [i, j], result: result)
  end

  # Keep the first width index pairs at each cofactor rank from the exact
  # minimum through minimum+slack. Stratification avoids letting a large
  # minimum-rank tie hide all slightly worse cofactor scores. This is ONLY
  # a bounded proposal policy: compression may favor any omitted pair.
  def candidate_pairs(left, right, width:, slack:)
    raise "invalid compression width" unless width.is_a?(Integer) && width.between?(1, 128)
    raise "invalid compression slack" unless slack.is_a?(Integer) && slack.between?(0, 16)
    savings, counts = pair_index(left, right)
    minimum = minimum_index(left, right, savings)
    buckets = Array.new(slack + 1) { [] }
    eligible = Array.new(slack + 1, 0)
    left.each_with_index do |a, i|
      right.each_with_index do |b, j|
        score = a.length + b.length - savings.fetch(i * right.length + j, 0)
        offset = score - minimum[0]
        raise "invalid minimum" if offset.negative?
        next if offset > slack
        eligible[offset] += 1
        buckets[offset] << { rank: score, indices: [i, j] } if buckets[offset].length < width
      end
    end
    counts.merge(minimum: minimum, eligible_by_rank: eligible, candidates: buckets.flatten)
  end

  # One shortlisted kernel word on each of the three vertex axes. These
  # tensor-preserving proposal words need not improve at their prefixes.
  # The caller bounds each pool and admits every selected complete tensor.
  def triple_proposals(leaf, pools, seen: Set.new([leaf.canonical_id]))
    raise "invalid triple pools" unless pools.is_a?(Array) && pools.length == 3 && pools.each_with_index.all? do |pool, axis|
      pool.is_a?(Array) && pool.all? { |a| a[:kind] == "kernel" && a[:axis] == axis }
    end
    return enum_for(__method__, leaf, pools, seen: seen) unless block_given?
    pools[0].product(pools[1], pools[2]).each do |components|
      word = components.flat_map { |a| a.fetch(:word) }
      terms = MetaflipOuterBasisProducts.transvection_word_terms(leaf, word)
      id = Digest::SHA256.hexdigest([leaf.shape.join("x"), MetaflipBudProducts.text(terms.sort)].join("\n"))
      next unless seen.add?(id)
      yield terms, { kind: "kernel_triple", word: word, components: components }
    end
  end

  # Replayable construction, separate from the finite-pool search claim.
  # The raw outer product remains in its own recipe: fusion can lower its
  # rank without being representable as a change to just one abstract leaf.
  def from_product(product_path, slots, axis)
    b = MetaflipBudProducts
    m = MetaflipOuterBasisProducts
    p = MetaflipOuterLeafPortfolio
    m.replay(product_path)
    data = JSON.parse(File.read(product_path))
    base = File.dirname(File.realpath(product_path))
    read = lambda do |entry|
      path = File.realpath(File.join(base, entry.fetch("path")))
      raise "snapshot escapes product" unless path.start_with?(base + "/")
      raise "snapshot hash mismatch" unless Digest::SHA256.file(path).hexdigest == entry.fetch("sha256")
      b.load_scheme(path, entry.fetch("shape"))
    end
    parent = read.call(data.fetch("parent"))
    leaves = data.fetch("leaves").map { |e| e && read.call(e) }
    raise "invalid merge slots" unless slots.is_a?(Array) && slots.length == 2 && slots.uniq.length == 2 &&
      slots.all? { |i| i.is_a?(Integer) && i.between?(0, leaves.length - 1) && leaves[i] }
    parts = leaves.each_with_index.map { |leaf, i| leaf ? p.mapped_terms(parent, i, data.fetch("allocation"), leaf).to_a : [] }
    pair = normalize(slots.flat_map { |i| parts[i] }, axis)
    terms = parts.each_with_index.flat_map { |part, i| slots.include?(i) ? [] : part } + materialize(pair, axis)
    bound = terms.length
    terms = terms.tally.filter_map { |t, n| t if n.odd? }
    native = b::Scheme.new(data.fetch("allocation").map(&:sum), b.text(terms))
    compressed, history = MetaflipSharedFactorCompression.compress(native)
    result = b.orient(compressed, data.fetch("result").fetch("shape"))
    { bound: bound, native: native, result: result, compression: history }
  end

  def export_merge(path, product_path, slots, axis)
    raise "merge recipe already exists" if File.exist?(path)
    base = File.realpath(File.dirname(path))
    product_path = File.realpath(product_path)
    raise "product outside merge artifact" unless product_path.start_with?(base + "/")
    row = from_product(product_path, slots, axis)
    b = MetaflipBudProducts
    data = { schema: 1, kind: "outer-cofactor-merge", field: "GF(2)", record_claim: false,
      product_recipe: product_path.delete_prefix(base + "/"), product_sha256: Digest::SHA256.file(product_path).hexdigest,
      slots: slots, axis: axis, bound: row[:bound], compression: row[:compression],
      native_fused: b.save_snapshot(base, "native", row[:native]), result: b.save_snapshot(base, "results", row[:result]),
      exact_rank: row[:result].rank, density: row[:result].audit[:density] }
    File.write(path, JSON.pretty_generate(data) + "\n")
    row[:result]
  end

  def replay(path)
    data = JSON.parse(File.read(path))
    raise "unsupported merge recipe" unless data.values_at("schema", "kind", "field", "record_claim") ==
      [1, "outer-cofactor-merge", "GF(2)", false]
    base = File.dirname(File.realpath(path))
    product = File.realpath(File.join(base, data.fetch("product_recipe")))
    raise "product escapes artifact" unless product.start_with?(base + "/")
    raise "product hash mismatch" unless Digest::SHA256.file(product).hexdigest == data.fetch("product_sha256")
    row = from_product(product, data.fetch("slots"), data.fetch("axis"))
    raise "merge score mismatch" unless row[:bound] == data.fetch("bound") && row[:result].rank == data.fetch("exact_rank") &&
      row[:result].audit[:density] == data.fetch("density") && JSON.parse(JSON.generate(row[:compression])) == data.fetch("compression")
    { native_fused: row[:native], result: row[:result] }.each do |key, scheme|
      entry = data.fetch(key.to_s)
      saved = File.realpath(File.join(base, entry.fetch("path")))
      raise "result escapes artifact" unless saved.start_with?(base + "/")
      raise "result mismatch" unless scheme.shape == entry.fetch("shape") &&
        Digest::SHA256.file(saved).hexdigest == entry.fetch("sha256") && File.binread(saved) == scheme.source_text
    end
    row[:result].audit
  end
end
