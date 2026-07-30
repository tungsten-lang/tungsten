# WRATB packed-certificate writer.
#
# `wrat_pack_file` validates and scans the source twice: once to determine the
# exact output size, then once to fill a compact ByteArray.  That keeps memory
# bounded by the packed result and the largest individual proof line.  Normal
# verification is one-pass and does not construct this output buffer.

use core/file
use stream

-> wrat_zigzag(value)
  value >= 0 ? 2 * value : 0 - 2 * value - 1

-> wrat_uvarint_size(value)
  size = 1
  while value >= 128
    value = value >> 7
    size += 1
  size

-> wrat_put_uvarint(bytes, pos, value)
  while value >= 128
    bytes[pos] = (value & 127) | 128
    pos += 1
    value = value >> 7
  bytes[pos] = value
  pos + 1

-> wrat_reference_bytes(ids, origin)
  total = 1 # zero terminator
  previous = origin
  ids.each -> (cid)
    total += wrat_uvarint_size(wrat_zigzag(previous - cid) + 1)
    previous = cid
  total

-> wrat_write_references(bytes, pos, ids, origin)
  previous = origin
  ids.each -> (cid)
    pos = wrat_put_uvarint(bytes, pos, wrat_zigzag(previous - cid) + 1)
    previous = cid
  bytes[pos] = 0
  pos + 1

-> wrat_packed_measure(scanner)
  total = WRATB_MAGIC_SIZE + 1 # magic plus end marker
  first_id = 0
  next_id = 0
  additions = 0
  deletions = 0

  while scanner.advance
    if scanner.kind == "a"
      if first_id == 0
        first_id = scanner.id
        next_id = first_id
      raise "packed WRAT requires sequential addition ids" unless scanner.id == next_id
      next_id += 1
      additions += 1
      total += 1 # record tag
      scanner.lits.each -> (lit)
        total += wrat_uvarint_size(wrat_zigzag(lit))
      total += 1 # literal terminator
      total += wrat_reference_bytes(scanner.hints, scanner.id)
    else
      raise "packed WRAT cannot begin with a deletion" if first_id == 0
      deletions += 1
      total += 1 # record tag
      total += wrat_reference_bytes(scanner.hints, next_id - 1)

  raise "proof contains no additions" if first_id == 0
  total += wrat_uvarint_size(first_id)
  {
    "bytes": total,
    "first_id": first_id,
    "additions": additions,
    "deletions": deletions,
  }

-> wrat_pack_into(scanner, info)
  out = u8[info["bytes"]]
  magic = [87, 82, 65, 84, 66, 1]
  pos = 0
  magic.each -> (byte)
    out[pos] = byte
    pos += 1
  pos = wrat_put_uvarint(out, pos, info["first_id"])

  next_id = info["first_id"]
  while scanner.advance
    if scanner.kind == "a"
      raise "addition ids changed between packing passes" unless scanner.id == next_id
      next_id += 1
      out[pos] = 1
      pos += 1
      scanner.lits.each -> (lit)
        pos = wrat_put_uvarint(out, pos, wrat_zigzag(lit))
      out[pos] = 0
      pos += 1
      pos = wrat_write_references(out, pos, scanner.hints, scanner.id)
    else
      out[pos] = 2
      pos += 1
      pos = wrat_write_references(out, pos, scanner.hints, next_id - 1)

  out[pos] = 0
  pos += 1
  raise "packed size changed between passes" unless pos == out.size
  out

-> wrat_pack_file(input_path, output_path)
  mapping = File.mmap(input_path)
  begin
    first = wrat_scanner_for_mmap(mapping)
    raise "only hinted WRAT/LRAT can be packed" unless first.hinted?
    raise "certificate is already packed" if first.format == "wratb"
    info = wrat_packed_measure(first)

    second = wrat_scanner_for_mmap(mapping)
    packed = wrat_pack_into(second, info)
    raise "could not write packed certificate" unless File.write_bytes(output_path, packed)
    info["input_bytes"] = mapping.size
    info["output_bytes"] = packed.size
    info
  ensure
    mapping.close
