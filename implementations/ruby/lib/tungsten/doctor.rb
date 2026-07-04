# frozen_string_literal: true

require "stringio"
require "rbconfig"
require "tmpdir"

module Tungsten
  class Doctor
    # Build-time preflight. Returns [[name, install_hint], ...] for each
    # REQUIRED external tool that `bin/tungsten build` shells out to but that is
    # missing, so the caller can print friendly guidance and abort before a raw
    # make/clang error dump partway through the bootstrap.
    #
    # Only genuinely-required, PATH-resolved tools are hard-checked here (clang,
    # make). Tools with special resolution — e.g. `llc` from keg-only Homebrew
    # LLVM, which lives off PATH at /opt/homebrew/opt/llvm/bin — are left to the
    # full `doctor` so this gate never false-aborts a working toolchain.
    def self.build_preflight
      linux = RbConfig::CONFIG["host_os"] =~ /linux/
      missing = []
      unless tool?("clang")
        missing << ["clang", linux ? "sudo apt-get install clang" : "xcode-select --install  (or: brew install llvm)"]
      end
      unless tool?("make")
        missing << ["make", linux ? "sudo apt-get install build-essential" : "xcode-select --install"]
      end
      # The compiler links with `clang -fuse-ld=lld`; a missing lld makes the
      # linker step fail (and the C VM can exit 0 having written no output, so
      # the failure surfaces later as a confusing "no such file" cp error).
      # On Ubuntu lld is a separate package; on macOS it ships with Homebrew
      # LLVM / the Xcode toolchain. Functional test, not a PATH lookup.
      unless linker_ok?
        missing << ["lld (clang -fuse-ld=lld)", linux ? "sudo apt-get install lld" : "brew install llvm"]
      end
      # The runtime's slab_zstd.c includes <zstd.h>; without the dev headers the
      # very first runtime C file fails to compile.
      unless header?("zstd.h", zstd_cflags)
        missing << ["libzstd headers (zstd.h)", linux ? "sudo apt-get install libzstd-dev" : "brew install zstd"]
      end
      missing
    end

    def self.tool?(name)
      system("command -v #{name} > /dev/null 2>&1")
    end

    # True when clang can actually link a program with lld (what the build
    # does). A functional check rather than `command -v ld.lld` so it never
    # false-fails where lld resolves off-PATH (keg-only Homebrew LLVM on macOS).
    def self.linker_ok?
      out = File.join(Dir.tmpdir, "tungsten-lld-check-#{Process.pid}")
      ok = system("printf 'int main(void){return 0;}' | clang -fuse-ld=lld -x c - -o #{out} > /dev/null 2>&1")
      File.delete(out) if File.exist?(out)
      ok
    end

    # True when a required C header is includable (preprocess test). Extra
    # cflags mirror however the build itself locates the header, so this never
    # false-fails where the header lives off the default include path.
    def self.header?(name, cflags = "")
      system("printf '#include <#{name}>\\n' | clang #{cflags} -E -x c - > /dev/null 2>&1")
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

      clang_version = `clang --version 2>/dev/null`.lines.first&.strip
      check("clang", clang_version || "not found") { clang_version }

      llc_out = `llc --version 2>/dev/null`.lines.grep(/LLVM version/).first&.strip
      check("LLVM (llc)", llc_out || "not found") { llc_out }

      lld_out = `ld.lld --version 2>/dev/null`.lines.first&.strip
      linker_ok = self.class.linker_ok?
      check("lld linker", lld_out || (linker_ok ? "ok" : "not found")) { linker_ok }

      check("libzstd (zstd.h)") { self.class.header?("zstd.h", self.class.zstd_cflags) }

      puts
      total = @passed + @failed
      puts "#{c(DIM)}#{@passed}/#{total} checks passed#{c(RESET)}"
    end

    private

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
