#!/usr/bin/env ruby
# Bounded CPU-only native integration: drain on interrupt and raw-TUI resets.
require "fileutils"
require "open3"
require "pty"
require "tmpdir"

binary = File.expand_path(ARGV.fetch(0))
root = File.expand_path(ARGV.fetch(1))
verifier = File.expand_path("../tools/bench_cpu_epochs.rb", __dir__)

def wait_until(seconds)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
  until yield
    raise "timed out waiting for fleet" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    sleep 0.05
  end
end

Dir.mktmpdir("metaflip-async-test-") do |directory|
  %w[interrupt reset].each do |mode|
    state_dir = File.join(directory, mode)
    status_path = File.join(state_dir, "runs/gf2/5x5x5", mode, "status.txt")
    command = [binary, "--tensor", "5x5", "-J", "8", "--steps", "500000", "--secs", "0",
               "--no-gpu", "--runtime-root", root, "--state-dir", state_dir, "--run-tag", mode]
    command << (mode == "reset" ? "--tui" : "--no-tui")
    environment = { "METAFLIP_CPU_SCHEDULER" => "async", "METAFLIP_PHASE_TIMING" => "1",
                    "METAFLIP_CPU_EPOCH_MS" => "100", "METAFLIP_HOME" => state_dir }
    log = +""
    PTY.spawn(environment, *command) do |reader, writer, pid|
      status = nil
      collector = Thread.new do
        loop { log << reader.readpartial(65_536) }
      rescue EOFError, Errno::EIO
        nil
      end
      begin
        wait_until(20) { File.file?(status_path) && File.read(status_path).include?("producer_state=LIVE") }
        if mode == "reset"
          writer.write(" ")
          wait_until(10) { log.include?("manual-naive") || log.include?("fresh naive") || log.include?("reset to naive") }
          # Resume epochs from the new generation before requesting shutdown.
          sleep 0.5
          writer.write("q")
        else
          sleep 0.5
          Process.kill("INT", pid)
        end
        wait_until(20) do
          result = Process.waitpid2(pid, Process::WNOHANG)
          status = result[1] if result
          !result.nil?
        end
      ensure
        unless status
          Process.kill("KILL", pid) rescue Errno::ESRCH
          Process.waitpid(pid) rescue Errno::ECHILD
        end
        collector.join(2)
      end
      raise "#{mode}: native failure #{status}: #{log[-4000..]}" unless status&.success?
    end
    raise "#{mode}: did not finish persistence" unless File.read(status_path).include?("producer_state=DONE")
    raise "#{mode}: exact rejection" if log.match?(/exact[-_]rejects=[1-9]|exact_bad=[1-9]/)
    phases = log.lines.grep(/METAFLIP_PHASE /)
    raise "#{mode}: no asynchronous progress" unless phases.any? { |line| line.include?("async=1") && line.match?(/inflight=[1-9]/) }
    raise "#{mode}: last CPU endpoints not drained" unless phases.last&.include?("inflight=0")
    output, status = Open3.capture2e("ruby", verifier, "--verify", File.join(state_dir, "checkpoints/gf2/5x5x5/best.txt"))
    raise "#{mode}: independent exact verifier failed: #{output}" unless status.success?
    puts "PASS async fleet #{mode}: bounded shutdown, final CPU intake, exact persisted GF(2) checkpoint"
  end
end
