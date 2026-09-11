require "minitest/autorun"
require "tmpdir"
require_relative "../tools/outer_basis_products"

class OuterWidthFrontierTest < Minitest::Test
  B = MetaflipBudProducts
  M = MetaflipOuterBasisProducts

  def setup
    @parent = B.load_scheme(File.expand_path("../lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt",__dir__))
    @images = [{parent:@parent},{parent:B.naive([1,2,1])}]
    @library = B::Library.new([@parent])
  end

  def test_complete_census_matches_direct_composer_prices_and_top_k
    expected = []
    @images.each_with_index do |e,index|
      parent = e[:parent]
      axes = parent.shape.map { |n| [1,2].repeated_permutation(n).to_a }
      axes[0].product(axes[1],axes[2]).each do |allocation|
        next unless allocation.flatten.include?(2)
        price = M.leaf_shapes(parent,allocation).sum { |s| @library.rank(s) }
        expected << {index:expected.length,parent_index:index,allocation:allocation,target:allocation.map(&:sum),formula_rank:price}
      end
    end
    actual = []
    result = M.width_frontier(@images,@library,widths:[2,1],required_width:2) { |r| actual << r }
    assert result[:complete]
    assert_equal 80,result[:visited_allocations]
    assert_equal 78,result[:scored]
    assert_equal expected,actual
    groups = expected.group_by { |r| r[:target].sort }.sort.map do |shape,rs|
      candidates = rs.map { |r| [r[:formula_rank],r[:parent_index],r[:allocation]] }.sort.first(2)
      {shape:shape,formula_min:candidates.first[0],candidates:candidates}
    end
    assert_equal groups,result[:targets]
  end

  def test_budget_counts_filtered_work_and_never_claims_a_partial_census_complete
    [0,1,2,63,64,65].each do |limit|
      rows = []
      r = M.width_frontier([@images.first],@library,widths:[1,2],required_width:2,context_limit:limit) { |x| rows << x }
      assert_equal [64,limit].min,r[:visited_allocations]
      assert_equal limit >= 64,r[:complete]
      assert_equal 64,r[:expected_allocations]
      assert_equal 63,r[:expected_contexts]
      assert_equal [0,[64,limit].min-1].max,r[:scored]
      assert_equal r[:scored],rows.length
    end
  end

  def test_optional_filter_and_duplicate_rank_ties_preserve_parent_identity
    r = M.width_frontier([@images.first,@images.first],@library,widths:[2],per_target:2)
    assert r[:complete]
    assert_equal 2,r[:scored]
    assert_equal 2,r[:expected_contexts]
    assert_equal [0,1],r[:targets].first[:candidates].map { |c| c[1] }
    assert_equal 49,r[:targets].first[:formula_min]
  end

  def test_shortlist_materializes_and_exports_through_existing_exact_boundary
    r = M.width_frontier([@images.first],@library,widths:[1,2],required_width:2)
    Dir.mktmpdir do |root|
      r[:targets].each_with_index do |target,index|
        out = M.materialize([@images.first],target[:candidates],@library,verification: :all)
        winner = out[:winner]
        assert winner[:result].audit[:exact]
        assert_equal target[:shape],winner[:result].shape.sort
        dir = File.join(root,index.to_s);Dir.mkdir(dir)
        result,path = M.export(dir,winner[:parent],winner[:allocation],winner[:leaves],target[:shape])
        assert M.replay(path)[:exact]
        assert_equal winner[:result].rank,result.rank
      end
    end
  end

  def test_bad_rank_is_not_a_candidate
    [-1,0,1.5,nil].each do |value|
      library = Object.new
      library.define_singleton_method(:rank) { |_| value }
      assert_raises(RuntimeError) { M.width_frontier([@images.first],library,widths:[1]) }
    end
    library = Object.new
    library.define_singleton_method(:rank) { |_| 1 }
    library.define_singleton_method(:scheme) { |shape| B.naive(shape) }
    r = M.width_frontier([@images.first],library,widths:[2])
    assert_raises(RuntimeError) { M.materialize([@images.first],r[:targets].first[:candidates],library) }
  end

  def test_invalid_parameters_fail_closed
    [{widths:[]},{widths:[1,1]},{widths:[0,1]},{widths:[17]},
     {required_width:2,widths:[1]},{required_width:2.0,widths:[2]},{per_target:0},{context_limit:-1}].each do |options|
      assert_raises(RuntimeError) { M.width_frontier(@images,@library,**options) }
    end
    assert_raises(RuntimeError) { M.width_frontier([],@library) }
    assert_raises(RuntimeError) { M.width_frontier([{parent:nil}],@library) }
  end
end
