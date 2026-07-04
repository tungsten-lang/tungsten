require "date"

module Tungsten::AST
  class Date < Value
    def initialize(value)
      @value = ::Date.parse(value.to_s)
    end
  end
end
