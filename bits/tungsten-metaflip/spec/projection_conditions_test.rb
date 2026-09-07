require "minitest/autorun"
require_relative "../tools/projection_conditions"

class ProjectionEnvelopeTest < Minitest::Test
  B = MetaflipBudProducts
  M = MetaflipOuterBasisProducts
  def setup
    @parent = B.load_scheme(File.expand_path("../lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt",__dir__))
  end

  def zeros(parent,allocation,leaf,slot,terms=leaf.terms)
    terms.count do |term|
      B::EDGES.each_with_index.any? do |(r,c),edge|
        M.embed(term[edge],parent.terms[slot][edge],parent.shape[r],parent.shape[c],
          allocation[r],allocation[c],leaf.shape[r],leaf.shape[c]).zero?
      end
    end
  end

  def test_every_small_complementary_pair_compiles_the_prescribed_two_kernels
    (1..4).each do |n|
      1.upto((1<<n)-1) do |u|
        1.upto((1<<n)-1) do |v|
          next unless (u&v).to_s(2).count("1").odd?
          word = MetaflipProjectionClipping.word(n,0,u,v)
          image = word.reduce(u){|bits,(_,d,s)|M.shear(bits,n,1,0,d,s)}
          dual = word.reduce(v){|bits,(_,d,s)|M.shear(bits,n,1,0,s,d)}
          assert_equal 1<<(n-1),image
          assert_equal 1<<(n-1),dual
        end
      end
    end
  end

  def test_envelopes_equal_complete_small_projection_enumeration
    random = Random.new(3193)
    [[2,2,2],[2,3,3],[3,3,3]].each do |shape|
      allocation = shape.map{|n|[n-1,n]}
      parent = M.transvection(@parent,0,0,1)
      shapes = M.leaf_shapes(parent,allocation)
      shapes.each_with_index do |local,slot|
        next unless local == shape
        2.times do
          leaf = Struct.new(:shape,:terms).new(shape,Array.new(9){B::EDGES.map{|r,c|random.rand(1...(1<<(shape[r]*shape[c])))}})
          (0..2).each do |axis|
            result = MetaflipProjectionClipping.envelope(parent,allocation,leaf,slot,axis)
            assert_equal zeros(parent,allocation,leaf,slot),result[:baseline_zero]
            actual = 0
            1.upto((1<<shape[axis])-1) do |u|
              1.upto((1<<shape[axis])-1) do |v|
                next unless (u&v).to_s(2).count("1").odd?
                terms = M.transvection_word_terms(leaf,MetaflipProjectionClipping.word(shape[axis],axis,u,v))
                actual = [actual,zeros(parent,allocation,leaf,slot,terms)].max
              end
            end
            assert_equal actual,result[:maximum_zero]
          end
          (0..2).to_a.combination(2) do |axes|
            result = MetaflipDoubleProjectionClipping.envelope(parent,allocation,leaf,slot,axes)
            assert_equal zeros(parent,allocation,leaf,slot),result[:baseline_zero]
            choices = axes.map do |axis|
              (1...(1<<shape[axis])).flat_map{|u|(1...(1<<shape[axis])).filter_map{|v|[u,v] if (u&v).to_s(2).count("1").odd?}}
            end
            actual = 0
            choices[0].product(choices[1]).each do |left,right|
              word = axes.zip([left,right]).flat_map{|axis,(u,v)|MetaflipProjectionClipping.word(shape[axis],axis,u,v)}
              terms = M.transvection_word_terms(leaf,word)
              actual = [actual,zeros(parent,allocation,leaf,slot,terms)].max
            end
            assert_equal actual,result[:maximum_zero]
          end
        end
      end
    end
  end

  def test_sat_conditions_equal_direct_clipping_for_every_three_axis_gl2_choice
    random = Random.new(6149)
    shape = [2,2,2]
    parent = Struct.new(:shape,:terms).new([2,2,2],[[1,1,1]])
    allocation = [[1,2],[1,2],[1,2]]
    leaf = Struct.new(:shape,:terms).new(shape,Array.new(24){Array.new(3){random.rand(1...16)}})
    conditions = MetaflipProjectionConditions.conditions(parent,allocation,leaf,0,[0,1,2])
    choices = (1...4).flat_map{|u|(1...4).filter_map{|v|[u,v] if (u&v).to_s(2).count("1").odd?}}
    choices.repeated_permutation(3) do |pairs|
      assignment = pairs.each_with_index.flat_map{|(u,v),axis|[[[axis,"u"],u],[[axis,"v"],v]]}.to_h
      word = pairs.each_with_index.flat_map{|(u,v),axis|MetaflipProjectionClipping.word(2,axis,u,v)}
      terms = M.transvection_word_terms(leaf,word)
      assert_equal zeros(parent,allocation,leaf,0,terms),MetaflipProjectionConditions.evaluate(conditions,assignment)
    end
  end

  def test_invalid_domains_are_rejected_before_enumeration
    assert_raises(RuntimeError){MetaflipProjectionClipping.word(0,0,1,1)}
    assert_raises(RuntimeError){MetaflipProjectionClipping.word(3,0,8,1)}
    assert_raises(RuntimeError){MetaflipProjectionClipping.word(3,0,1,2)}
    assert_raises(RuntimeError){MetaflipProjectionClipping.envelope(@parent,[[1,1]]*3,@parent,0,3)}
    assert_raises(RuntimeError){MetaflipDoubleProjectionClipping.envelope(@parent,[[1,1]]*3,@parent,0,[0,0])}
    assert_raises(RuntimeError){MetaflipDoubleProjectionClipping.rank_two_factors(512,3,3)}
    assert_raises(RuntimeError){MetaflipDoubleProjectionClipping.candidate_word([3,3,3],[1,0],[1,1,1,1])}
    assert_raises(RuntimeError){MetaflipProjectionConditions.conditions(@parent,[[1,1]]*3,@parent,0,[0,0])}
    assert_raises(RuntimeError){MetaflipProjectionConditions.conditions(@parent,[[1,1]]*3,@parent,0,[3])}
  end
end
