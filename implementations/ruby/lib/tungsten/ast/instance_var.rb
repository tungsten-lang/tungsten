module Tungsten::AST
  class InstanceVar < Node
    attr_accessor :name

    def initialize(name)
      @name = Tungsten::AST.intern_name(name)
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
