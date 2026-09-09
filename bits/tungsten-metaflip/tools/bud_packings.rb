#!/usr/bin/env ruby
# Exact bounded set packing of shared-factor buds, not a tensor-rank oracle.
# Every returned partition is constructive even if a search limit is reached.
require_relative "bud_products" unless defined?(MetaflipBudProducts)

module MetaflipBudPackings
  B = MetaflipBudProducts
  class Limit < StandardError; end
  module_function

  def enough_bits?(mask, count)
    count.times do
      return false if mask.zero?
      mask &= mask - 1
    end
    true
  end

  # Match the bounded native parent objective, independently reconstructing
  # its witness: at most one 2x2 grid, then a pure-axis partition of the rest.
  def one_grid_partition(parent, scale, library, max_leaf: 16)
    baseline = B.partitions(parent, scale, library, trials: 0, max_leaf: max_leaf)
    candidates = [baseline]
    costs = 3.times.map do |axis|
      limit = [parent.rank, max_leaf / scale[B::EXPANDED_DIMENSION[axis]]].min
      [0] + (1..limit).map { |size| library.rank(B.leaf_shape(scale, axis, size)) }
    end
    grid_groups(parent).each do |grid|
      next if B.group_leaf_shape(scale, grid).max > max_leaf
      remaining = (0...parent.rank).to_a - grid.fetch(:indices)
      3.times do |axis|
        groups = [grid]
        remaining.group_by { |i| parent.terms[i][axis] }.each_value do |bucket|
          dp = [[0, []]]
          1.upto(bucket.length) do |size|
            dp << 1.upto([size, costs[axis].length - 1].min).map do |k|
              [dp[size - k][0] + costs[axis][k], dp[size - k][1] + [k]]
            end.min
          end
          cursor = 0
          dp.last[1].each do |k|
            groups << { axis: axis, indices: bucket.slice(cursor, k) }
            cursor += k
          end
        end
        candidates << groups
      end
    end
    best = candidates.min_by { |g| [B.score(g, scale, library), JSON.generate(g)] }
    B.validate_groups(parent, best)
    best
  end

  # Complete nondegenerate rectangles in two factor classes. The third
  # factor is a free coordinate image. Duplicate cells enumerate every term
  # choice, rather than silently retaining only one equivalent-looking mask.
  def grid_groups(parent, shapes: nil, max_side: 2, min_free_multiplicity: 1)
    raise "invalid grid side" unless max_side.is_a?(Integer) && max_side.between?(2, 4)
    raise "invalid free multiplicity" unless min_free_multiplicity.is_a?(Integer) && min_free_multiplicity.positive?
    return enum_for(__method__, parent, shapes: shapes, max_side: max_side,
                   min_free_multiplicity: min_free_multiplicity) unless block_given?
    [0, 1, 2].combination(2) do |a, b|
      row_vertex = (B::EDGES[a] - B::EDGES[b]).first
      col_vertex = (B::EDGES[b] - B::EDGES[a]).first
      cells = {}
      # Optional subgraph restriction. Default grid packing is unchanged.
      # Stacking two layers requires each free-factor value at least twice;
      # singleton free images can never participate in such a stack.
      free = ([0, 1, 2] - [a, b]).first
      counts = parent.terms.map { |term| term[free] }.tally if min_free_multiplicity > 1
      parent.terms.each_with_index do |term, index|
        next if counts && counts.fetch(term[free]) < min_free_multiplicity
        ((cells[term[a]] ||= {})[term[b]] ||= []) << index
      end
      cols = cells.values.flat_map(&:keys).uniq.sort
      col_ids = cols.each_with_index.to_h
      row_keys = cells.keys.sort
      row_masks = row_keys.map { |r| cells.fetch(r).keys.reduce(0) { |mask, c| mask | (1 << col_ids.fetch(c)) } }
      2.upto(max_side) do |height|
        2.upto(max_side) do |width|
          shape = [1, 1, 1]
          shape[row_vertex], shape[col_vertex] = height, width
          next if shapes && !shapes.include?(shape)
          eligible = row_keys.each_index.select { |i| enough_bits?(row_masks[i], width) }
          selected_rows = []
          visit = lambda do |start, common|
            remaining = height - selected_rows.size
            if remaining.zero?
              MetaflipTensorVerifier.bit_positions(common).combination(width) do |selected_cols|
                choices = selected_rows.flat_map { |r| selected_cols.map { |c| cells.fetch(row_keys[r]).fetch(cols[c]) } }
                choices[0].product(*choices.drop(1)) do |selected|
                  indices = shape[0].times.flat_map do |i|
                    shape[1].times.flat_map do |j|
                      shape[2].times.map do |k|
                        coordinates = [i, j, k]
                        selected[width * coordinates[row_vertex] + coordinates[col_vertex]]
                      end
                    end
                  end
                  yield({ elementary_shape: shape, indices: indices })
                end
              end
              next
            end
            # Adding rows only removes common columns. Prune a prefix once
            # fewer than width columns remain; no complete grid is lost.
            start.upto(eligible.size - remaining) do |position|
              r = eligible[position]
              intersection = common & row_masks[r]
              next unless enough_bits?(intersection, width)
              selected_rows << r
              visit.call(position + 1, intersection)
              selected_rows.pop
            end
          end
          visit.call(0, (1 << cols.size) - 1)
        end
      end
    end
  end

  def solve(parent, scale, library, max_leaf: 16, max_vertices: 24,
            max_states: 50_000, max_candidates: 50_000, grids: false, grid_side: 2)
    raise "invalid packing limits" unless max_leaf >= scale.max && max_vertices.positive? &&
                                          max_states.positive? && max_candidates.positive?
    raise "invalid grid side" unless grid_side.is_a?(Integer) && grid_side.between?(2, 4)
    baseline = B.partitions(parent, scale, library, trials: 0, max_leaf: max_leaf)
    single = library.rank(scale)
    edges = {}
    generated = 0
    complete = true
    cutoff = []
    # Every positive-gain subset of an equal-factor bucket is considered.
    # Subsets with nonpositive gain can be replaced by singleton groups without
    # increasing the formula cost (not necessarily the post-XOR product rank).
    begin
      3.times do |axis|
        parent.terms.each_index.group_by { |i| parent.terms[i][axis] }.each_value do |bucket|
          limit = [bucket.length, max_leaf / scale[B::EXPANDED_DIMENSION[axis]]].min
          2.upto(limit) do |size|
            gain = size * single - library.rank(B.leaf_shape(scale, axis, size))
            next unless gain.positive?
            bucket.combination(size) do |indices|
              raise Limit if generated >= max_candidates
              generated += 1
              mask = indices.reduce(0) { |m, i| m | (1 << i) }
              old = edges[mask]
              if !old || gain > old[:gain]
                edges[mask] = { mask: mask, gain: gain, group: { axis: axis, indices: indices } }
              end
            end
          end
        end
      end
      if grids
        shapes = (2..grid_side).flat_map { |h| (2..grid_side).flat_map { |w| [1, h, w].permutation.to_a } }.uniq
        gains = shapes.filter_map do |shape|
          leaf = shape.zip(scale).map { |a, b| a * b }
          next if leaf.max > max_leaf
          gain = shape.reduce(:*) * single - library.rank(leaf)
          [shape, gain] if gain.positive?
        end.to_h
        grid_groups(parent, shapes: gains.keys, max_side: grid_side).each do |group|
          raise Limit if generated >= max_candidates
          generated += 1
          mask = group.fetch(:indices).reduce(0) { |m, i| m | (1 << i) }
          gain = gains.fetch(group.fetch(:elementary_shape))
          old = edges[mask]
          if !old || gain > old[:gain]
            edges[mask] = { mask: mask, gain: gain, group: group }
          end
        end
      end
    rescue Limit
      complete = false
      cutoff << "candidates"
    end

    # Disconnected components have disjoint terms, so their formula gains add.
    leaders = Array.new(parent.rank) { |i| i }
    find = lambda do |i|
      while leaders[i] != i
        leaders[i] = leaders[leaders[i]]
        i = leaders[i]
      end
      i
    end
    edges.each_value do |edge|
      first = edge[:group][:indices].first
      edge[:group][:indices].each { |i| leaders[find.call(i)] = find.call(first) }
    end
    components = edges.values.group_by { |edge| find.call(edge[:group][:indices].first) }.values
    selected = []
    states = 0
    sizes = []
    components.each do |component|
      mask = component.reduce(0) { |m, edge| m | edge[:mask] }
      vertices = component.flat_map { |edge| edge[:group][:indices] }.uniq.sort
      sizes << vertices.length
      begin
        if vertices.length > max_vertices
          cutoff << "vertices"
          raise Limit
        end
        containing = vertices.to_h { |v| [v, component.select { |edge| edge[:mask][v] == 1 }] }
        memo = { 0 => [0, nil, 0] }
        visit = lambda do |available|
          return memo.fetch(available)[0] if memo.key?(available)
          if states >= max_states
            cutoff << "states"
            raise Limit
          end
          states += 1
          # Branch on a constrained term; selecting no bud is always legal.
          choices = vertices.filter_map do |v|
            next unless available[v] == 1
            viable = containing.fetch(v).select { |e| (e[:mask] & available) == e[:mask] }
            [v, viable] unless viable.empty?
          end
          if choices.empty?
            memo[available] = [0, nil, 0]
            return 0
          end
          vertex, viable = choices.max_by { |v, candidates| [candidates.length, -v] }
          rest = available ^ (1 << vertex)
          best = [visit.call(rest), nil, rest]
          viable.sort_by { |edge| [-edge[:gain], edge[:mask]] }.each do |edge|
            next_mask = available ^ edge[:mask]
            gain = edge[:gain] + visit.call(next_mask)
            best = [gain, edge, next_mask] if gain > best[0]
          end
          memo[available] = best
          best[0]
        end
        visit.call(mask)
        remaining = mask
        until remaining.zero?
          _gain, edge, remaining = memo.fetch(remaining)
          selected << edge[:group] if edge
        end
      rescue Limit
        complete = false
        # A deterministic legal packing of this component is a safe fallback.
        occupied = 0
        component.sort_by { |edge| [-Rational(edge[:gain], edge[:group][:indices].length),
                                    -edge[:gain], edge[:mask]] }.each do |edge|
          next unless (occupied & edge[:mask]).zero?
          selected << edge[:group]
          occupied |= edge[:mask]
        end
      end
    end
    used = selected.flat_map { |g| g[:indices] }.to_h { |i| [i, true] }
    parent.rank.times { |i| selected << { axis: nil, indices: [i] } unless used[i] }
    B.validate_groups(parent, selected)
    if complete && B.score(baseline, scale, library) < B.score(selected, scale, library)
      raise "complete packing lost to a feasible baseline"
    end
    groups = [baseline, selected].min_by { |g| [B.score(g, scale, library), JSON.generate(g)] }
    model = grids ? "disjoint equal-factor buds and nondegenerate elementary grids with sides 2..#{grid_side} within max_leaf" :
                    "minimum formula cost of disjoint equal-factor buds within max_leaf"
    { groups: groups, formula_rank: B.score(groups, scale, library), exact_within_model: complete, grids: grids, grid_side: grid_side,
      model: model,
      max_leaf: max_leaf, components: components.length, max_component_vertices: sizes.max || 0,
      states: states, generated_candidates: generated, candidates: edges.length,
      cutoffs: cutoff.uniq, record_claim: false }
  end

  def main(argv)
    options = { max_leaf: 16, max_vertices: 24, max_states: 50_000, max_candidates: 50_000,
                library: File.expand_path("../lib/metaflip/seeds/gf2", __dir__) }
    OptionParser.new do |p|
      p.banner = "Usage: bud_packings.rb --output DIR [--scale AxBxC PARENT... | --from-report FILE]"
      %i[scale output library].each { |key| p.on("--#{key} VALUE") { |v| options[key] = v } }
      p.on('--native-spool DIR', 'Add fully verified immutable native leaf-bank witnesses') { |v| options[:native_spool] = v }
      p.on("--from-report FILE") { |v| options[:from_report] = v }
      p.on("--recursive-products", "Match verified Kronecker leaf pricing from bud_products") { options[:products] = true }
      p.on("--grids", "Also pack checked two-axis elementary groups") { options[:grids] = true }
      p.on("--grid-side N", Integer, "Largest grid side, 2..4 (default 2; requires --grids)") { |v| options[:grid_side] = v }
      %i[max_leaf max_vertices max_states max_candidates].each do |key|
        p.on("--#{key.to_s.tr('_', '-')} N", Integer) { |v| options[key] = v }
      end
    end.parse!(argv)
    raise "--grid-side requires --grids" if options[:grid_side] && !options[:grids]
    raise "provide --output" unless options[:output]
    if options[:from_report]
      raise "do not mix report and parent modes" unless argv.empty? && !options[:scale]
    elsif argv.empty? || !options[:scale]
      raise "provide parents and --scale"
    end
    root = File.expand_path(options[:output])
    raise "output must be new or empty" if File.exist?(root) && (!File.directory?(root) || !Dir.empty?(root))
    sources = Dir[File.join(options[:library], "matmul_*_gf2.txt")].sort
    raise "empty witness library" if sources.empty?
    native_schemes, native_banks = options[:native_spool] ? B.native_bank_schemes(File.expand_path(options[:native_spool])) : [[], []]
    library = B::Library.new(sources.map { |p| B.load_scheme(p) } + native_schemes, products: !!options[:products])
    jobs = if options[:from_report]
      prior = JSON.parse(File.read(options[:from_report]))
      raise "unsupported baseline" unless prior["schema"] == 1 && prior["field"] == "GF(2)"
      prior.fetch("rows").map do |row|
        path = row.fetch("recipe")
        audit = B.replay(path)
        data = JSON.parse(File.read(path), symbolize_names: true)
        parent_path = File.join(File.dirname(File.expand_path(path)), data[:parent][:path])
        parent = B.load_scheme(parent_path, data[:parent][:shape])
        raise "baseline leaf pricing changed" unless B.score(data[:groups], data[:scale], library) == data[:formula_rank]
        { path: parent_path, parent: parent, scale: data[:scale],
          baseline: { formula_rank: data[:formula_rank], exact_rank: audit[:rank], recipe: File.expand_path(path) },
          baseline_groups: data[:groups] }
      end
    else
      scale = MetaflipTensorVerifier.dimensions(options[:scale])
      argv.sort.map { |path| { path: path, parent: B.load_scheme(path), scale: scale } }
    end
    FileUtils.mkdir_p(root)
    rows = jobs.each_with_index.map do |job, index|
      path, parent, scale = job.values_at(:path, :parent, :scale)
      result = solve(parent, scale, library, **options.select do |key, _|
        %i[max_leaf max_vertices max_states max_candidates grids grid_side].include?(key)
      end)
      if job[:baseline] && job[:baseline][:formula_rank] <= result[:formula_rank]
        if result[:exact_within_model] && job[:baseline][:formula_rank] < result[:formula_rank]
          raise "complete packing lost to the baseline recipe"
        end
        result[:groups] = job[:baseline_groups]
        result[:formula_rank] = job[:baseline][:formula_rank]
      end
      product, recipe = B.export(File.join(root, index.to_s), parent, scale, result.fetch(:groups), library)
      row = result.reject { |k, _| k == :groups }.merge(parent: parent.audit, source: File.expand_path(path),
                                                       scale: scale, product: product.audit, recipe: recipe,
                                                       baseline: job[:baseline])
      puts JSON.generate(row)
      row
    end
    report = {schema: 1, field: "GF(2)",
      record_claim: false, options: options, source_sha256: Digest::SHA256.file(__FILE__).hexdigest,
      composer_sha256: Digest::SHA256.file(File.join(__dir__, "bud_products.rb")).hexdigest,
      baseline_sha256: options[:from_report] && Digest::SHA256.file(options[:from_report]).hexdigest,
      library_sha256: sources.to_h { |p| [File.expand_path(p), Digest::SHA256.file(p).hexdigest] },
      rows: rows}
    report[:native_banks] = native_banks unless native_banks.empty?
    File.write(File.join(root, "report.json"), JSON.pretty_generate(report) + "\n")
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    MetaflipBudPackings.main(ARGV)
  rescue StandardError => error
    warn "Bud packing rejected: #{error.message}"
    exit 1
  end
end
