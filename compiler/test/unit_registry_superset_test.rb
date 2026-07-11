# frozen_string_literal: true

require "open3"
require "rbconfig"
require "set"
require "tmpdir"

ROOT = File.expand_path("../..", __dir__)
GENERATOR = File.join(ROOT, "scripts/gen_units.rb")
COMPILER = File.join(ROOT, "bin/tungsten")
LEGACY_UNITS = File.join(ROOT, "data/units.tsv")
BATCH_SIZE = Integer(ENV.fetch("UNIT_PARITY_BATCH_SIZE", "80"))

$LOAD_PATH.unshift File.join(ROOT, "implementations/ruby/lib")
require "tungsten"

def capture!(*command)
  output, error, status = Open3.capture3(*command, chdir: ROOT)
  return output if status.success?

  abort <<~ERROR
    command failed (#{status.exitstatus}): #{command.join(" ")}
    #{output}#{error}
  ERROR
end

def quote_string(value)
  value.gsub("\\", "\\\\").gsub('"', '\\"')
end

def quantity_literal(name)
  return "1%" if name == "%"
  return "1in" if name == "in"

  "1 #{name}"
end

def first_difference(expected, actual)
  limit = [expected.length, actual.length].max
  index = (0...limit).find { |i| expected[i] != actual[i] }
  return nil unless index

  [index, expected[index], actual[index]]
end

def compile_and_compare!(tmpdir, label, rows)
  rows.each_slice(BATCH_SIZE).with_index do |batch, batch_index|
    source = File.join(tmpdir, "#{label}-#{batch_index}.w")
    binary = File.join(tmpdir, "#{label}-#{batch_index}")
    expected = batch.map do |_name, canonical|
      label == "runtime" ? canonical : (canonical == "%" ? "1%" : "1 #{canonical}")
    end

    File.open(source, "w", encoding: "utf-8") do |file|
      batch.each do |name, _canonical|
        expression = if label == "runtime"
                       escaped = quote_string(name)
                       %(ccall("w_quantity_parse", "1", "#{escaped}"))
                     else
                       quantity_literal(name)
                     end
        if label == "runtime"
          file.puts %(<< ccall("w_quantity_unit_name", #{expression}))
        else
          file.puts "<< #{expression}"
        end
      end
    end

    compile_output, compile_error, compile_status = Open3.capture3(
      COMPILER, "compile", "--no-lto", source, "--out", binary, chdir: ROOT
    )
    unless compile_status.success?
      names = batch.map(&:first).join(", ")
      abort <<~ERROR
        #{label} unit batch #{batch_index} failed to compile
        units: #{names}
        #{compile_output}#{compile_error}
      ERROR
    end

    output, error, run_status = Open3.capture3(binary, chdir: ROOT)
    unless run_status.success?
      names = batch.map(&:first).join(", ")
      abort <<~ERROR
        #{label} unit batch #{batch_index} failed at runtime
        units: #{names}
        #{output}#{error}
      ERROR
    end

    actual = output.lines(chomp: true)
    next if actual == expected

    index, wanted, got = first_difference(expected, actual)
    unit = index && batch[index]&.first
    abort <<~ERROR
      #{label} unit batch #{batch_index} output mismatch at item #{index}
      spelling: #{unit.inspect}
      expected canonical: #{wanted.inspect}
      actual canonical:   #{got.inspect}
      output lengths: expected #{expected.length}, actual #{actual.length}
      actual tail: #{actual.last(5).inspect}
    ERROR
  end
end

ruby = RbConfig.ruby
capture!(ruby, GENERATOR, "--check")
manifest_text = capture!(ruby, GENERATOR, "--manifest")
compiler_registry = manifest_text.lines(chomp: true).to_h do |line|
  name, _id, canonical = line.split("\t", 3)
  [name, canonical]
end

legacy_names = File.foreach(LEGACY_UNITS, encoding: "utf-8").filter_map do |line|
  line = line.strip
  next if line.empty? || line.start_with?("#")

  line.split("\t", 3)[1]
end

ruby_canonicals = Tungsten::Units::UNIT_TABLE.keys | Tungsten::Units::COMPOUND_DEFS.keys
ruby_aliases = Tungsten::Units::UNIT_ALIASES.keys
superset = (legacy_names | ruby_canonicals | ruby_aliases | compiler_registry.keys).sort

missing_from_compiler = superset.reject { |name| compiler_registry.key?(name) }
unless missing_from_compiler.empty?
  abort "compiled registry is missing #{missing_from_compiler.length} union entries: " \
        "#{missing_from_compiler.join(', ')}"
end

ruby_parse_failures = superset.filter_map do |name|
  begin
    parsed = Tungsten::Units.parse(name)
    name unless parsed
  rescue StandardError => error
    "#{name} (#{error.class}: #{error.message})"
  end
end
unless ruby_parse_failures.empty?
  abort "Ruby registry cannot parse #{ruby_parse_failures.length} union entries:\n" \
        "#{ruby_parse_failures.join("\n")}"
end

rows = superset.map { |name| [name, compiler_registry.fetch(name)] }
literal_rows = rows.reject do |name, _canonical|
  # A unit beginning with a digit has no unambiguous source-literal form:
  # `1 1/mol` is necessarily tokenized as two numeric expressions. It is
  # still covered by the exhaustive runtime-parser leg below.
  name.match?(/\A\d/)
end
apostrophe_rows, batched_literal_rows = literal_rows.partition { |name, _canonical| name.include?("'") }
Dir.mktmpdir("tungsten-unit-superset") do |tmpdir|
  # Runtime construction proves every spelling exists in the generated C
  # registry. Literal construction additionally exercises the compiled lexer
  # and lowering table for the exact same union.
  compile_and_compare!(tmpdir, "runtime", rows)
  compile_and_compare!(tmpdir, "literal", batched_literal_rows)
  # An apostrophe is also Tungsten's postfix syntax. Keep those registered
  # phrases in isolated source files so the packed-token skip marker cannot
  # consume the statement that follows while still testing the literal itself.
  apostrophe_rows.each { |row| compile_and_compare!(tmpdir, "literal", [row]) }
end

puts "PASS  unit registry superset: #{superset.length} spellings " \
     "(#{literal_rows.length} source-literal spellings, " \
     "#{ruby_canonicals.length} Ruby canonicals, #{legacy_names.length} legacy canonicals)"
