module Tungsten::AST
  class TypedArray < Node
    attr_accessor :element_type, :size

    def initialize(element_type, size)
      @element_type = element_type
      @size = size
    end

    def children
      yield @size if @size.is_a?(Node)
    end

    def accept_children(visitor)
      children { |child| child.accept visitor }
    end
  end
end
