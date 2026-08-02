# frozen_string_literal: true

require "rbconfig"

module Tungsten
  # Single source of truth for C-compiler ISA/tuning flags shared by the Ruby
  # build/compile drivers (build.rb, compile.rb). Mirrors compiler/tungsten.w's
  # `march_flags`:
  #
  #   :native   host-tuned (-march=native -mtune=native) — local speed. Default.
  #   :portable a conservative baseline (-mtune=generic) so a distributed binary
  #             never hits an illegal instruction on a CPU older than the build
  #             machine. x86-64-v2 on x86; armv8-a on arm.
  #
  # -march is a clang codegen flag applied after .ll emission, so which mode is
  # chosen never affects the self-host stage1==stage2 byte-identity check.
  module BuildFlags
    module_function

    # Resolve optimization-profile and CPU-target flags as separate axes.
    # A bare release keeps Tungsten's historical portable baseline; an explicit
    # target wins over both that fallback and an ambient march override.
    def target_mode(release:, native:, portable:)
      raise ArgumentError, "--native and --portable are mutually exclusive" if native && portable

      return :native if native
      return :portable if portable

      release ? :portable : :native
    end

    def march_for(release:, native:, portable:, override: nil)
      mode = target_mode(release: release, native: native, portable: portable)
      if !native && !portable && !override.to_s.empty?
        override.split
      else
        march(mode)
      end
    end

    def march(mode)
      x86 = RbConfig::CONFIG["host_cpu"] =~ /x86_64|amd64|i\d86/
      if mode == :portable
        x86 ? %w[-march=x86-64-v2 -mtune=generic] : %w[-march=armv8-a -mtune=generic]
      else
        %w[-march=native -mtune=native]
      end
    end
  end
end
