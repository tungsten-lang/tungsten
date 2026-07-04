module Tungsten::AST
  class ColorLiteral < Value
    attr_reader :r, :g, :b, :a

    def initialize(r, g, b, a = 255)
      @value = [r, g, b, a]
      @r = r
      @g = g
      @b = b
      @a = a
    end
  end
end
