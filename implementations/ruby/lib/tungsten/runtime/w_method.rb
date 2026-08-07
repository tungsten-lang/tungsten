# frozen_string_literal: true

module Tungsten
  module Runtime
    class WMethod
      attr_accessor :name, :params, :body, :defining_class, :splat_index, :param_types

      def initialize(name, params, body, defining_class = nil, splat_index: nil, param_types: nil)
        @name = name
        @params = params
        @body = body
        @defining_class = defining_class
        @splat_index = splat_index
        @param_types = param_types
      end
    end
  end
end
