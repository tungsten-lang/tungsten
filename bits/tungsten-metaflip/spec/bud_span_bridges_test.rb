require 'minitest/autorun'
require_relative '../tools/bud_span_bridges'

class BudSpanBridgesTest < Minitest::Test
  M=MetaflipBudSpanBridges
  B=MetaflipBudProducts

  def span(words)
    (0...(1<<words.size)).map{|m|M.combination(words,m)}.uniq.sort
  end

  def tensor(terms)
    out=Hash.new(0)
    terms.each do |u,v,w|
      MetaflipTensorVerifier.bit_positions(u).product(MetaflipTensorVerifier.bit_positions(v)).each{|i,j|out[[i,j]]^=w}
    end
    out.reject{|_,v|v.zero?}
  end

  def test_intersection_against_exhaustive_spans_including_dependencies
    rng=Random.new(913071)
    300.times do
      left=Array.new(rng.rand(0..6)){rng.rand(0..31)}
      right=Array.new(rng.rand(0..6)){rng.rand(0..31)}
      rows=M.intersection(left,right)
      rows.each do |target,l,r|
        assert_operator target,:>,0
        assert_equal target,M.combination(left,l)
        assert_equal target,M.combination(right,r)
      end
      assert_equal(span(left)&span(right),span(rows.map(&:first)))
      assert_equal 1<<rows.size,span(rows.map(&:first)).size
    end
  end

  def test_hidden_shared_vector_exposes_reversible_exact_cross_group_flips
    terms=[[1,1,1],[1,2,2],[2,3,4],[2,4,8]]
    original=Marshal.load(Marshal.dump(terms))
    rows=M.each_bridge(terms).to_a
    assert_operator rows.size,:>,0
    assert rows.any?{|r|r[:target]==3 && r[:word].size>=2}
    rows.each do |row|
      assert_equal tensor(terms),tensor(row[:terms])
      assert_equal row[:terms],M.replay(terms,row[:word])
      raw=M.replay(terms,row[:word],normalize:false)
      assert_equal terms,M.replay(raw,row[:word].reverse,normalize:false)
      assert_operator row[:terms].size,:<=,terms.size
    end
    assert_equal original,terms
    assert_equal rows.map{|r|r[:terms]}.uniq.size,rows.size
  end

  def test_complete_small_matmul_admission_and_mutation_rejection
    base=B.naive([2,2,3])
    group=base.terms.each_index.group_by{|i|base.terms[i][0]}.values.first
    scrambled=M.replay(base.terms,[[0,1,group[0],group[1]]],normalize:false)
    rows=M.each_bridge(scrambled).to_a
    assert_operator rows.size,:>,0
    rows.each do |row|
      valid=B::Scheme.new(base.shape,B.text(row[:terms]))
      assert_operator valid.rank,:<=,base.rank
    end
    bad=rows.first[:terms].map(&:dup);bad[0][0]^=1
    assert_raises(RuntimeError){B::Scheme.new(base.shape,B.text(bad))}
  end

  def test_invalid_inputs_and_bounded_enumeration
    assert_raises(RuntimeError){M.intersection([1,-2],[1])}
    assert_raises(RuntimeError){M.intersection([1<<257],[1])}
    assert_raises(RuntimeError){M.combination([1],2)}
    assert_raises(RuntimeError){M.replay([[1,1,1],[2,2,2]],[[0,1,0,1]])}
    assert_raises(RuntimeError){M.replay([[1,1,1]],[[0,0,0,0]])}
    assert_raises(RuntimeError){M.each_bridge([[0,1,1]]).to_a}
    assert_raises(RuntimeError){M.each_bridge([[1,1,1]],max_vectors:0).to_a}
    terms=[[1,1,1],[1,2,2],[2,3,4],[2,4,8]]
    assert_empty M.each_bridge(terms,max_group:1).to_a
    rows=M.each_bridge(terms,max_vectors:1,max_pivots:1).to_a
    rows.each{|r|assert_equal tensor(terms),tensor(r[:terms])}
  end
end
