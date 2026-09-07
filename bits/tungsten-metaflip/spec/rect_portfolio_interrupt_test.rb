#!/usr/bin/env ruby
# Preserve already-published work through cancellation of an active segment.
require "open3"
require "tmpdir"
require_relative "../tools/verify_tensor"

binary = File.expand_path(ARGV.fetch(0))
runtime = File.expand_path(ARGV.fetch(1, File.join(__dir__, "../lib/metaflip")))
gpu = ARGV.include?("--gpu")

def owned_pids(directory, tag)
  output, = Open3.capture2("/bin/ps", "-axo", "pid=,command=")
  output.lines.filter_map do |line|
    pid, command = line.strip.split(/\s+/, 2)
    pid.to_i if pid.to_i != Process.pid && (command.to_s.include?(directory) || command.to_s.include?(tag))
  end
end

Dir.mktmpdir("metaflip-interrupt-") do |root|
  status_path = File.join(root, "status.txt")
  tag = "interrupt-#{Process.pid}"
  command = [binary, "--runtime-root", runtime, "--rect", "--rect-shapes", "2x5x6,3x4x6",
             "-J", "2", "--steps", "5000000", "--rect-epoch-rounds", "256",
             "--secs", "0", "--no-tui", "--quiet", "--state-dir", root,
             "--status", status_path, "--run-tag", tag]
  command += gpu ? ["--gpu", "--gpu-walkers", "8192", "--gpu-steps", "40000"] : ["--no-gpu"]
  last = nil
  output = +""
  Open3.popen2e({ "METAFLIP_RECT_CPU_GPU" => "overlap" }, *command) do |input, stream, waiter|
    input.close
    reader = Thread.new { loop { output << stream.readpartial(65536) } rescue EOFError }
    begin
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 45
      seen_sequence = nil
      loop do
        raise "child exited early: #{output}" unless waiter.alive?
        if File.file?(status_path)
          fields = File.read(status_path).lines.first.to_s.split.to_h { |word| word.split("=", 2) }
          if fields.fetch("total_cpu_moves", "0").to_i.positive? && (!gpu || fields.fetch("total_gpu_moves", "0").to_i.positive?)
            last = fields
            break if seen_sequence && seen_sequence != fields["sequence"]
            seen_sequence = fields["sequence"]
          end
        end
        raise "no published work: #{output}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        sleep 0.05
      end
      Process.kill("INT", waiter.pid)
      raise "interrupt did not stop portfolio" unless waiter.join(15)
      raise "portfolio failed: #{output}" unless waiter.value.success?
    ensure
      if waiter.alive?
        owned_pids(root, tag).reverse_each { |pid| Process.kill("TERM", pid) rescue Errno::ESRCH }
        waiter.join(3)
        owned_pids(root, tag).reverse_each { |pid| Process.kill("KILL", pid) rescue Errno::ESRCH } if waiter.alive?
        waiter.join(3)
      end
      reader.join(3)
    end
  end
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
  loop do
    left = owned_pids(root, tag)
    break if left.empty?
    if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      left.each { |pid| Process.kill("TERM", pid) rescue Errno::ESRCH }
      raise "owned descendants survived: #{left.inspect}"
    end
    sleep 0.05
  end
  lines = File.readlines(status_path)
  final = lines.first.split.to_h { |word| word.split("=", 2) }
  raise "unclean terminal state" unless final["producer_state"] == "stopped" && final["health"] == "ok"
  %w[total_moves total_cpu_moves total_gpu_moves total_mitm_attempts total_mitm_pairs].each do |key|
    raise "#{key} regressed #{last[key]} -> #{final[key]}" unless final.fetch(key).to_i >= last.fetch(key).to_i
  end
  shapes = lines.drop(1).map { |line| line.split.to_h { |word| word.split("=", 2) } }
  %w[moves cpu_moves gpu_moves].each do |key|
    raise "shape sum mismatch #{key}" unless shapes.sum { |shape| shape.fetch(key).to_i } == final.fetch("total_#{key}").to_i
  end
  witnesses = Dir.glob(File.join(root, "checkpoints/gf2/*/*.txt"))
  raise "no checkpoints" if witnesses.empty?
  witnesses.each { |path| MetaflipTensorVerifier.verify(path, *MetaflipTensorVerifier.dimensions(MetaflipTensorVerifier.infer_shape(path))) }
  puts "PASS portfolio interrupt #{gpu ? 'CPU+GPU' : 'CPU-only'}: monotone counters, exact #{witnesses.size} witnesses, no surviving children"
end
