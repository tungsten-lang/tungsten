# Location mode 11 Range spec.
# Tests inline location range encoding (file_id, start_offset, length).

loc = ccall("w_location_range_w", 42, 1024, 64)
fid = ccall("w_unbox_location_file_id_extern", loc)

-> expect(name, cond)
  if cond
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

expect("location.range_mode11_fid", fid == 42)
