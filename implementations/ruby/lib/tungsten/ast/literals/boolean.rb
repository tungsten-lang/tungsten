module Tungsten::AST
  class Boolean < Value
    def initialize(value)
      @value = value
    end

    def eval_in(_interp)
      @value
    end
  end
end
