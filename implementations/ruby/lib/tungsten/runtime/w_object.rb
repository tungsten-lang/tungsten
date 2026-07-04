# frozen_string_literal: true

module Tungsten
  module Runtime
    class WObject
      attr_accessor :w_class, :instance_vars

      def initialize(w_class)
        @w_class = w_class
        @instance_vars = {}
      end

      def get_ivar(name)  = @instance_vars[name]
      def set_ivar(name, value) = (@instance_vars[name] = value)
      def to_s = "#<#{@w_class&.name || 'Object'}>"
    end
  end
end
