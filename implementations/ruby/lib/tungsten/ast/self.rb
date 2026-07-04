module Tungsten::AST
  class Self < Node
    def to_sexp
      [:self]
    end
  end
end
