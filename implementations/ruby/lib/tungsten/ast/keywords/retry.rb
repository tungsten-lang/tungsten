module Tungsten::AST
  class Retry < Node
    def to_sexp
      [:retry]
    end
  end
end
