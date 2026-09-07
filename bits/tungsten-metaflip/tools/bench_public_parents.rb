#!/usr/bin/env ruby
# Compare independently checked public coefficient presentations as composition
# parents. Only certificate-backed prices enter this screen; reference numbers
# are comparison data, never construction leaves. Does not touch fleet state.
require_relative "bud_packings"
require "optparse"

module MetaflipPublicParents
  B = MetaflipBudProducts
  P = MetaflipBudPackings
  module_function

  def main(argv)
    options = { max_scale: 8, max_leaf: 32, trials: 8, seed: 2026090711, candidate_role: 'public' }
    OptionParser.new do |p|
      %i[scout closure output].each { |k| p.on("--#{k} PATH") { |v| options[k] = File.expand_path(v) } }
      %i[max_scale max_leaf trials seed].each { |k| p.on("--#{k.to_s.tr('_', '-')} N", Integer) { |v| options[k] = v } }
      p.on('--candidate-role ROLE', %w[public search], 'Keep search-generated parents distinct from public inputs') { |v| options[:candidate_role] = v }
    end.parse!(argv)
    raise "provide --scout DIR --closure DIR --output DIR" unless argv.empty? && %i[scout closure output].all? { |k| options[k] }
    raise "invalid limits" unless options[:max_scale].positive? && options[:max_leaf] >= options[:max_scale] && options[:trials] >= 0
    root = options.fetch(:output)
    raise "output exists" if File.exist?(root)
    pins = {}
    read = lambda do |path|
      raw = File.binread(path)
      pins[File.realpath(path)] = Digest::SHA256.hexdigest(raw)
      raw
    end
    scout = JSON.parse(read.call(File.join(options[:scout], "report.json")))
    closure = JSON.parse(read.call(File.join(options[:closure], "report.json")))
    [scout, closure].each do |r|
      raise "unverified input report" unless r.fetch("complete") && r.fetch("field") == "GF(2)" && !r.fetch("record_claim")
    end
    maximum = closure.fetch("maximum")
    role = options.fetch(:candidate_role)
    raise "leaf prices exceed closure" if options[:max_leaf] > maximum
    prices = closure.fetch("rows").to_h { |r| [r.fetch("shape"), r.fetch("augmented_rank")] }
    oracle = Object.new
    oracle.define_singleton_method(:rank) do |shape|
      raise "price outside checked grid" unless shape.all? { |v| v.between?(1, maximum) }
      shape.include?(1) ? shape.inject(:*) : prices.fetch(shape.sort)
    end
    public_parents = scout.fetch("schemes").map do |entry|
      raw = read.call(File.join(options[:scout], entry.fetch("gf2")))
      raise "public hash mismatch" unless Digest::SHA256.hexdigest(raw) == entry.fetch("sha256")
      scheme = B::Scheme.new(entry.fetch("shape"), raw)
      raise "public rank mismatch" unless scheme.rank == entry.fetch("rank")
      { scheme: B.orient(scheme, scheme.shape.sort), source: entry.fetch("gf2"), role: role }
    end
    shapes = public_parents.map { |r| r[:scheme].shape.sort }
    controls = closure.fetch("basis").filter_map do |row|
      entry = row.fetch("snapshot")
      next unless shapes.include?(entry.fetch("shape").sort)
      raw = read.call(File.join(options[:closure], entry.fetch("path")))
      raise "control hash mismatch" unless Digest::SHA256.hexdigest(raw) == entry.fetch("sha256")
      scheme = B::Scheme.new(entry.fetch("shape"), raw)
      { scheme: B.orient(scheme, scheme.shape.sort), source: entry.fetch("path"), role: "control" }
    end
    parents = (public_parents + controls).uniq { |r| [r[:role], r[:scheme].canonical_id] }
    FileUtils.mkdir_p(File.join(root, "tools"))
    %w[bench_public_parents.rb bud_packings.rb bud_products.rb verify_tensor.rb].each do |name|
      raw = read.call(File.join(__dir__, name))
      File.binwrite(File.join(root, "tools", name), raw)
    end
    File.write(File.join(root, "prices.json"), JSON.generate(closure.fetch("rows").map { |r| r.slice("shape", "augmented_rank") }) + "\n")
    rows = []
    parent_rows = []
    parents.each_with_index do |input, id|
      parent = input.fetch(:scheme)
      parent_rows << { id: id, role: input[:role], source: input[:source], canonical_id: parent.canonical_id,
        shape: parent.shape, rank: parent.rank, density: parent.audit[:density], snapshot: B.save_snapshot(root, "parents", parent) }
      scales = parent.shape.map { |d| (1..[options[:max_scale], maximum / d].min).to_a }
      scales[0].product(scales[1], scales[2]).each do |scale|
        next if scale == [1, 1, 1]
        target = parent.shape.zip(scale).map { |a, b| a * b }.sort
        heuristic = B.partitions(parent, scale, oracle, trials: options[:trials], seed: options[:seed], max_leaf: options[:max_leaf])
        packing = P.solve(parent, scale, oracle, max_leaf: options[:max_leaf], max_vertices: 32,
          max_states: 100_000, max_candidates: 100_000, grids: true, grid_side: 3)
        groups = [heuristic, packing[:groups]].min_by { |g| [B.score(g, scale, oracle), JSON.generate(g)] }
        formula = B.score(groups, scale, oracle)
        if packing[:exact_within_model] && formula < packing[:formula_rank]
          raise "exhaustive packing lost to legal heuristic"
        end
        rows << { parent: id, scale: scale, target: target, baseline: oracle.rank(target), formula: formula,
          gain: oracle.rank(target) - formula, groups: groups, exact_within_packing_model: packing[:exact_within_model],
          states: packing[:states], generated_candidates: packing[:generated_candidates], cutoffs: packing[:cutoffs] }
      end
      puts JSON.generate(parent: id, role: input[:role], shape: parent.shape, total_scales: rows.length,
        wins_so_far: rows.count { |r| r[:gain].positive? })
      $stdout.flush
    end
    by_id = parent_rows.to_h { |r| [r[:id], r] }
    comparisons = rows.group_by { |r| [by_id.fetch(r[:parent])[:shape].sort, r[:scale]] }.values.filter_map do |group|
      current = group.select { |r| by_id.fetch(r[:parent])[:role] == role }.min_by { |r| r[:formula] }
      control = group.select { |r| by_id.fetch(r[:parent])[:role] == "control" }.min_by { |r| r[:formula] }
      next unless current && control
      { shape: by_id.fetch(current[:parent])[:shape], scale: current[:scale], target: current[:target],
        "#{role}_formula".to_sym => current[:formula], control_formula: control[:formula], gain: control[:formula]-current[:formula] }
    end
    selected = rows.group_by { |r| r[:target] }.values.map { |g| g.min_by { |r| [r[:formula], r[:parent], r[:scale]] } }
    raise "source changed" unless pins.all? { |path, hash| Digest::SHA256.file(path).hexdigest == hash }
    report = { schema: 1, complete: true, field: "GF(2)", record_claim: false, canonical_archive_changed: false,
      redistribution_cleared: false, screen_only: true,
      scope: "Constructive formula prices; tensors must be materialized and independently checked before admission",
      options: options, source_sha256: pins, parents: parent_rows,
      summary: { parents: parents.length, parent_scales: rows.length, targets: selected.length,
        positive_formula_targets: selected.count { |r| r[:gain].positive? },
        "#{role}_better_than_control".to_sym => comparisons.count { |r| r[:gain].positive? },
        "#{role}_worse_than_control".to_sym => comparisons.count { |r| r[:gain].negative? },
        packing_cutoffs: rows.count { |r| !r[:exact_within_packing_model] } },
      comparisons: comparisons, selected: selected, rows: rows }
    File.write(File.join(root, "report.json"), JSON.pretty_generate(report) + "\n")
    puts JSON.generate(report[:summary])
  end
end

MetaflipPublicParents.main(ARGV) if $PROGRAM_NAME == __FILE__
