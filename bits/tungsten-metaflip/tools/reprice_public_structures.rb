#!/usr/bin/env ruby
# Screening only: reported parent structures are not coefficient certificates.
# Reprice their leaves, then exact-check the actual parent and materialized
# tensor before admitting anything. Reference-only ranks never become leaves.
require 'digest'
require 'fileutils'
require 'json'
require 'optparse'

module MetaflipPublicStructurePrices
  module_function

  def structure(text)
    raise 'empty structure' unless text.is_a?(String) && !text.empty?
    text.split('+', -1).map do |part|
      match = /\A\s*(\d*)\s*<\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*>\s*\z/.match(part)
      raise 'unsupported structure syntax' unless match
      count = match[1].empty? ? 1 : Integer(match[1], 10)
      shape = match.captures.drop(1).map { |s| Integer(s, 10) }
      raise 'nonpositive structure' unless count.positive? && shape.all?(&:positive?)
      {count: count, shape: shape}
    end
  end

  def price(tag, entry, prices, maximum)
    target = tag.split('x').map { |s| Integer(s, 10) }
    parent, scale = entry.fetch('s1').fetch('dimension'), entry.fetch('s2').fetch('dimension')
    [target, parent, scale].each do |s|
      raise 'invalid dimensions' unless s.length == 3 && s.all? { |v| v.is_a?(Integer) && v.positive? }
    end
    raise 'parent/scale target mismatch' unless parent.zip(scale).map { |a,b| a*b }.sort == target.sort
    groups = structure(entry.fetch('s1').fetch('structure'))
    raise 'parent rank mismatch' unless groups.sum { |g| g[:count]*g[:shape].inject(:*) } == entry.fetch('s1').fetch('rank')
    return nil if target.max > maximum
    leaves = groups.map do |g|
      shape = g[:shape].zip(scale).map { |a,b| a*b }
      return nil if shape.max > maximum
      rank = shape.include?(1) ? shape.inject(:*) : prices.fetch(shape.sort)
      g.merge(leaf: shape, leaf_rank: rank, charge: g[:count]*rank)
    end
    formula = leaves.sum { |g| g[:charge] }
    baseline = target.include?(1) ? target.inject(:*) : prices.fetch(target.sort)
    {target: target.sort, parent: parent, scale: scale, parent_rank: entry.fetch('s1').fetch('rank'),
     source_path: entry.fetch('path'), reported_rank: entry.fetch('serendipitous_rank'),
     baseline: baseline, repriced_formula: formula, potential_gain: baseline-formula,
     parent_coefficients_verified: false, leaves: leaves}
  end

  def main(argv)
    options = {}
    OptionParser.new do |p|
      %i[table closure output].each { |k| p.on("--#{k} PATH") { |v| options[k] = File.expand_path(v) } }
    end.parse!(argv)
    raise 'provide --table --closure --output' unless argv.empty? && options.length == 3
    raise 'output exists' if File.exist?(options[:output])
    raw = {table: File.binread(options[:table]), closure: File.binread(options[:closure])}
    table, closure = JSON.parse(raw[:table]), JSON.parse(raw[:closure])
    raise 'invalid witness-price report' unless closure.fetch('complete') && closure.fetch('field') == 'GF(2)' && !closure.fetch('record_claim')
    prices = closure.fetch('rows').to_h { |r| [r.fetch('shape'), r.fetch('augmented_rank')] }
    rows = table.filter_map { |tag, e| price(tag, e, prices, closure.fetch('maximum')) }
    winners = rows.select { |r| r[:potential_gain].positive? }.sort_by { |r| [-r[:potential_gain], r[:target]] }
    priorities = winners.group_by { |r| r[:source_path] }.map do |path, rs|
      {source_path: path, potential_targets: rs.length, total_potential_gain: rs.sum { |r| r[:potential_gain] },
       targets: rs.map { |r| r[:target] }}
    end.sort_by { |r| [-r[:potential_targets], -r[:total_potential_gain], r[:source_path]] }
    report = {schema: 1, complete: true, screen_only: true, record_claim: false,
      price_field: 'GF(2)', parent_fields_unchecked: true, canonical_archive_changed: false,
      source_sha256: {options[:table] => Digest::SHA256.hexdigest(raw[:table]),
                      options[:closure] => Digest::SHA256.hexdigest(raw[:closure])},
      summary: {table_entries: table.length, priced_entries: rows.length,
        potential_targets: winners.length, parent_fetches: priorities.length},
      priorities: priorities, candidates: winners, rows: rows}
    FileUtils.mkdir_p(File.dirname(options[:output]))
    File.write(options[:output], JSON.pretty_generate(report)+"\n")
    puts JSON.generate(report[:summary])
  end
end

MetaflipPublicStructurePrices.main(ARGV) if $PROGRAM_NAME == __FILE__
