use flipfleet_block_composer

# Exact-gate every certificate listed in the machine-readable manifest.  The
# composer has its own construction tests; this test deliberately reloads the
# published decimal files so a stale filename, rank, dimension, or truncated
# certificate cannot pass unnoticed.

root = "benchmarks/matmul/metaflip/"
manifest = read_file(root + "block_composition_records.tsv")
if manifest == nil
  << "FAIL missing block composition manifest"
  exit(1)

lines = manifest.split("\n")
checked = 0 ## i64
i = 1 ## i64
while i < lines.size()
  if lines[i].size() > 0
    fields = lines[i].split("\t")
    if fields.size() != 8
      << "FAIL malformed manifest row " + i.to_s()
      exit(1)
    dims = fields[0].split("x")
    if dims.size() != 3
      << "FAIL malformed target " + fields[0]
      exit(1)
    rank = fields[2].to_i() ## i64
    scheme = ffbc_load_exact(root + fields[6], dims[0].to_i(), dims[1].to_i(), dims[2].to_i(), rank + 16)
    if scheme == nil || scheme.rank() != rank
      << "FAIL certificate " + fields[0] + " expected rank " + rank.to_s()
      exit(1)
    checked += 1
  i += 1

if checked != 186
  << "FAIL expected 186 block composition records, got " + checked.to_s()
  exit(1)

# Keep the publication manifest and the broader exact-scan queue in lockstep.
# A materialized queue row must have exactly one manifest row; an unmaterialized
# row must not silently acquire a certificate without its flag being updated.
queue = read_file(root + "block_composition_opportunities.tsv")
if queue == nil
  << "FAIL missing block composition opportunity queue"
  exit(1)
queue_lines = queue.split("\n")
queued = 0 ## i64
materialized = 0 ## i64
i = 1
while i < queue_lines.size()
  if queue_lines[i].size() > 0
    fields = queue_lines[i].split("\t")
    if fields.size() != 12
      << "FAIL malformed opportunity row " + i.to_s()
      exit(1)
    queued += 1
    published = manifest.include?("\n" + fields[0] + "\t")
    flag = fields[11].to_i() ## i64
    if flag == 1
      materialized += 1
      if !published
        << "FAIL materialized opportunity absent from manifest: " + fields[0]
        exit(1)
    else
      if flag != 0 || published
        << "FAIL opportunity/manifest flag mismatch: " + fields[0]
        exit(1)
  i += 1

if queued != 148 || materialized != 146
  << "FAIL opportunity counts expected 148/146, got " + queued.to_s() + "/" + materialized.to_s()
  exit(1)
<< "PASS block composition records exact=" + checked.to_s() + " queue=" + queued.to_s() + " materialized=" + materialized.to_s()
