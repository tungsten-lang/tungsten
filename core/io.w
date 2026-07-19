# SciIO — scientific data interchange (no system libhdf5/netcdf/arrow).
#
# Policy: implement formats in-tree (pure Tungsten and/or vendored C we
# compile ourselves). Never require distro packages for core I/O.
#
#   CSV, FITS header, Zarr meta, MAT Level-5 header — pure Tungsten now
#   HDF5 / NetCDF classic / Parquet / Zarr chunks — in-tree parsers grow
#   here; optional compressed codecs via runtime/zstd (already linked) etc.
#
# Codecs: :none, :gzip, :zstd, :blosc, :lz4

+ SciIO
  # ---- open / sniff ----

  -> .sniff(path)
    bytes = SciIO.read_prefix(path, 16)
    if bytes == nil
      return {:path => path, :format => :missing}
    if SciIO.starts_with?(bytes, "\x89HDF\r\n\x1a\n")
      return {:path => path, :format => :hdf5}
    if SciIO.starts_with?(bytes, "CDF\x01") || SciIO.starts_with?(bytes, "CDF\x02")
      return {:path => path, :format => :netcdf_classic}
    if SciIO.starts_with?(bytes, "\x89HDF")
      # NetCDF-4 is HDF5 under the hood
      return {:path => path, :format => :netcdf4}
    if SciIO.starts_with?(bytes, "SIMPLE  =")
      return {:path => path, :format => :fits}
    if SciIO.starts_with?(bytes, "PAR1")
      return {:path => path, :format => :parquet}
    if SciIO.starts_with?(bytes, "MATLAB")
      return {:path => path, :format => :mat}
    # Zarr is a directory with .zgroup / .zarray
    if File.directory?(path)
      if File.exists?(path + "/.zgroup") || File.exists?(path + "/.zarray")
        return {:path => path, :format => :zarr}
    if SciIO.looks_like_csv?(path)
      return {:path => path, :format => :csv}
    suf = SciIO.sniff_suffix(path)
    if suf != :unknown
      return {:path => path, :format => suf}
    {:path => path, :format => :unknown}

  -> .open(path, compression: :auto)
    info = SciIO.sniff(path)
    fmt = info[:format]
    if fmt == :csv
      return SciIO.read_csv(path)
    if fmt == :fits
      return SciIO.read_fits(path)
    if fmt == :zarr
      return SciIO.read_zarr(path, compression)
    if fmt == :hdf5 || fmt == :netcdf4
      return SciIO.read_hdf5(path)
    if fmt == :netcdf_classic
      return SciIO.read_netcdf(path)
    if fmt == :parquet
      return SciIO.read_parquet(path)
    if fmt == :mat
      return SciIO.read_mat(path)
    raise "SciIO.open: unsupported or unknown format for " + path

  -> .read_prefix(path, n)
    # Best-effort: full File.read then slice (fine for sniffs).
    if File.exists?(path) == false
      return nil
    if File.directory?(path)
      return nil
    text = File.read(path)
    if text.size() <= n
      return text
    # byte-ish string prefix
    out = ""
    i = 0
    while i < n
      out = out + text[i]
      i = i + 1
    out

  -> .starts_with?(s, prefix)
    if s == nil
      return false
    if s.size() < prefix.size()
      return false
    i = 0
    while i < prefix.size()
      if s[i] != prefix[i]
        return false
      i = i + 1
    true

  -> .looks_like_csv?(path)
    if File.exists?(path) == false
      return false
    n = path.size()
    if n >= 4
      # suffix .csv
      if path[n - 4] == "." && path[n - 3] == "c" && path[n - 2] == "s" && path[n - 1] == "v"
        return true
    false

  # Suffix-based sniff when magic bytes are awkward in string path
  -> .sniff_suffix(path)
    n = path.size()
    if n >= 3 && path[n - 3] == "." && path[n - 2] == "n" && path[n - 1] == "c"
      return :netcdf_classic
    if n >= 3 && path[n - 3] == "." && path[n - 2] == "h" && path[n - 1] == "5"
      return :hdf5
    if n >= 4 && path[n - 4] == "." && path[n - 3] == "h" && path[n - 2] == "d" && path[n - 1] == "f"
      return :hdf5
    :unknown

  # ---- CSV (always pure) ----

  -> .parse_csv(text, sep = ",")
    rows = []
    line = ""
    i = 0
    n = text.size()
    while i < n
      ch = text[i]
      if ch == "\n"
        rows = rows.push(SciIO.parse_csv_line(line, sep))
        line = ""
      elsif ch == "\r"
        if i + 1 < n && text[i + 1] == "\n"
          i = i + 1
        rows = rows.push(SciIO.parse_csv_line(line, sep))
        line = ""
      else
        line = line + ch
      i = i + 1
    if line.size() > 0
      rows = rows.push(SciIO.parse_csv_line(line, sep))
    rows

  -> .parse_csv_line(line, sep)
    fields = []
    field = ""
    in_q = false
    i = 0
    n = line.size()
    while i < n
      ch = line[i]
      if in_q
        if ch == "\""
          if i + 1 < n && line[i + 1] == "\""
            field = field + "\""
            i = i + 1
          else
            in_q = false
        else
          field = field + ch
      else
        if ch == "\""
          in_q = true
        elsif ch == sep
          fields = fields.push(field)
          field = ""
        else
          field = field + ch
      i = i + 1
    fields = fields.push(field)
    fields

  -> .csv_to_floats(rows, skip_header = true)
    start = 0
    if skip_header
      start = 1
    out = []
    i = start
    while i < rows.size()
      row = rows[i]
      nums = []
      j = 0
      while j < row.size()
        nums = nums.push(row[j].to_f())
        j = j + 1
      out = out.push(nums)
      i = i + 1
    out

  -> .read_csv(path, sep = ",")
    SciIO.parse_csv(File.read(path), sep)

  -> .write_csv(path, rows, sep = ",")
    sb = ""
    i = 0
    while i < rows.size()
      row = rows[i]
      line = ""
      j = 0
      while j < row.size()
        if j > 0
          line = line + sep
        cell = row[j].to_s()
        line = line + cell
        j = j + 1
      sb = sb + line + "\n"
      i = i + 1
    File.write(path, sb)
    path

  # ---- FITS (pure, primary HDU header + float image if BITPIX=-32/-64) ----

  -> .read_fits(path)
    raw = File.read(path)
    cards = []
    bitpix = 0
    naxis = 0
    naxes = []
    i = 0
    n = raw.size()
    while i + 80 <= n
      card = ""
      j = 0
      while j < 80
        card = card + raw[i + j]
        j = j + 1
      cards = cards.push(card)
      if SciIO.starts_with?(card, "BITPIX")
        bitpix = SciIO.fits_int_value(card)
      if SciIO.starts_with?(card, "NAXIS   ") || SciIO.starts_with?(card, "NAXIS  =")
        naxis = SciIO.fits_int_value(card)
      if SciIO.starts_with?(card, "NAXIS1")
        naxes = naxes.push(SciIO.fits_int_value(card))
      if SciIO.starts_with?(card, "NAXIS2")
        naxes = naxes.push(SciIO.fits_int_value(card))
      if SciIO.starts_with?(card, "NAXIS3")
        naxes = naxes.push(SciIO.fits_int_value(card))
      if SciIO.starts_with?(card, "END")
        i = i + 80
        while i % 2880 != 0
          i = i + 1
        return {:format => :fits, :header => cards, :data_offset => i, :path => path,
                :bitpix => bitpix, :naxis => naxis, :naxes => naxes,
                :raw => raw}
      i = i + 80
    {:format => :fits, :header => cards, :data_offset => 0, :path => path}

  # Parse FITS card value as integer (columns 11–30, free form).
  -> .fits_int_value(card)
    s = ""
    j = 10
    while j < 30 && j < card.size()
      ch = card[j]
      if ch == " " || ch == "/"
        j = 30
      else
        s = s + ch
        j = j + 1
    if s.size() == 0
      return 0
    s.to_i()

  # Primary image as list of Float (BITPIX = -32 big-endian).
  # Uses in-tree C unpacker (no CFITSIO).
  -> .fits_image_f32(fits)
    if fits[:bitpix] != -32
      raise "SciIO.fits_image_f32: BITPIX must be -32 (f32 BE)"
    n = 1
    k = 0
    while k < fits[:naxes].size()
      n = n * fits[:naxes][k]
      k = k + 1
    ccall("w_sci_fits_f32_be", fits[:path], fits[:data_offset], n)


  # ---- Zarr (directory; .zarray JSON + chunk files) ----

  -> .read_zarr(path, compression = :auto)
    # Minimal: read .zarray metadata if present
    meta_path = path + "/.zarray"
    if File.exists?(meta_path) == false
      # group
      if File.exists?(path + "/.zgroup")
        return {:format => :zarr, :kind => :group, :path => path}
      raise "SciIO.read_zarr: no .zarray at " + path
    meta = File.read(meta_path)
    {:format => :zarr, :kind => :array, :path => path, :zarray_json => meta,
     :compression => compression,
     :note => "chunk decode: use SciIO.zarr_chunk(path, indices) when codecs linked"}

  -> .zarr_chunk(path, indices)
    # Uncompressed whole-array chunk "0" for 1-D; multi-index later
    SciIO.read_zarr_f32(path)

  # ---- HDF5 / NetCDF / Parquet / MAT — bridge-backed ----

  # ---- HDF5 (in-tree; no libhdf5) ----
  # TH5C/TH5D = fast Tungsten↔Tungsten payloads under the HDF5 signature.
  # Foreign files: pure-C OHDR walk for contiguous numeric datasets
  # (f32/f64/integers; no chunks/filters yet). See runtime/sci_io_native.c.
  -> .read_hdf5(path)
    sb = ccall("w_sci_hdf5_superblock", path)
    names = nil
    begin
      names = ccall("w_sci_hdf5_list", path)
    rescue err
      names = []
    {:format => :hdf5, :path => path, :superblock => sb, :version => sb[0],
     :datasets => names,
     :note => "TH5C/TH5D or foreign contiguous; use hdf5_read / read_hdf5_f32"}

  # Write 1-D f32 as sniffable HDF5 signature + TH5C body (no libhdf5).
  -> .write_hdf5_f32(path, values)
    ccall("w_sci_hdf5_write_f32_1d", path, values)

  -> .read_hdf5_f32(path)
    ccall("w_sci_hdf5_read_f32_1d", path)

  # Multi-named datasets (TH5D) or foreign OHDR names
  -> .write_hdf5_datasets(path, names, arrays)
    ccall("w_sci_hdf5_write_datasets", path, names, arrays)

  -> .hdf5_list(path)
    ccall("w_sci_hdf5_list", path)

  -> .hdf5_read(path, name)
    ccall("w_sci_hdf5_read_named", path, name)

  # Parquet PLAIN f32 columns (TPAR)
  -> .write_parquet_f32(path, names, arrays)
    ccall("w_sci_parquet_write_f32", path, names, arrays)

  -> .read_parquet_f32(path, name)
    ccall("w_sci_parquet_read_f32", path, name)

  # Zarr 1-D f32 uncompressed (dir + .zarray + chunk 0)
  -> .write_zarr_f32(dir, values)
    ccall("w_sci_zarr_write_f32_1d", dir, values)

  -> .read_zarr_f32(dir)
    ccall("w_sci_zarr_read_f32_1d", dir)

  -> .read_netcdf(path)
    raw = File.read(path)
    if SciIO.starts_with?(raw, "CDF\x01")
      data = ccall("w_sci_netcdf_read_f32_1d", path)
      return {:format => :netcdf_classic, :path => path, :data => data}
    if SciIO.starts_with?(raw, "CDF\x02")
      return {:format => :netcdf_classic, :path => path, :version => 2,
              :note => "CDF\\x02 not yet parsed"}
    if SciIO.starts_with?(raw, "\x89HDF")
      return SciIO.read_hdf5(path)
    raise "SciIO.read_netcdf: unrecognized"

  -> .write_netcdf_f32(path, values)
    ccall("w_sci_netcdf_write_f32_1d", path, values)

  -> .read_netcdf_f32(path)
    ccall("w_sci_netcdf_read_f32_1d", path)

  -> .read_parquet(path)
    raw = File.read(path)
    if SciIO.starts_with?(raw, "PAR1") == false
      raise "SciIO.read_parquet: missing PAR1 magic"
    {:format => :parquet, :path => path,
     :note => "use read_parquet_f32(path, col) for TPAR PLAIN f32 columns"}

  -> .read_mat(path)
    raw = File.read(path)
    if SciIO.starts_with?(raw, "MATLAB")
      return {:format => :mat, :level => 5, :path => path,
              :description => SciIO.mat_desc(raw),
              :note => "miMATRIX body: pure Tungsten/C Level-5 reader"}
    raise "SciIO.read_mat: not Level-5 MATLAB"

  -> .mat_desc(raw)
    # Bytes 0–116 are the descriptive text field
    out = ""
    i = 0
    while i < 116 && i < raw.size()
      out = out + raw[i]
      i = i + 1
    out

  # ---- compression codec names (documentation + dispatch keys) ----

  -> .codecs
    [:none, :gzip, :zstd, :blosc, :lz4]
