module Tungsten::AST
  class RangeLiteral < Node
    attr_accessor :from, :to, :exclusive

    def initialize(from, to, exclusive:)
      @from = from
      @to   = to
      @exclusive = exclusive
    end

    def children
      yield @from if @from.is_a?(Node)
      yield @to if @to.is_a?(Node)
    end

    def accept_children(visitor)
      children { |child| child.accept visitor }
    end

    def ==(other)
      super && other.from == @from &&
               other.to   == @to   &&
               other.exclusive == @exclusive
    end
  end
end
