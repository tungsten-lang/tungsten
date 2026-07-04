# frozen_string_literal: true

require "ipaddr"

module Tungsten
  class IP4 < Literal
    def self.parse(text)
      new(text)
    end

    def self.of(a, b, c, d, prefix = nil)
      suffix = prefix.nil? ? "" : "/#{prefix}"
      new("#{a}.#{b}.#{c}.#{d}#{suffix}")
    end

    def self.cidr(address, prefix)
      parse(address).with_prefix(prefix)
    end

    attr_reader :prefix

    def initialize(value, prefix: :infer)
      raw = value.to_s
      address_text, prefix_text = raw.split("/", 2)
      inferred_prefix = prefix_text&.to_i
      @value = value.is_a?(::IPAddr) ? value : ::IPAddr.new(address_text)
      raise Tungsten::Error, "expected IPv4 address" unless @value.ipv4?

      @prefix = prefix == :infer ? inferred_prefix : prefix
    end

    def to_s
      @prefix.nil? ? @value.to_s : "#{@value.to_s}/#{@prefix}"
    end
    alias inspect to_s

    def to_i = @value.to_i
    def cidr? = !@prefix.nil?
    def with_prefix(prefix) = CIDR4.new("#{@value}/#{prefix}")

    def octet(index)
      idx = index.to_i
      return nil unless idx.between?(0, 3)

      (to_i >> (8 * (3 - idx))) & 0xff
    end
    alias [] octet

    def octets = 4.times.map { |index| octet(index) }
    def a = octet(0)
    def b = octet(1)
    def c = octet(2)
    def d = octet(3)

    def network
      return self.class.new(@value) unless cidr?

      self.class.new(@value.mask(@prefix), prefix: @prefix)
    end

    def netmask
      mask = @prefix.nil? ? 0xffffffff : ((0xffffffff << (32 - @prefix)) & 0xffffffff)
      self.class.of((mask >> 24) & 0xff, (mask >> 16) & 0xff, (mask >> 8) & 0xff, mask & 0xff)
    end
    alias mask netmask

    def broadcast
      pfx = @prefix || 32
      mask = pfx.zero? ? 0 : ((0xffffffff << (32 - pfx)) & 0xffffffff)
      addr = to_i | (~mask & 0xffffffff)
      self.class.of((addr >> 24) & 0xff, (addr >> 16) & 0xff, (addr >> 8) & 0xff, addr & 0xff, @prefix)
    end

    def include?(address)
      other = address.is_a?(IP4) ? address : IP4.parse(address)
      return to_i == other.to_i unless cidr?

      mask = @prefix.zero? ? 0 : ((0xffffffff << (32 - @prefix)) & 0xffffffff)
      (to_i & mask) == (other.to_i & mask)
    end
    alias contains? include?

    def private? = @value.private?
    def loopback? = @value.loopback?
    def link_local? = @value.link_local?
    def multicast? = (to_i & 0xf0000000) == 0xe0000000
    def unspecified? = to_i.zero?
    def broadcast? = to_i == 0xffffffff
    def reserved? = (to_i & 0xf0000000) == 0xf0000000
    def global? = !(private? || loopback? || link_local? || multicast? || unspecified? || broadcast? || reserved?)

    def ==(other)
      other = IP4.parse(other) unless other.is_a?(IP4)
      to_i == other.to_i && prefix == other.prefix
    rescue StandardError
      false
    end

    def eql?(other) = other.is_a?(IP4) && self == other
    def hash = [to_i, prefix].hash
  end

  IPv4 = IP4
end
