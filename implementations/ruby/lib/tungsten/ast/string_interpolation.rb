module Tungsten::AST
  class StringInterpolation < Node
    attr_accessor :parts

    def initialize(parts = [])
      @parts = parts
    end

    def eval_in(interp)
      interp.visit_string_interpolation(self)
    end

    def children
      @parts.each { |part| yield part if part.is_a?(Node) }
    end
  end
end
