require "minitest/autorun"
require "tmpdir"
require_relative "../tools/outer_cofactor_join"

class OuterCofactorJoinTest < Minitest::Test
  B = MetaflipBudProducts
  M = MetaflipOuterBasisProducts
  C = MetaflipCofactorMergers
  J = MetaflipOuterCofactorJoin

  def test_finite_study_roundtrip_and_input_guards
    path = File.expand_path("../lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt", __dir__)
    seed = B.load_scheme(path)
    parent = M.gl2_image(M.gl2_image(seed, 1, 1), 2, 2)
    allocation = [[1, 2], [1, 2], [2, 1]]
    _, _, leaves = M.compose(parent, allocation, library: B::Library.new([seed]))
    Dir.mktmpdir("metaflip-cofactor-study-") do |root|
      _, recipe = M.export(File.join(root, "input"), parent, allocation, leaves, [3, 3, 3])
      out = File.join(root, "output")
      rows = nil
      capture_io { rows = J.run(out, [recipe], maximum: 2, pair_width: 2, triple_width: 2) }
      assert_equal 1, rows.length
      report = JSON.parse(File.read(File.join(out, "report.json")))
      assert report.fetch("complete")
      refute report.fetch("record_claim")
      assert_equal 2,report.fetch("kernel_triple_width")
      rows.first.fetch(:cases).each do |row|
        replay = C.replay(File.join(out, row.fetch(:merge_recipe)))
        assert_equal row.fetch(:rank), replay.fetch(:rank)
        assert_operator row.fetch(:rank), :<=, rows.first.fetch(:initial_rank)
      end
      improved = nil
      capture_io do
        improved = J.run(File.join(root, "compressed"), [recipe], maximum: 2,
          pair_width: 2, triple_width: 2, compression_width: 3, compression_slack: 2)
      end
      improved.first.fetch(:cases).zip(rows.first.fetch(:cases)).each do |row, control|
        detail = row.fetch(:postcompression)
        assert_operator row.fetch(:rank), :<=, control.fetch(:rank)
        assert_operator detail.fetch(:assessments).length, :<=, 9
        assert_equal [row.fetch(:rank), row.fetch(:density)], detail[:assessments][detail[:selected]].values_at(:rank, :density)
        refute detail.fetch(:exhaustive_final_rank)
        assert_equal row.fetch(:rank), C.replay(File.join(root, "compressed", row.fetch(:merge_recipe))).fetch(:rank)
      end
      assert_raises(RuntimeError) { J.run(out, [recipe]) }
      assert_raises(RuntimeError) { J.run(File.join(root, "new"), [recipe, recipe]) }
      assert_raises(RuntimeError) { J.run(File.join(root, "new"), [recipe], pair_width: 33) }
      assert_raises(RuntimeError) { J.run(File.join(root, "new"), [recipe], triple_width: 17) }
      assert_raises(RuntimeError) { J.run(File.join(root, "new"), [recipe], maximum: 0) }
      assert_raises(RuntimeError) { J.run(File.join(root, "new"), [recipe], compression_width: 0) }
      assert_raises(RuntimeError) { J.run(File.join(root, "new"), [recipe], compression_slack: 17) }
      assert_raises(RuntimeError) { J.run(File.join(root, "new"), []) }
      original = C.method(:best_pair)
      C.define_singleton_method(:best_pair) do |*args|
        File.open(recipe, "a") { |f| f.puts }
        original.call(*args)
      end
      begin
        capture_io do
          error = assert_raises(RuntimeError) { J.run(File.join(root, "changed"), [recipe], maximum: 2) }
          assert_equal "source changed", error.message
        end
        refute JSON.parse(File.read(File.join(root, "changed", "report.json"))).fetch("complete")
      ensure
        C.define_singleton_method(:best_pair, original)
      end
    end
  end
end
