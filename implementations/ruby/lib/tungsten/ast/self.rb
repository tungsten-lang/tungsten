module Tungsten::AST
  class Self < Node
    def eval_in(interp)
      interp.visit_self(self)
    end

    def to_sexp
      [:self]
    end
  end
end
