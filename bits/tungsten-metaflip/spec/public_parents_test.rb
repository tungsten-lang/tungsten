require "minitest/autorun"
require "tmpdir"
require_relative "../tools/bench_public_parents"

class PublicParentsTest < Minitest::Test
  B = MetaflipBudProducts
  def fixture(root, corrupt: false)
    parent = B.naive([2, 2, 3])
    public_root, closure_root = ["public", "closure"].map { |p| File.join(root, p) }
    FileUtils.mkdir_p([public_root, closure_root])
    text = parent.source_text
    if corrupt
      terms = parent.terms.map(&:dup)
      terms[0][0] ^= 1
      text = B.text(terms)
    end
    File.write(File.join(public_root, "source.txt"), text)
    common = { complete: true, field: "GF(2)", record_claim: false }
    File.write(File.join(public_root, "report.json"), JSON.generate(common.merge(schemes: [
      { gf2: "source.txt", sha256: Digest::SHA256.hexdigest(text), shape: parent.shape, rank: parent.rank }
    ])))
    control = B.orient(parent, [3, 2, 2])
    snapshot = B.save_snapshot(closure_root, "basis", control)
    rows = (2..6).to_a.repeated_combination(3).map do |shape|
      { shape: shape, augmented_rank: shape.inject(:*) }
    end
    File.write(File.join(closure_root, "report.json"), JSON.generate(common.merge(maximum: 6,
      rows: rows, basis: [{ snapshot: snapshot, rank: control.rank }])))
    ["--scout", public_root, "--closure", closure_root, "--output", File.join(root, "out"),
     "--max-scale", "2", "--max-leaf", "6", "--trials", "0"]
  end

  def test_axis_permuted_control_is_compared_in_the_same_orientation
    Dir.mktmpdir do |root|
      capture_io { MetaflipPublicParents.main(fixture(root)) }
      report = JSON.parse(File.read(File.join(root, "out/report.json")))
      assert_equal 14, report.fetch("rows").length
      assert_equal 7, report.fetch("comparisons").length
      assert report.fetch("comparisons").all? { |r| r.fetch("gain").zero? }
      assert report.fetch("parents").all? { |r| r.fetch("shape") == [2, 2, 3] }
      assert report.fetch("screen_only")
      refute report.fetch("record_claim")
      report.fetch("rows").each do |row|
        s = report.fetch("parents").fetch(row.fetch("parent"))
        parent = B.load_scheme(File.join(root, "out", s.fetch("snapshot").fetch("path")), s.fetch("shape"))
        assert B.validate_groups(parent, JSON.parse(JSON.generate(row.fetch("groups")), symbolize_names: true))
      end
    end
  end

  def test_bad_tensor_is_rejected_even_when_its_hash_matches
    Dir.mktmpdir do |root|
      assert_raises(RuntimeError) { MetaflipPublicParents.main(fixture(root, corrupt: true)) }
      refute File.exist?(File.join(root, "out/report.json"))
    end
  end

  def test_existing_output_is_not_overwritten
    Dir.mktmpdir do |root|
      argv = fixture(root)
      FileUtils.mkdir_p(File.join(root, "out"))
      assert_raises(RuntimeError) { MetaflipPublicParents.main(argv) }
    end
  end

  def test_search_candidates_are_not_labelled_as_public_schemes
    Dir.mktmpdir do |root|
      capture_io { MetaflipPublicParents.main(fixture(root) + ['--candidate-role', 'search']) }
      report = JSON.parse(File.read(File.join(root, 'out/report.json')))
      assert_equal %w[search control], report.fetch('parents').map { |r| r.fetch('role') }
      assert_equal 0, report.fetch('summary').fetch('search_better_than_control')
      refute report.fetch('summary').key?('public_better_than_control')
      assert report.fetch('comparisons').all? { |r| r.fetch('search_formula') == r.fetch('control_formula') }
    end
  end
end
