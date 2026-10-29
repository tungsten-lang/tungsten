module Tungsten::AST
  class ClassVar < Node
    attr_accessor :name

    def initialize(name)
      @name = Tungsten::AST.intern_name(name)
    end

    def eval_in(interp)
      interp.visit_class_var(self)
    end

    def can_assign?
      true
    end

    def ==(other)
      super && other.name == name
    end

    def clone
      self.class.new(name).tap do |node|
        node.location = location
      end
    end
  end
end
