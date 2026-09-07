#!/usr/bin/env ruby
# CPU-only mode compatibility; optional bounded real-GPU accounting check.
require "open3"
require "tmpdir"
require_relative "../tools/verify_tensor"

binary = File.expand_path(ARGV.fetch(0))
runtime = File.expand_path(ARGV.fetch(1, File.join(__dir__, "../lib/metaflip")))
gpu = ARGV.include?("--gpu")
Dir.mktmpdir("metaflip-cpu-gpu-") do |root|
  modes = gpu ? [nil, "barrier", "overlap"] : [nil, "barrier", "overlap", "invalid"]
  modes.each_with_index do |mode, index|
    directory = File.join(root, index.to_s)
    status_path = File.join(root, "#{index}.status")
    command = [binary, "--runtime-root", runtime, "--tensor", "2x5x6",
               "-J", "2", "--steps", "10000", "--rounds", "2", "--secs", "15",
               "--no-tui", "--quiet", "--state-dir", directory,
               "--status", status_path, "--run-tag", "cpu-gpu-#{Process.pid}-#{index}"]
    command += gpu ? ["--gpu", "--gpu-walkers", "8192", "--gpu-steps", "40000"] : ["--no-gpu"]
    output, status = Open3.capture2e({ "METAFLIP_RECT_CPU_GPU" => mode }, *command)
    if mode == "invalid"
      raise "invalid policy accepted" unless status.exitstatus == 2 && output.include?("METAFLIP_RECT_CPU_GPU")
      next
    end
    raise "#{mode.inspect} failed: #{output}" unless status.success?
    fields = File.read(status_path).split.to_h { |word| word.split("=", 2) }
    raise "not stopped" unless fields["producer_state"] == "stopped"
    raise "wrong effective policy" unless fields["cpu_gpu_overlap"] == (mode == "barrier" ? "0" : "1")
    %w[exact_rejects gpu_failures gpu_degraded side_archive_rejects side_archive_write_failures].each do |key|
      raise "#{mode.inspect}: #{key}=#{fields[key]}" unless fields.fetch(key, "0") == "0"
    end
    followups = fields.fetch("cpu_followup_batches").to_i
    extra = fields.fetch("cpu_followup_moves").to_i
    cpu = fields.fetch("cpu_moves").to_i
    if gpu && mode != "barrier"
      raise "no CPU work overlapped GPU" unless followups.positive? && extra.positive? && cpu > extra
    else
      raise "unexpected followup work" unless followups.zero? && extra.zero?
    end
    if gpu
      raise "GPU did not execute" unless fields.fetch("gpu_moves").to_i.positive? && fields["gpu_ready"] == "1"
    else
      raise "CPU-only counts changed" unless cpu == 40000 && fields.fetch("gpu_moves") == "0"
    end
    witnesses = Dir.glob(File.join(directory, "checkpoints/gf2/*/*.txt"))
    raise "no persisted witnesses" if witnesses.empty?
    witnesses.each { |path| MetaflipTensorVerifier.verify(path, 2, 5, 6) }
    puts "PASS rectangular #{gpu ? 'CPU+GPU' : 'CPU-only'} policy=#{mode || 'default'} extra_batches=#{followups} extra_moves=#{extra} exact_witnesses=#{witnesses.size}"
  end
end
