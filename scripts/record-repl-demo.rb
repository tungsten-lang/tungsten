#!/usr/bin/env ruby
# frozen_string_literal: true

# Records a REAL Tungsten REPL session to asciinema v2 (.cast) format by
# driving the compiled REPL through a PTY with scripted keystrokes and
# capturing the actual output with actual timings. Nothing is synthesized —
# re-run after REPL changes to refresh the demo.
#
#   ruby scripts/record-repl-demo.rb [out.cast]
#
# GIF conversion (on a machine with agg): agg out.cast repl-demo.gif

require "pty"
require "timeout"
require "json"

ROOT = File.expand_path("..", __dir__)
out_path = ARGV[0] || File.join(ROOT, "sites/tungsten-lang.org/repl-demo.cast")

# [delay-before-sending, bytes] — paced like a human typing/watching.
SCRIPT = [
  [2.0, nil],                       # let the banner land
  [0.0, "<< $499.99 - 15%\r"],      # currency literal
  [1.4, "? Σ(2x⁷ + 3x²)\r"],        # capital-sigma polynomial sum, inspected
  [2.2, "\r"],                      # blank Enter → scrub mode on the Σ expr
  [1.4, "\e[A"],                    # ↑ nudge a coefficient — value recomputes
  [1.6, "\e[A"],                    # again
  [1.6, "q"],                       # leave scrub
  [1.2, "? ∫(x², 0..2)\r"],         # integral: braille plot + shaded AUC
  [2.6, "<< 2 ** 64\r"],            # bignum
  [1.2, ":help Array\r"],           # stdlib docs lookup
  [1.8, "\x04"]                     # Ctrl+D
]

events = []
t0 = nil
env = { "TUNGSTEN_VERSION" => File.read(File.join(ROOT, "VERSION")).strip }

PTY.spawn(env, File.join(ROOT, "bin/tungsten"), "repl") do |reader, writer, pid|
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  collector = Thread.new do
    loop do
      data = reader.readpartial(8192)
      # PTY reads arrive tagged BINARY; the bytes are UTF-8 (json 3.0 will
      # refuse BINARY-tagged strings).
      events << [Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0, "o",
                 data.force_encoding(Encoding::UTF_8)]
    end
  rescue EOFError, Errno::EIO
    nil
  end

  Timeout.timeout(60) do
    SCRIPT.each do |delay, bytes|
      sleep delay
      writer.write(bytes) if bytes
      # A human pause between keystroke bursts so output groups naturally.
      sleep 0.35 if bytes
    end
    Process.wait(pid)
  end
  sleep 0.3
  collector.kill
rescue Timeout::Error
  Process.kill("KILL", pid) rescue nil
  abort "recording timed out"
end

header = {
  version: 2, width: 80, height: 24,
  env: { TERM: "xterm-256color", SHELL: "/bin/zsh" },
  title: "Tungsten REPL — currency, dates, bignums, :help"
}
File.open(out_path, "w") do |f|
  f.puts JSON.generate(header)
  events.each { |t, kind, data| f.puts JSON.generate([t.round(6), kind, data]) }
end
puts "wrote #{out_path} (#{events.size} events, #{events.last&.first&.round(1)}s)"
