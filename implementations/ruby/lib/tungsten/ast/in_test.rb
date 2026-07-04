module Tungsten::AST
  class InTest < Node
    attr_accessor :lhs, :elements

    def initialize(lhs, elements)
      @lhs = lhs
      @elements = elements
    end

    def children
      yield @lhs if @lhs.is_a?(Node)
      @elements.each { |element| yield element if element.is_a?(Node) }
    end

    def ==(other)
      super && other.lhs == lhs && other.elements == elements
    end
  end
end
