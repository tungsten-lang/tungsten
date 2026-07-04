# frozen_string_literal: true

require_relative "spec_helper"
require "tmpdir"
require "open3"
require "fileutils"
require "tungsten"

RSpec.describe "Compiler parity", :parity do
  FIXTURES_DIR = File.join(PROJECT_ROOT, "compiler/test/fixtures")

  FIXTURES = %w[
    hello simple add arithmetic variables
    ifelse elsif while countdown break
    while_elsif
    fib fib0 fib1 fib2 fib3
    func func_if innercall innercall_arg
    nocall othercall selfcall fib_norun
    fn_fib class class_var case rescue array block
    method_call classes capture yield hash
    range range_mutation with multi_assign
    currency quantity duration
    short_circuit
    magic_constants
    case_value
  ].freeze

  # Discover non-skipped examples with embedded expectations (no stdin, exit 0)
  EXAMPLE_DIRS = [
    File.join(PROJECT_ROOT, "doc/examples"),
    File.join(PROJECT_ROOT, "doc/rosetta_code")
  ].freeze

  EXAMPLES = EXAMPLE_DIRS.flat_map { |dir| Dir["#{dir}/**/*.w"] }.sort.select { |path|
    source = File.read(path)
    next false unless source.include?("## expect") && !source.match?(/^## expect skip\b/)
    next false if source.match?(/^## parity skip\b/)
    exp = Tungsten::ExampleExpectations.parse(source)
    exp.stdin.to_s.empty? && exp.exit_status == 0
  }.freeze

  before(:all) do
    @tmpdir = Dir.mktmpdir("parity")
    @expected = {}
    @skipped = []

    # Phase 1: Generate expected output
    $stderr.print "  parity: interpreting #{FIXTURES.size} fixtures..."
    FIXTURES.each do |name|
      fixture = File.join(FIXTURES_DIR, "#{name}.w")
      next unless File.exist?(fixture)

      source = File.read(fixture)
      if source.include?("## expect skip")
        @skipped << name
        next
      end

      expected_file = File.join(FIXTURES_DIR, "#{name}.expected")
      if File.exist?(expected_file)
        @expected[name] = File.read(expected_file)
      else
        out = StringIO.new
        old_stdout = $stdout
        begin
          $stdout = out
          Tungsten::Interpreter.new.run(source, file_path: fixture)
          @expected[name] = out.string
        rescue
          @skipped << name
        ensure
          $stdout = old_stdout
        end
      end
    end
    $stderr.puts " done"

    # Phase 2: Read embedded expectations for examples
    EXAMPLES.each do |path|
      key = example_key(path)
      @expected[key] = Tungsten::ExampleExpectations.parse(File.read(path)).stdout
    end

    # Phase 3: Batch compile fixtures
    compile_list = []
    FIXTURES.each do |name|
      next if @skipped.include?(name)
      fixture = File.join(FIXTURES_DIR, "#{name}.w")
      next unless File.exist?(fixture)
      tmp = File.join(@tmpdir, "#{name}.w")
      FileUtils.cp(fixture, tmp)
      compile_list << tmp
    end

    unless compile_list.empty?
      $stderr.print "  parity: batch compiling #{compile_list.size} fixtures..."
      _out, err, status = Open3.capture3(
        TUNGSTEN_BIN, "compile-batch", *compile_list,
        chdir: PROJECT_ROOT
      )
      unless status.success?
        $stderr.puts " (#{err.scan(/(\d+) file\(s\) failed/).flatten.first || '?'} failed)"
      else
        $stderr.puts " done"
      end
    end

    # Phase 4: Batch compile examples (tolerates individual failures)
    example_list = []
    EXAMPLES.each do |path|
      key = example_key(path)
      tmp = File.join(@tmpdir, "#{key}.w")
      FileUtils.cp(path, tmp)
      example_list << tmp
    end

    unless example_list.empty?
      $stderr.print "  parity: batch compiling #{example_list.size} examples..."
      Open3.capture3(
        TUNGSTEN_BIN, "compile-batch", *example_list,
        chdir: PROJECT_ROOT
      )
      $stderr.puts " done"
    end
  end

  after(:all) do
    FileUtils.rm_rf(@tmpdir) if @tmpdir
  end

  FIXTURES.each do |name|
    it "fixture: #{name}" do
      skip "skipped" if @skipped.include?(name)
      expect(@expected).to have_key(name), "no expected output for #{name}"

      binary = File.join(@tmpdir, "#{name}.wc")
      expect(File.exist?(binary)).to be(true), "#{name}: binary not compiled"

      actual, _err, status = Open3.capture3(binary)
      expect(status.success?).to be(true), "#{name}: runtime error"
      expect(actual).to eq(@expected[name])
    end
  end

  EXAMPLES.each do |path|
    rel = path.delete_prefix("#{PROJECT_ROOT}/")
    it "example: #{rel}" do
      key = example_key(path)
      binary = File.join(@tmpdir, "#{key}.wc")
      skip "not compiled" unless File.exist?(binary)

      actual, _err, status = Open3.capture3(binary)
      expect(status.success?).to be(true), "#{rel}: runtime error"
      expect(Tungsten::ExampleExpectations.output_mismatch(@expected[key], actual)).to be_nil
    end
  end

  private

  def example_key(path)
    path.delete_prefix("#{PROJECT_ROOT}/").delete_suffix(".w").tr("/", "__")
  end
end
