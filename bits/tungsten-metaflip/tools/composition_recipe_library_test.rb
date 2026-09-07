require 'minitest/autorun'
require 'tmpdir'
require_relative 'composition_recipe_library'

class CompositionRecipeLibraryTest < Minitest::Test
  B=MetaflipBudProducts
  class Base
    def scheme(shape); MetaflipBudProducts.naive(shape);end
    def verify_sources_unchanged!;true;end
    def used_sources;{};end
  end
  def setup
    @tmp=Dir.mktmpdir('composition-recipe-test-')
    @parent=B.naive([2,2,2])
    @path=File.join(@tmp,'parent.txt');File.binwrite(@path,B.text(@parent.terms))
    @parents=[{'path'=>@path,'shape'=>[2,2,2],'sha256'=>Digest::SHA256.file(@path).hexdigest}]
    @plan={'complete'=>true,'field'=>'GF(2)','record_claim'=>false,
      'model_shapes'=>[[1,1,1],[1,1,2],[1,2,2],[2,2,2],[2,2,4],[2,3,4],[4,4,4]],
      'baseline_recipes'=>[
        {'kind'=>'naive','rank'=>1},{'kind'=>'naive','rank'=>2},
        {'kind'=>'seed','rank'=>4},{'kind'=>'naive','rank'=>8},
        {'kind'=>'bud','rank'=>16,'parent'=>0,'scale'=>[2,1,1],'axis'=>0,'splits'=>[0,1,2]},
        {'kind'=>'block','rank'=>24,'inputs'=>[3,4]},
        {'kind'=>'kronecker','rank'=>64,'inputs'=>[3,3]}]}
  end
  def teardown;FileUtils.remove_entry(@tmp);end
  def make;MetaflipCompositionRecipeLibrary.new(@plan,@parents,Base.new,File.join(@tmp,'out'));end
  def test_bud_block_kronecker_and_orientation
    # Change the block target to the actual concatenation 2x2x6.
    @plan['model_shapes'][5]=[2,2,6]
    lib=make
    [[2,2,4],[2,2,6],[4,4,4],[4,2,2]].each do |shape|
      scheme=lib.scheme(shape)
      assert_equal shape.inject(:*),scheme.rank
      assert_equal B.naive(shape).terms.sort,scheme.terms.sort
    end
    assert lib.verify_sources_unchanged!
  end
  def test_hash_drift_and_impossible_block_are_rejected
    assert_raises(RuntimeError){make.scheme([2,3,4])}
    File.binwrite(@path,B.text(@parent.terms.reverse))
    assert_raises(RuntimeError){make.scheme([2,2,4])}
  end
  def test_underpriced_plan_is_rejected
    @plan['baseline_recipes'][4]['rank']=15
    assert_raises(RuntimeError){make.scheme([2,2,4])}
  end
  def mixed_plan
    @parents[0]['mixed_partitions']=[[
      {'axis'=>0,'indices'=>[0,1]}, {'axis'=>1,'indices'=>[2,6]},
      *[3,4,5,7].map{|i|{'axis'=>nil,'indices'=>[i]}}]]
    @plan['baseline_recipes'][4]={'kind'=>'mixed_bud','rank'=>16,'parent'=>0,
      'partition'=>0,'scale'=>[1,2,1],'splits'=>[[0,1,2],[0,1,2],nil]}
  end
  def test_mixed_axis_partition_and_splitting
    mixed_plan
    [2,1].each do |chunk|
      @plan['baseline_recipes'][4]['splits'][0][2]=chunk
      lib=make;scheme=lib.scheme([2,2,4])
      assert_equal B.naive([2,2,4]).terms.sort,scheme.terms.sort
      assert_equal 'mixed_bud',lib.recipes[[2,2,4]][:kind]
      assert lib.verify_sources_unchanged!
    end
  end
  def test_mixed_partition_cannot_hide_bad_shared_factor_with_singleton_splits
    mixed_plan
    groups=@parents[0]['mixed_partitions'][0]
    groups[0]['indices']=[0,2];groups[1]['indices']=[1,6]
    @plan['baseline_recipes'][4]['splits']=[[0,1,1],[0,1,1],nil]
    assert_raises(RuntimeError){make.scheme([2,2,4])}
  end
  def test_mixed_partition_rejects_duplicate_missing_hash_drift_and_underprice
    mixed_plan
    @parents[0]['mixed_partitions'][0][-1]['indices']=[0]
    assert_raises(RuntimeError){make.scheme([2,2,4])}
    mixed_plan
    @parents[0]['mixed_partitions'][0].pop
    assert_raises(RuntimeError){make.scheme([2,2,4])}
    mixed_plan
    @plan['baseline_recipes'][4]['rank']=15
    assert_raises(RuntimeError){make.scheme([2,2,4])}
    mixed_plan
    File.binwrite(@path,B.text(@parent.terms.reverse))
    assert_raises(RuntimeError){make.scheme([2,2,4])}
  end
  def grid_plan
    @parents[0]['mixed_partitions']=[[
      {'elementary_shape'=>[2,2,1],'indices'=>[0,2,4,6]},
      *[1,3,5,7].map{|i|{'axis'=>nil,'indices'=>[i]}}]]
    @plan['baseline_recipes'][4]={'kind'=>'mixed_bud','rank'=>16,'parent'=>0,
      'partition'=>0,'scale'=>[1,1,2],'splits'=>[[0,1],nil,nil],
      'grid_plans'=>{'2x2x1'=>{'kind'=>'leaf'}}}
  end
  def test_grid_and_recursive_grid_cuts_materialize_exactly
    grid_plan
    whole=make.scheme([2,2,4]);assert_equal B.naive([2,2,4]).terms.sort,whole.terms.sort
    @plan['baseline_recipes'][4]['grid_plans']['2x2x1']={
      'kind'=>'cut','axis'=>0,'at'=>1,'left'=>{'kind'=>'cut','axis'=>1,'at'=>1,
        'left'=>{'kind'=>'leaf'},'right'=>{'kind'=>'leaf'}},'right'=>{'kind'=>'leaf'}}
    cut=make.scheme([2,2,4]);assert_equal whole.terms.sort,cut.terms.sort
    @plan['baseline_recipes'][4]['grid_plans']['2x2x1']['at']=2
    assert_raises(RuntimeError){make.scheme([2,2,4])}
    grid_plan
    @parents[0]['mixed_partitions'][0][0]['indices']=[0,1,4,6]
    @parents[0]['mixed_partitions'][0][1]['indices']=[2]
    assert_raises(RuntimeError){make.scheme([2,2,4])}
  end
end
