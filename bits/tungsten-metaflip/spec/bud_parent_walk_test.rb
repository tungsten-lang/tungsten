#!/usr/bin/env ruby
require "minitest/autorun"
require "open3"
require "tmpdir"
require_relative "../tools/bud_products"

class BudParentWalkTest < Minitest::Test
  B = MetaflipBudProducts

  def setup
    @binary = ENV["METAFLIP_BUD_WALK_BINARY"]
    skip "Set METAFLIP_BUD_WALK_BINARY to the freshly built native tool" unless @binary
    assert File.executable?(@binary), "native tool must exist and be executable"
    @bit = File.expand_path("..", __dir__)
    @parent = File.join(@bit, "lib/metaflip/seeds/gf2/matmul_2x2x5_rank18_d84_gf2.txt")
  end

  def command(output)
    [RbConfig.ruby, File.join(@bit, "tools/bench_bud_parents.rb"),
     "--binary", @binary, "--parent", @parent, "--scale", "2x2x1",
     "--output", output, "--trials", "2", "--chunks", "8", "--steps", "128"]
  end

  def test_matched_accounting_exact_replay_repeatability_and_overwrite_refusal
    Dir.mktmpdir("bud-parent-test") do |root|
      reports = %w[first second].map do |name|
        directory = File.join(root, name)
        output, status = Open3.capture2e(*command(directory))
        assert status.success?, output
        report = JSON.parse(File.read(File.join(directory, "report.json")))
        assert_equal false, report.fetch("record_claim")
        assert_equal %w[walk greedy anneal], report.fetch("arms").map { |a| a.fetch("mode") }
        report.fetch("arms").each do |arm|
          assert_equal 2048, arm.fetch("totals").fetch("attempted").to_i
          assert_operator arm.fetch("totals").fetch("accepted_chunks").to_i, :<=, 16
          assert_equal 2, arm.fetch("trials").length
          arm.fetch("trials").each do |trial|
            audit = B.replay(trial.fetch("recipe"))
            assert audit.fetch(:exact)
            assert_equal "4x4x5", audit.fetch(:shape)
            assert_equal trial.fetch("exact_product_rank"), audit.fetch(:rank)
            assert_operator audit.fetch(:rank), :<=, trial.fetch("score")
          end
        end
        report
      end
      identities = reports.map do |report|
        report.fetch("arms").map do |arm|
          [arm.fetch("mode"), arm.fetch("trials").map do |trial|
            trial.values_at("score", "exact_product_rank", "parent_id", "chunks_accepted")
          end]
        end
      end
      assert_equal identities[0], identities[1]
      path = File.join(root, "first", "report.json")
      before = File.binread(path)
      output, status = Open3.capture2e(*command(File.join(root, "first")))
      refute status.success?
      assert_includes output, "output must be new or empty"
      assert_equal before, File.binread(path)
    end
  end

  def test_native_gate_rejects_invalid_prices_mode_and_tensor
    Dir.mktmpdir("bud-parent-gates") do |root|
      table = File.join(root, "prices.txt")
      File.write(table, (["20"] + 3.times.map { (0..20).to_a.join(" ") }).join("\n") + "\n")
      base = [@binary, @parent, "2x2x5", table, "1", "1", "1", "walk", "17", root, "2"]
      invalid_mode = base.dup
      invalid_mode[7] = "unknown"
      output, status = Open3.capture2e(*invalid_mode)
      refute status.success?
      assert_includes output, "invalid strategy"
      invalid_debt = base.dup
      invalid_debt[10] = "9"
      output, status = Open3.capture2e(*invalid_debt)
      refute status.success?
      assert_includes output, "invalid shape or search budget"
      [-1, 1025].each do |slack|
        output, status = Open3.capture2e(*(base + [slack.to_s]))
        refute status.success?
        assert_includes output, "invalid shape or search budget"
      end
      malformed = File.read(table).sub("0 1", "0 0")
      File.write(table, malformed)
      output, status = Open3.capture2e(*base)
      refute status.success?
      assert_includes output, "invalid bucket price"
      File.write(table, (["20"] + 3.times.map { (0..20).to_a.join(" ") }).join("\n") + "\n")
      rows = B.load_scheme(@parent).terms.map(&:dup)
      rows.first[0] ^= (rows.first[0] == 1 ? 2 : 1) # wrong tensor, still a nonzero in-width mask
      corrupt = File.join(root, "corrupt.txt")
      File.write(corrupt, B.text(rows))
      base[1] = corrupt
      output, status = Open3.capture2e(*base)
      refute status.success?
      assert_includes output, "invalid seed"
      refute File.exist?(File.join(root, "trial-0.txt"))
    end
  end

  def test_offline_public_shapes_and_parent_only_reports
    Dir.mktmpdir("bud-public-parent-test") do |root|
      [[2,2,13], [2,3,7], [2,4,8], [3,4,11], [4,4,10], [7,8,7]].each do |shape|
        label = shape.join("x")
        parent = B.naive(shape)
        path = File.join(root,"matmul_#{label}_rank#{parent.rank}_test_gf2.txt")
        File.write(path,parent.source_text)
        directory = File.join(root,label)
        cmd = command(directory)
        cmd[cmd.index("--parent")+1] = path
        cmd[cmd.index("--scale")+1] = "1x1x1"
        cmd += ["--parents-only", "--observe-every", "32"]
        output, status = Open3.capture2e(*cmd)
        assert status.success?, output
        report = JSON.parse(File.read(File.join(directory,"report.json")))
        report.fetch("arms").each do |arm|
          assert_equal false, arm.fetch("products_materialized")
          refute arm.key?("best_exact_product_rank")
          refute File.exist?(File.join(directory,arm.fetch("mode"),"products"))
          arm.fetch("trials").each do |trial|
            refute trial.key?("recipe")
            refute trial.key?("exact_product_rank")
            assert trial.fetch("parent").fetch("exact")
            assert trial.fetch("end_parent").fetch("exact")
            assert_operator trial.fetch("score"), :<=, parent.rank
          end
        end
      end
    end
  end

  def test_offline_import_rejects_partial_mutated_and_out_of_width_tensors
    Dir.mktmpdir("bud-offline-gates") do |root|
      table = File.join(root,"prices.txt")
      File.write(table, (["54"] + 3.times.map { (0..54).to_a.join(" ") }).join("\n")+"\n")
      source = File.join(root,"seed.txt")
      cmd = [@binary,source,"2x2x13",table,"1","1","8","walk","17",root,"2"]
      good = B.naive([2,2,13])
      mutant = good.terms.map(&:dup)
      mutant[0][0] ^= 2
      high = good.terms.map(&:dup)
      high[0][1] = 1 << 26
      ["", "52\n", B.text(good.terms[0...-1]), B.text(mutant), B.text(high), good.source_text+"1 1 1\n"].each do |text|
        File.write(source,text)
        output,status = Open3.capture2e(*cmd)
        refute status.success?, output
        assert_includes output,"invalid seed"
        refute File.exist?(File.join(root,"trial-0.txt"))
      end
    end
  end

  def test_weighted_portfolio_is_not_reported_as_one_tensor_rank
    Dir.mktmpdir('bud-portfolio-test') do |root|
      path=File.join(root,'portfolio.json')
      cases=[{scale:[2,2,1],weight:2},{scale:[3,3,1],weight:1}]
      File.write(path,JSON.generate(cases))
      cmd=command(File.join(root,'result'))
      cmd.slice!(cmd.index('--scale'),2)
      cmd+=['--portfolio',path,'--parents-only','--observe-every','32']
      output,status=Open3.capture2e(*cmd)
      assert status.success?,output
      report=JSON.parse(File.read(File.join(root,'result','report.json')))
      assert_equal cases.map{|c|c.transform_keys(&:to_s)},report.fetch('portfolio')
      assert_equal 'weighted-common-axis-portfolio-cost-not-a-tensor-rank',report.fetch('score_kind')
      assert_equal Digest::SHA256.file(path).hexdigest,report.fetch('portfolio_source_sha256')
      rows=File.readlines(File.join(root,'result','prices.txt')).drop(1).map{|r|r.split.map(&:to_i)}
      report.fetch('arms').each do |arm|
        assert_equal false,arm.fetch('products_materialized')
        arm.fetch('trials').each do |trial|
          parent=B.load_scheme(File.join(root,'result',arm['mode'],"trial-#{trial['trial']}.txt"),[2,2,5])
          score=3.times.map{|a|parent.terms.group_by{|t|t[a]}.values.sum{|group|rows[a][group.size]}}.min
          assert_equal score,trial.fetch('score')
          refute trial.key?('exact_product_rank')
        end
      end
      bad_cases=[[],[{scale:[0,2,1],weight:1}],[{scale:[2,2,1],weight:0}],cases+[cases[0]]]
      bad_cases.each_with_index do |data,i|
        File.write(path,JSON.generate(data))
        bad=cmd.dup;bad[bad.index('--output')+1]=File.join(root,"bad-#{i}")
        output,status=Open3.capture2e(*bad)
        refute status.success?,output
        refute File.exist?(File.join(root,"bad-#{i}",'report.json'))
      end
    end
  end

  def test_explicit_density_slack_is_replayable_and_default_is_preserved
    Dir.mktmpdir("bud-parent-density") do |root|
      reports = [4, 16].map do |slack|
        output, status = Open3.capture2e(*(command(File.join(root, slack.to_s)) + ["--density-slack", slack.to_s]))
        assert status.success?, output
        report = JSON.parse(File.read(File.join(root, slack.to_s, "report.json")))
        assert_equal slack, report.fetch("options").fetch("density_slack")
        report.fetch("arms").each do |arm|
          assert_equal slack, arm.fetch("totals").fetch("density_slack").to_i
          assert_operator arm.fetch("totals").fetch("sampled_peak_rank").to_i, :>=, 18
          arm.fetch("trials").each { |t| assert B.replay(t.fetch("recipe"))[:exact] }
        end
        report
      end
      # Old ten-argument native invocations keep the original slack of four.
      original = reports.first.fetch("arms").first
      explicit = File.join(root, "explicit-four")
      Dir.mkdir(explicit)
      args = original.fetch("command").dup
      args[-2] = explicit
      output, status = Open3.capture2e(*(args + ["4"]))
      assert status.success?, output
      assert_includes output, "density_slack=4"
      2.times do |i|
        assert_equal File.binread(File.join(original.fetch("command")[-2], "trial-#{i}.txt")),
                     File.binread(File.join(explicit, "trial-#{i}.txt"))
      end
    end
  end

  def test_observation_cadence_preserves_walk_and_greedy_trajectories
    Dir.mktmpdir("bud-parent-cadence") do |root|
      reports = [128, 7, 1].map do |interval|
        # Cross the 2000-attempt split cadence and test a partial final span.
        cmd = command(File.join(root, interval.to_s)) + ["--chunks", "24", "--observe-every", interval.to_s]
        output, status = Open3.capture2e(*cmd)
        assert status.success?, output
        report = JSON.parse(File.read(File.join(root, interval.to_s, "report.json")))
        report.fetch("arms").each do |arm|
          assert_equal 6144, arm.fetch("totals").fetch("attempted").to_i
          assert_equal 48 * ((128 + interval - 1) / interval), arm.fetch("totals").fetch("observations").to_i
          arm.fetch("trials").each { |t| assert B.replay(t.fetch("recipe"))[:exact] }
        end
        report
      end
      [0, 1].each do |arm_index|
        baseline = reports.first.fetch("arms")[arm_index]
        reports.drop(1).each do |report|
          arm = report.fetch("arms")[arm_index]
          assert_equal baseline.fetch("totals").fetch("accepted_flips"), arm.fetch("totals").fetch("accepted_flips")
          assert_equal baseline.fetch("trials").map { |t| t.fetch("end_parent").fetch("sha256") },
                       arm.fetch("trials").map { |t| t.fetch("end_parent").fetch("sha256") }
        end
        # Every-attempt observation contains every coarse endpoint.
        assert_operator reports.last.fetch("arms")[arm_index].fetch("best_score"), :<=, baseline.fetch("best_score")
      end
      output, status = Open3.capture2e(*(command(File.join(root, "bad")) + ["--observe-every", "129"]))
      refute status.success?
      assert_includes output, "invalid observation interval"
    end
  end

  def test_square_parent_and_grid_objective_match_ruby_and_replay
    Dir.mktmpdir("bud-square-grid") do |root|
      parent = File.join(root, 'matmul_2x2x2_rank8_test_gf2.txt')
      File.write(parent, B.text(B.naive([2, 2, 2]).terms))
      [false, true].each do |grids|
        args = command(File.join(root, grids ? 'grids' : 'buckets'))
        args[args.index('--parent') + 1] = parent
        args[args.index('--scale') + 1] = '3x2x3'
        args += ['--grids', '--recursive-products'] if grids
        output, status = Open3.capture2e(*args)
        assert status.success?, output
        report = JSON.parse(File.read(File.join(root, grids ? 'grids' : 'buckets', 'report.json')))
        assert_equal 112, report['initial_score'] if grids
        report['arms'].each do |arm|
          assert_equal 2048, arm['totals']['attempted'].to_i
          arm['trials'].each do |trial|
            assert B.replay(trial['recipe'])[:exact]
            assert_operator trial['exact_product_rank'], :<=, trial['score']
          end
        end
      end
    end
  end

  def test_holdout_literals_are_rejoined_before_scoring_and_export
    Dir.mktmpdir("bud-parent-holdout") do |root|
      reports = %w[first second].map do |name|
        args = command(File.join(root, name)) + ["--holdout-indices", "0,1", "--chunks", "24", "--observe-every", "7"]
        output, status = Open3.capture2e(*args)
        assert status.success?, output
        report = JSON.parse(File.read(File.join(root, name, 'report.json')))
        assert_equal B.load_scheme(@parent).terms.values_at(0, 1), report.fetch('holdout').fetch('terms')
        report.fetch('arms').each do |arm|
          assert_equal '2', arm.fetch('totals').fetch('held_terms')
          assert_equal '6144', arm.fetch('totals').fetch('attempted')
          arm.fetch('trials').each { |t| assert B.replay(t.fetch('recipe'))[:exact] }
        end
        report
      end
      ids = reports.map { |r| r.fetch('arms').map { |a| a.fetch('trials').map { |t| t.values_at('score', 'parent_id', 'end_parent') } } }
      # End audits contain run-local paths; compare tensor hashes instead.
      ids.each { |arms| arms.each { |trials| trials.each { |t| t[2] = t[2].fetch('sha256') } } }
      assert_equal ids[0], ids[1]
      %w[0,0 99].each do |indices|
        output, status = Open3.capture2e(*(command(File.join(root, 'invalid')) + ['--holdout-indices', indices]))
        refute status.success?
        assert_includes output, 'invalid holdout indices'
      end
      base = reports.first.fetch('arms').first.fetch('command').dup
      duplicate = File.join(root, 'duplicate.txt')
      term = reports.first.fetch('holdout').fetch('terms').first
      File.write(duplicate, B.text([term, term]))
      base[-1] = duplicate
      output, status = Open3.capture2e(*base)
      refute status.success?
      assert_includes output, 'holdout terms must be distinct literal seed terms'
    end
  end

  def test_square_holdout_uses_the_square_engine_and_full_output_gate
    Dir.mktmpdir('bud-square-holdout') do |root|
      parent = File.join(root, 'matmul_2x2x2_rank8_test_gf2.txt')
      File.write(parent, B.text(B.naive([2, 2, 2]).terms))
      args = command(File.join(root, 'run'))
      args[args.index('--parent') + 1] = parent
      args[args.index('--scale') + 1] = '3x3x3'
      args += ['--holdout-indices', '0,1,2,3', '--chunks', '24', '--observe-every', '7', '--grids']
      output, status = Open3.capture2e(*args)
      assert status.success?, output
      report = JSON.parse(File.read(File.join(root, 'run', 'report.json')))
      report.fetch('arms').each do |arm|
        assert_equal '4', arm.fetch('totals').fetch('held_terms')
        assert_equal '6144', arm.fetch('totals').fetch('attempted')
        arm.fetch('trials').each { |t| assert B.replay(t.fetch('recipe'))[:exact] }
      end
    end
  end

  def test_read_only_observers_match_separate_runs_without_extra_flips
    Dir.mktmpdir('bud-sidecar-observers') do |root|
      limit = 20
      primary = Array.new(3) { (0..limit).to_a }
      secondary = (0...8).map do |observer|
        3.times.map { |axis| (0..limit).map { |k| (11+observer)*k - (axis==observer%3 ? 3*(k/2) : 0) } }
      end
      parse = ->(output, label) { output.lines.grep(/^#{label} /).map { |line| line.split.drop(1).to_h { |w| w.split('=',2) } } }
      run = lambda do |name, prices, observers|
        directory = File.join(root,name)
        Dir.mkdir(directory)
        rows = [limit.to_s] + prices.map { |r|r.join(' ') }
        rows += ["observers #{observers.size}"] + observers.flatten(1).map { |r|r.join(' ') } unless observers.empty?
        table = File.join(directory,'prices.txt')
        File.write(table,rows.join("\n")+"\n")
        output,status = Open3.capture2e(@binary,@parent,'2x2x5',table,'2','16','128','walk','910701',directory,'2','4','16')
        assert status.success?,output
        [directory,parse.call(output,'BUD_TRIAL'),parse.call(output,'BUD_RESULT').fetch(0),parse.call(output,'BUD_OBSERVER')]
      end
      alone = [primary,*secondary].each_with_index.map { |table,i| run.call("single-#{i}",table,[]) }
      together = run.call('together',primary,secondary)
      assert_equal [],alone[0][3]
      assert_equal 2*secondary.size,together[3].size
      %w[attempted accepted_flips accepted_chunks observations].each do |key|
        alone.each { |result| assert_equal result[2][key],together[2][key] }
      end
      assert_equal '4096',together[2]['attempted']
      2.times do |trial|
        assert_equal File.binread(File.join(alone[0][0],"trial-#{trial}.txt")),File.binread(File.join(together[0],"trial-#{trial}.txt"))
        alone.each do |result|
          assert_equal File.binread(File.join(result[0],"end-#{trial}.txt")),File.binread(File.join(together[0],"end-#{trial}.txt"))
        end
        secondary.each_index do |observer|
          entry = together[3].find { |r|r['observer']==observer.to_s && r['trial']==trial.to_s }
          assert_equal alone[observer+1][1][trial].slice('score','rank','bits','best_at'),entry.slice('score','rank','bits','best_at')
          expected = File.binread(File.join(alone[observer+1][0],"trial-#{trial}.txt"))
          actual = File.join(together[0],"observer-#{observer}-trial-#{trial}.txt")
          assert_equal expected,File.binread(actual)
          assert B.load_scheme(actual,[2,2,5]).audit[:exact]
        end
      end
    end
  end

  def test_batched_observer_scores_above_rank_64_match_direct_bucket_sums
    Dir.mktmpdir('bud-large-observers') do |root|
      [[3,4,11],[5,5,5]].each do |shape|
        parent = B.naive(shape)
        source = File.join(root,shape.join('x')+'.txt')
        File.write(source,parent.source_text)
        directory = File.join(root,shape.join('x'))
        Dir.mkdir(directory)
        limit = parent.rank+2
        tables = 8.times.map do |observer|
          3.times.map { |axis| (0..limit).map { |k| (observer+5)*k-(axis==observer%3 ? k/2 : 0) } }
        end
        lines = [limit.to_s]+Array.new(3) { (0..limit).to_a.join(' ') }+['observers 8']
        lines += tables.flatten(1).map { |row|row.join(' ') }
        prices = File.join(directory,'prices')
        File.write(prices,lines.join("\n")+"\n")
        output,status = Open3.capture2e(@binary,source,shape.join('x'),prices,'1','2','32','walk','817',directory,'2','4','1')
        assert status.success?,output
        rows = output.lines.grep(/^BUD_OBSERVER /).map { |line|line.split.drop(1).to_h { |word|word.split('=',2) } }
        assert_equal 8,rows.size
        rows.each do |row|
          observer = row.fetch('observer').to_i
          value = B.load_scheme(File.join(directory,"observer-#{observer}-trial-0.txt"),shape)
          expected = 3.times.map do |axis|
            value.terms.group_by { |term|term[axis] }.values.sum { |group|tables[observer][axis].fetch(group.size) }
          end.min
          assert_equal expected,row.fetch('score').to_i
          assert_equal value.rank,row.fetch('rank').to_i
          assert value.audit[:exact]
        end
      end
    end
  end

  def test_observer_tables_fail_closed
    Dir.mktmpdir('bud-observer-gates') do |root|
      table = File.join(root,'prices.txt')
      lines = ['20'] + Array.new(3) { (0..20).to_a.join(' ') }
      valid = lines + ['observers 1'] + lines.drop(1)
      args = [@binary,@parent,'2x2x5',table,'1','1','1','walk','17',root,'2','4','1']
      [lines+['observers 2']+lines.drop(1), lines+['observers 0']+lines.drop(1),
       lines+['observers 9']+lines.drop(1)*9,
       valid[0...-1]+['0 1'], valid[0...-1]+[(0..20).map { |i|i==1 ? -1 : i }.join(' ')]].each do |bad|
        File.write(table,bad.join("\n")+"\n")
        output,status = Open3.capture2e(*args)
        refute status.success?,output
        assert_includes output,'invalid observer'
        refute File.exist?(File.join(root,'trial-0.txt'))
      end
      File.write(table,valid.join("\n")+"\n")
      incompatible = args.dup;incompatible[7]='greedy'
      output,status = Open3.capture2e(*incompatible)
      refute status.success?,output
      assert_includes output,'invalid observer layout or strategy'
      output,status = Open3.capture2e(*(args+['not-a-holdout.txt']))
      refute status.success?,output
      assert_includes output,'invalid observer layout or strategy'
      kept = File.join(root,'observer-0-trial-0.txt')
      File.write(kept,'keep')
      output,status = Open3.capture2e(*args)
      refute status.success?,output
      assert_includes output,'refusing to overwrite observer output'
      assert_equal 'keep',File.read(kept)
    end
  end

  def test_fixed_elementary_holdout_prices_a_witness_and_supports_rank_above_64
    Dir.mktmpdir('bud-fixed-elementary') do |root|
      [[2,2,2],[2,3,12]].each do |shape|
        parent=B.naive(shape)
        path=File.join(root,"matmul_#{shape.join('x')}_rank#{parent.rank}_test_gf2.txt")
        File.write(path,parent.source_text)
        held=[0,1].product([0,1]).map do |j,k|
          parent.terms.index([1<<j,1<<(j*shape[2]+k),1<<k])
        end
        directory=File.join(root,shape.join('x'))
        args=command(directory)
        args[args.index('--parent')+1]=path
        args[args.index('--scale')+1]='3x2x3'
        args+=['--holdout-indices',held.join(','),'--holdout-shape','1x2x2',
               '--recursive-products','--observe-every','7']
        args<<'--parents-only' if parent.rank>64
        output,status=Open3.capture2e(*args)
        assert status.success?,output
        report=JSON.parse(File.read(File.join(directory,'report.json')))
        assert_equal 54,report.fetch('holdout').fetch('cost')
        assert_equal 112,report.fetch('initial_score') if parent.rank==8
        report['arms'].each do |arm|
          assert_equal '54',arm['totals']['held_cost']
          arm['trials'].each do |t|
            assert t['parent']['exact']
            assert B.replay(t['recipe'])[:exact] if t['recipe']
          end
        end
        bad=args.dup;bad[bad.index('--output')+1]=File.join(root,'bad-'+shape.join('x'))
        bad[bad.index('--holdout-shape')+1]='2x2x1'
        output,status=Open3.capture2e(*bad)
        refute status.success?,output
        assert_includes output,'inconsistent elementary factor map'
        # The native price is a caller-supplied number; the Ruby adapter binds
        # it to an exact leaf tensor. Malformed native numeric inputs fail.
        native=report['arms'].first['command'].dup
        native[-1]='0'
        output,status=Open3.capture2e(*native)
        refute status.success?,output
        assert_includes output,'invalid verified holdout cost'
      end
    end
  end
end
