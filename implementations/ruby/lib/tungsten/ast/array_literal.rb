module Tungsten::AST
  # An array literal.
  #
  #   '[' [ expression ] ( ',' expression )* ']'
  class ArrayLiteral < List
    def eval_in(interp)
      interp.visit_array_literal(self)
    end
  end
end
