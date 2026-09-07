# Exact rank-improving two-slot delta join for a fixed finite proposal family.
# This prunes by full rank-one tensor identity, not a support/hull descriptor.
# The caller must first handle rank-improving singles, and independently admit
# both selected leaf representations and the complete composed tensor.
require_relative "outer_leaf_portfolio"

module MetaflipLeafDeltaCollisions
  module_function

  def binary_rank(words)
    rows = {}
    words.each do |word|
      raise "invalid binary vector" unless word.is_a?(Integer) && word >= 0
      v = word
      until v.zero?
        pivot = v.bit_length - 1
        if rows[pivot]
          v ^= rows[pivot]
        else
          rows[pivot] = v
          break
        end
      end
    end
    rows.length
  end

  # A nonzero rank-one term can collide between two slots only if their
  # factor-image spaces have a nonzero intersection on all three axes.
  # A zero intersection on even one axis certifies disjoint term supports
  # for every leaf representation in this fixed parent/allocation/shape.
  def image_disjointness(parent, allocation, leaves)
    b = MetaflipBudProducts
    m = MetaflipOuterBasisProducts
    spaces = leaves.each_with_index.map do |leaf, slot|
      if leaf
        b::EDGES.each_with_index.map do |(r, c), axis|
          (leaf.shape[r] * leaf.shape[c]).times.map do |bit|
            m.embed(1 << bit, parent.terms[slot][axis], parent.shape[r], parent.shape[c],
              allocation[r], allocation[c], leaf.shape[r], leaf.shape[c])
          end.uniq.reject(&:zero?)
        end
      else
        [[], [], []]
      end
    end
    ranks = spaces.map { |parts| parts.map { |part| binary_rank(part) } }
    pairs = leaves.each_index.to_a.combination(2).map do |i, j|
      dimensions = 3.times.map { |a| ranks[i][a] + ranks[j][a] - binary_rank(spaces[i][a] + spaces[j][a]) }
      { slots: [i, j], intersection_dimensions: dimensions, disjoint: dimensions.include?(0) }
    end
    { factor_ranks: ranks, pairs: pairs, all_disjoint: pairs.all? { |p| p[:disjoint] } }
  end

  def rank_pairs(parity, proposals, weight: ->(_term) { 0 })
    raise "expected parity Set" unless parity.is_a?(Set)
    raise "invalid proposal" unless proposals.is_a?(Array) && proposals.all? do |p|
      p.is_a?(Hash) && p[:slot].is_a?(Integer) && p[:slot] >= 0 && p[:delta].is_a?(Set)
    end
    rows = proposals.map do |p|
      removed = p[:delta] & parity
      added = p[:delta] - parity
      cost = added.length - removed.length
      raise "handle rank-improving singles first" if cost.negative?
      { removed: removed, added: added, cost: cost }
    end
    index = Hash.new { |h, term| h[term] = [] }
    rows.each_with_index { |r, i| r[:added].each { |term| index[term] << i } }
    n = proposals.length
    counts = proposals.group_by { |p| p[:slot] }.values.map(&:length)
    possible = (n * n - counts.sum { |c| c * c }) / 2
    intersections = Hash.new(0)
    index.each_value do |ids|
      ids.combination(2) do |i, j|
        next if proposals[i][:slot] == proposals[j][:slot]
        intersections[i * n + j] += 1
      end
    end
    best = nil; lower_bound_survivors = 0; rank_gains = 0
    intersections.each do |packed, common_new|
      i, j = packed.divmod(n)
      bound = rows[i][:cost] + rows[j][:cost] - 2 * common_new
      next unless bound.negative?
      lower_bound_survivors += 1
      common_old = (rows[i][:removed] & rows[j][:removed]).length
      rank_delta = bound + 2 * common_old
      next unless rank_delta.negative?
      rank_gains += 1
      delta = proposals[i][:delta] ^ proposals[j][:delta]
      direct_rank = delta.sum { |term| parity.include?(term) ? -1 : 1 }
      raise "delta collision score mismatch" unless rank_delta == direct_rank
      density_delta = delta.sum { |term| (parity.include?(term) ? -1 : 1) * weight.call(term) }
      key = [rank_delta, density_delta, i, j]
      if !best || (key <=> best[:key]) == -1
        best = { indices: [i, j], rank_delta: rank_delta, density_delta: density_delta,
          common_new: common_new, common_old: common_old, key: key }
      end
    end
    { proposals: n, possible_pairs: possible, collision_pairs: intersections.length,
      lower_bound_survivors: lower_bound_survivors, rank_gain_pairs: rank_gains,
      shared_new_terms: index.count { |_, ids| ids.map { |i| proposals[i][:slot] }.uniq.length > 1 },
      best: best }
  end
end
