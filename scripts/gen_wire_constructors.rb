#!/usr/bin/env ruby
# frozen_string_literal: true

# Generate fixed-layout WIRE instruction constructors and mechanically migrate
# literal instruction hashes to those constructors.

require "json"

ROOT = File.expand_path("..", __dir__)
SCHEMA_PATH = File.join(ROOT, "compiler/wire_instruction_schema.json")
OUTPUT_PATH = File.join(ROOT, "compiler/lib/wire_constructors.w")
SOURCE_GLOB = File.join(ROOT, "compiler/lib/**/*.w")

Call = Struct.new(:path, :start, :finish, :callee, :prefix, :entries, :op, :op_expr, keyword_init: true)

def fail_gen(message)
  warn "gen_wire_constructors: #{message}"
  exit 1
end

def matching_close(text, start, open_char, close_char)
  depth = 0
  quote = nil
  escape = false
  comment = false
  i = start
  while i < text.length
    ch = text[i]
    if comment
      comment = false if ch == "\n"
    elsif quote
      if escape
        escape = false
      elsif ch == "\\"
        escape = true
      elsif ch == quote
        quote = nil
      end
    elsif ch == "#"
      comment = true
    elsif ch == '"' || ch == "'"
      quote = ch
    elsif ch == open_char
      depth += 1
    elsif ch == close_char
      depth -= 1
      return i if depth.zero?
    end
    i += 1
  end
  nil
end

def split_top_level(text, delimiter = ",")
  parts = []
  start = 0
  stack = []
  quote = nil
  escape = false
  comment = false
  pairs = { "(" => ")", "[" => "]", "{" => "}" }
  text.each_char.with_index do |ch, i|
    if comment
      comment = false if ch == "\n"
    elsif quote
      if escape
        escape = false
      elsif ch == "\\"
        escape = true
      elsif ch == quote
        quote = nil
      end
    elsif ch == "#"
      comment = true
    elsif ch == '"' || ch == "'"
      quote = ch
    elsif pairs.key?(ch)
      stack << pairs[ch]
    elsif !stack.empty? && ch == stack.last
      stack.pop
    elsif ch == delimiter && stack.empty?
      parts << text[start...i].strip
      start = i + 1
    end
  end
  parts << text[start..].to_s.strip
  parts.reject(&:empty?)
end

def split_entry(entry)
  stack = []
  quote = nil
  escape = false
  pairs = { "(" => ")", "[" => "]", "{" => "}" }
  entry.each_char.with_index do |ch, i|
    if quote
      if escape
        escape = false
      elsif ch == "\\"
        escape = true
      elsif ch == quote
        quote = nil
      end
    elsif ch == '"' || ch == "'"
      quote = ch
    elsif pairs.key?(ch)
      stack << pairs[ch]
    elsif !stack.empty? && ch == stack.last
      stack.pop
    elsif ch == ":" && stack.empty?
      key = entry[0...i].strip
      value = entry[(i + 1)..].strip
      return [key, value] if key.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
    end
  end
  nil
end

def calls_in(path)
  text = File.read(path)
  calls = []
  pattern = /\b(emit_instruction|emit_return_instruction|wire_instruction)\s*\(/
  offset = 0
  while (match = pattern.match(text, offset))
    callee = match[1]
    open = text.index("(", match.begin(0))
    close = matching_close(text, open, "(", ")")
    break unless close
    args = split_top_level(text[(open + 1)...close])
    hash_index = callee == "wire_instruction" ? 0 : 1
    if args.length > hash_index
      hash = args[hash_index].strip
      if hash.start_with?("{") && matching_close(hash, 0, "{", "}") == hash.length - 1
        entries = split_top_level(hash[1...-1]).map { |entry| split_entry(entry) }
        if entries.all?
          op_entry = entries.find { |key, _value| key == "op" }
          if op_entry
            op_expr = op_entry[1]
            op = op_expr[/\A:([A-Za-z_][A-Za-z0-9_]*)\z/, 1]
            calls << Call.new(path: path, start: match.begin(0), finish: close + 1,
                              callee: callee, prefix: args[0], entries: entries,
                              op: op, op_expr: op_expr)
          end
        end
      end
    end
    offset = close + 1
  end
  [text, calls]
end

def source_paths
  Dir.glob(SOURCE_GLOB).sort.reject { |path| path == OUTPUT_PATH }
end

def discovered_schema
  schema = Hash.new { |hash, key| hash[key] = [] }
  source_paths.each do |path|
    _text, calls = calls_in(path)
    calls.each do |call|
      next unless call.op
      schema[call.op]
      call.entries.each do |key, _value|
        next if key == "op"
        schema[call.op] << key unless schema[call.op].include?(key)
      end
    end
  end
  schema.transform_values(&:sort).sort.to_h
end

def constructor_name(op)
  op.gsub(/[^A-Za-z0-9_]/, "_").downcase
end

def kind_ids
  text = File.read(File.join(ROOT, "compiler/lib/wire_schema.w"))
  body = text[/wire_kind_symbols\s*=\s*\[(.*?)\n\]/m, 1]
  fail_gen("cannot read wire_kind_symbols") unless body
  symbols = body.scan(/:([A-Za-z_][A-Za-z0-9_]*)/).flatten
  symbols.each_with_index.to_h { |symbol, index| [symbol, index + 1] }
end

def generate(schema)
  ids = kind_ids
  missing = schema.keys.reject { |op| ids.key?(op) }
  fail_gen("schema has unknown opcodes: #{missing.join(', ')}") unless missing.empty?
  suffixes = schema.keys.group_by { |op| constructor_name(op) }
  collisions = suffixes.select { |_suffix, ops| ops.length > 1 }
  fail_gen("constructor name collisions: #{collisions.inspect}") unless collisions.empty?

  out = []
  out << "# Generated by scripts/gen_wire_constructors.rb. Do not edit."
  out << "# Fields are stored in the canonical order recorded in"
  out << "# compiler/wire_instruction_schema.json."
  out << ""
  schema.each do |op, fields|
    suffix = constructor_name(op)
    params = fields.join(", ")
    out << "-> wire_make_#{suffix}(#{params})"
    out << "  handle = ccall_rawargs(\"w_wire_alloc\", #{ids.fetch(op)}, #{fields.length})"
    fields.each_with_index do |field, index|
      out << "  ccall_nobox(\"w_wire_field_store_at\", handle, #{index}, :#{field}, #{field})"
    end
    out << "  handle"
    out << ""
    emit_args = (["f"] + fields).join(", ")
    make_args = fields.join(", ")
    out << "-> emit_wire_#{suffix}(#{emit_args})"
    out << "  current_block(f)[:instructions].push(wire_make_#{suffix}(#{make_args}))"
    out << ""
  end

  # Dynamic opcode selectors (machine-width loads/stores and arithmetic
  # families) still use the same canonical symbol order, but resolve the kind
  # at runtime. They avoid allocating a temporary Hash while sharing one small
  # constructor family rather than emitting a selector branch for every site.
  (0..10).each do |count|
    pairs = (0...count).flat_map { |i| ["field#{i}", "value#{i}"] }
    params = (["op"] + pairs).join(", ")
    out << "-> wire_make_dynamic_#{count}(#{params})"
    out << "  kind_id = ccall_nobox(\"w_numeric_to_i64\", wire_kind_id(op))"
    out << "  handle = ccall_rawargs(\"w_wire_alloc\", kind_id, #{count})"
    (0...count).each do |i|
      out << "  ccall_nobox(\"w_wire_field_store_at\", handle, #{i}, field#{i}, value#{i})"
    end
    out << "  handle"
    out << ""
    out << "-> emit_wire_dynamic_#{count}(#{(["f"] + ["op"] + pairs).join(', ')})"
    out << "  current_block(f)[:instructions].push(wire_make_dynamic_#{count}(#{params}))"
    out << ""
  end
  out.join("\n").sub(/\n+\z/, "") + "\n"
end

def rewrite(schema)
  changed = 0
  source_paths.each do |path|
    text, calls = calls_in(path)
    next if calls.empty?
    replacements = []
    calls.each do |call|
      values = call.entries.to_h
      if call.op
        fields = schema[call.op]
        next unless fields
        args = fields.map { |field| values.fetch(field, "nil") }.join(", ")
        suffix = constructor_name(call.op)
        replacement = case call.callee
                      when "emit_instruction"
                        call_args = args.empty? ? call.prefix : "#{call.prefix}, #{args}"
                        "emit_wire_#{suffix}(#{call_args})"
                      when "emit_return_instruction"
                        "emit_return_instruction(#{call.prefix}, wire_make_#{suffix}(#{args}))"
                      else
                        "wire_make_#{suffix}(#{args})"
                      end
      else
        fields = values.keys.reject { |key| key == "op" }.sort
        fail_gen("dynamic instruction has more than 10 fields in #{call.path}") if fields.length > 10
        pairs = fields.flat_map { |field| [":#{field}", values.fetch(field)] }
        args = ([call.op_expr] + pairs).join(", ")
        replacement = case call.callee
                      when "emit_instruction"
                        "emit_wire_dynamic_#{fields.length}(#{call.prefix}, #{args})"
                      when "emit_return_instruction"
                        "emit_return_instruction(#{call.prefix}, wire_make_dynamic_#{fields.length}(#{args}))"
                      else
                        "wire_make_dynamic_#{fields.length}(#{args})"
                      end
      end
      replacements << [call.start, call.finish, replacement]
    end
    next if replacements.empty?
    replacements.reverse_each { |start, finish, replacement| text[start...finish] = replacement }
    File.write(path, text)
    changed += replacements.length
  end
  puts "rewrote #{changed} literal WIRE instruction constructors"
end

mode = ARGV.first
case mode
when "--bootstrap-schema"
  fail_gen("#{SCHEMA_PATH} already exists; use --update-schema") if File.exist?(SCHEMA_PATH)
  schema = discovered_schema
  File.write(SCHEMA_PATH, JSON.pretty_generate(schema) + "\n")
  puts "recorded #{schema.length} WIRE instruction layouts"
when "--update-schema"
  fail_gen("missing #{SCHEMA_PATH}; use --bootstrap-schema") unless File.file?(SCHEMA_PATH)
  schema = JSON.parse(File.read(SCHEMA_PATH))
  discovered_schema.each do |op, fields|
    schema[op] ||= []
    schema[op] = (schema[op] + fields).uniq.sort
  end
  File.write(SCHEMA_PATH, JSON.pretty_generate(schema.sort.to_h) + "\n")
  puts "updated #{schema.length} WIRE instruction layouts"
when "--write", "--rewrite", "--check"
  fail_gen("missing #{SCHEMA_PATH}") unless File.file?(SCHEMA_PATH)
  schema = JSON.parse(File.read(SCHEMA_PATH)).sort.to_h
  generated = generate(schema)
  if mode == "--check"
    fail_gen("generated constructors are stale; run scripts/gen_wire_constructors.rb --write") unless File.file?(OUTPUT_PATH) && File.read(OUTPUT_PATH) == generated
    remaining = source_paths.sum { |path| calls_in(path)[1].length }
    fail_gen("#{remaining} literal instruction hashes remain; run scripts/gen_wire_constructors.rb --rewrite") unless remaining.zero?
    puts "WIRE constructors are current (#{schema.length} layouts)"
  else
    File.write(OUTPUT_PATH, generated)
    rewrite(schema) if mode == "--rewrite"
    puts "generated #{schema.length} WIRE instruction constructors"
  end
else
  fail_gen("usage: #{$PROGRAM_NAME} --bootstrap-schema|--update-schema|--write|--rewrite|--check")
end
