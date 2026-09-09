require 'minitest/autorun'
require_relative '../tools/bud_span_bridges'
require_relative '../tools/bud_packings'

class BudGridAlignmentTest < Minitest::Test
  M=MetaflipBudSpanBridges; B=MetaflipBudProducts; P=MetaflipBudPackings

  def tensor(terms)
    out=Hash.new(0)
    terms.each do |u,v,w|
      MetaflipTensorVerifier.bit_positions(u).product(MetaflipTensorVerifier.bit_positions(v)).each{|i,j|out[[i,j]]^=w}
    end
    out.reject{|_,v|v.zero?}
  end

  def hidden
    [[1,1,1],[1,2,2],[2,3,4],[2,2,8]]
  end

  def test_two_vectors_exposed_by_exact_reversible_words
    terms=hidden; original=Marshal.load(Marshal.dump(terms)); rows=[]
    assert_equal 0,P.grid_groups(Struct.new(:terms).new(terms)).count
    stats=M.each_grid_alignment(terms){|r|rows<<r}
    assert_empty stats[:cutoffs]
    assert_equal rows.size,stats[:emitted]
    assert_operator rows.size,:>,0
    assert_equal rows.size,rows.map{|r|r[:terms]}.uniq.size
    rows.each do |r|
      assert_equal tensor(terms),tensor(r[:terms])
      assert_equal r[:terms],M.replay(terms,r[:word])
      raw=M.replay(terms,r[:word],normalize:false)
      assert_equal terms,M.replay(raw,r[:word].reverse,normalize:false)
      assert_operator r[:terms].size,:<=,terms.size
      probe=Struct.new(:terms).new(r[:terms])
      assert_operator P.grid_groups(probe).count,:>,0
    end
    assert_equal original,terms
  end

  def test_random_exactness_dependencies_and_nonmutation
    rng=Random.new(940927)
    40.times do
      terms=Array.new(rng.rand(4..12)){[rng.rand(1..3),rng.rand(1..7),rng.rand(1..31)]}
      before=Marshal.load(Marshal.dump(terms))
      rows=M.each_grid_alignment(terms,max_candidates:16).to_a
      rows.each do |r|
        assert_equal tensor(terms),tensor(r[:terms])
        assert_equal r[:terms],M.replay(terms,r[:word])
        raw=M.replay(terms,r[:word],normalize:false)
        assert_equal terms,M.replay(raw,r[:word].reverse,normalize:false)
      end
      assert_equal before,terms
    end
  end

  def test_full_matmul_admission_and_deliberate_corruption
    base=B.naive([2,2,3])
    ids=base.terms.each_index.group_by{|i|base.terms[i][0]}.values.first
    scrambled=M.replay(base.terms,[[0,1,ids[0],ids[1]]],normalize:false)
    rows=M.each_grid_alignment(scrambled,max_candidates:64).to_a
    assert_operator rows.size,:>,0
    rows.each{|r|assert B::Scheme.new(base.shape,B.text(r[:terms])).audit[:exact]}
    bad=rows.first[:terms].map(&:dup);bad[0][0]^=1
    assert_raises(RuntimeError){B::Scheme.new(base.shape,B.text(bad))}
  end

  def test_explicit_work_bounds_and_determinism
    rows=[];stats=M.each_grid_alignment(hidden,max_candidates:1){|r|rows<<r}
    assert_equal 1,rows.size
    assert_equal ['candidates'],stats[:cutoffs]
    assert_equal rows,M.each_grid_alignment(hidden,max_candidates:1).to_a
    stats=M.each_grid_alignment(hidden,max_pairs:1){|_|}
    assert_equal 1,stats[:examined_pairs]
    assert_includes stats[:cutoffs],'pairs'
    refute stats[:exhaustive]
    stats=M.each_grid_alignment(hidden,max_alignments:1){|_|}
    assert_equal 1,stats[:alignment_attempts]
    assert_equal ['alignments'],stats[:cutoffs]
    assert_empty M.each_grid_alignment([[1,1,1],[2,2,2]]).to_a
    {max_group:1,max_vectors:2,max_pivots:0,max_pairs:0,max_alignments:0,max_candidates:0}.each do |k,v|
      assert_raises(RuntimeError){M.each_grid_alignment(hidden,**{k=>v}).to_a}
    end
    assert_raises(RuntimeError){M.each_grid_alignment([[0,1,1]]).to_a}
    assert_raises(RuntimeError){M.each_grid_alignment([[1<<257,1,1]]).to_a}
  end
end
