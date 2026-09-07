#!/usr/bin/env ruby
require "minitest/autorun"
require "tmpdir"
require_relative "../tools/bud_packings"

class ElementaryGroupsTest < Minitest::Test
  B = MetaflipBudProducts
  P = MetaflipBudPackings

  def setup
    root = File.expand_path("../lib/metaflip/seeds/gf2", __dir__)
    @leaves = %w[matmul_2x2_rank7_strassen_gf2.txt matmul_3x3x4_rank29_gf2.txt
                 matmul_3x4x6_rank54_catalog_gf2.txt].map { |name| B.load_scheme(File.join(root, name)) }
    @library = B::Library.new(@leaves)
  end

  def verify_product(parent, scale, groups)
    leaves = groups.map { |g| @library.scheme(B.group_leaf_shape(scale, g)) }
    product = B.compose(parent, scale, groups, leaves)
    assert product.audit[:exact]
    assert_operator product.rank, :<=, B.score(groups, scale, @library)
    product
  end

  def test_checked_general_elementary_map_is_identity_on_naive_coordinates
    parent = B.naive([2, 2, 2])
    group = { elementary_shape: [2, 2, 2], indices: (0...8).to_a }
    leaf = @library.scheme([4, 6, 4])
    result = B.compose(parent, [2, 3, 2], [group], [leaf])
    assert_equal leaf.terms.sort, result.terms
    assert result.audit[:exact]
  end

  def test_all_three_grid_orientations_improve_the_same_factor_model
    [0, 1, 2].permutation.each do |permutation|
      shape = permutation.map { |i| [1, 2, 2][i] }
      scale = permutation.map { |i| [3, 2, 3][i] }
      parent = B.naive(shape)
      old = P.solve(parent, scale, @library)
      result = P.solve(parent, scale, @library, grids: true)
      assert_equal 58, old[:formula_rank]
      assert_equal 54, result[:formula_rank]
      assert result[:exact_within_model]
      assert_empty result[:cutoffs]
      assert_equal [shape], result[:groups].map { |g| g[:elementary_shape] }
      assert_equal 54, verify_product(parent, scale, result[:groups]).rank
    end
  end

  def test_noninjective_factor_maps_and_cancellation_are_valid
    original = B.naive([1, 1, 2])
    parent = B::Scheme.new(original.shape, B.text(original.terms * 3))
    groups = [{ elementary_shape: [2, 1, 2], indices: [0, 1, 2, 3] },
              { axis: nil, indices: [4] }, { axis: nil, indices: [5] }]
    maps = B.group_factor_maps(parent, groups.first)
    assert_equal [1, 1], maps.first
    result = verify_product(parent, [1, 1, 1], groups)
    assert_equal original.terms.sort, result.terms
    assert_equal 6, B.score(groups, [1, 1, 1], @library)
    assert_equal 2, result.rank
  end

  def test_bad_maps_shapes_indices_and_ambiguous_group_kind_are_rejected
    parent = B.naive([2, 2, 2])
    valid = { elementary_shape: [2, 2, 2], indices: (0...8).to_a }
    invalid = [
      valid.merge(indices: [0, 1, 2, 3, 4, 5, 7, 6]),
      valid.merge(indices: [0, 1, 2, 3, 4, 5, 6, 8]),
      valid.merge(indices: [0, 1, 2, 3, 4, 5, 6, 6]),
      valid.merge(indices: [0, 1, 2, 3, 4, 5, 6, -1]),
      valid.merge(elementary_shape: [2, 2, 3]),
      valid.merge(elementary_shape: [2, 2, 0]),
      valid.merge(elementary_shape: [2, 2, 2.0]),
      valid.merge(elementary_shape: [2, 2, true]),
      valid.merge(elementary_shape: [2, 4]),
      valid.merge(axis: nil)
    ]
    invalid.each { |group| assert_raises(StandardError) { B.validate_groups(parent, [group]) } }
    assert B.validate_groups(parent, [valid])
  end

  # Independent, unordered subset recognition. It never
  # calls grid_groups or group_factor_maps, and does not assume term order.
  def brute_grids(parent, max_side: 2)
    groups = []
    (2..max_side).to_a.product((2..max_side).to_a).map { |a, b| a * b }.uniq.each do |size|
      parent.terms.each_index.to_a.combination(size) do |indices|
        [0, 1, 2].combination(2) do |a, b|
          pairs = indices.map { |i| [parent.terms[i][a], parent.terms[i][b]] }
          height, width = pairs.map(&:first).uniq.size, pairs.map(&:last).uniq.size
          next unless height.between?(2, max_side) && width.between?(2, max_side) &&
                      pairs.uniq.size == size && height * width == size
          shape = [1, 1, 1]
          shape[(B::EDGES[a] - B::EDGES[b]).first] = height
          shape[(B::EDGES[b] - B::EDGES[a]).first] = width
          groups << [indices.reduce(0) { |m, i| m | (1 << i) }, shape]
        end
      end
    end
    groups.sort
  end

  def test_grid_enumeration_matches_all_four_subsets_and_preserves_duplicate_choices
    [B.naive([2, 2, 2]), B.naive([1, 2, 3])].each do |parent|
      actual = P.grid_groups(parent).map do |g|
        assert B.group_factor_maps(parent, g)
        [g[:indices].reduce(0) { |m, i| m | (1 << i) }, g[:elementary_shape]]
      end
      assert_equal brute_grids(parent), actual.sort
    end
    base = B.naive([1, 2, 2])
    duplicate_parent = B::Scheme.new(base.shape, B.text(base.terms * 3))
    groups = P.grid_groups(duplicate_parent).to_a
    assert_equal 81, groups.size
    assert_equal 81, groups.map { |g| g[:indices].sort }.uniq.size
    assert_equal brute_grids(duplicate_parent), groups.map { |g| [g[:indices].sum { |i| 1 << i }, g[:elementary_shape]] }.sort
  end

  def brute_partition_cost(parent, scale, grid_side: 2)
    candidates = []
    (1...(1 << parent.rank)).each do |mask|
      ids = parent.terms.each_index.select { |i| mask[i] == 1 }
      candidates << [mask, @library.rank(scale)] if ids.size == 1
      3.times do |axis|
        next unless ids.map { |i| parent.terms[i][axis] }.uniq.size == 1
        leaf = B.leaf_shape(scale, axis, ids.size)
        candidates << [mask, @library.rank(leaf)] if leaf.max <= 16
      end
    end
    brute_grids(parent, max_side: grid_side).each do |mask, shape|
      leaf = shape.zip(scale).map { |a, b| a * b }
      candidates << [mask, @library.rank(leaf)] if leaf.max <= 16
    end
    memo = { 0 => 0 }
    visit = lambda do |mask|
      return memo.fetch(mask) if memo.key?(mask)
      first = mask & -mask
      memo[mask] = candidates.filter_map do |group, cost|
        cost + visit.call(mask ^ group) if (group & first) != 0 && (group & mask) == group
      end.min
    end
    visit.call((1 << parent.rank) - 1)
  end

  def test_grid_packing_matches_independent_exhaustion_and_reports_limits
    parents = [B.naive([1, 2, 2]), B.naive([2, 2, 2])]
    rows = parents.last.terms.map(&:dup)
    rows[0][2] ^= rows[1][2]
    rows[1][1] ^= rows[0][1]
    parents << B::Scheme.new([2, 2, 2], B.text(rows))
    parents.each do |parent|
      result = P.solve(parent, [3, 2, 3], @library, grids: true)
      assert result[:exact_within_model]
      assert_equal brute_partition_cost(parent, [3, 2, 3]), result[:formula_rank]
      verify_product(parent, [3, 2, 3], result[:groups])
      %i[max_candidates max_vertices max_states].each do |limit|
        limited = P.solve(parent, [3, 2, 3], @library, grids: true, **{ limit => 1 })
        refute limited[:exact_within_model]
        assert_operator limited[:formula_rank], :>=, result[:formula_rank]
        verify_product(parent, [3, 2, 3], limited[:groups])
      end
    end
  end

  def test_larger_rectangles_match_independent_subsets_and_partition_optima
    [[1, 2, 3], [1, 3, 3]].each do |base|
      base.permutation.to_a.uniq.each do |shape|
        parent = B.naive(shape)
        actual = P.grid_groups(parent, max_side: 3).map do |g|
          assert B.group_factor_maps(parent, g)
          [g[:indices].sum { |i| 1 << i }, g[:elementary_shape]]
        end
        assert_equal brute_grids(parent, max_side: 3), actual.sort
        result = P.solve(parent, [2, 2, 2], @library, grids: true, grid_side: 3)
        assert result[:exact_within_model]
        assert_equal brute_partition_cost(parent, [2, 2, 2], grid_side: 3), result[:formula_rank]
        verify_product(parent, [2, 2, 2], result[:groups])
      end
    end
    parent = B.naive([1, 2, 3])
    groups = P.grid_groups(parent, max_side: 3, shapes: [[1, 2, 3]]).to_a
    assert_equal 1, groups.size
    assert_equal [1, 2, 3], groups.first.fetch(:elementary_shape)
    [1, 5, 2.0, true].each do |bad|
      assert_raises(RuntimeError) { P.grid_groups(parent, max_side: bad).to_a }
      assert_raises(RuntimeError) { P.solve(parent, [1, 1, 1], @library, grid_side: bad) }
    end
  end

  def test_larger_rectangles_improve_and_export_replayable_maps
    parent = B.naive([1, 2, 3])
    scale = [3, 2, 2]
    before = P.solve(parent, scale, @library, grids: true)
    result = P.solve(parent, scale, @library, grids: true, grid_side: 3)
    assert_operator result[:formula_rank], :<, before[:formula_rank]
    assert_equal 54, result[:formula_rank]
    assert_equal 54, verify_product(parent, scale, result[:groups]).rank
    Dir.mktmpdir("larger-grid-replay") do |dir|
      _scheme, recipe = B.export(dir, parent, scale, result[:groups], @library)
      assert_equal 54, B.replay(recipe)[:rank]
      assert_equal 2, JSON.parse(File.read(recipe)).fetch("schema")
    end
  end

  def test_four_side_and_more_than_sixty_four_columns_preserve_enumeration
    parent = B.naive([1, 2, 4])
    actual = P.grid_groups(parent, max_side: 4).map do |g|
      assert B.group_factor_maps(parent, g)
      [g[:indices].sum { |i| 1 << i }, g[:elementary_shape]]
    end
    assert_equal brute_grids(parent, max_side: 4), actual.sort
    assert_includes actual.map(&:last), [1, 2, 4]
    # Many distinct column classes, not just high bits inside factor masks.
    fake = Struct.new(:terms).new((0...70).flat_map { |c| [[1, 1 << c, 1], [2, 1 << c, 2]] })
    grids = P.grid_groups(fake, shapes: [[2, 1, 2]]).to_a
    assert_equal 70 * 69 / 2, grids.length
    assert_equal [0, 2, 1, 3], grids.first.fetch(:indices)
    assert_equal [136, 138, 137, 139], grids.last.fetch(:indices)
    [0, 1, 2, 3, (1 << 70) | 1].each do |mask|
      (1..4).each { |count| assert_equal mask.to_s(2).count("1") >= count, P.enough_bits?(mask, count) }
    end
  end

  def test_one_grid_parent_objective_is_constructive_and_not_full_packing
    parent = B.naive([2, 2, 2])
    scale = [3, 2, 3]
    groups = P.one_grid_partition(parent, scale, @library)
    assert_equal 1, groups.count { |g| g.key?(:elementary_shape) }
    assert_equal 112, B.score(groups, scale, @library)
    assert_equal 112, verify_product(parent, scale, groups).rank
    full = P.solve(parent, scale, @library, grids: true)
    assert_equal 108, full[:formula_rank]
    assert_operator full[:formula_rank], :<, B.score(groups, scale, @library)
  end

  def test_cli_schema_two_replay_and_schema_downgrade_rejection
    Dir.mktmpdir("elementary-grid-test") do |root|
      lib = File.join(root, "library")
      Dir.mkdir(lib)
      @leaves.each do |leaf|
        File.write(File.join(lib, "matmul_#{leaf.shape.join('x')}_rank#{leaf.rank}_test_gf2.txt"), leaf.source_text)
      end
      parent = B.save_snapshot(root, "input", B.naive([1, 2, 2]))
      output = File.join(root, "output")
      capture_io { P.main(["--library", lib, "--grids", "--scale", "3x2x3", "--output", output, File.join(root, parent[:path])]) }
      report = JSON.parse(File.read(File.join(output, "report.json")))
      path = report.fetch("rows").first.fetch("recipe")
      recipe = JSON.parse(File.read(path))
      assert_equal 2, recipe.fetch("schema")
      assert_equal 54, B.replay(path)[:rank]
      recipe["schema"] = 1
      File.write(path, JSON.generate(recipe))
      error = assert_raises(RuntimeError) { B.replay(path) }
      assert_equal "elementary groups require schema 2", error.message
    end
  end

  def test_product_search_opt_in_keeps_legacy_search_and_finds_the_grid
    Dir.mktmpdir("elementary-product-test") do |root|
      lib = File.join(root, "library")
      Dir.mkdir(lib)
      @leaves.each do |leaf|
        File.write(File.join(lib, "matmul_#{leaf.shape.join('x')}_rank#{leaf.rank}_test_gf2.txt"), leaf.source_text)
      end
      parent = B.save_snapshot(root, "input", B.naive([1, 2, 2]))
      reports = [false, true].map do |grids|
        args = ["--library", lib, "--max-scale", "3", "--max-dimension", "6", "--trials", "0",
                "--output", File.join(root, grids ? "grids" : "legacy"), File.join(root, parent[:path])]
        args << "--grids" if grids
        capture_io { B.main(args) }
        JSON.parse(File.read(File.join(root, grids ? "grids" : "legacy", "report.json")))
      end
      old, extended = reports.map { |r| r.fetch("rows").find { |x| x.fetch("canonical_target") == "3x4x6" } }
      assert_equal 58, old.fetch("exact_rank")
      assert_equal 54, extended.fetch("exact_rank")
      assert_equal 1, extended.fetch("elementary_groups")
      assert_equal 0, reports.first.fetch("grid_jobs")
      assert_operator reports.last.fetch("grid_cost_improvements"), :>, 0
      assert_equal 54, B.replay(extended.fetch("recipe"))[:rank]
    end
  end
end
