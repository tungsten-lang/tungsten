module Tungsten
  module Target
    ARCH_ALIASES = { "amd64" => "x86_64", "intel" => "x86_64", "aarch64" => "arm64" }.freeze
    KNOWN_OS     = %w[macos linux windows freebsd].freeze
    KNOWN_ARCH   = %w[x86_64 arm64].freeze

    def self.current
      @current ||= detect
    end

    def self.current=(target)
      @current = target
    end

    def self.reset!
      @current = nil
    end

    def self.detect
      os = case RUBY_PLATFORM
           when /darwin/i  then "macos"
           when /linux/i   then "linux"
           when /mingw|mswin/i then "windows"
           when /freebsd/i then "freebsd"
           end
      arch = case RUBY_PLATFORM
             when /x86_64|amd64/i  then "x86_64"
             when /arm64|aarch64/i then "arm64"
             end
      features = detect_features(os)
      { os: os, arch: arch, features: features }
    end

    def self.detect_features(os)
      features = []
      if os == "linux"
        features << "io_uring" if File.exist?("/proc/sys/kernel/io_uring_disabled") || File.exist?("/proc/sys/kernel/io_uring_group")
      end
      if os == "macos"
        features << "metal" if File.exist?("/System/Library/Frameworks/Metal.framework/Metal")
      end
      features
    rescue
      features
    end

    def self.matches?(predicate, capabilities, target = current)
      evaluate_predicate(predicate, target) &&
        capabilities.all? { |cap| target[:features].include?(cap) }
    end

    def self.evaluate_predicate(node, target)
      case node
      when AST::TargetDesignator
        name = normalize(node.name)
        target[:os] == name || target[:arch] == name
      when AST::TargetAnd
        evaluate_predicate(node.left, target) && evaluate_predicate(node.right, target)
      when AST::TargetOr
        evaluate_predicate(node.left, target) || evaluate_predicate(node.right, target)
      when AST::TargetNot
        !evaluate_predicate(node.expression, target)
      else
        false
      end
    end

    def self.normalize(name)
      ARCH_ALIASES.fetch(name, name)
    end
  end
end
