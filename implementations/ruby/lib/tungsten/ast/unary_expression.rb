module Tungsten::AST
  class UnaryExpression < Node
    attr_accessor :exp

    def initialize(exp)
      @exp = exp
    end

    def children
      yield @exp if @exp.is_a?(Node)
    end

    def accept_children(visitor)
      children { |child| child.accept visitor }
    end

    def ==(other)
      super && other.exp == exp
    end
  end
end
