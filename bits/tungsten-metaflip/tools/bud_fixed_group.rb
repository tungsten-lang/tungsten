# Offline, certificate-backed cover; never treats a residual as a full tensor.
require_relative 'bud_products'

module MetaflipFixedGroup
  B = MetaflipBudProducts
  ResidualTerms = Struct.new(:terms, :rank)
  module_function

  def partition(parent, scale, library, held, shape)
    ordinary = B.partitions(parent, scale, library, trials: 0)
    positions = parent.terms.each_with_index.to_h
    indices = held.map { |t| positions[t] }
    return ordinary if indices.any?(&:nil?)
    raise 'duplicate held term' unless indices.uniq == indices
    available = (0...parent.rank).to_a - indices
    residual = ResidualTerms.new(available.map { |i| parent.terms[i] }, available.length)
    fixed = [{elementary_shape: shape, indices: indices}]
    unless available.empty?
      fixed += B.partitions(residual, scale, library, trials: 0).map do |g|
        g.merge(indices: g[:indices].map { |i| available[i] })
      end
    end
    B.validate_groups(parent, fixed)
    B.score(fixed, scale, library) < B.score(ordinary, scale, library) ? fixed : ordinary
  end
end
