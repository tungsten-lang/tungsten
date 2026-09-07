#!/usr/bin/env ruby
require "minitest/autorun"
require "tmpdir"
require_relative "../tools/bud_products"

class BudProductsTest < Minitest::Test
  B = MetaflipBudProducts

  def setup
    root = File.expand_path("../lib/metaflip/seeds/gf2", __dir__)
    @strassen = B.load_scheme(File.join(root, "matmul_2x2_rank7_strassen_gf2.txt"))
    @library = B::Library.new([@strassen])
  end

  def test_each_bud_axis_constructs_strassen_not_an_unverified_rank_number
    [[0, [1, 1, 2], [2, 2, 1]], [1, [2, 1, 1], [1, 2, 2]],
     [2, [1, 2, 1], [2, 1, 2]]].each do |axis, shape, scale|
      parent = B.naive(shape)
      groups = [{ axis: axis, indices: [0, 1] }]
      assert_equal 8, parent.rank * @library.rank(scale)
      assert_equal 7, B.score(groups, scale, @library)
      result = B.compose(parent, scale, groups, [@strassen])
      assert_equal [2, 2, 2], result.shape
      assert_equal 7, result.rank
      assert result.audit[:exact]
    end
  end

  def test_all_six_orientations_with_asymmetric_nontrivial_factors
    shape = [2, 3, 4]
    root = File.expand_path("../lib/metaflip/seeds/gf2", __dir__)
    source = B.load_scheme(File.join(root, "matmul_2x3x4_rank20_d130_global_isotropy_gf2.txt"))
    shape.permutation.each do |target|
      result = B.orient(source, target)
      assert_equal target, result.shape
      assert_equal 20, result.rank
      assert result.audit[:exact]
      assert_equal source.terms, B.orient(result, shape).terms
    end
    assert_raises(RuntimeError) { B.orient(source, [2, 3, 5]) }
  end

  def test_exact_missing_leaf_block_sums_and_wide_words
    [[2, 2, 3], [3, 2, 4], [2, 4, 3], [8, 8, 2]].each do |shape|
      leaf = @library.scheme(shape)
      assert leaf.audit[:exact]
      assert_equal @library.rank(shape), leaf.rank
    end
    assert_equal 11, @library.rank([2, 2, 3])
    parent = B.naive([1, 1, 2])
    groups = [{ axis: 0, indices: [0, 1] }]
    result = B.compose(parent, [8, 8, 1], groups, [@library.scheme([8, 8, 2])])
    assert result.terms.any? { |u, _v, _w| u.bit_length == 64 }
    assert result.audit[:exact]
  end

  def test_optional_recursive_products_improve_bounds_and_preserve_default
    closure = B::Library.new([@strassen], products: true)
    assert_equal 56, @library.rank([4, 4, 4])
    assert_equal 49, closure.rank([4, 4, 4])
    assert_equal 343, closure.rank([8, 8, 8])
    assert_equal :product, closure.plan([4, 4, 4])[:kind]
    [[4, 4, 4], [4, 6, 6], [6, 4, 6], [6, 6, 4], [8, 8, 8], [1, 7, 9]].each do |shape|
      scheme = closure.scheme(shape)
      assert_equal closure.rank(shape), scheme.rank
      assert scheme.audit[:exact]
      assert_operator scheme.rank, :<=, @library.rank(shape)
    end
    # No infinite recursion on unit coordinates; multiplicity is retained.
    assert_equal 63, closure.rank([1, 7, 9])
    left = B.naive([1, 1, 2])
    left = B::Scheme.new(left.shape, B.text(left.terms + [[1, 3, 3], [1, 3, 3]]))
    result = B.tensor_product(left, @strassen)
    assert_equal left.rank * @strassen.rank, result.rank
    assert result.audit[:exact]
  end

  def test_recursive_product_leaves_export_self_contained_recipes
    closure = B::Library.new([@strassen], products: true)
    parent = B.naive([1, 1, 1])
    groups = [{ axis: nil, indices: [0] }]
    Dir.mktmpdir("product-closure-replay") do |root|
      result, path = B.export(root, parent, [4, 4, 4], groups, closure)
      assert_equal 49, result.rank
      assert_equal result.audit, B.replay(path)
    end
  end

  def test_dense_buds_asymmetric_scale_and_deterministic_search
    # A flip changes the last two factors but keeps the same exact parent.
    parent = B.naive([2, 2, 3])
    terms = parent.terms.map(&:dup)
    terms[0][1] ^= terms[1][1]
    terms[1][2] ^= terms[0][2]
    parent = B::Scheme.new(parent.shape, B.text(terms))
    scale = [2, 3, 1]
    groups = B.partitions(parent, scale, @library, trials: 5, seed: 927)
    assert_equal groups, B.partitions(parent, scale, @library, trials: 5, seed: 927)
    assert_operator B.score(groups, scale, @library), :<=, parent.rank * @library.rank(scale)
    leaves = groups.map { |g| @library.scheme(B.leaf_shape(scale, g[:axis], g[:indices].length)) }
    result = B.compose(parent, scale, groups, leaves)
    assert_equal [4, 6, 3], result.shape
    assert result.audit[:exact]
  end

  def test_partition_gate_and_corrupt_leaf
    parent = B.naive([1, 1, 2])
    bad = [[{ axis: 0, indices: [0, 0] }], [{ axis: 0, indices: [0] }],
           [{ axis: 0, indices: [-1, 1] }], [{ axis: nil, indices: [0, 1] }],
           [{ axis: 3, indices: [0, 1] }], [{ axis: 1, indices: [0, 1] }]]
    bad.each { |groups| assert_raises(RuntimeError) { B.validate_groups(parent, groups) } }
    groups = [{ axis: 0, indices: [0, 1] }]
    assert_raises(RuntimeError) { B.compose(parent, [2, 2, 1], groups, [B.naive([2, 1, 2])]) }
    corrupt = @strassen.terms.map(&:dup)
    corrupt[0][0] ^= 1
    assert_raises(RuntimeError) { B::Scheme.new([2, 2, 2], B.text(corrupt)) }
  end

  def test_xor_cancellation_and_mapped_zero_are_exact_not_set_union
    parent = B.naive([1, 1, 2])
    # Two redundant copies vanish in F2 but remain in the input partition.
    rows = parent.terms.map(&:dup) + [[1, 3, 3], [1, 3, 3]]
    parent = B::Scheme.new(parent.shape, B.text(rows))
    groups = parent.rank.times.map { |i| { axis: nil, indices: [i] } }
    leaves = groups.map { @library.scheme([2, 2, 1]) }
    result = B.compose(parent, [2, 2, 1], groups, leaves)
    assert_equal 8, result.rank
    assert result.audit[:exact]
    # Both copies can instead be embedded as one bud whose maps have a kernel.
    groups = [{ axis: 0, indices: [0, 1] }, { axis: 0, indices: [2, 3] }]
    result = B.compose(parent, [2, 2, 1], groups, [@strassen, @strassen])
    assert result.audit[:exact]
    assert_operator result.rank, :<=, 14
  end

  def test_replay_is_self_contained_and_rejects_mutation
    parent = B.naive([1, 1, 2])
    groups = [{ axis: 0, indices: [0, 1] }]
    Dir.mktmpdir("bud-product-test") do |root|
      result, recipe = B.export(root, parent, [2, 2, 1], groups, @library)
      assert_equal result.audit, B.replay(recipe)
      data = JSON.parse(File.read(recipe))
      assert_equal false, data["record_claim"]
      input = File.join(root, data["parent"]["path"])
      assert_equal [1, 1, 2], B.infer_shape(input)
      File.write(input, File.read(input) + "# altered bytes\n")
      assert_raises(RuntimeError) { B.replay(recipe) }
    end
  end

  def test_canonical_identity_ignores_term_order_not_coefficients
    parent = B.naive([2, 2, 3])
    reversed = B::Scheme.new(parent.shape, B.text(parent.terms.reverse))
    assert_equal parent.canonical_id, reversed.canonical_id
    assert_raises(RuntimeError) { B.infer_shape("matmul_2x3_rank20_bad_gf2.txt") }
    assert_equal [5, 5, 5], B.infer_shape("matmul_5x5_rank93_gf2.txt")
  end

  def test_cli_snapshots_dedup_control_and_replay
    Dir.mktmpdir("bud-product-cli-test") do |root|
      library = File.join(root, 'library')
      Dir.mkdir(library)
      File.write(File.join(library, 'matmul_2x2_rank7_strassen_gf2.txt'), @strassen.source_text)
      parent = B.naive([1, 1, 2])
      first = File.join(root, 'matmul_1x1x2_rank2_first_gf2.txt')
      second = File.join(root, 'matmul_1x1x2_rank2_reverse_gf2.txt')
      File.write(first, parent.source_text)
      File.write(second, B.text(parent.terms.reverse))
      output = File.join(root, 'output')
      args = ['--library', library, '--output', output, '--max-dimension', '4',
              '--max-scale', '2', '--trials', '2', '--leaders-only', first, second]
      capture_io { B.main(args.dup) }
      report = JSON.parse(File.read(File.join(output, 'report.json')))
      assert_equal 2, report['input_files']
      assert_equal 1, report['parents']
      assert_equal false, report['record_claim']
      assert report['rows'].all? { |row| B.replay(row['recipe'])[:exact] }
      assert_raises(RuntimeError) { B.main(args.dup) } # never overwrite an earlier run
    end
  end

  def test_saved_8_by_8_by_9_recipe
    fixture = File.expand_path('../../../benchmarks/matmul/metaflip/bud_products_2026_09_06/8x8x9.recipe.json', __dir__)
    skip 'Research certificates are not bundled in the standalone bit' unless File.file?(fixture)
    result = B.replay(fixture)
    assert_equal '8x8x9', result[:shape]
    assert_equal 387, result[:rank]
    assert_equal '36e8029b64a6a85803072e5eef59762ea00061f420da8ba883b8ee8498ebc93b', result[:sha256]
  end

  def test_saved_native_parent_product
    fixture = File.expand_path('../../../benchmarks/matmul/metaflip/bud_parent_walk_2026_09_06/8x8x9.recipe.json', __dir__)
    skip 'Research certificates are not bundled in the standalone bit' unless File.file?(fixture)
    result = B.replay(fixture)
    assert_equal '8x8x9', result[:shape]
    assert_equal 381, result[:rank]
    assert_equal 6416, result[:density]
    assert_equal 'eef47a4542032ad74a1e6f121bdf8deadcd38c85aa04ccd88462a12a57af63cd', result[:sha256]
  end

  def test_saved_enriched_library_products
    root = File.expand_path('../../../benchmarks/matmul/metaflip/bud_parent_walk_2026_09_06/enriched', __dir__)
    skip 'Research certificates are not bundled in the standalone bit' unless File.directory?(root)
    { '16x16x10' => 1535, '12x12x10' => 895, '8x12x15' => 896 }.each do |shape, rank|
      result = B.replay(File.join(root, shape + '.recipe.json'))
      assert result[:exact]
      assert_equal shape, result[:shape]
      assert_equal rank, result[:rank]
    end
  end
end
