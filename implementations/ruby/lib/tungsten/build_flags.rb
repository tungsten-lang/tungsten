# frozen_string_literal: true

require "rbconfig"

module Tungsten
  # Single source of truth for target-CPU flags shared by the Ruby build and
  # compile drivers. CPU selection is independent of optimization profile:
  # local builds use the configured CPU (native by default), while release
  # packaging asks for explicit x86-64-v2/v3 artifacts.
  module BuildFlags
    RELEASE_CPUS = %w[x86-64-v2 x86-64-v3].freeze
    CPU_ALIASES = {
      "v1" => "x86-64-v1",
      "v2" => "x86-64-v2",
      "v3" => "x86-64-v3",
      "v4" => "x86-64-v4"
    }.freeze

    module_function

    def normalize_cpu(cpu)
      value = cpu.to_s.strip.downcase
      value = CPU_ALIASES.fetch(value, value)
      raise ArgumentError, "CPU name cannot be empty" if value.empty?
      unless value.match?(/\A[a-z0-9][a-z0-9_.+-]*\z/)
        raise ArgumentError, "invalid CPU name: #{cpu.inspect}"
      end
      value
    end

    def configured_value(key, path: nil, env: ENV)
      path ||= env["TUNGSTEN_CONFIG"].to_s
      path = File.expand_path("~/.tungsten/config") if path.empty?
      return nil unless File.file?(path)

      section = nil
      File.foreach(path) do |line|
        text = line.sub(/\s+[#;].*\z/, "").strip
        next if text.empty? || text.start_with?("#", ";")
        if (match = text.match(/\A\[([^\]]+)\]\z/))
          section = match[1].strip
          next
        end
        next unless section == "build"
        match = text.match(/\A#{Regexp.escape(key)}\s*=\s*(.*?)\s*\z/)
        next unless match
        value = match[1]
        value = value[1...-1] if value.match?(/\A(["']).*\1\z/)
        return value
      end
      nil
    rescue Errno::ENOENT, Errno::EACCES
      nil
    end

    def configured_cpu(path: nil, env: ENV)
      from_env = env["TUNGSTEN_CPU"].to_s.strip
      return normalize_cpu(from_env) unless from_env.empty?

      value = configured_value("cpu", path: path, env: env)
      value && normalize_cpu(value)
    end

    def configured_cc(path: nil, env: ENV)
      from_env = env["TUNGSTEN_CC"].to_s.strip
      return from_env unless from_env.empty?

      configured_value("cc", path: path, env: env)
    end

    # A cross target without an explicit --cpu uses clang's baseline for that
    # target. It must not inherit a local apple-m5/native preference.
    def resolve_cpu(cpu: nil, native: false, target: nil, configured: nil)
      explicit = cpu && normalize_cpu(cpu)
      if native
        raise ArgumentError, "--native conflicts with --cpu #{explicit}" if explicit && explicit != "native"
        explicit = "native"
      end
      return explicit if explicit
      return nil unless target.to_s.empty?

      configured ? normalize_cpu(configured) : (configured_cpu || "native")
    end

    def x86_target?(target)
      triple = target.to_s
      return !!(RbConfig::CONFIG["host_cpu"] =~ /x86_64|amd64|i\d86/) if triple.empty?
      triple.match?(/\A(?:x86_64|amd64)/)
    end

    def march(cpu, target: nil)
      normalized = normalize_cpu(cpu)
      if normalized.match?(/\Ax86-64-v[1-4]\z/)
        ["-march=#{normalized}", "-mtune=generic"]
      elsif normalized == "native" && x86_target?(target)
        %w[-march=native -mtune=native]
      else
        ["-mcpu=#{normalized}"]
      end
    end

    def march_for(cpu: nil, native: false, target: nil, override: nil, configured: nil)
      explicit = cpu || native
      if !explicit && target.to_s.empty? && !override.to_s.empty?
        return override.split
      end

      resolved = resolve_cpu(cpu: cpu, native: native, target: target, configured: configured)
      resolved ? march(resolved, target: target) : []
    end
  end
end
