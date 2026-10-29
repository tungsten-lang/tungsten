module Tungsten::AST
  class Splat < Node
    attr_accessor :exp

    def initialize(exp)
      @exp = exp
    end

    def eval_in(interp)
      interp.visit_splat(self)
    end

    def ==(other)
      super && other.exp == exp
    end
  end
end
