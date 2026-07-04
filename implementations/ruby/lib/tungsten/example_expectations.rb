# frozen_string_literal: true

require "open3"
require "ostruct"
require "timeout"

module Tungsten
  module ExampleExpectations
    ParseError = Class.new(StandardError)
    DEFAULT_TIMEOUT = 5

    Definition = Struct.new(
      :stdin,
      :stdout,
      :stderr,
      :exit_status,
      :skip_reason,
      :timeout_seconds,
      keyword_init: true
    ) do
      def skip?
        !skip_reason.nil?
      end
    end

    module_function

    def parse(source)
      # Early out: if the source contains "## expect skip" anywhere, skip without full parsing
      if source.match?(/^## expect skip\b/)
        reason = source[/^## expect skip\s*(.*)/, 1].to_s.strip
        reason = "skipped" if reason.empty?
        return Definition.new(skip_reason: reason)
      end

      trailer_lines = extract_trailer_lines(source)
      raise ParseError, "missing ## expect trailer" if trailer_lines.empty?

      definition = Definition.new(
        stdin: "",
        stdout: "",
        stderr: "",
        exit_status: 0,
        timeout_seconds: DEFAULT_TIMEOUT
      )

      current_block = nil
      seen_expect = false

      trailer_lines.each do |line|
        if (directive = parse_directive(line))
          seen_expect = true
          current_block = nil

          case directive[:name]
          when "stdout", "stderr", "stdin"
            current_block = directive[:name]
            definition[current_block] = +""
          when "exit"
            definition.exit_status = Integer(directive[:value] || "0", 10)
          when "timeout"
            definition.timeout_seconds = Integer(directive[:value] || DEFAULT_TIMEOUT.to_s, 10)
          when "skip"
            definition.skip_reason = directive[:value].to_s.strip
            definition.skip_reason = "skipped" if definition.skip_reason.empty?
          else
            raise ParseError, "unknown ## expect directive: #{directive[:name]}"
          end
        elsif line.start_with?("##")
          next unless current_block

          definition[current_block] << extract_block_line(line)
          definition[current_block] << "\n"
        elsif !line.strip.empty?
          raise ParseError, "unexpected non-comment line inside ## expect trailer: #{line.inspect}"
        end
      end

      raise ParseError, "missing ## expect directive" unless seen_expect

      definition
    rescue ArgumentError => e
      raise ParseError, e.message
    end

    def load_file(path)
      parse(File.read(path))
    end

    def extract_trailer_lines(source)
      lines = source.lines
      index = lines.length - 1

      index -= 1 while index >= 0 && lines[index].strip.empty?
      return [] if index.negative?

      trailer = []
      while index >= 0
        line = lines[index]
        break unless line.start_with?("##") || line.strip.empty?

        trailer.unshift(line)
        index -= 1
      end

      expect_index = trailer.index { |line| line.match?(/\A## expect\b/) }
      return [] unless expect_index

      trailer[expect_index..]
    end

    def parse_directive(line)
      match = line.match(/\A## expect (?<name>\w+)(?: (?<value>.*))?\n?\z/)
      return unless match

      { name: match[:name], value: match[:value] }
    end

    def extract_block_line(line)
      body = line.delete_prefix("##")
      body = body.delete_prefix(" ")
      body.delete_suffix("\n")
    end

    def run_file(path, cli_path:, repo_root:)
      expectation = load_file(path)
      return [expectation, nil, nil, nil] if expectation.skip?

      # Use in-process interpreter when possible (no stdin/stderr/non-zero exit)
      if expectation.stdin.to_s.empty? && expectation.stderr.to_s.empty? && expectation.exit_status == 0
        stdout = run_in_process(path, repo_root:, timeout_seconds: expectation.timeout_seconds)
        return [expectation, stdout, "", OpenStruct.new(exitstatus: 0)]
      end

      stdout, stderr, status = capture3(
        "ruby", cli_path, File.expand_path(path),
        chdir: repo_root,
        stdin_data: expectation.stdin,
        timeout_seconds: expectation.timeout_seconds
      )

      [expectation, stdout, stderr, status]
    end

    def run_in_process(path, repo_root:, timeout_seconds:)
      source = File.read(path)
      captured = StringIO.new

      Timeout.timeout(timeout_seconds) do
        old_stdout = $stdout
        begin
          $stdout = captured
          interpreter = Tungsten::Interpreter.new
          interpreter.run(source, file_path: path)
        ensure
          $stdout = old_stdout
        end
      end

      captured.string
    end

    def output_mismatch(expected, actual)
      expected_lines = normalized_output_lines(expected)
      actual_lines = normalized_output_lines(actual)

      return if lines_match?(expected_lines, actual_lines)

      "expected output to match embedded expectation\n" \
        "expected: #{expected_lines.inspect}\n" \
        "actual:   #{actual_lines.inspect}"
    end

    def capture3(*cmd, chdir:, stdin_data:, timeout_seconds:)
      stdout = +""
      stderr = +""
      status = nil

      Open3.popen3(*cmd, chdir:) do |stdin, out, err, wait_thr|
        stdin.write(stdin_data.to_s)
        stdin.close

        stdout_thread = Thread.new { out.read }
        stderr_thread = Thread.new { err.read }

        unless wait_thr.join(timeout_seconds)
          terminate_process(wait_thr.pid)
          raise Timeout::Error, "timed out after #{timeout_seconds}s"
        end

        stdout = stdout_thread.value
        stderr = stderr_thread.value
        status = wait_thr.value
      end

      [stdout, stderr, status]
    end

    def terminate_process(pid)
      Process.kill("TERM", pid)
      sleep 0.1
      Process.kill("KILL", pid)
    rescue Errno::ESRCH
      nil
    end

    def normalized_output_lines(text)
      lines = text.to_s.split("\n", -1)
      lines.pop if text.to_s.end_with?("\n")

      index = 0
      normalized = []

      while index < lines.length
        line = lines[index]

        if wildcard_line?(line)
          normalized.pop if normalized.last == ""
          normalized << line
          index += 1
          index += 1 while index < lines.length && lines[index] == ""
          next
        end

        normalized << line
        index += 1
      end

      normalized
    end

    def lines_match?(expected_lines, actual_lines)
      match_from_indices(expected_lines, actual_lines, 0, 0)
    end

    def match_from_indices(expected_lines, actual_lines, expected_index, actual_index)
      while expected_index < expected_lines.length
        expected_line = expected_lines[expected_index]

        if wildcard_line?(expected_line)
          return true if expected_index == expected_lines.length - 1

          next_expected_index = expected_index + 1

          while actual_index <= actual_lines.length
            return true if match_from_indices(expected_lines, actual_lines, next_expected_index, actual_index)

            actual_index += 1
          end

          return false
        end

        return false if actual_index >= actual_lines.length
        return false unless expected_line == actual_lines[actual_index]

        expected_index += 1
        actual_index += 1
      end

      actual_index == actual_lines.length
    end

    def wildcard_line?(line)
      line.strip == "..."
    end
  end
end
