#!/usr/bin/env ruby
# Regenerate exact GF(2) tensor certificates from compact parent/scale records.
require 'json'
require 'fileutils'
require 'optparse'
require 'digest'
require_relative 'bud_products'

module MetaflipStructuredParentPortfolio
  B = MetaflipBudProducts
  module_function

  def run(argv)
    options = { manifest: File.expand_path('certificates/structured-parent-portfolio-20260922/manifest.json', __dir__), only: [] }
    OptionParser.new do |parser|
      parser.banner = 'Usage: replay_structured_parent_portfolio.rb --output DIR [--only AxBxC]'
      parser.on('--manifest FILE') { |value| options[:manifest] = value }
      parser.on('--output DIR') { |value| options[:output] = value }
      parser.on('--only AxBxC') { |value| options[:only] << value }
    end.parse!(argv)
    raise 'unexpected arguments' unless argv.empty?
    raise 'missing --output' unless options[:output]
    root = File.expand_path(options[:output])
    raise 'output must be new or empty' if File.exist?(root) && (!File.directory?(root) || !Dir.empty?(root))
    manifest = JSON.parse(File.binread(options[:manifest]))
    raise 'invalid manifest' unless manifest['schema'] == 1 && manifest['field'] == 'GF(2)' &&
                                    manifest['rows'].is_a?(Array) && !manifest['rows'].empty?
    selected = manifest['rows'].select { |row| options[:only].empty? || options[:only].include?(row.fetch('shape').join('x')) }
    raise 'unknown --only shape' unless selected.length >= options[:only].uniq.length
    seed_dir = File.expand_path('../lib/metaflip/seeds/gf2', __dir__)
    library = B::Library.new(Dir[File.join(seed_dir, 'matmul_*_gf2.txt')].sort.map { |path| B.load_scheme(path) }, products: true)
    FileUtils.mkdir_p(root)
    selected.each do |row|
      name = row.fetch('parent')
      raise 'invalid parent name' unless name == File.basename(name) && name.match?(/\Amatmul_[a-zA-Z0-9_]+_gf2\.txt\z/)
      parent = B.load_scheme(File.join(seed_dir, name))
      raise 'parent hash mismatch' unless Digest::SHA256.hexdigest(B.text(parent.terms)) == row.fetch('parent_sha256')
      scale = row.fetch('scale')
      shape = row.fetch('shape')
      raise 'invalid scale or shape' unless scale.is_a?(Array) && scale.length == 3 && scale.all? { |n| n.is_a?(Integer) && n.between?(1, 8) } &&
                                           shape == parent.shape.zip(scale).map { |a, b| a * b }.sort
      groups = B.partitions(parent, scale, library, trials: 0)
      price = B.score(groups, scale, library)
      raise 'formula price mismatch' unless price == row.fetch('rank') && price < row.fetch('catalog_recursive_bound')
      result, recipe = B.export(File.join(root, shape.join('x')), parent, scale, groups, library)
      raise 'result mismatch' unless result.shape == row.fetch('result_shape') && result.rank == price &&
                                     result.audit[:sha256] == row.fetch('result_sha256')
      raise 'recipe replay mismatch' unless B.replay(recipe) == result.audit
      wide = (["MFW1 #{result.shape.join(' ')} #{result.rank}"] +
              result.terms.map { |term| term.map { |factor| factor.to_s(16) }.join(' ') }).join("\n") + "\n"
      File.binwrite(File.join(File.dirname(recipe), "#{result.shape.join('x')}.mfw"), wide)
      puts "#{shape.join('x')} GF(2) #{result.rank} < #{row.fetch('catalog_recursive_bound')} #{result.audit[:sha256]}"
    end
  end
end

MetaflipStructuredParentPortfolio.run(ARGV) if $PROGRAM_NAME == __FILE__
