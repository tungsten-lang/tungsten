#!/usr/bin/env ruby
# Offline, bounded cofactor-aware leaf search. The production fleet and its
# archives are untouched. Every retained endpoint has a replayable recipe.
require "optparse"
require_relative "cofactor_mergers"

module MetaflipOuterCofactorJoin
  B = MetaflipBudProducts
  M = MetaflipOuterBasisProducts
  P = MetaflipOuterLeafPortfolio
  D = MetaflipLeafDeltaCollisions
  C = MetaflipCofactorMergers
  S = MetaflipSharedFactorCompression
  module_function

  def run(root, paths, maximum: 8, pair_width: 0, triple_width: 0, compression_width: 1, compression_slack: 0)
    raise "need recipes and a new output directory" if paths.empty? || File.exist?(root)
    raise "invalid kernel bound" unless maximum.is_a?(Integer) && maximum.between?(1, 10)
    raise "invalid pair width" unless pair_width.is_a?(Integer) && pair_width.between?(0, 32)
    raise "invalid triple width" unless triple_width.is_a?(Integer) && triple_width.between?(0, 16)
    raise "invalid compression width" unless compression_width.is_a?(Integer) && compression_width.between?(1, 128)
    raise "invalid compression slack" unless compression_slack.is_a?(Integer) && compression_slack.between?(0, 16)
    targets = paths.map { |p| JSON.parse(File.read(p)).fetch("result").fetch("shape") }
    raise "duplicate output targets" unless targets.uniq == targets
    root = File.expand_path(root)
    FileUtils.mkdir_p(File.join(root, "tools"))
    names = %w[outer_cofactor_join cofactor_mergers leaf_delta_collisions cancellation_patterns outer_leaf_portfolio outer_basis_products bud_products verify_tensor]
    pins = names.to_h do |name|
      path = File.join(__dir__, "#{name}.rb")
      FileUtils.cp(path, File.join(root, "tools", File.basename(path)))
      [path, Digest::SHA256.file(path).hexdigest]
    end
    rows = []
    paths.each do |path|
      M.replay(path)
      pins[File.expand_path(path)] = Digest::SHA256.file(path).hexdigest
      recipe = JSON.parse(File.read(path))
      base = File.dirname(File.expand_path(path))
      load_entry = ->(e) { B.load_scheme(File.join(base, e.fetch("path")), e.fetch("shape")) }
      parent = load_entry.call(recipe.fetch("parent"))
      leaves = recipe.fetch("leaves").map { |e| e && load_entry.call(e) }
      allocation = recipe.fetch("allocation")
      target = recipe.fetch("result").fetch("shape")
      initial, initial_path = M.export(File.join(root, "initial"), parent, allocation, leaves, target)
      images = D.image_disjointness(parent, allocation, leaves)
      raise "cross-slot parity premise failed" unless images[:all_disjoint]
      mapped = leaves.each_with_index.map { |leaf, i| leaf ? P.mapped_terms(parent, i, allocation, leaf) : Set.new }
      raise "nonadditive initial rank" unless mapped.sum(&:length) == initial.rank
      eligible = images[:pairs].select { |p| p[:intersection_dimensions].count(0) == 1 }
      pools = {}
      generated = pair_generated = triple_generated = 0
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      eligible.flat_map { |p| p[:slots] }.uniq.each do |slot|
        leaf = leaves[slot]
        pool = [{ action: { kind: "identity", word: [] }, terms: mapped[slot], raw_id: leaf.canonical_id }]
        seen = Set.new([mapped[slot]])
        consider = lambda do |raw, action|
          generated += 1
          pair_generated += 1 if action[:kind] == "kernel_pair"
          triple_generated += 1 if action[:kind] == "kernel_triple"
          terms = P.mapped_terms_from(parent, slot, allocation, leaf.shape, raw)
          next unless seen.add?(terms)
          pool << { action: action, terms: terms,
            raw_id: Digest::SHA256.hexdigest([leaf.shape.join("x"), B.text(raw.sort)].join("\n")) }
        end
        P.truncation_proposals(parent, slot, allocation, leaf, maximum: maximum, &consider)
        if pair_width.positive? || triple_width.positive?
          # A bounded heuristic shortlist only; it is not dominance. Score
          # against each unchanged eligible partner before composing words.
          partners = eligible.select { |p| p[:slots].include?(slot) }.map do |pair|
            axis = pair[:intersection_dimensions].index(0)
            other = (pair[:slots] - [slot]).first
            [axis, C.normalize(mapped[other], axis)]
          end
          shortlist = Array.new(3) { [] }
          pool.each_with_index do |proposal, index|
            action = proposal[:action]
            next unless action[:kind] == "kernel"
            score = partners.map { |axis, partner| C.merge(C.normalize(proposal[:terms], axis), partner).length }.min
            density = proposal[:terms].sum { |t| t.sum { |v| v.to_s(2).count("1") } }
            shortlist[action[:axis]] << { key: [score, density, index], action: action }
          end
          shortlist.map! { |s| s.sort_by { |e| e[:key] }.map { |e| e[:action] } }
          if pair_width.positive?
            P.kernel_pair_proposals(leaf, shortlist.map { |s| s.first(pair_width) }, seen: Set.new(pool.map { |p| p[:raw_id] }), &consider)
          end
          if triple_width.positive?
            C.triple_proposals(leaf, shortlist.map { |s| s.first(triple_width) }, seen: Set.new(pool.map { |p| p[:raw_id] }), &consider)
          end
        end
        pools[slot] = pool
        puts JSON.generate(target: target, slot: slot, proposals: pool.length)
        $stdout.flush
      end
      cases = []
      eligible.each do |pair|
        a, b = pair[:slots]
        axis = pair[:intersection_dimensions].index(0)
        normalized = [a, b].map { |slot| pools[slot].map { |p| C.normalize(p[:terms], axis) } }
        answer = C.best_pair(*normalized)
        assessment = nil
        if compression_width > 1 || compression_slack.positive?
          shortlist = C.candidate_pairs(*normalized, width: compression_width, slack: compression_slack)
          others = mapped.each_with_index.flat_map { |part, slot| [a, b].include?(slot) ? [] : part.to_a }
          assessments = shortlist[:candidates].map do |candidate|
            ci, cj = candidate[:indices]
            fused = C.materialize(C.merge(normalized[0][ci], normalized[1][cj]), axis)
            raise "candidate score mismatch" unless fused.length == candidate[:rank]
            native = (others + fused).tally.filter_map { |term, n| term if n.odd? }
            compressed, history = S.compress_terms(native)
            { indices: candidate[:indices], cofactor_rank: candidate[:rank], bound: others.length + fused.length,
              rank: compressed.length, density: compressed.sum { |t| t.sum { |v| v.to_s(2).count("1") } },
              compressed_sha256: Digest::SHA256.hexdigest(B.text(compressed.sort)), compression: history }
          end
          selected = assessments.each_index.min_by { |k| [assessments[k][:rank], assessments[k][:density], *assessments[k][:indices]] }
          choice = assessments[selected]
          assessment = { minimum: shortlist[:minimum], eligible_by_rank: shortlist[:eligible_by_rank],
            assessments: assessments, selected: selected, policy: "first-index-pairs-per-cofactor-rank", exhaustive_final_rank: false }
          answer = answer.merge(rank: choice[:cofactor_rank], indices: choice[:indices])
        end
        i, j = answer[:indices]
        chosen = [pools[a][i], pools[b][j]]
        changed = leaves.dup
        [a, b].zip(chosen).each do |slot, choice|
          changed[slot] = M.transvection_word(leaves[slot], choice[:action][:word])
          raise "selected leaf identity mismatch" unless changed[slot].canonical_id == choice[:raw_id]
        end
        tag = "#{target.join('x')}-#{a}-#{b}"
        _, product_recipe = M.export(File.join(root, "products", tag), parent, allocation, changed, target)
        merge_path = File.join(root, "#{tag}.merge.json")
        result = C.export_merge(merge_path, product_recipe, [a, b], axis)
        C.replay(merge_path)
        merged = JSON.parse(File.read(merge_path))
        expected_bound = mapped.each_with_index.sum { |part, slot| [a, b].include?(slot) ? 0 : part.length } + answer[:rank]
        raise "join bound mismatch" unless merged.fetch("bound") == expected_bound && result.rank <= initial.rank
        if assessment
          choice = assessment[:assessments][assessment[:selected]]
          snapshot = merged.fetch("native_fused")
          native = B.load_scheme(File.join(root, snapshot.fetch("path")), snapshot.fetch("shape"))
          compressed, history = S.compress_terms(native.terms)
          raise "postcompression assessment mismatch" unless
            [result.rank, result.audit[:density], Digest::SHA256.hexdigest(B.text(compressed.sort)), history] ==
            choice.values_at(:rank, :density, :compressed_sha256, :compression)
        end
        states = [a, b].each_with_index.map do |slot, side|
          pools[slot].each_with_index.map do |p, index|
            map = normalized[side][index]
            { slot: slot, index: index, action: p[:action], raw_id: p[:raw_id], mapped_rank: p[:terms].length,
              cofactor_rank: map.length, cofactor_sha256: Digest::SHA256.hexdigest(JSON.generate(map.sort)) }
          end
        end
        proposal_path = File.join(root, "#{tag}.proposals.json")
        File.write(proposal_path, JSON.pretty_generate(states) + "\n")
        entry = answer.reject { |k, _| k == :result }.merge(slots: [a, b], axis: axis,
          bound: expected_bound, rank: result.rank, density: result.audit[:density],
          selected: chosen.map { |c| c.slice(:action, :raw_id) }, compression: merged.fetch("compression"),
          product_recipe: product_recipe.delete_prefix(root + "/"), merge_recipe: File.basename(merge_path),
          proposals: File.basename(proposal_path), native_fused: merged.fetch("native_fused"), result: merged.fetch("result"))
        entry[:postcompression] = assessment if assessment
        cases << entry
        puts JSON.generate(entry.reject { |k, _| [:selected, :compression, :native_fused, :result, :postcompression].include?(k) }.merge(
          target: target, compression_assessments: assessment ? assessment[:assessments].length : 1))
        $stdout.flush
      end
      rows << { target: target, initial_rank: initial.rank, initial_density: initial.audit[:density],
        initial_recipe: initial_path.delete_prefix(root + "/"), images: images, generated: generated,
        pair_generated: pair_generated, triple_generated: triple_generated, cases: cases, seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started }
      File.write(File.join(root, "report.json"), JSON.pretty_generate(schema: 1, field: "GF(2)", record_claim: false,
        redistribution_cleared: false, complete: false, source_sha256: pins,
        kernel_maximum: maximum, kernel_pair_width: pair_width, kernel_triple_width: triple_width,
        compression_width: compression_width, compression_slack: compression_slack, rows: rows) + "\n")
    end
    raise "source changed" unless pins.all? { |p, h| Digest::SHA256.file(p).hexdigest == h }
    report_path = File.join(root, "report.json")
    report = JSON.parse(File.read(report_path))
    report["complete"] = true
    File.write(report_path, JSON.pretty_generate(report) + "\n")
    rows
  end
end

if $PROGRAM_NAME == __FILE__
  options = { maximum: 8, pair_width: 0, triple_width: 0, compression_width: 1, compression_slack: 0 }
  output = replay = nil
  parser = OptionParser.new do |o|
    o.banner = "Usage: ruby outer_cofactor_join.rb --output NEW_DIR [options] PRODUCT_RECIPE..."
    o.on("--output PATH") { |v| output = v }
    o.on("--kernel-maximum N", Integer) { |v| options[:maximum] = v }
    o.on("--kernel-pair-width N", Integer) { |v| options[:pair_width] = v }
    o.on("--kernel-triple-width N", Integer) { |v| options[:triple_width] = v }
    o.on("--compression-width N", Integer) { |v| options[:compression_width] = v }
    o.on("--compression-slack N", Integer) { |v| options[:compression_slack] = v }
    o.on("--replay PATH") { |v| replay = v }
    o.on("--help") { puts o; exit }
  end
  parser.parse!
  if replay
    abort "--replay cannot accompany output or inputs" if output || !ARGV.empty?
    puts JSON.generate(MetaflipCofactorMergers.replay(replay))
  else
    abort parser.to_s unless output && !ARGV.empty?
    MetaflipOuterCofactorJoin.run(output, ARGV, **options)
  end
end
