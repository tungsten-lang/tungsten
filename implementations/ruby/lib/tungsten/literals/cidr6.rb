# frozen_string_literal: true

require_relative "ip6"

module Tungsten
  class CIDR6 < IP6
    def initialize(value)
      raw = value.to_s
      prefix = raw.include?("/") ? raw.split("/", 2).last.to_i : value.respond_to?(:prefix) ? value.prefix : 128
      super(value, prefix:)
    end
  end
end
