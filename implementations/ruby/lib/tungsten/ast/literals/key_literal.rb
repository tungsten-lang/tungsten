module Tungsten::AST
  class KeyLiteral < Value
    def initialize(value)
      @value = value.to_s
    end
  end
end
