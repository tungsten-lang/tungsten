module Tungsten::AST
  # Boolean OR of two target predicates in a guard expression.
  # Example: linux || macos
  #
  class TargetOr < Node
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
      [:target_or, @left.to_sexp, @right.to_sexp]
    end
  end
end
