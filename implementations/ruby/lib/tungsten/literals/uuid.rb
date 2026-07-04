# frozen_string_literal: true

require "digest"
require "securerandom"
require "socket"

module Tungsten
  class UUID < Literal
    NAMESPACE_NIL = "00000000-0000-0000-0000-000000000000"
    NAMESPACE_DNS = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
    NAMESPACE_URL = "6ba7b811-9dad-11d1-80b4-00c04fd430c8"
    NAMESPACE_OID = "6ba7b812-9dad-11d1-80b4-00c04fd430c8"
    NAMESPACE_X500 = "6ba7b814-9dad-11d1-80b4-00c04fd430c8"

    attr_reader :raw_bytes

    def initialize(value)
      @raw_bytes = self.class.coerce_bytes(value)
      super(self.class.format(@raw_bytes))
    end

    def self.parse(text) = new(text)
    def self.nil_uuid = new(NAMESPACE_NIL)
    def self.dns = new(NAMESPACE_DNS)
    def self.url = new(NAMESPACE_URL)
    def self.oid = new(NAMESPACE_OID)
    def self.x500 = new(NAMESPACE_X500)

    def self.v1(options = nil)
      timestamp, clock_seq, node = time_fields(options)
      bytes = Array.new(16, 0)
      time_low = timestamp & 0xffff_ffff
      time_mid = (timestamp >> 32) & 0xffff
      time_hi = (timestamp >> 48) & 0x0fff
      bytes[0] = (time_low >> 24) & 0xff
      bytes[1] = (time_low >> 16) & 0xff
      bytes[2] = (time_low >> 8) & 0xff
      bytes[3] = time_low & 0xff
      bytes[4] = (time_mid >> 8) & 0xff
      bytes[5] = time_mid & 0xff
      bytes[6] = (time_hi >> 8) & 0xff
      bytes[7] = time_hi & 0xff
      bytes[8] = (clock_seq >> 8) & 0xff
      bytes[9] = clock_seq & 0xff
      bytes[10, 6] = node
      set_version_variant(bytes, 1)
      new(bytes)
    end

    def self.v2(options = nil)
      option_hash = options.is_a?(Hash) ? options : {}
      local_identifier = option_value(option_hash, :local_identifier, :local_id, :id) || 0
      domain = option_value(option_hash, :domain) || 0
      local_identifier = local_identifier.to_i
      domain = domain.to_i
      unless local_identifier.between?(0, 0xffff_ffff) && domain.between?(0, 255)
        raise Tungsten::Error, "UUID.v2: local identifier or domain out of range"
      end

      bytes = v1(options).raw_bytes
      bytes[0] = (local_identifier >> 24) & 0xff
      bytes[1] = (local_identifier >> 16) & 0xff
      bytes[2] = (local_identifier >> 8) & 0xff
      bytes[3] = local_identifier & 0xff
      bytes[9] = domain
      set_version_variant(bytes, 2)
      new(bytes)
    end

    def self.v3(namespace, name)
      ns = coerce_bytes(namespace)
      digest = ::Digest::MD5.digest(ns.pack("C*") + crypto_bytes(name)).bytes.first(16)
      set_version_variant(digest, 3)
      new(digest)
    end

    def self.v4
      bytes = SecureRandom.bytes(16).bytes
      set_version_variant(bytes, 4)
      new(bytes)
    end

    class << self
      alias random v4
    end

    def self.v5(namespace, name)
      ns = coerce_bytes(namespace)
      digest = ::Digest::SHA1.digest(ns.pack("C*") + crypto_bytes(name)).bytes.first(16)
      set_version_variant(digest, 5)
      new(digest)
    end

    def self.v6
      timestamp, clock_seq, node = time_fields
      bytes = Array.new(16, 0)
      bytes[0] = (timestamp >> 52) & 0xff
      bytes[1] = (timestamp >> 44) & 0xff
      bytes[2] = (timestamp >> 36) & 0xff
      bytes[3] = (timestamp >> 28) & 0xff
      bytes[4] = (timestamp >> 20) & 0xff
      bytes[5] = (timestamp >> 12) & 0xff
      bytes[6] = (timestamp >> 8) & 0x0f
      bytes[7] = timestamp & 0xff
      bytes[8] = (clock_seq >> 8) & 0xff
      bytes[9] = clock_seq & 0xff
      bytes[10, 6] = node
      set_version_variant(bytes, 6)
      new(bytes)
    end

    def self.v7
      bytes = Array.new(16, 0)
      millis = (::Time.now.to_r * 1000).to_i
      bytes[0] = (millis >> 40) & 0xff
      bytes[1] = (millis >> 32) & 0xff
      bytes[2] = (millis >> 24) & 0xff
      bytes[3] = (millis >> 16) & 0xff
      bytes[4] = (millis >> 8) & 0xff
      bytes[5] = millis & 0xff
      bytes[6, 10] = SecureRandom.bytes(10).bytes
      set_version_variant(bytes, 7)
      new(bytes)
    end

    def self.v8(custom = nil)
      bytes = custom.nil? ? SecureRandom.bytes(16).bytes : coerce_bytes(custom)
      set_version_variant(bytes, 8)
      new(bytes)
    end

    def self.coerce_bytes(value)
      case value
      when UUID then value.raw_bytes.dup
      when Tungsten::ByteArray then value.bytes.dup
      when Array
        raise Tungsten::Error, "invalid UUID byte length" unless value.length == 16

        value.map do |byte|
          int = byte.to_i
          raise Tungsten::Error, "invalid UUID byte" unless int.between?(0, 255)

          int
        end
      else
        parse_bytes(value.to_s)
      end
    end

    def self.crypto_bytes(value)
      case value
      when Tungsten::ByteArray then value.bytes.pack("C*")
      else value.to_s.b
      end
    end

    def self.parse_bytes(text)
      text = text.delete_prefix("urn:uuid:")
      hex =
        case text.length
        when 36
          unless text[8] == "-" && text[13] == "-" && text[18] == "-" && text[23] == "-"
            raise Tungsten::Error, "invalid UUID"
          end
          text.delete("-")
        when 32
          text
        else
          raise Tungsten::Error, "invalid UUID"
        end

      raise Tungsten::Error, "invalid UUID" unless hex.match?(/\A[0-9a-fA-F]{32}\z/)

      [hex].pack("H*").bytes
    end

    def self.format(bytes)
      hex = bytes.pack("C*").unpack1("H*")
      "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
    end

    def self.set_version_variant(bytes, version)
      bytes[6] = (bytes[6] & 0x0f) | (version << 4)
      bytes[8] = (bytes[8] & 0x3f) | 0x80
    end

    def self.time_fields(options = nil)
      time_value = nil
      node_value = nil
      if options.is_a?(Hash)
        time_value = option_value(options, :time, :at, :timestamp)
        raw_node_value = option_value(options, :mac, :node)
        unless raw_node_value.nil?
          node_value = mac_bytes(raw_node_value)
          raise Tungsten::Error, "UUID.v1/v2: invalid MAC option" if node_value.nil?
        end
      elsif !options.nil?
        node_value = mac_bytes(options)
        if node_value.nil?
          time_value = options
        end
      end

      @time_mutex ||= ::Mutex.new
      @time_mutex.synchronize do
        unless @time_state
          seed = SecureRandom.bytes(2).bytes
          @time_state = {
            clock_seq: (((seed[0] << 8) | seed[1]) & 0x3fff),
            node: default_node,
            last_timestamp: 0
          }
        end

        timestamp = uuid_timestamp(time_value)
        if timestamp <= @time_state[:last_timestamp]
          @time_state[:clock_seq] = (@time_state[:clock_seq] + 1) & 0x3fff
        end
        @time_state[:last_timestamp] = timestamp
        [timestamp, @time_state[:clock_seq], node_value || @time_state[:node].dup]
      end
    end

    def self.uuid_timestamp(value)
      offset = 0x01b21dd213814000
      return (::Time.now.to_r * 10_000_000).to_i + offset if value.nil?
      return (value.to_r * 10_000_000).to_i + offset if value.is_a?(::Time)

      if value.respond_to?(:unix_ms)
        return offset + value.unix_ms.to_i * 10_000
      end

      if value.is_a?(Integer)
        return value if value >= offset
        return offset + value * 10_000 if value.abs >= 1_000_000_000_000
        return offset + value * 10_000_000
      end

      if value.is_a?(Numeric)
        return (value.to_r * 10_000_000).to_i + offset
      end

      raise Tungsten::Error, "UUID.v1/v2: invalid time option"
    end

    def self.option_value(hash, *keys)
      keys.each do |key|
        return hash[key] if hash.key?(key)
        string_key = key.to_s
        return hash[string_key] if hash.key?(string_key)
      end
      nil
    end

    def self.default_node
      @default_node ||= local_mac || SecureRandom.bytes(6).bytes.tap { |node| node[0] |= 0x01 }
      @default_node.dup
    end

    def self.local_mac
      sysfs_mac || socket_mac
    end

    def self.sysfs_mac
      Dir.glob("/sys/class/net/*/address").sort.each do |path|
        next if File.basename(File.dirname(path)) == "lo"

        bytes = parse_mac(File.read(path).strip)
        return bytes if usable_mac?(bytes)
      rescue SystemCallError
        next
      end
      nil
    end

    def self.socket_mac
      Socket.getifaddrs.each do |ifaddr|
        text = ifaddr.addr&.inspect_sockaddr
        next unless text&.include?("LINK[")

        bytes = parse_mac(text)
        return bytes if usable_mac?(bytes)
      end
      nil
    rescue SystemCallError
      nil
    end

    def self.usable_mac?(bytes)
      bytes && bytes.length == 6 && bytes.any?(&:nonzero?) && (bytes[0] & 0x01).zero?
    end

    def self.mac_bytes(value)
      case value
      when Tungsten::ByteArray
        value.bytes.dup if value.bytes.length == 6
      when Array
        if value.length == 6
          value.map do |byte|
            int = byte.to_i
            raise Tungsten::Error, "UUID.v1/v2: MAC byte out of range" unless int.between?(0, 255)

            int
          end
        end
      else
        parse_mac(value.to_s)
      end
    end

    def self.parse_mac(text)
      hex = text.scan(/[0-9a-fA-F]{2}/).join
      return nil unless hex.length == 12

      [hex].pack("H*").bytes
    end

    def version
      case @raw_bytes[6] >> 4
      when 1 then :v1
      when 2 then :v2
      when 3 then :v3
      when 4 then :v4
      when 5 then :v5
      when 6 then :v6
      when 7 then :v7
      when 8 then :v8
      end
    end

    def variant
      case @raw_bytes[8] >> 4
      when 0..7 then :ncs
      when 8..11 then :rfc4122
      when 12..13 then :microsoft
      else :reserved
      end
    end

    def byte(index)
      @raw_bytes[index.to_i]
    end

    def bytes
      Tungsten::ByteArray.new(@raw_bytes)
    end
  end
end
