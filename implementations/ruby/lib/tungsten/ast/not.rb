module Tungsten::AST
  class Not < UnaryExpression
    def eval_in(interp)
      interp.visit_not(self)
    end

    def clone
      Not.new(@exp.clone)
    end
  end
end
