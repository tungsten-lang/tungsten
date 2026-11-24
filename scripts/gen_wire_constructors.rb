#!/usr/bin/env ruby
# frozen_string_literal: true

# Generate fixed-layout WIRE instruction constructors and mechanically migrate
# literal instruction hashes to those constructors.

require "json"

ROOT = File.expand_path("..", __dir__)
SCHEMA_PATH = File.join(ROOT, "compiler/wire_instruction_schema.json")
OUTPUT_PATH = File.join(ROOT, "compiler/lib/wire_constructors.w")
SCHEMA_HEADER_PATH = File.join(ROOT, "runtime/wire_schema_table.h")
SOURCE_GLOB = File.join(ROOT, "compiler/lib/**/*.w")

Call = Struct.new(:path, :start, :finish, :callee, :prefix, :entries, :op, :op_expr, keyword_init: true)

# Variable-width instruction operands live as dense WIRE-arena sequences.
# The field names are schema-wide contracts: every instruction use of one of
# these names is a WValue list (or nil), never a scalar.
WIRE_SEQUENCE_FIELDS = %w[arg_types args cases fields incoming s].freeze

# Instructions that commonly receive late non-schema metadata via wire_set
# (e.g. :fast_builtin, :sym_idx_get, :function_recycle_count, :ascope, :call_conv).
# All other packed kinds allocate extra_cap = 0 and spill any unexpected late
# field into the sparse runtime overflow table.
EXTRA_CAP_OPS = {
  "call_direct_i64" => 2,
  "call_direct_void" => 2,
  "call_direct_ptr" => 2,
  "call_direct_i128" => 2,
  "call_direct_i64_ptr1" => 2,
  "call_direct_void_ptr1" => 2,
  "call_method_i64" => 4,
  "ret_i64" => 2,
  "ret_i32" => 2,
  "ret_void" => 2,
  "typed_array_get_inline" => 2,
  "typed_array_set_inline" => 2,
  "typed_array_compound_op_inline" => 2,
  "small_array_get_inline" => 2,
  "small_array_set_inline" => 2,
  "big_array_get_inline" => 2,
  "phi_i64" => 2,
  "phi_ssa" => 2
}.freeze

SUBST_NO_OP_KINDS = %w[
  br call_loc_set_col load_class load_global ret_void string_i64 symbol_i64 const_float
].freeze

SUBST_SCALAR_FIELDS = %w[
  value lhs rhs ptr index raw boxed cond buf table arr idx arg dest base cap node
  a_value b_value receiver self_reg then_val else_val lhs_boxed rhs_boxed super_reg
  class_temp captures_ptr method_name_val
].freeze

SUBST_ASM_FIELDS = %w[outp ap bp vp twp ivp n ooff aoff boff bsc na nb hq].freeze

# Opcodes whose fixed slot indices are exported as top-level `## i64` constants
# (`WIRE_SLOT_<OP>_<FIELD>`) for inlined positional `w_wire_slot_load` reads in
# the hottest WIRE passes (emitter, content_hash, wire CSE/DSE, ownership).
HOT_SLOT_CONST_OPS = %w[
  add_i64 alloca_array alloca_i64 and_i1 and_i64 array_size_raw ashr_i64
  bigint_literal_i64 br builtin_class_init call_direct_i128 call_direct_i64
  call_direct_i64_ptr1 call_direct_ptr call_direct_void call_direct_void_ptr1
  call_loc_set_col call_method_i64 class_add_method class_add_static_method
  class_new class_store closure_new cond_br const_float fadd_f64 fdiv_f64
  fmul_f64 free_value frem_f64 fsub_f64 gep_array i64_to_ptr icmp_eq_i32
  icmp_i64 icmp_ne_i64 icmp_ne_zero inttoptr_i64 ivar_get ivar_get_idx
  ivar_set ivar_set_idx load_class load_cvar load_double load_float
  load_global load_i128 load_i64 load_ptr lshr_i64 mul_i64 nanbox_bool
  nanbox_float nanbox_int nanunbox_float nanunbox_int node_kind_class_register
  not_i1 null_ptr or_i1 or_i64 phi_i64 phi_ssa print_i64 ptr_to_i64 puts_i64
  recycle_object ret_i32 ret_i64 sdiv_i64 select_i64 setjmp shl_i64 srem_i64
  store_cvar store_double store_float store_global store_i128 store_i64
  store_ptr string_i64 sub_i64 switch_i64 symbol_i64 ta_size_raw
  trunc_i64_i32 truthy_inline type_class_register typed_array_get_inline
  typed_array_set_inline udiv_i64 urem_i64 xor_i64 zext_i1_i64
].freeze

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
  # Comments inside the literal may mention symbols (`:type, :value`); only
  # the elements themselves number the kinds.
  body = body.gsub(/#[^\n]*/, "")
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
  out << "WIRE_KIND_MAX = #{ids.values.max} ## i64"
  ids.sort_by { |_op, id| id }.each do |op, id|
    out << "WIRE_KIND_#{constructor_name(op).upcase} = #{id} ## i64"
  end
  out << ""
  HOT_SLOT_CONST_OPS.each do |op|
    fields = schema[op]
    next unless fields
    prefix = "WIRE_SLOT_#{constructor_name(op).upcase}"
    fields.each_with_index do |field, idx|
      out << "#{prefix}_#{field.upcase} = #{idx} ## i64"
    end
  end
  out << "WIRE_SLOT_WIRE_TYPED_VALUE_TYPE = 0 ## i64"
  out << "WIRE_SLOT_WIRE_TYPED_VALUE_VALUE = 1 ## i64"
  out << ""
  schema.each do |op, fields|
    suffix = constructor_name(op)
    params = fields.join(", ")
    id = ids.fetch(op)
    packed_vals = fields.map { |field| WIRE_SEQUENCE_FIELDS.include?(field) ? "wire_sequence(#{field})" : field }
    out << "-> wire_make_#{suffix}(#{params})"
    packed_args = ([id.to_s] + packed_vals).join(", ")
    out << "  ccall_rawargs(\"w_wire_packed_#{fields.length}\", #{packed_args})"
    out << ""
    emit_args = (["f"] + fields).join(", ")
    make_args = fields.join(", ")
    out << "-> emit_wire_#{suffix}(#{emit_args})"
    out << "  ccall_rawargs(\"w_wire_func_push_inst\", f, wire_make_#{suffix}(#{make_args}))"
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
      out << "  if wire_sequence_field?(field#{i})"
      out << "    value#{i} = wire_sequence(value#{i})"
      out << "  ccall_nobox(\"w_wire_field_store_at\", handle, #{i}, field#{i}, value#{i})"
    end
    out << "  handle"
    out << ""
    out << "-> emit_wire_dynamic_#{count}(#{(["f"] + ["op"] + pairs).join(', ')})"
    out << "  ccall_rawargs(\"w_wire_func_push_inst\", f, wire_make_dynamic_#{count}(#{params}))"
    out << ""
  end
  out.join("\n").sub(/\n+\z/, "") + "\n"
end

def generate_schema_header(schema)
  ids = kind_ids
  max_kind = ids.values.max + 1
  entries = {}
  schema.each do |op, fields|
    entries[ids.fetch(op)] = [op, fields]
  end
  # Compiler-internal typed_value record (kind 268): fixed 2-slot schema.
  tv_id = ids.fetch("wire_typed_value")
  entries[tv_id] = ["wire_typed_value", %w[type value]]

  # Deterministic FNV-1a 32-bit fingerprint of (kind_id, fixed_count, field_names)
  # so serialized packed caches auto-invalidate if any schema layout changes.
  fp = 0x811c9dc5
  entries.keys.sort.each do |kid|
    op, fields = entries[kid]
    sig = "#{kid}:#{op}:#{fields.join(',')};"
    sig.each_byte do |b|
      fp ^= b
      fp = (fp * 0x01000193) & 0xFFFFFFFF
    end
  end

  out = []
  out << "/* Generated by scripts/gen_wire_constructors.rb. Do not edit. */"
  out << "#ifndef W_WIRE_SCHEMA_TABLE_H"
  out << "#define W_WIRE_SCHEMA_TABLE_H"
  out << ""
  out << "#include <stdint.h>"
  out << "#include <stddef.h>"
  out << ""
  out << "#define W_WIRE_SCHEMA_MAX_KIND #{max_kind}"
  out << "#define W_WIRE_SCHEMA_MAX_FIELDS 16"
  out << format("#define W_WIRE_SCHEMA_FINGERPRINT UINT32_C(0x%08x)", fp)
  out << ""
  out << "typedef struct WWireKindSchema {"
  out << "    uint8_t fixed_count;"
  out << "    uint8_t extra_cap;"
  out << "    uint8_t temp_slot;"
  out << "    uint8_t is_schema;"
  out << "    uint16_t sequence_mask;"
  out << "    uint16_t subst_scalar_mask;"
  out << "    uint16_t subst_seq_mask;"
  out << "    const char *const *field_names;"
  out << "} WWireKindSchema;"
  out << ""

  entries.keys.sort.each do |kid|
    op, fields = entries[kid]
    next if fields.empty?
    cname = constructor_name(op)
    items = fields.map { |f| "\"#{f}\"" }.join(", ")
    out << "static const char *const w_wire_schema_fields_#{cname}[#{fields.length}] = { #{items} };"
  end
  out << ""
  out << "static const WWireKindSchema g_wire_kind_schemas[W_WIRE_SCHEMA_MAX_KIND] = {"
  entries.keys.sort.each do |kid|
    op, fields = entries[kid]
    cname = constructor_name(op)
    extra_cap = EXTRA_CAP_OPS.fetch(op, 0)
    temp_slot = fields.index("temp") || 255
    seq_mask = 0
    subst_scalar_mask = 0
    subst_seq_mask = 0
    is_asm = op.start_with?("asm_") && op != "asm_add_test"
    no_subst = SUBST_NO_OP_KINDS.include?(op) || op == "wire_typed_value"
    fields.each_with_index do |f, i|
      seq_mask |= (1 << i) if WIRE_SEQUENCE_FIELDS.include?(f)
      next if no_subst
      if f == "args" || f == "s" || (op == "slab_alloc_init" && f == "fields") || (op == "phi_ssa" && f == "incoming")
        subst_seq_mask |= (1 << i)
      elsif SUBST_SCALAR_FIELDS.include?(f) || (is_asm && SUBST_ASM_FIELDS.include?(f)) || (f == "val" && (op == "bool_array_set_inline" || op == "bool_array_set_byte_inline"))
        subst_scalar_mask |= (1 << i)
      end
    end
    fn_ptr = fields.empty? ? "NULL" : "w_wire_schema_fields_#{cname}"
    out << format("    [%d] = { %d, %d, %d, 1, 0x%04xu, 0x%04xu, 0x%04xu, %s }, /* %s */",
                  kid, fields.length, extra_cap, temp_slot, seq_mask, subst_scalar_mask, subst_seq_mask, fn_ptr, op)
  end
  out << "};"
  out << ""
  out << "#endif /* W_WIRE_SCHEMA_TABLE_H */"
  out.join("\n") + "\n"
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
  header = generate_schema_header(schema)
  if mode == "--check"
    fail_gen("generated constructors are stale; run scripts/gen_wire_constructors.rb --write") unless File.file?(OUTPUT_PATH) && File.read(OUTPUT_PATH) == generated
    fail_gen("generated runtime/wire_schema_table.h is stale; run scripts/gen_wire_constructors.rb --write") unless File.file?(SCHEMA_HEADER_PATH) && File.read(SCHEMA_HEADER_PATH) == header
    remaining = source_paths.sum { |path| calls_in(path)[1].length }
    fail_gen("#{remaining} literal instruction hashes remain; run scripts/gen_wire_constructors.rb --rewrite") unless remaining.zero?
    puts "WIRE constructors are current (#{schema.length} layouts)"
  else
    File.write(OUTPUT_PATH, generated)
    File.write(SCHEMA_HEADER_PATH, header)
    rewrite(schema) if mode == "--rewrite"
    puts "generated #{schema.length} WIRE instruction constructors + runtime/wire_schema_table.h"
  end
else
  fail_gen("usage: #{$PROGRAM_NAME} --bootstrap-schema|--update-schema|--write|--rewrite|--check")
end
