#!/usr/bin/env ruby
# frozen_string_literal: true

ROOT = File.expand_path("..", __dir__)

def source(path)
  File.read(File.join(ROOT, path))
end

launcher = source("compiler/tungsten.w")
driver_paths = ["compiler/tungsten_driver.w"] +
               Dir.glob(File.join(ROOT, "compiler/lib/driver/*.w")).sort.map do |path|
                 path.delete_prefix(ROOT + "/")
               end
driver = driver_paths.map { |path| source(path) }.join("\n")
repl = source("compiler/repl.w")
metal = source("compiler/tungsten_metal.w")
gpu_base = source("compiler/lib/compiler_gpu_emitter.w")
gpu_metal = source("compiler/lib/compiler_gpu_emitter_metal.w")
runtime = source("runtime/runtime.c")

forbidden = %w[
  use\ lib/interpreter
  use\ lib/repl
  use\ lib/metal_emitter
]
forbidden.each do |line|
  raise "default compiler image imports optional feature: #{line}" if driver.lines.any? { |candidate| candidate.strip == line }
end

profile_marker = 'ccall("w_compiler_image_lean_profile")'
raise "default compiler image lost lean-runtime marker" unless launcher.include?(profile_marker)
raise "Metal compiler image lost lean-runtime marker" unless metal.include?(profile_marker)
raise "REPL compiler image must retain the universal runtime" if repl.include?(profile_marker)

unless driver.include?('@w_compiler_image_lean_profile(') &&
       driver.include?('-DTUNGSTEN_RUNTIME_COMPILER_IMAGE=1') &&
       runtime.include?("#ifndef TUNGSTEN_RUNTIME_COMPILER_IMAGE")
  raise "compiler-image runtime profile contract is incomplete"
end

{
  "default" => [launcher, %w[tungsten_driver]],
  "REPL" => [repl, %w[lib/interpreter lib/repl lib/compiler_gpu_emitter_metal tungsten_driver]],
  "Metal" => [metal, %w[lib/compiler_gpu_emitter_metal tungsten_driver]],
}.each do |name, (text, imports)|
  imports.each do |import|
    raise "#{name} compiler image lost `use #{import}`" unless text.lines.any? { |line| line.strip == "use #{import}" }
  end
  # LOCK_THE_DOORS! already implies STOP_THE_PRESS!; PROTECT_THE_CORE! is the
  # independent provenance promise needed for the stable Core ABI/cache.
  %w[PROTECT_THE_CORE! LOCK_THE_DOORS!].each do |contract|
    raise "#{name} compiler image lost Tungsten.#{contract}" unless text.include?("Tungsten.#{contract}")
  end
  if text.include?("Tungsten.STOP_THE_PRESS!")
    raise "#{name} compiler image redundantly declares STOP_THE_PRESS! after LOCK_THE_DOORS!"
  end
end

unless driver.include?('delegate_compiler_image("repl")') &&
       driver.include?('delegate_compiler_image("metal")') &&
       driver.include?('TUNGSTEN_COMPILER_IMAGE')
  raise "compiler driver lost transparent optional-image delegation"
end

unless gpu_base.include?("+ CompilerGPUEmitter") &&
       gpu_base.include?("ast_get(node, :body)") &&
       gpu_base.include?("ast_get(node, :expressions)") &&
       gpu_metal.include?("+ MetalCompilerGPUEmitter < CompilerGPUEmitter")
  raise "GPU compiler image lost its narrow base/implementation boundary"
end

puts "compiler image boundaries: ok"
