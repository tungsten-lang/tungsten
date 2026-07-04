# frozen_string_literal: true

require "base64"
require "digest"
require "openssl"
require "securerandom"

module Tungsten
  class Crypto
    def self.random_bytes(length)
      length = length.to_i
      raise Tungsten::Error, "Crypto.random_bytes: length out of range" if length.negative?

      Tungsten::ByteArray.new(SecureRandom.bytes(length).bytes)
    end

    def self.md5(data) = MD5.hexdigest(data)
    def self.md5_bytes(data) = MD5.digest(data)
    def self.sha1(data) = SHA1.hexdigest(data)
    def self.sha1_bytes(data) = SHA1.digest(data)
    def self.sha1_base64(data) = SHA1.base64digest(data)
    def self.sha224(data) = SHA224.hexdigest(data)
    def self.sha224_bytes(data) = SHA224.digest(data)
    def self.sha256(data) = SHA256.hexdigest(data)
    def self.sha256_bytes(data) = SHA256.digest(data)
    def self.sha384(data) = SHA384.hexdigest(data)
    def self.sha384_bytes(data) = SHA384.digest(data)
    def self.sha512(data) = SHA512.hexdigest(data)
    def self.sha512_bytes(data) = SHA512.digest(data)
    def self.sha512_224(data) = SHA2.hexdigest(data, "512/224")
    def self.sha512_224_bytes(data) = SHA2.digest(data, "512/224")
    def self.sha512_256(data) = SHA2.hexdigest(data, "512/256")
    def self.sha512_256_bytes(data) = SHA2.digest(data, "512/256")

    def self.sha2(data, bits = 256)
      SHA2.hexdigest(data, bits)
    end

    def self.sha2_bytes(data, bits = 256)
      SHA2.digest(data, bits)
    end

    def self.bytes_for(data)
      case data
      when Tungsten::ByteArray then data.bytes.pack("C*")
      else data.to_s.b
      end
    end

    class MD5
      def self.digest(data)
        Tungsten::ByteArray.new(::Digest::MD5.digest(Crypto.bytes_for(data)).bytes)
      end

      def self.hexdigest(data) = ::Digest::MD5.hexdigest(Crypto.bytes_for(data))
      def self.hex(data) = hexdigest(data)
    end

    class SHA1
      def self.digest(data)
        Tungsten::ByteArray.new(::Digest::SHA1.digest(Crypto.bytes_for(data)).bytes)
      end

      def self.hexdigest(data) = ::Digest::SHA1.hexdigest(Crypto.bytes_for(data))
      def self.hex(data) = hexdigest(data)
      def self.base64digest(data) = Base64.strict_encode64(::Digest::SHA1.digest(Crypto.bytes_for(data)))
    end

    class SHA224
      def self.digest(data)
        Tungsten::ByteArray.new(OpenSSL::Digest.new("SHA224").digest(Crypto.bytes_for(data)).bytes)
      end

      def self.hexdigest(data) = OpenSSL::Digest.new("SHA224").hexdigest(Crypto.bytes_for(data))
      def self.hex(data) = hexdigest(data)
    end

    class SHA256
      def self.digest(data)
        Tungsten::ByteArray.new(::Digest::SHA256.digest(Crypto.bytes_for(data)).bytes)
      end

      def self.hexdigest(data) = ::Digest::SHA256.hexdigest(Crypto.bytes_for(data))
      def self.hex(data) = hexdigest(data)
    end

    class SHA384
      def self.digest(data)
        Tungsten::ByteArray.new(::Digest::SHA2.new(384).digest(Crypto.bytes_for(data)).bytes)
      end

      def self.hexdigest(data) = ::Digest::SHA2.new(384).hexdigest(Crypto.bytes_for(data))
      def self.hex(data) = hexdigest(data)
    end

    class SHA512
      def self.digest(data)
        Tungsten::ByteArray.new(::Digest::SHA2.new(512).digest(Crypto.bytes_for(data)).bytes)
      end

      def self.hexdigest(data) = ::Digest::SHA2.new(512).hexdigest(Crypto.bytes_for(data))
      def self.hex(data) = hexdigest(data)
    end

    class SHA2
      def self.digest(data, bits = 256)
        case variant(bits)
        when 224 then SHA224.digest(data)
        when 256 then SHA256.digest(data)
        when 384 then SHA384.digest(data)
        when 512 then SHA512.digest(data)
        when "512/224"
          Tungsten::ByteArray.new(OpenSSL::Digest.new("SHA512-224").digest(Crypto.bytes_for(data)).bytes)
        when "512/256"
          Tungsten::ByteArray.new(OpenSSL::Digest.new("SHA512-256").digest(Crypto.bytes_for(data)).bytes)
        else
          raise Tungsten::Error, "unsupported SHA-2 variant: #{bits}"
        end
      end

      def self.hexdigest(data, bits = 256)
        case variant(bits)
        when 224 then SHA224.hexdigest(data)
        when 256 then SHA256.hexdigest(data)
        when 384 then SHA384.hexdigest(data)
        when 512 then SHA512.hexdigest(data)
        when "512/224" then OpenSSL::Digest.new("SHA512-224").hexdigest(Crypto.bytes_for(data))
        when "512/256" then OpenSSL::Digest.new("SHA512-256").hexdigest(Crypto.bytes_for(data))
        else
          raise Tungsten::Error, "unsupported SHA-2 variant: #{bits}"
        end
      end

      def self.hex(data, bits = 256) = hexdigest(data, bits)

      def self.variant(bits)
        case bits
        when 224, 256, 384, 512 then bits
        else
          case bits.to_s
          when "224" then 224
          when "256" then 256
          when "384" then 384
          when "512" then 512
          when "512/224", "512-224", "sha512_224" then "512/224"
          when "512/256", "512-256", "sha512_256" then "512/256"
          else bits
          end
        end
      end
    end
  end

  class Digest
    def self.md5(data) = Crypto::MD5.hexdigest(data)
    def self.md5_bytes(data) = Crypto::MD5.digest(data)
    def self.sha1(data) = Crypto::SHA1.hexdigest(data)
    def self.sha1_bytes(data) = Crypto::SHA1.digest(data)
    def self.sha1_base64(data) = Crypto::SHA1.base64digest(data)
    def self.sha224(data) = Crypto::SHA224.hexdigest(data)
    def self.sha224_bytes(data) = Crypto::SHA224.digest(data)
    def self.sha256(data) = Crypto::SHA256.hexdigest(data)
    def self.sha256_bytes(data) = Crypto::SHA256.digest(data)
    def self.sha384(data) = Crypto::SHA384.hexdigest(data)
    def self.sha384_bytes(data) = Crypto::SHA384.digest(data)
    def self.sha512(data) = Crypto::SHA512.hexdigest(data)
    def self.sha512_bytes(data) = Crypto::SHA512.digest(data)
    def self.sha512_224(data) = Crypto::SHA2.hexdigest(data, "512/224")
    def self.sha512_224_bytes(data) = Crypto::SHA2.digest(data, "512/224")
    def self.sha512_256(data) = Crypto::SHA2.hexdigest(data, "512/256")
    def self.sha512_256_bytes(data) = Crypto::SHA2.digest(data, "512/256")
    def self.sha2(data, bits = 256) = Crypto.sha2(data, bits)
    def self.sha2_bytes(data, bits = 256) = Crypto.sha2_bytes(data, bits)
  end

  class Random
    def self.bytes(length) = Crypto.random_bytes(length)
    def self.uuid = UUID.v4
    def self.uuid1(options = nil) = UUID.v1(options)
    def self.uuid2(options = nil) = UUID.v2(options)
    def self.uuid3(namespace, name) = UUID.v3(namespace, name)
    def self.uuid4 = UUID.v4
    def self.uuid5(namespace, name) = UUID.v5(namespace, name)
    def self.uuid6 = UUID.v6
    def self.uuid7 = UUID.v7
    def self.uuid8(custom = nil) = UUID.v8(custom)
  end
end
