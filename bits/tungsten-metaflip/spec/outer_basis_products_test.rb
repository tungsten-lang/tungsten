#!/usr/bin/env ruby
require "minitest/autorun"
require "tmpdir"
require_relative "../tools/outer_basis_products"

class OuterBasisProductsTest < Minitest::Test
  B = MetaflipBudProducts
  M = MetaflipOuterBasisProducts
  ROOT = File.expand_path("../lib/metaflip/seeds/gf2", __dir__)

  def setup
    @parent = B.load_scheme(File.join(ROOT,"matmul_2x2_rank7_strassen_gf2.txt"))
    @library = B::Library.new([@parent])
  end

  def test_transvections_are_exact_involutions_on_every_axis
    [@parent,B.naive([2,3,4])].each do |parent|
      3.times do |axis|
        parent.shape[axis].times do |dst|
          parent.shape[axis].times do |src|
            next if dst == src
            image = M.transvection(parent,axis,dst,src)
            assert image.audit[:exact]
            assert_equal parent.rank,image.rank
            assert_equal parent.terms,M.transvection(image,axis,dst,src).terms
          end
        end
      end
    end
    [[-1,0,1],[3,0,1],[0,0,0],[1,2,0],[2,0,-1],[0,0.5,1]].each do |args|
      assert_raises(RuntimeError) { M.transvection(@parent,*args) }
    end
    [[-1,0],[3,0],[0,-1],[0,6],[0,0.5]].each do |args|
      assert_raises(RuntimeError) { M.gl2_image(@parent,*args) }
    end
  end

  def test_gl2_covers_216_codes_and_36_distinct_term_multisets
    images = M.orbit2(@parent)
    assert_equal 36,images.length
    assert_equal 36,images.map { |r| r[:parent].canonical_id }.uniq.length
    assert_equal (0...6).to_a.repeated_permutation(3).to_a.sort,images.flat_map { |r| r[:codes] }.sort
    images.each do |row|
      assert row[:parent].audit[:exact]
      assert_equal 7,row[:parent].rank
    end
    assert_raises(RuntimeError) { M.orbit2(B.naive([2,2,3])) }
  end

  def test_basis_word_matches_successive_moves_and_inverse
    rng = Random.new(20260906)
    [@parent,B.naive([2,3,4])].each do |parent|
      12.times do
        word = Array.new(8) do
          axis = rng.rand(3)
          dst,src = (0...parent.shape[axis]).to_a.sample(2,random:rng)
          [axis,dst,src]
        end
        slow = word.reduce(parent){|s,move|M.transvection(s,*move)}
        fast = M.transvection_word(parent,word)
        assert_equal slow.terms,fast.terms
        assert_equal slow.terms,M.transvection_word_terms(parent,word)
        assert fast.audit[:exact]
        assert_equal parent.terms,M.transvection_word(fast,word.reverse).terms
      end
      assert_equal parent.terms,M.transvection_word(parent,[]).terms
    end
    [nil,[[0,0]],[[3,0,1]],[[0,0,0]],[[0,0,2]],[[0,0,0.5]]].each do |word|
      assert_raises(RuntimeError){M.transvection_word(@parent,word)}
    end
  end

  def test_allocations_match_independent_bounded_enumeration
    (0..9).each do |total|
      (1..3).each do |parts|
        expected = (0..3).to_a.repeated_permutation(parts).select { |row| row.sum == total }
        assert_equal expected,M.allocations(total,parts,minimum:0,maximum:3)
      end
    end
    assert_empty M.allocations(5,0)
    assert_empty M.allocations(5,2,minimum:3,maximum:2)
  end

  def test_naive_block_composition_and_zero_extents
    parent = B.naive([2,2,2])
    [[[1,3],[2,1],[1,2]],[[0,2],[1,0],[0,2]]].each do |allocation|
      product,audit,leaves = M.compose(parent,allocation,library:B::Library.new([]))
      assert_equal B.naive(allocation.map(&:sum)).terms.sort,product.terms.sort
      assert_equal product.rank,audit[:nominal]
      assert_equal 0,audit[:zero_terms]
      assert_equal 0,audit[:parity_reduction]
      assert_equal M.leaf_shapes(parent,allocation).map { |s| s.include?(0) ? nil : s },leaves.map { |l| l&.shape }
    end
    assert_raises(RuntimeError) { M.compose(parent,[[1,1],[1,1],[0,0]],library:@library) }
    assert_raises(RuntimeError) { M.compose(parent,[[1],[1,1],[1,1]],library:@library) }
    assert_raises(RuntimeError) { M.compose(parent,[[1,1],[1,1],[1,1]],leaves:[]) }
    assert_raises(RuntimeError) do
      M.compose(parent,[[1,1],[1,1],[1,1]],leaves:Array.new(8) { @parent })
    end
  end

  def golden
    parent = M.gl2_image(M.gl2_image(@parent,1,1),2,2)
    allocation = [[3,4],[3,4],[4,3]]
    names = %w[matmul_3x3_rank23_d139_gf2.txt matmul_3x3x4_rank29_gf2.txt
               matmul_3x4x4_rank38_gf2.txt matmul_4x4_rank47_d450_gf2.txt]
    library = B::Library.new(names.map { |name| B.load_scheme(File.join(ROOT,name)) })
    [parent,allocation,*M.compose(parent,allocation,library:library)]
  end

  def test_known_seven_cubed_recipe_is_rank_247_not_nominal_248
    _,_,product,audit, = golden
    assert_equal [7,7,7],product.shape
    assert_equal 247,product.rank
    assert_equal 3554,product.audit[:density]
    assert_equal({nominal:248,zero_terms:1,parity_reduction:0},audit)
  end

  def test_parity_cancellation_is_exact
    parent = B::Scheme.new(@parent.shape,B.text(@parent.terms*3))
    product,audit, = M.compose(parent,[[1,1],[1,1],[1,1]],library:@library)
    assert_equal @parent.terms.sort,product.terms.sort
    assert_equal({nominal:21,zero_terms:0,parity_reduction:14},audit)
  end

  def test_export_replay_and_mutated_snapshot_rejection
    parent,allocation,product,_,leaves = golden
    Dir.mktmpdir("outer-basis-replay") do |root|
      output,path = M.export(root,parent,allocation,leaves,[7,7,7])
      assert_equal product.terms,output.terms
      assert_equal product.audit,M.replay(path)
      data = JSON.parse(File.read(path))
      data["exact_rank"] += 1
      File.write(path,JSON.generate(data))
      assert_raises(RuntimeError) { M.replay(path) }
      _,path = M.export(root,parent,allocation,leaves,[7,7,7])
      entry = JSON.parse(File.read(path)).fetch("parent")
      File.open(File.join(root,entry.fetch("path")),"a") { |f| f.puts "# changed" }
      assert_raises(RuntimeError) { M.replay(path) }
      data["parent"]["path"] = "../outside.txt"
      File.write(path,JSON.generate(data))
      assert_raises(RuntimeError) { M.replay(path) }
    end
  end

  def test_small_scan_matches_independent_full_materialization_and_reports_limit
    images = M.orbit2(@parent)
    target = [3,3,3]
    candidates = images.each_with_index.flat_map do |entry,index|
      [[1,2],[2,1]].repeated_permutation(3).map do |allocation|
        product,audit, = M.compose(entry[:parent],allocation,library:@library)
        [[product.rank,audit[:nominal],product.audit[:density],index,allocation],audit[:nominal]]
      end
    end
    result = M.scan(images,target,@library,maximum:2,slack:100,materializations:1000)
    assert_equal 288,result[:scored]
    assert_equal 288,result[:materialized]
    assert result[:complete_competitive]
    assert_equal candidates.map(&:last).min,result[:formula_min]
    assert_equal candidates.map(&:first).min,result[:winner][:key]
    limited = M.scan(images,target,@library,maximum:2,slack:100,materializations:1)
    assert_equal 288,limited[:scored]
    assert_equal 1,limited[:materialized]
    refute limited[:complete_competitive]
    assert limited[:winner][:result].audit[:exact]
    assert_equal result[:formula_min],limited[:formula_min]
    screened = M.scan(images,target,@library,maximum:2,slack:100,materializations:1000,verification: :winner)
    assert_equal result[:histogram],screened[:histogram]
    assert_equal result[:winner][:key],screened[:winner][:key]
    assert_equal result[:winner][:result].terms,screened[:winner][:result].terms
    assert_equal 288,result[:verified_candidates]
    assert_equal 1,screened[:verified_candidates]
    assert screened[:winner][:result].audit[:exact]
    [{maximum:0},{minimum:-1},{slack:-1},{materializations:0},{verification: :off}].each do |bad|
      assert_raises(RuntimeError) { M.scan(images,target,@library,**bad) }
    end
  end

  def test_screened_admission_rejects_a_corrupt_proposal
    original = M.method(:compose_terms)
    corrupt = lambda do |*args,**kwargs|
      terms,audit,leaves = original.call(*args,**kwargs)
      terms = terms.map(&:dup)
      terms[0][2] ^= 1
      [terms,audit,leaves]
    end
    images = [{parent:@parent}]
    candidates = [[7,0,[[1,1],[1,1],[1,1]]]]
    begin
      M.define_singleton_method(:compose_terms,corrupt)
      assert_raises(RuntimeError) { M.materialize(images,candidates,@library,verification: :winner) }
    ensure
      M.define_singleton_method(:compose_terms,original)
    end
  end
end
