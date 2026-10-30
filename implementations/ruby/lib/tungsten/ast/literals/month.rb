module Tungsten::AST
  class Month < Value
    def initialize(value)
      @value = ::Tungsten::Month.new(value.to_s)
    end

    def eval_in(_interp)
      @value
    end
  end
end
