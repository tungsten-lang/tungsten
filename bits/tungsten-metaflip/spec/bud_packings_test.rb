#!/usr/bin/env ruby
require "minitest/autorun"
require "tmpdir"
require_relative "../tools/bud_packings"

class BudPackingsTest < Minitest::Test
  B = MetaflipBudProducts
  P = MetaflipBudPackings

  def setup
    root = File.expand_path("../lib/metaflip/seeds/gf2", __dir__)
    @leaves = %w[matmul_2x2_rank7_strassen_gf2.txt matmul_3x3x4_rank29_gf2.txt
                 matmul_3x4x6_rank54_catalog_gf2.txt].map { |n| B.load_scheme(File.join(root, n)) }
    @library = B::Library.new(@leaves)
  end

  def mixed_parent
    # A single W-equal flip of the naive 2x2x3 decomposition, not imported data.
    rows = B.naive([2, 2, 3]).terms.map(&:dup)
    rows[6][1] ^= rows[9][1]
    rows[9][0] ^= rows[6][0]
    B::Scheme.new([2, 2, 3], B.text(rows))
  end

  # Independent exhaustive partition recurrence: minimize costs directly,
  # including nonpositive-gain groups, without components or gain pruning.
  def brute_cost(parent, scale, max_leaf: 16)
    memo = { 0 => 0 }
    visit = lambda do |mask|
      return memo.fetch(mask) if memo.key?(mask)
      bit = mask & -mask
      first = bit.bit_length - 1
      best = @library.rank(scale) + visit.call(mask ^ bit)
      3.times do |axis|
        others = parent.terms.each_index.select do |i|
          i != first && mask[i] == 1 && parent.terms[i][axis] == parent.terms[first][axis]
        end
        maximum = [others.length + 1, max_leaf / scale[B::EXPANDED_DIMENSION[axis]]].min
        2.upto(maximum) do |size|
          cost = @library.rank(B.leaf_shape(scale, axis, size))
          others.combination(size - 1) do |rest|
            group = rest.reduce(bit) { |m, i| m | (1 << i) }
            best = [best, cost + visit.call(mask ^ group)].min
          end
        end
      end
      memo[mask] = best
    end
    visit.call((1 << parent.rank) - 1)
  end

  def check_product(parent, scale, result)
    groups = result.fetch(:groups)
    assert B.validate_groups(parent, groups)
    leaves = groups.map { |g| @library.scheme(B.leaf_shape(scale, g[:axis], g[:indices].length)) }
    product = B.compose(parent, scale, groups, leaves)
    assert product.audit[:exact]
    assert_operator product.rank, :<=, result.fetch(:formula_rank)
  end

  def test_matches_independent_exhaustive_partition_cost
    parents = [[1, 1, 3], [1, 2, 2], [2, 2, 2]].map { |s| B.naive(s) } + [mixed_parent]
    parents.each do |parent|
      [[2, 2, 1], [3, 4, 3]].each do |scale|
        result = P.solve(parent, scale, @library)
        assert result[:exact_within_model]
        assert_empty result[:cutoffs]
        assert_equal brute_cost(parent, scale), result[:formula_rank]
        assert_equal false, result[:record_claim]
        check_product(parent, scale, result)
      end
    end
  end

  def test_mixed_axis_partition_beats_every_pure_axis_and_is_repeatable
    parent = mixed_parent
    scale = [3, 4, 3]
    baseline = B.score(B.partitions(parent, scale, @library, trials: 0), scale, @library)
    result = P.solve(parent, scale, @library)
    assert_equal 328, baseline
    assert_equal 324, result[:formula_rank]
    assert_equal [0, 1], result[:groups].map { |g| g[:axis] }.uniq.sort
    assert_equal 2, result[:components]
    assert_equal 6, result[:max_component_vertices]
    assert_equal result, P.solve(parent, scale, @library)
    check_product(parent, scale, result)
  end

  def test_limits_are_explicit_and_preserve_a_feasible_upper_bound
    parent = mixed_parent
    scale = [3, 4, 3]
    baseline = B.score(B.partitions(parent, scale, @library, trials: 0), scale, @library)
    { max_states: "states", max_vertices: "vertices", max_candidates: "candidates" }.each do |key, reason|
      result = P.solve(parent, scale, @library, **{ key => 1 })
      refute result[:exact_within_model]
      assert_includes result[:cutoffs], reason
      assert_operator result[:formula_rank], :<=, baseline
      check_product(parent, scale, result)
    end
  end

  def test_empty_candidate_set_and_invalid_limits
    library = B::Library.new([@leaves.first])
    result = P.solve(B.naive([1, 1, 2]), [2, 2, 2], library)
    assert result[:exact_within_model]
    assert_equal 0, result[:candidates]
    assert_equal 0, result[:states]
    assert_equal 14, result[:formula_rank]
    assert_raises(RuntimeError) { P.solve(mixed_parent, [3, 4, 3], @library, max_leaf: 3) }
    assert_raises(RuntimeError) { P.solve(mixed_parent, [3, 4, 3], @library, max_states: 0) }
  end

  def test_cli_recipe_replay_and_overwrite_refusal
    Dir.mktmpdir("bud-packing-test") do |root|
      library = File.join(root, "library")
      Dir.mkdir(library)
      @leaves.each do |leaf|
        File.write(File.join(library, "matmul_#{leaf.shape.join('x')}_rank#{leaf.rank}_test_gf2.txt"), leaf.source_text)
      end
      parent = B.save_snapshot(root, "input", mixed_parent)
      output = File.join(root, "output")
      args = ["--library", library, "--scale", "3x4x3", "--output", output, File.join(root, parent[:path])]
      capture_io { P.main(args.dup) }
      report = JSON.parse(File.read(File.join(output, "report.json")))
      assert_equal false, report.fetch("record_claim")
      assert_equal 324, report.fetch("rows").first.fetch("formula_rank")
      assert B.replay(report.fetch("rows").first.fetch("recipe"))[:exact]
      assert_raises(RuntimeError) { P.main(args.dup) }
    end
  end

  def test_report_mode_improves_or_preserves_the_verified_baseline
    Dir.mktmpdir("bud-packing-report-test") do |root|
      library = File.join(root, "library")
      Dir.mkdir(library)
      @leaves.each do |leaf|
        File.write(File.join(library, "matmul_#{leaf.shape.join('x')}_rank#{leaf.rank}_test_gf2.txt"), leaf.source_text)
      end
      parent = mixed_parent
      scale = [3, 4, 3]
      pure = B.partitions(parent, scale, @library, trials: 0)
      optimal = P.solve(parent, scale, @library).fetch(:groups)
      recipes = [pure, optimal].each_with_index.map do |groups, index|
        _product, path = B.export(File.join(root, "baseline-#{index}"), parent, scale, groups, @library)
        { recipe: path }
      end
      baseline = File.join(root, "baseline.json")
      File.write(baseline, JSON.generate(schema: 1, field: "GF(2)", rows: recipes))
      output = File.join(root, "output")
      args = ["--library", library, "--from-report", baseline, "--output", output]
      capture_io { P.main(args.dup) }
      report = JSON.parse(File.read(File.join(output, "report.json")))
      assert_equal Digest::SHA256.file(baseline).hexdigest, report.fetch("baseline_sha256")
      assert_equal [328, 324], report.fetch("rows").map { |r| r.fetch("baseline").fetch("formula_rank") }
      report.fetch("rows").each do |row|
        assert_equal 324, row.fetch("formula_rank")
        assert row.fetch("exact_within_model")
        assert B.replay(row.fetch("recipe"))[:exact]
      end

      limited = File.join(root, "limited")
      capture_io do
        P.main(["--library", library, "--from-report", baseline, "--max-states", "1", "--output", limited])
      end
      row = JSON.parse(File.read(File.join(limited, "report.json"))).fetch("rows").last
      refute row.fetch("exact_within_model")
      assert_equal 324, row.fetch("formula_rank")
      assert_equal 324, row.fetch("baseline").fetch("formula_rank")
      assert B.replay(row.fetch("recipe"))[:exact]
      saved = JSON.parse(File.read(row.fetch("recipe"))).fetch("groups")
      original = JSON.parse(File.read(recipes.last.fetch(:recipe))).fetch("groups")
      assert_equal original, saved

      assert_raises(RuntimeError) { P.main(args + ["--scale", "3x4x3"]) }
      assert_raises(RuntimeError) { P.main(args + [recipes.first.fetch(:recipe)]) }
      File.delete(Dir[File.join(library, "matmul_3x3x4_*")].fetch(0))
      error = assert_raises(RuntimeError) do
        P.main(["--library", library, "--from-report", baseline, "--output", File.join(root, "changed")])
      end
      assert_equal "baseline leaf pricing changed", error.message
    end
  end

  def test_report_mode_requires_matching_recursive_product_prices
    Dir.mktmpdir("bud-packing-product-test") do |root|
      library_path = File.join(root, "library")
      Dir.mkdir(library_path)
      strassen = @leaves.first
      File.write(File.join(library_path, "matmul_2x2x2_rank7_test_gf2.txt"), strassen.source_text)
      block_library = B::Library.new([strassen])
      product_library = B::Library.new([strassen], products: true)
      assert_equal 56, block_library.rank([4, 4, 4])
      assert_equal 49, product_library.rank([4, 4, 4])
      _scheme, recipe = B.export(File.join(root, "baseline"), B.naive([1, 1, 1]),
                                [4, 4, 4], [{ axis: nil, indices: [0] }], product_library)
      report_path = File.join(root, "baseline.json")
      File.write(report_path, JSON.generate(schema: 1, field: "GF(2)", rows: [{ recipe: recipe }]))
      args = ["--library", library_path, "--from-report", report_path]
      error = assert_raises(RuntimeError) { P.main(args + ["--output", File.join(root, "wrong-prices")]) }
      assert_equal "baseline leaf pricing changed", error.message
      output = File.join(root, "matched-prices")
      capture_io { P.main(args + ["--recursive-products", "--output", output]) }
      report = JSON.parse(File.read(File.join(output, "report.json")))
      assert_equal true, report.fetch("options").fetch("products")
      row = report.fetch("rows").first
      assert_equal 49, row.fetch("formula_rank")
      assert row.fetch("exact_within_model")
      assert B.replay(row.fetch("recipe"))[:exact]
    end
  end

  def test_native_bank_supports_parent_and_report_modes_with_standalone_replay
    Dir.mktmpdir('bud-packing-native') do |root|
      spool = File.join(root,'spool')
      %w[objects composition/banks composition/bank-latest].each { |p| FileUtils.mkdir_p(File.join(spool,p)) }
      native = B::Library.new([@leaves.first])
      ids = (1..6).map do |k|
        leaf = native.scheme([k,2,2])
        raw = "MFR1 #{k} 2 2 #{leaf.rank}\n" + leaf.terms.sort.map { |t| t.join(' ')+"\n" }.join
        key = Digest::SHA256.hexdigest(raw)
        File.write(File.join(spool,'objects',"#{key}.tensor"),raw)
        key
      end
      manifest = ['MFC_BANK1','2',*ids].join(' ')+"\n"
      bank_id = Digest::SHA256.hexdigest(manifest)
      File.write(File.join(spool,'composition/banks',bank_id),manifest)
      pointer = File.join(spool,'composition/bank-latest/2')
      File.write(pointer,bank_id+"\n")
      library = File.join(root,'library'); Dir.mkdir(library)
      File.write(File.join(library,'matmul_1x1x1_rank1_gf2.txt'),B.naive([1,1,1]).source_text)
      parent = B.naive([1,1,2]); scale = [2,2,1]
      source = File.join(root,'matmul_1x1x2_rank2_gf2.txt')
      File.write(source,parent.source_text)
      groups = [{axis:0,indices:[0,1]}]
      _result,recipe = B.export(File.join(root,'baseline'),parent,scale,groups,native)
      from = File.join(root,'baseline.json')
      File.write(from,JSON.generate(schema:1,field:'GF(2)',rows:[{recipe:recipe}]))
      base = ['--library',library]
      error = assert_raises(RuntimeError) do
        P.main(base+['--from-report',from,'--output',File.join(root,'without-native')])
      end
      assert_equal 'baseline leaf pricing changed',error.message
      recipes = []
      [['--scale','2x2x1',source],['--from-report',from]].each_with_index do |mode,i|
        output = File.join(root,"output-#{i}")
        capture_io { P.main(base+['--native-spool',spool,'--output',output]+mode) }
        report = JSON.parse(File.read(File.join(output,'report.json')))
        assert_equal [bank_id],report.fetch('native_banks').map { |b| b.fetch('identity') }
        row = report.fetch('rows').first
        assert_equal 7,row.fetch('formula_rank')
        assert row.fetch('exact_within_model')
        assert B.replay(row.fetch('recipe'))[:exact]
        recipes << row.fetch('recipe')
      end
      File.write(pointer,'broken')
      assert_raises(RuntimeError) do
        P.main(base+['--native-spool',spool,'--scale','2x2x1','--output',File.join(root,'bad'),source])
      end
      refute File.exist?(File.join(root,'bad'))
      FileUtils.rm_rf(spool)
      recipes.each { |r| assert B.replay(r)[:exact] }
    end
  end
end
