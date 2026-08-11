# frozen_string_literal: true

require "open3"

module Tungsten
  module SystemDependencies
    module_function

    # Homebrew is installed under different prefixes on Apple Silicon, Intel,
    # Linuxbrew, and custom installations. Ask brew itself instead of baking an
    # architecture-specific prefix into every build host.
    def brew_prefix(formula = nil)
      @brew_prefixes ||= {}
      key = formula.to_s
      return @brew_prefixes[key] if @brew_prefixes.key?(key)

      command = ["brew", "--prefix"]
      command << formula if formula
      output, status = Open3.capture2(*command)
      @brew_prefixes[key] = status.success? && !output.strip.empty? ? output.strip : nil
    rescue Errno::ENOENT
      @brew_prefixes[key] = nil
    end

    def brew_header(formula, relative_path)
      prefix = brew_prefix(formula)
      prefix && File.join(prefix, "include", relative_path)
    end
  end
end
