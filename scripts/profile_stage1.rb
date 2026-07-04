#!/usr/bin/env ruby

require "tmpdir"

module Stage1Profile
  ROOT = File.expand_path("..", __dir__)
  TARGET = File.join(ROOT, "compiler/tungsten.w")
  SOURCE = File.read(TARGET)
  DEFAULT_ITERS = {
    "lex" => 75,
    "parse" => 25,
    "interpret" => 1
  }.freeze

  $LOAD_PATH.unshift(File.join(ROOT, "implementations/ruby/lib"))
  require "tungsten"

  module_function

  def run(mode, iterations: nil)
    iterations ||= Integer(ENV.fetch("TUNGSTEN_PROFILE_ITERS", DEFAULT_ITERS.fetch(mode) { 1 }))

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    iterations.times do
      case mode
      when "lex"
        lex_once
      when "parse"
        parse_once
      when "interpret"
        interpret_once
      else
        raise ArgumentError, "unknown mode: #{mode}"
      end
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    $stderr.puts "#{mode} iterations=#{iterations} elapsed=#{format('%.3f', elapsed)}s"
  end

  def lex_once
    lexer = Tungsten.new_lexer(SOURCE, file: TARGET)

    loop do
      token = lexer.next_token
      break if token.type == :EOF
    end
  end

  def parse_once
    Tungsten::Parser.parse(SOURCE)
  end

  def interpret_once
    Dir.mktmpdir("tungsten-stage1-profile-") do |dir|
      out_path = File.join(dir, "stage1-profile.wc")
      saved_argv = ARGV.dup
      ARGV.replace(["compile", "-v", TARGET, "--out", out_path])
      begin
        Tungsten::Interpreter.new.run(SOURCE, file_path: TARGET)
      ensure
        ARGV.replace(saved_argv)
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  mode = ARGV.fetch(0) do
    warn "usage: ruby scripts/profile_stage1.rb [lex|parse|interpret]"
    exit 1
  end
  Stage1Profile.run(mode)
end
