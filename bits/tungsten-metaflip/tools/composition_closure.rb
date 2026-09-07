#!/usr/bin/env ruby
# Compare exact candidates with a finite recursive block/Kronecker closure.
# This is a constructive upper-bound family, never a world-record oracle.
require_relative "cofactor_mergers"

module MetaflipCompositionClosure
  B = MetaflipBudProducts
  module_function

  def candidate_scheme(path)
    data = JSON.parse(File.read(path))
    if data["kind"] == "outer-cofactor-merge"
      MetaflipCofactorMergers.replay(path)
    elsif data["kind"] == "outer-basis-block"
      MetaflipOuterBasisProducts.replay(path)
    else
      B.replay(path)
    end
    entry = data.fetch("result")
    B.load_scheme(File.join(File.dirname(path),entry.fetch("path")),entry.fetch("shape"))
  end

  # Exhausts this finite DP family, not all tensor constructions. Materialize
  # selected rows separately before reporting them as admitted witnesses.
  def grid(known, augmented, minimum: 2, maximum: 32)
    raise "invalid grid limits" unless minimum.is_a?(Integer) && maximum.is_a?(Integer) &&
      minimum.between?(1,32) && maximum.between?(minimum,32)
    (minimum..maximum).to_a.repeated_combination(3).map do |shape|
      before,after = known.rank(shape),augmented.rank(shape)
      raise "augmented library lost a construction" unless after <= before
      {shape:shape,known_rank:before,augmented_rank:after,gain:before-after,
       known_kind:known.plan(shape)[:kind],augmented_kind:augmented.plan(shape)[:kind]}
    end
  end

  def trace(library, shape)
    plan = library.plan(shape)
    result = { shape: shape, canonical_shape: shape.sort, kind: plan[:kind], rank: plan[:rank] }
    case plan[:kind]
    when :seed
      result[:source_shape] = plan[:scheme].shape
      result[:source_sha256] = plan[:scheme].audit[:sha256]
      result[:source_id] = plan[:scheme].canonical_id
    when :split, :product
      result[:axis] = plan[:axis] if plan[:kind] == :split
      result[:left] = trace(library, plan[:left])
      result[:right] = trace(library, plan[:right])
    end
    result
  end

  # A reusable, self-contained propagation study. Older reports may label
  # some snapshots "new"; all of them belong to this run's baseline. The
  # explicit candidate recipes are the only additions credited by this run.
  def propagate(root, basis_report, paths, reference_index: nil, minimum: 2, maximum: 32, additional_basis_reports: [])
    raise "provide candidates and a new output directory" if paths.empty? || File.exist?(root)
    raise "invalid grid limits" unless minimum.is_a?(Integer) && maximum.is_a?(Integer) &&
      minimum.between?(1, 32) && maximum.between?(minimum, 32)
    root = File.expand_path(root)
    pins = {}
    best = {}
    # Reconcile older verified comparators before crediting candidate gains.
    # These minima serve leaf pricing only; parent term variants remain distinct.
    ([basis_report] + additional_basis_reports).map { |p| File.realpath(p) }.uniq.each do |report_path|
      base = File.dirname(report_path)
      raw = File.binread(report_path)
      previous = JSON.parse(raw)
      raise "invalid baseline report" unless previous["complete"] && previous["field"] == "GF(2)" &&
        previous["record_claim"] == false && previous["basis"].is_a?(Array) && !previous["basis"].empty?
      pins[report_path] = Digest::SHA256.hexdigest(raw)
      previous.fetch("basis").each do |row|
        e = row.fetch("snapshot")
        path = File.realpath(File.join(base, e.fetch("path")))
        raise "basis snapshot escapes report" unless path.start_with?(base + "/")
        pins[path] = Digest::SHA256.file(path).hexdigest
        raise "basis snapshot hash mismatch" unless pins[path] == e.fetch("sha256")
        s = B.load_scheme(path, e.fetch("shape"))
        raise "basis snapshot changed while reading" unless s.audit[:sha256] == pins[path]
        raise "basis rank mismatch" unless s.rank == row.fetch("rank")
        raise "bounded closure requires dimensions <= 32" if s.shape.max > 32
        key = s.shape.sort
        score = [s.rank, s.audit[:density], s.canonical_id]
        old = best[key] && best[key][0]
        best[key] = [s, path] if !old || (score <=> [old.rank, old.audit[:density], old.canonical_id]) < 0
      end
    end
    candidates = paths.map do |path|
      path = File.realpath(path)
      pins[path] = Digest::SHA256.file(path).hexdigest
      s = candidate_scheme(path)
      raise "bounded closure requires dimensions <= 32" if s.shape.max > 32
      [s, path]
    end
    FileUtils.mkdir_p(File.join(root, "tools"))
    %w[composition_closure cofactor_mergers leaf_delta_collisions cancellation_patterns outer_leaf_portfolio outer_basis_products bud_products verify_tensor].each do |name|
      path = File.join(__dir__, "#{name}.rb")
      pins[path] = Digest::SHA256.file(path).hexdigest
      FileUtils.cp(path, File.join(root, "tools", File.basename(path)))
    end
    inputs = best.sort.map do |_, (s, path)|
      [s, { kind: "base", source: path, rank: s.rank, snapshot: B.save_snapshot(root, "basis/base", s) }]
    end
    extras = candidates.map do |s, path|
      [s, { kind: "new", source: path, recipe_sha256: pins.fetch(path), rank: s.rank,
        snapshot: B.save_snapshot(root, "basis/new", s) }]
    end
    catalog = {}
    if reference_index
      reference_index = File.realpath(reference_index)
      pins[reference_index] = Digest::SHA256.file(reference_index).hexdigest
      FileUtils.cp(reference_index, File.join(root, "catalog-index.json"))
      JSON.parse(File.read(reference_index)).fetch("schemes").each do |e|
        next unless e["verified"] == true && e.fetch("fields", []).include?("F2") &&
          !e.fetch("fields_not", []).include?("F2") && !e["commutative"] && e["scheme_type"] != "non_bilinear"
        key = e.fetch("format").sort
        catalog[key] = [catalog.fetch(key, e.fetch("rank")), e.fetch("rank")].min
      end
    else
      File.write(File.join(root, "catalog-index.json"), JSON.generate(schemes: []) + "\n")
    end
    known = B::Library.new(inputs.map(&:first), products: true)
    augmented = B::Library.new((inputs + extras).map(&:first), products: true)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rows = grid(known, augmented, minimum: minimum, maximum: maximum).map do |r|
      ref = catalog[r[:shape]]
      r.merge(catalog_minimum: ref, below_catalog: ref && r[:augmented_rank] < ref)
    end
    improved = rows.select { |r| r[:gain].positive? }
    summary = { targets: rows.length, improved_prices: improved.length,
      improved_with_catalog: improved.count { |r| r[:catalog_minimum] },
      improved_below_catalog: improved.count { |r| r[:below_catalog] },
      materialization_targets: improved.length, materialized: 0,
      planning_seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started }
    finished = false
    save = lambda do
      report = { schema: 1, complete: finished, field: "GF(2)",
        record_claim: false, redistribution_cleared: false, minimum: minimum, maximum: maximum,
        family: "recursive axis block sums and Kronecker products; all previous basis snapshots are baseline",
        summary: summary, basis: (inputs + extras).map(&:last), source_sha256: pins, rows: rows }
      File.write(File.join(root, "report.json"), JSON.pretty_generate(report) + "\n")
    end
    save.call
    puts JSON.generate(summary); $stdout.flush
    singleton = B.naive([1, 1, 1]); group = [{ axis: nil, indices: [0] }]
    admitted = []
    FileUtils.mkdir_p(File.join(root, "admitted"))
    improved.each do |r|
      s, path = B.export(File.join(root, "admitted"), singleton, r[:shape], group, augmented)
      raise "rank mismatch" unless s.rank == r[:augmented_rank]
      B.replay(path)
      r[:recipe] = path.delete_prefix(root + "/")
      r[:known_plan] = trace(known, r[:shape]); r[:augmented_plan] = trace(augmented, r[:shape])
      r[:result_sha256] = s.audit[:sha256]
      admitted << { shape: r[:shape], rank: s.rank, gain: r[:gain], recipe: File.basename(path) }
      summary[:materialized] += 1
      save.call
      puts JSON.generate(r.slice(:shape, :known_rank, :augmented_rank, :gain, :catalog_minimum)); $stdout.flush
    end
    raise "source changed during propagation" unless pins.all? { |p, h| Digest::SHA256.file(p).hexdigest == h }
    finished = true
    save.call
    File.write(File.join(root, "admitted/report.json"), JSON.pretty_generate(schema: 1, complete: true,
      field: "GF(2)", record_claim: false, source_report_sha256: Digest::SHA256.file(File.join(root, "report.json")).hexdigest,
      rows: admitted) + "\n")
    { summary: summary, rows: rows }
  end

  def main(argv)
    options = { library: File.expand_path("../lib/metaflip/seeds/gf2", __dir__), extra_libraries: [], additional_basis_reports: [], minimum: 2, maximum: 32 }
    OptionParser.new do |p|
      p.banner = "Usage: composition_closure.rb --output DIR [--library DIR] [--extra-library DIR] RECIPE..."
      p.on("--library DIR") { |v| options[:library] = v }
      p.on("--extra-library DIR") { |v| options[:extra_libraries] << v }
      p.on("--output DIR") { |v| options[:output] = v }
      p.on("--basis-report PATH", "Propagate from every verified snapshot in a completed grid report") { |v| options[:basis_report] = v }
      p.on("--extra-basis-report PATH", "Reconcile another verified baseline without crediting its witnesses as new") { |v| options[:additional_basis_reports] << v }
      p.on("--reference-index PATH") { |v| options[:reference_index] = v }
      p.on("--grid MIN:MAX", /\A\d+:\d+\z/) do |v|
        options[:grid_requested] = true
        options[:minimum], options[:maximum] = v.split(":").map(&:to_i)
      end
    end.parse!(argv)
    raise "provide candidate recipes and --output" if argv.empty? || !options[:output]
    if options[:basis_report]
      return propagate(options[:output], options[:basis_report], argv,
        reference_index: options[:reference_index], minimum: options[:minimum], maximum: options[:maximum],
        additional_basis_reports: options[:additional_basis_reports])
    end
    raise "--extra-basis-report requires --basis-report" unless options[:additional_basis_reports].empty?
    raise "--reference-index requires --basis-report" if options[:reference_index]
    raise "--grid requires --basis-report" if options[:grid_requested]
    root = File.expand_path(options[:output])
    raise "output must be new or empty" if File.exist?(root) && (!File.directory?(root) || !Dir.empty?(root))
    files = ([options[:library]] + options[:extra_libraries]).flat_map do |dir|
      paths = Dir[File.join(dir, "matmul_*_gf2.txt")].sort
      raise "empty witness library: #{dir}" if paths.empty?
      paths
    end.uniq
    seeds = files.map { |p| B.load_scheme(p) }
    candidates = argv.sort.map do |path|
      scheme = candidate_scheme(path)
      raise "bounded closure requires dimensions <= 32" if scheme.shape.max > 32
      { path: File.expand_path(path), sha256: Digest::SHA256.file(path).hexdigest, scheme: scheme }
    end
    blocks = B::Library.new(seeds)
    known = B::Library.new(seeds, products: true)
    augmented = B::Library.new(seeds + candidates.map { |c| c[:scheme] }, products: true)
    singleton = B.naive([1, 1, 1])
    group = [{ axis: nil, indices: [0] }]
    FileUtils.mkdir_p(root)
    inputs = files.zip(seeds).map do |path, scheme|
      { source: File.expand_path(path), audit: scheme.audit, snapshot: B.save_snapshot(root, "basis", scheme) }
    end
    rows = candidates.each_with_index.map do |candidate, index|
      scheme = candidate[:scheme]
      shape = scheme.shape
      before = known.rank(shape)
      after = augmented.rank(shape)
      raise "closure lost a feasible construction" unless after <= [before, scheme.rank].min
      known_scheme, known_recipe = B.export(File.join(root, index.to_s, "known"), singleton, shape, group, known)
      new_scheme, new_recipe = B.export(File.join(root, index.to_s, "augmented"), singleton, shape, group, augmented)
      raise "closure cost/materialization mismatch" unless known_scheme.rank == before && new_scheme.rank == after
      { canonical_shape: shape.sort.join("x"), candidate: scheme.audit,
        candidate_recipe: candidate[:path], candidate_recipe_sha256: candidate[:sha256],
        known_block_rank: blocks.rank(shape), known_recursive_rank: before,
        augmented_recursive_rank: after, candidate_beats_known: scheme.rank < before,
        improvement_from_candidates: before - after,
        known_plan: trace(known, shape), augmented_plan: trace(augmented, shape),
        known_recipe: known_recipe, augmented_recipe: new_recipe, record_claim: false }
    end
    report = { schema: 1, field: "GF(2)", record_claim: false,
      family: "finite recursive axis block sums and Kronecker products of verified inputs",
      options: options, tool_sha256: Digest::SHA256.file(__FILE__).hexdigest,
      composer_sha256: Digest::SHA256.file(File.join(__dir__, "bud_products.rb")).hexdigest,
      basis: inputs, rows: rows }
    File.write(File.join(root, "report.json"), JSON.pretty_generate(report) + "\n")
    puts JSON.generate(cases: rows.length, verified_inputs: seeds.length,
      candidates_below_known: rows.count { |r| r[:candidate_beats_known] },
      targets_improved_by_candidates: rows.count { |r| r[:improvement_from_candidates].positive? }, record_claim: false)
    report
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    MetaflipCompositionClosure.main(ARGV)
  rescue StandardError => error
    warn "Composition closure rejected: #{error.message}"
    exit 1
  end
end
