module Tungsten::AST
  # Binary operator
  #
  #     left operator right
  #
  class BinaryOp < Node
    attr_accessor :left, :operator, :right

    def initialize(left, operator, right)
      @left     = left
      @operator = operator
      @right    = right
    end

    def children
      yield @left if @left.is_a?(Node)
      yield @right if @right.is_a?(Node)
    end

    def accept_children(visitor)
      children { |child| child.accept visitor }
    end

    def ==(other)
      super && other.left     == left &&
               other.operator == operator &&
               other.right    == right
    end

    def clone
      self.class.new(left.clone, operator, right.clone).tap do |node|
        node.location = location
      end
    end
  end
end
