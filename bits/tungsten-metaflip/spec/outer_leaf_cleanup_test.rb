require "minitest/autorun"
require_relative "../tools/outer_leaf_portfolio"

class OuterLeafCleanupTest < Minitest::Test
  B = MetaflipBudProducts
  M = MetaflipOuterBasisProducts
  P = MetaflipOuterLeafPortfolio

  def setup
    @parent = B.naive([1,1,1])
    @allocation = [[2],[2],[2]]
    @s = B.load_scheme(File.expand_path("../lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt",__dir__))
    @dense = M.transvection(@s,0,0,1)
  end

  def with_pool(leaves)
    pool = leaves.map{|leaf|{leaf:leaf,terms:leaf.terms.to_set}}
    with_pools([[pool],leaves,leaves.length]){yield}
  end

  def with_pools(value)
    original = P.method(:leaf_pools)
    P.define_singleton_method(:leaf_pools){|*args|value}
    yield
  ensure
    P.define_singleton_method(:leaf_pools,original)
  end

  def run_search(leaf=@dense, **options)
    P.optimize_cleaned(@parent,@allocation,leaves:[leaf],seeds:{},cleanup:->(s){s},**options)
  end

  def test_rejects_raw_score_improvement_that_worsens_cleaned_objective
    cleaner = ->(raw){raw.canonical_id == @dense.canonical_id ? @s : @dense}
    with_pool([@dense,@s]) do
      raw = P.optimize(@parent,@allocation,leaves:[@dense],seeds:{},rounds:1)
      assert_operator raw[:density],:<,@dense.audit[:density]
      assert_operator cleaner.call(raw[:result]).audit[:density],:>,cleaner.call(@dense).audit[:density]
      result = run_search(cleanup:cleaner,rounds:1)
      assert_equal @s.canonical_id,result[:result].canonical_id
      assert_equal @dense.canonical_id,result[:leaves].first.canonical_id
      assert_empty result[:history]
      assert_equal 2,result[:assessments].length
      # Even an unhelpful cleanup output is retained, not mistaken for a gain.
      assert_equal @dense.canonical_id,result[:assessments].last[:cleaned].canonical_id
    end
  end

  def test_raw_worsening_move_can_win_after_exact_cleanup
    very_dense = M.transvection(@dense,1,0,1)
    assert_operator very_dense.audit[:density],:>,@dense.audit[:density]
    cleaner = ->(raw){raw.canonical_id == very_dense.canonical_id ? @s : raw}
    with_pool([@dense,very_dense]) do
      result = run_search(cleanup:cleaner,rounds:1)
      assert_equal @s.canonical_id,result[:result].canonical_id
      assert_equal very_dense.canonical_id,result[:raw].canonical_id
      assert_equal very_dense.canonical_id,result[:leaves].first.canonical_id
      assert_equal 1,result[:history].length
      assert_operator result[:density],:<,result[:initial_density]
    end
  end

  def test_cache_preserves_distinct_leaf_states_with_the_same_raw_tensor
    triple = B::Scheme.new([1,1,1],B.text([[1,1,1]]*3))
    pool = [@dense,@s].map{|leaf|{leaf:leaf,terms:leaf.terms.to_set}}
    calls = 0
    with_pools([[pool,pool,pool],[@dense,@s],2]) do
      result = P.optimize_cleaned(triple,@allocation,leaves:[@dense]*3,seeds:{},rounds:1,
        cleanup:->(s){calls+=1;s})
      assert_equal 4,result[:assessment_count]
      assert_equal 2,result[:cleanup_calls]
      assert_equal 2,calls
      assert_equal 2,result[:assessments].count{|a|a[:cached]}
      states = result[:assessments].drop(1).map{|a|a[:leaves].map(&:canonical_id)}
      assert_equal 3,states.uniq.length
      assert result[:assessments].all?{|a|a[:result].audit[:exact]}
    end
  end

  def test_budget_includes_baseline_and_never_claims_a_partial_shortlist_is_exhaustive
    baseline = run_search(assessment_limit:1)
    assert_equal 1,baseline[:assessment_count]
    assert_equal 0,baseline[:checks]
    assert_equal :assessment_limit,baseline[:stop_reason]
    bounded = run_search(rounds:2,assessment_limit:2,shortlist:16)
    assert_equal 2,bounded[:assessment_count]
    assert_operator bounded[:unassessed_proposals],:>,0
    assert_equal :assessment_limit,bounded[:stop_reason]
    narrow = run_search(@s,shortlist:1,rounds:2)
    assert_equal :no_shortlisted_improvement,narrow[:stop_reason]
    assert_operator narrow[:unassessed_proposals],:>,0
    assert_equal 1,narrow[:round_audits].first[:evaluated]
  end

  def test_all_assessments_and_final_recipe_are_exact_and_deterministic
    allocation = [[1,2],[2,1],[1,2]]
    _,_,leaves = M.compose(@s,allocation,library:B::Library.new([@s]))
    args = {leaves:leaves,seeds:{[2,2,2]=>[@s]},cleanup:->(s){s},rounds:2,
      shortlist:8,assessment_limit:17,pair_width:4}
    a = P.optimize_cleaned(@s,allocation,**args)
    b = P.optimize_cleaned(@s,allocation,**args)
    assert_equal a[:history],b[:history]
    assert_equal a[:round_audits],b[:round_audits]
    assert_equal a[:checks],b[:checks]
    assert_equal a[:result].canonical_id,b[:result].canonical_id
    assert_operator a[:pair_checks],:>,0
    assert_operator a[:assessment_count],:<=,17
    a[:assessments].each do |entry|
      raw, = M.compose(@s,allocation,leaves:entry[:leaves])
      assert_equal raw.canonical_id,entry[:raw].canonical_id
      assert entry[:result].audit[:exact]
    end
    costs = [[a[:initial_rank],a[:initial_density]]]+a[:history].map{|r|r.values_at(:rank,:density)}
    assert costs.each_cons(2).all?{|left,right|(right<=>left)==-1}
    assert_equal a[:raw].canonical_id,M.compose(@s,allocation,leaves:a[:leaves]).first.canonical_id
  end

  def test_callback_cannot_supply_a_score_wrong_shape_or_forged_tensor
    [->(_){7},->(_){@parent}].each do |cleanup|
      assert_raises(RuntimeError){run_search(cleanup:cleanup)}
    end
    forged = B::Scheme.new(@s.shape,@s.source_text)
    forged.instance_variable_set(:@terms,[[1,1,1]])
    assert forged.audit[:exact] # Forged metadata must never bypass the check.
    assert_raises(RuntimeError){run_search(cleanup:->(_){forged})}
    assert_raises(FrozenError){run_search(cleanup:->(raw){raw.instance_variable_set(:@terms,[[1,1,1]]);raw})}
    assert_raises(RuntimeError){run_search(cleanup:->(_){raise "limited cleanup"})}
  end

  def test_invalid_limits_fail_before_cleanup
    [{assessment_limit:0},{assessment_limit:4097},{shortlist:0},{shortlist:257},
     {rounds:0},{pair_width:33},{seed_limit:0},{cleanup:nil}].each do |invalid|
      assert_raises(RuntimeError){run_search(**invalid)}
    end
  end
end
