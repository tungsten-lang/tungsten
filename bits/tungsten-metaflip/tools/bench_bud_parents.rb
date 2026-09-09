#!/usr/bin/env ruby
# Matched flip-attempt study, not a throughput benchmark or record oracle.
require "open3"
require_relative "bud_products"
require_relative "bud_packings"
require_relative "bud_fixed_group"

B = MetaflipBudProducts
options = { trials: 16, chunks: 512, steps: 512, seed: 900001, debt: 2, density_slack: 4,
            library: File.expand_path("../lib/metaflip/seeds/gf2", __dir__) }
OptionParser.new do |parser|
  parser.banner = "Usage: bench_bud_parents.rb --binary FILE --parent FILE --scale AxBxC --output DIR"
  %i[binary parent scale output library portfolio].each { |key| parser.on("--#{key} VALUE") { |v| options[key] = v } }
  parser.on('--native-spool DIR', 'Add fully verified immutable native leaf-bank witnesses') { |v| options[:native_spool] = v }
  parser.on('--holdout-shape AxBxC', 'Price the held literal terms as one verified elementary group') { |v| options[:holdout_shape] = v }
  %i[trials chunks steps seed debt].each { |key| parser.on("--#{key} N", Integer) { |v| options[key] = v } }
  parser.on("--density-slack N", Integer) { |v| options[:density_slack] = v }
  parser.on("--observe-every N", Integer) { |v| options[:observe_every] = v }
  parser.on("--holdout-indices LIST", "Comma-separated literal parent terms kept outside the walk") do |v|
    raise OptionParser::InvalidArgument, v unless v.match?(/\A\d+(,\d+)*\z/)
    options[:holdout_indices] = v.split(',').map { |i| Integer(i, 10) }
  end
  parser.on("--grids", "Score at most one elementary grid plus pure-axis buckets") { options[:grids] = true }
  parser.on("--recursive-products", "Allow verified Kronecker products in leaf pricing") { options[:products] = true }
  parser.on("--parents-only", "Verify and retain parents; defer potentially large tensor products") { options[:parents_only] = true }
end.parse!
begin
  %i[binary parent output].each { |key| raise "missing --#{key}" unless options[key] }
  raise "provide exactly one of --scale or --portfolio" unless !!options[:scale] != !!options[:portfolio]
  raise "portfolio scoring requires --parents-only and does not support --grids" if options[:portfolio] && (!options[:parents_only] || options[:grids])
  if options[:holdout_shape]
    raise 'fixed elementary holdout requires indices and one scale, without --grids' unless options[:holdout_indices] && !options[:portfolio] && !options[:grids]
    options[:holdout_shape] = MetaflipTensorVerifier.dimensions(options[:holdout_shape])
    raise 'fixed elementary sides must be at most four' unless options[:holdout_shape].all? { |d| d.between?(1,4) }
  end
  raise "invalid budget" unless options[:trials].between?(1, 4096) && options[:chunks].between?(1, 100000) &&
                                options[:steps].between?(1, 1000000) && options[:debt].between?(0, 8) &&
                                options[:density_slack].between?(0, 1024) &&
                                options[:seed].between?(0, 2**31 - 1)
  raise "invalid observation interval" if options[:observe_every] && !options[:observe_every].between?(1, options[:steps])
  root = File.expand_path(options[:output])
  raise "output must be new or empty" if File.exist?(root) && (!File.directory?(root) || !Dir.empty?(root))
  binary = File.expand_path(options[:binary])
  digest = Digest::SHA256.file(binary).hexdigest
  parent = B.load_scheme(options[:parent])
  if options[:holdout_indices]
    indices = options[:holdout_indices]
    raise "invalid holdout indices" unless indices.uniq == indices && indices.length.between?(1, parent.rank-1) &&
                                          indices.all? { |i| i.between?(0, parent.rank-1) }
    # Use literal masks, not native hash/live-list positions, at this boundary.
    held_terms = indices.map { |i| parent.terms.fetch(i) }
    B.group_factor_maps(parent, {elementary_shape: options[:holdout_shape], indices: indices}) if options[:holdout_shape]
    options[:observe_every] ||= options[:steps]
  end
  if options[:portfolio]
    portfolio_raw = File.binread(options[:portfolio])
    portfolio_hash = Digest::SHA256.hexdigest(portfolio_raw)
    cases = JSON.parse(portfolio_raw)
    raise "invalid portfolio" unless cases.is_a?(Array) && cases.length.between?(1, 32) && cases.all? do |row|
      row.is_a?(Hash) && row.keys.sort == %w[scale weight] && row['scale'].is_a?(Array) &&
        row['scale'].length == 3 && row['scale'].all? { |d| d.is_a?(Integer) && d.between?(1, 16) } &&
        row['weight'].is_a?(Integer) && row['weight'].between?(1, 1024)
    end
    raise "duplicate portfolio scales" unless cases.map { |row| row['scale'] }.uniq.length == cases.length
  else
    scale = MetaflipTensorVerifier.dimensions(options[:scale])
    raise "scale exceeds bounded leaf library" if scale.max > 16
    cases = [{'scale' => scale, 'weight' => 1}]
  end
  scale = cases.first.fetch('scale')
  native_schemes, native_banks = options[:native_spool] ? B.native_bank_schemes(File.expand_path(options[:native_spool])) : [[], []]
  library = B::Library.new(Dir[File.join(options[:library], "matmul_*_gf2.txt")].sort.map { |p| B.load_scheme(p) } + native_schemes, products: !!options[:products])
  FileUtils.mkdir_p(root)
  File.binwrite(File.join(root, 'portfolio.json'), portfolio_raw) if portfolio_raw
  snapshot = B.save_snapshot(root, "input", parent)
  if held_terms
    holdout_path = File.join(root, "holdout.txt")
    File.write(holdout_path, B.text(held_terms))
  end
  if options[:holdout_shape]
    held_leaf_shape = options[:holdout_shape].zip(scale).map { |a,b| a*b }
    raise 'fixed elementary leaf exceeds bounded library' if held_leaf_shape.max > 16
    held_leaf = library.scheme(held_leaf_shape)
    held_snapshot = B.save_snapshot(root, 'held-leaf', held_leaf)
  end
  limit = parent.rank + options[:debt]
  raise "grid objective is bounded to rank plus debt <= 64" if options[:grids] && limit > 64
  leaves = []
  case_prices = cases.each_with_index.map do |entry, case_index|
    3.times.map do |axis|
      chunks = (1..[limit, 16 / entry.fetch('scale')[B::EXPANDED_DIMENSION[axis]]].min).map do |k|
        leaf = library.scheme(B.leaf_shape(entry.fetch('scale'), axis, k))
        leaves << { case: case_index, axis: axis, count: k, rank: leaf.rank, snapshot: B.save_snapshot(root, "price-leaves", leaf) }
        leaf.rank
      end
      dp = [0]
      1.upto(limit) { |k| dp << 1.upto([k, chunks.length].min).map { |j| dp[k - j] + chunks[j - 1] }.min }
      dp
    end
  end
  prices = 3.times.map do |axis|
    (0..limit).map { |k| cases.each_index.sum { |i| cases[i].fetch('weight') * case_prices[i][axis][k] } }
  end
  raise "portfolio price exceeds native bound" if prices.flatten.max > 1_000_000_000
  table_rows = [limit.to_s] + prices.map { |row| row.join(" ") }
  if options[:grids]
    grid_prices = [[2, 1, 2], [1, 2, 2], [2, 2, 1]].map do |shape|
      leaf_shape = shape.zip(scale).map { |x, y| x * y }
      if leaf_shape.max <= 16
        leaf = library.scheme(leaf_shape)
        leaves << { elementary_shape: shape, rank: leaf.rank, snapshot: B.save_snapshot(root, "price-leaves", leaf) }
        leaf.rank
      else
        4 * library.rank(scale) # cannot improve the feasible pure-axis baseline
      end
    end
    table_rows << "grids #{grid_prices.join(' ')}"
  end
  table = table_rows.join("\n") + "\n"
  table_path = File.join(root, "prices.txt")
  File.write(table_path, table)
  File.write(File.join(root, "price-leaves.json"), JSON.pretty_generate(leaves) + "\n")
  grouping = lambda do |candidate|
    if options[:holdout_shape]
      MetaflipFixedGroup.partition(candidate, scale, library, held_terms, options[:holdout_shape])
    else
      options[:grids] ? MetaflipBudPackings.one_grid_partition(candidate, scale, library) :
                       B.partitions(candidate, scale, library, trials: 0)
    end
  end
  evaluate = lambda do |candidate|
    if options[:portfolio]
      3.times.map do |axis|
        candidate.terms.group_by { |term| term[axis] }.values.sum { |bucket| prices[axis].fetch(bucket.length) }
      end.min
    else
      B.score(grouping.call(candidate), scale, library)
    end
  end
  initial = evaluate.call(parent)
  summary = { schema: 1, field: "GF(2)", record_claim: false, options: options,
              binary_sha256: digest, price_sha256: Digest::SHA256.hexdigest(table), parent: snapshot,
              initial_score: initial, arms: [] }
  summary[:native_banks] = native_banks unless native_banks.empty?
  if options[:portfolio]
    summary[:portfolio] = cases
    summary[:portfolio_source_sha256] = portfolio_hash
    summary[:portfolio_source_path] = 'portfolio.json'
    summary[:score_kind] = 'weighted-common-axis-portfolio-cost-not-a-tensor-rank'
  end
  summary[:holdout] = { terms: held_terms, path: "holdout.txt", sha256: Digest::SHA256.file(holdout_path).hexdigest } if held_terms
  if held_leaf
    summary[:holdout].merge!(elementary_shape: options[:holdout_shape], leaf: held_snapshot, cost: held_leaf.rank)
    summary[:score_kind] = 'fixed-elementary-group-or-pure-axis-upper-bound'
  end
  summary[:source_sha256] = %w[bud_parent_walk.w bud_holdout.w bud_parent_score.w bud_mixed_score.w bud_parent_shapes.w bud_products.rb bud_packings.rb bud_fixed_group.rb bench_bud_parents.rb].to_h do |name|
    [name, Digest::SHA256.file(File.join(__dir__, name)).hexdigest]
  end
  summary[:engine_sha256] = %w[rect.w seeds/rect.w scheme.w composition/mixed_pairs.w composition/mixed_groups.w].to_h do |name|
    [name, Digest::SHA256.file(File.join(__dir__, "../lib/metaflip", name)).hexdigest]
  end
  %w[walk greedy anneal].each do |mode|
    directory = File.join(root, mode)
    FileUtils.mkdir_p(directory)
    command = [binary, File.join(root, snapshot[:path]), parent.shape.join("x"), table_path,
               options[:trials].to_s, options[:chunks].to_s, options[:steps].to_s, mode,
               options[:seed].to_s, directory, options[:debt].to_s]
    command << options[:density_slack].to_s if options[:density_slack] != 4 || options[:observe_every]
    command << options[:observe_every].to_s if options[:observe_every]
    command << holdout_path if held_terms
    command << held_leaf.rank.to_s if held_leaf
    output, status = Open3.capture2e(*command)
    File.write(File.join(directory, "native.log"), output)
    raise "#{mode} failed: #{output}" unless status.success?
    fields = lambda { |line| line.split.drop(1).to_h { |word| word.split("=", 2) } }
    results = output.lines.grep(/\ABUD_RESULT /)
    trials = output.lines.grep(/\ABUD_TRIAL /).map { |line| fields.call(line) }
    raise "bad native result count" unless results.length == 1 && trials.length == options[:trials]
    totals = fields.call(results.first)
    expected = options[:trials] * options[:chunks] * options[:steps]
    raise "attempt accounting mismatch" unless totals.fetch("attempted").to_i == expected &&
                                               totals.fetch("initial").to_i == initial
    raise "holdout accounting mismatch" unless totals.fetch("held_terms").to_i == (held_terms || []).length
    raise 'fixed holdout cost mismatch' if held_leaf && totals.fetch('held_cost').to_i != held_leaf.rank
    if options[:observe_every]
      observations = options[:trials] * options[:chunks] * ((options[:steps] + options[:observe_every] - 1) / options[:observe_every])
      raise "observation accounting mismatch" unless totals.fetch("observe_every").to_i == options[:observe_every] &&
                                                    totals.fetch("observations").to_i == observations
    end
    checked = trials.each_with_index.map do |row, index|
      raise "trial order mismatch" unless row.fetch("trial").to_i == index && row.fetch("strategy") == mode
      candidate = B.load_scheme(File.join(directory, "trial-#{index}.txt"), parent.shape)
      score = evaluate.call(candidate)
      raise "native/Ruby score mismatch" unless row.fetch("score").to_i == score
      raise "native/Ruby tensor metrics mismatch" unless row.fetch("rank").to_i == candidate.rank &&
                                                        row.fetch("bits").to_i == candidate.audit[:density]
      result = { trial: index, score: score, parent: candidate.audit,
                 parent_id: candidate.canonical_id, chunks_accepted: row.fetch("chunks_accepted").to_i }
      unless options[:parents_only]
        groups = grouping.call(candidate)
        product_root = File.join(directory, "products", "trial-#{index}")
        product, recipe = B.export(product_root, candidate, scale, groups, library)
        raise "product exceeds constructive score" if product.rank > score
        result.merge!(exact_product_rank: product.rank, recipe: recipe)
      end
      result[:best_at] = row.fetch("best_at").to_i if row.key?("best_at")
      result[:end_parent] = B.load_scheme(File.join(directory, "end-#{index}.txt"), parent.shape).audit if options[:observe_every]
      result
    end
    arm = { mode: mode, command: command, totals: totals, trials: checked,
            best_score: checked.map { |r| r[:score] }.min,
            products_materialized: !options[:parents_only],
            improvements: checked.count { |r| r[:score] < initial },
            distinct_parents: checked.map { |r| r[:parent_id] }.uniq.length }
    arm[:best_exact_product_rank] = checked.map { |r| r.fetch(:exact_product_rank) }.min unless options[:parents_only]
    summary[:arms] << arm
    raise "binary changed during study" unless Digest::SHA256.file(binary).hexdigest == digest
    raise "portfolio changed during study" if portfolio_hash && Digest::SHA256.file(options[:portfolio]).hexdigest != portfolio_hash
    summary[:source_sha256].each do |name, expected_hash|
      raise "source changed during study: #{name}" unless Digest::SHA256.file(File.join(__dir__, name)).hexdigest == expected_hash
    end
    File.write(File.join(root, "report.json"), JSON.pretty_generate(summary) + "\n")
    puts JSON.generate(arm.reject { |k, _| %i[trials command].include?(k) })
  end
rescue StandardError => error
  warn "Bud parent study rejected: #{error.message}"
  exit 1
end
