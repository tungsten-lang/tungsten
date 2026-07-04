# frozen_string_literal: true

require "set"

module Tungsten
  class Loader
    def initialize(interpreter)
      @interpreter = interpreter
      @loaded = Set.new
      @loading = Set.new  # circular dependency detection
      @load_paths = [
        File.expand_path("../../../lib", __dir__),  # project lib/
      ]
      @ast_cache = {}
    end

    def add_load_path(path)
      @load_paths.unshift(File.expand_path(path))
    end

    def load_file(path, from: nil)
      resolved = resolve(path, from: from)
      raise Error, "cannot find '#{path}'" unless resolved

      return nil if @loaded.include?(resolved)

      if @loading.include?(resolved)
        raise Error, "circular dependency detected: #{path}"
      end

      @loading.add(resolved)

      begin
        source = File.read(resolved)
        ast = cached_parse(resolved, source)

        @loaded.add(resolved)
        @interpreter.instance_variable_set(:@current_file, resolved)
        @interpreter.evaluate(ast)
      ensure
        @loading.delete(resolved)
      end
    end

    def load_prelude
      prelude_dir = File.expand_path("../../../lib/prelude", __dir__)
      return unless File.directory?(prelude_dir)

      Dir[File.join(prelude_dir, "*.w")].sort.each do |f|
        load_file(f)
      end
    end

    private

    def resolve(path, from: nil)
      # Absolute path
      if path.start_with?("/")
        candidate = path.end_with?(".w") ? path : "#{path}.w"
        return candidate if File.exist?(candidate)
        return nil
      end

      # Relative to the requiring file
      if from
        base = File.dirname(from)
        candidate = File.expand_path(path, base)
        candidate += ".w" unless candidate.end_with?(".w")
        return candidate if File.exist?(candidate)
      end

      # Search load paths
      @load_paths.each do |dir|
        candidate = File.join(dir, path)
        candidate += ".w" unless candidate.end_with?(".w")
        return candidate if File.exist?(candidate)
      end

      nil
    end

    def cached_parse(path, source)
      mtime = File.mtime(path)
      cached = @ast_cache[path]

      if cached && cached[:mtime] == mtime
        cached[:ast]
      else
        ast = Parser.parse(source)
        @ast_cache[path] = { ast: ast, mtime: mtime }
        ast
      end
    end
  end
end
