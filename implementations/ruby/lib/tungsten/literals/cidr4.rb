# frozen_string_literal: true

require_relative "ip4"

module Tungsten
  class CIDR4 < IP4
    def initialize(value)
      raw = value.to_s
      prefix = raw.include?("/") ? raw.split("/", 2).last.to_i : value.respond_to?(:prefix) ? value.prefix : 32
      super(value, prefix:)
    end
  end

  class CIDR
    def self.parse(text)
      text.to_s.include?(":") ? IPv6.parse(text) : IPv4.parse(text)
    end

    def self.v4(text) = IPv4.parse(text)
    def self.v6(text) = IPv6.parse(text)
  end
end
