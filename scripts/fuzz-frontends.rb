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

def run(env, *command)
  stdout, stderr, status = Open3.capture3(env, *command, chdir: ROOT)
  [status.exitstatus, stdout, stderr]
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
  status, stdout, stderr = run(env, *command)
  [status, stdout, stderr]
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

  <<~W
    #{name} = #{left}
    #{other} = #{right}
    << #{name} #{operator} #{factor}
    if #{name} #{comparison} #{other}
      << #{name} + #{other}
    else
      << #{name} - #{other}
  W
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
  path = File.join(CORPUS, format("%s-%04d.w", kind, index))
  File.write(path, source)
  path
end

def lex_parity_disagreement(path)
  status, stdout, stderr = run({"TUNGSTEN_ROOT" => ROOT}, LEX_PARITY, path)
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
