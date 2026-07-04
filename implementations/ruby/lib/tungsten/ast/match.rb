module Tungsten::AST
  class Match < Node
    attr_accessor :pattern

    def initialize(pattern, flags)
      @pattern = RegexLiteral.new pattern, flags
    end

    def to_sexp
      [:match, @pattern.to_sexp]
    end
  end
end
