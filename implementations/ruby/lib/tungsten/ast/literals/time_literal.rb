module Tungsten::AST
  class TimeLiteral < Value
    def initialize(value)
      @value = value
    end
  end
end
