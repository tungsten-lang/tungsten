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
end
