module Tungsten::AST
  class Char < Value
    def initialize(value)
      @value = value
    end

    def eval_in(_interp)
      Tungsten::CharValue.new(@value)
    end
  end
end
