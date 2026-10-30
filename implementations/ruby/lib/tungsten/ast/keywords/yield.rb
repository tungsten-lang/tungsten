module Tungsten::AST
  class Yield < KeywordArgs
    def eval_in(interp)
      interp.visit_yield(self)
    end
  end
end
