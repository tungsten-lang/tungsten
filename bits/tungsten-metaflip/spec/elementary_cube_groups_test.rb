require 'minitest/autorun'
require 'tmpdir'
require_relative '../tools/elementary_cube_groups'

class ElementaryCubeGroupsTest < Minitest::Test
  C = MetaflipElementaryCubeGroups
  B = MetaflipBudProducts

  def setup
    path = File.expand_path('../lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt', __dir__)
    @strassen = B.load_scheme(path)
    @library = B::Library.new([@strassen])
  end

  def test_complete_naive_coordinate_cubes
    [[[2,2,2],1], [[2,2,3],3], [[3,3,3],27]].each do |shape,count|
      parent = B.naive(shape)
      r = C.scan(parent)
      assert r[:complete]
      assert_equal count, r[:groups].size
      assert_equal count, r[:groups].map { |g| g[:indices].sort }.uniq.size
      r[:groups].each do |g|
        assert_equal 8, g[:indices].size
        assert B.validate_groups(parent,C.partition(parent,g))
        assert_equal parent.rank-1, B.score(C.partition(parent,g),[1,1,1],@library)
      end
    end
  end

  def test_literal_order_and_invertible_raw_factor_map_preserve_detection
    source = B.naive([2,2,3])
    # Independent invertible bit shears on each factor destroy the coordinate
    # monomial spelling without changing the equality pattern or exact tensor
    # relation being replaced. Embed the transformed block plus its compensating
    # difference into a checked matrix-multiplication scheme.
    block = source.terms.each_with_index.filter_map { |t,i| t unless i%3 == 2 }
    mapped = block.map { |t| t.each_with_index.map { |v,a| v[0] == 1 ? v ^ (1 << (a+1)) : v } }
    toggled = source.terms + mapped + mapped
    # A checked redundant parent is allowed here; exact index disjointness is
    # tested even when duplicate factor triples exist.
    parent = B::Scheme.new(source.shape,B.text(toggled.reverse))
    r = C.scan(parent,max_layers: 100_000,max_pairs: 100_000,max_groups: 10_000)
    refute_empty r[:groups]
    # Original mapped positions 12...20 become reversed positions 8...16.
    assert r[:groups].any? { |g| g[:indices].all? { |i| (8...16).cover?(i) } }
    r[:groups].first(20).each { |g| assert B.validate_groups(parent,C.partition(parent,g)) }
    reversed = B::Scheme.new(source.shape,B.text(source.terms.reverse))
    expected = C.scan(source)[:groups].map { |g| g[:indices].sort }.sort
    actual = C.scan(reversed)[:groups].map { |g| g[:indices].map { |i| source.rank-1-i }.sort }.sort
    assert_equal expected, actual
  end

  def test_actual_strassen_replacement_and_full_tensor_replay
    parent = B.naive([2,2,3])
    cube = C.scan(parent)[:groups].first
    Dir.mktmpdir('metaflip-cube-') do |root|
      result, recipe = B.export(root,parent,[1,1,1],C.partition(parent,cube),@library)
      assert_equal 11, result.rank
      assert_equal 11, B.replay(recipe)[:rank]
    end
    assert_empty C.scan(@strassen)[:groups]
  end

  def test_limits_do_not_claim_complete_detection
    parent = B.naive([3,3,3])
    [{max_layers: 1}, {max_pairs: 1}, {max_groups: 1}].each do |limits|
      r = C.scan(parent,**limits)
      refute r[:complete]
      refute_empty r[:cutoffs]
      r[:groups].each { |g| assert B.validate_groups(parent,C.partition(parent,g)) }
    end
    assert_raises(RuntimeError) { C.scan(parent,max_layers: 0) }
    assert_raises(RuntimeError) { C.scan(parent,max_pairs: -1) }
    assert_raises(RuntimeError) { C.scan(parent,max_groups: false) }
  end

  def test_free_factor_filter_matches_exhaustive_layer_pairs
    base = B.naive([2,2,3])
    parents = [base, B.naive([3,3,3]), B.naive([4,4,4]), @strassen]
    8.times do |seed|
      rows = base.terms.map(&:dup)
      random = Random.new(seed)
      5.times do
        axis = random.rand(3)
        buckets = rows.each_index.group_by { |i| rows[i][axis] }.values.select { |b| b.size > 1 }
        i,j = buckets.sample(random: random).sample(2,random: random)
        a,b = [0,1,2]-[axis]
        next if rows[i][a] == rows[j][a] || rows[i][b] == rows[j][b]
        rows[i][a] ^= rows[j][a]; rows[j][b] ^= rows[i][b]
      end
      parents << B::Scheme.new(base.shape,B.text(rows))
    end
    parents.each do |parent|
      layers = MetaflipBudPackings.grid_groups(parent).map { |g| C.canonical_layer(parent,g) }
      expected, matching, overlapping = [], 0, 0
      layers.group_by { |l| [l[:stack],l[:signature]] }.each_value do |bucket|
        bucket.combination(2) do |a,b|
          matching += 1
          if (a[:mask] & b[:mask]).zero?
            expected << (a[:mask] | b[:mask])
          else
            overlapping += 1
          end
        end
      end
      result = C.scan(parent)
      assert result[:complete]
      masks = result[:groups].map { |g| g[:indices].reduce(0) { |m,i| m | (1<<i) } }
      assert_equal expected.uniq.sort, masks.sort
      assert_operator result[:matching_pairs], :<=, matching
      assert_operator result[:overlapping_pairs], :<=, overlapping
      assert_equal matching-overlapping, result[:matching_pairs]-result[:overlapping_pairs]
    end
  end

  def test_unique_free_factors_cannot_make_two_disjoint_layers
    parent = B.naive([1,12,12])
    control = C.scan(parent, max_layers: 50)
    assert control[:complete]
    assert_equal 0, control[:layers]
    assert_empty control[:groups]
    unfiltered = C.scan(parent,max_layers: 50,prune_singleton_free: false)
    refute unfiltered[:complete]
    assert_equal ['layers'], unfiltered[:cutoffs]
    assert_raises(RuntimeError) { C.scan(parent,prune_singleton_free: 1) }
    assert_raises(RuntimeError) { MetaflipBudPackings.grid_groups(parent,min_free_multiplicity: 0).to_a }
  end
end
