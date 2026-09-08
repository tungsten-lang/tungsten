#!/usr/bin/env ruby
# Bounded offline cover proposals. Replay with verify_parent_cover_scan.py
# before admitting them; neither this scan nor a histogram proves novelty.
require 'timeout'
require_relative 'bud_packing_context'

module MetaflipParentCoverScan
  B = MetaflipBudProducts
  P = MetaflipBudPackings
  module_function

  def select_parents(entries, families)
    raise 'select at least one family' if families.empty?
    selection = []
    parents = families.flat_map do |shape, mode|
      raise 'invalid family selection' unless shape.is_a?(Array) && shape.size == 3 &&
        shape.all? { |d| d.is_a?(Integer) && d.positive? } && %i[all sample].include?(mode)
      family = entries.each_with_index.filter_map { |p,i| [i,p] if p.fetch('shape') == shape }
      raise "empty family #{shape.join('x')}" if family.empty?
      picked = if mode == :sample
        # A heuristic sample, not a shared state key. Retain the newest literal
        # per ordered histogram AND every previously admitted mixed-cover parent.
        representatives = family.group_by { |i,p| p.fetch('signature') }.values.map(&:last)
        controls = family.select { |i,p| !p.fetch('mixed_partitions', []).empty? }
        (representatives + controls).uniq { |i,p| i }
      else
        family
      end
      selection << {shape: shape, family_parents: family.size,
        selected_parents: picked.size, sampling_only: mode == :sample}
      picked
    end
    [parents.sort_by(&:first), selection]
  end

  def scales(shape, maximum)
    shape.map { |d| (1..maximum/d).to_a }.then { |r| r[0].product(r[1], r[2]) }
  end

  def normalize(groups)
    groups.map do |g|
      if g.key?(:elementary_shape)
        {elementary_shape: g[:elementary_shape], indices: g[:indices]}
      else
        {axis: g[:indices].size == 1 ? 0 : g[:axis], indices: g[:indices].sort}
      end
    end.sort_by { |g| JSON.generate(g) }
  end

  def run(inputs:, plan:, output:, families:, max_leaf: 32, max_vertices: 24,
          max_states: 50_000, max_candidates: 50_000, grid_side: 4,
          seconds: 180, case_seconds: 2, progress: $stdout,
          clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    raise 'invalid maximum side' unless max_leaf.is_a?(Integer) && max_leaf.between?(2,32)
    raise 'invalid search limits' unless [max_vertices, max_states, max_candidates].all? { |v| v.is_a?(Integer) && v.positive? }
    raise 'invalid time budget' unless [seconds, case_seconds].all? { |v| v.is_a?(Numeric) && v.finite? && v.positive? }
    raise 'invalid grid side' unless grid_side.is_a?(Integer) && grid_side.between?(2,4)
    paths = [inputs, plan].map { |p| File.realpath(p) }
    # The independent checker uses these two unique roles even after relocation.
    raise 'expected inputs.json and report.json' unless paths.map { |p| File.basename(p) } == %w[inputs.json report.json]
    pins = {}
    documents = paths.map do |path|
      raw = File.binread(path); pins[path] = Digest::SHA256.hexdigest(raw); JSON.parse(raw)
    end
    raise 'unverified input format' unless documents.all? { |d| d['complete'] == true && d['field'] == 'GF(2)' && d['record_claim'] == false }
    corpus, prices_plan = documents
    parents, selection = select_parents(corpus.fetch('parents'), families)
    raise 'family exceeds side cap' unless parents.all? { |i,p| p['shape'].max <= max_leaf }
    shapes, recipes = prices_plan.values_at('model_shapes', 'baseline_recipes')
    raise 'misaligned price plan' unless shapes.size == recipes.size && shapes.uniq.size == shapes.size
    prices = shapes.zip(recipes).to_h { |s,r| [s, r.fetch('rank')] }
    raise 'invalid prices' unless prices.all? { |s,v| s == s.sort && s.size == 3 &&
      s.all? { |d| d.is_a?(Integer) && d.between?(1,32) } && v.is_a?(Integer) && v.positive? }
    library = P::ContextCache::FrozenPrices.new(prices)
    %w[bud_products.rb bud_packings.rb bud_packing_context.rb verify_tensor.rb scan_parent_covers.rb].each do |name|
      path = File.join(__dir__, name); pins[path] = Digest::SHA256.file(path).hexdigest
    end
    root = File.expand_path(output)
    raise 'output already exists' if File.exist?(root)
    FileUtils.mkdir_p(File.dirname(root)); Dir.mkdir(root)
    report = {complete: false, field: 'GF(2)', record_claim: false, screen_only: true,
      workers: 1, gpu_used: false, source_sha256: pins,
      limits: {max_leaf: max_leaf, max_vertices: max_vertices, max_states: max_states,
        max_candidates: max_candidates, grid_side: grid_side,
        case_seconds: case_seconds, campaign_seconds: seconds},
      selection: {families: selection}, requested_parents: parents.size,
      requested_cases: parents.sum { |i,p| scales(p['shape'], max_leaf).size },
      parents: [], rows: [], direct_improvements: [],
      scope: 'Bounded offline formula-cost proposals on ordered literal parents. All integral scales through max_leaf per selected parent. Histogram sampling is not state equivalence or dominance. Campaign time is checked between cases; products, leaf constructions, optimality and novelty require separate verification.'}
    started = clock.call
    save = lambda do
      report[:elapsed_seconds] = clock.call-started
      File.write(root + '/report.pending.json', JSON.pretty_generate(report) + "\n")
      File.rename(root + '/report.pending.json', root + '/report.json')
    end
    expired = -> { clock.call-started >= seconds }
    save.call
    catch(:budget) do
      parents.each do |index, entry|
        throw :budget if expired.call
        raw = File.binread(entry.fetch('path'))
        raise 'source drift' unless Digest::SHA256.hexdigest(raw) == entry.fetch('sha256')
        pins[entry['path']] = entry['sha256']
        parent = B::Scheme.new(entry['shape'], raw)
        raise 'rank drift' unless parent.rank == entry['rank']
        identity = parent.shape.join('x') + "\n" + parent.terms.sort.map { |t| t.join(' ') + "\n" }.join
        raise 'identity drift' unless Digest::SHA256.hexdigest(identity) == entry.fetch('identity')
        info = {index: index, identity: entry['identity'], shape: parent.shape, rank: parent.rank,
          source: B.save_snapshot(root, 'tensors', parent).merge(rank: parent.rank),
          prior_mixed_partitions: entry.fetch('mixed_partitions', []).size, covers: []}
        report[:parents] << info
        known = {}
        cache = P::ContextCache.new(parent, max_leaf: max_leaf, max_vertices: max_vertices,
          max_states: max_states, max_candidates: max_candidates, grids: true, grid_side: grid_side)
        scales(parent.shape, max_leaf).each do |scale|
          throw :budget if expired.call
          target = parent.shape.zip(scale).map { |a,b| a*b }.sort
          pure = B.score(B.partitions(parent, scale, library, trials: 0, max_leaf: max_leaf), scale, library)
          row = {parent: index, scale: scale, target: target, pure_rank: pure, local_rank: prices.fetch(target)}
          begin
            packing = Timeout.timeout(case_seconds) { cache.solve(scale, library) }
            groups = normalize(packing.fetch(:groups)); B.validate_groups(parent, groups)
            raise 'normalization changed cost' unless B.score(groups, scale, library) == packing[:formula_rank]
            key = JSON.generate(groups)
            unless known.key?(key)
              known[key] = info[:covers].size; info[:covers] << groups
            end
            row.merge!(cover: known[key], packing: packing.reject { |k,v| k == :groups },
              rank: packing[:formula_rank], improved: packing[:formula_rank] < row[:local_rank])
            report[:direct_improvements] << row if row[:improved]
          rescue Timeout::Error
            row.merge!(timed_out: true, improved: false)
          end
          report[:rows] << row
          info[:context_cache] = cache.stats
        end
        if report[:parents].size % 10 == 0
          save.call
          progress&.puts(JSON.generate(parents: report[:parents].size, cases: report[:rows].size,
            winning_shapes: report[:direct_improvements].map { |r| r[:target] }.uniq.size,
            elapsed: report[:elapsed_seconds]))
          progress&.flush
        end
      end
    end
    raise 'source changed during scan' unless pins.all? { |p,h| Digest::SHA256.file(p).hexdigest == h }
    report[:complete] = true
    report[:all_cases_attempted] = report[:rows].size == report[:requested_cases]
    report[:all_exact_within_model] = report[:all_cases_attempted] && report[:rows].all? { |r| r.dig(:packing, :exact_within_model) }
    save.call
    report
  end

  def main(argv)
    options = {families: {}}
    OptionParser.new do |p|
      p.banner = 'Usage: scan_parent_covers.rb --inputs inputs.json --plan report.json --output NEW_DIR --all AxBxC | --sample AxBxC'
      %i[inputs plan output].each { |key| p.on("--#{key} PATH") { |v| options[key] = v } }
      %i[all sample].each do |mode|
        p.on("--#{mode} SHAPE", 'Repeat for each ordered family; sample retains newest histogram representatives and prior cover controls') do |v|
          raise 'expected AxBxC' unless v.match?(/\A[1-9]\d*x[1-9]\d*x[1-9]\d*\z/)
          shape = v.split('x').map(&:to_i)
          raise 'duplicate family' if options[:families].key?(shape)
          options[:families][shape] = mode
        end
      end
      %i[max_leaf max_vertices max_states max_candidates grid_side].each do |key|
        p.on("--#{key.to_s.tr('_','-')} N", Integer) { |v| options[key] = v }
      end
      %i[seconds case_seconds].each do |key|
        p.on("--#{key.to_s.tr('_','-')} N", Float) { |v| options[key] = v }
      end
    end.parse!(argv)
    raise 'provide inputs, plan and output; no positional arguments' unless argv.empty? && %i[inputs plan output].all? { |k| options[k] }
    r = run(**options)
    puts JSON.generate(r.slice(:complete, :all_cases_attempted, :all_exact_within_model,
      :requested_parents, :requested_cases, :elapsed_seconds).merge(parents: r[:parents].size,
      cases: r[:rows].size, covers: r[:parents].sum { |p| p[:covers].size },
      winning_shapes: r[:direct_improvements].map { |row| row[:target] }.uniq.size))
  end
end

MetaflipParentCoverScan.main(ARGV) if $PROGRAM_NAME == __FILE__
