require "minitest/autorun"
require_relative "../tools/leaf_delta_collisions"

class LeafDeltaCollisionsTest < Minitest::Test
  D = MetaflipLeafDeltaCollisions
  def test_positive_collision_and_old_term_correction
    parity = Set[1, 2]
    proposals = [{ slot: 0, delta: Set[1, 3] }, { slot: 1, delta: Set[2, 3] }]
    result = D.rank_pairs(parity, proposals)
    assert_equal(-2, result[:best][:rank_delta])
    assert_equal 1, result[:possible_pairs]
    assert_equal 1, result[:rank_gain_pairs]
    assert_nil D.rank_pairs(Set[1], [{ slot: 0, delta: Set[1, 3] }, { slot: 1, delta: Set[1, 3] }])[:best]
    assert_nil D.rank_pairs(parity, proposals.map { |p| p.merge(slot: 0) })[:best]
    assert_raises(RuntimeError) { D.rank_pairs(parity, [{ slot: 0, delta: Set[1] }]) }
    assert_raises(RuntimeError) { D.rank_pairs([], []) }
  end

  def test_complete_rank_gain_join_matches_bruteforce
    random = Random.new(20_260_906_51)
    1_000.times do
      parity = (0...16).select { random.rand(2) == 1 }.to_set
      proposals = Array.new(20) do
        delta = (0...32).select { random.rand(5) == 0 }.to_set
        next if (delta - parity).length < (delta & parity).length
        { slot: random.rand(5), delta: delta }
      end.compact
      expected = nil; gains = 0
      proposals.each_index.to_a.combination(2) do |i, j|
        next if proposals[i][:slot] == proposals[j][:slot]
        delta = proposals[i][:delta] ^ proposals[j][:delta]
        score = delta.sum { |t| parity.include?(t) ? -1 : 1 }
        next unless score.negative?
        gains += 1
        density = delta.sum { |t| (parity.include?(t) ? -1 : 1) * (t + 1) }
        key = [score, density, i, j]
        expected = key if !expected || (key <=> expected) == -1
      end
      result = D.rank_pairs(parity, proposals, weight: ->(t) { t + 1 })
      assert_equal gains, result[:rank_gain_pairs]
      expected ? assert_equal(expected, result[:best][:key]) : assert_nil(result[:best])
    end
  end

  def test_intersection_dimension_matches_explicit_small_spans
    random = Random.new(20_260_906_52)
    span = ->(words) { words.reduce(Set[0]) { |s, w| s | s.map { |v| v ^ w }.to_set } }
    500.times do
      left, right = Array.new(2) { Array.new(random.rand(0..6)) { random.rand(32) } }
      actual = D.binary_rank(left) + D.binary_rank(right) - D.binary_rank(left + right)
      assert_equal(span.call(left).intersection(span.call(right)).length, 1 << actual)
    end
    assert_raises(RuntimeError) { D.binary_rank([-1]) }
  end
end
