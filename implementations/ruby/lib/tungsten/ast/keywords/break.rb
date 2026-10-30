module Tungsten::AST
  class Break < KeywordValue
    def eval_in(interp)
      interp.visit_break(self)
    end

    def sexp_name
      :break
    end
  end
end
