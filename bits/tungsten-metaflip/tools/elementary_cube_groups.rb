#!/usr/bin/env ruby
# Offline 2x2x2 elementary subtensors assembled from two nondegenerate 2x2
# layers. This is not an arbitrary rank-seven sub-tensor recognizer.
require_relative 'bud_packings'

module MetaflipElementaryCubeGroups
  B = MetaflipBudProducts
  P = MetaflipBudPackings
  module_function

  def coordinates(shape)
    shape[0].times.flat_map { |i| shape[1].times.flat_map { |j| shape[2].times.map { |k| [i,j,k] } } }
  end

  # Canonicalize only the shared free-factor array, using both row and column
  # swaps. Other two factor maps remain separate for each stacked layer.
  def canonical_layer(parent, group)
    shape = group.fetch(:elementary_shape)
    raise 'expected one elementary 2x2 layer' unless shape.sort == [1,2,2]
    stack = shape.index(1)
    other = [0,1,2]-[stack]
    free = B::EDGES.index(other)
    variants = [false,true].repeated_permutation(2).map do |flips|
      indices = coordinates(shape).map do |point|
        old = point.dup
        other.each_with_index { |v,n| old[v] = 1-old[v] if flips[n] }
        group.fetch(:indices).fetch((old[0]*shape[1]+old[1])*shape[2]+old[2])
      end
      [indices.map { |i| parent.terms.fetch(i).fetch(free) }, indices]
    end
    signature, indices = variants.min
    {stack: stack, shape: shape, signature: signature, indices: indices,
      mask: indices.reduce(0) { |m,i| m | (1<<i) }}
  end

  def scan(parent, max_layers: 50_000, max_pairs: 50_000, max_groups: 10_000, prune_singleton_free: true)
    raise 'expected checked Scheme' unless parent.is_a?(B::Scheme)
    raise 'invalid cube limits' unless [max_layers,max_pairs,max_groups].all? { |v| v.is_a?(Integer) && v.positive? }
    raise 'invalid free-factor filter' unless [true,false].include?(prune_singleton_free)
    report = {free_factor_filter: prune_singleton_free, complete: true, model: 'pairs of nondegenerate 2x2 elementary layers with the same free-factor array up to row/column swaps',
      record_claim: false, layers: 0, matching_pairs: 0, overlapping_pairs: 0,
      pattern_classes: 0, groups: [], cutoffs: []}
    buckets, masks = {}, {}
    stop = lambda do |reason|
      report[:complete] = false; report[:cutoffs] << reason; throw :limit
    end
    catch(:limit) do
      P.grid_groups(parent, max_side: 2, min_free_multiplicity: prune_singleton_free ? 2 : 1).each do |grid|
        stop.call('layers') if report[:layers] >= max_layers
        report[:layers] += 1
        layer = canonical_layer(parent, grid)
        key = [layer[:stack],layer[:signature]]
        previous = buckets[key] ||= []
        previous.each do |left|
          stop.call('pairs') if report[:matching_pairs] >= max_pairs
          report[:matching_pairs] += 1
          unless (left[:mask] & layer[:mask]).zero?
            report[:overlapping_pairs] += 1
            next
          end
          mask = left[:mask] | layer[:mask]
          # One checked map per exact subset suffices to witness an 8->7
          # replacement. No equivalence/dominance of resulting walks is claimed.
          next if masks.key?(mask)
          stop.call('groups') if report[:groups].size >= max_groups
          indices = coordinates([2,2,2]).map do |point|
            part = point[layer[:stack]].zero? ? left : layer
            local = point.dup; local[layer[:stack]] = 0
            shape = part[:shape]
            part[:indices].fetch((local[0]*shape[1]+local[1])*shape[2]+local[2])
          end
          group = {elementary_shape: [2,2,2], indices: indices}
          raise 'overlapping cube' unless indices.uniq.size == 8
          B.group_factor_maps(parent,group)
          masks[mask] = true
          report[:groups] << group
        end
        previous << layer
      end
    end
    report[:pattern_classes] = buckets.size
    report
  end

  def partition(parent, cube)
    raise 'expected cube shape' unless cube.fetch(:elementary_shape) == [2,2,2]
    used = cube.fetch(:indices).to_h { |i| [i,true] }
    groups = [cube] + parent.terms.each_index.filter_map { |i| {axis: nil, indices: [i]} unless used[i] }
    B.validate_groups(parent,groups)
    groups
  end
end
