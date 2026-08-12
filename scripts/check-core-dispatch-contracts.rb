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

if errors.empty?
  initialized = assignments.values.sum(&:size)
  puts "core dispatch contracts: #{tables.size} IC tables, #{initialized} named rows, #{quantity_methods.size} Quantity methods consistent"
else
  warn "core dispatch contracts: FAIL (#{errors.size} disagreement#{errors.size == 1 ? '' : 's'})"
  errors.each { |error| warn "  - #{error}" }
  exit 1
end
