module Tungsten::AST
  # A bare platform designator in a target guard expression.
  # Examples: macos, linux, x86_64, arm64, amd64, intel
  #
  class TargetDesignator < Node
    attr_accessor :name

    def initialize(name)
      @name = Tungsten::AST.intern_name(name)
    end

    def ==(other)
      super && other.name == name
    end

    def clone
      self.class.new(name).tap { |n| n.location = location }
    end

    def to_sexp
      [:target_designator, @name]
    end
  end
end
