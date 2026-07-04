# frozen_string_literal: true

module Tungsten
  class PathValue
    include Enumerable

    attr_reader :path

    def initialize(path)
      @path = path.to_s
    end

    def parent
      PathValue.new(File.dirname(@path))
    end

    def name
      File.basename(@path)
    end

    def stem
      File.basename(@path, extension)
    end

    def extension
      File.extname(@path)
    end

    def root
      PathValue.new("/")
    end

    def absolute?
      @path.start_with?("/")
    end

    def home_relative?
      @path.start_with?("~/") || @path == "~"
    end

    def segments
      @path.split("/").reject(&:empty?)
    end

    def join(*parts)
      return self if parts.empty?

      PathValue.new(File.join(@path, *parts.map { |part| part.is_a?(PathValue) ? part.path : part.to_s }))
    end

    def /(other)
      join(other)
    end

    def exist?
      expanded = expand
      File.exist?(expanded)
    rescue StandardError
      false
    end

    def file?
      expanded = expand
      File.file?(expanded)
    rescue StandardError
      false
    end

    def directory?
      expanded = expand
      File.directory?(expanded)
    rescue StandardError
      false
    end

    def symlink?
      File.symlink?(expand)
    rescue StandardError
      false
    end

    def type
      stat = File.lstat(expand)
      case stat.ftype
      when "link" then "symlink"
      when "characterSpecial" then "character"
      when "blockSpecial" then "block"
      else stat.ftype
      end
    rescue StandardError
      nil
    end
    alias file_type type

    def entries
      Dir.children(expand)
    rescue StandardError
      nil
    end

    def children
      (entries || []).map { |entry| join(entry) }
    end
    alias ls children

    def each(&block)
      list = children
      return list.each unless block

      list.each(&block)
      self
    end

    def empty?
      children.empty?
    end

    def size
      File.size(expand)
    rescue StandardError
      nil
    end

    def mtime
      File.mtime(expand)
    rescue StandardError
      nil
    end

    def mtime_ns
      stamp = mtime
      stamp ? (stamp.to_i * 1_000_000_000) + stamp.nsec : nil
    end

    def expand
      @path.start_with?("~") ? File.expand_path(@path) : @path
    end

    def to_s
      @path
    end

    def inspect
      "Path(#{@path.inspect})"
    end

    def ==(other)
      other.is_a?(PathValue) && @path == other.path
    end
    alias eql? ==

    def hash
      @path.hash
    end
  end
end
