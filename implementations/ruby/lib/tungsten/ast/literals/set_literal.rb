module Tungsten::AST
  class SetLiteral < Node
    attr_reader :elements

    def initialize(elements)
      @elements = elements
    end

    def accept(visitor) = visitor.visit_set_literal(self)
    def children(&block) = @elements.each(&block)
  end

  class MultisetLiteral < Node
    attr_reader :elements

    def initialize(elements)
      @elements = elements
    end

    def accept(visitor) = visitor.visit_multiset_literal(self)
    def children(&block) = @elements.each(&block)
  end
end
