module Tungsten::AST
  class Begin < Node
    attr_accessor :body, :rescue_var, :rescue_body, :ensure_body

    def initialize(body, rescue_var = nil, rescue_body = nil, ensure_body = nil)
      @body = List.from(body)
      @rescue_var = rescue_var
      @rescue_body = List.from(rescue_body)
      @ensure_body = List.from(ensure_body)
    end

    def ==(other)
      super && other.body == body &&
               other.rescue_var == rescue_var &&
               other.rescue_body == rescue_body &&
               other.ensure_body == ensure_body
    end
  end
end
