require 'minitest/autorun'
require 'tmpdir'
require_relative '../tools/reprice_public_structures'

class PublicStructurePricesTest < Minitest::Test
  S = MetaflipPublicStructurePrices

  def example
    {'s1'=>{'dimension'=>[2,2,12], 'rank'=>42,
      'structure'=>'<1,1,4> + 2<1,1,1> + 3<1,1,2> + 6<1,1,5>'},
     's2'=>{'dimension'=>[4,4,2]}, 'path'=>'published.json', 'serendipitous_rank'=>982}
  end

  def prices
    {[4,4,8]=>94, [2,4,4]=>26, [4,4,4]=>47, [4,4,10]=>115, [8,8,24]=>985}
  end

  def test_reprices_known_leaf_without_admitting_metadata
    row = S.price('8x8x24',example,prices,32)
    assert_equal 977, row[:repriced_formula]
    assert_equal 8, row[:potential_gain]
    assert_equal false, row[:parent_coefficients_verified]
    assert_equal 42, S.structure(example['s1']['structure']).sum { |g| g[:count]*g[:shape].inject(:*) }
  end

  def test_rejects_malformed_and_nonpositive_groups
    ['', '<1,1,1> +', '0<1,1,1>', '<0,1,1>', '-1<1,1,1>', '<1,1,1> garbage'].each do |s|
      assert_raises(RuntimeError) { S.structure(s) }
    end
  end

  def test_rejects_inconsistent_geometry_and_rank
    assert_raises(RuntimeError) { S.price('8x8x23',example,prices,32) }
    bad = example
    bad['s1']['rank'] = 43
    assert_raises(RuntimeError) { S.price('8x8x24',bad,prices,32) }
    assert_raises(KeyError) { S.price('8x8x24',example,{},32) }
  end

  def test_outside_grid_not_silently_priced
    assert_nil S.price('8x8x24',example,prices,16)
  end

  def test_cli_keeps_suggestions_distinct_from_certificates
    Dir.mktmpdir do |root|
      table, closure, output = %w[table.json closure.json output.json].map { |n| File.join(root,n) }
      File.write(table,JSON.generate('8x8x24'=>example))
      data={complete:true,field:'GF(2)',record_claim:false,maximum:32,
        rows:prices.map { |shape,rank| {shape:shape,augmented_rank:rank} }}
      File.write(closure,JSON.generate(data))
      args=['--table',table,'--closure',closure,'--output',output]
      capture_io { S.main(args.dup) }
      r=JSON.parse(File.read(output))
      assert r.fetch('screen_only')
      assert r.fetch('parent_fields_unchecked')
      refute r.fetch('record_claim')
      refute r.key?('field')
      assert_equal 1,r.fetch('summary').fetch('parent_fetches')
      assert_equal Digest::SHA256.file(table).hexdigest,r.fetch('source_sha256').fetch(table)
      assert_raises(RuntimeError) { S.main(args.dup) }
      File.delete(output)
      data[:complete]=false
      File.write(closure,JSON.generate(data))
      assert_raises(RuntimeError) { S.main(args.dup) }
      refute File.exist?(output)
    end
  end
end
