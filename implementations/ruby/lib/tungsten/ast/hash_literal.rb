module Tungsten::AST
  class HashLiteral < Node
    attr_accessor :entries

    def initialize(entries = [])
      @entries = entries
    end

    def ==(other)
      super && other.entries == entries
    end

    def clone
      cloned = entries.map { |k, v| [k.clone, v.clone] }
      self.class.new(cloned).tap do |node|
        node.location = location
      end
    end
  end
end
