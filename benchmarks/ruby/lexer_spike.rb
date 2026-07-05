#!/usr/bin/env ruby
# frozen_string_literal: true

require "benchmark"
require "objspace"

ROOT = File.expand_path("../..", __dir__)
GEM_LIB = File.join(ROOT, "implementations", "ruby", "lib")
$LOAD_PATH.unshift(GEM_LIB) unless $LOAD_PATH.include?(GEM_LIB)

require "tungsten"
require "tungsten/codepoint_lexer"

RUNS = Integer(ENV.fetch("RUNS", "10"))
WARMUP = Integer(ENV.fetch("WARMUP", "2"))
DETAIL = ENV.fetch("DETAIL", "0") != "0"
FILE_SET = ENV.fetch("FILES", "compiler")
PROFILE_ONLY = ENV.fetch("PROFILE_ONLY", "0") != "0"
TOKEN_PROFILE = ENV.fetch("TOKEN_PROFILE", ENV.fetch("TOKEN_COUNTS", "0")) != "0"
TOKEN_PROFILE_LIMIT = Integer(ENV.fetch("TOKEN_PROFILE_LIMIT", "50"))
COUNT_KEYS = %i[T_ARRAY T_HASH T_STRING T_OBJECT].freeze

def compiler_files
  Dir[File.join(ROOT, "compiler", "lib", "*.w")].sort
end

def project_w_files
  Dir.glob(File.join(ROOT, "**", "*.w"), File::FNM_DOTMATCH)
     .reject { |path| path.include?("/.git/") }
     .sort
end

def token_pairs(lexer_class, source)
  lexer_class.new(source).tokens.map { |token| [token.type, token.value] }
end

def first_mismatch(ref, alt)
  i = 0
  i += 1 while ref[i] == alt[i]
  i
end

def selected_paths
  return ARGV.map { |path| File.expand_path(path, ROOT) } unless ARGV.empty?

  case FILE_SET
  when "compiler"
    compiler_files
  when "all", "repo", "comparable"
    project_w_files
  else
    abort "unknown FILES=#{FILE_SET.inspect}; use compiler, comparable, repo, or explicit paths"
  end
end

def validate_cases(paths, comparable_only: false)
  cases = []
  skipped_reference_errors = 0

  paths.each do |path|
    source = File.read(path)
    begin
      ref = token_pairs(Tungsten::Lexer, source)
    rescue StandardError
      raise unless comparable_only

      skipped_reference_errors += 1
      next
    end

    alt = token_pairs(Tungsten::CodepointLexer, source)

    unless ref == alt
      i = first_mismatch(ref, alt)
      warn "token mismatch in #{path}"
      warn "  index: #{i}"
      warn "  regex:     #{ref[i].inspect}"
      warn "  codepoint: #{alt[i].inspect}"
      exit 1
    end

    cases << [path, source, ref.length]
  end

  [cases, skipped_reference_errors]
end

def lex_all(cases, lexer_class)
  count = 0
  cases.each do |(_path, source, _tokens)|
    count += lexer_class.new(source).tokens.length
  end
  count
end

def profile_codepoint_tokens(cases)
  token_counts = Hash.new(0)
  branch_counts = Hash.new(0)
  regex_attempts = Hash.new(0)
  regex_hits = Hash.new(0)
  count = 0

  cases.each do |(_path, source, _tokens)|
    lexer = Tungsten::CodepointLexer.new(source, profile: true)
    count += lexer.tokens.length
    lexer.profile_token_counts.each { |type, n| token_counts[type] += n }
    lexer.profile_branch_counts.each { |byte, n| branch_counts[byte] += n }
    lexer.profile_regex_attempts.each { |label, n| regex_attempts[label] += n }
    lexer.profile_regex_hits.each { |label, n| regex_hits[label] += n }
  end

  [count, token_counts, branch_counts, regex_attempts, regex_hits]
end

def print_count_table(title, counts, total, limit)
  puts
  puts title
  counts.sort_by { |key, count| [-count, key.to_s] }.first(limit).each do |key, count|
    pct = total.zero? ? 0.0 : (count * 100.0 / total)
    puts "  %9d  %6.2f%%  %s" % [count, pct, yield(key)]
  end
end

def branch_byte_label(byte)
  name =
    case byte
    when 10 then "\\n"
    when 32 then "space"
    when 34..126 then byte.chr.inspect
    else "byte"
    end

  "%3d  0x%02x  %s" % [byte, byte, name]
end

def print_regex_profile(attempts, hits, limit)
  total = attempts.values.sum

  puts
  puts "codepoint fallback regex attempts"
  attempts.sort_by { |label, count| [-count, label.to_s] }.first(limit).each do |label, count|
    hit_count = hits[label]
    miss_count = count - hit_count
    pct = total.zero? ? 0.0 : (count * 100.0 / total)
    miss_pct = count.zero? ? 0.0 : (miss_count * 100.0 / count)
    puts "  %9d  %6.2f%%  misses=%-8d %6.2f%%  %s" % [count, pct, miss_count, miss_pct, label.inspect]
  end
end

def allocation_delta(cases, lexer_class)
  begin
    GC.start
    GC.disable
    before = ObjectSpace.count_objects
    tokens = lex_all(cases, lexer_class)
    after = ObjectSpace.count_objects
  ensure
    GC.enable
  end

  [tokens, COUNT_KEYS.to_h { |key| [key, after[key] - before[key]] }]
end

def elapsed_for(cases, lexer_class)
  WARMUP.times { lex_all(cases, lexer_class) }
  tokens = 0
  elapsed = Benchmark.realtime do
    RUNS.times { tokens = lex_all(cases, lexer_class) }
  end
  [elapsed, tokens]
end

comparable_only = FILE_SET == "comparable"
paths = selected_paths
cases, skipped_reference_errors = validate_cases(paths, comparable_only: comparable_only)
token_count = cases.sum { |(_path, _source, tokens)| tokens }

puts "files=#{cases.length} tokens=#{token_count} runs=#{RUNS}"
puts "skipped_reference_errors=#{skipped_reference_errors}" if skipped_reference_errors.positive?

if DETAIL
  cases.each do |(path, _source, tokens)|
    puts "%7d  %s" % [tokens, path.delete_prefix("#{ROOT}/")]
  end
end

if TOKEN_PROFILE
  profile_tokens, token_counts, branch_counts, regex_attempts, regex_hits = profile_codepoint_tokens(cases)
  raise "profile token count drift" unless profile_tokens == token_count

  print_count_table("codepoint token counts", token_counts, profile_tokens, TOKEN_PROFILE_LIMIT, &:inspect)
  print_count_table(
    "codepoint scan_token first-byte counts", branch_counts, branch_counts.values.sum, TOKEN_PROFILE_LIMIT
  ) do |byte|
    branch_byte_label(byte)
  end
  print_regex_profile(regex_attempts, regex_hits, TOKEN_PROFILE_LIMIT)
end

if PROFILE_ONLY
  puts
  puts "profile_only=true"
  exit
end

regex_elapsed, regex_tokens = elapsed_for(cases, Tungsten::Lexer)
codepoint_elapsed, codepoint_tokens = elapsed_for(cases, Tungsten::CodepointLexer)

raise "token count drift" unless regex_tokens == codepoint_tokens

regex_per_run = regex_elapsed / RUNS
codepoint_per_run = codepoint_elapsed / RUNS
speedup = regex_per_run / codepoint_per_run

puts
puts "timing"
puts "  regex:     %0.6fs/run  %8.0f tokens/s" % [regex_per_run, regex_tokens / regex_per_run]
puts "  codepoint: %0.6fs/run  %8.0f tokens/s" % [codepoint_per_run, codepoint_tokens / codepoint_per_run]
puts "  speedup:   %0.2fx" % speedup

regex_alloc_tokens, regex_alloc = allocation_delta(cases, Tungsten::Lexer)
codepoint_alloc_tokens, codepoint_alloc = allocation_delta(cases, Tungsten::CodepointLexer)

raise "allocation token count drift" unless regex_alloc_tokens == codepoint_alloc_tokens

puts
puts "allocations for one full pass"
COUNT_KEYS.each do |key|
  regex_count = regex_alloc[key]
  codepoint_count = codepoint_alloc[key]
  ratio = codepoint_count.zero? ? Float::INFINITY : regex_count.to_f / codepoint_count
  puts "  %-8s regex=%-9d codepoint=%-9d ratio=%0.2fx" % [key, regex_count, codepoint_count, ratio]
end
