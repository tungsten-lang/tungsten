# frozen_string_literal: true

require "stringio"
require "rbconfig"
require "tmpdir"
require "shellwords"
require_relative "build_flags"

module Tungsten
  class Doctor
    # Build-time preflight. Returns [[name, install_hint], ...] for each
    # REQUIRED external tool that `bin/tungsten build` shells out to but that is
    # missing, so the caller can print friendly guidance and abort before a raw
    # make/clang error dump partway through the bootstrap.
    #
    # PATH-resolved build tools (clang, make) are checked directly. Linker and
    # header dependencies use functional probes so keg-only Homebrew installs
    # and other nonstandard-but-working layouts are accepted.
    def self.build_preflight
      linux = RbConfig::CONFIG["host_os"] =~ /linux/
      missing = []
      cc = selected_cc
      unless tool?(cc)
        missing << ["clang", linux ? "sudo apt-get install clang-22 lld-22" : "brew install llvm lld"]
      else
        cpu = BuildFlags.configured_cpu || "native"
        unless cpu_supported?(cpu, cc)
          hint = linux ? "install LLVM/Clang 22+ or choose a supported [build] cpu" :
                         "brew install llvm; set [build] cc = /opt/homebrew/opt/llvm/bin/clang"
          missing << ["configured CPU #{cpu}", hint]
        end
      end
      unless tool?("make")
        missing << ["make", linux ? "sudo apt-get install build-essential" : "xcode-select --install"]
      end
      # The compiler links with `clang -fuse-ld=lld`; a missing lld makes the
      # linker step fail (and the C VM can exit 0 having written no output, so
      # the failure surfaces later as a confusing "no such file" cp error).
      # On Ubuntu lld is a separate package; on macOS it ships with Homebrew
      # LLVM / the Xcode toolchain. Functional test, not a PATH lookup.
      unless linker_ok?(cc)
        missing << ["lld (clang -fuse-ld=lld)", linux ? "sudo apt-get install lld-22" : "brew install lld"]
      end
      # The runtime's slab_zstd.c includes <zstd.h>; without the dev headers the
      # very first runtime C file fails to compile.
      unless header?("zstd.h", zstd_cflags, cc)
        missing << ["libzstd headers (zstd.h)", linux ? "sudo apt-get install libzstd-dev" : "brew install zstd"]
      end
      missing
    end

    def self.selected_cc
      BuildFlags.configured_cc || "clang"
    end

    def self.tool?(name)
      File.executable?(name) || system("command -v #{Shellwords.escape(name)} > /dev/null 2>&1")
    end

    # True when clang can actually link a program with lld (what the build
    # does). A functional check rather than `command -v ld.lld` so it never
    # false-fails where lld resolves off-PATH (keg-only Homebrew LLVM on macOS).
    def self.linker_ok?(cc = selected_cc)
      out = File.join(Dir.tmpdir, "tungsten-lld-check-#{Process.pid}")
      ok = system("printf 'int main(void){return 0;}' | #{Shellwords.escape(cc)} -fuse-ld=lld -x c - -o #{out} > /dev/null 2>&1")
      File.delete(out) if File.exist?(out)
      ok
    end

    # True when a required C header is includable (preprocess test). Extra
    # cflags mirror however the build itself locates the header, so this never
    # false-fails where the header lives off the default include path.
    def self.header?(name, cflags = "", cc = selected_cc)
      system("printf '#include <#{name}>\\n' | #{Shellwords.escape(cc)} #{cflags} -E -x c - > /dev/null 2>&1")
    end

    def self.cpu_supported?(cpu, cc = selected_cc)
      flags = BuildFlags.march_for(cpu: cpu).map { |flag| Shellwords.escape(flag) }.join(" ")
      out = File.join(Dir.tmpdir, "tungsten-cpu-check-#{Process.pid}.o")
      ok = system("printf 'int main(void){return 0;}\\n' | #{Shellwords.escape(cc)} #{flags} -x c - -c -o #{out} > /dev/null 2>&1")
      File.delete(out) if File.exist?(out)
      ok
    end

    # zstd include flags, mirroring runtime/Makefile's ZSTD_CFLAGS exactly:
    # pkg-config if it knows libzstd, else the Homebrew include dir. Keeps the
    # doctor check honest against the real build (macOS finds zstd.h via
    # -I/opt/homebrew/include, which a bare `clang -E` would miss).
    def self.zstd_cflags
      out = `pkg-config --cflags libzstd 2>/dev/null`.strip
      out.empty? ? "-I/opt/homebrew/include" : out
    end

    RESET      = "\e[0m"
    BOLD       = "\e[1m"
    DIM        = "\e[2m"
    CYAN       = "\e[36m"
    GREEN      = "\e[32m"
    YELLOW     = "\e[33m"
    BRIGHT_RED = "\e[91m"

    def initialize(color: $stdout.tty? && !ENV["NO_COLOR"])
      @color = color
      @passed = 0
      @failed = 0
    end

    def run
      puts c("#{BOLD}#{YELLOW}✶ Tungsten Doctor#{RESET}")
      puts

      check("Ruby", RUBY_VERSION) { Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.2") }
      check("Tungsten", Tungsten::VERSION) { true }
      check("Parser") { Tungsten::Parser.parse("<< 1"); true }
      check("Interpreter") do
        old = $stdout
        $stdout = StringIO.new
        Tungsten::Interpreter.new.run("<< 1", file_path: "(doctor)")
        $stdout = old
        true
      end

      cc = self.class.selected_cc
      clang_version = `#{Shellwords.escape(cc)} --version 2>/dev/null`.lines.first&.strip
      check("clang", clang_version ? "#{clang_version} [#{cc}]" : "not found") { clang_version }
      recommend_llvm22(cc, clang_version)

      configured_cpu = BuildFlags.configured_cpu || "native"
      cpu_flags = BuildFlags.march_for(cpu: configured_cpu).join(" ")
      check("configured CPU", "#{configured_cpu} (#{cpu_flags})") do
        self.class.cpu_supported?(configured_cpu, cc)
      end

      lld_out = `ld.lld --version 2>/dev/null`.lines.first&.strip
      linker_ok = self.class.linker_ok?(cc)
      check("lld linker", lld_out || (linker_ok ? "ok" : "not found")) { linker_ok }

      check("libzstd (zstd.h)") { self.class.header?("zstd.h", self.class.zstd_cflags, cc) }

      puts
      total = @passed + @failed
      puts "#{c(DIM)}#{@passed}/#{total} checks passed#{c(RESET)}"
    end

    private

    def recommend_llvm22(cc, version)
      major = version.to_s[/version\s+(\d+)/, 1].to_i
      return if major >= 22

      candidates = ["clang-22", "/opt/homebrew/opt/llvm/bin/clang", "/usr/local/opt/llvm/bin/clang"]
      preferred = candidates.find do |candidate|
        next false unless self.class.tool?(candidate)
        candidate_version = `#{Shellwords.escape(candidate)} --version 2>/dev/null`.lines.first.to_s
        candidate_version[/version\s+(\d+)/, 1].to_i >= 22
      end
      puts "  #{c(CYAN)}→#{c(RESET)} LLVM 22+ available: #{preferred}" if preferred && preferred != cc
      puts "    configure [build] cc = #{preferred} in ~/.tungsten/config" if preferred && preferred != cc
      return if preferred

      hint = if RbConfig::CONFIG["host_os"] =~ /darwin/
               "brew install llvm lld"
             elsif File.file?("/etc/debian_version")
               "wget https://apt.llvm.org/llvm.sh && chmod +x llvm.sh && sudo ./llvm.sh 22"
             elsif File.file?("/etc/arch-release")
               "sudo pacman -S clang llvm lld"
             else
               "install LLVM/Clang 22+ and lld with your platform package manager"
             end
      puts "  #{c(CYAN)}→#{c(RESET)} LLVM 22+ recommended: #{hint}"
    end

    def check(name, version = nil)
      result = begin
        yield
      rescue => e
        @failed += 1
        puts "  #{c(BRIGHT_RED)}✗#{c(RESET)} #{name}#{version_str(version)} #{c(DIM)}(#{e.message})#{c(RESET)}"
        return
      end

      if result
        @passed += 1
        puts "  #{c(GREEN)}✓#{c(RESET)} #{name}#{version_str(version)}"
      else
        @failed += 1
        puts "  #{c(BRIGHT_RED)}✗#{c(RESET)} #{name}#{version_str(version)}"
      end
    end

    def version_str(version)
      version ? " #{c(CYAN)}#{version}#{c(RESET)}" : ""
    end

    def c(code)
      @color ? code : ""
    end
  end
end
