#!/usr/bin/env ruby
# frozen_string_literal: true

ROOT = File.expand_path("../..", __dir__)
GEM_LIB = File.join(ROOT, "implementations", "ruby", "lib")
$LOAD_PATH.unshift(GEM_LIB) unless $LOAD_PATH.include?(GEM_LIB)

require "tungsten"
require "tungsten/codepoint_lexer"

MAX_EXAMPLES = Integer(ENV.fetch("EXAMPLES", "20"))

def w_files
  Dir.glob("**/*.w", File::FNM_DOTMATCH)
     .reject { |path| path.start_with?(".git/") }
     .sort
end

def token_pairs(lexer_class, source)
  lexer_class.new(source).tokens.map { |token| [token.type, token.value] }
end

def first_mismatch(left, right)
  i = 0
  i += 1 while i < left.length && i < right.length && left[i] == right[i]
  i
end

summary = Hash.new(0)
mismatch_types = Hash.new(0)
examples = Hash.new { |hash, key| hash[key] = [] }

w_files.each do |path|
  source = File.read(path)
  reference = codepoint = reference_error = codepoint_error = nil

  begin
    reference = token_pairs(Tungsten::Lexer, source)
  rescue StandardError => e
    reference_error = e
  end

  begin
    codepoint = token_pairs(Tungsten::CodepointLexer, source)
  rescue StandardError => e
    codepoint_error = e
  end

  if reference_error && codepoint_error
    summary[:both_error] += 1
    examples[:both_error] << [
      path,
      reference_error.message.lines.first&.strip,
      codepoint_error.message.lines.first&.strip
    ]
  elsif reference_error
    summary[:reference_error_only] += 1
    examples[:reference_error_only] << [path, reference_error.message.lines.first&.strip, codepoint&.length]
  elsif codepoint_error
    summary[:codepoint_error_only] += 1
    examples[:codepoint_error_only] << [path, codepoint_error.message.lines.first&.strip]
  elsif reference == codepoint
    summary[:match] += 1
  else
    summary[:mismatch] += 1
    i = first_mismatch(reference, codepoint)
    mismatch_types[reference[i]&.first] += 1
    examples[:mismatch] << [path, i, reference[i], codepoint[i]]
  end
end

total = summary.values_at(:match, :mismatch, :codepoint_error_only, :reference_error_only, :both_error).sum
comparable = summary[:match] + summary[:mismatch] + summary[:codepoint_error_only]

puts "total=#{total}"
puts "comparable=#{comparable}"
%i[match mismatch codepoint_error_only reference_error_only both_error].each do |key|
  puts "#{key}=#{summary[key]}"
end

unless mismatch_types.empty?
  types = mismatch_types.sort_by { |type, count| [-count, type.to_s] }
                        .map { |type, count| "#{type}:#{count}" }
                        .join(", ")
  puts "mismatch_types=#{types}"
end

%i[mismatch codepoint_error_only reference_error_only both_error].each do |key|
  next if examples[key].empty?

  puts
  puts "#{key} examples:"
  examples[key].first(MAX_EXAMPLES).each { |example| puts "  #{example.inspect}" }
end

exit 1 if summary[:mismatch].positive? || summary[:codepoint_error_only].positive?
