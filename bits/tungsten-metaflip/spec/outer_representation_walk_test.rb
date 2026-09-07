require "minitest/autorun"
require "tmpdir"
require_relative "../tools/outer_representation_walk"

class OuterRepresentationWalkTest < Minitest::Test
  W = MetaflipOuterRepresentationWalk
  B = MetaflipBudProducts
  M = MetaflipOuterBasisProducts
  P = MetaflipOuterLeafPortfolio

  def test_cli_keeps_exact_recipes_and_rejects_invalid_limits
    parent = B.load_scheme(File.expand_path("../lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt",__dir__))
    allocation = [[1,2],[2,1],[1,2]]
    _,_,leaves = M.compose(parent,allocation,library:B::Library.new([parent]))
    Dir.mktmpdir("representation-walk") do |root|
      _,source = M.export(File.join(root,"source"),parent,allocation,leaves,[3,3,3])
      out = File.join(root,"out")
      args = ["--output",out,"--moves","kernel","--rounds","2",source]
      capture_io { W.main(args.dup) }
      report = JSON.parse(File.read(File.join(out,"report.json")))
      assert report["complete"]
      refute report["record_claim"]
      assert_equal 1,report["targets"]
      assert report["rows"].first["history_replayed"]
      assert M.replay(File.join(out,report["rows"].first["recipe"]))[:exact]
      assert_raises(RuntimeError){W.main(args.dup)}
      assert_raises(RuntimeError){W.main(["--output",File.join(root,"bad"),"--moves","invalid",source])}
      refute File.exist?(File.join(root,"bad"))
      assert_raises(RuntimeError){W.main(["--output",File.join(root,"duplicate"),source,source])}
      refute File.exist?(File.join(root,"duplicate"))
      screened = File.join(root,"screened")
      capture_io { W.main(["--output",screened,"--moves","kernel","--rounds","2","--screen-before-verify",source]) }
      fast = JSON.parse(File.read(File.join(screened,"report.json")))
      assert_equal "winner",fast["rows"].first["verification"]
      assert_equal report["rows"].first["result_sha256"],fast["rows"].first["result_sha256"]
      assert_raises(RuntimeError){W.main(["--output",File.join(root,"bad-policy"),"--moves","swap","--screen-before-verify",source])}
      refute File.exist?(File.join(root,"bad-policy"))
      paired = File.join(root,"paired")
      capture_io { W.main(["--output",paired,"--moves","kernel","--rounds","2","--screen-before-verify","--kernel-pair-width","4",source]) }
      pair_report = JSON.parse(File.read(File.join(paired,"report.json")))
      assert pair_report["complete"]
      assert_operator pair_report["rows"].first["pair_checks"],:>,0
      assert M.replay(File.join(paired,pair_report["rows"].first["recipe"]))[:exact]
      assert_raises(RuntimeError){W.main(["--output",File.join(root,"bad-pair"),"--moves","swap","--kernel-pair-width","4",source])}
      refute File.exist?(File.join(root,"bad-pair"))
    end
  end

  def test_history_replay_rejects_wrong_score
    parent = B.load_scheme(File.expand_path("../lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt",__dir__))
    allocation = [[1,2],[2,1],[1,2]]
    _,_,leaves = M.compose(parent,allocation,library:B::Library.new([parent]))
    slot = leaves.index{|leaf|leaf && leaf.shape[0]>1}
    word = [[0,0,1]]
    changed = leaves.dup
    changed[slot] = M.transvection_word(changed[slot],word)
    state, = M.compose(parent,allocation,leaves:changed)
    result = {leaves:changed,history:[{kind:"kernel",slot:slot,word:word,
      from:leaves[slot].canonical_id,to:changed[slot].canonical_id,
      rank:state.rank,density:state.audit[:density]}]}
    W.replay_history(parent,allocation,leaves,result)
    bad = result.merge(history:result[:history].map(&:dup))
    bad[:history].first[:rank] += 1
    assert_raises(RuntimeError){W.replay_history(parent,allocation,leaves,bad)}
  end

  def test_paired_history_rejects_mismatched_component_words
    parent = B.naive([1,1,1])
    leaf = B.naive([2,2,2])
    components = [{kind:"kernel",axis:0,word:[[0,0,1]]},{kind:"kernel",axis:1,word:[[1,1,0]]}]
    word = components.flat_map{|a|a[:word]}
    image = M.transvection_word(leaf,word)
    result = {leaves:[image],history:[{kind:"kernel_pair",slot:0,components:components,word:word,
      from:leaf.canonical_id,to:image.canonical_id,rank:image.rank,density:image.audit[:density]}]}
    W.replay_history(parent,[[2],[2],[2]],[leaf],result)
    result[:history].first[:word] = word.reverse
    assert_raises(RuntimeError){W.replay_history(parent,[[2],[2],[2]],[leaf],result)}
  end
end
