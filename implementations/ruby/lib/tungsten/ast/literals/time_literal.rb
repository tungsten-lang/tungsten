module Tungsten::AST
  class TimeLiteral < Value
    def initialize(value)
      @value = value
    end

    def eval_in(interp)
      interp.visit_time_literal(self)
    end
  end
end
