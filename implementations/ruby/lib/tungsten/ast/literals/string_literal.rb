module Tungsten::AST
  class StringLiteral < Value
    def initialize(value)
      @value = value.to_s
    end
  end
end
