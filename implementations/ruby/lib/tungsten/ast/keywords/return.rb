module Tungsten::AST
  class Return < KeywordValue
    def eval_in(interp)
      interp.visit_return(self)
    end

    def sexp_name
      :return
    end
  end
end
