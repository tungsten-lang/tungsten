module Tungsten::AST
  class KeywordArgs < Node
    attr_accessor :args

    def initialize(args = [])
      @args = args || []
    end

    def children
      @args.each { |arg| yield arg if arg.is_a?(Node) }
    end

    def ==(other)
      super && other.args == args
    end

    def clone
      self.class.new(args.map(&:clone)).tap do |node|
        node.location = location
      end
    end
  end
end
