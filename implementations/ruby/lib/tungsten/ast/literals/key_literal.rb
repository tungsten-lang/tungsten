module Tungsten::AST
  class KeyLiteral < Value
    def initialize(value)
      @value = value.to_s
    end

    def eval_in(interp)
      interp.visit_key_literal(self)
    end
  end
end
