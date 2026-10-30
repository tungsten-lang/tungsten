module Tungsten::AST
  class RationalLiteral < Value
    attr_reader :numerator, :denominator

    def initialize(value)
      parts = value.to_s.split("/")
      @numerator = parts[0].to_i
      @denominator = parts[1].to_i
      @value = Rational(@numerator, @denominator)
    end

    def eval_in(_interp)
      @value
    end
  end
end
