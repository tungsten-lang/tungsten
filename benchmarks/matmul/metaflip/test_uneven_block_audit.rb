require "minitest/autorun"
require "tmpdir"
require "open3"
require_relative "../../../bits/tungsten-metaflip/tools/bud_products"

class UnevenBlockAuditTest < Minitest::Test
  B = MetaflipBudProducts
  REPO = File.expand_path("../../..", __dir__)

  def setup
    @binary = ENV["METAFLIP_UNEVEN_AUDIT_BINARY"]
    skip "set METAFLIP_UNEVEN_AUDIT_BINARY to a freshly built audit binary" unless @binary
    @directory = Dir.mktmpdir("metaflip-uneven-test-")
    @outer = File.join(REPO,"bits/tungsten-metaflip/lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt")
    @leaves = (1..3).to_a.repeated_combination(3).map { |s| B.naive(s) }
    @leaves << B.naive([4,4,4]) # Unreachable from the balanced target below.
    @manifest = File.join(@directory,"leaves.txt")
    write_leaves(@leaves)
    @targets = File.join(@directory,"targets.txt")
    File.write(@targets,"3x4x5\n")
    @output = File.join(@directory,"output")
    Dir.mkdir(@output)
  end

  def teardown
    FileUtils.remove_entry(@directory) if @directory && File.directory?(@directory)
  end

  def write_leaves(leaves)
    rows = leaves.map do |leaf|
      entry = B.save_snapshot(@directory,"leaves",leaf)
      ([File.join(@directory,entry[:path])] + leaf.shape).join(" ")
    end
    File.write(@manifest,rows.join("\n")+"\n")
  end

  def run_audit(*bounds)
    Open3.capture2e(@binary,@outer,"2","2","2",@manifest,@targets,@output,*bounds,chdir:REPO)
  end

  def test_balanced_filter_preserves_exact_tensor
    output,status = run_audit
    assert status.success?, output
    assert_includes output,"selection=min-exact-formula-ties"
    assert_includes output,"leaf_pool=10"
    assert B.load_scheme(File.join(@output,"3x4x5.txt"),[3,4,5]).audit[:exact]
  end

  def test_bounded_scan_requires_complete_leaf_coverage
    output,status = run_audit("1","3")
    assert status.success?, output
    assert_includes output,"selection=first-formula-min"
    assert B.load_scheme(File.join(@output,"3x4x5.txt"),[3,4,5]).audit[:exact]
  end

  def test_missing_leaf_is_not_silently_skipped
    write_leaves([@leaves.first])
    output,status = run_audit("1","3")
    refute status.success?
    assert_includes output,"missing bounded leaf"
    assert_empty Dir.children(@output)
  end

  def test_existing_result_is_not_overwritten
    output,status = run_audit
    assert status.success?, output
    path = File.join(@output,"3x4x5.txt")
    before = File.binread(path)
    output,status = run_audit
    refute status.success?
    assert_includes output,"refusing output overwrite"
    assert_equal before,File.binread(path)
  end

  def test_allocation_bound_guard
    output,status = run_audit("1","17")
    refute status.success?
    assert_includes output,"invalid allocation bounds"
    assert_empty Dir.children(@output)
  end
end
