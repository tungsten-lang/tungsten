# frozen_string_literal: true

require "ipaddr"

module Tungsten
  class IP6 < Literal
    def self.parse(text)
      new(text)
    end

    attr_reader :prefix

    def initialize(value, prefix: :infer)
      raw = value.to_s
      address_text, prefix_text = raw.split("/", 2)
      inferred_prefix = prefix_text&.to_i
      @value = value.is_a?(::IPAddr) ? value : ::IPAddr.new(address_text)
      raise Tungsten::Error, "expected IPv6 address" unless @value.ipv6?

      @prefix = prefix == :infer ? inferred_prefix : prefix
    end

    def to_s
      @prefix.nil? ? @value.to_s : "#{@value.to_s}/#{@prefix}"
    end
    alias inspect to_s

    def cidr? = !@prefix.nil?
    def with_prefix(prefix) = CIDR6.new("#{@value}/#{prefix}")

    def byte(index)
      idx = index.to_i
      return nil unless idx.between?(0, 15)

      (to_i >> (8 * (15 - idx))) & 0xff
    end
    alias [] byte

    def bytes = 16.times.map { |index| byte(index) }
    def to_i = @value.to_i

    def network
      return self.class.new(@value) unless cidr?

      self.class.new(@value.mask(@prefix), prefix: @prefix)
    end

    def include?(address)
      other = address.is_a?(IP6) ? address : IP6.parse(address)
      return to_i == other.to_i unless cidr?

      width = 128
      all = (1 << width) - 1
      mask = @prefix.zero? ? 0 : ((all << (width - @prefix)) & all)
      (to_i & mask) == (other.to_i & mask)
    end
    alias contains? include?

    def unspecified? = to_i.zero?
    def loopback? = @value.loopback?
    def multicast? = byte(0) == 0xff
    def link_local? = byte(0) == 0xfe && (byte(1) & 0xc0) == 0x80
    def unique_local? = (byte(0) & 0xfe) == 0xfc
    alias private? unique_local?
    def global? = !(unspecified? || loopback? || multicast? || link_local? || unique_local?)

    def ==(other)
      other = IP6.parse(other) unless other.is_a?(IP6)
      to_i == other.to_i && prefix == other.prefix
    rescue StandardError
      false
    end

    def eql?(other) = other.is_a?(IP6) && self == other
    def hash = [to_i, prefix].hash
  end

  IPv6 = IP6
end
