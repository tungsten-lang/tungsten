module Tungsten::AST
  class AssignOp < Node
    attr_accessor :name, :operator, :value

    def initialize(name, operator, value)
      @name     = name
      @operator = operator
      @value    = value
    end

    def children
      yield @name if @name.is_a?(Node)
      yield @value if @value.is_a?(Node)
    end
  end
end
