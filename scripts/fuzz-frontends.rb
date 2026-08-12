#!/usr/bin/env ruby
# frozen_string_literal: true

# Deterministic, grammar-aware differential probe for Tungsten's active
# frontends. This is intentionally a focused developer/CI check rather than a
# coverage-guided security fuzzer: every seed is replayable, disagreements are
# line-minimized, and artifacts stay under build/cache/.

require "digest"
require "fileutils"
require "open3"
require "optparse"
require "timeout"

ROOT = File.expand_path("..", __dir__)
RUBY_IMPL = File.join(ROOT, "implementations/ruby")
C_VM = File.join(ROOT, "implementations/c/build/tungsten-c")
TUNGSTEN = File.join(ROOT, "bin/tungsten")
LEX_TABLE = File.join(ROOT, "languages/tungsten/tungsten.lex64")
CACHE = File.join(ROOT, "build/cache/frontend-fuzz")
CORPUS = File.join(CACHE, "corpus")
FAILURES = File.join(CACHE, "failures")
LEX_PARITY = File.join(CACHE, "lex-parity")

$LOAD_PATH.unshift(File.join(RUBY_IMPL, "lib"))
require "tungsten"

Options = Struct.new(:seed, :cases, :replay, :replay_valid, keyword_init: true)

def parse_options
  options = Options.new(seed: 0x54554E47, cases: 32, replay: nil, replay_valid: true)
  OptionParser.new do |parser|
    parser.banner = "usage: scripts/fuzz-frontends.rb [--seed N] [--cases N] [--replay FILE]"
    parser.on("--seed N", Integer) { |value| options.seed = value }
    parser.on("--cases N", Integer) { |value| options.cases = value }
    parser.on("--replay FILE") { |value| options.replay = value }
    parser.on("--invalid", "Treat --replay input as intentionally invalid") { options.replay_valid = false }
  end.parse!
  abort "--cases must be positive" unless options.cases.positive?
  options
end

def run(env, *command, timeout: 30)
  stdout = nil
  stderr = nil
  status = nil
  Open3.popen3(env, *command, chdir: ROOT) do |stdin, out, error, wait_thread|
    stdin.close
    stdout_thread = Thread.new { out.read }
    stderr_thread = Thread.new { error.read }
    begin
      status = Timeout.timeout(timeout) { wait_thread.value }
    rescue Timeout::Error
      Process.kill("KILL", wait_thread.pid) rescue nil
      status = wait_thread.value
      stderr = "command timed out after #{timeout}s: #{command.join(' ')}\n"
    end
    stdout = stdout_thread.value
    stderr = stderr.to_s + stderr_thread.value
  end
  [status&.exitstatus || 124, stdout.to_s, stderr.to_s]
end

def token_result(lexer_class, source)
  tokens = lexer_class.new(source).tokens.map do |token|
    [token.type.to_s, token.value.inspect, token.row, token.col]
  end
  [:ok, tokens]
rescue StandardError => error
  location = error.respond_to?(:location) ? error.location : nil
  row = location&.respond_to?(:row) ? location.row : nil
  col = location&.respond_to?(:col) ? location.col : nil
  [:error, error.class.name, error.message, row, col]
end

def ruby_lexer_disagreement(source)
  regex = token_result(Tungsten::Lexer, source)
  codepoint = token_result(Tungsten::CodepointLexer, source)
  return nil if regex == codepoint

  "Ruby regex/codepoint token mismatch\nregex=#{regex.inspect}\ncodepoint=#{codepoint.inspect}"
end

def command_result(*command, env: {})
  status, stdout, stderr = run(env, *command, timeout: 5)
  [status, stdout, stderr]
end

RUBY_BINARY_OPS = {
  "+" => :PLUS,
  "-" => :MINUS,
  "*" => :STAR,
  "/" => :SLASH,
  "%" => :PERCENT,
  "<" => :LT,
  "<=" => :LTE,
  ">" => :GT,
  ">=" => :GTE,
  "==" => :EQ,
  "!=" => :NEQ
}.freeze

def ruby_body_wire(body)
  body.list.map { |node| ruby_ast_wire(node) }
end

def ruby_params_wire(definition)
  (definition.args || []).each_with_index.map do |arg, index|
    {
      node: :param,
      name: arg.name,
      default: arg.default && ruby_ast_wire(arg.default),
      ivar_assign: !!arg.ivar,
      keyword: !!arg.keyword,
      block_param: definition.block.equal?(arg),
      splat: definition.splat_index == index
    }
  end
end

def ruby_class_ref_name?(name)
  name.match?(/\A[A-Z]/) && name.match?(/[a-z]/)
end

def ruby_ast_wire(node)
  case node
  when Tungsten::AST::ArrayLiteral
    {node: :array, elements: node.list.map { |item| ruby_ast_wire(item) }}
  when Tungsten::AST::List
    {node: :program, expressions: ruby_body_wire(node)}
  when Tungsten::AST::Assign
    {node: :assign, target: ruby_ast_wire(node.name), value: ruby_ast_wire(node.value), type_hint: node.type_hint}
  when Tungsten::AST::Var
    {node: ruby_class_ref_name?(node.name) ? :class_ref : :var, name: node.name}
  when Tungsten::AST::Int
    {node: :int, value: node.value, format: nil, raw: node.value.to_s}
  when Tungsten::AST::BinaryOp
    operator = RUBY_BINARY_OPS.fetch(node.operator.to_s)
    {node: :binary_op, left: ruby_ast_wire(node.left), op: operator, right: ruby_ast_wire(node.right)}
  when Tungsten::AST::AssignOp
    operator = RUBY_BINARY_OPS.fetch(node.operator.to_s)
    {node: :compound_assign, target: ruby_ast_wire(node.name), op: operator, value: ruby_ast_wire(node.value)}
  when Tungsten::AST::Fn
    {
      node: :fn_def,
      name: node.name,
      params: ruby_params_wire(node),
      body: ruby_body_wire(node.body),
      type_hints: nil
    }
  when Tungsten::AST::Def
    {
      node: :method_def,
      name: node.name,
      params: ruby_params_wire(node),
      body: ruby_body_wire(node.body),
      type_hints: nil,
      is_class_method: false
    }
  when Tungsten::AST::ClassDef
    {
      node: :class_def,
      name: node.name,
      superclass: node.superclass,
      body: ruby_body_wire(node.body),
      class_role: node.class_role
    }
  when Tungsten::AST::Call
    {
      node: :call,
      receiver: node.obj && ruby_ast_wire(node.obj),
      name: node.name,
      args: node.args.map { |arg| ruby_ast_wire(arg) },
      block: node.block && ruby_ast_wire(node.block)
    }
  when Tungsten::AST::Print
    {node: :puts, value: node.args.map { |arg| ruby_ast_wire(arg) }}
  when Tungsten::AST::If
    {
      node: :if,
      condition: ruby_ast_wire(node.condition),
      then_body: ruby_body_wire(node.then_block),
      elsif_clauses: [],
      else_body: ruby_body_wire(node.else_block)
    }
  when Tungsten::AST::While
    {node: :while, condition: ruby_ast_wire(node.condition), body: ruby_body_wire(node.body)}
  else
    raise "unsupported Ruby AST node in differential grammar: #{node.class}"
  end
end

def canonical_key(key)
  text = key.to_s
  "k#{text.bytesize}:#{text}"
end

def canonical_value(value)
  case value
  when nil
    "n;"
  when true
    "b1;"
  when false
    "b0;"
  when Integer
    "i#{value};"
  when String
    "s#{value.bytesize}:#{value}"
  when Symbol
    text = value.to_s
    "y#{text.bytesize}:#{text}"
  when Array
    "a[#{value.map { |item| canonical_value(item) }.join}]"
  when Hash
    fields = value.map { |key, item| canonical_key(key) + canonical_value(item) }.join
    "h{#{fields}}"
  else
    raise "unsupported canonical value: #{value.class}"
  end
end

def ruby_ast_result(source)
  [0, canonical_value(ruby_ast_wire(Tungsten.parse(source))) + "\n", ""]
rescue StandardError => error
  [1, "", "#{error.class}: #{error.message}\n"]
end

def ast_disagreement(path, source)
  env = {"TUNGSTEN_LEX64_TABLE" => LEX_TABLE}
  ruby = ruby_ast_result(source)
  self_hosted = command_result(TUNGSTEN, "--canonical-ast", path)
  c_vm = command_result(C_VM, "--canonical-ast", path, env: env)
  return nil if ruby == self_hosted && ruby == c_vm

  "canonical AST mismatch\nruby=#{ruby.inspect}\nself_hosted=#{self_hosted.inspect}\nc_vm=#{c_vm.inspect}"
end

def execution_disagreement(path)
  env = {"TUNGSTEN_LEX64_TABLE" => LEX_TABLE}
  ruby = command_result(TUNGSTEN, "run", "--ruby", path)
  self_hosted = command_result(TUNGSTEN, "run", path)
  c_vm = command_result(C_VM, path, env: env)
  return nil if ruby == self_hosted && ruby == c_vm

  "execution mismatch\nruby=#{ruby.inspect}\nself_hosted=#{self_hosted.inspect}\nc_vm=#{c_vm.inspect}"
end

def valid_source(rng, index)
  left = rng.rand(1..500)
  right = rng.rand(1..500)
  factor = rng.rand(2..11)
  operator = %w[+ - * %][rng.rand(4)]
  comparison = %w[< <= > >= == !=][rng.rand(6)]
  name = "value_#{index}"
  other = "other_#{index}"

  case index % 5
  when 0
    <<~W
      #{name} = #{left}
      #{other} = #{right}
      << (#{name} #{operator} #{factor})
      if #{name} #{comparison} #{other}
        << (#{name} + #{other}) * #{factor}
      else
        << #{name} - (#{other} % #{factor})
    W
  when 1
    values = "values_#{index}"
    <<~W
      #{values} = [#{left}, #{right}, #{factor}]
      << #{values}[1]
      << #{values}[0] + #{values}[2]
      << #{values}.size()
    W
  when 2
    count = "count_#{index}"
    total = "total_#{index}"
    <<~W
      #{count} = 0
      #{total} = #{left}
      while #{count} < #{factor}
        #{total} += #{count}
        #{count} += 1
      << #{total}
    W
  when 3
    method = "combine_#{index}"
    <<~W
      -> #{method}(x, y)
        (x * #{factor}) + y
      << #{method}(#{left}, #{right})
    W
  else
    class_name = "Box_#{index}"
    <<~W
      + #{class_name}
        -> value
          #{left}
      << #{class_name}.new().value()
    W
  end
end

def invalid_source(rng, index)
  stem = "fuzz#{index}_#{rng.rand(10_000)}"
  [
    "#{stem}Camel = 1\n",
    "_#{stem}Camel = 1\n",
    "@#{stem}Camel = 1\n",
    "@@#{stem}Camel = 1\n",
    "$#{stem}Camel = 1\n"
  ][index % 5]
end

def invalid_acceptance_disagreement(path)
  env = {"TUNGSTEN_LEX64_TABLE" => LEX_TABLE}
  packed = command_result(TUNGSTEN, "--check", path)
  c_vm = command_result(C_VM, "--check-ast", path, env: env)
  return nil if packed[0] != 0 && c_vm[0] != 0

  "invalid source accepted\npacked=#{packed.inspect}\nc_vm=#{c_vm.inspect}"
end

def valid_acceptance_disagreement(path)
  env = {"TUNGSTEN_LEX64_TABLE" => LEX_TABLE}
  packed = command_result(TUNGSTEN, "--check", path)
  c_vm = command_result(C_VM, "--check-ast", path, env: env)
  return nil if packed[0].zero? && c_vm[0].zero?

  "valid source rejected\npacked=#{packed.inspect}\nc_vm=#{c_vm.inspect}"
end

def minimize_lines(source)
  lines = source.lines
  changed = true
  while changed && lines.size > 1
    changed = false
    lines.size.times do |index|
      candidate = lines.each_with_index.filter_map { |line, i| line unless i == index }.join
      next if candidate.empty? || !yield(candidate)

      lines = candidate.lines
      changed = true
      break
    end
  end
  lines.join
end

def persist_failure(label, seed, source, detail)
  FileUtils.mkdir_p(FAILURES)
  digest = Digest::SHA256.hexdigest(source)[0, 16]
  source_path = File.join(FAILURES, "#{label}-#{digest}.w")
  detail_path = File.join(FAILURES, "#{label}-#{digest}.txt")
  File.write(source_path, source)
  File.write(detail_path, "seed=#{seed}\n#{detail}\n")
  warn "FAIL #{label}: #{source_path}"
  warn "     promote with: cp #{source_path} compiler/test/fixtures/frontend_fuzz_#{digest}.w"
end

def ensure_tools
  abort "missing #{C_VM}; run make -C implementations/c" unless File.executable?(C_VM)
  FileUtils.mkdir_p(CORPUS)
  status, stdout, stderr = run({}, TUNGSTEN, "compile", "--no-lto",
                              File.join(ROOT, "compiler/lex_parity.w"), "--out", LEX_PARITY)
  abort "failed to build lex parity oracle\n#{stdout}#{stderr}" unless status.zero?
end

def write_case(kind, index, source)
  name = kind == "minimize" ? format("%s-%d-%04d.w", kind, Process.pid, index) : format("%s-%04d.w", kind, index)
  path = File.join(CORPUS, name)
  File.write(path, source)
  path
end

def lex_parity_disagreement(path)
  status, stdout, stderr = run({"TUNGSTEN_ROOT" => ROOT}, LEX_PARITY, path, timeout: 5)
  return nil if status.zero?

  "self-hosted regex/packed mismatch\n#{stdout}#{stderr}"
end

options = parse_options
ensure_tools
rng = Random.new(options.seed)
cases = []

if options.replay
  source = File.read(File.expand_path(options.replay))
  cases << [:replay, source, options.replay_valid]
else
  options.cases.times do |index|
    cases << [:valid, valid_source(rng, index), true]
    cases << [:invalid, invalid_source(rng, index), false]
  end
end

failures = 0
cases.each_with_index do |(kind, source, valid), index|
  path = write_case(kind, index, source)
  checks = []
  checks << ["ruby-lex", ->(candidate) { ruby_lexer_disagreement(candidate) }]
  checks << ["lex-parity", lambda do |candidate|
    candidate_path = write_case("minimize", index, candidate)
    lex_parity_disagreement(candidate_path)
  end]
  if valid
    checks << ["valid-accept", lambda do |candidate|
      candidate_path = write_case("minimize", index, candidate)
      valid_acceptance_disagreement(candidate_path)
    end]
    checks << ["ast", lambda do |candidate|
      candidate_path = write_case("minimize", index, candidate)
      ast_disagreement(candidate_path, candidate)
    end]
    checks << ["execution", lambda do |candidate|
      candidate_path = write_case("minimize", index, candidate)
      execution_disagreement(candidate_path)
    end]
  else
    checks << ["invalid-accept", lambda do |candidate|
      candidate_path = write_case("minimize", index, candidate)
      invalid_acceptance_disagreement(candidate_path)
    end]
  end

  checks.each do |label, check|
    detail = check.call(source)
    next unless detail

    minimized = minimize_lines(source) { |candidate| !check.call(candidate).nil? }
    persist_failure(label, options.seed, minimized, check.call(minimized))
    failures += 1
  end
end

if failures.zero?
  puts "frontend differential fuzz: ok (seed=#{options.seed}, cases=#{cases.size})"
else
  abort "frontend differential fuzz: #{failures} disagreement(s) (seed=#{options.seed})"
end
