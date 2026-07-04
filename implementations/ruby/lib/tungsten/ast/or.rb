module Tungsten::AST
  class Or < Node
    attr_accessor :left, :right

    def initialize(left, right)
      @left = left
      @right = right
    end

    def children
      yield @left if @left.is_a?(Node)
      yield @right if @right.is_a?(Node)
    end

    def ==(other)
      super && other.left == left && other.right == right
    end
  end
end
