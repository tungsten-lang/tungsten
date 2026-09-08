require 'minitest/autorun'
require 'tmpdir'
require_relative '../tools/scan_parent_covers'

class ScanParentCoversTest < Minitest::Test
  S = MetaflipParentCoverScan
  B = MetaflipBudProducts
  P = MetaflipBudPackings

  def setup
    @root = Dir.mktmpdir('metaflip-cover-command-')
    parent = B.naive([2,2,2])
    path = File.join(@root, 'seed.txt'); File.write(path, parent.source_text)
    identity = Digest::SHA256.hexdigest("2x2x2\n" + parent.terms.sort.map { |t| t.join(' ') + "\n" }.join)
    @entry = {shape: [2,2,2], path: path, rank: 8, sha256: Digest::SHA256.file(path).hexdigest,
      identity: identity, signature: [[2]*4]*3, mixed_partitions: []}
    @inputs = {complete: true, field: 'GF(2)', record_claim: false, parents: [@entry]}
    shapes = (1..4).to_a.repeated_combination(3).to_a
    @plan = {complete: true, field: 'GF(2)', record_claim: false, model_shapes: shapes,
      baseline_recipes: shapes.map { |s| {rank: s.reduce(:*)} }}
    write_inputs
    @options = {inputs: @root+'/inputs.json', plan: @root+'/report.json', output: @root+'/scan',
      families: {[2,2,2] => :all}, max_leaf: 2, progress: nil}
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def write_inputs
    File.write(@root+'/inputs.json', JSON.generate(@inputs))
    File.write(@root+'/report.json', JSON.generate(@plan))
  end

  def test_selection_is_explicit_and_preserves_cover_controls
    entries = JSON.parse(JSON.generate([@entry, @entry, @entry, @entry]))
    entries[0]['mixed_partitions'] = [[{axis: 0, indices: [0]}]]
    entries[2]['signature'] = [[8], [8], [8]]
    selected, summary = S.select_parents(entries, {[2,2,2] => :sample})
    assert_equal [0,2,3], selected.map(&:first)
    assert_equal({shape: [2,2,2], family_parents: 4, selected_parents: 3, sampling_only: true}, summary.first)
    assert_equal [0,1,2,3], S.select_parents(entries, {[2,2,2] => :all}).first.map(&:first)
    assert_raises(RuntimeError) { S.select_parents(entries, {}) }
    assert_raises(RuntimeError) { S.select_parents(entries, {[1,1,1] => :all}) }
    assert_raises(RuntimeError) { S.select_parents(entries, {[2,2,2] => :dominated}) }
  end

  def test_complete_scan_pins_inputs_and_saves_replayable_literal_order
    r = S.run(**@options)
    assert r[:complete]
    assert r[:all_cases_attempted]
    assert r[:all_exact_within_model]
    assert_equal [1,1], r.values_at(:requested_parents, :requested_cases)
    assert_equal 8, r[:rows].first[:rank]
    assert_empty r[:direct_improvements]
    refute r[:record_claim]
    refute r[:gpu_used]
    assert_equal 1, r[:workers]
    assert_equal @entry[:sha256], r[:source_sha256][@entry[:path]]
    assert_equal Digest::SHA256.file(@options[:plan]).hexdigest, r[:source_sha256][File.realpath(@options[:plan])]
    assert_equal JSON.parse(JSON.generate(r)), JSON.parse(File.read(@options[:output]+'/report.json'))
    assert_raises(RuntimeError) { S.run(**@options) }
  end

  def test_campaign_budget_is_not_reported_as_an_exhaustion
    calls = 0
    r = S.run(**@options.merge(max_leaf: 4, clock: -> { calls += 1; calls > 4 ? 1000 : 0 }))
    assert r[:complete]
    assert_equal 8, r[:requested_cases]
    assert_equal 1, r[:rows].size
    refute r[:all_cases_attempted]
    refute r[:all_exact_within_model]
  end

  def test_case_timeout_retains_no_false_cover_or_price
    fake = Object.new
    def fake.solve(*); raise Timeout::Error; end
    def fake.stats; {hits: 0, misses: 1}; end
    original = P::ContextCache.method(:new)
    P::ContextCache.define_singleton_method(:new) { |*args, **kwargs| fake }
    begin
      r = S.run(**@options)
      assert r[:all_cases_attempted]
      refute r[:all_exact_within_model]
      row = r[:rows].first
      assert row[:timed_out]
      refute row[:improved]
      assert_empty row.keys & %i[rank packing cover]
      assert_empty r[:parents].first[:covers]
    ensure
      P::ContextCache.define_singleton_method(:new, original)
    end
  end

  def test_source_and_identity_drift_fail_closed
    @entry[:identity] = '0'*64; write_inputs
    assert_raises(RuntimeError) { S.run(**@options) }
    refute JSON.parse(File.read(@options[:output]+'/report.json'))['complete']
    File.write(@entry[:path], 'changed')
    assert_raises(RuntimeError) { S.run(**@options.merge(output: @root+'/scan2')) }
  end

  def test_price_plan_mutation_during_search_cannot_seal_report
    actual = P::ContextCache.new(B.naive([2,2,2]), max_leaf: 2, grids: true, grid_side: 4)
    path = @options[:plan]
    fake = Object.new
    fake.define_singleton_method(:solve) do |*args|
      result = actual.solve(*args)
      File.write(path, File.read(path) + "\n")
      result
    end
    fake.define_singleton_method(:stats) { actual.stats }
    original = P::ContextCache.method(:new)
    P::ContextCache.define_singleton_method(:new) { |*args, **kwargs| fake }
    begin
      error = assert_raises(RuntimeError) { S.run(**@options) }
      assert_match(/source changed during scan/, error.message)
      refute JSON.parse(File.read(@options[:output]+'/report.json'))['complete']
    ensure
      P::ContextCache.define_singleton_method(:new, original)
    end
  end

  def test_invalid_prices_and_limits_fail_before_creating_output
    [-1,0,Float::INFINITY,Float::NAN].each do |seconds|
      assert_raises(RuntimeError) { S.run(**@options.merge(seconds: seconds)) }
    end
    [1,33].each { |maximum| assert_raises(RuntimeError) { S.run(**@options.merge(max_leaf: maximum)) } }
    assert_raises(RuntimeError) { S.run(**@options.merge(grid_side: 5)) }
    @plan[:baseline_recipes][0][:rank] = 0; write_inputs
    assert_raises(RuntimeError) { S.run(**@options) }
    refute File.exist?(@options[:output])
  end

  def test_grid_order_survives_cover_normalization
    g = [{elementary_shape: [1,2,2], indices: [3,1,2,0]},
      {axis: 1, indices: [9,8]}, {axis: nil, indices: [4]}]
    normal = S.normalize(g)
    assert_includes normal, {elementary_shape: [1,2,2], indices: [3,1,2,0]}
    assert_includes normal, {axis: 1, indices: [8,9]}
    assert_includes normal, {axis: 0, indices: [4]}
    assert_equal 180, S.scales([5,5,6], 32).size
    assert_equal 144, S.scales([5,5,7], 32).size
  end
end
