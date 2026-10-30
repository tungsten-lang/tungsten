module Tungsten::AST
  class Week < Value
    def initialize(value)
      @value = ::Tungsten::Week.new(value.to_s)
    end

    def eval_in(_interp)
      @value
    end
  end
end
