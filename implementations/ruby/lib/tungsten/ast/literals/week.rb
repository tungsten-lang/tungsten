module Tungsten::AST
  class Week < Value
    def initialize(value)
      @value = ::Tungsten::Week.new(value.to_s)
    end
  end
end
