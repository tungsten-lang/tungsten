module Tungsten::AST
  # Boolean AND of two target predicates in a guard expression.
  # Example: linux && x86_64
  #
  class TargetAnd < Node
    attr_accessor :left, :right

    def initialize(left, right)
      @left = left
      @right = right
    end

    def ==(other)
      super && other.left == left && other.right == right
    end

    def clone
      self.class.new(left.clone, right.clone).tap { |n| n.location = location }
    end

    def to_sexp
      [:target_and, @left.to_sexp, @right.to_sexp]
    end
  end
end
