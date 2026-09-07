require "minitest/autorun"
require_relative "../tools/matrix_pockets"

class MatrixPocketsTest < Minitest::Test
  M = MetaflipMatrixPockets
  def signature(terms)
    result = Hash.new(0)
    terms.each do |t|
      a, b, c = t.map { |v| MetaflipTensorVerifier.bit_positions(v) }
      a.product(b, c).each { |point| result[point] ^= 1 }
    end
    result.select { |_, v| v == 1 }.keys.sort
  end

  def test_entire_lookup_reconstructs_and_is_minimal_through_three
    table = M.table
    terms = (1..15).to_a.product((1..3).to_a, (1..3).to_a)
    words = terms.map do |t|
      signature([t]).sum { |i, j, k| 1 << (4 * i + 2 * j + k) }
    end
    reachable = { 0 => 0 }
    frontier = [0]
    3.times do |level|
      next_frontier = {}
      frontier.each { |v| words.each { |w| next_frontier[v ^ w] = true unless reachable.key?(v ^ w) } }
      frontier = next_frontier.keys
      frontier.each { |v| reachable[v] = level + 1 }
    end
    table.each_with_index do |row, bits|
      assert_equal bits, signature(row).sum { |i, j, k| 1 << (4 * i + 2 * j + k) }
      assert_equal reachable.fetch(bits, 4), row.length
    end
  end

  def test_four_independent_original_factors_reduce_to_three
    terms = [[1, 1, 1], [2, 1, 2], [4, 2, 3], [8, 3, 3]]
    assert_equal 4, MetaflipSharedFactorCompression.factor(terms.map { |t| [t[0], t[0]] }).length
    row = M.replacement(terms, 0)
    assert_equal 3, row[:dimension]
    assert_equal 3, row[:replacement].length
    assert_equal signature(terms), signature(row[:replacement])
    result = M.scan(terms)
    refute_nil result[:best]
    assert_equal signature(result[:best][:indices].map { |i| terms[i] }), signature(result[:best][:replacement])
  end

  def test_index_covers_every_nonstar_plane_subset
    random = Random.new(20_260_906_41)
    150.times do
      terms = Array.new(8) { Array.new(3) { random.rand(1..15) } }.uniq
      expected = {}
      3.times do |axis|
        other = (0..2).to_a - [axis]
        terms.each_index.to_a.combination(3) do |ids|
          group = ids.map { |i| terms[i] }
          next unless other.all? { |a| M.plane(group.map { |t| t[a] }) }
          next unless other.all? { |a| group.map { |t| t[a] }.uniq.length >= 2 }
          palettes = other.map { |a| x, y = group.map { |t| t[a] }.uniq.take(2); [x, y, x ^ y] }
          all = terms.each_index.select { |i| other.each_with_index.all? { |a, j| palettes[j].include?(terms[i][a]) } }
          expected[[axis, all]] = true
        end
      end
      actual = M.each_pocket(terms).to_a
      assert_equal expected.keys.sort, actual.sort
      assert_equal actual.uniq, actual
      actual.each do |axis, ids|
        old = ids.map { |i| terms[i] }
        assert_equal signature(old), signature(M.replacement(old, axis)[:replacement])
      end
    end
  end

  def test_high_bits_and_fail_closed_domains
    terms = [[1 << 255, 1 << 254, 1 << 253], [1 << 252, 1 << 254, 1 << 251],
      [1 << 250, 1 << 249, (1 << 253) ^ (1 << 251)],
      [1 << 248, (1 << 254) ^ (1 << 249), (1 << 253) ^ (1 << 251)]]
    assert_equal signature(terms), signature(M.replacement(terms, 0)[:replacement])
    assert_equal 3, M.replacement(terms, 0)[:replacement].length
    assert_nil M.replacement([[1, 1, 1], [2, 2, 2], [4, 4, 4]], 0)
    assert_raises(RuntimeError) { M.replacement([[1, 1, -1]], 0) }
    assert_raises(RuntimeError) { M.replacement([[1, 1, 1 << 256]], 0) }
    assert_raises(RuntimeError) { M.replacement([[1, 1, 1]], 3) }
    assert_raises(RuntimeError) { M.scan([]) }
  end

  def test_every_shortest_alternative_is_exact
    M.alternative_table.each_with_index do |rows, bits|
      rows.each do |row|
        assert_equal bits, signature(row).sum { |i, j, k| 1 << (4 * i + 2 * j + k) }
        assert_equal M.table[bits].length, row.length
      end
      assert_equal rows.uniq, rows
    end
  end

  def test_raw_compression_and_macro_scoring_preserve_tensor
    random = Random.new(20_260_906_42)
    100.times do
      terms = Array.new(8) { Array.new(3) { random.rand(1..3) } }
      reduced, = MetaflipSharedFactorCompression.compress_terms(terms)
      assert_equal signature(terms), signature(reduced)
      next if reduced.empty?
      result = M.scan_variants(reduced)
      if result[:best]
        assert_equal signature(reduced), signature(result[:best][:terms])
        assert_operator result[:best][:key] <=> [reduced.length, reduced.flatten.sum { |v| v.digits(2).sum }], :<, 0
      end
    end
  end
end
