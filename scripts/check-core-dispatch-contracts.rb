#!/usr/bin/env ruby
# frozen_string_literal: true

# Runtime-backed Core values can bypass ordinary source-class dispatch. Their
# native inline-cache tables and compiler direct-call whitelists therefore form
# one public-method contract. This gate checks the table structure globally and
# pins Quantity's complete three-way source/lowering/runtime surface, the first
# class migrated to an exhaustive contract.

ROOT = File.expand_path("..", __dir__)
RUNTIME_PATH = File.join(ROOT, "runtime", "runtime.c")
QUANTITY_PATH = File.join(ROOT, "core", "quantity.w")
LOWERING_PATH = File.join(ROOT, "compiler", "lib", "lowering", "method_call.w")

# Every instance method on these runtime-backed classes must be classified.
# `native_ic` methods are intercepted by the runtime table even when the
# receiver's concrete type is erased. `source_fallback` methods deliberately
# dispatch through the loaded Core class. Adding a source method or IC row
# without choosing one of those contracts is a gate failure.
RUNTIME_CLASS_CONTRACTS = {
  "Mmap" => {
    path: "core/mmap.w",
    table: "w_ic_mmap_table",
    native_ic: %w[[] byte_at close view_at],
    source_fallback: %w[as_f32 as_f64 as_i16 as_i32 as_i64 as_i8 as_u16 as_u32 as_u64 as_u8 size]
  },
  "Atomic" => {
    path: "core/atomic.w",
    table: "w_ic_atomic_table",
    native_ic: %w[add cas get set],
    source_fallback: %w[compare_exchange decrement exchange fetch_add fetch_sub increment load store]
  },
  "Socket" => {
    path: "core/socket.w",
    table: "w_ic_socket_table",
    native_ic: %w[accept alpn_protocol close read read_exact read_into serve_http set_timeout shutdown write write_bytes write_slice],
    source_fallback: []
  },
  "Thread" => {
    path: "core/thread.w",
    table: "w_ic_thread_table",
    native_ic: %w[join kill],
    source_fallback: %w[alive? new]
  },
  "Channel" => {
    path: "core/channel.w",
    table: "w_ic_channel_table",
    native_ic: %w[close send],
    source_fallback: %w[each receive receive_result recv try_receive try_receive_result try_send]
  },
  "BigArray" => {
    path: "core/big_array.w",
    table: "w_ic_big_array_table",
    native_ic: %w[[] []= get push set subview],
    native_only: %w[[] []= get push set subview],
    source_fallback: %w[__enumerable_iteration_mode __replace_elements cap each empty? mergesort! rotate rotate! shuffle shuffle! size sort sort!]
  },
  "SmallArray" => {
    path: "core/small_array.w",
    table: "w_ic_small_array_table",
    native_ic: %w[[] []= get set],
    native_only: %w[[] []= get set],
    source_fallback: %w[__enumerable_iteration_mode cap each empty? rotate shuffle size sort]
  },
  "IPv4" => {
    path: "core/ipv4.w",
    table: "w_ic_ipv4_table",
    native_ic: %w[inspect],
    source_fallback: %w[[] a b broadcast broadcast? c cidr? contains? d global? include? link_local? loopback? mask multicast? netmask network octet octets prefix private? reserved? to_i to_s unspecified? with_prefix]
  },
  "IPv6" => {
    path: "core/ipv6.w",
    table: "w_ic_ipv6_table",
    native_ic: %w[inspect],
    source_fallback: %w[[] byte bytes cidr? contains? global? include? link_local? loopback? multicast? network prefix private? to_s unique_local? unspecified? with_prefix]
  },
  "MAC" => {
    path: "core/mac.w",
    table: "w_ic_mac_table",
    native_ic: %w[inspect],
    source_fallback: %w[[] broadcast? byte bytes local? multicast? to_s unicast? universal?]
  },
  "Hash" => {
    path: "core/hash.w",
    table: "w_ic_hash_table",
    native_ic: %w[[] []= delete each get has_key? keys merge! set values],
    native_only: %w[[] []= delete each get has_key? keys set values],
    source_fallback: %w[__enumerable_each __enumerable_iteration_mode __enumerable_yields_pair? each_pair fetch include? invert key? merge size transform_keys transform_values update]
  }
}.freeze

runtime = File.read(RUNTIME_PATH, encoding: "utf-8")
quantity = File.read(QUANTITY_PATH, encoding: "utf-8")
lowering = File.read(LOWERING_PATH, encoding: "utf-8")
errors = []

method_names = {}
runtime.scan(/^#define\s+(WN_\w+)\s+W_M\d+\("([^"]+)"\)/) do |constant, name|
  method_names[constant] = name
end
runtime.scan(/^\s*(WN_\w+)\s*=\s*w_string\("([^"]+)"\);/) do |constant, name|
  method_names[constant] = name
end

tables = {}
runtime.scan(/^static WICEntry\s+(w_ic_\w+_table)\[\]\s*=\s*\{(.*?)^\};/m) do |table_name, body|
  handlers = body.scan(/^\s*\{0,\s*([A-Za-z_][A-Za-z0-9_]*|NULL)\s*\}/).flatten
  if handlers.empty? || handlers.last != "NULL"
    errors << "#{table_name}: missing terminal NULL handler"
  end
  tables[table_name] = handlers.take_while { |handler| handler != "NULL" }
end

assignments = Hash.new { |hash, key| hash[key] = {} }
runtime.scan(/^\s*(w_ic_\w+_table)\[(\d+)\]\.name\s*=\s*([^;]+);/) do |table_name, index_text, expression|
  index = Integer(index_text, 10)
  handlers = tables[table_name]
  if handlers.nil?
    errors << "#{table_name}[#{index}]: initializer names an unknown table"
    next
  end
  if index >= handlers.size
    errors << "#{table_name}[#{index}]: initializer exceeds #{handlers.size} live handlers"
    next
  end
  if assignments[table_name].key?(index)
    errors << "#{table_name}[#{index}]: duplicate name initializer"
    next
  end

  name = if (match = expression.match(/\Aw_string\("([^"]+)"\)\z/))
           match[1]
         else
           method_names[expression.strip]
         end
  if name.nil?
    errors << "#{table_name}[#{index}]: unresolved method-name expression #{expression.strip.inspect}"
    next
  end
  assignments[table_name][index] = name
end

quantity_methods = quantity.scan(/^  ->\s+([^\s(]+)/).flatten
quantity_methods.concat(quantity.scan(/^  alias_method\s+:([^\s\/]+)\/\d+,/).flatten)
quantity_methods = quantity_methods.uniq.sort

quantity_gate = lowering.match(
  /if recv_is_known_quantity[^\n]*method_name in \((?<names>[^\n]+)\)/
)
if quantity_gate.nil?
  errors << "lowering: missing recv_is_known_quantity method whitelist"
  lowered_quantity_methods = []
else
  lowered_quantity_methods = quantity_gate[:names].scan(/"([^"]+)"/).flatten.uniq.sort
end

quantity_ic_methods = assignments.fetch("w_ic_quantity_table", {}).values.uniq.sort

{
  "compiler Quantity whitelist" => lowered_quantity_methods,
  "runtime Quantity IC table" => quantity_ic_methods
}.each do |label, actual|
  missing = quantity_methods - actual
  stale = actual - quantity_methods
  errors << "#{label}: missing #{missing.join(', ')}" unless missing.empty?
  errors << "#{label}: not declared by core/quantity.w: #{stale.join(', ')}" unless stale.empty?
end

RUNTIME_CLASS_CONTRACTS.each do |class_name, contract|
  source = File.read(File.join(ROOT, contract[:path]), encoding: "utf-8")
  body = source[/^\+ #{Regexp.escape(class_name)}\s*$\n(?<body>.*?)(?=^\+ |\z)/m, :body]
  if body.nil?
    errors << "#{class_name}: missing class declaration in #{contract[:path]}"
    next
  end

  source_methods = body.scan(/^  ->\s+(?!\.)([^\s(]+)/).flatten.map { |name| name.sub(%r{/.*\z}, "") }.uniq.sort
  native_methods = contract[:native_ic].uniq.sort
  native_only = contract.fetch(:native_only, []).uniq.sort
  fallback_methods = contract[:source_fallback].uniq.sort
  declared_native = native_methods - native_only
  classified = (declared_native + fallback_methods).uniq.sort
  overlap = native_methods & fallback_methods
  errors << "#{class_name}: methods classified as both native IC and source fallback: #{overlap.join(', ')}" unless overlap.empty?
  invalid_native_only = native_only - native_methods
  errors << "#{class_name}: native-only methods without IC classification: #{invalid_native_only.join(', ')}" unless invalid_native_only.empty?
  declared_native_only = native_only & source_methods
  errors << "#{class_name}: native-only methods also have source declarations: #{declared_native_only.join(', ')}" unless declared_native_only.empty?

  unclassified = source_methods - classified
  stale = classified - source_methods
  errors << "#{class_name}: unclassified source methods: #{unclassified.join(', ')}" unless unclassified.empty?
  errors << "#{class_name}: classifications not declared in #{contract[:path]}: #{stale.join(', ')}" unless stale.empty?

  actual_ic = assignments.fetch(contract[:table], {}).values.uniq.sort
  missing_ic = native_methods - actual_ic
  stale_ic = actual_ic - native_methods
  errors << "#{class_name}: native IC classification missing runtime rows: #{missing_ic.join(', ')}" unless missing_ic.empty?
  errors << "#{class_name}: runtime IC rows not classified native: #{stale_ic.join(', ')}" unless stale_ic.empty?
end

if errors.empty?
  initialized = assignments.values.sum(&:size)
  classified = RUNTIME_CLASS_CONTRACTS.size
  puts "core dispatch contracts: #{tables.size} IC tables, #{initialized} named rows, #{quantity_methods.size} Quantity methods, #{classified} runtime classes consistent"
else
  warn "core dispatch contracts: FAIL (#{errors.size} disagreement#{errors.size == 1 ? '' : 's'})"
  errors.each { |error| warn "  - #{error}" }
  exit 1
end
