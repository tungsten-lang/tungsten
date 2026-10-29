module Tungsten::AST
  class Recase < KeywordValue
    def eval_in(interp)
      interp.visit_recase(self)
    end

    def sexp_name
      :recase
    end
  end
end
