module Tungsten::AST
  # with i in 0..9
  #   expressions
  #
  # with i in 0..9, j in 0..9
  #   expressions
  #
  class With < Node
    attr_accessor :bindings, :body

    def initialize(bindings, body = nil)
      @bindings = bindings
      @body = List.from body
    end

    def ==(other)
      super && other.bindings == bindings &&
               other.body     == body
    end

    def clone
      self.class.new(bindings.map { |var, expr| [var.clone, expr.clone] }, body.clone).tap do |node|
        node.location = location
      end
    end

    def to_sexp
      [:with, @bindings.map { |var, expr| [var.to_sexp, expr.to_sexp] }, @body.to_sexp]
    end
  end
end
