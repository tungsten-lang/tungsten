#!/usr/bin/env ruby
require "minitest/autorun"
require_relative "../tools/bud_packing_context"

class BudPackingContextTest < Minitest::Test
  B = MetaflipBudProducts
  P = MetaflipBudPackings

  class Prices
    attr_accessor :multiplier, :override
    def initialize(library, multiplier = 1)
      @library, @multiplier = library, multiplier
      @override = {}
    end
    def rank(shape)
      @override.fetch(shape.sort) { @multiplier * @library.rank(shape) }
    end
  end

  def setup
    root = File.expand_path("../lib/metaflip/seeds/gf2", __dir__)
    @library = B::Library.new(%w[matmul_2x2_rank7_strassen_gf2.txt
      matmul_3x3x4_rank29_gf2.txt matmul_3x4x6_rank54_catalog_gf2.txt].map { |n|
      B.load_scheme(File.join(root, n))
    })
    rows = B.naive([2, 2, 3]).terms.map(&:dup)
    rows[6][1] ^= rows[9][1]; rows[9][0] ^= rows[6][0]
    @parent = B::Scheme.new([2, 2, 3], B.text(rows))
  end

  def test_exact_full_result_matches_uncached_over_scales_and_price_multiples
    [B.naive([1, 2, 2]), @parent, B::Scheme.new(@parent.shape, B.text(@parent.terms.reverse))].each do |parent|
      [false, true].each do |grids|
        options = {max_leaf: 8, grids: grids, grid_side: 3}
        cache = P::ContextCache.new(parent, **options)
        [1, 3].repeated_permutation(3).each do |scale|
          [1, 7].each do |multiplier|
            library = Prices.new(@library, multiplier)
            expected = P.solve(parent, scale, library, **options)
            actual = cache.solve(scale, library)
            assert_equal expected, actual
            assert B.validate_groups(parent, actual[:groups])
          end
        end
        assert_operator cache.stats[:hits], :>=, 8
      end
    end
  end

  def test_result_mutation_cannot_poison_cache_and_changed_prices_are_rekeyed
    options = {max_leaf: 8, grids: true}
    cache = P::ContextCache.new(@parent, **options)
    library = Prices.new(@library)
    expected = P.solve(@parent, [2, 2, 2], library, **options)
    result = cache.solve([2, 2, 2], library)
    result[:groups][0][:indices][0] = 999
    result[:cutoffs] << "invented"
    assert_equal expected, cache.solve([2, 2, 2], library)
    assert_equal 1, cache.stats[:hits]
    library.override[[2, 2, 2]] = 6
    assert_equal P.solve(@parent, [2, 2, 2], library, **options), cache.solve([2, 2, 2], library)
    assert_equal 2, cache.stats[:misses]
    assert_raises(FrozenError) { @parent.terms.first[0] = 0 }
  end

  def test_incomplete_results_are_not_cached
    options = {max_states: 1}
    cache = P::ContextCache.new(@parent, **options)
    2.times do
      actual = cache.solve([3, 4, 3], @library)
      refute actual[:exact_within_model]
      assert_equal P.solve(@parent, [3, 4, 3], @library, **options), actual
    end
    assert_equal 0, cache.stats[:hits]
    assert_equal 0, cache.stats[:entries]
  end

  def test_orientation_sensitive_prices_are_not_silently_canonicalized
    library = Object.new
    def library.rank(shape)
      100*shape[0] + 10*shape[1] + shape[2]
    end
    options = {max_leaf: 8, grids: true}
    cache = P::ContextCache.new(@parent, **options)
    [[2, 3, 1], [3, 2, 1], [2, 3, 1]].each do |scale|
      assert_equal P.solve(@parent, scale, library, **options), cache.solve(scale, library)
    end
    assert_equal 1, cache.stats[:hits]
  end

  def test_capacity_and_truncated_grid_catalog_preserve_results
    parent = B.naive([2, 2, 3])
    options = {max_leaf: 8, grids: true, grid_side: 3}
    cache = P::ContextCache.new(parent, **options, entries: 1, grid_scan_limit: 1)
    refute cache.stats[:grid_shape_scan_complete]
    [[1, 1, 1], [3, 2, 1], [1, 1, 1]].each do |scale|
      assert_equal P.solve(parent, scale, @library, **options), cache.solve(scale, @library)
      assert_operator cache.stats[:entries], :<=, 1
    end
    assert_equal 3, cache.stats[:misses]
  end

  def test_invalid_prices_and_limits_fail_closed
    [{entries: 0}, {grid_scan_limit: 0}, {max_states: -1}, {grid_side: 5}, {grids: 1}].each do |options|
      assert_raises(RuntimeError) { P::ContextCache.new(@parent, **options) }
    end
    cache = P::ContextCache.new(@parent)
    [[], [0, 1, 1], [1.0, 1, 1], [17, 1, 1]].each do |scale|
      assert_raises(RuntimeError) { cache.solve(scale, @library) }
    end
    [0, -1, 1.5].each do |rank|
      library = Prices.new(@library)
      library.override[[1, 1, 1]] = rank
      assert_raises(RuntimeError) { cache.solve([1, 1, 1], library) }
    end
  end
end
