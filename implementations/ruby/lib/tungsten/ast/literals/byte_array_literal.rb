module Tungsten::AST
  class ByteArrayLiteral < Value
    def initialize(values)
      @value = values
    end
  end
end
