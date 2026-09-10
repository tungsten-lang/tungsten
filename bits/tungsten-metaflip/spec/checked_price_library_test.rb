require 'minitest/autorun'
require 'tmpdir'
require_relative '../tools/checked_price_library'

class CheckedPriceLibraryTest < Minitest::Test
  B=MetaflipBudProducts
  def fixture(root)
    source=File.expand_path('../lib/metaflip/seeds/gf2/matmul_2x2_rank7_d36_gf2.txt',__dir__)
    # Resolve the existing canonical rank-seven seed without assuming a density suffix.
    source=Dir[File.expand_path('../lib/metaflip/seeds/gf2/matmul_2x2*rank7*_gf2.txt',__dir__)].first unless File.file?(source)
    seed=B.load_scheme(source,[2,2,2])
    path=File.join(root,'seed.txt');File.binwrite(path,seed.source_text)
    prices=(2..4).to_a.repeated_combination(3).to_h { |s| [s,s.inject(:*)] }
    prices[[2,2,2]]=7;prices[[2,2,3]]=11;prices[[4,4,4]]=49
    sources=[{shape:[2,2,2],rank:7,path:path,sha256:Digest::SHA256.file(path).hexdigest}]
    [prices,sources]
  end
  def test_lazy_block_product_orientation_and_pin_replay
    Dir.mktmpdir do |root|
      prices,sources=fixture(root);lib=MetaflipCheckedPriceLibrary.new(prices,sources,maximum:4)
      assert_empty lib.used_sources
      assert_equal 11,lib.scheme([3,2,2]).rank
      assert_equal [3,2,2],lib.scheme([3,2,2]).shape
      assert_equal 49,lib.scheme([4,4,4]).rank
      assert_equal 1,lib.used_sources.size
      assert lib.verify_sources_unchanged!
      File.write(sources[0][:path],'corrupt')
      assert_raises(RuntimeError) { lib.verify_sources_unchanged! }
    end
  end
  def test_unwitnessed_rank_bad_hash_and_invalid_shapes_fail_closed
    Dir.mktmpdir do |root|
      prices,sources=fixture(root)
      wrong=MetaflipCheckedPriceLibrary.new(prices,sources.map { |r| r.merge(sha256:'wrong') },maximum:4)
      assert_raises(RuntimeError) { wrong.scheme([2,2,2]) }
      prices[[2,2,3]]=10
      lib=MetaflipCheckedPriceLibrary.new(prices,sources,maximum:4)
      assert_raises(RuntimeError) { lib.scheme([2,2,3]) }
      assert_raises(RuntimeError) { lib.rank([0,2,3]) }
      assert_raises(RuntimeError) { lib.rank([5,2,3]) }
    end
  end
  def test_matching_hash_does_not_replace_full_tensor_verification
    Dir.mktmpdir do |root|
      prices,sources=fixture(root)
      terms=B.load_scheme(sources[0][:path],[2,2,2]).terms.map(&:dup)
      terms[0][0]^=terms[0][0]==1 ? 2 : 1
      File.binwrite(sources[0][:path],B.text(terms))
      sources[0][:sha256]=Digest::SHA256.file(sources[0][:path]).hexdigest
      lib=MetaflipCheckedPriceLibrary.new(prices,sources,maximum:4)
      assert_raises(RuntimeError){lib.scheme([2,2,2])}
    end
  end

  def test_missing_first_block_does_not_hide_a_later_checked_block
    Dir.mktmpdir do |root|
      prices,sources=fixture(root)
      (2..6).to_a.repeated_combination(3){|s|prices[s] ||= s.inject(:*)}
      prices[[2,2,4]]=14
      prices[[2,2,5]]=17 # Unwitnessed first 1+5 split; not an admitted rank.
      prices[[2,2,6]]=21 # The later 2+4 split is constructible.
      lib=MetaflipCheckedPriceLibrary.new(prices,sources,maximum:6)
      result=lib.scheme([2,6,2])
      assert_equal [2,6,2],result.shape
      assert_equal 21,result.rank
      assert_equal B.tensor_product(B.load_scheme(sources[0][:path],[2,2,2]),B.naive([1,1,3])).rank,result.rank
      assert_raises(RuntimeError){lib.scheme([2,2,5])}
      assert lib.verify_sources_unchanged!
    end
  end

  def test_missing_blocks_do_not_hide_a_checked_kronecker_product
    Dir.mktmpdir do |root|
      prices,sources=fixture(root)
      prices[[3,4,4]]=33 # Makes the first block price 16+33=49.
      lib=MetaflipCheckedPriceLibrary.new(prices,sources,maximum:4)
      assert_equal 49,lib.scheme([4,4,4]).rank
      assert_raises(RuntimeError){lib.scheme([3,4,4])}
      assert lib.verify_sources_unchanged!
    end
  end

  def test_missing_first_product_does_not_hide_a_later_checked_product
    Dir.mktmpdir do |root|
      prices,sources=fixture(root)
      (2..6).to_a.repeated_combination(3){|s|prices[s] ||= s.inject(:*)}
      prices[[2,2,3]]=12
      prices[[3,4,4]]=42 # The 2 * 42 product has no witness.
      prices[[4,4,6]]=84 # The 7 * 12 product does.
      lib=MetaflipCheckedPriceLibrary.new(prices,sources,maximum:6)
      assert_equal 84,lib.scheme([4,6,4]).rank
      assert_raises(RuntimeError){lib.scheme([3,4,4])}
      assert lib.verify_sources_unchanged!
    end
  end

  def test_backtracking_never_swallows_source_or_admission_errors
    Dir.mktmpdir do |root|
      %i[pin tensor rank].each do |failure|
        prices,sources=fixture(root)
        prices[[3,4,4]]=33
        case failure
        when :pin then sources[0][:sha256]='wrong'
        when :tensor
          File.write(sources[0][:path],"1\n1 1 1\n")
          sources[0][:sha256]=Digest::SHA256.file(sources[0][:path]).hexdigest
        when :rank
          # A valid full tensor at the wrong claimed rank is not a missing
          # recipe and must not be bypassed by another decomposition.
          File.write(sources[0][:path],B.text(B.naive([2,2,2]).terms))
          sources[0][:sha256]=Digest::SHA256.file(sources[0][:path]).hexdigest
        end
        lib=MetaflipCheckedPriceLibrary.new(prices,sources,maximum:4)
        error=assert_raises(RuntimeError){lib.scheme([4,4,4])}
        refute_kind_of MetaflipCheckedPriceLibrary::MissingConstruction,error
      end
    end
  end

  def test_failed_subproblems_are_memoized_without_hiding_successes
    Dir.mktmpdir do |root|
      prices,sources=fixture(root);prices[[3,4,4]]=33
      calls=Hash.new(0)
      lib=MetaflipCheckedPriceLibrary.new(prices,sources,maximum:4)
      lib.define_singleton_method(:construct){|shape|calls[shape]+=1;super(shape)}
      assert_equal 49,lib.scheme([4,4,4]).rank
      2.times do
        error=assert_raises(MetaflipCheckedPriceLibrary::MissingConstruction){lib.scheme([4,3,4])}
        assert_equal [3,4,4],error.shape
        assert_equal 33,error.rank
      end
      assert_equal 1,calls[[3,4,4]]
      assert_equal 49,lib.scheme([4,4,4]).rank
    end
  end

  def test_source_membership_is_snapshotted_for_negative_memoization
    Dir.mktmpdir do |root|
      prices,sources=fixture(root);prices[[3,4,4]]=33
      lib=MetaflipCheckedPriceLibrary.new(prices,sources,maximum:4)
      assert_raises(MetaflipCheckedPriceLibrary::MissingConstruction){lib.scheme([3,4,4])}
      sources[0][:shape][0]=3
      sources[0][:path].replace('not-the-pinned-source')
      sources[0][:sha256].replace('not-the-pinned-hash')
      sources.clear
      prices[[2,2,2]]=6
      assert_equal 7,lib.scheme([2,2,2]).rank
      assert_equal 49,lib.scheme([4,4,4]).rank
      assert lib.verify_sources_unchanged!
    end
  end

  def test_reachability_matches_an_independent_bottom_up_price_graph
    Dir.mktmpdir do |root|
      rng=Random.new(985039)
      16.times do
        prices,sources=fixture(root)
        prices.keys.each{|shape|prices[shape]=rng.rand(1..shape.inject(:*)) unless shape==[2,2,2]}
        lib=MetaflipCheckedPriceLibrary.new(prices,sources,maximum:4)
        rank=lambda{|s|s.include?(1) ? s.inject(:*) : prices.fetch(s.sort)}
        reachable={}
        (1..4).to_a.repeated_combination(3).sort_by{|s|[s.inject(:*),s]}.each do |s|
          yes=s.include?(1)||rank.call(s)==s.inject(:*)||s==[2,2,2]
          3.times do |axis|
            1.upto(s[axis]/2) do |cut|
              a,b=s.dup,s.dup;a[axis]=cut;b[axis]-=cut
              yes ||= rank.call(a)+rank.call(b)==rank.call(s)&&reachable[a.sort]&&reachable[b.sort]
            end
          end
          divs=s.map{|n|(1..n).select{|d|n%d==0}}
          divs[0].product(divs[1],divs[2]).each do |a|
            b=s.zip(a).map{|n,d|n/d}
            next if a==[1,1,1]||b==[1,1,1]
            yes ||= rank.call(a)*rank.call(b)==rank.call(s)&&reachable[a.sort]&&reachable[b.sort]
          end
          reachable[s]=!!yes
          if yes
            result=lib.scheme(s.reverse)
            assert_equal s.reverse,result.shape
            assert_equal rank.call(s),result.rank
          else
            assert_raises(MetaflipCheckedPriceLibrary::MissingConstruction){lib.scheme(s)}
          end
        end
      end
    end
  end
end
