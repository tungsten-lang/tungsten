# frozen_string_literal: true

module Tungsten
  # Reference-host facade for the process environment. Snapshot methods return
  # ordinary Ruby Arrays/Hashes, matching the values the Tungsten interpreter
  # uses for its Core collection types.
  class Env
    class << self
      def get(name, default = nil)
        validate_name(name)
        ENV.fetch(name, default)
      end

      def [](name) = get(name)

      def fetch(name, *defaults, &block)
        validate_name(name)
        return ENV.fetch(name, &block) if defaults.empty?

        ENV.fetch(name, defaults.first, &block)
      end

      def set(name, value)
        validate_name(name)
        validate_value(value)
        ENV[name] = value
      end

      def []=(name, value)
        set(name, value)
      end

      def delete(name)
        validate_name(name)
        ENV.delete(name)
      end

      def key?(name)
        validate_name(name)
        ENV.key?(name)
      end

      def include?(name) = key?(name)
      def keys = ENV.keys
      def values = ENV.values
      def to_h = ENV.to_h
      def size = ENV.size
      def empty? = ENV.empty?

      def each(&block)
        ENV.to_h.each(&block)
        self
      end

      private

      def validate_name(name)
        unless name.is_a?(String) && !name.empty? && !name.include?("=") && !name.include?("\0")
          raise Tungsten::Error, "environment variable name must be a non-empty String without '=' or NUL"
        end
      end

      def validate_value(value)
        unless value.is_a?(String) && !value.include?("\0")
          raise Tungsten::Error, "environment variable value must be a String without NUL"
        end
      end
    end
  end
end
