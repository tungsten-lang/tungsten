#!/usr/bin/env ruby
# frozen_string_literal: true

# Generate the derived slab-AST lookup tables from the canonical declarations
# in compiler/lib/ast.w and the stable KIND_* registry in ast_schema.w.

ROOT = File.expand_path("..", __dir__)
AST_PATH = File.join(ROOT, "compiler/lib/ast.w")
SCHEMA_PATH = File.join(ROOT, "compiler/lib/ast_schema.w")
HEADER_PATH = File.join(ROOT, "runtime/ast_schema_generated.h")

START_MARKER = "# BEGIN GENERATED AST ABI\n"
END_MARKER = "# END GENERATED AST ABI\n"

Kind = Struct.new(
  :constant, :id, :name, :public_name, :class_name, :storage, :sclass, :fields,
  keyword_init: true
)
Field = Struct.new(:name, :type, keyword_init: true)

def fail_schema(message)
  warn "gen_ast_schema: #{message}"
  exit 1
end

def parse_kind_registry(schema)
  kinds = {}
  schema.scan(/^KIND_([A-Z0-9_]+)\s*=\s*(\d+)\s+## i64$/) do |suffix, id_text|
    constant = "KIND_#{suffix}"
    next if constant == "KIND_MAX"

    id = Integer(id_text, 10)
    fail_schema("duplicate kind id #{id}") if kinds.value?(id)
    kinds[constant] = id
  end
  fail_schema("no KIND_* registry found") if kinds.empty?
  kinds
end

def constructor_metadata(block, class_name)
  if (match = block.match(/slab_alloc_init\((KIND_[A-Z0-9_]+),\s*(SC_(?:2|4|8|16))/))
    return [match[1], "slab", match[2]]
  end
  if (match = block.match(/w_ast_intern_node",\s*(KIND_[A-Z0-9_]+)/))
    return [match[1], "intern", "SC_2"]
  end
  if (match = block.match(/w_node_inline_payload",\s*(KIND_[A-Z0-9_]+)/))
    return [match[1], "inline", "SC_2"]
  end
  if (match = block.match(/w_node_singleton",\s*(KIND_[A-Z0-9_]+)/))
    return [match[1], "singleton", "SC_2"]
  end
  if block.include?('w_ast_bool_cached')
    explicit = block[/# ast-kind:\s*(KIND_[A-Z0-9_]+)/, 1]
    fail_schema("#{class_name} cached constructor needs '# ast-kind: KIND_*'") unless explicit
    return [explicit, "cached", "SC_2"]
  end

  fail_schema("#{class_name} has no recognized slab constructor")
end

def parse_ast_declarations(ast, registry)
  declarations = {}
  class_pattern = /^\+ (\w+) < Node \[slab\]\n(.*?)(?=^\+ \w+ < Node \[slab\]|\z)/m
  ast.scan(class_pattern) do |class_name, block|
    constant, storage, sclass = constructor_metadata(block, class_name)
    fail_schema("#{class_name} references unknown #{constant}") unless registry.key?(constant)
    fail_schema("#{constant} is declared by two AST classes") if declarations.key?(constant)

    fields = block.scan(/^\s+@(\w+)\s+(ast|w64|inline\((?:21|32)\))/).map do |name, type|
      normalized = type.start_with?("inline") ? "inline" : type
      Field.new(name: name, type: normalized)
    end
    if %w[inline intern cached].include?(storage) && fields.size != 1
      fail_schema("#{class_name} #{storage} storage requires exactly one declared field")
    end
    fail_schema("#{class_name} singleton cannot declare fields") if storage == "singleton" && !fields.empty?

    internal_name = constant.delete_prefix("KIND_").downcase
    public_name = block[/# ast-public-kind:\s*(\w+)/, 1] || internal_name
    declarations[constant] = Kind.new(
      constant: constant,
      id: registry.fetch(constant),
      name: internal_name,
      public_name: public_name,
      class_name: class_name,
      storage: storage,
      sclass: sclass,
      fields: fields
    )
  end

  missing = registry.keys - declarations.keys
  extra = declarations.keys - registry.keys
  fail_schema("registry kinds without AST classes: #{missing.join(', ')}") unless missing.empty?
  fail_schema("AST classes without registry kinds: #{extra.join(', ')}") unless extra.empty?
  declarations.values.sort_by(&:id)
end

def symbol_literal(name)
  ":#{name}"
end

def hash_literal(fields, storage)
  pairs = fields.each_with_index.map do |field, index|
    offset = case storage
             when "inline" then "OFFSET_INLINE"
             when "intern" then "OFFSET_INTERN"
             else index.to_s
             end
    "#{symbol_literal(field.name)} => #{offset}"
  end
  "{" + pairs.join(", ") + "}"
end

def type_hash_literal(fields)
  pairs = fields.map { |field| "#{symbol_literal(field.name)} => #{symbol_literal(field.type)}" }
  "{" + pairs.join(", ") + "}"
end

def physical_offset(kind, index)
  case kind.storage
  when "inline" then 256
  when "intern" then 257
  else index
  end
end

def schema_hash(kinds)
  bytes = +"tungsten-ast-schema-v2-exact-width\0"
  kinds.each do |kind|
    bytes << [
      kind.id, kind.constant, kind.name, kind.public_name, kind.class_name,
      kind.storage, kind.sclass, kind.fields.size
    ].join("\0") << "\0"
    kind.fields.each_with_index do |field, index|
      bytes << [index, field.name, field.type, physical_offset(kind, index)].join("\0") << "\0"
    end
  end

  full_hash = bytes.each_byte.reduce(0xcbf29ce484222325) do |hash, byte|
    ((hash ^ byte) * 0x100000001b3) & 0xffffffffffffffff
  end
  # Cache manifests store this as a normal Tungsten Int. Fold to the positive
  # signed-i48 payload range so both bootstrap stages constant-fold it and the
  # value round-trips through Hash/serialization without BigInt allocation.
  (full_hash ^ (full_hash >> 47)) & ((1 << 47) - 1)
end

def generate_schema(kinds, fingerprint)
  max_id = kinds.map(&:id).max
  reverse = Array.new(max_id + 1, "nil")
  sclasses = Array.new(max_id + 1, "nil")
  widths = Array.new(max_id + 1, "0")
  kinds.each do |kind|
    reverse[kind.id] = symbol_literal(kind.public_name)
    sclasses[kind.id] = kind.sclass
    widths[kind.id] = kind.fields.size.to_s if %w[slab cached].include?(kind.storage)
  end

  out = []
  out << "# Generated by scripts/gen_ast_schema.rb from ast.w. Do not edit."
  out << "# The KIND_* numeric registry above is stable and remains hand-assigned."
  out << ""
  out << "AST_SCHEMA_ABI_VERSION = 2 ## i64"
  signed_fingerprint = fingerprint >= (1 << 63) ? fingerprint - (1 << 64) : fingerprint
  # Decimal signed i64 literals constant-fold identically in the bootstrap VM
  # and self-hosted compiler. A high-bit hexadecimal literal is parsed as an
  # unsigned value by stage 0 and as a runtime-initialized BigInt by stage 1.
  out << "AST_SCHEMA_HASH = #{signed_fingerprint} ## i64"
  out << ""
  out << "KIND_ID_TABLE = {"
  kinds.each { |kind| out << format("  %-20s => %s,", symbol_literal(kind.name), kind.constant) }
  out << "}"
  out << ""
  out << "kind_id_table = KIND_ID_TABLE"
  out << "kind_sym_table_data = [#{reverse.join(', ')}]"
  out << ""
  out << "-> kind_id_for_name(sym)"
  out << "  v = kind_id_table[sym]"
  out << "  return -1 if v == nil"
  out << "  v"
  out << ""
  out << "-> kind_sym_for_id(kind_id)"
  out << "  return nil if kind_id < 0 || kind_id > KIND_MAX"
  out << "  kind_sym_table_data[kind_id]"
  out << ""
  out << "OFFSET_INLINE = 256 ## i64"
  out << "OFFSET_INTERN = 257 ## i64"
  out << ""
  out << "slab_offset_table_data = {"
  kinds.each do |kind|
    out << format("  %-25s => %s,", kind.constant, hash_literal(kind.fields, kind.storage))
  end
  out << "}"
  out << ""
  out << "slab_field_type_table_data = {"
  kinds.each do |kind|
    out << format("  %-25s => %s,", kind.constant, type_hash_literal(kind.fields))
  end
  out << "}"
  out << ""
  out << "-> build_slab_table_arr(hash)"
  out << "  arr = [nil]"
  out << "  i = 1"
  out << "  while i <= KIND_MAX"
  out << "    arr.push(hash[i])"
  out << "    i += 1"
  out << "  arr"
  out << ""
  out << "slab_offset_table_arr = build_slab_table_arr(slab_offset_table_data)"
  out << "slab_field_type_table_arr = build_slab_table_arr(slab_field_type_table_data)"
  out << ""
  out << "-> build_slab_keys_arr(arr)"
  out << "  out = [nil]"
  out << "  i = 1"
  out << "  while i <= KIND_MAX"
  out << "    h = arr[i]"
  out << "    if h == nil"
  out << "      out.push(nil)"
  out << "    else"
  out << "      out.push(h.keys())"
  out << "    i += 1"
  out << "  out"
  out << ""
  out << "slab_keys_table = build_slab_keys_arr(slab_offset_table_arr)"
  out << ""
  out << "-> slab_offset_for_id(kid, sym)"
  out << "  return nil if kid < 1 || kid > KIND_MAX"
  out << "  fields = slab_offset_table_arr[kid]"
  out << "  return nil if fields == nil"
  out << "  fields[sym]"
  out << ""
  out << "-> slab_offset_for(kind, sym)"
  out << "  kid = kind"
  out << "  if type(kind) == \"Symbol\""
  out << "    kid = kind_id_table[kind]"
  out << "    return nil if kid == nil"
  out << "  slab_offset_for_id(kid, sym)"
  out << ""
  out << "slab_sclass_table = [#{sclasses.join(', ')}]"
  out << "slab_width_table = [#{widths.join(', ')}]"
  out << ""
  out << "-> sc_for_kind(kind)"
  out << "  return SC_2 if kind < 1 || kind > KIND_MAX"
  out << "  sc = slab_sclass_table[kind]"
  out << "  return SC_2 if sc == nil"
  out << "  sc"
  out << ""
  out << "-> width_for_kind(kind)"
  out << "  return 0 if kind < 1 || kind > KIND_MAX"
  out << "  slab_width_table[kind]"
  out.join("\n") + "\n"
end

def generate_header(kinds, fingerprint)
  max_id = kinds.map(&:id).max
  widths = Array.new(max_id + 1, 0)
  kinds.each do |kind|
    widths[kind.id] = kind.fields.size if %w[slab cached].include?(kind.storage)
  end
  <<~HEADER
    /* Generated by scripts/gen_ast_schema.rb. Do not edit. */
    #ifndef TUNGSTEN_AST_SCHEMA_GENERATED_H
    #define TUNGSTEN_AST_SCHEMA_GENERATED_H

    #include <stdint.h>

    #define W_AST_SCHEMA_ABI_VERSION UINT32_C(2)
    #define W_AST_SCHEMA_HASH UINT64_C(0x#{format('%016X', fingerprint)})
    #define W_AST_KIND_MAX UINT32_C(#{max_id})

    static const uint8_t W_AST_KIND_WIDTH[W_AST_KIND_MAX + 1] = {
        #{widths.each_slice(16).map { |slice| slice.join(', ') }.join(",\n    ")}
    };

    #endif
  HEADER
end

schema = File.read(SCHEMA_PATH)
ast = File.read(AST_PATH)
registry = parse_kind_registry(schema)
kinds = parse_ast_declarations(ast, registry)
fingerprint = schema_hash(kinds)
generated = generate_schema(kinds, fingerprint)
generated_header = generate_header(kinds, fingerprint)

start_at = schema.index(START_MARKER)
end_at = schema.index(END_MARKER)
fail_schema("missing generated-section markers") unless start_at && end_at && end_at > start_at
content_start = start_at + START_MARKER.length
current = schema[content_start...end_at]

if ARGV.include?("--check")
  header_current = File.exist?(HEADER_PATH) && File.read(HEADER_PATH) == generated_header
  if current == generated && header_current
    puts "ast schema generated tables are current (#{kinds.size} kinds, 0x#{format('%016X', fingerprint)})"
    exit 0
  end
  stale = []
  stale << File.basename(SCHEMA_PATH) unless current == generated
  stale << File.basename(HEADER_PATH) unless header_current
  fail_schema("generated output is stale (#{stale.join(', ')}); run scripts/gen_ast_schema.rb")
end

updated = schema[0...content_start] + generated + schema[end_at..]
File.write(SCHEMA_PATH, updated)
File.write(HEADER_PATH, generated_header)
puts "generated AST schema tables for #{kinds.size} kinds (0x#{format('%016X', fingerprint)})"
