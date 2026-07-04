module Tungsten::AST
  class Redo < Node
    def to_sexp
      [:redo]
    end
  end
end
