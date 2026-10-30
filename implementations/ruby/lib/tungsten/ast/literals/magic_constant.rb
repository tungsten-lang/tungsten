module Tungsten::AST
  class MagicConstant < Value
    def initialize(value)
      @value = value
    end

    def eval_in(interp)
      interp.visit_magic_constant(self)
    end
  end
end
