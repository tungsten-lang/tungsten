module Tungsten
  class Type
    attr_reader :name

    def initialize(name)
      @name = name
    end

    # attr_reader :name, :llvm_type

    # def initialize(name, llvm_type)
    #   @name      = name
    #   @llvm_type = llvm_type
    # end

    # Boolean = Type.new "Boolean", LLVM::Int1
    # Int     = Type.new "Int",     LLVM::Int
    # Float   = Type.new "Float",   LLVM::Float
  end
end
