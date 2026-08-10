#!/usr/bin/env ruby
# frozen_string_literal: true

# Audit the emitted Tungsten module rather than trusting symbol presence alone.
# Older partial bitwise ports use the same strong seam names, so the completion
# marker and an audited reachable call graph are both required for the full
# acceptance mode. Immutable seams must be entirely fallback-free. Consumed
# seams retain exactly one policy boundary: their direct raw helper may call
# the matching public operator for non-integer coercion/error handling.

path = ARGV.fetch(0) do
  warn "usage: #{$PROGRAM_NAME} FILE.ll [baseline|accept]"
  exit 2
end
mode = ARGV.fetch(1, "baseline")
unless %w[baseline accept].include?(mode)
  warn "mode must be baseline or accept"
  exit 2
end

ir = File.read(path)

functions = {}
header = /^define\b[^\n{]*@(?:"([^"]+)"|([-A-Za-z$._0-9]+))\([^\n]*\)[^{]*\{\n/
offset = 0
while (match = header.match(ir, offset))
  name = match[1] || match[2]
  body_start = match.end(0)
  body_end = ir.index(/^\}/, body_start)
  unless body_end
    warn "unterminated LLVM function #{name}"
    exit 1
  end
  body = ir[body_start...body_end]
  calls = body.scan(/\b(?:call|invoke)\b[^@\n]*@(?:"([^"]+)"|([-A-Za-z$._0-9]+))\s*\(/)
              .map { |quoted, plain| quoted || plain }
  functions[name] = { body: body, calls: calls }
  offset = body_end + 1
end

roots = {
  "and" => "__w_bigint_and_src",
  "or" => "__w_bigint_or_src",
  "xor" => "__w_bigint_xor_src",
  "and-mut" => "__w_bigint_and_mut_src",
  "or-mut" => "__w_bigint_or_mut_src",
  "xor-mut" => "__w_bigint_xor_mut_src"
}
marker = "__w_bigint_bitwise_source_complete"
problems = []

marker_fn = functions[marker]
marker_ok = marker_fn && marker_fn[:body].match?(/\bret i64 1\b/)
problems << "missing or invalid #{marker}" unless marker_ok

public_bitwise = /\Aw_bit_(?:and|or|xor)\z/
forbidden_math = /\A(?:w_bigint_(?:and|or|xor)(?:_c|_mut)|bignum_bitwise(?:_generic|_positive_equal)?)\z/

roots.each do |op, root|
  unless functions.key?(root)
    problems << "missing strong LLVM definition #{root}"
    puts "IR|#{op}|missing|#{root}"
    next
  end

  mut = op.end_with?("-mut")
  base_op = op.delete_suffix("-mut")
  raw_helper = nil
  if mut
    direct_helpers = functions.fetch(root)[:calls].select { |callee| functions.key?(callee) }.uniq
    if direct_helpers.length == 1
      raw_helper = direct_helpers.first
    else
      problems << "#{root} must call exactly one emitted raw helper"
    end
  end

  queue = [[root, [root]]]
  visited = {}
  bad_paths = []
  policy_paths = []
  while (item = queue.shift)
    name, chain = item
    next if visited[name]
    visited[name] = true
    fn = functions[name]
    next unless fn
    fn[:calls].each do |callee|
      next_chain = chain + [callee]
      if public_bitwise.match?(callee)
        if mut && name == raw_helper && callee == "w_bit_#{base_op}"
          policy_paths << next_chain
        else
          bad_paths << next_chain
        end
      elsif forbidden_math.match?(callee)
        bad_paths << next_chain
      end
      queue << [callee, next_chain] if functions.key?(callee)
    end
  end

  policy_paths.each do |chain|
    puts "IR|#{op}|allowed-noninteger-policy|#{chain.join(' -> ')}"
  end
  if mut && policy_paths.empty?
    problems << "#{root} is missing its guarded non-integer public policy edge"
  end

  if bad_paths.empty? && !mut
    puts "IR|#{op}|fallback-free|reachable=#{visited.length}"
  elsif bad_paths.empty?
    puts "IR|#{op}|integer-path-audited|reachable=#{visited.length}|policy_edges=#{policy_paths.length}"
  else
    bad_paths.each { |chain| puts "IR|#{op}|fallback|#{chain.join(' -> ')}" }
    problems << "#{root} reaches a retained-C or unexpected public fallback"
  end
end

puts "IR|marker|#{marker_ok ? 'complete' : 'missing'}|#{marker}"

if mode == "accept" && problems.any?
  warn "full bitwise IR acceptance failed: #{problems.uniq.join('; ')}"
  exit 1
end

# Baseline mode reports incomplete state but deliberately remains runnable so a
# pre-migration artifact can be captured with identical benchmark machinery.
exit 0
