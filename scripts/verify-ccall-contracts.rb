#!/usr/bin/env ruby
# frozen_string_literal: true

# Verify the compiler/runtime foreign-call boundary without introducing a
# second hand-maintained signature list. Contracts are derived from:
#
#   * compiler/lib/emitter/primitives.w (`wv` means boxed WValue; literal LLVM types raw)
#   * declare_runtime()'s actual output
#   * runtime/runtime.h plus exported definitions in runtime/runtime.c
#
# `--json` prints the resulting machine-readable registry. The default mode
# checks symbol presence, arity, boxed-value/raw ABI, and physical LLVM types.

require "json"
require "open3"

ROOT = File.expand_path("..", __dir__)
EMITTER = File.join(ROOT, "compiler/lib/emitter/primitives.w")
RUNTIME_H = File.join(ROOT, "runtime/runtime.h")
RUNTIME_C = File.join(ROOT, "runtime/runtime.c")
DUMP_SOURCE = File.join(ROOT, "compiler/test/dump_runtime_declarations.w")
COMPILER = ENV.fetch("TUNGSTEN_COMPILER", File.join(ROOT, "bin/tungsten-compiler"))
REGISTRY_PATH = File.join(ROOT, "data/ccall_contracts.json")

Type = Struct.new(:llvm, :abi, keyword_init: true) do
  def to_h
    { "llvm" => llvm, "abi" => abi }
  end
end

Contract = Struct.new(:symbol, :return_type, :args, :source, keyword_init: true) do
  def to_h
    {
      "symbol" => symbol,
      "return" => return_type.to_h,
      "args" => args.map(&:to_h),
      "arity" => args.size,
      "source" => source
    }
  end
end

CallSite = Struct.new(:mode, :symbol, :arity, :source, keyword_init: true) do
  def to_h
    { "mode" => mode, "symbol" => symbol, "arity" => arity, "source" => source }
  end
end

CALL_MODES = %w[ccall ccall_nobox ccall_rawargs].freeze

def split_top_level(text, separator = ",")
  parts = []
  current = +""
  depth = 0
  quote = nil
  escaped = false
  text.each_char do |char|
    if quote
      current << char
      if escaped
        escaped = false
      elsif char == "\\"
        escaped = true
      elsif char == quote
        quote = nil
      end
      next
    end
    if char == '"' || char == "'"
      quote = char
      current << char
    elsif char == "("
      depth += 1
      current << char
    elsif char == ")"
      depth -= 1
      current << char
    elsif char == separator && depth.zero?
      parts << current.strip
      current = +""
    else
      current << char
    end
  end
  parts << current.strip unless current.strip.empty?
  parts
end

def llvm_raw_types(text)
  text = text.strip
  return [] if text.empty?
  split_top_level(text).map do |type|
    type = type.sub(/\Apreserve_mostcc\s+/, "").strip
    Type.new(llvm: type, abi: type == "void" ? "void" : "raw")
  end
end

class EmitterContracts
  attr_reader :contracts

  def initialize(path)
    @lines = File.readlines(path, chomp: true)
    @source_path = path.delete_prefix(ROOT + "/")
    @env = {}
    @contracts = {}
    parse
  end

  private

  def parse
    start = @lines.index { |line| line.start_with?("-> declare_runtime") }
    finish = @lines.index.with_index { |line, index| index > start && line.start_with?("-> declare_fn(") }
    raise "could not locate declare_runtime in #{EMITTER}" unless start && finish

    @lines[(start + 1)...finish].each_with_index do |line, offset|
      stripped = line.strip
      source = "#{@source_path}:#{start + offset + 2}"
      if stripped =~ /\A([a-z][a-z0-9_]*)\s*=\s*(.+)\z/ && !stripped.start_with?("out =")
        name = Regexp.last_match(1)
        expression = Regexp.last_match(2)
        # `wv` is physically i64 but semantically a boxed WValue.  Preserve
        # that distinction through all of the derived argument-list helpers;
        # a literal "i64" at a declaration site remains a raw integer.
        value = if name == "wv"
          [Type.new(llvm: "i64", abi: "value")]
        else
          evaluate(expression)
        end
        @env[name] = value if value
      end
      next unless stripped =~ /\Aout << declare_fn(?:_attrs|_noreturn)?\((.*)\)\z/

      fields = split_top_level(Regexp.last_match(1))
      next if fields.size < 3
      symbol = parse_string(fields[0])
      next unless symbol
      return_types = evaluate(fields[1])
      arg_types = evaluate(fields[2])
      raise "cannot evaluate emitter contract for #{symbol} at #{source}" unless return_types && arg_types
      raise "invalid return contract for #{symbol} at #{source}" unless return_types.size == 1
      contract = Contract.new(symbol: symbol, return_type: return_types.first, args: arg_types, source: source)
      prior = @contracts[symbol]
      if prior && signature(prior) != signature(contract)
        raise "conflicting emitter declarations for #{symbol}: #{prior.source} and #{source}"
      end
      @contracts[symbol] = contract
    end
  end

  def signature(contract)
    [contract.return_type.llvm, contract.return_type.abi, contract.args.map { |arg| [arg.llvm, arg.abi] }]
  end

  def parse_string(expression)
    expression = expression.strip
    return nil unless expression.start_with?('"') && expression.end_with?('"')
    JSON.parse(expression)
  rescue JSON::ParserError
    nil
  end

  def evaluate(expression)
    expression = expression.strip
    if expression.start_with?('"') && expression.end_with?('"')
      value = parse_string(expression)
      return nil unless value
      return llvm_raw_types(value)
    end
    if expression =~ /\Ajoin_arg_types\d+\((.*)\)\z/
      return split_top_level(Regexp.last_match(1)).flat_map { |part| evaluate(part) || [] }
    end
    pieces = split_top_level(expression, "+")
    if pieces.size > 1
      result = []
      pieces.each do |piece|
        literal = parse_string(piece)
        next if literal == ", " || literal == "preserve_mostcc "
        evaluated = evaluate(piece)
        return nil unless evaluated
        result.concat(evaluated)
      end
      return result
    end
    return @env[expression].map(&:dup) if @env.key?(expression)
    nil
  end
end

def parse_actual_emitter
  stdout, stderr, status = Open3.capture3(COMPILER, "run", DUMP_SOURCE, chdir: ROOT)
  abort "ccall-contracts: declaration emitter failed:\n#{stderr}" unless status.success?
  contracts = {}
  stdout.each_line.with_index(1) do |line, line_number|
    next unless line =~ /\Adeclare\s+(?:preserve_mostcc\s+)?(\S+)\s+@([A-Za-z0-9_.$]+)\(([^)]*)\)/
    return_type = Type.new(llvm: Regexp.last_match(1), abi: "physical")
    symbol = Regexp.last_match(2)
    args = llvm_raw_types(Regexp.last_match(3))
    contracts[symbol] = Contract.new(
      symbol: symbol,
      return_type: return_type,
      args: args,
      source: "declare_runtime output:#{line_number}"
    )
  end
  contracts
end

def strip_c_comments(source)
  source.gsub(%r{/\*.*?\*/}m, " ").gsub(%r{//.*$}, " ")
end

def c_type(type, return_position: false)
  type = type.gsub(/__attribute__\s*\(\(.*?\)\)/m, " ")
             .gsub(/\b(?:extern|static|inline|const|volatile|restrict|_Noreturn)\b/, " ")
             .gsub(/\s+/, " ").strip
  return Type.new(llvm: "void", abi: "void") if return_position && type == "void"
  return Type.new(llvm: "ptr", abi: "raw") if type.include?("(*") || type.include?("*") || type.end_with?("]")
  return Type.new(llvm: "ptr", abi: "raw") if type.match?(/\b[A-Za-z_][A-Za-z0-9_]*(?:Fn|Callback)\b/)
  return Type.new(llvm: "i64", abi: "value") if type.match?(/\bWValue\b/)
  return Type.new(llvm: "double", abi: "raw") if type.match?(/\bdouble\b/)
  return Type.new(llvm: "float", abi: "raw") if type.match?(/\bfloat\b/)
  return Type.new(llvm: "i128", abi: "raw") if type.include?("__int128")
  if type.match?(/\b(?:int64_t|uint64_t|size_t|ssize_t|uintptr_t|intptr_t)\b/) || type == "long" || type == "unsigned long"
    return Type.new(llvm: "i64", abi: "raw")
  end
  Type.new(llvm: "i32", abi: "raw")
end

def remove_parameter_name(parameter)
  parameter = parameter.strip
  return parameter if parameter.include?("(*")
  parameter.sub(/\s+[A-Za-z_][A-Za-z0-9_]*(?:\[[^\]]*\])?\s*\z/, "")
end

def parse_c_contracts(path)
  source = strip_c_comments(File.read(path))
  source.gsub!(/^\s*#.*$/, " ")
  # One level of nested parentheses covers callback parameters such as
  # WValue (*fn)(WValue). Attributes were stripped by c_type after capture.
  # Keep the leading declaration delimiter outside the match. Consuming it
  # would make adjacent prototypes alternate between parsed and skipped.
  pattern = /(?:\A|(?<=[;{}]))\s*([^;{}]*?)\b((?:w_|__w_|bigint_)[A-Za-z0-9_]+)\s*\(((?:[^()]|\([^()]*\))*)\)\s*(?:__attribute__\s*\(\(.*?\)\)\s*)?(?=[;{])/m
  contracts = {}
  source.scan(pattern) do |return_text, symbol, args_text|
    return_text = return_text.gsub(/\s+/, " ").strip
    next if return_text.empty? || return_text.include?("=")
    next if return_text.match?(/\b(?:return|if|else|while|for|switch|case)\b/)
    args = split_top_level(args_text)
    args = [] if args == ["void"] || args.empty?
    arg_types = args.map { |arg| c_type(remove_parameter_name(arg)) }
    contract = Contract.new(
      symbol: symbol,
      return_type: c_type(return_text, return_position: true),
      args: arg_types,
      source: path.delete_prefix(ROOT + "/")
    )
    contracts[symbol] = contract
  end
  contracts
end

def tracked_files(*pathspecs)
  stdout, status = Open3.capture2("git", "ls-files", "-z", *pathspecs, chdir: ROOT)
  raise "git ls-files failed" unless status.success?
  stdout.split("\0").reject(&:empty?).map { |path| File.join(ROOT, path) }
end

def ascii_space?(byte)
  byte == 9 || byte == 10 || byte == 13 || byte == 32
end

def ascii_alpha?(byte)
  (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || byte == 95
end

def ascii_alnum?(byte)
  ascii_alpha?(byte) || (byte >= 48 && byte <= 57)
end

def parse_quoted_string(source, offset)
  return [nil, offset] unless source.getbyte(offset) == 34
  index = offset + 1
  escaped = false
  while index < source.size
    char = source.getbyte(index)
    if escaped
      escaped = false
    elsif char == 92
      escaped = true
    elsif char == 34
      literal = source.byteslice(offset, index - offset + 1)
      begin
        return [JSON.parse(literal), index + 1]
      rescue JSON::ParserError
        return [literal.byteslice(1, literal.bytesize - 2), index + 1]
      end
    end
    index += 1
  end
  [nil, index]
end

def ccall_shape(source, open_paren)
  index = open_paren + 1
  index += 1 while index < source.size && ascii_space?(source.getbyte(index))
  symbol, = parse_quoted_string(source, index)
  return nil unless symbol

  stack = [41]
  commas = 0
  index = open_paren + 1
  while index < source.size
    char = source.getbyte(index)
    if char == 34 || char == 39
      quote = char
      index += 1
      escaped = false
      while index < source.size
        inner = source.getbyte(index)
        if escaped
          escaped = false
        elsif inner == 92
          escaped = true
        elsif inner == quote
          break
        end
        index += 1
      end
    elsif char == 35
      if source.getbyte(index + 1) == 35
        # `## type` is a Tungsten type annotation, not a line comment. Skip
        # the sigil as syntax and keep scanning later arguments on this line.
        index += 2
        next
      end
      index += 1
      index += 1 while index < source.size && source.getbyte(index) != 10
      next
    elsif char == 40
      stack << 41
    elsif char == 91
      stack << 93
    elsif char == 123
      stack << 125
    elsif char == stack.last
      stack.pop
      return [symbol, commas] if stack.empty?
    elsif char == 44 && stack.size == 1
      commas += 1
    end
    index += 1
  end
  nil
end

def scan_ccalls(path)
  source = File.binread(path)
  relative = path.delete_prefix(ROOT + "/")
  calls = []
  index = 0
  line = 1
  while index < source.size
    char = source.getbyte(index)
    if char == 10
      line += 1
      index += 1
      next
    end
    if char == 34 || char == 39
      quote = char
      index += 1
      escaped = false
      while index < source.size
        inner = source.getbyte(index)
        line += 1 if inner == 10
        if escaped
          escaped = false
        elsif inner == 92
          escaped = true
        elsif inner == quote
          index += 1
          break
        end
        index += 1
      end
      next
    end
    if char == 35
      if source.getbyte(index + 1) == 35
        # Preserve scanning after a Tungsten `## type` annotation. Treating
        # its second `#` as a comment hides subsequent ccall arguments.
        index += 2
        next
      end
      index += 1
      index += 1 while index < source.size && source.getbyte(index) != 10
      next
    end
    unless ascii_alpha?(char)
      index += 1
      next
    end

    start = index
    index += 1
    index += 1 while index < source.size && ascii_alnum?(source.getbyte(index))
    mode = source.byteslice(start, index - start)
    next unless CALL_MODES.include?(mode)
    cursor = index
    cursor += 1 while cursor < source.size && ascii_space?(source.getbyte(cursor))
    next unless source.getbyte(cursor) == 40
    shape = ccall_shape(source, cursor)
    next unless shape
    calls << CallSite.new(
      mode: mode,
      symbol: shape[0],
      arity: shape[1],
      source: "#{relative}:#{line}"
    )
  end
  calls
end

def signature(contract, semantic: true)
  values = [[contract.return_type.llvm, semantic ? contract.return_type.abi : nil]]
  values + contract.args.map { |arg| [arg.llvm, semantic ? arg.abi : nil] }
end

emitter = EmitterContracts.new(EMITTER).contracts
actual = parse_actual_emitter
# runtime.h is the public ABI authority. runtime.c is used only to fill
# internal helpers that intentionally are not exported in that header.
runtime = parse_c_contracts(RUNTIME_C).merge(parse_c_contracts(RUNTIME_H))
errors = []

emitter.each do |symbol, declared|
  generated = actual[symbol]
  unless generated
    errors << "#{symbol}: absent from declare_runtime output (source #{declared.source})"
    next
  end
  if signature(declared, semantic: false) != signature(generated, semantic: false)
    errors << "#{symbol}: emitter source physical signature #{signature(declared, semantic: false).inspect} != generated #{signature(generated, semantic: false).inspect}"
  end

  # libc/libm functions are intentionally supplied by the platform rather than
  # runtime.c. Every Tungsten runtime spelling must have a C contract.
  next unless symbol.start_with?("w_", "__w_", "bigint_")
  implementation = runtime[symbol]
  unless implementation
    errors << "#{symbol}: emitted runtime symbol has no declaration/definition in runtime/runtime.h or runtime/runtime.c"
    next
  end
  if declared.args.size != implementation.args.size
    errors << "#{symbol}: emitter arity #{declared.args.size} != runtime arity #{implementation.args.size}"
    next
  end
  if declared.return_type.abi != implementation.return_type.abi
    errors << "#{symbol}: emitter return ABI #{declared.return_type.abi} != runtime #{implementation.return_type.abi}"
  end
  if declared.return_type.llvm != implementation.return_type.llvm
    errors << "#{symbol}: emitter return type #{declared.return_type.llvm} != runtime #{implementation.return_type.llvm}"
  end
  declared.args.zip(implementation.args).each_with_index do |(wire_arg, runtime_arg), index|
    if wire_arg.abi != runtime_arg.abi
      errors << "#{symbol}: arg #{index + 1} emitter ABI #{wire_arg.abi} != runtime #{runtime_arg.abi}"
    end
    if wire_arg.llvm != runtime_arg.llvm
      errors << "#{symbol}: arg #{index + 1} emitter type #{wire_arg.llvm} != runtime #{runtime_arg.llvm}"
    end
  end
end

# Source-level foreign calls include optional bridges implemented outside
# runtime.c. Derive contracts from production runtime translation units; test
# doubles and benchmark reference implementations deliberately reuse runtime
# names with smaller signatures and are not part of the shipped ABI.
native_contracts = {}
native_files = tracked_files(
  "runtime/*.h", "runtime/*.c", "runtime/*.m", "runtime/*.mm",
  "bits/*/lib/*.h", "bits/*/lib/*.c", "bits/*/lib/*.m", "bits/*/lib/*.mm",
  "bits/*/runtime/*.h", "bits/*/runtime/*.c", "bits/*/runtime/*.m", "bits/*/runtime/*.mm"
).reject do |path|
  relative = path.delete_prefix(ROOT + "/")
  relative.start_with?("runtime/test", "runtime/bench_")
end
native_files.each do |path|
  parse_c_contracts(path).each { |symbol, contract| native_contracts[symbol] = contract }
end
# The public header is authoritative when a platform implementation and its
# declaration both occur in the scan.
native_contracts.merge!(parse_c_contracts(RUNTIME_H))

# Helpers materialized as private LLVM bodies have no C symbol by design but
# still participate in the same physical call contract.
%w[
  __w_bit_ctpop_u32 __w_bit_ctpop_u64
  __w_bit_ctlz_u32 __w_bit_ctlz_u64
  __w_bit_cttz_u32 __w_bit_cttz_u64
].each do |symbol|
  native_contracts[symbol] = Contract.new(
    symbol: symbol,
    return_type: Type.new(llvm: "i64", abi: "raw"),
    args: [Type.new(llvm: "i64", abi: "raw")],
    source: "#{EMITTER.delete_prefix(ROOT + "/")} generated intrinsic"
  )
end

production_w_files = tracked_files("*.w").select do |path|
  relative = path.delete_prefix(ROOT + "/")
  relative.start_with?("bin/", "compiler/", "core/", "services/") ||
    relative.match?(%r{\Abits/[^/]+/lib/})
end.reject { |path| path.include?("/compiler/test/") }
call_sites = production_w_files.flat_map { |path| scan_ccalls(path) }
call_sites.each do |call|
  contract = native_contracts[call.symbol]
  unless contract
    errors << "#{call.source}: #{call.mode} target #{call.symbol.inspect} has no tracked native contract"
    next
  end
  if call.arity != contract.args.size
    errors << "#{call.source}: #{call.symbol} call arity #{call.arity} != native arity #{contract.args.size} (#{contract.source})"
  end
  # All three current WIRE instructions are physically `call i64`. Whether
  # those bits are treated as a boxed WValue or a raw integer is the explicit
  # distinction between ccall and ccall_nobox; both are ABI-compatible i64.
  if contract.return_type.llvm != "i64"
    errors << "#{call.source}: #{call.mode} emits an i64 result but #{call.symbol} returns #{contract.return_type.llvm} (#{contract.source})"
  end
end

registry = emitter.keys.sort.filter_map do |symbol|
  next unless runtime[symbol]
  {
    "symbol" => symbol,
    "compiler" => emitter.fetch(symbol).to_h,
    "runtime" => runtime.fetch(symbol).to_h
  }
end


calls_by_symbol = call_sites.group_by(&:symbol)
foreign_registry = calls_by_symbol.keys.sort.filter_map do |symbol|
  contract = native_contracts[symbol]
  next unless contract
  {
    "symbol" => symbol,
    "native" => contract.to_h,
    "call_modes" => calls_by_symbol.fetch(symbol).map(&:mode).uniq.sort
  }
end

document = {
  "schema" => 1,
  "runtime_declarations" => registry,
  "foreign_calls" => foreign_registry
}
generated_json = JSON.pretty_generate(document) + "\n"

json_output = ARGV.delete("--json")
write_registry = ARGV.delete("--write")
abort "usage: #{$PROGRAM_NAME} [--json | --write]" unless ARGV.empty?

if errors.any?
  warn "ccall-contracts: FAIL (#{errors.size} disagreement#{errors.size == 1 ? '' : 's'})"
  errors.each { |error| warn "  - #{error}" }
  exit 1
end

if json_output
  print generated_json
elsif write_registry
  File.write(REGISTRY_PATH, generated_json)
end

unless write_registry || json_output
  unless File.file?(REGISTRY_PATH) && File.binread(REGISTRY_PATH) == generated_json
    warn "ccall-contracts: #{REGISTRY_PATH.delete_prefix(ROOT + '/')} is stale; run #{$PROGRAM_NAME} --write"
    exit 1
  end
end

unless json_output || write_registry
  puts "ccall-contracts: PASS (#{registry.size} runtime declarations, #{foreign_registry.size} foreign targets verified)"
end
