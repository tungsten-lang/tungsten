module Tungsten::AST
  class Undef < Node
    attr_accessor :name

    def initialize(name)
      @name = name
    end

    def to_sexp
      [:undef, @name.to_sexp]
    end
  end
end
