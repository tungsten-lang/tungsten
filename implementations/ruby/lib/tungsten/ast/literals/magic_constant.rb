module Tungsten::AST
  class MagicConstant < Value
    def initialize(value)
      @value = value
    end
  end
end
