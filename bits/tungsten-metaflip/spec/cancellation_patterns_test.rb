require "minitest/autorun"
require_relative "../tools/cancellation_patterns"
class ThreeToTwoTest < Minitest::Test
  def test_matrix_factorization_and_invalid_domains
    assert_equal [],MetaflipSharedFactorCompression.factor([[0,1],[1,0]])
    result=MetaflipSharedFactorCompression.factor([[1,1],[2,2],[3,3]])
    assert_equal 2,result.length
    assert_equal signature([[1,1,1],[1,2,2],[1,3,3]]),signature(result.map{|a,b|[1,a,b]})
    assert_raises(RuntimeError){MetaflipSharedFactorCompression.factor([[1,-1]])}
    assert_raises(RuntimeError){MetaflipThreeToTwo.small_term(4,1,1)}
    assert_raises(RuntimeError){MetaflipThreeToTwo.replacement([[1,1,1]])}
    assert_raises(RuntimeError){MetaflipThreeToTwo.scan(Struct.new(:terms).new([[1,1,1],[1,1,2]]))}
  end
  def signature(terms)
    result={}
    terms.each do |t|
      lists=t.map{|v|MetaflipTensorVerifier.bit_positions(v)}
      lists[0].product(lists[1],lists[2]).each{|point|result[point]=!result.fetch(point,false)}
    end
    result.select{|_,odd|odd}.keys.sort
  end
  def test_explicit_wide_compression_keeps_default_domain_and_tensor
    c=MetaflipSharedFactorCompression
    [257,1024,4096].each do |width|
      a=1<<255;b=1<<(width-1)
      terms=[[1,a,a],[1,b,b],[1,a^b,a^b]]
      assert_raises(RuntimeError){c.factor(terms.map{|t|t[1,2]})}
      assert_raises(RuntimeError){c.compress_terms(terms)}
      out,history=c.compress_terms(terms,max_bits:width)
      assert_equal 2,out.length
      assert_equal signature(terms),signature(out)
      assert_equal [{axis:0,fixed:1,before:3,after:2}],history
      again,further=c.compress_terms(out,max_bits:width)
      assert_equal out.sort,again.sort
      assert_empty further
      assert_raises(RuntimeError){c.compress_terms(terms,max_bits:width-1)}
    end
    [0,4097,nil,1.5].each{|width|assert_raises(RuntimeError){c.factor([],max_bits:width)}}
    assert_raises(RuntimeError){c.compress_terms([[1,0,1]],max_bits:1024)}
  end
  def test_neutral_column_basis_moves_preserve_wide_tensor
    c=MetaflipSharedFactorCompression
    rng=Random.new(202609074)
    100.times do
      terms=Array.new(8){Array.new(3){v=rng.rand(1..15);[17,256,512,1000].each_with_index.sum{|j,i|v[i]<<j}}}
      3.times do |axis|
        [false,true].each do |reverse|
          out,_=c.refactor_terms(terms,axis:axis,max_bits:1024,reverse_columns:reverse)
          assert_equal signature(terms),signature(out)
          assert_operator out.size,:<=,terms.size
        end
      end
    end
    terms=[[1,3,1],[1,2,3]]
    out,changed=c.refactor_terms(terms,axis:0,reverse_columns:true)
    refute_equal terms.sort,out.sort
    refute_empty changed
    assert_equal signature(terms),signature(out)
  end
  def test_lookup_replacements_preserve_every_small_three_term_tensor
    terms=(1..3).to_a.repeated_permutation(3).to_a
    terms.combination(3) do |triple|
      replacement=MetaflipThreeToTwo.replacement(triple)
      next unless replacement
      assert_operator replacement.length,:<=,2
      assert_equal signature(triple),signature(replacement)
    end
  end
  def test_plus_inverse_is_found
    terms=[[1,3,1],[3,2,2],[1,2,3]]
    result=MetaflipThreeToTwo.scan(Struct.new(:terms).new(terms))
    refute_nil result[:indices]
    assert_equal signature(terms),signature(result[:replacement])
    assert_equal 2,result[:replacement].length
  end
  def test_candidate_index_matches_bruteforce_after_shared_factor_reduction
    random=Random.new(74581)
    checked=0
    3000.times do
      terms=Array.new(6){Array.new(3){random.rand(1..7)}}.uniq
      reduced=3.times.all? do |axis|
        others=(0..2).to_a-[axis]
        terms.group_by{|t|t[axis]}.values.all? do |group|
          MetaflipSharedFactorCompression.factor(group.map{|t|others.map{|a|t[a]}}).length==group.length
        end
      end
      next unless reduced
      expected=terms.combination(3).any?{|triple|MetaflipThreeToTwo.replacement(triple)}
      result=MetaflipThreeToTwo.scan(Struct.new(:terms).new(terms))
      assert_equal expected,!result[:indices].nil?
      if result[:indices]
        assert_equal signature(result[:indices].map{|i|terms[i]}),signature(result[:replacement])
      end
      checked+=1
      break if checked==300
    end
    assert_equal 300,checked
  end
end
