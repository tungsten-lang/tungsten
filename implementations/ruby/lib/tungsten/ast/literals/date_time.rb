require "date"

module Tungsten::AST
  class DateTime < Value
    def initialize(value)
      @value = ::DateTime.parse(value.to_s)
    end
  end
end
