module Tungsten::AST
  class KeywordValue < Node
    attr_accessor :value

    def initialize(value)
      @value = value
    end

    def children
      yield @value if @value.is_a?(Node)
    end

    def sexp_name
      raise NotImplementedError
    end

    def to_sexp
      sexp = [sexp_name]
      sexp << @value.to_sexp if @value
      sexp
    end
  end
end
