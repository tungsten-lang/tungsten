module Tungsten::AST
  class Month < Value
    def initialize(value)
      @value = ::Tungsten::Month.new(value.to_s)
    end
  end
end
