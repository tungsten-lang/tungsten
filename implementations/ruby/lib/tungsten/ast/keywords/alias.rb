module Tungsten::AST
  class Alias < Node
    attr_accessor :to, :from

    def initialize(to, from)
      @to   = to
      @from = from
    end

    def to_sexp
      [:alias, @to.to_sexp, @from.to_sexp]
    end
  end
end
