module Tungsten::AST
  class ByteArrayLiteral < Value
    def initialize(values)
      @value = values
    end

    def eval_in(interp)
      interp.visit_byte_array_literal(self)
    end
  end
end
