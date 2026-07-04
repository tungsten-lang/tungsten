module Tungsten::AST
  # @source rubinius
  class Flip2 < Node
    def initialize(start, finish)
      @start = start
      @finish = finish
    end

    def sexp_name
      :flip2
    end

    def exclusive?
      false
    end

    def to_sexp
      [sexp_name, @start.to_sexp, @finish.to_sexp]
    end
  end
end
