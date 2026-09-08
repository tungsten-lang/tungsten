#!/usr/bin/env ruby
# Reuse an exact packing only when every usable group price is proportional.
# One cache belongs to one immutable literal parent, including term order.
require_relative "bud_packings" unless defined?(MetaflipBudPackings)

module MetaflipBudPackings
  class ContextCache
    class FrozenPrices
      def initialize(prices, ordered: false)
        @prices = prices
        @ordered = ordered
      end

      def rank(shape)
        @prices.fetch(@ordered ? shape : shape.sort)
      end
    end

    def initialize(parent, max_leaf: 16, max_vertices: 24, max_states: 50_000,
                   max_candidates: 50_000, grids: false, grid_side: 2,
                   entries: 2048, grid_scan_limit: 50_000)
      raise "expected an immutable checked Scheme" unless parent.is_a?(B::Scheme)
      raise "invalid context limits" unless [max_leaf, max_vertices, max_states, max_candidates,
        entries, grid_scan_limit].all? { |v| v.is_a?(Integer) && v.positive? }
      raise "invalid grid side" unless grid_side.is_a?(Integer) && grid_side.between?(2, 4)
      raise "invalid grids flag" unless grids == true || grids == false
      @parent, @capacity = parent, entries
      @limits = {max_leaf: max_leaf, max_vertices: max_vertices, max_states: max_states,
        max_candidates: max_candidates, grids: grids, grid_side: grid_side}.freeze
      shared = [[1, 1, 1]]
      3.times do |axis|
        maximum = parent.terms.group_by { |t| t[axis] }.values.map(&:size).max
        2.upto(maximum) do |size|
          dims = [1, 1, 1]; dims[B::EXPANDED_DIMENSION[axis]] = size
          shared << dims
        end
      end
      all_grids = grids ? (2..grid_side).flat_map { |h|
        (2..grid_side).flat_map { |w| [1, h, w].permutation.to_a }
      }.uniq : []
      actual_grids = []
      @shape_scan_complete = true
      if grids
        count = 0
        MetaflipBudPackings.grid_groups(parent, max_side: grid_side).each do |group|
          count += 1
          if count > grid_scan_limit
            # A superset key is safe but less selective; never use a partial
            # catalog to declare other grid shapes impossible.
            actual_grids = all_grids
            @shape_scan_complete = false
            break
          end
          actual_grids << group.fetch(:elementary_shape)
        end
      end
      @query_dimensions = (shared + all_grids).uniq.sort.map(&:freeze).freeze
      @key_dimensions = (shared + actual_grids).uniq.sort.map(&:freeze).freeze
      @cache = {}
      @hits = @misses = 0
    end

    def stats
      {hits: @hits, misses: @misses, entries: @cache.size,
       grid_shape_scan_complete: @shape_scan_complete}
    end

    def solve(scale, library)
      raise "invalid scale" unless scale.length == 3 &&
        scale.all? { |v| v.is_a?(Integer) && v.positive? } && scale.max <= @limits[:max_leaf]
      # Freeze every lookup the cold solver can make, including shapes that
      # have no actual grid. The fingerprint omits only structurally impossible
      # grids; their prices cannot change candidates, states, or tie choices.
      prices, costs = {}, {}
      @query_dimensions.each do |dims|
        leaf = dims.zip(scale).map { |d, s| d*s }
        if leaf.max > @limits[:max_leaf]
          costs[dims] = nil
          next
        end
        unless prices.key?(leaf)
          rank = library.rank(leaf)
          raise "invalid leaf price" unless rank.is_a?(Integer) && rank.positive?
          prices[leaf] = rank
        end
        costs[dims] = prices.fetch(leaf)
      end
      context = @key_dimensions.map { |dims| costs.fetch(dims) }
      divisor = context.compact.reduce(&:gcd)
      key = context.map { |cost| cost && cost/divisor }.freeze
      if (saved = @cache[key])
        @hits += 1
        result = Marshal.load(saved)
        result[:formula_rank] *= divisor
        return result
      end
      @misses += 1
      result = MetaflipBudPackings.solve(@parent, scale, FrozenPrices.new(prices, ordered: true), **@limits)
      # Incomplete search certificates are never upgraded or reused.
      if result[:exact_within_model]
        raise "inconsistent normalized cost" unless result[:formula_rank] % divisor == 0
        normalized = result.merge(formula_rank: result[:formula_rank]/divisor)
        @cache.shift if @cache.size >= @capacity
        @cache[key] = Marshal.dump(normalized)
      end
      result
    end
  end
end
