# One bounded native cleanup attempt per distinct verified composition.
# The original recipe/result is immutable. This separate, versioned manifest
# records a full-check-admitted improvement or an explicit work/verify limit.
use matrix_cleanup
use ../fleet/refinement_artifacts
use utility

-> ffwc_index_kind(root, identity, blob, rank, n, m, p, source, kind) (String String String i64 i64 i64 i64 String String) i64
  archive = root + "/composition/"
  path = archive + "objects/" + identity + ".tensor"
  old = File.read_prefix(path, 12632129)
  if old != nil && old != blob
    return 0
  if old == nil && ffrf_atomic(path, blob, "wide-cleanup") != 1
    return 0
  shape = n.to_s() + "x" + m.to_s() + "x" + p.to_s()
  if !File.mkdir_p(archive + "by-shape/" + shape)
    return 0
  marker = archive + "by-shape/" + shape + "/" + identity
  if !File.exists?(marker) && ffrf_atomic(marker, kind + " " + source + "\n", "wide-cleanup") != 1
    return 0
  previous = File.read_prefix(archive + "best/" + shape, 100)
  best = 16385 ## i64
  if previous != nil
    fields = previous.strip().split(" ")
    if fields.size() == 2 && ffrf_hash_valid(fields[1]) == 1
      best = ffpk_decimal(fields[0])
  if rank < best && ffrf_atomic(archive + "best/" + shape, rank.to_s() + " " + identity + "\n", "wide-cleanup") != 1
    return 0
  ffcu_record(root, identity, rank, n, m, p)

-> ffwc_index(root, identity, blob, rank, n, m, p, source) (String String String i64 i64 i64 i64 String) i64
  ffwc_index_kind(root, identity, blob, rank, n, m, p, source, "MFW_CLEAN1")

# Both source and cached output still cross full tensor gates. The cache is a
# dedup optimization, never authority for rank or validity. Metadata describes
# one bounded run, not a proof of matrix/tensor-rank optimality.
-> ffwc_cached(root, raw, source, before, n, m, p, out, parity) (String String String i64 i64 i64 i64 i64[] i64[]) i64
  fields = raw.strip().split(" ")
  if fields.size() != 12 || fields[0] != "MFW_CLEAN1" || fields[1] != source || ffrf_hash_valid(fields[2]) != 1
    return 0
  shape = n.to_s() + "x" + m.to_s() + "x" + p.to_s()
  proposed = ffpk_decimal(fields[5]) ## i64
  after = ffpk_decimal(fields[6]) ## i64
  status = ffpk_decimal(fields[7]) ## i64
  used = ffpk_decimal(fields[8]) ## i64
  axes = ffpk_decimal(fields[9]) ## i64
  groups = ffpk_decimal(fields[10]) ## i64
  saved = ffpk_decimal(fields[11]) ## i64
  if fields[3] != shape || fields[4] != before.to_s() || proposed < 1 || proposed > before || after < 1 || after > before || status < 1 || status > 3 || used < 0 || used > 20000000 || axes < 0 || axes > 3*(before+1) || groups < 0 || groups > before || saved < 0 || saved > before-proposed
    return 0
  if (status < 3 && after != proposed) || (status == 3 && (after != before || fields[2] != source))
    return 0
  if status == 1 && (axes < 3 || axes%3 != 0)
    return 0
  if (after == before && fields[2] != source) || (after < before && fields[2] == source)
    return 0
  canonical = "MFW_CLEAN1 " + source + " " + fields[2] + " " + shape + " " + before.to_s() + " " + proposed.to_s() + " " + after.to_s() + " " + status.to_s() + " " + used.to_s() + " " + axes.to_s() + " " + groups.to_s() + " " + saved.to_s() + "\n"
  if raw != canonical
    return 0
  if fields[2] != source
    blob = File.read_prefix(root + "/composition/objects/" + fields[2] + ".tensor", 12632129)
    if blob == nil || Crypto:SHA256.hexdigest(blob) != fields[2]
      return 0
    meta = i64[4]
    parsed = ffpk_parse(blob, out, 3*32*16384, meta, 4) ## i64
    if parsed != after || meta[0] != n || meta[1] != m || meta[2] != p
      return 0
    checked = ffpk_exact(out, 3*32*16384, after, n, m, p, parity, 32768, 20000000) ## i64
    if checked == 0-1
      return 0-2
    if checked != 1
      return 0
    if File.exists?(root + "/stop")
      return 0-1
    if ffwc_index(root, fields[2], blob, after, n, m, p, source) != 1
      return 0
  ffrf_atomic(root + "/composition/cleanup/last", status.to_s() + " " + (before-after).to_s() + "\n", "wide-cleanup")

-> ffwc_refine(root, source, before, n, m, p, out, parity) (String String i64 i64 i64 i64 i64[] i64[]) i64
  if File.exists?(root + "/stop")
    return 0-1
  queue = root + "/composition/cleanup/"
  if !File.mkdir_p(queue + "results")
    return 0
  existing = File.read_prefix(queue + "results/" + source, 320)
  if existing != nil
    return ffwc_cached(root, existing, source, before, n, m, p, out, parity)
  stride = ffpk_stride(n, m, p) ## i64
  words = ffwm_scratch_words(before, stride) ## i64
  if words == 0
    return 0
  scratch = i64[words]
  stats = i64[6]
  proposed = ffwm_reduce(out, 3*32*16384, before, n, m, p, scratch, words, 20000000, stats, 6) ## i64
  if proposed < 1 || proposed > before
    return 0
  status = 1 ## i64
  if stats[2] != 0
    status = 2
  after = proposed ## i64
  identity = source
  if proposed < before
    checked = ffpk_exact(out, 3*32*16384, proposed, n, m, p, parity, 32768, 20000000) ## i64
    if checked == 0-1
      # Retain the verified original, not this unverified candidate. The
      # explicit status prevents a bounded attempt being called a fixed point.
      status = 3
      after = before
    elsif checked != 1
      return 0
    else
      if File.exists?(root + "/stop")
        return 0-1
      blob = ffpk_blob(out, proposed, n, m, p)
      identity = Crypto:SHA256.hexdigest(blob)
      if ffwc_index(root, identity, blob, proposed, n, m, p, source) != 1
        return 0
  if File.exists?(root + "/stop")
    return 0-1
  shape = n.to_s() + "x" + m.to_s() + "x" + p.to_s()
  record = "MFW_CLEAN1 " + source + " " + identity + " " + shape + " " + before.to_s() + " " + proposed.to_s() + " " + after.to_s() + " " + status.to_s() + " " + stats[0].to_s() + " " + stats[3].to_s() + " " + stats[4].to_s() + " " + stats[5].to_s() + "\n"
  if ffrf_atomic(queue + "results/" + source, record, "wide-cleanup") != 1 || ffrf_atomic(queue + "last", status.to_s() + " " + (before-after).to_s() + "\n", "wide-cleanup") != 1
    return 0
  << "METAFLIP_WIDE_CLEAN source=" + source + " before=" + before.to_s() + " after=" + after.to_s() + " status=" + status.to_s() + " work=" + stats[0].to_s()
  1
