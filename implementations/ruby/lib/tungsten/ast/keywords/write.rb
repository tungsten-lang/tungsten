module Tungsten::AST
  class Write < KeywordArgs
    def eval_in(interp)
      interp.visit_write(self)
    end
  end
end
