module Tungsten::AST
  class TraitDef < Node
    attr_accessor :name, :body

    def initialize(name, body = nil)
      @name = Tungsten::AST.intern_name(name)
      @body = List.from(body)
    end

    def children
      yield @body if @body.is_a?(Node)
    end

    def accept_children(visitor)
      children { |child| child.accept visitor }
    end

    def ==(other)
      super && other.name == name && other.body == body
    end
  end
end
