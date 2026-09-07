#!/usr/bin/env ruby
require "open3"
require "tmpdir"
require_relative "../tools/verify_tensor"

binary = File.expand_path(ARGV.fetch(0))
runtime = File.expand_path(ARGV.fetch(1, File.join(__dir__, "../lib/metaflip")))
Dir.mktmpdir("metaflip-fill-cli-") do |root|
  [nil, "single", "batch", "invalid"].each_with_index do |policy, index|
    directory = File.join(root, index.to_s)
    status_path = File.join(root, "#{index}.status")
    command = [binary, "--runtime-root", runtime, "--rect", "--rect-shapes", "2x5x6,4x4x5",
               "-J", "2", "--steps", "20000", "--rounds", "2", "--rect-epoch-rounds", "1",
               "--secs", "0", "--no-gpu", "--no-tui", "--quiet", "--state-dir", directory,
               "--status", status_path, "--run-tag", "fill-cli-#{index}"]
    output, status = Open3.capture2e({ "METAFLIP_RECT_FILL" => policy }, *command)
    if policy == "invalid"
      raise "invalid fill policy accepted" unless status.exitstatus == 2 && output.include?("METAFLIP_RECT_FILL")
      next
    end
    raise "fill policy #{policy.inspect} failed: #{output}" unless status.success?
    lines = File.readlines(status_path)
    fields = lines.first.split.to_h { |word| word.split("=", 2) }
    raise "unclean terminal state" unless fields["producer_state"] == "stopped" && fields["health"] == "ok"
    raise "epoch accounting changed: #{lines.first}" unless fields["total_moves"] == "80000" && fields["total_cpu_moves"] == "80000" && fields["total_gpu_moves"] == "0"
    Dir.glob(File.join(directory, "checkpoints/gf2/*/*.txt")).each do |path|
      shape = MetaflipTensorVerifier.dimensions(MetaflipTensorVerifier.infer_shape(path))
      MetaflipTensorVerifier.verify(path, *shape)
    end
  end
end
puts "PASS rectangular fill policy: defaults, overrides, exact epoch accounting, final witnesses"
