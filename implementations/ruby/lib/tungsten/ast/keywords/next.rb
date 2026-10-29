module Tungsten::AST
  class Next < KeywordValue
    def eval_in(interp)
      interp.visit_next(self)
    end

    def sexp_name
      :next
    end
  end
end
