# frozen_string_literal: true

module Tungsten
  module Runtime
    class WMethod
      attr_accessor :name, :params, :body, :defining_class, :splat_index, :param_types, :class_method, :block_param,
                    :has_return, :defining_env, :slot_names_template, :simple_w_method_plan

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
        @slot_names_template = nil
        @simple_w_method_plan = nil
      end
    end
  end
end
