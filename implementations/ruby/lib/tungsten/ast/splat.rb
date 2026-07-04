module Tungsten::AST
  class Splat < Node
    attr_accessor :exp

    def initialize(exp)
      @exp = exp
    end

    def ==(other)
      super && other.exp == exp
    end
  end
end
