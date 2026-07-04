module Tungsten::AST
  class List < Node
    include Enumerable

    attr_accessor :list

    def self.from(obj)
      case obj
      when nil     then new

      # @todo this looks wrong
      when List    then obj
      when ::Array then new(obj)
      else
        new [obj]
      end
    end

    def initialize(list = [])
      @list = list
    end

    def [](i)
      @list[i]
    end

    def <<(exp)
      @list << exp
    end

    def children
      @list.each { |e| yield e if e.is_a?(Node) }
    end

    def accept_children(visitor)
      children { |child| child.accept visitor }
    end

    def each(&block)
      @list.each(&block)
    end

    def empty?
      @list.empty?
    end

    def last
      @list.last
    end

    def ==(other)
      super && other.list == list
    end

    def clone
      self.class.new(list.map(&:clone)).tap do |node|
        node.location = location
      end
    end
  end
end
