#!/usr/bin/env ruby
# frozen_string_literal: true

# Build a Hugging Face-style sharded-safetensors view over an Ollama MLX
# model. Ollama stores every tensor (and JSON sidecar) as a content-addressed
# blob. tungsten-llama's ShardedSafetensors reader expects an index plus
# ordinary shard paths, so this script creates only symlinks and a small JSON
# index; it never copies model weights.

require "fileutils"
require "json"
require "pathname"

model_ref = ARGV.fetch(0) do
  warn "usage: ruby scripts/bench/prepare_ollama_mlx.rb MODEL[:TAG] [OUT_DIR]"
  exit 2
end

model, tag = model_ref.split(":", 2)
tag ||= "latest"

ollama_root = Pathname(ENV.fetch("OLLAMA_MODELS", File.expand_path("~/.ollama/models")))
manifest_path = ollama_root.join("manifests", "registry.ollama.ai", "library", model, tag)
unless manifest_path.file?
  abort "Ollama manifest not found: #{manifest_path}\nRun: ollama pull #{model_ref}"
end

safe_ref = "#{model}-#{tag}".gsub(/[^A-Za-z0-9_.-]+/, "-")
out_dir = Pathname(ARGV[1] || File.expand_path("~/.cache/tungsten/#{safe_ref}"))
FileUtils.mkdir_p(out_dir)

manifest = JSON.parse(manifest_path.read)
layers = manifest.fetch("layers")
weight_map = {}
total_size = 0
tensor_layers = 0
json_layers = 0

def blob_path(root, digest)
  root.join("blobs", digest.sub(":", "-"))
end

def ensure_link(source, destination)
  source = source.expand_path
  if destination.symlink?
    current = destination.dirname.join(destination.readlink).expand_path
    return if current == source
    abort "refusing to replace mismatched symlink: #{destination} -> #{current}"
  end
  abort "refusing to replace existing path: #{destination}" if destination.exist?

  FileUtils.ln_s(source, destination)
end

layers.each do |layer|
  digest = layer.fetch("digest")
  source = blob_path(ollama_root, digest)
  abort "missing Ollama blob: #{source}" unless source.file?

  case layer.fetch("mediaType")
  when "application/vnd.ollama.image.tensor"
    tensor_layers += 1
    total_size += layer.fetch("size")
    short_digest = digest.delete_prefix("sha256:")[0, 16]
    shard_name = "blob-#{short_digest}.safetensors"
    destination = out_dir.join(shard_name)
    ensure_link(source, destination)

    File.open(source, "rb") do |file|
      header_length = file.read(8)&.unpack1("Q<")
      abort "invalid safetensors header: #{source}" unless header_length
      header = JSON.parse(file.read(header_length))
      header.each_key do |tensor_name|
        next if tensor_name == "__metadata__"
        if weight_map.key?(tensor_name)
          abort "duplicate tensor #{tensor_name.inspect} in #{source} and #{weight_map[tensor_name]}"
        end
        weight_map[tensor_name] = shard_name
      end
    end
  when "application/vnd.ollama.image.json"
    json_layers += 1
    name = layer.fetch("name")
    ensure_link(source, out_dir.join(name))
  end
end

index = {
  "metadata" => {
    "total_size" => total_size,
    "source_model" => model_ref,
    "source_manifest" => manifest_path.to_s
  },
  "weight_map" => weight_map.sort.to_h
}

index_path = out_dir.join("model.safetensors.index.json")
tmp_path = out_dir.join(".model.safetensors.index.json.tmp-#{Process.pid}")
tmp_path.write(JSON.pretty_generate(index) + "\n")
File.rename(tmp_path, index_path)

puts "prepared #{model_ref} at #{out_dir}"
puts "  tensor layers: #{tensor_layers}"
puts "  tensor names:  #{weight_map.length}"
puts "  JSON sidecars: #{json_layers}"
puts "  weight bytes:  #{total_size}"
puts "  index:         #{index_path}"
