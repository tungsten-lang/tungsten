module Tungsten::AST
  #
  # 'class' name [ '<' superclass ] [ '[' class_role ']' ]
  #    body
  #
  class ClassDef < Node
    attr_accessor :name, :body, :superclass, :class_role

    def initialize(name, body = nil, superclass = nil, class_role: nil)
      @name = Tungsten::AST.intern_name(name)

      @body = List.from(body)

      @superclass = Tungsten::AST.intern_name(superclass)
      @class_role = Tungsten::AST.intern_name(class_role)
    end

    def children
      yield @body if @body.is_a?(Node)
    end

    def accept_children(visitor)
      children { |child| child.accept visitor }
    end

    def ==(other)
      super && other.name       == name &&
               other.body       == body &&
               other.superclass == superclass &&
               other.class_role == class_role
    end

    def clone
      self.class.new(name, body.clone, superclass, class_role: class_role).tap do |node|
        node.location = location
      end
    end
  end
end
