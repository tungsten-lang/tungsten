module Tungsten::AST
  class Value < Node
    attr_accessor :value

    def ==(other)
      super && other.value == value
    end

    def children; end

    def clone
      self.class.new(value).tap do |node|
        node.location = location
      end
    end
  end
end
