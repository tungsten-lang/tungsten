# frozen_string_literal: true

require "set"

module Tungsten
  # Mathematical set: unique elements, unordered, O(1) membership.
  # Source syntax: `{1, 2, 3}` (distinct from hash `{a: 1}` and block `{x}`).
  class SetLiteral
    include Enumerable
    include Comparable

    attr_reader :elements  # internal: a Ruby Set

    def initialize(elements)
      @elements = elements.is_a?(::Set) ? elements : ::Set.new(elements)
    end

    def each(&block)        = @elements.each(&block)
    def size                = @elements.size
    def length              = @elements.size
    def empty?              = @elements.empty?
    def include?(elem)      = @elements.include?(elem)
    def member?(elem)       = @elements.include?(elem)

    def |(other)            = SetLiteral.new(@elements | coerce_other(other))   # union
    def &(other)            = SetLiteral.new(@elements & coerce_other(other))   # intersection
    def -(other)            = SetLiteral.new(@elements - coerce_other(other))   # difference
    def ^(other)            = SetLiteral.new(@elements ^ coerce_other(other))   # symmetric difference

    alias_method :union, :|
    alias_method :intersection, :&
    alias_method :difference, :-

    def subset?(other)      = @elements.subset?(coerce_other(other))
    def superset?(other)    = @elements.superset?(coerce_other(other))
    def proper_subset?(other) = @elements.proper_subset?(coerce_other(other))
    def proper_superset?(other) = @elements.proper_superset?(coerce_other(other))

    def to_a                = @elements.to_a
    def to_set              = @elements
    def to_multiset         = MultisetLiteral.new(to_a)

    def ==(other)
      case other
      when SetLiteral then @elements == other.elements
      when ::Set      then @elements == other
      else false
      end
    end

    alias_method :eql?, :==
    def hash                = @elements.hash

    def to_s
      return "{ }" if empty?
      "{ #{@elements.to_a.map(&:inspect).join(", ")} }"
    end

    def inspect             = to_s

    private

    def coerce_other(other)
      case other
      when SetLiteral      then other.elements
      when MultisetLiteral then ::Set.new(other.to_a)
      when ::Set           then other
      when Array           then ::Set.new(other)
      else raise TypeError, "expected Set or Array, got #{other.class}"
      end
    end
  end

  # Multiset (bag): elements with multiplicities. `<{1, 2, 2, 3}>` has count {1=>1, 2=>2, 3=>1}.
  # Mathematical operations preserve / merge multiplicities.
  class MultisetLiteral
    include Enumerable

    attr_reader :counts  # Hash{element => count}

    def initialize(elements)
      @counts = Hash.new(0)
      case elements
      when Hash         then elements.each { |k, v| @counts[k] += v }
      when MultisetLiteral then elements.counts.each { |k, v| @counts[k] += v }
      else                   elements.each { |e| @counts[e] += 1 }
      end
      @counts.delete_if { |_, v| v <= 0 }
    end

    # Iterate every occurrence (yields duplicates).
    def each
      return enum_for(:each) unless block_given?
      @counts.each { |elem, count| count.times { yield elem } }
    end

    def size                = @counts.values.sum
    def length              = size
    def empty?              = @counts.empty?
    def include?(elem)      = @counts.key?(elem)
    def count(elem = nil)   = elem.nil? ? size : @counts[elem]
    def uniq                = SetLiteral.new(@counts.keys)
    def to_a                = each.to_a

    # Set-style operations preserve multiplicity:
    # union (additive)        — counts add
    # intersection (min)      — counts take min
    # difference              — subtract counts, floor at 0
    def |(other)
      merged = Hash.new(0)
      @counts.each { |k, v| merged[k] += v }
      coerce_counts(other).each { |k, v| merged[k] += v }
      MultisetLiteral.new(merged)
    end

    def &(other)
      other_counts = coerce_counts(other)
      keys = @counts.keys & other_counts.keys
      MultisetLiteral.new(keys.to_h { |k| [k, [@counts[k], other_counts[k]].min] })
    end

    def -(other)
      result = @counts.dup
      coerce_counts(other).each do |k, v|
        next unless result.key?(k)
        result[k] -= v
        result.delete(k) if result[k] <= 0
      end
      MultisetLiteral.new(result)
    end

    alias_method :union, :|
    alias_method :intersection, :&
    alias_method :difference, :-

    def ==(other)
      case other
      when MultisetLiteral then @counts == other.counts
      else false
      end
    end

    alias_method :eql?, :==
    def hash                = @counts.hash

    def to_s
      return "<{ }>" if empty?
      # Render each element as many times as it appears, sorted for determinism.
      parts = @counts.flat_map { |k, v| Array.new(v) { k.inspect } }
      "<{ #{parts.join(", ")} }>"
    end

    def inspect             = to_s

    private

    def coerce_counts(other)
      case other
      when MultisetLiteral then other.counts
      when SetLiteral      then other.elements.to_h { |e| [e, 1] }
      when Array           then other.tally
      when Hash            then other
      else raise TypeError, "expected Multiset or Array, got #{other.class}"
      end
    end
  end
end
