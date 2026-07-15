#!/usr/bin/env ruby
# Static source audit for the isolated Lexer symbol-to-token-id direct-helper
# trial. This does not build or execute Tungsten code.

baseline_root = File.expand_path(ARGV.fetch(0) { "/tmp/tungsten-lexer-type-map-prep/baseline" })
candidate_root = File.expand_path(ARGV.fetch(1) { "/tmp/tungsten-lexer-type-map-prep/candidate" })

baseline_path = File.join(baseline_root, "compiler/lib/lexer.w")
candidate_path = File.join(candidate_root, "compiler/lib/lexer.w")
token_path = File.join(baseline_root, "core/token.w")

def fail_audit(message)
  warn "FAIL lexer type-map static audit: #{message}"
  exit 1
end

[baseline_path, candidate_path, token_path].each do |path|
  fail_audit("missing #{path}") unless File.file?(path)
end

baseline = File.binread(baseline_path)
candidate = File.binread(candidate_path)
token_source = File.binread(token_path)

# Normalize only the three declared edits: remove the added top-level helper
# block, restore the exact old public mapping block, and restore the two hot
# call spellings. Byte equality after that proves comments, strings, and all
# unrelated code were untouched.
baseline_mapping = baseline[/^  # Map a token symbol.*?(?=^  -> emit_at\(type, value, off\)$)/m]
candidate_wrappers = candidate[/^  # Public compatibility wrappers.*?(?=^  -> emit_at\(type, value, off\)$)/m]
fail_audit("could not locate baseline mapping block") unless baseline_mapping
fail_audit("could not locate candidate wrapper block") unless candidate_wrappers

normalized = candidate.dup
unless normalized.sub!(/^# Lexer-internal symbol-to-id mapping is top-level.*?(?=^\+ Lexer$)/m, "")
  fail_audit("could not locate one top-level helper block")
end
fail_audit("multiple top-level helper blocks") if normalized.match?(/^# Lexer-internal symbol-to-id mapping is top-level/m)
unless normalized.sub!(candidate_wrappers, baseline_mapping)
  fail_audit("could not restore the public mapping block")
end

direct_call = "type_id = lexer_type_sym_to_id(type)"
direct_calls = normalized.scan(direct_call).length
fail_audit("expected two internal direct calls, found #{direct_calls}") unless direct_calls == 2
normalized.gsub!(direct_call, "type_id = type_sym_to_id(type)")
fail_audit("candidate has changes outside the declared transformation") unless normalized == baseline

def mapping_pairs(source, region_pattern)
  region = source[region_pattern]
  fail_audit("could not locate mapping region #{region_pattern.inspect}") unless region
  region.scan(/^\s*when :([A-Z0-9_]+) then ([0-9]+)$/).map { |name, id| [name, id.to_i] }
end

baseline_pairs = mapping_pairs(
  baseline,
  /^  -> type_sym_to_id_a\(sym\)$.*?(?=^  -> emit_at\(type, value, off\)$)/m
)
candidate_pairs = mapping_pairs(
  candidate,
  /^-> lexer_type_sym_to_id_a\(sym\)$.*?(?=^\+ Lexer$)/m
)
fail_audit("top-level mapping differs from baseline order or values") unless candidate_pairs == baseline_pairs
fail_audit("expected 133 refined token mappings, found #{candidate_pairs.length}") unless candidate_pairs.length == 133
fail_audit("duplicate token symbols") unless candidate_pairs.map(&:first).uniq.length == candidate_pairs.length
fail_audit("duplicate token ids") unless candidate_pairs.map(&:last).uniq.length == candidate_pairs.length

token_pairs = token_source.scan(/^T_([A-Z0-9_]+)\s*=\s*([0-9]+)(?:\s|$)/).map do |name, id|
  [name, id.to_i]
end.select { |_name, id| id <= 159 }

unknown = token_pairs.assoc("UNKNOWN")
op = token_pairs.assoc("OP")
fail_audit("T_UNKNOWN must remain id 0") unless unknown == ["UNKNOWN", 0]
fail_audit("T_OP must remain broad-only id 11") unless op == ["OP", 11]
refined_constants = token_pairs.reject { |name, _id| name == "UNKNOWN" || name == "OP" }
unless candidate_pairs == refined_constants
  missing = refined_constants - candidate_pairs
  extra = candidate_pairs - refined_constants
  fail_audit("core/token.w mismatch; missing=#{missing.inspect} extra=#{extra.inspect}")
end

# Audit every slot, including deliberately unused gaps, rather than checking
# only the mapped entries.
constants_by_id = token_pairs.to_h { |name, id| [id, name] }
mapping_by_id = candidate_pairs.to_h { |name, id| [id, name] }
(0..159).each do |id|
  constant = constants_by_id[id]
  mapped = mapping_by_id[id]
  if constant && constant != "UNKNOWN" && constant != "OP"
    fail_audit("id #{id} maps #{mapped.inspect}, expected #{constant}") unless mapped == constant
  else
    fail_audit("unassigned/broad id #{id} unexpectedly maps to #{mapped}") if mapped
  end
end

%w[
  lexer_type_sym_to_id
  lexer_type_sym_to_id_a
  lexer_type_sym_to_id_b
  lexer_type_sym_to_id_c
].each do |name|
  count = candidate.scan(/^-> #{name}\(sym\)$/).length
  fail_audit("expected one top-level #{name}, found #{count}") unless count == 1
end

wrapper_expectations = {
  "type_sym_to_id" => "lexer_type_sym_to_id",
  "type_sym_to_id_a" => "lexer_type_sym_to_id_a",
  "type_sym_to_id_b" => "lexer_type_sym_to_id_b",
  "type_sym_to_id_c" => "lexer_type_sym_to_id_c"
}
wrapper_expectations.each do |public_name, direct_name|
  pattern = /^  -> #{public_name}\(sym\)\n    #{direct_name}\(sym\)$/
  fail_audit("public wrapper #{public_name} is not the exact one-call wrapper") unless candidate.scan(pattern).length == 1
end

production_roots = %w[compiler core languages].map { |dir| File.join(candidate_root, dir) }
production_sources = production_roots.flat_map { |root| Dir.glob(File.join(root, "**/*.w")) }
subclasses = production_sources.flat_map do |path|
  File.readlines(path, chomp: true).each_with_index.filter_map do |line, index|
    [path, index + 1, line] if line.match?(/^\+\s+\S+\s+<\s+Lexer\b/)
  end
end
unless subclasses.empty?
  fail_audit("production Lexer subclass would invalidate devirtualization: #{subclasses.inspect}")
end

lexer_declarations = production_sources.flat_map do |path|
  File.readlines(path, chomp: true).each_with_index.filter_map do |line, index|
    [path, index + 1, line] if line == "+ Lexer"
  end
end
unless lexer_declarations == [[candidate_path, candidate.lines.find_index { |line| line == "+ Lexer\n" } + 1, "+ Lexer"]]
  fail_audit("Lexer is reopened outside its canonical declaration: #{lexer_declarations.inspect}")
end

mapping_definitions = production_sources.flat_map do |path|
  File.readlines(path, chomp: true).each_with_index.filter_map do |line, index|
    if line.match?(/^  -> type_sym_to_id(?:_[abc])?\(sym\)$/)
      [path, index + 1, line]
    end
  end
end
unless mapping_definitions.length == 4 && mapping_definitions.all? { |entry| entry[0] == candidate_path }
  fail_audit("mapping override/redefinition found: #{mapping_definitions.inspect}")
end

puts "PASS lexer type-map static audit: exact source transform"
puts "PASS mapping audit: 133/133 core token constants, every id 0..159 checked"
puts "PASS devirtualization audit: no Lexer subclass in compiler/core/languages"
puts "NOTE external subclasses overriding type_sym_to_id cannot affect inherited emit/emit_at"
