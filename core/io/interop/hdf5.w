# ---- Standard HDF5 Reader & Writer ----
+ SciHDF5
  -> .is_undef_addr?(b, pos, so)
    i = 0
    while i < so
      if b[pos + i] != 255
        return false
      i += 1
    true

  -> .read_addr(b, pos, so)
    if SciHDF5.is_undef_addr?(b, pos, so)
      return -1
    if so == 8
      return SciBin.u64_le(b, pos)
    if so == 4
      return SciBin.u32_le(b, pos)
    v = 0
    i = 0
    while i < so
      v = v | ((b[pos + i] ## i64) << (8 * i))
      i += 1
    v

  -> .read_cstr(b, pos)
    end_pos = pos
    while end_pos < b.size && b[end_pos] != 0
      end_pos += 1
    SciBin.bytes_to_str(SciBin.slice(b, pos, end_pos - pos))

  # Collect all messages in an OHDR v1 or v2 object header (following 0x0010 continuations).
  # Each item is [mtype, mflags, body_u8].
  -> .collect_oh_messages(b, oh_addr, so, sl)
    msgs = []
    if oh_addr < 0 || oh_addr + 6 > b.size
      raise "invalid HDF5 object header address"
    if b[oh_addr] == 79 && b[oh_addr + 1] == 72 && b[oh_addr + 2] == 68 && b[oh_addr + 3] == 82
      # OHDR v2
      ver = b[oh_addr + 4]
      if ver != 2
        raise "unsupported OHDR version"
      fl = b[oh_addr + 5]
      pos = oh_addr + 6
      if (fl & 32) != 0
        pos += 16
      if (fl & 16) != 0
        pos += 4
      csz_len = 1 << (fl & 3)
      csz = SciHDF5.read_addr(b, pos, csz_len)
      pos += csz_len
      chunks = [[pos, pos + csz - 4]]
      ci = 0
      while ci < chunks.size
        cpos = chunks[ci][0]
        cend = chunks[ci][1]
        while cpos + 4 <= cend
          mtype = b[cpos]
          msize = SciBin.u16_le(b, cpos + 1)
          mflags = b[cpos + 3]
          cpos += 4
          if (fl & 4) != 0
            cpos += 2
          body = SciBin.slice(b, cpos, msize)
          cpos += msize
          if mtype == 16
            # Object Header Continuation: addr(so) + len(sl) -> "OCHK" + messages + 4-byte checksum
            cont_addr = SciHDF5.read_addr(b, 0, so)
            cont_len = SciHDF5.read_addr(body, so, sl)
            cont_addr = SciHDF5.read_addr(body, 0, so)
            chunks.push([cont_addr + 4, cont_addr + cont_len - 4])
          elsif mtype != 0
            msgs.push([mtype, mflags, body])
        ci += 1
    else
      # OHDR v1
      ver = b[oh_addr]
      if ver != 1
        raise "unsupported HDF5 object header v1"
      nmsgs = SciBin.u16_le(b, oh_addr + 2)
      hdr_sz = SciBin.u32_le(b, oh_addr + 8)
      chunks = [[oh_addr + 16, oh_addr + 16 + hdr_sz]]
      ci = 0
      seen = 0
      while ci < chunks.size
        cpos = chunks[ci][0]
        cend = chunks[ci][1]
        while cpos + 8 <= cend && seen < nmsgs
          mtype = SciBin.u16_le(b, cpos)
          msize = SciBin.u16_le(b, cpos + 2)
          mflags = b[cpos + 4]
          cpos += 8
          body = SciBin.slice(b, cpos, msize)
          cpos += msize
          seen += 1
          if mtype == 16
            cont_addr = SciHDF5.read_addr(body, 0, so)
            cont_len = SciHDF5.read_addr(body, so, sl)
            chunks.push([cont_addr, cont_addr + cont_len])
          elsif mtype != 0
            msgs.push([mtype, mflags, body])
        ci += 1
    msgs

  -> .collect_group_btree(b, tree_addr, heap_data_seg, so, sl, links)
    if tree_addr < 0 || tree_addr + 8 > b.size
      return links
    if b[tree_addr] != 84 || b[tree_addr + 1] != 82 || b[tree_addr + 2] != 69 || b[tree_addr + 3] != 69
      return links
    ntype = b[tree_addr + 4]
    nlevel = b[tree_addr + 5]
    entries = SciBin.u16_le(b, tree_addr + 6)
    if ntype != 0
      return links
    pos = tree_addr + 8 + 2 * so
    i = 0
    while i < entries
      pos += sl
      child_addr = SciHDF5.read_addr(b, pos, so)
      pos += so
      if nlevel > 0
        SciHDF5.collect_group_btree(b, child_addr, heap_data_seg, so, sl, links)
      else
        # SNOD at child_addr
        if child_addr >= 0 && child_addr + 8 <= b.size && b[child_addr] == 83 && b[child_addr + 1] == 78 && b[child_addr + 2] == 79 && b[child_addr + 3] == 68
          nsyms = SciBin.u16_le(b, child_addr + 6)
          spos = child_addr + 8
          s = 0
          while s < nsyms
            name_off = SciHDF5.read_addr(b, spos, so)
            obj_oh = SciHDF5.read_addr(b, spos + so, so)
            name = SciHDF5.read_cstr(b, heap_data_seg + name_off)
            if name.size > 0 && obj_oh >= 0
              links[name] = obj_oh
            spos += 2 * so + 24
            s += 1
      i += 1
    links

  -> .group_links(b, oh_addr, so, sl)
    msgs = SciHDF5.collect_oh_messages(b, oh_addr, so, sl)
    links = {}
    i = 0
    while i < msgs.size
      mtype = msgs[i][0]
      body = msgs[i][2]
      if mtype == 6
        # Link message
        lver = body[0]
        lfl = body[1]
        off = 2
        ltype = 0
        if (lfl & 8) != 0
          ltype = body[off]
          off += 1
        if (lfl & 4) != 0
          off += 8
        if (lfl & 16) != 0
          off += 1
        nlen_sz = 1 << (lfl & 3)
        nlen = SciHDF5.read_addr(body, off, nlen_sz)
        off += nlen_sz
        name = SciBin.bytes_to_str(SciBin.slice(body, off, nlen))
        off += nlen
        if ltype == 0
          targ = SciHDF5.read_addr(body, off, so)
          links[name] = targ
      elsif mtype == 17
        # Symbol table message (btree_addr + heap_addr)
        btree_addr = SciHDF5.read_addr(body, 0, so)
        heap_addr = SciHDF5.read_addr(body, so, so)
        if heap_addr >= 0 && b[heap_addr] == 72 && b[heap_addr + 1] == 69 && b[heap_addr + 2] == 65 && b[heap_addr + 3] == 80
          heap_data_seg = SciHDF5.read_addr(body.size >= 0 ? b : b, heap_addr + 8 + 2 * sl, so)
          SciHDF5.collect_group_btree(b, btree_addr, heap_data_seg, so, sl, links)
      i += 1
    links

  -> .parse_dtype_msg(body)
    cls_ver = body[0]
    tcls = cls_ver & 15
    bf0 = body[1]
    bf1 = body[2]
    bf2 = body[3]
    tsz = SciBin.u32_le(body, 4)
    le = (bf0 & 1) == 0
    if tcls == 0
      # Fixed-point integer
      sgn = (bf0 & 8) != 0
      if tsz == 4
        return [sgn ? "int32" : "uint32", 4, le, 0]
      if tsz == 8
        return [sgn ? "int64" : "uint64", 8, le, 0]
      if tsz == 1 && !sgn
        return ["uint8", 1, le, 0]
      raise "unsupported integer byte width [tsz]"
    if tcls == 1
      if tsz == 4
        return ["float32", 4, le, 1]
      if tsz == 8
        return ["float64", 8, le, 1]
      raise "unsupported float byte width [tsz]"
    if tcls == 3
      return ["fixed_string", tsz, true, 3]
    if tcls == 8
      if tsz == 1
        return ["bool", 1, true, 8]
      raise "unsupported enum datatype"
    if tcls == 9
      # Variable-length: bf0 & 15 == 1 means string
      if (bf0 & 15) == 1
        return ["vlen_string", tsz, true, 9]
      raise "unsupported variable-length datatype"
    raise "unsupported HDF5 datatype class [tcls]"

  -> .parse_dataspace_msg(body)
    ver = body[0]
    rank = body[1]
    flags = body[2]
    off = ver == 1 ? 8 : 4
    if ver == 2 && body.size > 3 && body[3] == 2
      # null dataspace
      return [[], 0]
    shape = []
    nelem = 1
    i = 0
    while i < rank
      d = SciBin.u64_le(body, off + i * 8)
      shape.push(d)
      nelem = nelem * d
      i += 1
    [shape, nelem]

  -> .read_gcol_object(b, gcol_addr, obj_idx, so, sl)
    if gcol_addr < 0 || gcol_addr + 16 > b.size
      raise "invalid GCOL address"
    if b[gcol_addr] != 71 || b[gcol_addr + 1] != 67 || b[gcol_addr + 2] != 79 || b[gcol_addr + 3] != 76
      raise "missing GCOL signature"
    col_sz = SciHDF5.read_addr(b, gcol_addr + 8, sl)
    pos = gcol_addr + 8 + sl
    end_pos = gcol_addr + col_sz
    while pos + 8 + sl <= end_pos
      idx = SciBin.u16_le(b, pos)
      if idx == 0
        break
      osz = SciHDF5.read_addr(b, pos + 8, sl)
      pos += 8 + sl
      if idx == obj_idx
        return SciBin.slice(b, pos, osz)
      pad = (8 - (osz % 8)) % 8
      pos += osz + pad
    raise "GCOL object not found"

  -> .parse_attribute_msg(b, body, so, sl)
    ver = body[0]
    flags = body[1]
    name_sz = SciBin.u16_le(body, 2)
    dt_sz = SciBin.u16_le(body, 4)
    ds_sz = SciBin.u16_le(body, 6)
    pos = 8
    if ver == 3
      pos += 1
    name_raw = SciBin.slice(body, pos, name_sz)
    # Trim trailing NUL
    nlen = name_raw.size
    while nlen > 0 && name_raw[nlen - 1] == 0
      nlen -= 1
    name = SciBin.bytes_to_str(SciBin.slice(name_raw, 0, nlen))
    if ver == 1
      pos += name_sz + ((8 - (name_sz % 8)) % 8)
    else
      pos += name_sz
    dt_body = SciBin.slice(body, pos, dt_sz)
    if ver == 1
      pos += dt_sz + ((8 - (dt_sz % 8)) % 8)
    else
      pos += dt_sz
    ds_body = SciBin.slice(body, pos, ds_sz)
    if ver == 1
      pos += ds_sz + ((8 - (ds_sz % 8)) % 8)
    else
      pos += ds_sz
    dt_info = SciHDF5.parse_dtype_msg(dt_body)
    ds_info = SciHDF5.parse_dataspace_msg(ds_body)
    dtype = dt_info[0]
    tsz = dt_info[1]
    le = dt_info[2]
    if dtype == "vlen_string"
      vlen = SciBin.u32_le(body, pos)
      gcol_addr = SciHDF5.read_addr(body, pos + 4, so)
      gcol_idx = SciBin.u32_le(body, pos + 4 + so)
      raw_str = SciHDF5.read_gcol_object(b, gcol_addr, gcol_idx, so, sl)
      return [name, SciBin.bytes_to_str(SciBin.slice(raw_str, 0, vlen))]
    if dtype == "fixed_string"
      raw_str = SciBin.slice(body, pos, tsz)
      slen = raw_str.size
      while slen > 0 && raw_str[slen - 1] == 0
        slen -= 1
      return [name, SciBin.bytes_to_str(SciBin.slice(raw_str, 0, slen))]
    [name, SciValidate.unpack_scalar(body, pos, dtype, le)]

  -> .collect_chunk_btree_v1(b, tree_addr, rank, so, out_chunks)
    # Each entry in out_chunks is [coords_array, chunk_addr, chunk_nbytes, filter_mask]
    if tree_addr < 0 || tree_addr + 8 > b.size
      return out_chunks
    if b[tree_addr] != 84 || b[tree_addr + 1] != 82 || b[tree_addr + 2] != 69 || b[tree_addr + 3] != 69
      raise "missing TREE signature in chunk B-tree"
    nlevel = b[tree_addr + 5]
    entries = SciBin.u16_le(b, tree_addr + 6)
    pos = tree_addr + 8 + 2 * so
    ndims = rank + 1
    i = 0
    while i < entries
      nbytes = SciBin.u32_le(b, pos)
      fmask = SciBin.u32_le(b, pos + 4)
      pos += 8
      coords = []
      d = 0
      while d < ndims
        coords.push(SciBin.u64_le(b, pos))
        pos += 8
        d += 1
      child_addr = SciHDF5.read_addr(b, pos, so)
      pos += so
      if nlevel > 0
        SciHDF5.collect_chunk_btree_v1(b, child_addr, rank, so, out_chunks)
      else
        out_chunks.push([coords, child_addr, nbytes, fmask])
      i += 1
    out_chunks

  -> .scatter_chunk(raw_chunk, coords, chunk_dims, shape, tsz, dtype, le, values)
    rank = shape.size
    if rank == 1
      c0 = coords[0]
      n0 = chunk_dims[0]
      i = 0
      while i < n0 && (c0 + i) < shape[0]
        values[c0 + i] = SciValidate.unpack_scalar(raw_chunk, i * tsz, dtype, le)
        i += 1
      return values
    # General rank-N scatter from chunk coordinates into C-order flat array
    chunk_nelem = 1
    d = 0
    while d < rank
      chunk_nelem = chunk_nelem * chunk_dims[d]
      d += 1
    idx = 0
    while idx < chunk_nelem
      rem = idx
      in_bounds = true
      flat_dst = 0
      dst_stride = 1
      d = rank - 1
      while d >= 0
        cd = chunk_dims[d]
        local_c = rem % cd
        rem = rem / cd
        global_c = coords[d] + local_c
        if global_c >= shape[d]
          in_bounds = false
        flat_dst = flat_dst + global_c * dst_stride
        dst_stride = dst_stride * shape[d]
        d -= 1
      if in_bounds
        values[flat_dst] = SciValidate.unpack_scalar(raw_chunk, idx * tsz, dtype, le)
      idx += 1
    values

  -> .index_to_chunk_coords(chunk_idx, shape, chunk_dims)
    rank = shape.size
    grid = i64[rank]
    d = 0
    while d < rank
      grid[d] = (shape[d] + chunk_dims[d] - 1) / chunk_dims[d]
      d += 1
    coords = i64[rank]
    rem = chunk_idx
    d = rank - 1
    while d >= 0
      coords[d] = (rem % grid[d]) * chunk_dims[d]
      rem = rem / grid[d]
      d -= 1
    coords

  -> .read_dataset(path, dataset_path)
    b = File.read_bytes(path)
    if b.size < 16 || b[0] != 137 || b[1] != 72 || b[2] != 68 || b[3] != 70 || b[4] != 13 || b[5] != 10 || b[6] != 26 || b[7] != 10
      raise "not a valid HDF5 file"
    sb_ver = b[8]
    so = 8
    sl = 8
    root_oh = -1
    if sb_ver == 0 || sb_ver == 1
      so = b[13]
      sl = b[14]
      off = sb_ver == 1 ? 28 : 24
      root_oh = SciHDF5.read_addr(b, off + 5 * so, so)
    elsif sb_ver == 2 || sb_ver == 3
      so = b[9]
      sl = b[10]
      root_oh = SciHDF5.read_addr(b, 12 + 3 * so, so)
    else
      raise "unsupported HDF5 superblock version [sb_ver]"

    parts = dataset_path.split("/")
    cur_oh = root_oh
    pi = 0
    while pi < parts.size
      part = parts[pi]
      if part.size > 0
        links = SciHDF5.group_links(b, cur_oh, so, sl)
        if links.has_key?(part) == false
          raise "HDF5 dataset or group not found: [dataset_path]"
        cur_oh = links[part]
      pi += 1

    msgs = SciHDF5.collect_oh_messages(b, cur_oh, so, sl)
    shape = []
    nelem = 0
    dtype = nil
    tsz = 0
    le = true
    compression = nil
    chunks = nil
    layout_body = nil
    attrs = {}

    i = 0
    while i < msgs.size
      mtype = msgs[i][0]
      body = msgs[i][2]
      if mtype == 1
        ds_info = SciHDF5.parse_dataspace_msg(body)
        shape = ds_info[0]
        nelem = ds_info[1]
      elsif mtype == 3
        dt_info = SciHDF5.parse_dtype_msg(body)
        dtype = dt_info[0]
        tsz = dt_info[1]
        le = dt_info[2]
      elsif mtype == 8
        layout_body = body
      elsif mtype == 11
        # Filter pipeline (v1 or v2)
        fver = body[0]
        nfilt = body[1]
        if nfilt > 0
          fid = fver == 1 ? SciBin.u16_le(body, 8) : SciBin.u16_le(body, 2)
          if fid == 1
            compression = "gzip"
          else
            raise "unsupported HDF5 filter id [fid]"
      elsif mtype == 12
        kv = SciHDF5.parse_attribute_msg(b, body, so, sl)
        attrs[kv[0]] = kv[1]
      i += 1

    if dtype == nil || layout_body == nil
      raise "incomplete HDF5 dataset header"
    if nelem > 1000000
      raise "dataset exceeds 1000000 value limit"

    values = []
    i = 0
    while i < nelem
      values.push(0)
      i += 1

    lver = layout_body[0]
    lcls = layout_body[1]
    if lcls == 0
      # Compact layout
      csz = SciBin.u16_le(layout_body, 2)
      cpos = 4
      i = 0
      while i < nelem
        values[i] = SciValidate.unpack_scalar(layout_body, cpos + i * tsz, dtype, le)
        i += 1
    elsif lcls == 1
      # Contiguous layout
      data_addr = SciHDF5.read_addr(layout_body, 2, so)
      if nelem > 0 && data_addr >= 0
        i = 0
        while i < nelem
          values[i] = SciValidate.unpack_scalar(b, data_addr + i * tsz, dtype, le)
          i += 1
    elsif lcls == 2
      # Chunked layout
      if lver == 3
        ndims = layout_body[2]
        btree_addr = SciHDF5.read_addr(layout_body, 3, so)
        chunks = []
        d = 0
        while d < shape.size
          chunks.push(SciBin.u32_le(layout_body, 3 + so + d * 4))
          d += 1
        if nelem > 0 && btree_addr >= 0
          clist = []
          SciHDF5.collect_chunk_btree_v1(b, btree_addr, shape.size, so, clist)
          ci = 0
          while ci < clist.size
            ce = clist[ci]
            c_coords = ce[0]
            c_addr = ce[1]
            c_nbytes = ce[2]
            c_fmask = ce[3]
            raw_c = SciBin.slice(b, c_addr, c_nbytes)
            if compression == "gzip" && (c_fmask & 1) == 0
              raw_c = SciDeflate.zlib_decompress(raw_c)
            SciHDF5.scatter_chunk(raw_c, c_coords, chunks, shape, tsz, dtype, le, values)
            ci += 1
      elsif lver == 4 || lver == 5
        lflags = layout_body[2]
        ndims = layout_body[3]
        enc_len = layout_body[4]
        chunks = []
        pos = 5
        d = 0
        while d < shape.size
          chunks.push(SciHDF5.read_addr(layout_body, pos, enc_len))
          pos += enc_len
          d += 1
        pos += enc_len # skip element size dimension
        idx_type = layout_body[pos]
        pos += 1
        if idx_type == 1
          # Single Chunk
          if (lflags & 2) != 0
            c_nbytes = SciHDF5.read_addr(layout_body, pos, sl)
            c_fmask = SciBin.u32_le(layout_body, pos + sl)
            pos += sl + 4
            c_addr = SciHDF5.read_addr(layout_body, pos, so)
            if nelem > 0 && c_addr >= 0
              raw_c = SciBin.slice(b, c_addr, c_nbytes)
              if compression == "gzip" && (c_fmask & 1) == 0
                raw_c = SciDeflate.zlib_decompress(raw_c)
              zero_coords = i64[shape.size]
              SciHDF5.scatter_chunk(raw_c, zero_coords, chunks, shape, tsz, dtype, le, values)
          else
            c_addr = SciHDF5.read_addr(layout_body, pos, so)
            if nelem > 0 && c_addr >= 0
              chunk_bytes = nelem * tsz
              raw_c = SciBin.slice(b, c_addr, chunk_bytes)
              zero_coords = i64[shape.size]
              SciHDF5.scatter_chunk(raw_c, zero_coords, chunks, shape, tsz, dtype, le, values)
        elsif idx_type == 3
          # Fixed Array (FAHD -> FADB)
          pos += 1 # page_bits
          fahd_addr = SciHDF5.read_addr(layout_body, pos, so)
          if nelem > 0 && fahd_addr >= 0
            if b[fahd_addr] != 70 || b[fahd_addr + 1] != 65 || b[fahd_addr + 2] != 72 || b[fahd_addr + 3] != 68
              raise "missing FAHD signature"
            client_id = b[fahd_addr + 5]
            entry_sz = b[fahd_addr + 6]
            nelts = SciHDF5.read_addr(b, fahd_addr + 8, sl)
            fadb_addr = SciHDF5.read_addr(b, fahd_addr + 8 + sl, so)
            if fadb_addr >= 0
              if b[fadb_addr] != 70 || b[fadb_addr + 1] != 65 || b[fadb_addr + 2] != 68 || b[fadb_addr + 3] != 66
                raise "missing FADB signature"
              epos = fadb_addr + 6 + so
              ci = 0
              while ci < nelts
                c_addr = SciHDF5.read_addr(b, epos, so)
                c_nbytes = 0
                c_fmask = 0
                if client_id == 1
                  nbytes_len = entry_sz - so - 4
                  c_nbytes = SciHDF5.read_addr(b, epos + so, nbytes_len)
                  c_fmask = SciBin.u32_le(b, epos + so + nbytes_len)
                else
                  c_nbytes = entry_sz
                epos += entry_sz
                if c_addr >= 0
                  raw_c = SciBin.slice(b, c_addr, c_nbytes)
                  if compression == "gzip" && (c_fmask & 1) == 0
                    raw_c = SciDeflate.zlib_decompress(raw_c)
                  coords = SciHDF5.index_to_chunk_coords(ci, shape, chunks)
                  SciHDF5.scatter_chunk(raw_c, coords, chunks, shape, tsz, dtype, le, values)
                ci += 1
        else
          raise "unsupported HDF5 v4 chunk index type [idx_type]"
    else
      raise "unsupported HDF5 layout class [lcls]"

    {"dtype" => dtype, "shape" => shape, "order" => "C", "values" => values, "attributes" => attrs, "chunks" => chunks, "compression" => compression}

  -> .encode_dtype_msg(dtype)
    out = SciByteBuf.new(36)
    if dtype == "float32"
      bytes = [17, 32, 31, 0, 4, 0, 0, 0, 0, 0, 32, 0, 23, 8, 0, 23, 127, 0, 0, 0]
      i = 0
      while i < bytes.size
        out.push(bytes[i])
        i += 1
    elsif dtype == "float64"
      bytes = [17, 32, 63, 0, 8, 0, 0, 0, 0, 0, 64, 0, 52, 11, 0, 52, 255, 3, 0, 0]
      i = 0
      while i < bytes.size
        out.push(bytes[i])
        i += 1
    elsif dtype == "int32"
      bytes = [16, 8, 0, 0, 4, 0, 0, 0, 0, 0, 32, 0]
      i = 0
      while i < bytes.size
        out.push(bytes[i])
        i += 1
    elsif dtype == "uint32"
      bytes = [16, 0, 0, 0, 4, 0, 0, 0, 0, 0, 32, 0]
      i = 0
      while i < bytes.size
        out.push(bytes[i])
        i += 1
    elsif dtype == "int64"
      bytes = [16, 8, 0, 0, 8, 0, 0, 0, 0, 0, 64, 0]
      i = 0
      while i < bytes.size
        out.push(bytes[i])
        i += 1
    elsif dtype == "uint64"
      bytes = [16, 0, 0, 0, 8, 0, 0, 0, 0, 0, 64, 0]
      i = 0
      while i < bytes.size
        out.push(bytes[i])
        i += 1
    elsif dtype == "bool"
      bytes = [88, 2, 0, 0, 1, 0, 0, 0, 16, 8, 0, 0, 1, 0, 0, 0, 0, 0, 8, 0, 70, 65, 76, 83, 69, 0, 84, 82, 85, 69, 0, 0, 1]
      i = 0
      while i < bytes.size
        out.push(bytes[i])
        i += 1
    else
      raise "unsupported HDF5 dtype [dtype]"
    out.to_bytes

  -> .wrap_oh1_msg(mtype, flags, body)
    out = SciByteBuf.new(body.size + 16)
    pad = (8 - (body.size % 8)) % 8
    out.put_u16_le(mtype)
    out.put_u16_le(body.size + pad)
    out.push(flags)
    out.extend_zeros(3)
    out.extend(body)
    out.extend_zeros(pad)
    out.to_bytes

  -> .build_oh1(msgs)
    total = 0
    i = 0
    while i < msgs.size
      total += msgs[i].size
      i += 1
    out = SciByteBuf.new(16 + total)
    out.push(1)
    out.push(0)
    out.put_u16_le(msgs.size)
    out.put_u32_le(1)
    out.put_u32_le(total)
    out.put_u32_le(0)
    i = 0
    while i < msgs.size
      out.extend(msgs[i])
      i += 1
    out.to_bytes

  -> .build_link_msg(name, target_addr)
    nb = SciBin.str_to_bytes(name)
    body = SciByteBuf.new(nb.size + 16)
    body.push(1)
    body.push(0)
    body.push(nb.size)
    body.extend(nb)
    body.put_u64_le(target_addr)
    SciHDF5.wrap_oh1_msg(6, 0, body.to_bytes)

  -> .build_group_oh1(child_pairs)
    msgs = []
    # Link Info message (0x0002)
    li = SciByteBuf.new(18)
    li.push(0)
    li.push(0)
    li.put_u64_le(-1)
    li.put_u64_le(-1)
    msgs.push(SciHDF5.wrap_oh1_msg(2, 0, li.to_bytes))
    # Group Info message (0x000A)
    gi = SciByteBuf.new(2)
    gi.push(0)
    gi.push(0)
    msgs.push(SciHDF5.wrap_oh1_msg(10, 1, gi.to_bytes))
    i = 0
    while i < child_pairs.size
      msgs.push(SciHDF5.build_link_msg(child_pairs[i][0], child_pairs[i][1]))
      i += 1
    SciHDF5.build_oh1(msgs)

  -> .write_standard(path, datasets)
    if File.exist?(path)
      raise "refusing to overwrite existing HDF5 file: [path]"
    if !SciValidate.is_hash?(datasets) || datasets.keys.size == 0
      raise "datasets must be a non-empty hash"

    # 1. Validate all dataset specs first before touching disk
    prepared = []
    gcol_strings = []
    dkeys = datasets.keys
    di = 0
    while di < dkeys.size
      raw_key = dkeys[di]
      dname = SciValidate.check_utf8_text(raw_key.to_s, "dataset name")
      parts = []
      raw_parts = dname.split("/")
      pi = 0
      while pi < raw_parts.size
        if raw_parts[pi].size > 0
          parts.push(raw_parts[pi])
        pi += 1
      if parts.size == 0
        raise "invalid dataset path [dname]"
      spec = datasets[raw_key]
      dtype = SciValidate.get_field(spec, "dtype", :dtype)
      shape = SciValidate.get_field(spec, "shape", :shape)
      vals = SciValidate.get_field(spec, "values", :values)
      attrs = SciValidate.get_field(spec, "attributes", :attributes)
      comp = SciValidate.get_field(spec, "compression", :compression)
      if !SciValidate.is_string?(dtype)
        raise "dataset dtype must be a string"
      tsz = SciValidate.dtype_byte_size(dtype)
      if !SciValidate.is_array?(shape) || !SciValidate.is_array?(vals)
        raise "dataset shape and values must be arrays"
      nelem = 1
      si = 0
      while si < shape.size
        dim = shape[si]
        if !SciValidate.is_int?(dim) || dim < 0
          raise "invalid shape dimension"
        nelem = nelem * dim
        si += 1
      if nelem > 1000000
        raise "dataset exceeds 1000000 value limit"
      if vals.size != nelem
        raise "dataset values length ([vals.size]) does not match shape product ([nelem])"
      if comp != nil && comp != "gzip"
        raise "unsupported compression [comp]"
      if comp == "gzip" && shape.size == 0
        raise "gzip compression is not supported on scalar datasets"

      raw_buf = SciByteBuf.new(nelem * tsz + 8)
      vi = 0
      while vi < nelem
        cv = SciValidate.validate_scalar(vals[vi], dtype)
        SciValidate.pack_scalar_le(raw_buf, cv, dtype)
        vi += 1

      prep_attrs = []
      if attrs != nil
        if !SciValidate.is_hash?(attrs)
          raise "attributes must be a hash"
        akeys = attrs.keys
        ai = 0
        while ai < akeys.size
          ak = akeys[ai]
          aname = SciValidate.check_utf8_text(ak.to_s, "attribute name")
          aval = attrs[ak]
          if SciValidate.is_string?(aval)
            SciValidate.check_utf8_string(aval, "attribute string")
            gcol_strings.push(SciBin.str_to_bytes(aval))
            prep_attrs.push([aname, "vlen_string", aval, gcol_strings.size])
          elsif SciValidate.is_bool?(aval)
            prep_attrs.push([aname, "bool", aval, 0])
          elsif SciValidate.is_int?(aval)
            SciValidate.validate_scalar(aval, "int64")
            prep_attrs.push([aname, "int64", aval, 0])
          elsif SciValidate.is_float?(aval)
            SciValidate.validate_scalar(aval, "float64")
            prep_attrs.push([aname, "float64", aval, 0])
          else
            raise "unsupported attribute value type"
          ai += 1

      prepared.push([parts, dtype, tsz, shape, nelem, raw_buf.to_bytes, comp, prep_attrs])
      di += 1

    # 2. Layout file:
    #    0..96: Superblock v0 placeholder
    #    Then data payloads, B-trees, and GCOL collection so we know their exact addresses!
    file_buf = SciByteBuf.new(4096)
    file_buf.extend_zeros(96)

    gcol_addr = 0
    if gcol_strings.size > 0
      file_buf.align(8)
      gcol_addr = file_buf.len
      # Compute GCOL size (at least 4096 bytes)
      objs_buf = SciByteBuf.new(512)
      gi = 0
      while gi < gcol_strings.size
        sb = gcol_strings[gi]
        objs_buf.put_u16_le(gi + 1)
        objs_buf.put_u16_le(0)
        objs_buf.put_u32_le(0)
        objs_buf.put_u64_le(sb.size)
        objs_buf.extend(sb)
        objs_buf.align(8)
        gi += 1
      col_sz = 4096
      while col_sz < 16 + objs_buf.len + 16
        col_sz = col_sz * 2
      free_rem = col_sz - 16 - objs_buf.len
      file_buf.extend(SciBin.str_to_bytes("GCOL"))
      file_buf.push(1)
      file_buf.extend_zeros(3)
      file_buf.put_u64_le(col_sz)
      file_buf.extend(objs_buf.to_bytes)
      # Object 0 free space header
      file_buf.put_u16_le(0)
      file_buf.put_u16_le(0)
      file_buf.put_u32_le(0)
      file_buf.put_u64_le(free_rem)
      file_buf.extend_zeros(free_rem - 16)

    # 3. Emit dataset payloads, B-trees, and dataset OHDR v1 blocks
    ds_addrs = []
    pi = 0
    while pi < prepared.size
      item = prepared[pi]
      parts = item[0]
      dtype = item[1]
      tsz = item[2]
      shape = item[3]
      nelem = item[4]
      raw_bytes = item[5]
      comp = item[6]
      prep_attrs = item[7]

      msgs = []
      # Dataspace v1
      ds_msg = SciByteBuf.new(16 + shape.size * 16)
      ds_msg.push(1)
      ds_msg.push(shape.size)
      ds_msg.push(0)
      ds_msg.extend_zeros(5)
      si = 0
      while si < shape.size
        ds_msg.put_u64_le(shape[si])
        si += 1
      msgs.push(SciHDF5.wrap_oh1_msg(1, 0, ds_msg.to_bytes))

      # Datatype
      msgs.push(SciHDF5.wrap_oh1_msg(3, 1, SciHDF5.encode_dtype_msg(dtype)))

      # Fill value (v2: space alloc late, default fill)
      fv_msg = SciByteBuf.new(8)
      fv_msg.push(2)
      fv_msg.push(3)
      fv_msg.push(2)
      fv_msg.push(0)
      msgs.push(SciHDF5.wrap_oh1_msg(5, 1, fv_msg.to_bytes))

      if comp == "gzip" && shape.size > 0
        # Filter pipeline v1: deflate (id=1)
        fp_bytes = [1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 8, 0, 1, 0, 1, 0, 100, 101, 102, 108, 97, 116, 101, 0, 4, 0, 0, 0, 0, 0, 0, 0]
        fp_buf = SciByteBuf.new(32)
        fi = 0
        while fi < fp_bytes.size
          fp_buf.push(fp_bytes[fi])
          fi += 1
        msgs.push(SciHDF5.wrap_oh1_msg(11, 1, fp_buf.to_bytes))

        # Compress single chunk covering shape (or 1 element per dim if empty)
        cdims = []
        si = 0
        while si < shape.size
          cdims.push(shape[si] > 0 ? shape[si] : 1)
          si += 1
        comp_bytes = SciDeflate.zlib_compress(raw_bytes)
        file_buf.align(8)
        chunk_addr = file_buf.len
        file_buf.extend(comp_bytes)

        # B-tree v1 node (must reserve 2*K = 64 entries for libhdf5 default K=32!)
        file_buf.align(8)
        btree_addr = file_buf.len
        ndims = shape.size + 1
        key_sz = 8 + ndims * 8
        tree_total_sz = 24 + 64 * (key_sz + 8) + key_sz
        tbuf = SciByteBuf.new(tree_total_sz)
        tbuf.extend(SciBin.str_to_bytes("TREE"))
        tbuf.push(1)
        tbuf.push(0)
        tbuf.put_u16_le(nelem > 0 ? 1 : 0)
        tbuf.put_u64_le(-1)
        tbuf.put_u64_le(-1)
        if nelem > 0
          tbuf.put_u32_le(comp_bytes.size)
          tbuf.put_u32_le(0)
          di2 = 0
          while di2 < ndims
            tbuf.put_u64_le(0)
            di2 += 1
          tbuf.put_u64_le(chunk_addr)
          tbuf.put_u32_le(0)
          tbuf.put_u32_le(0)
          si = 0
          while si < shape.size
            tbuf.put_u64_le(cdims[si])
            si += 1
          tbuf.put_u64_le(tsz)
        tbuf.extend_zeros(tree_total_sz - tbuf.len)
        file_buf.extend(tbuf.to_bytes)

        # Layout v3 chunked
        lbuf = SciByteBuf.new(16 + ndims * 4)
        lbuf.push(3)
        lbuf.push(2)
        lbuf.push(ndims)
        lbuf.put_u64_le(nelem > 0 ? btree_addr : -1)
        si = 0
        while si < cdims.size
          lbuf.put_u32_le(cdims[si])
          si += 1
        lbuf.put_u32_le(tsz)
        msgs.push(SciHDF5.wrap_oh1_msg(8, 0, lbuf.to_bytes))
      else
        # Contiguous layout v3
        data_addr = -1
        if nelem > 0
          file_buf.align(8)
          data_addr = file_buf.len
          file_buf.extend(raw_bytes)
        lbuf = SciByteBuf.new(18)
        lbuf.push(3)
        lbuf.push(1)
        lbuf.put_u64_le(data_addr)
        lbuf.put_u64_le(nelem * tsz)
        msgs.push(SciHDF5.wrap_oh1_msg(8, 0, lbuf.to_bytes))

      # Attributes (v1)
      ai = 0
      while ai < prep_attrs.size
        pa = prep_attrs[ai]
        aname = pa[0]
        atype = pa[1]
        aval = pa[2]
        gidx = pa[3]
        nb = SciBin.str_to_bytes(aname)
        name_len = nb.size + 1
        name_pad = (8 - (name_len % 8)) % 8
        dt_bytes = nil
        val_buf = SciByteBuf.new(16)
        if atype == "vlen_string"
          # 20-byte vlen UTF-8 string datatype
          vdt = [25, 1, 1, 0, 16, 0, 0, 0, 16, 0, 0, 0, 1, 0, 0, 0, 0, 0, 8, 0]
          dtb = SciByteBuf.new(20)
          vi = 0
          while vi < vdt.size
            dtb.push(vdt[vi])
            vi += 1
          dt_bytes = dtb.to_bytes
          sb = SciBin.str_to_bytes(aval)
          val_buf.put_u32_le(sb.size)
          val_buf.put_u64_le(gcol_addr)
          val_buf.put_u32_le(gidx)
        else
          dt_bytes = SciHDF5.encode_dtype_msg(atype)
          SciValidate.pack_scalar_le(val_buf, aval, atype)
        dt_pad = (8 - (dt_bytes.size % 8)) % 8
        abuf = SciByteBuf.new(64)
        abuf.push(1)
        abuf.push(0)
        abuf.put_u16_le(name_len)
        abuf.put_u16_le(dt_bytes.size)
        abuf.put_u16_le(8)
        abuf.extend(nb)
        abuf.push(0)
        abuf.extend_zeros(name_pad)
        abuf.extend(dt_bytes)
        abuf.extend_zeros(dt_pad)
        # scalar dataspace v1 (8 bytes)
        abuf.push(1)
        abuf.extend_zeros(7)
        abuf.extend(val_buf.to_bytes)
        msgs.push(SciHDF5.wrap_oh1_msg(12, 0, abuf.to_bytes))
        ai += 1

      file_buf.align(8)
      ds_addr = file_buf.len
      file_buf.extend(SciHDF5.build_oh1(msgs))
      ds_addrs.push([parts, ds_addr])
      pi += 1

    # 4. Build nested groups bottom-up
    root_addr = SciHDF5.emit_group_tree(file_buf, ds_addrs, 0)

    # 5. Patch Superblock v0 at offset 0
    eof_addr = file_buf.len
    sb = SciByteBuf.new(96)
    sig = [137, 72, 68, 70, 13, 10, 26, 10]
    si = 0
    while si < 8
      sb.push(sig[si])
      si += 1
    sb.push(0)
    sb.push(0)
    sb.push(0)
    sb.push(0)
    sb.push(0)
    sb.push(8)
    sb.push(8)
    sb.push(0)
    sb.put_u16_le(4)
    sb.put_u16_le(16)
    sb.put_u32_le(0)
    sb.put_u64_le(0)
    sb.put_u64_le(-1)
    sb.put_u64_le(eof_addr)
    sb.put_u64_le(-1)
    sb.put_u64_le(0)
    sb.put_u64_le(root_addr)
    sb.put_u32_le(0)
    sb.put_u32_le(0)
    sb.put_u64_le(0)
    sb.put_u64_le(0)
    sb_bytes = sb.to_bytes
    i = 0
    while i < 96
      file_buf.set_u8(i, sb_bytes[i])
      i += 1

    File.write_bytes(path, file_buf.to_bytes)
    {"written" => true, "path" => path}

  -> .emit_group_tree(file_buf, entries, depth)
    child_pairs = []
    subgroups = {}
    sub_order = []
    i = 0
    while i < entries.size
      parts = entries[i][0]
      addr = entries[i][1]
      head = parts[depth]
      if parts.size == depth + 1
        child_pairs.push([head, addr])
      else
        if subgroups.has_key?(head) == false
          subgroups[head] = []
          sub_order.push(head)
        subgroups[head].push(entries[i])
      i += 1
    si = 0
    while si < sub_order.size
      gname = sub_order[si]
      gaddr = SciHDF5.emit_group_tree(file_buf, subgroups[gname], depth + 1)
      child_pairs.push([gname, gaddr])
      si += 1
    file_buf.align(8)
    oh_addr = file_buf.len
    file_buf.extend(SciHDF5.build_group_oh1(child_pairs))
    oh_addr

