# Sharded safetensors reader. Reads model.safetensors.index.json (HF-standard
# shard manifest), opens each shard's Safetensors, and routes per-tensor
# lookups to the right shard.
#
# Used for models too big for a single safetensors file:
#   - mlx-community/Qwen3.6-35B-A3B-nvfp4 (4 shards, 20 GB)
#   - any HF model with safetensors.index.json
#
# Single-file models keep using `Safetensors.new(path)` directly.

in Tungsten:Llama

use core/json
use tungsten-llama/safetensors

+ ShardedSafetensors
  rw :index_dir       # directory containing the shards + index json
  rw :shards          # hash of {shard_filename: Safetensors}
  rw :weight_map      # hash of {tensor_name: shard_filename}

  -> new(index_path)
    @index_dir = index_path.split("/")[0...-1].join("/")
    raw = read_file(index_path)
    parsed = JSON.parse(raw)
    @weight_map = parsed["weight_map"]
    @shards = {}

  # Open and cache the Safetensors for the given shard filename.
  -> open_shard(filename)
    if @shards[filename] == nil
      shard_path = @index_dir + "/" + filename
      @shards[filename] = Safetensors.new(shard_path)
    @shards[filename]

  -> close
    keys = @shards.keys()
    i = 0
    while i < keys.size()
      @shards[keys[i]].close
      i = i + 1

  -> count
    @weight_map.size()

  # Map a requested tensor name to the one actually stored. The classic
  # mlx-community nvfp4 export names quant scales `<x>.scales`; ollama's MLX
  # repack (and newer mlx_lm) names them `<x>.weight.scale`. Only rewrites on
  # an exact miss with a matching alternate, so classic exports are untouched.
  -> resolve_name(name)
    if @weight_map[name] != nil
      return name
    if name.ends_with?(".scales")
      # NB: use slice(start, LENGTH) — the range-slice form `name[0...n]`
      # segfaults in the compiled front-end. ".scales" is 7 chars.
      alt = name.slice(0, name.size() - 7) + ".weight.scale"
      if @weight_map[alt] != nil
        return alt
    name

  -> has?(name)
    @weight_map[resolve_name(name)] != nil

  -> tensor(name)
    real = resolve_name(name)
    shard_name = @weight_map[real]
    if shard_name == nil
      raise "ShardedSafetensors: tensor `" + name + "` not in weight_map"
    s = open_shard(shard_name)
    s.tensor(real)

  # Zero-copy upload to a Metal buffer (delegates to the shard's mmap).
  -> upload_bytes(name, dst_buf)
    real = resolve_name(name)
    shard_name = @weight_map[real]
    if shard_name == nil
      raise "ShardedSafetensors: tensor `" + name + "` not in weight_map"
    s = open_shard(shard_name)
    s.upload_bytes(real, dst_buf)

  # Underlying mmap for the shard holding `name` — for callers that want
  # mmap.view_at(...) → BigArray → metal_buffer_for zero-copy wraps.
  -> mmap_for(name)
    shard_name = @weight_map[resolve_name(name)]
    if shard_name == nil
      raise "ShardedSafetensors: tensor `" + name + "` not in weight_map"
    s = open_shard(shard_name)
    s.mmap

  -> byte_offset(name)
    tensor(name)[:byte_offset]
