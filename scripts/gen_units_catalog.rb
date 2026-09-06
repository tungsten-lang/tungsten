#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/unit_registry"
require "optparse"
require "fileutils"

root = File.expand_path("..", __dir__)
options = {md: File.join(root, "doc/scientific-computing/units_catalog.md")}
OptionParser.new do |parser|
  parser.on("-m", "--md PATH") { |path| options[:md] = path }
  parser.on("-j", "--json PATH") { |path| options[:json] = path }
end.parse!
registry = TungstenUnitRegistry::Document.new(File.join(root, "data/unit_registry.json"))
metadata = File.readlines(File.join(root, "data/unit_metadata.tsv"), chomp: true).reject { |line| line.empty? || line.start_with?("#") }.to_h do |line|
  symbol, description, etymology, history, source, year, status = line.split("\t", -1)
  [symbol, {description: description, etymology: etymology, history: history, source: source, year: year, status: status}]
end
aliases = registry.aliases.group_by { |_, canonical| canonical }.transform_values { |rows| rows.map(&:first).sort }
rows = (registry.units.keys | registry.compounds.keys).sort.map do |name|
  value = registry.resolve(name)
  {symbol: name, powers: value.dimension.to_a, semantic: value.dimension.customs,
   factor: Rational(value.factor).to_s, offset: Rational(value.offset).to_s,
   kind: registry.units[name]&.fetch("kind") || "unit",
   aliases: aliases.fetch(name, [])}.merge(metadata.fetch(name, {}))
end
escape = ->(s) { s.to_s.gsub("|", "\\|").gsub("\n", " ") }
markdown = <<~MD
  # Unit registry catalog

  Generated from `data/unit_registry.json` and `data/unit_metadata.tsv` with
  `ruby scripts/gen_units_catalog.rb`. These data files are authoritative;
  no language implementation supplies definitions to this catalog.

  Factors and offsets are exact rationals: canonical value = value × factor + offset.
  Dimension powers use #{TungstenUnitRegistry::AXES.join(', ')} order.
  Semantic tags remain part of dimension identity. Constants and contextual or
  reference scales retain their explicit kind; a listed factor does not supply
  missing calibration, reference conditions, or physical context.

  | Symbol | Kind | SI factor | SI offset | Dimension powers | Semantic tags | Description | Aliases |
  |---|---|---|---|---|---|---|---|
MD
rows.each do |row|
  values = [row[:symbol], row[:kind], row[:factor], row[:offset], row[:powers].join(","), row[:semantic].map { |k, v| "#{k}:#{v}" }.join(", "), row[:description], row[:aliases].join(", ")]
  markdown << "| #{values.map(&escape).join(' | ')} |\n"
end
FileUtils.mkdir_p(File.dirname(options[:md]))
File.write(options[:md], markdown)
puts "Wrote #{options[:md]} (#{rows.size} canonical entries)"
if options[:json]
  File.write(options[:json], JSON.pretty_generate({schema: "tungsten.units-catalog/v1", units: rows}) + "\n")
  puts "Wrote #{options[:json]}"
end
