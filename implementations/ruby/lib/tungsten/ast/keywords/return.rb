module Tungsten::AST
  class Return < KeywordValue
    def sexp_name
      :return
    end
  end
end
