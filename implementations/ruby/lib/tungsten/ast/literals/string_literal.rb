module Tungsten::AST
  class StringLiteral < Value
    def initialize(value)
      @value = value.to_s
    end

    def eval_in(_interp)
      @value
    end
  end
end
