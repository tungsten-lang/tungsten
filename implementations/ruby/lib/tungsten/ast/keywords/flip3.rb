module Tungsten::AST
  class Flip3 < Flip2
    def sexp_name
      :flip3
    end

    def exclusive?
      true
    end
  end
end
