#!/usr/bin/env ruby
# frozen_string_literal: true

# Verifies that Tungsten `- data (CStruct)` layout declarations agree with the
# backing C structs and their runtime static asserts.
#
# v0 validates the ABI-sensitive array family first:
#   core/array.w        - data (WArray)
#   core/big_array.w    - data (WBigArray)
#   core/small_array.w  - data (WSmallArray)

require "fiddle"

ROOT = File.expand_path("..", __dir__)
CORE_GLOB = File.join(ROOT, "core", "**", "*.w")
RUNTIME_HEADER = File.join(ROOT, "runtime", "runtime.h")
POINTER_SIZE = Fiddle::SIZEOF_VOIDP

REQUIRED_BACKED_STRUCTS = %w[
  WArray
  WBigArray
  WSmallArray
].freeze

# W_SUBTAG_GENERIC heap values carry a leading runtime type byte that the
# user-visible Tungsten layout omits. The lowering adds this byte back when
# producing C offsets.
C_PREFIX_FIELDS = {
  "WBigArray" => %w[type]
}.freeze

LayoutField = Struct.new(:name, :type, :size, :align, :offset, keyword_init: true)
BackedLayout = Struct.new(:source, :class_name, :struct_name, :fields, :size, keyword_init: true)

DSL_TYPE_SIZES = {
  "u8" => [ 1, 1 ],
  "i8" => [ 1, 1 ],
  "u16" => [ 2, 2 ],
  "i16" => [ 2, 2 ],
  "u32" => [ 4, 4 ],
  "i32" => [ 4, 4 ],
  "f32" => [ 4, 4 ],
  "u64" => [ 8, 8 ],
  "i64" => [ 8, 8 ],
  "f64" => [ 8, 8 ],
  "w64" => [ 8, 8 ]
}.freeze

C_TYPE_SIZES = {
  "uint8_t" => [ 1, 1 ],
  "int8_t" => [ 1, 1 ],
  "uint16_t" => [ 2, 2 ],
  "int16_t" => [ 2, 2 ],
  "uint32_t" => [ 4, 4 ],
  "int32_t" => [ 4, 4 ],
  "uint64_t" => [ 8, 8 ],
  "int64_t" => [ 8, 8 ],
  "WValue" => [ 8, 8 ]
}.freeze

def align_to(offset, alignment)
  return offset if alignment <= 1

  remainder = offset % alignment
  remainder.zero? ? offset : offset + alignment - remainder
end

def finish_layout(fields, aligned:)
  offset = 0
  max_align = 1

  fields.each do |field|
    offset = align_to(offset, field.align) if aligned
    field.offset = offset
    offset += field.size
    max_align = [ max_align, field.align ].max
  end

  aligned ? align_to(offset, max_align) : offset
end

def dsl_type_size(type)
  return [ POINTER_SIZE, POINTER_SIZE ] if type.start_with?("*")

  if (match = type.match(/\A(?<base>[a-z]\d+|w64)\[(?<count>\d*)\]\z/))
    size, align = DSL_TYPE_SIZES.fetch(match[:base]) { abort "Unknown DSL layout type: #{type}" }
    return [ 0, align ] if match[:count].empty?

    return [ size * Integer(match[:count], 10), align ]
  end

  DSL_TYPE_SIZES.fetch(type) { abort "Unknown DSL layout type: #{type}" }
end

def c_type_size(type, pointer:, count:)
  if pointer
    size = POINTER_SIZE
    align = POINTER_SIZE
  else
    size, align = C_TYPE_SIZES.fetch(type) { abort "Unknown C layout type: #{type}" }
  end

  [ size * (count || 0), align ]
end

def parse_backed_layouts
  layouts = []

  Dir[CORE_GLOB].sort.each do |path|
    lines = File.readlines(path, encoding: "utf-8")
    class_name = nil
    index = 0

    while index < lines.length
      stripped = lines[index].strip
      if (class_match = stripped.match(/\A\+\s*(?<name>[A-Z]\w*)\b/))
        class_name = class_match[:name]
      end

      if (layout_match = stripped.match(/\A-\s+data\s+\((?<struct>[A-Z]\w*)\)\z/))
        fields = []
        index += 1

        while index < lines.length
          raw = lines[index].sub(/#.*/, "")
          break if raw.strip.empty? && !fields.empty?

          field_pattern = /
            \A\s*(?<star>\*)?\s*
            (?<type>[A-Za-z]\w*(?:\[[^\]]*\])?)\s+
            (?<name>[A-Za-z_]\w*)\s*\z
          /x

          if (field_match = raw.match(field_pattern))
            type = field_match[:type]
            type = "*#{type}" if field_match[:star]
            size, align = dsl_type_size(type)
            fields << LayoutField.new(name: field_match[:name], type:, size:, align:)
          end

          index += 1
        end

        size = finish_layout(fields, aligned: false)
        layouts << BackedLayout.new(
          source: path,
          class_name:,
          struct_name: layout_match[:struct],
          fields:,
          size:
        )
      end

      index += 1
    end
  end

  layouts
end

def parse_c_struct(header, struct_name)
  body_match = header.match(
    /typedef\s+struct(?:\s+\w+)?\s*\{(?<body>[^{}]*)\}\s+#{Regexp.escape(struct_name)}\s*;/m
  )
  abort "Missing C struct #{struct_name} in #{RUNTIME_HEADER}" unless body_match

  fields = []
  body_match[:body].lines.each do |line|
    clean = line.sub(%r{/[*].*?[*]/}, "").strip
    next if clean.empty?

    match = clean.match(
      /\A(?<type>[A-Za-z_]\w*)\s*(?<star>\*)?\s*(?<name>[A-Za-z_]\w*)(?:\[(?<count>\d*)\])?\s*;/
    )
    next unless match

    count = match[:count] ? (match[:count].empty? ? nil : Integer(match[:count], 10)) : 1
    pointer = !match[:star].nil?
    size, align = c_type_size(match[:type], pointer:, count:)
    ctype = pointer ? "#{match[:type]}*" : match[:type]
    ctype += "[#{count}]" if count && count != 1
    ctype += "[]" if count.nil?
    fields << LayoutField.new(name: match[:name], type: ctype, size:, align:)
  end

  size = finish_layout(fields, aligned: true)
  BackedLayout.new(source: RUNTIME_HEADER, struct_name:, fields:, size:)
end

def parse_static_asserts(header, struct_name)
  offsets = {}
  offset_pattern = /
    _Static_assert\s*\(\s*
    offsetof\s*\(\s*#{Regexp.escape(struct_name)}\s*,\s*(\w+)\s*\)\s*
    ==\s*(\d+)
  /x

  header.scan(offset_pattern) do |field, offset|
    offsets[field] = Integer(offset, 10)
  end

  size_match = header.match(/_Static_assert\s*\(\s*sizeof\s*\(\s*#{Regexp.escape(struct_name)}\s*\)\s*==\s*(\d+)/)
  size = size_match && Integer(size_match[1], 10)

  [ offsets, size ]
end

def fail_with(message, failures)
  failures << message
end

def validate_layout_set(layouts, failures)
  struct_names = layouts.map(&:struct_name)

  missing = REQUIRED_BACKED_STRUCTS - struct_names
  unless missing.empty?
    fail_with("Missing backed `- data (StructName)` layouts for: #{missing.join(', ')}", failures)
  end

  duplicates = struct_names.group_by(&:itself).select { |_name, entries| entries.size > 1 }.keys
  unless duplicates.empty?
    fail_with("Duplicate backed layout declarations for: #{duplicates.join(', ')}", failures)
  end
end

def c_prefix_fields(struct_name, c_layout)
  names = C_PREFIX_FIELDS.fetch(struct_name, [])
  prefix = c_layout.fields.first(names.size)
  actual_names = prefix.map(&:name)
  return prefix if actual_names == names

  abort "#{struct_name}: configured C prefix fields #{names.inspect} but found #{actual_names.inspect}"
end

def validate_layout(dsl_layout, c_layout, assert_offsets, assert_size, failures)
  label = "#{dsl_layout.class_name} -> #{dsl_layout.struct_name}"
  prefix_fields = c_prefix_fields(dsl_layout.struct_name, c_layout)
  prefix_size = prefix_fields.sum(&:size)
  dsl_names = dsl_layout.fields.map(&:name)
  c_fields = c_layout.fields.drop(prefix_fields.size)
  c_names = c_fields.map(&:name)

  if dsl_names != c_names
    fail_with("#{label}: DSL fields #{dsl_names.inspect} differ from C fields #{c_names.inspect}", failures)
  end

  prefix_fields.reject { |field| field.name.start_with?("_") }.each do |field|
    actual = assert_offsets[field.name]
    if actual.nil?
      fail_with("#{label}.#{field.name}: missing runtime offsetof static assert", failures)
    elsif actual != field.offset
      fail_with("#{label}.#{field.name}: runtime static assert offset #{actual} != C offset #{field.offset}", failures)
    end
  end

  dsl_layout.fields.zip(c_fields).each do |dsl_field, c_field|
    next unless dsl_field && c_field

    effective_offset = dsl_field.offset + prefix_size

    if effective_offset != c_field.offset
      fail_with(
        "#{label}.#{dsl_field.name}: DSL effective offset #{effective_offset} != C offset #{c_field.offset}",
        failures
      )
    end

    if dsl_field.size != c_field.size || dsl_field.align != c_field.align
      fail_with(
        "#{label}.#{dsl_field.name}: DSL size/align #{dsl_field.size}/#{dsl_field.align} " \
        "!= C size/align #{c_field.size}/#{c_field.align}",
        failures
      )
    end
  end

  effective_size = dsl_layout.size + prefix_size
  if effective_size != c_layout.size
    fail_with("#{label}: DSL effective sizeof #{effective_size} != C sizeof #{c_layout.size}", failures)
  end

  dsl_layout.fields.reject { |field| field.name.start_with?("_") }.each do |field|
    actual = assert_offsets[field.name]
    effective_offset = field.offset + prefix_size
    if actual.nil?
      fail_with("#{label}.#{field.name}: missing runtime offsetof static assert", failures)
    elsif actual != effective_offset
      fail_with(
        "#{label}.#{field.name}: runtime static assert offset #{actual} != DSL effective offset #{effective_offset}",
        failures
      )
    end
  end

  if assert_size.nil?
    fail_with("#{label}: missing runtime sizeof static assert", failures)
  elsif assert_size != effective_size
    fail_with(
      "#{label}: runtime static assert sizeof #{assert_size} != DSL effective sizeof #{effective_size}",
      failures
    )
  end
end

layouts = parse_backed_layouts
abort "No backed `- data (StructName)` layouts found" if layouts.empty?

header = File.read(RUNTIME_HEADER, encoding: "utf-8")
failures = []
validate_layout_set(layouts, failures)

layouts.each do |dsl_layout|
  c_layout = parse_c_struct(header, dsl_layout.struct_name)
  assert_offsets, assert_size = parse_static_asserts(header, dsl_layout.struct_name)
  validate_layout(dsl_layout, c_layout, assert_offsets, assert_size, failures)
end

if failures.empty?
  puts "Validated #{layouts.size} backed layout#{'s' unless layouts.size == 1}"
else
  failures.each { |failure| warn failure }
  abort "Layout validation failed"
end
