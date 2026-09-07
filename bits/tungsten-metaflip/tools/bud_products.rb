#!/usr/bin/env ruby
# Offline, exact GF(2) shared-factor (bud) product search. This is not a
# world-record oracle and does not mutate the running fleet's archive.
# Construction: https://arxiv.org/html/2606.02480v1, sections 2.4--2.5.
require "digest"
require "fileutils"
require "json"
require "optparse"
require_relative "verify_tensor"

module MetaflipBudProducts
  module_function

  EDGES = [[0, 1], [1, 2], [0, 2]].freeze # W is output-row-major, not transposed.
  EXPANDED_DIMENSION = [2, 0, 1].freeze  # equal U, V, W respectively

  def text(terms)
    ([terms.length.to_s] + terms.map { |term| term.join(" ") }).join("\n") + "\n"
  end

  def infer_shape(path)
    snapshot = File.basename(path).match(/\A([1-9][0-9]*x[1-9][0-9]*x[1-9][0-9]*)-[0-9a-f]{64}\.txt\z/)
    return MetaflipTensorVerifier.dimensions(snapshot[1]) if snapshot
    name = File.basename(path).match(/matmul_([1-9][0-9]*(?:x[1-9][0-9]*){1,2})_rank/)
    return MetaflipTensorVerifier.dimensions(MetaflipTensorVerifier.infer_shape(path)) unless name
    shape = name[1].split("x").map(&:to_i)
    raise "non-square two-coordinate name" if shape.length == 2 && shape[0] != shape[1]
    shape << shape[0] if shape.length == 2
    shape
  end

  class Scheme
    attr_reader :shape, :terms, :audit, :source_text

    def initialize(shape, source_text)
      @shape = shape.dup.freeze
      @audit = MetaflipTensorVerifier.verify_text(source_text, *shape).freeze
      @source_text = source_text.freeze
      lines = source_text.lines.map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
      lines.shift if lines.first.match?(/\A[0-9]+\z/)
      @terms = lines.map { |line| line.split.reject { |word| word == "R" }.map(&:to_i).freeze }.freeze
      @canonical_id = Digest::SHA256.hexdigest([shape.join("x"), MetaflipBudProducts.text(terms.sort)].join("\n")).freeze
    end

    def rank
      terms.length
    end

    def canonical_id
      @canonical_id
    end
  end

  def load_scheme(path, shape = infer_shape(path))
    # Read once: a live checkpoint may be atomically replaced during this scan.
    Scheme.new(shape, File.binread(path))
  end

  def naive(shape)
    n, m, p = shape
    terms = n.times.flat_map do |i|
      m.times.flat_map do |j|
        p.times.map { |k| [1 << (i * m + j), 1 << (j * p + k), 1 << (i * p + k)] }
      end
    end
    Scheme.new(shape, text(terms))
  end

  def transpose(word, rows, cols)
    MetaflipTensorVerifier.bit_positions(word).reduce(0) do |out, bit|
      out | (1 << ((bit % cols) * rows + bit / cols))
    end
  end

  def orient(scheme, target)
    return scheme if scheme.shape == target
    permutation = [0, 1, 2].permutation.find { |perm| perm.map { |i| scheme.shape[i] } == target }
    raise "not a dimension permutation" unless permutation
    terms = scheme.terms.map do |term|
      EDGES.map do |edge|
        mapped = edge.map { |vertex| permutation[vertex] }
        index = EDGES.index(mapped.sort)
        value = term[index]
        mapped == mapped.sort ? value : transpose(value, *EDGES[index].map { |v| scheme.shape[v] })
      end
    end
    Scheme.new(target, text(terms))
  end

  def embed_block(scheme, target, offsets)
    scheme.terms.map do |term|
      EDGES.each_with_index.map do |(row, col), axis|
        MetaflipTensorVerifier.bit_positions(term[axis]).reduce(0) do |out, bit|
          i, j = bit.divmod(scheme.shape[col])
          out ^ (1 << ((i + offsets[row]) * target[col] + j + offsets[col]))
        end
      end
    end
  end

  def tensor_product(left, right)
    terms = left.terms.each_index.flat_map do |index|
      map_leaf(left, right.shape, { axis: nil, indices: [index] }, right)
    end
    # Keep multiplicities: this is the stated product-rank upper bound, even
    # when an input contains redundant terms. The full tensor is verified.
    Scheme.new(left.shape.zip(right.shape).map { |a, b| a * b }, text(terms))
  end

  # A local, certificate-backed library. Missing leaves use exact block sums,
  # never rank numbers imported without a corresponding GF(2) witness.
  class Library
    def initialize(schemes, products: false)
      @seeds = {}
      schemes.each do |scheme|
        key = scheme.shape.sort.freeze
        old = @seeds[key]
        @seeds[key] = scheme if !old || ([scheme.rank, scheme.audit[:density], scheme.canonical_id] <=>
                                       [old.rank, old.audit[:density], old.canonical_id]) == -1
      end
      @plans = {}
      @materialized = {}
      @products = products
    end

    def plan(shape)
      key = shape.sort.freeze
      return @plans[key] if @plans.key?(key)
      seed = @seeds[key]
      best = { kind: :naive, rank: key.inject(:*) }
      best = { kind: :seed, rank: seed.rank, scheme: seed } if seed && seed.rank <= best[:rank]
      # Dimension-one tensors have exact naive rank, so splitting cannot help.
      unless key.include?(1)
        3.times do |axis|
          1.upto(key[axis] / 2) do |cut|
            left, right = key.dup, key.dup
            left[axis], right[axis] = cut, key[axis] - cut
            rank = plan(left)[:rank] + plan(right)[:rank]
            best = { kind: :split, rank: rank, axis: axis, left: left, right: right } if rank < best[:rank]
          end
        end
        if @products
          divisors = key.map { |d| (1..d).select { |i| (d % i).zero? } }
          divisors[0].product(divisors[1], divisors[2]).each do |left|
            right = key.zip(left).map { |d, i| d / i }
            next if left == [1, 1, 1] || right == [1, 1, 1]
            next if (left <=> right) == 1
            rank = plan(left)[:rank] * plan(right)[:rank]
            best = { kind: :product, rank: rank, left: left, right: right } if rank < best[:rank]
          end
        end
      end
      @plans[key] = best.freeze
    end

    def rank(shape)
      plan(shape)[:rank]
    end

    def scheme(shape)
      return @materialized[shape] if @materialized.key?(shape)
      key = shape.sort
      recipe = plan(key)
      result = case recipe[:kind]
               when :seed then MetaflipBudProducts.orient(recipe[:scheme], key)
               when :naive then MetaflipBudProducts.naive(key)
               when :split
                 offsets = [0, 0, 0]
                 offsets[recipe[:axis]] = recipe[:left][recipe[:axis]]
                 terms = MetaflipBudProducts.embed_block(scheme(recipe[:left]), key, [0, 0, 0]) +
                         MetaflipBudProducts.embed_block(scheme(recipe[:right]), key, offsets)
                 Scheme.new(key, MetaflipBudProducts.text(terms))
               when :product
                 MetaflipBudProducts.tensor_product(scheme(recipe[:left]), scheme(recipe[:right]))
               end
      raise "leaf rank mismatch" unless result.rank == recipe[:rank]
      @materialized[shape.dup.freeze] = MetaflipBudProducts.orient(result, shape)
    end

    def checked_in_rank(shape)
      @seeds[shape.sort]&.rank
    end
  end

  def leaf_shape(scale, axis, count)
    result = scale.dup
    result[EXPANDED_DIMENSION[axis]] *= count unless axis.nil?
    result
  end

  # Generic elementary groups list parent terms in (i,j,k) order. Their
  # factors must be images of the U_ij, V_jk and W_ik coordinate bases.
  # Images need not be independent: these are arbitrary linear maps.
  def group_shape(group)
    count = group.fetch(:indices).length
    if group.key?(:elementary_shape)
      raise "elementary group cannot also specify an axis" if group.key?(:axis)
      shape = group.fetch(:elementary_shape)
      raise "invalid elementary shape" unless shape.is_a?(Array) && shape.length == 3 &&
                                               shape.all? { |d| d.is_a?(Integer) && d.positive? }
      raise "elementary term count mismatch" unless shape.inject(:*) == count
      shape
    else
      axis = group[:axis]
      raise "bad bud axis" unless axis.nil? || [0, 1, 2].include?(axis)
      raise "empty bud" unless count.positive?
      raise "only singleton buds can omit axis" if axis.nil? && count != 1
      leaf_shape([1, 1, 1], axis, count)
    end
  end

  def group_leaf_shape(scale, group)
    group_shape(group).zip(scale).map { |a, b| a * b }
  end

  def group_factor_maps(parent, group)
    shape = group_shape(group)
    maps = EDGES.map { |r, c| Array.new(shape[r] * shape[c]) }
    group.fetch(:indices).each_with_index do |index, position|
      raise "invalid parent term index" unless index.is_a?(Integer) && index.between?(0, parent.rank - 1)
      coordinates = [position / (shape[1] * shape[2]), (position / shape[2]) % shape[1], position % shape[2]]
      EDGES.each_with_index do |(r, c), axis|
        slot = coordinates[r] * shape[c] + coordinates[c]
        factor = parent.terms[index][axis]
        old = maps[axis][slot]
        raise "inconsistent elementary factor map" if old && old != factor
        maps[axis][slot] = factor
      end
    end
    maps
  end

  def validate_groups(parent, groups)
    indices = groups.flat_map { |group| group.fetch(:indices) }
    raise "partition must use every parent term exactly once" unless indices.sort == (0...parent.rank).to_a
    groups.each { |group| group_factor_maps(parent, group) }
    true
  end

  def score(groups, scale, library)
    groups.sum { |g| library.rank(group_leaf_shape(scale, g)) }
  end

  def partitions(parent, scale, library, trials: 8, seed: 1, max_leaf: 16)
    raise "invalid search limits" unless trials >= 0 && max_leaf >= scale.max
    single = library.rank(scale)
    buckets = 3.times.map do |axis|
      (0...parent.rank).group_by { |i| parent.terms[i][axis] }.values
    end
    costs = 3.times.map do |axis|
      limit = [buckets[axis].map(&:length).max, max_leaf / scale[EXPANDED_DIMENSION[axis]]].min
      [0] + 1.upto(limit).map { |k| library.rank(leaf_shape(scale, axis, k)) }
    end
    candidates = [parent.rank.times.map { |i| { axis: nil, indices: [i] } }]
    # Three pure-axis partitions use exact small integer DP for each bucket.
    3.times do |axis|
      groups = []
      buckets[axis].each do |bucket|
        dp = [[0, []]]
        1.upto(bucket.length) do |size|
          choices = 1.upto([size, costs[axis].length - 1].min).map do |k|
            [dp[size - k][0] + costs[axis][k], dp[size - k][1] + [k]]
          end
          dp << choices.min
        end
        cursor = 0
        dp.last[1].each do |k|
          groups << { axis: axis, indices: bucket.slice(cursor, k) }
          cursor += k
        end
      end
      candidates << groups
    end
    # Mixed-axis greedy packings: objective is product rank, not bud count.
    trials.times do |trial|
      random = Random.new(seed + trial)
      available = Array.new(parent.rank, true)
      groups = []
      loop do
        best = nil
        3.times do |axis|
          buckets[axis].each do |bucket|
            remaining = bucket.select { |i| available[i] }
            2.upto([remaining.length, costs[axis].length - 1].min) do |k|
              gain = k * single - costs[axis][k]
              next unless gain.positive?
              priority = Rational(gain, k) * (trial.zero? ? 1 : Rational(1 + random.rand(1000), 1000))
              if best.nil? || priority > best[0]
                chosen = trial.zero? ? remaining.first(k) : remaining.sample(k, random: random)
                best = [priority, { axis: axis, indices: chosen.sort }]
              end
            end
          end
        end
        break unless best
        groups << best[1]
        best[1][:indices].each { |i| available[i] = false }
      end
      available.each_index { |i| groups << { axis: nil, indices: [i] } if available[i] }
      candidates << groups
    end
    candidates.each { |groups| validate_groups(parent, groups) }
    candidates.min_by { |groups| [score(groups, scale, library), JSON.generate(groups)] }
  end

  # Map an elementary tensor's scaled leaf into the parent tensor product.
  # The maps may be non-injective; XOR and mapped-zero
  # removal are intentional. Ruby integers preserve factors wider than u64.
  def map_leaf(parent, scale, group, leaf)
    elementary = group_shape(group)
    expected = group_leaf_shape(scale, group)
    raise "wrong bud leaf shape" unless leaf.shape == expected
    factors = group_factor_maps(parent, group)
    maps = EDGES.each_with_index.map do |(row, col), axis|
      Array.new(expected[row] * expected[col]) do |bit|
        i, j = bit.divmod(expected[col])
        index = (i / scale[row]) * elementary[col] + j / scale[col]
        factor = factors[axis][index]
        ri, cj = i % scale[row], j % scale[col]
        MetaflipTensorVerifier.bit_positions(factor).reduce(0) do |word, outer_bit|
          oi, oj = outer_bit.divmod(parent.shape[col])
          word ^ (1 << ((oi * scale[row] + ri) * (parent.shape[col] * scale[col]) + oj * scale[col] + cj))
        end
      end
    end
    leaf.terms.map do |term|
      3.times.map do |axis|
        MetaflipTensorVerifier.bit_positions(term[axis]).reduce(0) { |word, bit| word ^ maps[axis][bit] }
      end
    end
  end

  def compose(parent, scale, groups, leaves)
    validate_groups(parent, groups)
    raise "invalid scale" unless scale.length == 3 && scale.all? { |x| x.is_a?(Integer) && x.positive? }
    raise "missing leaf" unless groups.length == leaves.length
    parity = {}
    groups.zip(leaves).each do |group, leaf|
      map_leaf(parent, scale, group, leaf).each do |term|
        next if term.include?(0)
        parity[term] ? parity.delete(term) : parity[term] = true
      end
    end
    target = parent.shape.zip(scale).map { |x, y| x * y }
    Scheme.new(target, text(parity.keys.sort))
  end

  def save_snapshot(root, subdir, scheme)
    bytes = text(scheme.terms)
    sha = Digest::SHA256.hexdigest(bytes)
    relative = "#{subdir}/#{scheme.shape.join('x')}-#{sha}.txt"
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, bytes) unless File.exist?(path)
    { path: relative, shape: scheme.shape, sha256: sha }
  end

  def export(root, parent, scale, groups, library)
    leaves = groups.map { |g| library.scheme(group_leaf_shape(scale, g)) }
    result = compose(parent, scale, groups, leaves)
    schema = groups.any? { |g| g.key?(:elementary_shape) } ? 2 : 1
    recipe = { schema: schema, field: "GF(2)", record_claim: false,
               parent: save_snapshot(root, "inputs", parent), scale: scale,
               groups: groups.zip(leaves).map { |g, leaf| g.merge(leaf: save_snapshot(root, "leaves", leaf)) },
               result: save_snapshot(root, "candidates", result),
               formula_rank: leaves.sum(&:rank), exact_rank: result.rank }
    path = File.join(root, "#{result.shape.join('x')}.recipe.json")
    File.write(path, JSON.pretty_generate(recipe) + "\n")
    [result, path]
  end

  def replay(path)
    recipe = JSON.parse(File.read(path), symbolize_names: true)
    raise "unsupported recipe" unless [1, 2].include?(recipe[:schema]) && recipe[:field] == "GF(2)"
    root = File.dirname(File.expand_path(path))
    read = lambda do |entry|
      full = File.expand_path(entry.fetch(:path), root)
      raise "snapshot outside recipe directory" unless full.start_with?(root + File::SEPARATOR)
      scheme = load_scheme(full, entry.fetch(:shape))
      raise "snapshot hash mismatch" unless scheme.audit[:sha256] == entry[:sha256]
      scheme
    end
    parent = read.call(recipe.fetch(:parent))
    groups = recipe.fetch(:groups)
    raise "elementary groups require schema 2" if recipe[:schema] == 1 && groups.any? { |g| g.key?(:elementary_shape) }
    leaves = groups.map { |g| read.call(g.fetch(:leaf)) }
    result = compose(parent, recipe.fetch(:scale), groups, leaves)
    saved = read.call(recipe.fetch(:result))
    raise "replay mismatch" unless result.shape == saved.shape && result.terms == saved.terms &&
                                  result.rank == recipe[:exact_rank] && leaves.sum(&:rank) == recipe[:formula_rank]
    result.audit
  end

  def main(argv)
    options = { library: File.expand_path("../lib/metaflip/seeds/gf2", __dir__),
                max_dimension: 16, max_scale: 4, trials: 8, seed: 12345 }
    OptionParser.new do |parser|
      parser.banner = "Usage: bud_products.rb --output DIR [options] PARENT..."
      parser.on("--library DIR") { |v| options[:library] = v }
      parser.on("--output DIR") { |v| options[:output] = v }
      parser.on("--max-dimension N", Integer) { |v| options[:max_dimension] = v }
      parser.on("--max-scale N", Integer) { |v| options[:max_scale] = v }
      parser.on("--trials N", Integer) { |v| options[:trials] = v }
      parser.on("--seed N", Integer) { |v| options[:seed] = v }
      parser.on("--leaders-only", "One minimum-rank/density parent per shape (control)") { options[:leaders_only] = true }
      parser.on("--recursive-products", "Allow verified Kronecker products in the leaf library") { options[:products] = true }
      parser.on("--grids", "Also run bounded exact packing of elementary grids") { options[:grids] = true }
      parser.on("--grid-side N", Integer, "Largest grid side, 2..4 (default 2; requires --grids)") { |v| options[:grid_side] = v }
      parser.on("--replay FILE") { |v| options[:replay] = v }
    end.parse!(argv)
    return puts(JSON.pretty_generate(replay(options[:replay]))) if options[:replay]
    raise "--grid-side requires --grids" if options[:grid_side] && !options[:grids]
    raise "invalid grid side" if options[:grid_side] && !options[:grid_side].between?(2, 4)
    raise "provide parents and --output" if argv.empty? || !options[:output]
    raise "invalid limits" unless options[:max_dimension].between?(2, 32) &&
                                 options[:max_scale].between?(1, 8) && options[:trials].between?(0, 100)
    root = File.expand_path(options[:output])
    raise "output must be new or empty" if File.exist?(root) && (!File.directory?(root) || !Dir.empty?(root))
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    inputs = argv.sort.map { |path| [File.expand_path(path), load_scheme(path)] }
    parents = inputs.map(&:last).uniq(&:canonical_id)
    if options[:leaders_only]
      parents = parents.group_by(&:shape).values.map do |family|
        family.min_by { |p| [p.rank, p.audit[:density], p.canonical_id] }
      end
    end
    sources = Dir[File.join(options[:library], "matmul_*_gf2.txt")].sort
    raise "empty witness library" if sources.empty?
    library = Library.new(sources.map { |path| load_scheme(path) }, products: !!options[:products])
    require_relative "bud_packings" if options[:grids]
    grid_limits = { max_leaf: 16, max_vertices: 24, max_states: 50_000, max_candidates: 50_000 }
    FileUtils.mkdir_p(root)
    File.write(File.join(root, "inputs.json"), JSON.pretty_generate(inputs.map do |path, scheme|
      { original_path: path, audit: scheme.audit, canonical_id: scheme.canonical_id,
        snapshot: save_snapshot(root, "inputs", scheme) }
    end) + "\n")
    winners = {}
    scans = 0
    grid_jobs = grid_complete = grid_improvements = 0
    parents.each_with_index do |parent, index|
      has_grids = options[:grids] && MetaflipBudPackings.grid_groups(parent).any?
      limits = parent.shape.map { |dim| [options[:max_scale], options[:max_dimension] / dim].min }
      (1..limits[0]).each do |a|
        (1..limits[1]).each do |b|
          (1..limits[2]).each do |c|
            scale = [a, b, c]
            next if scale == [1, 1, 1]
            target = parent.shape.zip(scale).map { |x, y| x * y }
            groups = partitions(parent, scale, library, trials: options[:trials], seed: options[:seed])
            if has_grids
              extended = MetaflipBudPackings.solve(parent, scale, library, **grid_limits, grids: true,
                                                   grid_side: options.fetch(:grid_side, 2))
              grid_jobs += 1
              grid_complete += 1 if extended[:exact_within_model]
              before = score(groups, scale, library)
              raise "complete grid packing lost to baseline" if extended[:exact_within_model] && extended[:formula_rank] > before
              grid_improvements += 1 if extended[:formula_rank] < before
              groups = [groups, extended[:groups]].min_by { |g| [score(g, scale, library), JSON.generate(g)] }
            end
            formula = score(groups, scale, library)
            baseline = parent.rank * library.rank(scale)
            key = target.sort
            candidate = [formula, parent.rank, parent.canonical_id, scale]
            old = winners[key]
            if old.nil? || (candidate <=> old[:sort]) == -1
              winners[key] = { sort: candidate, parent: parent, scale: scale, groups: groups,
                               formula_rank: formula, product_rank: baseline, target: target }
            end
            scans += 1
          end
        end
      end
      warn "bud scan #{index + 1}/#{parents.length}: #{scans} products, #{winners.length} target shapes"
    end
    rows = winners.sort.map do |key, winner|
      exact, recipe = export(root, winner[:parent], winner[:scale], winner[:groups], library)
      { target: exact.shape.join("x"), canonical_target: key.join("x"),
        parent: winner[:parent].audit, parent_id: winner[:parent].canonical_id, scale: winner[:scale],
        plain_product_rank: winner[:product_rank], formula_rank: winner[:formula_rank], exact_rank: exact.rank,
        elementary_groups: winner[:groups].count { |g| g.key?(:elementary_shape) },
        checked_in_rank: library.checked_in_rank(key), record_claim: false, recipe: recipe }
    end
    family = options[:grids] ? "equal-factor buds and checked elementary grids with sides 2..#{options.fetch(:grid_side, 2)} with verified leaves" :
                             "disjoint equal-factor buds plus exact block-sum leaves"
    report = { schema: 1, construction: family,
               field: "GF(2)", record_claim: false, options: options, parents: parents.length,
               input_files: argv.length, library_files: sources.length, products: scans,
               grid_jobs: grid_jobs, grid_complete_jobs: grid_complete, grid_cost_improvements: grid_improvements,
               grid_limits: options[:grids] && grid_limits,
               packer_sha256: options[:grids] && Digest::SHA256.file(File.join(__dir__, "bud_packings.rb")).hexdigest,
               tool_sha256: Digest::SHA256.file(__FILE__).hexdigest,
               verifier_sha256: Digest::SHA256.file(File.join(__dir__, "verify_tensor.rb")).hexdigest,
               elapsed_seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
               rows: rows }
    File.write(File.join(root, "report.json"), JSON.pretty_generate(report) + "\n")
    puts JSON.generate(report.reject { |k, _| k == :rows }.merge(targets: rows.length,
                         below_plain_product: rows.count { |r| r[:exact_rank] < r[:plain_product_rank] },
                         below_checked_in: rows.count { |r| r[:checked_in_rank] && r[:exact_rank] < r[:checked_in_rank] }))
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    MetaflipBudProducts.main(ARGV)
  rescue StandardError => error
    warn "Bud product rejected: #{error.message}"
    exit 1
  end
end
