module Tungsten::AST
  # Boolean NOT of a target predicate in a guard expression.
  # Example: !(linux || macos)
  #
  class TargetNot < Node
    attr_accessor :expression

    def initialize(expression)
      @expression = expression
    end

    def ==(other)
      super && other.expression == expression
    end

    def clone
      self.class.new(expression.clone).tap { |n| n.location = location }
    end

    def to_sexp
      [:target_not, @expression.to_sexp]
    end
  end
end
