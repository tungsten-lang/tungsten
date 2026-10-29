module Tungsten::AST
  class Tuple < Node
    attr_accessor :elements

    def initialize(elements = [])
      @elements = elements
    end

    def eval_in(interp)
      interp.visit_tuple(self)
    end

    def children
      @elements.each { |element| yield element if element.is_a?(Node) }
    end
  end
end
