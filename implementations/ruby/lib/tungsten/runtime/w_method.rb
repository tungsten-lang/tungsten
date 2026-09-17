# frozen_string_literal: true

module Tungsten
  module Runtime
    class WMethod
      attr_accessor :name, :params, :body, :defining_class, :splat_index, :param_types, :class_method

      def initialize(name, params, body, defining_class = nil, splat_index: nil, param_types: nil, class_method: false)
        @name = name
        @params = params
        @body = body
        @defining_class = defining_class
        @splat_index = splat_index
        @param_types = param_types
        @class_method = class_method
      end
    end
  end
end
