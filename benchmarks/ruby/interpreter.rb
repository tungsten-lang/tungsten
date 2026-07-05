#!/usr/bin/env ruby
# frozen_string_literal: true

require "benchmark"
require "objspace"

# Usage:
#   ruby benchmarks/ruby/interpreter.rb
#   RUNS=10 N=100000 ALLOC_N=5000 FILES=0 ruby benchmarks/ruby/interpreter.rb
#   PARSER_BENCH=1 ruby benchmarks/ruby/interpreter.rb
#   PARSER_BENCH=1 PARSER_RUNS=20 PARSER_FILES=compiler/lib/lowering.w ruby benchmarks/ruby/interpreter.rb
#   PARSER_BENCH=1 PARSER_ALLOC_PROFILE=1 ruby benchmarks/ruby/interpreter.rb
#
# The benchmark separates parse-time shape from evaluation hot paths so changes
# to AST allocation, dispatch, environments, and loop lowering are easy to spot.

ROOT = File.expand_path("../..", __dir__)
GEM_LIB = File.join(ROOT, "implementations", "ruby", "lib")
$LOAD_PATH.unshift(GEM_LIB) unless $LOAD_PATH.include?(GEM_LIB)

require "tungsten"

Sample = Struct.new(:name, :source, :expected, keyword_init: true)

RUNS = Integer(ENV.fetch("RUNS", "5"))
WARMUP = Integer(ENV.fetch("WARMUP", "1"))
N = Integer(ENV.fetch("N", "50000"))
ALLOC_N = Integer(ENV.fetch("ALLOC_N", "1000"))
INCLUDE_FILES = ENV.fetch("FILES", "1") != "0"

COUNT_KEYS = %i[T_ARRAY T_HASH T_STRING T_OBJECT].freeze
COMPILER_FILES = %w[
  compiler/lib/lowering.w
  compiler/lib/parser.w
  compiler/lib/interpreter.w
].freeze

PARSER_BENCH = ENV.fetch("PARSER_BENCH", "0") != "0"
PARSER_RUNS = Integer(ENV.fetch("PARSER_RUNS", "8"))
PARSER_WARMUP = Integer(ENV.fetch("PARSER_WARMUP", "2"))
PARSER_FILES = ENV.fetch("PARSER_FILES", COMPILER_FILES.join(",")).split(",").map(&:strip).reject(&:empty?)
PARSER_ALLOC_PROFILE = ENV.fetch("PARSER_ALLOC_PROFILE", "0") != "0"
PARSER_ALLOC_MODE = ENV.fetch("PARSER_ALLOC_MODE", "codepoint")
PARSER_ALLOC_LIMIT = Integer(ENV.fetch("PARSER_ALLOC_LIMIT", "20"))

def sample_sources(n)
  [
    Sample.new(
      name: "numeric_while",
      source: <<~W,
        i = 0
        sum = 0
        while i < #{n}
          sum += i
          i += 1
        sum
      W
      expected: n * (n - 1) / 2
    ),
    Sample.new(
      name: "while_true_break",
      source: <<~W,
        i = 0
        while true
          break if i == #{n}
          i += 1
        i
      W
      expected: n
    ),
    Sample.new(
      name: "while_literal_eq_break",
      source: <<~W,
        i = 0
        while 1 == 1
          break if i == #{n}
          i += 1
        i
      W
      expected: n
    ),
    Sample.new(
      name: "local_call_loop",
      source: <<~W,
        -> add1(x)
          x + 1

        i = 0
        sum = 0
        while i < #{n}
          sum = add1(sum)
          i += 1
        sum
      W
      expected: n
    ),
    Sample.new(
      name: "yield_block_loop",
      source: <<~W,
        -> repeat(n)
          i = 0
          while i < n
            yield i
            i += 1

        sum = 0
        repeat(#{n}) -> (i)
          sum += i
        sum
      W
      expected: n * (n - 1) / 2
    ),
    Sample.new(
      name: "object_call_loop",
      source: <<~W,
        + Counter
          -> new
            @n = 0
          -> inc
            @n += 1
          -> value
            @n

        c = Counter()
        i = 0
        while i < #{n}
          c.inc()
          i += 1
        c.value()
      W
      expected: n
    ),
    Sample.new(
      name: "object_call_arg_loop",
      source: <<~W,
        + Counter
          -> new
            @n = 0
          -> add(x)
            @n += x
          -> value
            @n

        c = Counter()
        i = 0
        while i < #{n}
          c.add(1)
          i += 1
        c.value()
      W
      expected: n
    ),
    Sample.new(
      name: "object_call_two_arg_loop",
      source: <<~W,
        + Counter
          -> new
            @n = 0
          -> add2(x, y)
            @n += x + y
          -> value
            @n

        c = Counter()
        i = 0
        while i < #{n}
          c.add2(1, 1)
          i += 1
        c.value()
      W
      expected: n * 2
    ),
    Sample.new(
      name: "implicit_self_loop",
      source: <<~W,
        + Counter
          -> new
            @n = 0
          -> inc
            @n += 1
          -> value
            @n
          -> twice
            inc
            inc
            value

        c = Counter()
        i = 0
        while i < #{n}
          c.twice()
          i += 1
        c.value()
      W
      expected: n * 2
    )
  ]
end

def parse(source)
  Tungsten::Parser.parse(source)
end

def evaluate(source)
  Tungsten::Interpreter.new.evaluate(parse(source))
end

def ast_counts(ast)
  counts = Hash.new(0)
  walk = lambda do |node|
    return unless node.is_a?(Tungsten::AST::Node)

    counts[node.class.name.sub(/\A.*::/, "")] += 1
    node.children { |child| walk.call(child) }
  end
  walk.call(ast)
  counts
end

def ast_string_stats(ast)
  strings = []
  walk = lambda do |node|
    return unless node.is_a?(Tungsten::AST::Node)

    node.instance_variables.each do |ivar|
      next if ivar == :@parent || ivar == :@location

      value = node.instance_variable_get(ivar)
      case value
      when String
        strings << value
      when Array
        value.each { |item| strings << item if item.is_a?(String) }
      end
    end

    node.children { |child| walk.call(child) }
  end

  walk.call(ast)
  {
    slots: strings.size,
    values: strings.uniq.size,
    objects: strings.map(&:object_id).uniq.size
  }
end

def format_count_delta(before, after)
  COUNT_KEYS.to_h { |key| [key, after[key] - before[key]] }
end

def print_header(title)
  puts
  puts title
  puts "-" * title.length
end

def print_hash_counts(counts, limit: 12)
  total = counts.values.sum
  puts "total=#{total}"
  counts.sort_by { |name, count| [-count, name] }.first(limit).each do |name, count|
    puts "  #{name.to_s.rjust(18)} #{count}"
  end
end

def with_lexer_mode(mode)
  previous = ENV["TUNGSTEN_LEXER"]
  mode ? ENV["TUNGSTEN_LEXER"] = mode : ENV.delete("TUNGSTEN_LEXER")
  yield
ensure
  previous ? ENV["TUNGSTEN_LEXER"] = previous : ENV.delete("TUNGSTEN_LEXER")
end

def lexer_modes_for(label)
  case label
  when "regex"
    [["regex", nil]]
  when "codepoint"
    [["codepoint", "codepoint"]]
  when "both"
    [["regex", nil], ["codepoint", "codepoint"]]
  else
    abort "unknown PARSER_ALLOC_MODE=#{label.inspect}; expected regex, codepoint, or both"
  end
end

def relative_sourcefile(file)
  return "(unknown)" unless file

  prefix = "#{ROOT}/"
  file.start_with?(prefix) ? file.delete_prefix(prefix) : file
end

def allocation_site_key(obj)
  [
    obj.class.name || obj.class.to_s,
    relative_sourcefile(ObjectSpace.allocation_sourcefile(obj)),
    ObjectSpace.allocation_sourceline(obj),
    ObjectSpace.allocation_method_id(obj)
  ]
end

def format_allocation_site(key)
  klass, file, line, method = key
  location = line ? "#{file}:#{line}" : file
  method ? "#{klass} #{location}##{method}" : "#{klass} #{location}"
end

def measured_parse(source)
  ast = nil
  begin
    GC.start
    GC.disable
    before = ObjectSpace.count_objects
    elapsed = Benchmark.realtime { ast = parse(source) }
    after = ObjectSpace.count_objects
  ensure
    GC.enable
  end

  [elapsed, format_count_delta(before, after), ast]
end

def average_parse_measurements(source, runs)
  times = []
  totals = Hash.new(0)
  ast = nil

  runs.times do
    elapsed, delta, ast = measured_parse(source)
    times << elapsed
    COUNT_KEYS.each { |key| totals[key] += delta[key] }
  end

  avg_delta = COUNT_KEYS.to_h { |key| [key, (totals[key].to_f / runs).round] }
  [times, avg_delta, ast]
end

def parser_allocation_profile(source, mode)
  ObjectSpace.trace_object_allocations_clear
  ObjectSpace.trace_object_allocations_start
  marker = Object.new
  generation = ObjectSpace.allocation_generation(marker)
  class_counts = Hash.new(0)
  site_counts = Hash.new(0)
  ast = nil
  elapsed = nil

  begin
    GC.start
    GC.disable
    elapsed = Benchmark.realtime do
      with_lexer_mode(mode) { ast = parse(source) }
    end
    ObjectSpace.trace_object_allocations_stop

    ObjectSpace.each_object do |obj|
      allocation_generation = ObjectSpace.allocation_generation(obj)
      next unless allocation_generation && allocation_generation >= generation

      class_name = obj.class.name || obj.class.to_s
      class_counts[class_name] += 1
      site_counts[allocation_site_key(obj)] += 1
    end
  ensure
    ObjectSpace.trace_object_allocations_stop
    ObjectSpace.trace_object_allocations_clear
    GC.enable
  end

  {
    elapsed: elapsed,
    total: class_counts.values.sum,
    class_counts: class_counts,
    site_counts: site_counts,
    ast_counts: ast ? ast_counts(ast) : {}
  }
end

def print_parser_allocation_profile(label, mode, source)
  profile = parser_allocation_profile(source, mode)
  puts "  allocation_profile mode=#{label} parse=%0.4fs traced=%d ast_nodes=%d" %
       [profile[:elapsed], profile[:total], profile[:ast_counts].values.sum]

  puts "    classes"
  profile[:class_counts].sort_by { |klass, count| [-count, klass] }.first(PARSER_ALLOC_LIMIT).each do |klass, count|
    puts "      %-48s %d" % [klass, count]
  end

  puts "    sites"
  profile[:site_counts].sort_by { |site, count| [-count, format_allocation_site(site)] }
                       .first(PARSER_ALLOC_LIMIT).each do |site, count|
    puts "      %-8d %s" % [count, format_allocation_site(site)]
  end
end

def parser_benchmark
  print_header("Parser Lexer Comparison")
  puts "parser_runs=#{PARSER_RUNS} parser_warmup=#{PARSER_WARMUP}"
  puts "parser_alloc_profile=#{PARSER_ALLOC_PROFILE ? PARSER_ALLOC_MODE : "off"}"

  PARSER_FILES.each do |rel_path|
    path = File.join(ROOT, rel_path)
    unless File.exist?(path)
      puts "#{rel_path}: missing"
      next
    end

    source = File.read(path)
    rows = {}

    [["regex", nil], ["codepoint", "codepoint"]].each do |label, mode|
      with_lexer_mode(mode) do
        PARSER_WARMUP.times { parse(source) }
        times, delta, ast = average_parse_measurements(source, PARSER_RUNS)
        string_stats = ast_string_stats(ast)
        rows[label] = {
          avg: times.sum / times.size,
          min: times.min,
          max: times.max,
          delta: delta,
          ast_counts: ast_counts(ast),
          string_stats: string_stats
        }
      end
    rescue Tungsten::Error => e
      rows[label] = {error: e.message.lines.first&.strip}
    end

    puts
    puts rel_path
    rows.each do |label, row|
      if row[:error]
        puts "  %-9s parse failed: %s" % [label, row[:error]]
        next
      end

      delta = row[:delta]
      strings = row[:string_stats]
      puts "  %-9s avg=%0.4fs min=%0.4fs max=%0.4fs arrays=%-7d hashes=%-6d strings=%-7d objects=%-7d ast_nodes=%-7d ast_strings=%d/%d/%d" %
           [
             label,
             row[:avg],
             row[:min],
             row[:max],
             delta[:T_ARRAY],
             delta[:T_HASH],
             delta[:T_STRING],
             delta[:T_OBJECT],
             row[:ast_counts].values.sum,
             strings[:slots],
             strings[:values],
             strings[:objects]
           ]
    end

    if rows.dig("regex", :avg) && rows.dig("codepoint", :avg)
      speedup = rows["regex"][:avg] / rows["codepoint"][:avg]
      puts "  speedup   %0.2fx" % speedup
      top_counts = rows["codepoint"][:ast_counts].sort_by { |name, count| [-count, name] }.first(8)
      puts "  top_ast   #{top_counts.map { |name, count| "#{name}=#{count}" }.join(" ")}"
    end

    if PARSER_ALLOC_PROFILE
      lexer_modes_for(PARSER_ALLOC_MODE).each do |label, mode|
        print_parser_allocation_profile(label, mode, source)
      end
    end
  end
end

def verify_samples(samples)
  samples.each do |sample|
    result = evaluate(sample.source)
    next if result == sample.expected

    abort "#{sample.name}: expected #{sample.expected.inspect}, got #{result.inspect}"
  end
end

def benchmark_samples(samples)
  samples.each do |sample|
    ast = parse(sample.source)
    interpreter = Tungsten::Interpreter.new
    WARMUP.times { interpreter.evaluate(ast) }

    result = nil
    elapsed = Benchmark.realtime do
      RUNS.times { result = interpreter.evaluate(ast) }
    end
    per_run = elapsed / RUNS
    ops_per_sec = per_run.positive? ? 1.0 / per_run : Float::INFINITY

    puts "%-24s result=%-12s per=%0.6fs ops/s=%0.1f" %
         [sample.name, result.inspect, per_run, ops_per_sec]
  end
end

def allocation_samples(samples)
  samples.each do |sample|
    ast = parse(sample.source)
    interpreter = Tungsten::Interpreter.new
    WARMUP.times { interpreter.evaluate(ast) }

    begin
      GC.start
      GC.disable
      before = ObjectSpace.count_objects
      result = interpreter.evaluate(ast)
      after = ObjectSpace.count_objects
    ensure
      GC.enable
    end

    delta = format_count_delta(before, after)
    puts "%-24s result=%-12s arrays=%-6d hashes=%-5d strings=%-6d objects=%-5d" %
         [sample.name, result.inspect, delta[:T_ARRAY], delta[:T_HASH], delta[:T_STRING], delta[:T_OBJECT]]
  end
end

def parse_file_counts
  COMPILER_FILES.each do |rel_path|
    path = File.join(ROOT, rel_path)
    next unless File.exist?(path)

    source = File.read(path)
    ast = nil
    begin
      GC.start
      GC.disable
      before = ObjectSpace.count_objects
      elapsed = Benchmark.realtime { ast = parse(source) }
      after = ObjectSpace.count_objects
    ensure
      GC.enable
    end

    delta = format_count_delta(before, after)
    counts = ast_counts(ast)
    string_stats = ast_string_stats(ast)
    puts "#{rel_path}: parse=%0.4fs ast_nodes=%d arrays=%d hashes=%d strings=%d objects=%d ast_strings=%d/%d/%d" %
         [
           elapsed,
           counts.values.sum,
           delta[:T_ARRAY],
           delta[:T_HASH],
           delta[:T_STRING],
           delta[:T_OBJECT],
           string_stats[:slots],
           string_stats[:values],
           string_stats[:objects]
         ]
    print_hash_counts(counts, limit: 8)
  rescue Tungsten::Error => e
    puts "#{rel_path}: parse failed: #{e.message.lines.first&.strip}"
  end
end

def method_lookup_counts
  source = <<~W
    + Counter
      -> new
        @n = 0
      -> inc
        @n += 1
      -> value
        @n
      -> twice
        inc
        inc
        value

    c = Counter()
    i = 0
    while i < #{ALLOC_N}
      c.twice()
      i += 1
    c.value()
  W

  counts = Hash.new(0)
  klass = Tungsten::Runtime::WClass
  original_lookup = klass.instance_method(:lookup_method)
  klass.define_method(:lookup_method) do |name|
    counts[[self.name, name]] += 1
    original_lookup.bind_call(self, name)
  end

  result = evaluate(source)
  puts "result=#{result.inspect}"
  counts.sort_by { |key, count| [-count, key] }.each do |(owner, name), count|
    puts "  #{owner}##{name}: #{count}"
  end
ensure
  klass.define_method(:lookup_method, original_lookup) if klass && original_lookup
end

def bytecode_shape
  return unless defined?(RubyVM::InstructionSequence)

  methods = %i[
    visit_call
    visit_while
    call_method
    call_w_method_from_nodes
    execute_bound_w_method
    execute_simple_while_plan
    execute_simple_method_plan_from_nodes
    visit_var
  ]
  methods.each do |name|
    iseq = RubyVM::InstructionSequence.of(Tungsten::Interpreter.instance_method(name))
    puts "%-38s bytes=%-6d disasm_lines=%d" % [name, iseq.to_binary.bytesize, iseq.disasm.lines.length]
  end

  iseq = RubyVM::InstructionSequence.of(Tungsten::Runtime::WClass.instance_method(:lookup_method))
  puts "%-38s bytes=%-6d disasm_lines=%d" %
       ["WClass#lookup_method", iseq.to_binary.bytesize, iseq.disasm.lines.length]
end

if PARSER_BENCH
  puts "Tungsten Ruby parser benchmark"
  puts "ruby=#{RUBY_DESCRIPTION}"
  parser_benchmark
  exit
end

timing_samples = sample_sources(N)
allocation_source_samples = sample_sources(ALLOC_N)

puts "Tungsten Ruby interpreter benchmark"
puts "ruby=#{RUBY_DESCRIPTION}"
puts "runs=#{RUNS} warmup=#{WARMUP} n=#{N} alloc_n=#{ALLOC_N}"
puts "files=#{INCLUDE_FILES ? "on" : "off"}"

verify_samples(timing_samples)

print_header("Sample AST Node Counts")
allocation_source_samples.each do |sample|
  puts sample.name
  print_hash_counts(ast_counts(parse(sample.source)), limit: 10)
end

if INCLUDE_FILES
  print_header("Compiler File Parse Counts")
  parse_file_counts
end

print_header("Eval Timings")
benchmark_samples(timing_samples)

print_header("Eval Allocation Deltas")
allocation_samples(allocation_source_samples)

print_header("WClass Lookup Counts")
method_lookup_counts

print_header("Ruby Bytecode Shape")
bytecode_shape
