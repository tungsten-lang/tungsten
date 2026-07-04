module Tungsten::AST
  class Not < UnaryExpression
    def clone
      Not.new(@exp.clone)
    end
  end
end
