module Tungsten::AST
  class Duration < Value
    def initialize(value)
      @value = value
    end

    def eval_in(interp)
      interp.visit_duration(self)
    end
  end
end
