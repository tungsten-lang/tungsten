module Tungsten::AST
  class Print < KeywordArgs
    def eval_in(interp)
      interp.visit_print(self)
    end
  end
end
