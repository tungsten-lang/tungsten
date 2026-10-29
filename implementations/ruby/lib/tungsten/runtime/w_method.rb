# frozen_string_literal: true

module Tungsten
  module Runtime
    class WMethod
      attr_accessor :name, :params, :body, :defining_class, :splat_index, :param_types, :class_method, :block_param,
                    :has_return, :defining_env

      def initialize(name, params, body, defining_class = nil, splat_index: nil, param_types: nil, class_method: false, block_param: nil, defining_env: nil)
        @name = name
        @params = params
        @body = body
        @defining_class = defining_class
        @splat_index = splat_index
        @param_types = param_types
        @class_method = class_method
        @block_param = block_param
        @has_return = nil
        @defining_env = defining_env
      end
    end
  end
end
