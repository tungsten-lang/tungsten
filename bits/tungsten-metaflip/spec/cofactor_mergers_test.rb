require "minitest/autorun"
require "tmpdir"
require_relative "../tools/cofactor_mergers"

class CofactorMergersTest < Minitest::Test
  C = MetaflipCofactorMergers
  def signature(terms)
    result = Set.new
    terms.each do |t|
      parts = t.map { |v| MetaflipTensorVerifier.bit_positions(v) }
      parts[0].product(parts[1], parts[2]).each { |p| result.include?(p) ? result.delete(p) : result.add(p) }
    end
    result
  end

  def test_merge_and_cancellation_are_distinct
    a = C.normalize([[1, 2, 4]], 2)
    b = C.normalize([[1, 2, 8]], 2)
    row = C.best_pair([a], [b])
    assert_equal 1, row[:rank]
    assert_equal [[1, 2, 12]], C.materialize(row[:result], 2)
    assert_equal 0, C.best_pair([a], [a])[:rank]
    assert_equal 0, C.best_pair([{}], [{}])[:rank]
    assert_raises(RuntimeError) { C.best_pair([], [a]) }
    assert_raises(RuntimeError) { C.normalize([[1, 0, 1]], 1) }
    assert_raises(RuntimeError) { C.normalize([[1, 1, 1]], -1) }
  end

  def test_all_pairs_match_exhaustive_join
    random = Random.new(20_260_906_71)
    1_000.times do
      pools = Array.new(2) do
        Array.new(random.rand(1..10)) do
          C.normalize(Array.new(random.rand(0..8)) { Array.new(3) { random.rand(1..7) } }, 2)
        end
      end
      expected = pools[0].each_index.to_a.product(pools[1].each_index.to_a).map do |i, j|
        [C.merge(pools[0][i], pools[1][j]).length, i, j]
      end.min
      result = C.best_pair(*pools)
      assert_equal expected, [result[:rank], *result[:indices]]
      i, j = result[:indices]
      assert_equal signature(C.materialize(pools[0][i], 2) + C.materialize(pools[1][j], 2)), signature(C.materialize(result[:result], 2))
    end
  end

  def test_high_bit_normalization_on_every_axis
    words = [1 << 255, 1 << 254, (1 << 253) | 1]
    3.times do |axis|
      terms = [words, words.each_with_index.map { |v, i| i == axis ? v ^ 4 : v }]
      reduced = C.materialize(C.normalize(terms, axis), axis)
      assert_equal 1, reduced.length
      assert_equal signature(terms), signature(reduced)
    end
    assert_raises(RuntimeError) { C.normalize([[1, 1, 1 << 256]], 0) }
  end

  def test_rank_stratified_candidates_match_complete_pair_enumeration
    random = Random.new(20_260_907_19)
    300.times do
      pools = Array.new(2) do
        Array.new(random.rand(1..10)) do
          C.normalize(Array.new(random.rand(0..9)) { Array.new(3) { random.rand(1..7) } }, 2)
        end
      end
      all = pools[0].each_index.to_a.product(pools[1].each_index.to_a).map do |i, j|
        [C.merge(pools[0][i], pools[1][j]).length, i, j]
      end.sort
      width, slack = random.rand(1..5), random.rand(0..3)
      result = C.candidate_pairs(*pools, width: width, slack: slack)
      expected = (0..slack).flat_map { |s| all.select { |r| r[0] == all[0][0] + s }.first(width) }
      assert_equal all[0], result[:minimum]
      assert_equal expected, result[:candidates].map { |c| [c[:rank], *c[:indices]] }
      assert_equal (0..slack).map { |s| all.count { |r| r[0] == all[0][0] + s } }, result[:eligible_by_rank]
    end
    assert_raises(RuntimeError) { C.candidate_pairs([{}], [{}], width: 0, slack: 0) }
    assert_raises(RuntimeError) { C.candidate_pairs([{}], [{}], width: 1, slack: -1) }
    assert_equal [{rank: 0, indices: [0, 0]}], C.candidate_pairs([{}, {}], [{}, {}], width: 1, slack: 2)[:candidates]
  end

  def test_replayable_merger_and_invalid_mutations
    b = MetaflipBudProducts
    m = MetaflipOuterBasisProducts
    Dir.mktmpdir("metaflip-cofactor-test-") do |root|
      parent = b.naive([2, 1, 1])
      allocation = [[1, 1], [1], [1]]
      leaves = [b.naive([1, 1, 1])] * 2
      _, product = m.export(File.join(root, "product"), parent, allocation, leaves, [2, 1, 1])
      path = File.join(root, "merge.json")
      result = C.export_merge(path, product, [0, 1], 0)
      assert_equal result.audit, C.replay(path)
      assert_equal 2, result.rank
      assert_raises(RuntimeError) { C.export_merge(path, product, [0, 1], 0) }
      assert_raises(RuntimeError) { C.from_product(product, [0, 0], 0) }
      assert_raises(RuntimeError) { C.from_product(product, [0, 2], 0) }
      assert_raises(RuntimeError) { C.from_product(product, [0, 1], 3) }
      data = JSON.parse(File.read(path))
      data["exact_rank"] -= 1
      File.write(path, JSON.generate(data))
      assert_raises(RuntimeError) { C.replay(path) }
      data["exact_rank"] += 1
      data["product_sha256"] = "0" * 64
      File.write(path, JSON.generate(data))
      assert_raises(RuntimeError) { C.replay(path) }
    end
  end

  def test_triple_words_match_full_tensor_and_deduplicate
    b = MetaflipBudProducts
    m = MetaflipOuterBasisProducts
    leaf = b.naive([2,2,2])
    pools = 3.times.map { |axis| [ {kind:"kernel",axis:axis,word:[[axis,1,0]]} ] }
    rows = C.triple_proposals(leaf,pools).to_a
    assert_equal 1,rows.length
    raw,action = rows.first
    assert_equal "kernel_triple",action[:kind].to_s
    assert_equal m.transvection_word(leaf,action[:word]).terms,raw
    assert b::Scheme.new(leaf.shape,b.text(raw)).audit[:exact]
    assert_equal 1,C.triple_proposals(leaf,[pools[0]*2,pools[1],pools[2]]).to_a.length
    assert_empty C.triple_proposals(leaf,[[],pools[1],pools[2]]).to_a
    assert_raises(RuntimeError) { C.triple_proposals(leaf,[pools[0],pools[0],pools[2]]).to_a }
  end
end
