# frozen_string_literal: true

module Tungsten
  class ErrorReporter
    RESET      = "\e[0m"
    BOLD       = "\e[1m"
    BRIGHT     = "\e[1m"
    DIM        = "\e[2m"
    BRIGHT_RED = "\e[91m"
    WHITE      = "\e[97m"

    def initialize(color: $stdout.tty? && !ENV["NO_COLOR"])
      @color   = color
      @cwd     = "#{Dir.pwd}/"
      @cwd_alt = ENV["PWD"] != Dir.pwd ? "#{ENV["PWD"]}/" : nil
    end

    def format(error, source: nil, file: nil)
      msg = error.is_a?(Exception) ? error.message : error.to_s
      loc = error.respond_to?(:location) ? error.location : nil

      # Prefer error-carried source/file over params
      source = error.source_code || source if error.respond_to?(:source_code)
      file   = error.file_path   || file   if error.respond_to?(:file_path)

      # Detect embedded FILE:LINE:COL: message format (from Tungsten-level compiler code)
      if (m = msg.match(/\A(.+):(\d+):(\d+): (.+)\z/m))
        candidate = m[1]
        if File.exist?(candidate)
          file   = candidate
          loc    = Location.new(candidate, m[2].to_i, m[3].to_i)
          source = (File.read(candidate) rescue nil)
          msg    = m[4]
        end
      end

      name_length = error.respond_to?(:name_length) ? error.name_length : nil
      gutter_width = loc&.row ? (loc.row + 2).to_s.length : 0

      lines = []
      lines << ""
      lines << "#{c(BRIGHT_RED)}error:#{c(RESET)} #{c(BOLD)}#{msg}#{c(RESET)}"

      if loc || file
        file_str = shorten(file || loc&.file) || "(eval)"
        row = loc&.row
        col = loc&.col
        loc_str = [file_str, row, col].compact.join(":")
        lines << ""
        lines << "#{" " * (gutter_width + 1)}#{c(DIM)}-->#{c(RESET)} #{c(DIM)}#{loc_str}#{c(RESET)}"
      end

      if source && loc&.row
        row = loc.row
        col = loc.col || 1
        source_lines = source.lines
        if row >= 1 && row <= source_lines.size
          gutter = " " * (gutter_width + 1)
          lines << "#{gutter}#{c(DIM)}|#{c(RESET)}"

          # Up to 2 context lines before
          ([row - 2, 1].max..(row - 1)).each do |ctx|
            lines << "#{c(DIM)}#{ctx.to_s.rjust(gutter_width)} | #{source_lines[ctx - 1].chomp}#{c(RESET)}"
          end

          # Error line
          lines << "#{c(DIM)}#{row.to_s.rjust(gutter_width)} |#{c(RESET)} #{source_lines[row - 1].chomp}"

          # Caret — if the next line is blank, absorb it as the caret's row number
          after_start = row + 1
          if col >= 1
            underline_length = name_length && name_length > 1 ? name_length : 1
            pointer = " " * (col - 1) + "^" + "~" * (underline_length - 1)
            next_blank = row < source_lines.size && source_lines[row].chomp.strip.empty?
            if next_blank
              lines << "#{c(DIM)}#{(row + 1).to_s.rjust(gutter_width)} |#{c(RESET)} #{c(BRIGHT_RED)}#{pointer}#{c(RESET)}"
              after_start = row + 2
            else
              lines << "#{gutter}#{c(DIM)}|#{c(RESET)} #{c(BRIGHT_RED)}#{pointer}#{c(RESET)}"
            end
          end

          # Up to 2 context lines after (stop at first blank)
          (after_start..[after_start + 1, source_lines.size].min).each do |ctx|
            content = source_lines[ctx - 1].chomp
            break if content.strip.empty?
            lines << "#{c(DIM)}#{ctx.to_s.rjust(gutter_width)} | #{content}#{c(RESET)}"
          end
        end
      end

      # Call stack trace
      call_stack = error.respond_to?(:call_stack) ? error.call_stack : nil
      if call_stack&.any?
        frames = call_stack.reverse
        max_label = frames.map { |f| f[:label].length }.max
        lines << ""
        frames.each do |frame|
          frame_loc = frame[:location]
          padded = frame[:label].ljust(max_label)
          if frame_loc
            frame_file = shorten(frame_loc.file || file)
            lines << "  #{c(DIM)}from#{c(RESET)} #{padded} #{c(DIM)}at #{frame_file}:#{frame_loc.row}:#{frame_loc.col}#{c(RESET)}"
          else
            lines << "  #{c(DIM)}from#{c(RESET)} #{padded}"
          end
        end
      end

      lines.join("\n")
    end

    private

    def c(code)
      @color ? code : ""
    end

    def shorten(path)
      return nil unless path
      path.delete_prefix(@cwd).tap { |s| return s if s != path }
      @cwd_alt ? path.delete_prefix(@cwd_alt) : path
    end

  end
end
