#!/usr/bin/env ruby
require "minitest/autorun"
require "tmpdir"
require_relative "../tools/composition_closure"

class CompositionClosureTest < Minitest::Test
  B = MetaflipBudProducts
  C = MetaflipCompositionClosure

  def test_candidate_rank_gain_propagates_and_every_output_replays
    source = File.expand_path("../lib/metaflip/seeds/gf2", __dir__)
    strassen = B.load_scheme(File.join(source, "matmul_2x2_rank7_strassen_gf2.txt"))
    rank47 = B.load_scheme(File.join(source, "matmul_4x4_rank47_d450_gf2.txt"))
    Dir.mktmpdir("closure-test") do |root|
      library = File.join(root, "library")
      Dir.mkdir(library)
      File.write(File.join(library, "matmul_2x2_rank7_test_gf2.txt"), strassen.source_text)
      parent = B.naive([1, 1, 1])
      group = [{ axis: nil, indices: [0] }]
      _small, first = B.export(File.join(root, "small"), parent, [4, 4, 4], group, B::Library.new([rank47]))
      _large, second = B.export(File.join(root, "large"), parent, [8, 8, 8], group, B::Library.new([]))
      args = ["--library", library, "--output", File.join(root, "out"), first, second]
      report = nil
      capture_io { report = C.main(args.dup) }
      assert_equal false, report[:record_claim]
      by_shape = report[:rows].to_h { |r| [r[:canonical_shape], r] }
      assert_equal 56, by_shape["4x4x4"][:known_block_rank]
      assert_equal 49, by_shape["4x4x4"][:known_recursive_rank]
      assert_equal 47, by_shape["4x4x4"][:augmented_recursive_rank]
      assert by_shape["4x4x4"][:candidate_beats_known]
      assert_equal 343, by_shape["8x8x8"][:known_recursive_rank]
      assert_equal 329, by_shape["8x8x8"][:augmented_recursive_rank]
      refute by_shape["8x8x8"][:candidate_beats_known]
      assert_equal :product, by_shape["8x8x8"][:augmented_plan][:kind]
      report[:rows].each do |row|
        assert B.replay(row[:known_recipe])[:exact]
        assert B.replay(row[:augmented_recipe])[:exact]
      end
      assert_raises(RuntimeError) { C.main(args.dup) }
    end
  end

  def test_invalid_arguments_and_empty_library_fail_closed
    assert_raises(RuntimeError) { C.main([]) }
    Dir.mktmpdir("closure-empty") do |root|
      error = assert_raises(RuntimeError) do
        C.main(["--library", root, "--output", File.join(root, "out"), "missing.recipe.json"])
      end
      assert_match(/empty witness library/, error.message)
      refute File.exist?(File.join(root, "out"))
    end
  end

  def test_outer_basis_recipe_is_supported_and_still_rejects_mutation
    source = File.expand_path("../lib/metaflip/seeds/gf2",__dir__)
    parent = B.load_scheme(File.join(source,"matmul_2x2_rank7_strassen_gf2.txt"))
    mod = MetaflipOuterBasisProducts
    allocation = [[1,2],[2,1],[1,2]]
    _,_,leaves = mod.compose(parent,allocation,library:B::Library.new([parent]))
    Dir.mktmpdir("closure-outer") do |root|
      expected,path = mod.export(root,parent,allocation,leaves,[3,3,3])
      assert_equal expected.terms,C.candidate_scheme(path).terms
      data = JSON.parse(File.read(path))
      data["exact_rank"] += 1
      File.write(path,JSON.generate(data))
      assert_raises(RuntimeError) { C.candidate_scheme(path) }
    end
  end

  def test_bounded_grid_propagates_gain_and_materializes_every_row
    source = File.expand_path("../lib/metaflip/seeds/gf2",__dir__)
    a = B.load_scheme(File.join(source,"matmul_2x2_rank7_strassen_gf2.txt"))
    b = B.load_scheme(File.join(source,"matmul_4x4_rank47_d450_gf2.txt"))
    known = B::Library.new([a],products:true)
    augmented = B::Library.new([a,b],products:true)
    rows = C.grid(known,augmented,maximum:8)
    assert_equal (2..8).to_a.repeated_combination(3).to_a,rows.map{|r|r[:shape]}
    by_shape = rows.to_h{|r|[r[:shape],r]}
    assert_equal [49,47,2],by_shape[[4,4,4]].values_at(:known_rank,:augmented_rank,:gain)
    assert_equal [343,329,14],by_shape[[8,8,8]].values_at(:known_rank,:augmented_rank,:gain)
    rows.each do |row|
      assert_equal row[:known_rank],known.scheme(row[:shape]).rank
      assert_equal row[:augmented_rank],augmented.scheme(row[:shape]).rank
    end
    [{minimum:0},{maximum:33},{minimum:4,maximum:3},{minimum:2.5}].each do |args|
      assert_raises(RuntimeError) { C.grid(known,augmented,**args) }
    end
    assert_raises(RuntimeError) { C.grid(augmented,known,maximum:4) }
  end

  def test_cofactor_recipe_is_a_checked_constructive_seed
    Dir.mktmpdir("closure-cofactor") do |root|
      parent = B.naive([2,1,1])
      _, product = MetaflipOuterBasisProducts.export(File.join(root,"product"), parent,
        [[1,1],[1],[1]], [B.naive([1,1,1])] * 2, [2,1,1])
      recipe = File.join(root,"merge.json")
      expected = MetaflipCofactorMergers.export_merge(recipe,product,[0,1],0)
      assert_equal expected.terms,C.candidate_scheme(recipe).terms
      data = JSON.parse(File.read(recipe))
      data["exact_rank"] -= 1
      File.write(recipe,JSON.generate(data))
      assert_raises(RuntimeError) { C.candidate_scheme(recipe) }
    end
  end

  def test_completed_grid_report_becomes_baseline_without_recrediting_old_gains
    source = File.expand_path("../lib/metaflip/seeds/gf2", __dir__)
    a = B.load_scheme(File.join(source, "matmul_2x2_rank7_strassen_gf2.txt"))
    b = B.load_scheme(File.join(source, "matmul_4x4_rank47_d450_gf2.txt"))
    Dir.mktmpdir("closure-propagate-") do |root|
      base = File.join(root, "base"); Dir.mkdir(base)
      baseline = File.join(base, "report.json")
      # Previous "new" labels must not make an input new again in this run.
      File.write(baseline, JSON.generate(complete: true, field: "GF(2)", record_claim: false,
        basis: [{ kind: "new", rank: a.rank, snapshot: B.save_snapshot(base, "snapshots", a) }]))
      _, candidate = B.export(File.join(root, "candidate"), B.naive([1,1,1]), [4,4,4],
        [{ axis: nil, indices: [0] }], B::Library.new([b]))
      out = File.join(root, "first")
      args = ["--basis-report", baseline, "--output", out, "--grid", "2:4", candidate]
      result = nil
      capture_io { result = C.main(args.dup) }
      assert_equal 10, result[:summary][:targets]
      assert_equal 1, result[:summary][:improved_prices]
      row = result[:rows].find { |r| r[:shape] == [4,4,4] }
      assert_equal [49,47,2], row.values_at(:known_rank,:augmented_rank,:gain)
      report = JSON.parse(File.read(File.join(out,"report.json")))
      assert report.fetch("complete")
      assert_equal ["base","new"], report.fetch("basis").map { |r| r.fetch("kind") }
      assert_equal 47, B.replay(File.join(out,row[:recipe]))[:rank]
      extra = JSON.parse(File.read(File.join(out,"admitted/report.json")))
      assert_equal Digest::SHA256.file(File.join(out,"report.json")).hexdigest, extra.fetch("source_report_sha256")
      assert_raises(RuntimeError) { C.main(args.dup) }
      later = File.join(root,"later")
      capture_io { result = C.propagate(later,File.join(out,"report.json"),[candidate],maximum:4) }
      assert_equal 0, result[:summary][:improved_prices]
      assert_equal 2, JSON.parse(File.read(File.join(later,"report.json"))).fetch("basis").count { |r| r.fetch("kind") == "base" }
      assert_empty JSON.parse(File.read(File.join(later,"admitted/report.json"))).fetch("rows")
      saved = File.read(baseline)
      original = C.method(:grid)
      changed = File.join(root,"changed-source")
      mutation = lambda do |known, augmented, **options|
        File.write(baseline,saved+" ")
        original.call(known,augmented,**options)
      end
      error = nil
      C.define_singleton_method(:grid,&mutation)
      begin
        capture_io do
          error = assert_raises(RuntimeError) { C.propagate(changed,baseline,[candidate],maximum:4) }
        end
      ensure
        C.define_singleton_method(:grid,&original)
      end
      assert_match(/source changed during propagation/,error.message)
      refute JSON.parse(File.read(File.join(changed,"report.json"))).fetch("complete")
      refute File.exist?(File.join(changed,"admitted/report.json"))
      File.write(baseline,saved)
      report = JSON.parse(File.read(baseline))
      report.fetch("basis").first.fetch("snapshot")["sha256"] = "0" * 64
      File.write(baseline,JSON.generate(report))
      assert_raises(RuntimeError) { C.propagate(File.join(root,"bad"),baseline,[candidate],maximum:4) }
      refute File.exist?(File.join(root,"bad"))
    end
  end

  def test_extra_baselines_prevent_rediscovery_credit_and_verify_every_snapshot
    source = File.expand_path("../lib/metaflip/seeds/gf2", __dir__)
    a = B.load_scheme(File.join(source, "matmul_2x2_rank7_strassen_gf2.txt"))
    b = B.load_scheme(File.join(source, "matmul_4x4_rank47_d450_gf2.txt"))
    Dir.mktmpdir("closure-reconcile-") do |root|
      reports = [a, b].each_with_index.map do |s, i|
        base = File.join(root, "base#{i}"); Dir.mkdir(base)
        path = File.join(base, "report.json")
        File.write(path, JSON.generate(complete: true, field: "GF(2)", record_claim: false,
          basis: [{ kind: "new", rank: s.rank, snapshot: B.save_snapshot(base, "snapshots", s) }]))
        path
      end
      _, candidate = B.export(File.join(root, "candidate"), B.naive([1,1,1]), [4,4,4],
        [{ axis: nil, indices: [0] }], B::Library.new([b]))
      out = File.join(root, "out")
      result = nil
      capture_io do
        result = C.main(["--basis-report", reports[0], "--extra-basis-report", reports[1],
          "--extra-basis-report", reports[1], "--output", out, "--grid", "2:4", candidate])
      end
      assert_equal 0, result[:summary][:improved_prices]
      row = result[:rows].find { |r| r[:shape] == [4,4,4] }
      assert_equal [47,47,0], row.values_at(:known_rank,:augmented_rank,:gain)
      report = JSON.parse(File.read(File.join(out, "report.json")))
      assert_equal [7,47], report.fetch("basis").select { |r| r["kind"] == "base" }.map { |r| r["rank"] }
      reports.each { |p| assert_equal Digest::SHA256.file(p).hexdigest, report.fetch("source_sha256").fetch(File.realpath(p)) }
      assert_raises(RuntimeError) do
        C.main(["--extra-basis-report", reports[1], "--output", File.join(root,"no-primary"), candidate])
      end
      corrupted = JSON.parse(File.read(reports[1]))
      corrupted.fetch("basis").first.fetch("snapshot")["sha256"] = "0" * 64
      File.write(reports[1], JSON.generate(corrupted))
      assert_raises(RuntimeError) do
        C.propagate(File.join(root,"bad-extra"), reports[0], [candidate], maximum:4,
          additional_basis_reports:[reports[1]])
      end
      refute File.exist?(File.join(root,"bad-extra"))
    end
  end
end
