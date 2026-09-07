require 'minitest/autorun'
require_relative '../tools/packing_price_memo'

class PackingPriceMemoTest < Minitest::Test
  B=MetaflipBudProducts
  P=MetaflipBudPackings
  def setup
    path=File.expand_path('../lib/metaflip/seeds/gf2',__dir__)
    @library=B::Library.new(%w[matmul_2x2_rank7_strassen_gf2.txt matmul_3x3x4_rank29_gf2.txt
      matmul_3x4x6_rank54_catalog_gf2.txt].map{|f|B.load_scheme(File.join(path,f))})
    rows=B.naive([2,2,3]).terms.map(&:dup)
    rows[6][1]^=rows[9][1];rows[9][0]^=rows[6][0]
    @parent=B::Scheme.new([2,2,3],B.text(rows))
  end

  def test_all_small_scales_match_uncached_solve_with_and_without_grids
    [false,true].each do |grids|
      options={max_leaf:8,grids:grids,grid_side:3}
      memo=P::PriceMemo.new(@parent,**options)
      scales=(1..4).to_a.repeated_permutation(3).to_a
      (scales+scales.reverse).each do |scale|
        assert_equal P.solve(@parent,scale,@library,**options),memo.solve(scale,@library)
      end
      assert_operator memo.hits,:>,0
      assert_equal scales.size*2,memo.requests
    end
  end

  def test_proportional_prices_reuse_partition_but_reprice_exactly
    # Synthetic cost-table scaling tests only the arithmetic cache, not rank
    # admission. The unscaled witness also passes full tensor construction.
    memo=P::PriceMemo.new(@parent)
    original=memo.solve([3,4,3],@library)
    base=@library;scaled=Object.new
    scaled.define_singleton_method(:rank){|s|2*base.rank(s)}
    result=memo.solve([3,4,3],scaled)
    assert_equal 1,memo.hits
    assert_equal P.solve(@parent,[3,4,3],scaled),result
    assert_equal 2*original[:formula_rank],result[:formula_rank]
    groups=original[:groups]
    leaves=groups.map{|g|@library.scheme(B.group_leaf_shape([3,4,3],g))}
    product=B.compose(@parent,[3,4,3],groups,leaves)
    assert product.audit[:exact]
    assert_equal 324,product.rank
  end

  def test_price_changes_miss_and_returned_groups_cannot_poison_memo
    memo=P::PriceMemo.new(@parent)
    expected=P.solve(@parent,[3,4,3],@library)
    result=memo.solve([3,4,3],@library)
    result[:groups][0][:indices][0]=12345
    assert_equal expected,memo.solve([3,4,3],@library)
    base=@library;changed=Object.new
    changed.define_singleton_method(:rank){|s|s.sort==[3,3,4] ? 1 : base.rank(s)}
    assert_equal P.solve(@parent,[3,4,3],changed),memo.solve([3,4,3],changed)
    assert_equal 2,memo.misses
    assert_equal 1,memo.hits
  end

  def test_limits_capacity_and_parent_identity_remain_distinct
    memo=P::PriceMemo.new(@parent,max_entries:1,max_states:1)
    [[3,4,3],[1,1,1],[3,4,3]].each do |s|
      assert_equal P.solve(@parent,s,@library,max_states:1),memo.solve(s,@library)
    end
    assert_equal 1,memo.stats[:entries]
    refute memo.solve([3,4,3],@library)[:exact_within_model]
    other=P::PriceMemo.new(B.naive([2,2,3]))
    assert_equal P.solve(B.naive([2,2,3]),[3,4,3],@library),other.solve([3,4,3],@library)
    assert_equal 0,other.hits
  end

  def test_invalid_inputs_and_no_shared_factor_fast_path
    assert_raises(RuntimeError){P::PriceMemo.new(Object.new)}
    assert_raises(RuntimeError){P::PriceMemo.new(@parent,max_entries:0)}
    assert_raises(RuntimeError){P::PriceMemo.new(@parent,max_states:0)}
    assert_raises(RuntimeError){P::PriceMemo.new(@parent,typo:1)}
    memo=P::PriceMemo.new(@parent)
    assert_raises(RuntimeError){memo.solve([0,1,1],@library)}
    bad=Object.new;bad.define_singleton_method(:rank){|s|0}
    assert_raises(RuntimeError){memo.solve([3,4,3],bad)}
    path=File.expand_path('../lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt',__dir__)
    parent=B.load_scheme(path);empty=P::PriceMemo.new(parent)
    [[2,2,2],[2,3,4],[4,4,4]].each do |s|
      assert_equal P.solve(parent,s,@library),empty.solve(s,@library)
    end
    assert_equal 2,empty.hits
    with_grids=P::PriceMemo.new(parent,grids:true,grid_side:4)
    [[2,2,2],[2,3,4],[4,4,4]].each do |s|
      assert_equal P.solve(parent,s,@library,grids:true,grid_side:4),with_grids.solve(s,@library)
    end
    assert with_grids.stats[:grid_inventory][:complete]
    assert_equal 0,with_grids.stats[:grid_inventory][:shapes]
    assert_equal 2,with_grids.hits
  end

  def test_incomplete_grid_inventory_does_not_drop_unknown_shapes
    parent=B.naive([2,2,3]);memo=P::PriceMemo.new(parent,grids:true,grid_side:4,max_candidates:1)
    refute memo.stats[:grid_inventory][:complete]
    [[2,2,1],[3,4,3],[2,2,1]].each do |s|
      assert_equal P.solve(parent,s,@library,grids:true,grid_side:4,max_candidates:1),memo.solve(s,@library)
    end
  end

  def test_random_arithmetic_profiles_and_proportional_shifts_match_full_solver
    # Cost-oracle property test, not a source of admitted tensor ranks.
    random=Random.new(782341);scale=[2,2,2];parent=B.naive([2,2,3])
    [3,50_000].each do |limit|
      options={max_leaf:8,grids:true,grid_side:3,max_states:limit}
      memo=P::PriceMemo.new(parent,**options)
      8.times do
        prices=(1..8).to_a.repeated_combination(3).to_h{|s|[s,random.rand(1..s.inject(:*)+7)]}
        base=nil
        [[1,0],[2,3],[3,1]].each do |a,b|
          library=Object.new
          library.define_singleton_method(:rank){|s|a*prices.fetch(s.sort)+b*(s.inject(:*)/8)}
          expected=P.solve(parent,scale,library,**options)
          value=memo.solve(scale,library)
          assert_equal expected,value
          base ||= value[:formula_rank]
          assert_equal a*base+b*parent.rank,value[:formula_rank]
        end
      end
      assert_operator memo.hits,:>=,16
    end
  end
end
