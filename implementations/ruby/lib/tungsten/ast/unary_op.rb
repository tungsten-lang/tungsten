module Tungsten::AST
  class UnaryOp < Node
    attr_accessor :operator, :right

    def initialize(operator, right)
      @operator = operator

      @right = right
      @right.parent = self
    end

    def children
      yield @right if @right.is_a?(Node)
    end

    def accept_children(visitor)
      children { |child| child.accept visitor }
    end

    def ==(other)
      super && other.right == right
    end

    def clone
      self.class.new(operator, right.clone).tap do |node|
        node.location = location
      end
    end
  end
end
