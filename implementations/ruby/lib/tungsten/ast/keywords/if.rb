module Tungsten::AST
  #    'if' condition
  #       expressions
  #  [ 'else'
  #      expressions
  #  ]
  #
  class If < Node
    attr_accessor :condition, :body, :else

    attr_accessor :then_block, :else_block

    def initialize(condition, a_then, a_else = nil)
      @condition = condition
      @then_block = List.from(a_then)
      @else_block = List.from(a_else)
    end

    def children
      yield @condition if @condition.is_a?(Node)
      yield @then_block if @then_block.is_a?(Node)
      yield @else_block if @else_block.is_a?(Node)
    end

    def ==(other)
      super && other.condition  == condition  &&
               other.then_block == then_block &&
               other.else_block == else_block
    end

    def clone
      self.class.new(condition.clone, then_block.clone, else_block.clone).tap do |node|
        node.location = location
      end
    end

    def to_sexp
      [:if, @condition.to_sexp, @then_block.to_sexp, @else_block.to_sexp]
    end
  end
end
