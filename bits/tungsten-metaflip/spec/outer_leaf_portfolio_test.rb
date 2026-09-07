require "minitest/autorun"
require_relative "../tools/outer_leaf_portfolio"

class OuterLeafPortfolioTest < Minitest::Test
  B = MetaflipBudProducts
  M = MetaflipOuterBasisProducts
  P = MetaflipOuterLeafPortfolio

  def setup
    @parent = B.load_scheme(File.expand_path("../lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt",__dir__))
  end

  def test_every_axis_and_index_permutation_is_exact_and_invertible
    [@parent,B.naive([2,3,4])].each do |s|
      [0,1,2].permutation.each do |p|
        image = P.permute_axes(s,p)
        assert image.audit[:exact]
        assert_equal p.map{|i|s.shape[i]},image.shape
        inverse = (0...3).map{|i|p.index(i)}
        assert_equal s.terms,P.permute_axes(image,inverse).terms
      end
      maps = s.shape.map{|n|(0...n).to_a.reverse}
      image = P.permute_indices(s,maps)
      assert image.audit[:exact]
      assert_equal s.terms,P.permute_indices(image,maps).terms
    end
    assert_raises(RuntimeError){P.permute_axes(@parent,[0,0,2])}
    assert_raises(RuntimeError){P.permute_indices(@parent,[[0,0],[0,1],[0,1]])}
  end

  def test_variants_are_deduplicated_actual_tensor_witnesses
    images = P.variants(@parent,[2,2,2])
    assert_equal images.length,images.map(&:canonical_id).uniq.length
    assert_operator images.length,:>,1
    assert images.all?{|s|s.audit[:exact] && s.rank == 7 && s.shape == [2,2,2]}
    assert_raises(RuntimeError){P.variants(@parent,[2,2,3])}
  end

  def test_incremental_parity_exactly_matches_composer_including_zero_extents
    [[[1,2],[2,1],[1,2]],[[0,2],[1,1],[2,0]]].each do |allocation|
      result,_,leaves = M.compose(@parent,allocation,library:B::Library.new([@parent]))
      contributions = leaves.each_with_index.map{|leaf,i|P.mapped_terms(@parent,i,allocation,leaf)}
      assert_equal result.terms.to_set,contributions.reduce(Set.new){|p,t|p^t}
    end
  end

  def test_bounded_search_never_worsens_rank_density_and_exactly_replays
    allocation = [[1,2],[2,1],[1,2]]
    initial,_,leaves = M.compose(@parent,allocation,library:B::Library.new([@parent]))
    result = P.optimize(@parent,allocation,leaves:leaves,seeds:{[2,2,2]=>[@parent]},seed_limit:2,rounds:3)
    assert result[:result].audit[:exact]
    assert_operator ([result[:rank],result[:density]] <=> [initial.rank,initial.audit[:density]]),:<=,0
    assert_operator result[:checks],:>,0
    assert_operator result[:verified_variants],:>,0
    assert_operator result[:rounds],:<=,3
    assert_equal result[:result].terms,M.compose(@parent,allocation,leaves:result[:leaves]).first.terms
    pairs = [[initial.rank,initial.audit[:density]]]+result[:history].map{|r|r.values_at(:rank,:density)}
    assert pairs.each_cons(2).all?{|a,b|(b<=>a)==-1}
    paired = P.optimize(@parent,allocation,leaves:leaves,seeds:{[2,2,2]=>[@parent]},seed_limit:2,rounds:3,pair_width:4)
    assert paired[:result].audit[:exact]
    assert_operator paired[:pair_checks],:>,0
    assert_operator ([paired[:rank],paired[:density]] <=> [result[:rank],result[:density]]),:<=,0
    assert_raises(RuntimeError){P.optimize(@parent,allocation,leaves:leaves,seeds:{},rounds:0)}
    assert_raises(RuntimeError){P.optimize(@parent,allocation,leaves:leaves,seeds:{},pair_width:-1)}
  end

  def test_shear_walk_is_monotone_and_history_reconstructs_the_same_leaves
    allocation = [[1,2],[2,1],[1,2]]
    initial,_,leaves = M.compose(@parent,allocation,library:B::Library.new([@parent]))
    result = P.shear_walk(@parent,allocation,leaves:leaves,rounds:2)
    assert result[:result].audit[:exact]
    assert_operator result[:checks],:>,0
    assert_operator ([result[:rank],result[:density]] <=> [initial.rank,initial.audit[:density]]),:<=,0
    replay = leaves.dup
    result[:history].each do |step|
      slot = step[:slot]
      assert_equal step[:from],replay[slot].canonical_id
      replay[slot] = M.transvection(replay[slot],*step.values_at(:axis,:dst,:src))
      assert_equal step[:to],replay[slot].canonical_id
    end
    assert_equal result[:result].terms,M.compose(@parent,allocation,leaves:replay).first.terms
    assert_raises(RuntimeError){P.shear_walk(@parent,allocation,leaves:leaves,rounds:0)}
  end

  def test_basis_neighbors_cover_every_elementary_shear_and_swap
    leaf = B.naive([2,3,4])
    neighbors = P.basis_neighbors(leaf).to_a
    directed = leaf.shape.sum{|n|n*(n-1)}
    assert_equal directed*3/2,neighbors.length
    assert_equal directed,neighbors.count{|_,a|a[:kind]=="shear"}
    assert_equal directed/2,neighbors.count{|_,a|a[:kind]=="swap"}
    neighbors.each do |image,action|
      assert image.audit[:exact]
      assert_equal leaf.rank,image.rank
      if action[:kind] == "swap"
        maps = leaf.shape.map{|n|(0...n).to_a}
        axis,dst,src = action.values_at(:axis,:dst,:src)
        maps[axis][dst],maps[axis][src] = src,dst
        assert_equal leaf.terms,P.permute_indices(image,maps).terms
      end
    end
    assert_raises(RuntimeError){P.basis_neighbors(leaf,moves: :invalid)}
  end

  def test_mixed_walk_replays_each_action_and_stops_when_neighborhood_is_stationary
    allocation = [[1,2],[2,1],[1,2]]
    _,_,leaves = M.compose(@parent,allocation,library:B::Library.new([@parent]))
    result = P.basis_walk(@parent,allocation,leaves:leaves,rounds:2)
    replay = leaves.dup
    result[:history].each do |step|
      slot = step[:slot]
      assert_equal step[:from],replay[slot].canonical_id
      if step[:kind] == "shear"
        replay[slot] = M.transvection(replay[slot],*step.values_at(:axis,:dst,:src))
      else
        assert_equal "swap",step[:kind]
        axis,dst,src = step.values_at(:axis,:dst,:src)
        maps = replay[slot].shape.map{|n|(0...n).to_a}
        maps[axis][dst],maps[axis][src] = src,dst
        replay[slot] = P.permute_indices(replay[slot],maps)
      end
      assert_equal step[:to],replay[slot].canonical_id
    end
    assert_equal result[:result].terms,M.compose(@parent,allocation,leaves:replay).first.terms
    singleton = B.naive([1,1,1])
    leaf = B.naive([3,3,3])
    stationary = P.basis_walk(singleton,[[3],[3],[3]],leaves:[leaf],rounds:2)
    assert_equal 27,stationary[:checks]
    assert_equal 1,stationary[:rounds]
    assert stationary[:settled]
    assert_empty stationary[:history]
    assert_raises(RuntimeError){P.basis_walk(@parent,allocation,leaves:leaves,moves: :invalid)}
  end

  def test_kernel_words_send_every_small_nonzero_vector_to_deleted_coordinate
    (2..5).each do |n|
      3.times do |axis|
        1.upto((1<<n)-1) do |vector|
          word = P.eliminate_vector_word(n,axis,vector,n-1)
          image = word.reduce(vector){|v,(_,dst,src)|M.shear(v,n,1,0,dst,src)}
          assert_equal 1<<(n-1),image
        end
      end
    end
    assert_raises(RuntimeError){P.eliminate_vector_word(3,0,0,2)}
    assert_raises(RuntimeError){P.eliminate_vector_word(3,0,8,2)}
  end

  def test_kernel_walk_is_exact_and_its_long_word_history_replays
    allocation = [[1,2],[2,1],[1,2]]
    initial,_,leaves = M.compose(@parent,allocation,library:B::Library.new([@parent]))
    result = P.basis_walk(@parent,allocation,leaves:leaves,rounds:2,moves: :kernel)
    assert result[:result].audit[:exact]
    assert_operator ([result[:rank],result[:density]] <=> [initial.rank,initial.audit[:density]]),:<=,0
    assert_operator result[:checks],:>,0
    replay = leaves.dup
    result[:history].each do |step|
      assert_equal "kernel",step[:kind]
      slot = step[:slot]
      assert_equal step[:from],replay[slot].canonical_id
      replay[slot] = M.transvection_word(replay[slot],step[:word])
      assert_equal step[:to],replay[slot].canonical_id
    end
    assert_equal result[:result].terms,M.compose(@parent,allocation,leaves:replay).first.terms
    assert_raises(RuntimeError){P.basis_walk(@parent,allocation,leaves:leaves,moves: :kernel,kernel_maximum:11)}
  end

  def test_screened_kernel_policy_has_identical_moves_and_exact_admission
    [[[1,2],[2,1],[1,2]],[[2,1],[1,2],[2,1]],[[0,2],[1,1],[2,0]]].each do |allocation|
      _,_,leaves = M.compose(@parent,allocation,library:B::Library.new([@parent]))
      all = P.basis_walk(@parent,allocation,leaves:leaves,rounds:3,moves: :kernel)
      winner = P.basis_walk(@parent,allocation,leaves:leaves,rounds:3,moves: :kernel,verification: :winner)
      assert_equal all[:history],winner[:history]
      assert_equal all[:checks],winner[:checks]
      assert_equal all[:result].terms,winner[:result].terms
      assert winner[:result].audit[:exact]
      assert_equal all[:checks],all[:verified_neighbors]
      assert_equal winner[:history].length,winner[:verified_neighbors]
      assert_equal :winner,winner[:verification]
    end
    allocation = [[1,2],[2,1],[1,2]]
    _,_,leaves = M.compose(@parent,allocation,library:B::Library.new([@parent]))
    assert_raises(RuntimeError){P.basis_walk(@parent,allocation,leaves:leaves,verification: :winner,moves: :both)}
    assert_raises(RuntimeError){P.basis_walk(@parent,allocation,leaves:leaves,verification: :none,moves: :kernel)}
  end

  def test_screened_kernel_policy_rejects_a_corrupt_selected_leaf
    allocation = [[1,2],[2,1],[1,2]]
    _,_,leaves = M.compose(@parent,allocation,library:B::Library.new([@parent]))
    original = P.method(:truncation_proposals)
    fake = lambda do |*args,**kwargs|
      Enumerator.new{|out|out.yield([[0,0,0]],{kind:"kernel",axis:0,vector:1,deleted:0,dual:false,word:[]})}
    end
    begin
      P.define_singleton_method(:truncation_proposals,fake)
      assert_raises(RuntimeError){P.basis_walk(@parent,allocation,leaves:leaves,moves: :kernel,verification: :winner)}
    ensure
      P.define_singleton_method(:truncation_proposals,original)
    end
  end

  def test_kernel_pairs_are_exact_complete_words_with_canonical_deduplication
    allocation = [[1,2],[2,1],[1,2]]
    _,_,leaves = M.compose(@parent,allocation,library:B::Library.new([@parent]))
    slot = leaves.index{|leaf|leaf && leaf.shape == [2,2,2]}
    leaf = leaves.fetch(slot)
    pools = Array.new(3){[]}
    P.truncation_proposals(@parent,slot,allocation,leaf).each{|_,a|pools[a[:axis]] << a}
    pairs = P.kernel_pair_proposals(leaf,pools).to_a
    assert_operator pairs.length,:>,0
    identities = []
    pairs.each do |terms,action|
      assert_equal "kernel_pair",action[:kind]
      assert_equal 2,action[:components].map{|a|a[:axis]}.uniq.length
      assert_equal action[:word],action[:components].flat_map{|a|a[:word]}
      image = B::Scheme.new(leaf.shape,B.text(terms))
      sequential = action[:components].reduce(leaf){|s,a|M.transvection_word(s,a[:word])}
      assert_equal sequential.terms,image.terms
      assert_equal leaf.terms,M.transvection_word(image,action[:word].reverse).terms
      identities << image.canonical_id
    end
    assert_equal identities.uniq,identities
    assert_raises(RuntimeError){P.kernel_pair_proposals(leaf,[[],[]])}
  end

  def test_paired_walk_policies_match_and_every_accepted_move_is_exact
    [[[1,2],[2,1],[1,2]],[[2,1],[1,2],[2,1]],[[0,2],[1,1],[2,0]]].each do |allocation|
      initial,_,leaves = M.compose(@parent,allocation,library:B::Library.new([@parent]))
      all = P.basis_walk(@parent,allocation,leaves:leaves,rounds:3,moves: :kernel,kernel_pair_width:4)
      winner = P.basis_walk(@parent,allocation,leaves:leaves,rounds:3,moves: :kernel,kernel_pair_width:4,verification: :winner)
      assert_operator all[:pair_checks],:>,0
      assert_equal all[:history],winner[:history]
      assert_equal all[:checks],winner[:checks]
      assert_equal all[:pair_checks],winner[:pair_checks]
      assert_equal all[:result].terms,winner[:result].terms
      assert_equal all[:checks],all[:verified_neighbors]
      assert_equal winner[:history].length,winner[:verified_neighbors]
      assert_operator ([winner[:rank],winner[:density]] <=> [initial.rank,initial.audit[:density]]),:<=,0
      current = leaves.dup
      winner[:history].each do |action|
        slot = action[:slot]
        current[slot] = M.transvection_word(current[slot],action[:word])
        state, = M.compose(@parent,allocation,leaves:current)
        assert_equal action.values_at(:rank,:density),[state.rank,state.audit[:density]]
      end
    end
    assert_raises(RuntimeError){P.basis_walk(@parent,[[1,2],[2,1],[1,2]],leaves:[],moves: :kernel,kernel_pair_width:33)}
    assert_raises(RuntimeError){P.basis_walk(@parent,[[1,2],[2,1],[1,2]],leaves:[],moves: :both,kernel_pair_width:1)}
  end

  def test_screened_pair_cannot_admit_a_corrupt_leaf
    allocation = [[1,2],[2,1],[1,2]]
    _,_,leaves = M.compose(@parent,allocation,library:B::Library.new([@parent]))
    original = P.method(:kernel_pair_proposals)
    fake = lambda do |*args,**kwargs,&block|
      block.call([[0,0,0]],{kind:"kernel_pair",word:[],components:[]})
    end
    begin
      P.define_singleton_method(:kernel_pair_proposals,fake)
      assert_raises(RuntimeError){P.basis_walk(@parent,allocation,leaves:leaves,moves: :kernel,
        verification: :winner,kernel_pair_width:4)}
    ensure
      P.define_singleton_method(:kernel_pair_proposals,original)
    end
  end
end
