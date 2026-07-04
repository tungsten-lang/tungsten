module Tungsten::AST
  # An array literal.
  #
  #   '[' [ expression ] ( ',' expression )* ']'
  class ArrayLiteral < List
  end
end
