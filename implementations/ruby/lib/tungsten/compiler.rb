# frozen_string_literal: true

require "digest"
require "fileutils"

module Tungsten
  class Compiler
    CACHE_DIR = File.join(Dir.home, ".tungsten", "cache")
    STAGES_DIR = File.expand_path("../../../../compiler", __dir__)

    def initialize
      @interpreter = Interpreter.new
    end

    def compile(source_file, output: nil)
      output ||= File.basename(source_file, ".w")

      if cached_compiler
        # Use cached native compiler (fast path)
        system_safe(cached_compiler, "compile", source_file, "-o", output)
      else
        # Interpret the self-hosted compiler (slow path)
        compiler_source = File.join(STAGES_DIR, "tungsten.w")
        unless File.exist?(compiler_source)
          raise Error, "self-hosted compiler not found at #{compiler_source}"
        end

        @interpreter.run(
          File.read(compiler_source),
          file_path: compiler_source
        )
      end
    end

    private

    def cached_compiler
      return nil unless File.directory?(STAGES_DIR)

      sha = compiler_sha
      path = File.join(CACHE_DIR, "compiler-#{sha}")
      File.executable?(path) ? path : nil
    end

    def compiler_sha
      files = Dir[File.join(STAGES_DIR, "lib", "**", "*.w")].sort
      content = files.map { |f| File.read(f) }.join
      ::Digest::SHA256.hexdigest(content)[0, 16]
    end

    def system_safe(*args)
      # Use multi-arg system() to avoid shell injection
      success = Kernel.system(*args)
      raise Error, "compilation failed: #{args.join(" ")}" unless success
    end
  end
end
