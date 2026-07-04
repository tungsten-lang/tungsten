# frozen_string_literal: true

require_relative "spec_helper"
require "json"
require "tmpdir"
require "open3"

# Compiler emits single-instruction checks for `wvalue == nil / != nil`
# and at-most-two-instruction checks for `wvalue == true/false / != true/false`.
#
# Tungsten's WValue sentinel encoding assigns W_NIL=0, W_FALSE=1, W_TRUE=2.
# Equality against any of these is a bit compare against a small constant —
# the lowering in `compiler/lib/lowering.w` special-cases these forms to
# emit `icmp` directly, bypassing polymorphic `w_eq`/`w_neq` dispatch.
#
# These specs lock in the IR-level and ARM64-asm-level shapes.
RSpec.describe "sentinel equality fast path" do
  project_root = File.expand_path("../../..", __dir__)
  compiler_bin = File.join(project_root, "bin/tungsten-compiler")
  llc_bin = `which llc`.strip
  llc_bin = "/opt/homebrew/opt/llvm/bin/llc" if llc_bin.empty? && File.exist?("/opt/homebrew/opt/llvm/bin/llc")

  def compile_to_ll(source, name, compiler_bin, project_root)
    Dir.mktmpdir("tungsten-sentinel") do |dir|
      src = File.join(dir, "#{name}.w")
      File.write(src, source)
      out = File.join(dir, name)
      env = { "TUNGSTEN_EMIT_LL" => "1", "TUNGSTEN_CACHE_DIR" => File.join(project_root, "build/cache") }
      _o, err, status = Open3.capture3(env, compiler_bin, "compile", src, "--out", out)
      raise "compile failed: #{err}" unless status.success?
      @last_sidemap_path = "#{out}.sidemap"
      @last_sidemap = File.exist?(@last_sidemap_path) ? JSON.parse(File.read(@last_sidemap_path)) : nil
      ll_path = "/tmp/tungsten/#{name}.ll"
      raise "LL not emitted at #{ll_path}" unless File.exist?(ll_path)
      yield File.read(ll_path), ll_path
    end
  end

  # Extract the function body for `__w_<fn_name>` from LL text.
  # Returns the block between `define ... @__w_<name>(...)` and the
  # terminating `}`.
  def mapped_symbol(original)
    return original unless @last_sidemap

    @last_sidemap.fetch("hashes").each_value do |entry|
      entry.fetch("originals").each do |item|
        return entry.fetch("symbol") if item.fetch("symbol") == original
      end
    end

    original
  end

  def extract_fn(ll, name)
    symbol = mapped_symbol("__w_#{name}")
    match = ll.match(/^define[^\n]*@#{Regexp.escape(symbol)}\(.*?\n(.*?)^\}/m)
    raise "function #{symbol} not found in LL" unless match
    match[1]
  end

  describe "IR: no polymorphic dispatch for sentinel compares" do
    let(:source) do
      <<~W
        -> is_nil(x)
          x == nil
        -> is_not_nil(x)
          x != nil
        -> is_true(x)
          x == true
        -> is_not_true(x)
          x != true
        -> is_false(x)
          x == false
        -> is_not_false(x)
          x != false
        << is_nil(nil).to_s
      W
    end

    it "x == nil lowers to icmp eq against 0, no w_eq call" do
      compile_to_ll(source, "sentinel_is_nil", compiler_bin, project_root) do |ll, _|
        body = extract_fn(ll, "is_nil")
        expect(body).not_to include("@w_eq"), "expected no w_eq call, got:\n#{body}"
        expect(body).not_to include("@w_neq"), "expected no w_neq call, got:\n#{body}"
        expect(body).to match(/icmp eq i64 [^,]+, 0/), "expected icmp eq i64 ..., 0, got:\n#{body}"
      end
    end

    it "x != nil lowers to icmp ne against 0, no w_neq call" do
      compile_to_ll(source, "sentinel_is_not_nil", compiler_bin, project_root) do |ll, _|
        body = extract_fn(ll, "is_not_nil")
        expect(body).not_to include("@w_eq")
        expect(body).not_to include("@w_neq")
        expect(body).to match(/icmp ne i64 [^,]+, 0/)
      end
    end

    it "x == true lowers to icmp eq against 2, no w_eq call" do
      compile_to_ll(source, "sentinel_is_true", compiler_bin, project_root) do |ll, _|
        body = extract_fn(ll, "is_true")
        expect(body).not_to include("@w_eq")
        expect(body).not_to include("@w_neq")
        expect(body).to match(/icmp eq i64 [^,]+, 2/)
      end
    end

    it "x != true lowers to icmp ne against 2" do
      compile_to_ll(source, "sentinel_is_not_true", compiler_bin, project_root) do |ll, _|
        body = extract_fn(ll, "is_not_true")
        expect(body).not_to include("@w_eq")
        expect(body).not_to include("@w_neq")
        expect(body).to match(/icmp ne i64 [^,]+, 2/)
      end
    end

    it "x == false lowers to icmp eq against 1, no w_eq call" do
      compile_to_ll(source, "sentinel_is_false", compiler_bin, project_root) do |ll, _|
        body = extract_fn(ll, "is_false")
        expect(body).not_to include("@w_eq")
        expect(body).not_to include("@w_neq")
        expect(body).to match(/icmp eq i64 [^,]+, 1/)
      end
    end

    it "x != false lowers to icmp ne against 1" do
      compile_to_ll(source, "sentinel_is_not_false", compiler_bin, project_root) do |ll, _|
        body = extract_fn(ll, "is_not_false")
        expect(body).not_to include("@w_eq")
        expect(body).not_to include("@w_neq")
        expect(body).to match(/icmp ne i64 [^,]+, 1/)
      end
    end
  end

  describe "ARM64 asm: single instruction for nil, ≤2 for true/false", if: RUBY_PLATFORM =~ /arm64|aarch64/i do
    before do
      skip "llc not available" unless llc_bin && File.exist?(llc_bin)
    end

    # Compiles the source through clang -S to produce ARM64 assembly for the
    # named function, then counts the relevant compare/branch ops in its
    # body. Uses -O3 to match release builds.
    def compile_to_asm(source, name, compiler_bin, llc_bin, project_root)
      Dir.mktmpdir("tungsten-asm") do |dir|
        src = File.join(dir, "#{name}.w")
        File.write(src, source)
        bin_out = File.join(dir, name)
      env = { "TUNGSTEN_EMIT_LL" => "1", "TUNGSTEN_CACHE_DIR" => File.join(project_root, "build/cache") }
      _o, err, status = Open3.capture3(env, compiler_bin, "compile", src, "--out", bin_out)
      raise "compile failed: #{err}" unless status.success?
      @last_sidemap_path = "#{bin_out}.sidemap"
      @last_sidemap = File.exist?(@last_sidemap_path) ? JSON.parse(File.read(@last_sidemap_path)) : nil
      ll_path = "/tmp/tungsten/#{name}.ll"
        raise "LL not emitted" unless File.exist?(ll_path)
        asm_path = File.join(dir, "#{name}.s")
        _o, err, status = Open3.capture3(llc_bin, "-O3", "-mtriple=arm64-apple-macos", ll_path, "-o", asm_path)
        raise "llc failed: #{err}" unless status.success?
        yield File.read(asm_path)
      end
    end

    # Extract the body of a named function from the asm. Returns the
    # lines between the function label and the next top-level label or end.
    def asm_body(asm, name)
      symbol = mapped_symbol("__w_#{name}")
      in_fn = false
      lines = []
      asm.each_line do |line|
        if line =~ /^_?#{Regexp.escape(symbol)}:/
          in_fn = true
          next
        end
        if in_fn
          break if line =~ /^_?(?:__w_|__wy_)[a-zA-Z0-9_]/  # next function
          break if line =~ /^\.globl|^\.cfi_endproc/ && !lines.empty?
          lines << line
        end
      end
      lines.join
    end

    # Counts ARM64 instructions in the asm body. Only counts "real" opcodes,
    # skipping labels, directives, comments, and blank lines.
    def count_insns(asm_body)
      asm_body.each_line.count do |line|
        stripped = line.strip
        next false if stripped.empty?
        next false if stripped.start_with?(";", "//", "#", ".", "_")
        next false if stripped.end_with?(":")
        true
      end
    end

    # Counts only the cmp/cset/cbz/cbnz/b.cond compare-and-branch family ops.
    def count_compare_ops(asm_body)
      asm_body.each_line.count do |line|
        stripped = line.strip
        stripped.match?(/^\s*(cmp|cmn|cset|cbz|cbnz|tbz|tbnz|b\.(eq|ne|lt|gt|le|ge|hi|lo|hs|ls))\b/)
      end
    end

    let(:wrapper_source) do
      # Each function: unbox param, compare against sentinel, return bool.
      # We branch on the compare result to avoid the compiler short-circuiting
      # via cset alone — that exercises the cbz/cbnz fusion path for nil.
      <<~W
        -> branch_nil(x)
          if x == nil
            return 1
          0
        -> branch_not_nil(x)
          if x != nil
            return 1
          0
        -> branch_true(x)
          if x == true
            return 1
          0
        -> branch_false(x)
          if x == false
            return 1
          0
        << branch_nil(nil).to_s
      W
    end

    it "x == nil in branch context uses cbz (1 compare-op)" do
      compile_to_asm(wrapper_source, "asm_branch_nil", compiler_bin, llc_bin, project_root) do |asm|
        body = asm_body(asm, "branch_nil")
        ops = count_compare_ops(body)
        expect(ops).to be <= 1, "expected ≤1 compare-op for nil branch, got #{ops}:\n#{body}"
      end
    end

    it "x != nil in branch context uses cbnz (1 compare-op)" do
      compile_to_asm(wrapper_source, "asm_branch_not_nil", compiler_bin, llc_bin, project_root) do |asm|
        body = asm_body(asm, "branch_not_nil")
        ops = count_compare_ops(body)
        expect(ops).to be <= 1, "expected ≤1 compare-op for !nil branch, got #{ops}:\n#{body}"
      end
    end

    it "x == true in branch context uses cmp+b.cond (≤2 compare-ops)" do
      compile_to_asm(wrapper_source, "asm_branch_true", compiler_bin, llc_bin, project_root) do |asm|
        body = asm_body(asm, "branch_true")
        ops = count_compare_ops(body)
        expect(ops).to be <= 2, "expected ≤2 compare-ops for true branch, got #{ops}:\n#{body}"
      end
    end

    it "x == false in branch context uses cmp+b.cond (≤2 compare-ops)" do
      compile_to_asm(wrapper_source, "asm_branch_false", compiler_bin, llc_bin, project_root) do |asm|
        body = asm_body(asm, "branch_false")
        ops = count_compare_ops(body)
        expect(ops).to be <= 2, "expected ≤2 compare-ops for false branch, got #{ops}:\n#{body}"
      end
    end
  end
end
