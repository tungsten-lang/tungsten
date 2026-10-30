module Tungsten::AST
  class PercentageLiteral < Node
    attr_accessor :value_str, :num_type

    def initialize(value_str, num_type)
      @value_str = value_str
      @num_type = num_type
    end

    def eval_in(interp)
      interp.visit_percentage_literal(self)
    end

    def ==(other)
      other.is_a?(PercentageLiteral) &&
        other.value_str == @value_str &&
        other.num_type == @num_type
    end

    def children; end
  end
end
