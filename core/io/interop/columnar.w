# ---- FlatBuffers Helper & Arrow IPC Reader/Writer ----
+ SciFB
  rw :buf

  -> new
    @buf = SciByteBuf.new(256)
    @buf.put_u32_le(0)

  -> align(n)
    @buf.align(n)

  -> align_plus4(n)
    while ((@buf.len + 4) % n) != 0
      @buf.push(0)

  -> start_table(field_offs, table_size, align_to = 4)
    @buf.align(4)
    vlen = 4 + 2 * field_offs.size
    vt_pos = @buf.len
    @buf.put_u16_le(vlen)
    @buf.put_u16_le(table_size)
    i = 0
    while i < field_offs.size
      @buf.put_u16_le(field_offs[i])
      i += 1
    @buf.align(align_to)
    t_pos = @buf.len
    @buf.put_u32_le(t_pos - vt_pos)
    @buf.extend_zeros(table_size - 4)
    t_pos

  -> set_u8(t_pos, off, val)
    @buf.set_u8(t_pos + off, val)

  -> set_i16(t_pos, off, val)
    @buf.set_u16_le(t_pos + off, val)

  -> set_i32(t_pos, off, val)
    @buf.set_u32_le(t_pos + off, val)

  -> set_i64(t_pos, off, val)
    @buf.set_u64_le(t_pos + off, val)

  -> set_ref(field_pos, target_pos)
    @buf.set_u32_le(field_pos, target_pos - field_pos)

  -> bytes_obj(raw_bytes)
    @buf.align(4)
    pos = @buf.len
    @buf.put_u32_le(raw_bytes.size)
    @buf.extend(raw_bytes)
    @buf.push(0)
    @buf.align(4)
    pos

  # Read helpers on a u8[] FlatBuffer slice
  -> .table_field_pos(b, t_pos, field_idx)
    vt_rel = SciBin.i32_le(b, t_pos)
    vt_pos = t_pos - vt_rel
    vlen = SciBin.u16_le(b, vt_pos)
    off_pos = vt_pos + 4 + 2 * field_idx
    if off_pos + 2 > vt_pos + vlen
      return 0
    f_off = SciBin.u16_le(b, off_pos)
    f_off == 0 ? 0 : t_pos + f_off

  -> .deref(b, pos)
    pos + SciBin.u32_le(b, pos)

  -> .read_bytes_obj(b, ref_pos)
    p = SciFB.deref(b, ref_pos)
    n = SciBin.u32_le(b, p)
    SciBin.slice(b, p + 4, n)

  -> .read_str_obj(b, ref_pos)
    SciBin.bytes_to_str(SciFB.read_bytes_obj(b, ref_pos))

+ SciArrow
  -> .validate_meta_b64(meta)
    out = []
    if meta == nil
      return out
    if !SciValidate.is_hash?(meta)
      raise "metadata_base64 must be a hash"
    keys = meta.keys
    i = 0
    while i < keys.size
      k = keys[i]
      kstr = SciValidate.check_utf8_text(k.to_s, "metadata key")
      vstr = meta[k]
      if !SciValidate.is_string?(vstr)
        raise "metadata_base64 value must be a base64 string"
      out.push([SciBin.str_to_bytes(kstr), Base64.decode(vstr)])
      i += 1
    out

  -> .validate_table(table)
    if !SciValidate.is_hash?(table)
      raise "table must be a hash"
    cols = SciValidate.get_field(table, "columns", :columns)
    if !SciValidate.is_array?(cols) || cols.size == 0
      raise "table columns must be a non-empty array"
    has_rows = SciValidate.has_field?(table, "rows", :rows)
    declared_rows = SciValidate.get_field(table, "rows", :rows)
    meta_b64 = SciValidate.get_field(table, "metadata_base64", :metadata_base64)
    meta_kv = SciArrow.validate_meta_b64(meta_b64)

    seen_names = {}
    prep_cols = []
    nrows = -1
    ci = 0
    while ci < cols.size
      col = cols[ci]
      name = SciValidate.check_utf8_text(SciValidate.get_field(col, "name", :name), "column name")
      if seen_names.has_key?(name)
        raise "duplicate column name [name]"
      seen_names[name] = true
      dtype = SciValidate.get_field(col, "dtype", :dtype)
      if !SciValidate.is_string?(dtype)
        raise "column dtype must be a string"
      if dtype != "float32" && dtype != "float64" && dtype != "int32" && dtype != "int64" && dtype != "uint32" && dtype != "uint64" && dtype != "bool" && dtype != "string"
        raise "unsupported column dtype [dtype]"
      nullable = true
      if SciValidate.has_field?(col, "nullable", :nullable)
        nb = SciValidate.get_field(col, "nullable", :nullable)
        if !SciValidate.is_bool?(nb)
          raise "column nullable must be a bool"
        nullable = nb
      vals = SciValidate.get_field(col, "values", :values)
      if !SciValidate.is_array?(vals)
        raise "column values must be an array"
      if nrows < 0
        nrows = vals.size
      elsif vals.size != nrows
        raise "column length mismatch"
      if nrows > 1000000
        raise "table exceeds 1000000 row limit"
      cvals = []
      vi = 0
      while vi < vals.size
        v = vals[vi]
        if v == nil
          if !nullable
            raise "null value in non-nullable column [name]"
          cvals.push(nil)
        else
          cvals.push(SciValidate.validate_scalar(v, dtype))
        vi += 1
      cmeta = SciArrow.validate_meta_b64(SciValidate.get_field(col, "metadata_base64", :metadata_base64))
      prep_cols.push([name, dtype, nullable, cvals, cmeta])
      ci += 1

    if has_rows && declared_rows != nil
      if !SciValidate.is_int?(declared_rows) || declared_rows != nrows
        raise "declared rows does not match column length"
    [nrows, prep_cols, meta_kv]

  -> .write_kv_vec(fb, kv_list)
    fb.align(4)
    vec_pos = fb.buf.len
    fb.buf.put_u32_le(kv_list.size)
    fb.buf.extend_zeros(4 * kv_list.size)
    i = 0
    while i < kv_list.size
      t = fb.start_table([4, 8], 12)
      fb.set_ref(vec_pos + 4 + 4 * i, t)
      kp = fb.bytes_obj(kv_list[i][0])
      vp = fb.bytes_obj(kv_list[i][1])
      fb.set_ref(t + 4, kp)
      fb.set_ref(t + 8, vp)
      i += 1
    vec_pos

  -> .write_schema_table(fb, prep_cols, meta_kv)
    st = fb.start_table([0, 4, meta_kv.size > 0 ? 8 : 0], 12)
    fb.align(4)
    fvec = fb.buf.len
    fb.buf.put_u32_le(prep_cols.size)
    fb.buf.extend_zeros(4 * prep_cols.size)
    fb.set_ref(st + 4, fvec)
    i = 0
    while i < prep_cols.size
      col = prep_cols[i]
      name = col[0]
      dt = col[1]
      nullable = col[2]
      cmeta = col[4]
      has_meta = cmeta.size > 0
      ft = fb.start_table([4, 8, 9, 12, 0, 16, has_meta ? 20 : 0], 24)
      fb.set_ref(fvec + 4 + 4 * i, ft)
      fb.set_u8(ft, 8, nullable ? 1 : 0)
      tt = 0
      if dt == "int32" || dt == "int64" || dt == "uint32" || dt == "uint64"
        fb.set_u8(ft, 9, 2)
        tt = fb.start_table([4, 8], 12)
        fb.set_i32(tt, 4, (dt == "int32" || dt == "uint32") ? 32 : 64)
        fb.set_u8(tt, 8, (dt == "uint32" || dt == "uint64") ? 0 : 1)
      elsif dt == "float32" || dt == "float64"
        fb.set_u8(ft, 9, 3)
        tt = fb.start_table([4], 8)
        fb.set_i16(tt, 4, dt == "float32" ? 1 : 2)
      elsif dt == "string"
        fb.set_u8(ft, 9, 5)
        tt = fb.start_table([], 4)
      elsif dt == "bool"
        fb.set_u8(ft, 9, 6)
        tt = fb.start_table([], 4)
      fb.set_ref(ft + 12, tt)
      np_pos = fb.bytes_obj(SciBin.str_to_bytes(name))
      fb.set_ref(ft + 4, np_pos)
      fb.align(4)
      cvec = fb.buf.len
      fb.buf.put_u32_le(0)
      fb.set_ref(ft + 16, cvec)
      if has_meta
        mvec = SciArrow.write_kv_vec(fb, cmeta)
        fb.set_ref(ft + 20, mvec)
      i += 1
    if meta_kv.size > 0
      mvec = SciArrow.write_kv_vec(fb, meta_kv)
      fb.set_ref(st + 8, mvec)
    st

  -> .serialize_schema_msg(prep_cols, meta_kv)
    fb = SciFB.new
    mt = fb.start_table([4, 6, 8], 12)
    fb.set_ref(0, mt)
    fb.set_i16(mt, 4, 4)
    fb.set_u8(mt, 6, 1)
    st = SciArrow.write_schema_table(fb, prep_cols, meta_kv)
    fb.set_ref(mt + 8, st)
    fb.align(8)
    out = SciByteBuf.new(fb.buf.len + 8)
    out.put_u32_le(4294967295)
    out.put_u32_le(fb.buf.len)
    out.extend(fb.buf.to_bytes)
    out.to_bytes

  -> .read_kv_vec(b, ref_pos)
    out = {}
    if ref_pos == 0
      return out
    vec = SciFB.deref(b, ref_pos)
    cnt = SciBin.u32_le(b, vec)
    i = 0
    while i < cnt
      kv_pos = SciFB.deref(b, vec + 4 + 4 * i)
      kp = SciFB.table_field_pos(b, kv_pos, 0)
      vp = SciFB.table_field_pos(b, kv_pos, 1)
      kstr = kp != 0 ? SciFB.read_str_obj(b, kp) : ""
      vbytes = vp != 0 ? SciFB.read_bytes_obj(b, vp) : u8[0]
      out[kstr] = Base64.encode(vbytes)
      i += 1
    out

  # Returns [fields_array_of_[name, dtype, nullable, meta_hash], schema_meta_hash]
  -> .parse_schema_table(b, st_pos)
    f_ref = SciFB.table_field_pos(b, st_pos, 1)
    m_ref = SciFB.table_field_pos(b, st_pos, 2)
    schema_meta = SciArrow.read_kv_vec(b, m_ref)
    fields = []
    if f_ref != 0
      fvec = SciFB.deref(b, f_ref)
      nf = SciBin.u32_le(b, fvec)
      i = 0
      while i < nf
        ft = SciFB.deref(b, fvec + 4 + 4 * i)
        np = SciFB.table_field_pos(b, ft, 0)
        null_p = SciFB.table_field_pos(b, ft, 1)
        ttype_p = SciFB.table_field_pos(b, ft, 2)
        tpos_p = SciFB.table_field_pos(b, ft, 3)
        dict_p = SciFB.table_field_pos(b, ft, 4)
        fmeta_p = SciFB.table_field_pos(b, ft, 6)
        if dict_p != 0
          raise "dictionary-encoded Arrow IPC fields not supported"
        name = SciFB.read_str_obj(b, np)
        nullable = null_p == 0 ? false : (b[null_p] != 0)
        ttype = ttype_p == 0 ? 0 : b[ttype_p]
        tt = SciFB.deref(b, tpos_p)
        dtype = nil
        if ttype == 2
          bw_p = SciFB.table_field_pos(b, tt, 0)
          sg_p = SciFB.table_field_pos(b, tt, 1)
          bw = bw_p == 0 ? 0 : SciBin.i32_le(b, bw_p)
          sg = sg_p == 0 ? false : (b[sg_p] != 0)
          if bw == 32
            dtype = sg ? "int32" : "uint32"
          elsif bw == 64
            dtype = sg ? "int64" : "uint64"
          else
            raise "unsupported Arrow Int bitWidth [bw]"
        elsif ttype == 3
          pr_p = SciFB.table_field_pos(b, tt, 0)
          pr = pr_p == 0 ? 0 : SciBin.i16_le(b, pr_p)
          if pr == 1
            dtype = "float32"
          elsif pr == 2
            dtype = "float64"
          else
            raise "unsupported Arrow FloatingPoint precision [pr]"
        elsif ttype == 5
          dtype = "string"
        elsif ttype == 6
          dtype = "bool"
        else
          raise "unsupported Arrow type id [ttype]"
        fmeta = SciArrow.read_kv_vec(b, fmeta_p)
        fields.push([name, dtype, nullable, fmeta])
        i += 1
    [fields, schema_meta]

  -> .write_ipc(path, table)
    if File.exist?(path)
      raise "refusing to overwrite existing Arrow IPC file: [path]"
    validated = SciArrow.validate_table(table)
    nrows = validated[0]
    prep_cols = validated[1]
    meta_kv = validated[2]

    schema_msg = SciArrow.serialize_schema_msg(prep_cols, meta_kv)

    body = SciByteBuf.new(512)
    nodes = []
    buffers = []
    ci = 0
    while ci < prep_cols.size
      col = prep_cols[ci]
      dt = col[1]
      vals = col[3]
      nc = 0
      vi = 0
      while vi < nrows
        if vals[vi] == nil
          nc += 1
        vi += 1
      nodes.push([nrows, nc])
      if nc == 0
        buffers.push([0, 0])
      else
        voff = body.len
        vlen = (nrows + 7) / 8
        vbytes = u8[vlen]
        vi = 0
        while vi < nrows
          if vals[vi] != nil
            vbytes[vi / 8] = vbytes[vi / 8] | (1 << (vi % 8))
          vi += 1
        body.extend(vbytes)
        buffers.push([voff, vlen])
        body.align(8)

      if dt == "string"
        ooff = body.len
        sbuf = SciByteBuf.new(nrows * 8 + 8)
        body.put_u32_le(0)
        vi = 0
        while vi < nrows
          if vals[vi] != nil
            sbuf.extend(SciBin.str_to_bytes(vals[vi]))
          body.put_u32_le(sbuf.len)
          vi += 1
        buffers.push([ooff, (nrows + 1) * 4])
        body.align(8)
        doff = body.len
        body.extend(sbuf.to_bytes)
        buffers.push([doff, sbuf.len])
        body.align(8)
      elsif dt == "bool"
        doff = body.len
        dlen = (nrows + 7) / 8
        dbytes = u8[dlen]
        vi = 0
        while vi < nrows
          if vals[vi] == true
            dbytes[vi / 8] = dbytes[vi / 8] | (1 << (vi % 8))
          vi += 1
        body.extend(dbytes)
        buffers.push([doff, dlen])
        body.align(8)
      else
        doff = body.len
        esz = SciValidate.dtype_byte_size(dt)
        vi = 0
        while vi < nrows
          SciValidate.pack_scalar_le(body, vals[vi] == nil ? 0 : vals[vi], dt)
          vi += 1
        buffers.push([doff, nrows * esz])
        body.align(8)
      ci += 1

    fb_rb = SciFB.new
    mt_rb = fb_rb.start_table([4, 6, 8, 16], 24, 8)
    fb_rb.set_ref(0, mt_rb)
    fb_rb.set_i16(mt_rb, 4, 4)
    fb_rb.set_u8(mt_rb, 6, 3)
    fb_rb.set_i64(mt_rb, 16, body.len)
    rbt = fb_rb.start_table([8, 16, 20], 24, 8)
    fb_rb.set_ref(mt_rb + 8, rbt)
    fb_rb.set_i64(rbt, 8, nrows)
    fb_rb.align_plus4(8)
    nvec = fb_rb.buf.len
    fb_rb.buf.put_u32_le(nodes.size)
    ni = 0
    while ni < nodes.size
      fb_rb.buf.put_u64_le(nodes[ni][0])
      fb_rb.buf.put_u64_le(nodes[ni][1])
      ni += 1
    fb_rb.set_ref(rbt + 16, nvec)
    fb_rb.align_plus4(8)
    bvec = fb_rb.buf.len
    fb_rb.buf.put_u32_le(buffers.size)
    bi = 0
    while bi < buffers.size
      fb_rb.buf.put_u64_le(buffers[bi][0])
      fb_rb.buf.put_u64_le(buffers[bi][1])
      bi += 1
    fb_rb.set_ref(rbt + 20, bvec)
    fb_rb.align(8)
    rb_msg = SciByteBuf.new(fb_rb.buf.len + 8)
    rb_msg.put_u32_le(4294967295)
    rb_msg.put_u32_le(fb_rb.buf.len)
    rb_msg.extend(fb_rb.buf.to_bytes)
    rb_msg_bytes = rb_msg.to_bytes

    rb_offset = 8 + schema_msg.size
    rb_meta_len = rb_msg_bytes.size
    fb_f = SciFB.new
    ft = fb_f.start_table([4, 8, 12, 16], 20)
    fb_f.set_ref(0, ft)
    fb_f.set_i16(ft, 4, 4)
    st_f = SciArrow.write_schema_table(fb_f, prep_cols, meta_kv)
    fb_f.set_ref(ft + 8, st_f)
    fb_f.align_plus4(8)
    dvec = fb_f.buf.len
    fb_f.buf.put_u32_le(0)
    fb_f.set_ref(ft + 12, dvec)
    fb_f.align_plus4(8)
    rbvec = fb_f.buf.len
    fb_f.buf.put_u32_le(1)
    fb_f.buf.put_u64_le(rb_offset)
    fb_f.buf.put_u32_le(rb_meta_len)
    fb_f.buf.put_u32_le(0)
    fb_f.buf.put_u64_le(body.len)
    fb_f.set_ref(ft + 16, rbvec)
    fb_f.align(8)
    footer_bytes = fb_f.buf.to_bytes

    file_out = SciByteBuf.new(rb_offset + rb_meta_len + body.len + footer_bytes.size + 32)
    file_out.extend(SciBin.str_to_bytes("ARROW1"))
    file_out.push(0)
    file_out.push(0)
    file_out.extend(schema_msg)
    file_out.extend(rb_msg_bytes)
    file_out.extend(body.to_bytes)
    file_out.put_u32_le(4294967295)
    file_out.put_u32_le(0)
    file_out.extend(footer_bytes)
    file_out.put_u32_le(footer_bytes.size)
    file_out.extend(SciBin.str_to_bytes("ARROW1"))
    File.write_bytes(path, file_out.to_bytes)
    {"written" => true, "path" => path}

  -> .read_ipc(path)
    b = File.read_bytes(path)
    if b.size < 18 || b[0] != 65 || b[1] != 82 || b[2] != 82 || b[3] != 79 || b[4] != 87 || b[5] != 49
      raise "not a valid Arrow IPC file"
    n = b.size
    if b[n - 6] != 65 || b[n - 5] != 82 || b[n - 4] != 82 || b[n - 3] != 79 || b[n - 2] != 87 || b[n - 1] != 49
      raise "missing trailing ARROW1 magic"
    flen = SciBin.i32_le(b, n - 10)
    fbuf = SciBin.slice(b, n - 10 - flen, flen)
    fpos = SciBin.u32_le(fbuf, 0)
    st_ref = SciFB.table_field_pos(fbuf, fpos, 1)
    st_pos = SciFB.deref(fbuf, st_ref)
    parsed_schema = SciArrow.parse_schema_table(fbuf, st_pos)
    fields = parsed_schema[0]
    schema_meta = parsed_schema[1]

    col_values = []
    i = 0
    while i < fields.size
      col_values.push([])
      i += 1
    total_rows = 0

    rb_ref = SciFB.table_field_pos(fbuf, fpos, 3)
    if rb_ref != 0
      rb_vec = SciFB.deref(fbuf, rb_ref)
      nblocks = SciBin.u32_le(fbuf, rb_vec)
      bi = 0
      while bi < nblocks
        bpos = rb_vec + 4 + 24 * bi
        blk_off = SciBin.i64_le(fbuf, bpos)
        meta_len = SciBin.i32_le(fbuf, bpos + 8)
        body_len = SciBin.i64_le(fbuf, bpos + 16)
        hdr_skip = SciBin.u32_le(b, blk_off) == 4294967295 ? 8 : 4
        mbuf = SciBin.slice(b, blk_off + hdr_skip, meta_len - hdr_skip)
        mpos = SciBin.u32_le(mbuf, 0)
        comp_p = SciFB.table_field_pos(mbuf, SciFB.deref(mbuf, SciFB.table_field_pos(mbuf, mpos, 2)), 3)
        if comp_p != 0
          raise "compressed Arrow IPC buffers not supported"
        rbt = SciFB.deref(mbuf, SciFB.table_field_pos(mbuf, mpos, 2))
        len_p = SciFB.table_field_pos(mbuf, rbt, 0)
        batch_rows = len_p == 0 ? 0 : SciBin.i64_le(mbuf, len_p)
        total_rows += batch_rows
        if total_rows > 1000000
          raise "Arrow table exceeds 1000000 row limit"
        nodes_vec = SciFB.deref(mbuf, SciFB.table_field_pos(mbuf, rbt, 1))
        bufs_vec = SciFB.deref(mbuf, SciFB.table_field_pos(mbuf, rbt, 2))
        body_start = blk_off + meta_len
        buf_idx = 0
        fi = 0
        while fi < fields.size
          dt = fields[fi][1]
          vals = col_values[fi]
          node_pos = nodes_vec + 4 + 16 * fi
          null_cnt = SciBin.i64_le(mbuf, node_pos + 8)
          vbuf_pos = bufs_vec + 4 + 16 * buf_idx
          v_off = SciBin.i64_le(mbuf, vbuf_pos)
          v_len = SciBin.i64_le(mbuf, vbuf_pos + 8)
          buf_idx += 1

          if dt == "string"
            obuf_pos = bufs_vec + 4 + 16 * buf_idx
            o_off = SciBin.i64_le(mbuf, obuf_pos)
            buf_idx += 1
            dbuf_pos = bufs_vec + 4 + 16 * buf_idx
            d_off = SciBin.i64_le(mbuf, dbuf_pos)
            buf_idx += 1
            ri = 0
            while ri < batch_rows
              is_valid = true
              if null_cnt > 0 && v_len > 0
                is_valid = ((b[body_start + v_off + (ri / 8)] >> (ri % 8)) & 1) != 0
              if !is_valid
                vals.push(nil)
              else
                s0 = SciBin.i32_le(b, body_start + o_off + ri * 4)
                s1 = SciBin.i32_le(b, body_start + o_off + (ri + 1) * 4)
                sstr = SciBin.bytes_to_str(SciBin.slice(b, body_start + d_off + s0, s1 - s0))
                SciValidate.check_utf8_string(sstr, "Arrow string")
                vals.push(sstr)
              ri += 1
          elsif dt == "bool"
            dbuf_pos = bufs_vec + 4 + 16 * buf_idx
            d_off = SciBin.i64_le(mbuf, dbuf_pos)
            buf_idx += 1
            ri = 0
            while ri < batch_rows
              is_valid = true
              if null_cnt > 0 && v_len > 0
                is_valid = ((b[body_start + v_off + (ri / 8)] >> (ri % 8)) & 1) != 0
              if !is_valid
                vals.push(nil)
              else
                bit = ((b[body_start + d_off + (ri / 8)] >> (ri % 8)) & 1) != 0
                vals.push(bit)
              ri += 1
          else
            dbuf_pos = bufs_vec + 4 + 16 * buf_idx
            d_off = SciBin.i64_le(mbuf, dbuf_pos)
            buf_idx += 1
            esz = SciValidate.dtype_byte_size(dt)
            ri = 0
            while ri < batch_rows
              is_valid = true
              if null_cnt > 0 && v_len > 0
                is_valid = ((b[body_start + v_off + (ri / 8)] >> (ri % 8)) & 1) != 0
              if !is_valid
                vals.push(nil)
              else
                vals.push(SciValidate.unpack_scalar(b, body_start + d_off + ri * esz, dt, true))
              ri += 1
          fi += 1
        bi += 1

    out_cols = []
    fi = 0
    while fi < fields.size
      f = fields[fi]
      out_cols.push({"name" => f[0], "dtype" => f[1], "nullable" => f[2], "values" => col_values[fi], "metadata_base64" => f[3]})
      fi += 1
    {"columns" => out_cols, "rows" => total_rows, "metadata_base64" => schema_meta}

# ---- Thrift Compact Protocol & Standard Parquet Reader/Writer ----
+ SciParquet
  -> .read_uvarint(b, st)
    pos = st[0]
    res = 0
    shift = 0
    while true
      byte = b[pos] ## i64
      pos += 1
      res = res | ((byte & 127) << shift)
      if (byte & 128) == 0
        st[0] = pos
        return res
      shift += 7

  -> .read_ivarint(b, st)
    u = SciParquet.read_uvarint(b, st)
    (u >> 1) ^ (0 - (u & 1))

  -> .parse_thrift_struct(b, st)
    fields = {}
    fid = 0
    while true
      hdr = b[st[0]] ## i64
      st[0] = st[0] + 1
      if hdr == 0
        return fields
      delta = hdr >> 4
      ttype = hdr & 15
      if delta == 0
        fid = SciParquet.read_ivarint(b, st)
      else
        fid += delta
      fields[fid] = SciParquet.parse_thrift_val(b, st, ttype)

  -> .parse_thrift_val(b, st, ttype)
    if ttype == 1
      return true
    if ttype == 2
      return false
    if ttype == 3
      v = b[st[0]] ## i64
      st[0] = st[0] + 1
      return v
    if ttype == 4 || ttype == 5 || ttype == 6
      return SciParquet.read_ivarint(b, st)
    if ttype == 7
      pos = st[0]
      st[0] = pos + 8
      return SciBin.slice(b, pos, 8)
    if ttype == 8
      n = SciParquet.read_uvarint(b, st)
      pos = st[0]
      st[0] = pos + n
      return SciBin.slice(b, pos, n)
    if ttype == 9 || ttype == 10
      hdr = b[st[0]] ## i64
      st[0] = st[0] + 1
      cnt = hdr >> 4
      etype = hdr & 15
      if cnt == 15
        cnt = SciParquet.read_uvarint(b, st)
      lst = []
      i = 0
      while i < cnt
        lst.push(SciParquet.parse_thrift_val(b, st, etype))
        i += 1
      return lst
    if ttype == 11
      cnt = SciParquet.read_uvarint(b, st)
      if cnt == 0
        return []
      kv = b[st[0]] ## i64
      st[0] = st[0] + 1
      ktype = kv >> 4
      vtype = kv & 15
      lst = []
      i = 0
      while i < cnt
        k = SciParquet.parse_thrift_val(b, st, ktype)
        v = SciParquet.parse_thrift_val(b, st, vtype)
        lst.push([k, v])
        i += 1
      return lst
    if ttype == 12
      return SciParquet.parse_thrift_struct(b, st)
    raise "unsupported Thrift compact type [ttype]"

  -> .put_uvarint(out, n)
    v = n
    while true
      byte = (v % 128).to_i
      v = v / 128
      if v > 0
        out.push(byte | 128)
      else
        out.push(byte)
        return out

  -> .put_ivarint(out, n)
    u = n >= 0 ? (n * 2) : ((0 - n) * 2 - 1)
    SciParquet.put_uvarint(out, u)

  -> .put_field_hdr(out, fid, prev_fid, ttype)
    delta = fid - prev_fid
    if delta >= 1 && delta <= 15
      out.push((delta << 4) | ttype)
    else
      out.push(ttype)
      SciParquet.put_ivarint(out, fid)
    fid

  -> .put_i32_field(out, fid, prev_fid, val)
    SciParquet.put_field_hdr(out, fid, prev_fid, 5)
    SciParquet.put_ivarint(out, val)
    fid

  -> .put_i64_field(out, fid, prev_fid, val)
    SciParquet.put_field_hdr(out, fid, prev_fid, 6)
    SciParquet.put_ivarint(out, val)
    fid

  -> .put_bin_field(out, fid, prev_fid, bytes)
    SciParquet.put_field_hdr(out, fid, prev_fid, 8)
    SciParquet.put_uvarint(out, bytes.size)
    out.extend(bytes)
    fid

  -> .put_list_hdr(out, fid, prev_fid, etype, cnt)
    SciParquet.put_field_hdr(out, fid, prev_fid, 9)
    if cnt < 15
      out.push((cnt << 4) | etype)
    else
      out.push(240 | etype)
      SciParquet.put_uvarint(out, cnt)
    fid

  # Decode RLE / bit-packed hybrid values (used for definition levels and dictionary indices)
  -> .decode_rle_hybrid(b, st, bit_width, count, max_end)
    out = []
    if bit_width == 0
      i = 0
      while i < count
        out.push(0)
        i += 1
      return out
    byte_width = (bit_width + 7) / 8
    mask = (1 << bit_width) - 1
    while out.size < count && st[0] < max_end
      hdr = SciParquet.read_uvarint(b, st)
      if (hdr & 1) == 0
        # RLE run
        run_len = hdr >> 1
        val = 0
        bi = 0
        while bi < byte_width
          val = val | ((b[st[0]] ## i64) << (8 * bi))
          st[0] = st[0] + 1
          bi += 1
        k = 0
        while k < run_len && out.size < count
          out.push(val)
          k += 1
      else
        # Bit-packed run of (hdr >> 1) groups of 8 values
        ngroups = hdr >> 1
        nvals = ngroups * 8
        bit_buf = 0
        bit_cnt = 0
        k = 0
        while k < nvals
          while bit_cnt < bit_width
            if st[0] < max_end
              bit_buf = bit_buf | ((b[st[0]] ## i64) << bit_cnt)
              st[0] = st[0] + 1
            bit_cnt += 8
          if out.size < count
            out.push(bit_buf & mask)
          bit_buf = bit_buf >> bit_width
          bit_cnt -= bit_width
          k += 1
    out

  -> .decode_plain_value(b, st, ptype, dtype)
    pos = st[0]
    if ptype == 0
      # BOOLEAN in PLAIN is bit-packed; handled at array level
      raise "use bit-packed reader for PLAIN BOOLEAN"
    if ptype == 1 || ptype == 4
      st[0] = pos + 4
      return SciValidate.unpack_scalar(b, pos, dtype, true)
    if ptype == 2 || ptype == 5
      st[0] = pos + 8
      return SciValidate.unpack_scalar(b, pos, dtype, true)
    if ptype == 6
      blen = SciBin.u32_le(b, pos)
      st[0] = pos + 4 + blen
      s = SciBin.bytes_to_str(SciBin.slice(b, pos + 4, blen))
      return SciValidate.check_utf8_string(s, "Parquet string")
    raise "unsupported Parquet physical type [ptype]"

  -> .read_standard(path)
    b = File.read_bytes(path)
    n = b.size
    if n < 12 || b[0] != 80 || b[1] != 65 || b[2] != 82 || b[3] != 49 || b[n - 4] != 80 || b[n - 3] != 65 || b[n - 2] != 82 || b[n - 1] != 49
      raise "not a valid Parquet file"
    flen = SciBin.i32_le(b, n - 8)
    fpos = n - 8 - flen
    st = i64[1]
    st[0] = fpos
    fmeta = SciParquet.parse_thrift_struct(b, st)
    schema_elts = fmeta[2]
    num_rows = fmeta[3]
    row_groups = fmeta.has_key?(4) ? fmeta[4] : []
    kv_list = fmeta.has_key?(5) ? fmeta[5] : []
    if num_rows > 1000000
      raise "Parquet table exceeds 1000000 row limit"

    table_meta = {}
    arrow_fields = nil
    ki = 0
    while ki < kv_list.size
      kv = kv_list[ki]
      kstr = SciBin.bytes_to_str(kv[1])
      vbytes = kv.has_key?(2) ? kv[2] : u8[0]
      if kstr == "ARROW:schema"
        s_raw = Base64.decode(SciBin.bytes_to_str(vbytes))
        hskip = SciBin.u32_le(s_raw, 0) == 4294967295 ? 8 : 4
        mbuf = SciBin.slice(s_raw, hskip, s_raw.size - hskip)
        mpos = SciBin.u32_le(mbuf, 0)
        st_pos = SciFB.deref(mbuf, SciFB.table_field_pos(mbuf, mpos, 2))
        parsed_s = SciArrow.parse_schema_table(mbuf, st_pos)
        arrow_fields = parsed_s[0]
      else
        table_meta[kstr] = Base64.encode(vbytes)
      ki += 1

    # Leaf columns are schema_elts[1..]
    ncols = schema_elts.size - 1
    col_defs = []
    ci = 0
    while ci < ncols
      se = schema_elts[ci + 1]
      ptype = se[1]
      rep = se.has_key?(3) ? se[3] : 1
      cname = SciBin.bytes_to_str(se[4])
      ctype = se.has_key?(6) ? se[6] : -1
      ltype = se.has_key?(10) ? se[10] : nil
      nullable = rep != 0
      dtype = nil
      fmeta = {}
      if arrow_fields != nil && ci < arrow_fields.size
        dtype = arrow_fields[ci][1]
        nullable = arrow_fields[ci][2]
        fmeta = arrow_fields[ci][3]
      else
        if ptype == 0
          dtype = "bool"
        elsif ptype == 1
          dtype = (ctype == 13 || (ltype != nil && ltype.has_key?(8) && ltype[8].has_key?(2) && ltype[8][2] == false)) ? "uint32" : "int32"
        elsif ptype == 2
          dtype = (ctype == 14 || (ltype != nil && ltype.has_key?(8) && ltype[8].has_key?(2) && ltype[8][2] == false)) ? "uint64" : "int64"
        elsif ptype == 4
          dtype = "float32"
        elsif ptype == 5
          dtype = "float64"
        elsif ptype == 6
          dtype = "string"
        else
          raise "unsupported Parquet physical type [ptype]"
      col_defs.push([cname, dtype, nullable, fmeta, ptype, rep, []])
      ci += 1

    rgi = 0
    while rgi < row_groups.size
      rg = row_groups[rgi]
      chunks = rg[1]
      ci = 0
      while ci < ncols
        cdef = col_defs[ci]
        dtype = cdef[1]
        ptype = cdef[4]
        rep = cdef[5]
        vals_out = cdef[6]

        cmeta = chunks[ci][3]
        codec = cmeta[4]
        if codec != 0 && codec != 2
          raise "unsupported Parquet compression codec [codec]"
        start_off = cmeta.has_key?(11) ? cmeta[11] : cmeta[9]
        end_off = start_off + cmeta[7]
        pst = i64[1]
        pst[0] = start_off
        dict_vals = []

        while pst[0] < end_off
          phdr = SciParquet.parse_thrift_struct(b, pst)
          page_type = phdr[1]
          usz = phdr[2]
          csz = phdr[3]
          raw_page = SciBin.slice(b, pst[0], csz)
          pst[0] = pst[0] + csz
          if codec == 2
            raw_page = SciDeflate.gzip_decompress(raw_page)

          if page_type == 2
            # DICTIONARY_PAGE
            dhdr = phdr[7]
            dcount = dhdr[1]
            dst = i64[1]
            dst[0] = 0
            di = 0
            while di < dcount
              dict_vals.push(SciParquet.decode_plain_value(raw_page, dst, ptype, dtype))
              di += 1
          elsif page_type == 0
            # DATA_PAGE v1
            dphdr = phdr[5]
            nvals = dphdr[1]
            enc = dphdr[2]
            dst = i64[1]
            dst[0] = 0
            def_levels = nil
            if rep == 1
              rle_len = SciBin.i32_le(raw_page, dst[0])
              dst[0] = dst[0] + 4
              rle_end = dst[0] + rle_len
              def_levels = SciParquet.decode_rle_hybrid(raw_page, dst, 1, nvals, rle_end)
              dst[0] = rle_end
            non_null_cnt = 0
            if def_levels == nil
              non_null_cnt = nvals
            else
              vi = 0
              while vi < nvals
                if def_levels[vi] > 0
                  non_null_cnt += 1
                vi += 1

            non_null_vals = []
            if enc == 0
              if ptype == 0
                # Bit-packed booleans
                bpos = dst[0]
                bi = 0
                while bi < non_null_cnt
                  bit = ((raw_page[bpos + (bi / 8)] >> (bi % 8)) & 1) != 0
                  non_null_vals.push(bit)
                  bi += 1
              else
                bi = 0
                while bi < non_null_cnt
                  non_null_vals.push(SciParquet.decode_plain_value(raw_page, dst, ptype, dtype))
                  bi += 1
            elsif enc == 2 || enc == 8
              bw = raw_page[dst[0]] ## i64
              dst[0] = dst[0] + 1
              idxs = SciParquet.decode_rle_hybrid(raw_page, dst, bw, non_null_cnt, raw_page.size)
              bi = 0
              while bi < non_null_cnt
                non_null_vals.push(dict_vals[idxs[bi]])
                bi += 1
            else
              raise "unsupported Parquet page encoding [enc]"

            nni = 0
            vi = 0
            while vi < nvals
              if def_levels != nil && def_levels[vi] == 0
                vals_out.push(nil)
              else
                vals_out.push(non_null_vals[nni])
                nni += 1
              vi += 1
          else
            raise "unsupported Parquet page type [page_type]"
        ci += 1
      rgi += 1

    out_cols = []
    ci = 0
    while ci < ncols
      cdef = col_defs[ci]
      out_cols.push({"name" => cdef[0], "dtype" => cdef[1], "nullable" => cdef[2], "values" => cdef[6], "metadata_base64" => cdef[3]})
      ci += 1
    {"columns" => out_cols, "rows" => num_rows, "metadata_base64" => table_meta}

  -> .write_standard(path, table)
    if File.exist?(path)
      raise "refusing to overwrite existing Parquet file: [path]"
    validated = SciArrow.validate_table(table)
    nrows = validated[0]
    prep_cols = validated[1]
    meta_kv = validated[2]

    schema_msg = SciArrow.serialize_schema_msg(prep_cols, meta_kv)
    schema_b64 = SciBin.str_to_bytes(Base64.encode(schema_msg))

    file_buf = SciByteBuf.new(1024)
    file_buf.extend(SciBin.str_to_bytes("PAR1"))

    col_chunks_info = []
    total_byte_sz = 0
    ci = 0
    while ci < prep_cols.size
      col = prep_cols[ci]
      cname = col[0]
      dt = col[1]
      nullable = col[2]
      vals = col[3]

      ptype = 0
      if dt == "bool"
        ptype = 0
      elsif dt == "int32" || dt == "uint32"
        ptype = 1
      elsif dt == "int64" || dt == "uint64"
        ptype = 2
      elsif dt == "float32"
        ptype = 4
      elsif dt == "float64"
        ptype = 5
      elsif dt == "string"
        ptype = 6

      page_payload = SciByteBuf.new(256)
      if nullable && nrows > 0
        # RLE definition levels (bit_width=1): 1 bit-packed run of ceil(nrows/8) groups of 8
        ngroups = (nrows + 7) / 8
        rle_body = SciByteBuf.new(ngroups + 8)
        SciParquet.put_uvarint(rle_body, (ngroups << 1) | 1)
        gi = 0
        while gi < ngroups
          byte = 0
          bi = 0
          while bi < 8
            idx = gi * 8 + bi
            if idx < nrows && vals[idx] != nil
              byte = byte | (1 << bi)
            bi += 1
          rle_body.push(byte)
          gi += 1
        page_payload.put_u32_le(rle_body.len)
        page_payload.extend(rle_body.to_bytes)

      if dt == "bool"
        non_nulls = []
        vi = 0
        while vi < nrows
          if vals[vi] != nil
            non_nulls.push(vals[vi])
          vi += 1
        bbytes = u8[(non_nulls.size + 7) / 8]
        bi = 0
        while bi < non_nulls.size
          if non_nulls[bi] == true
            bbytes[bi / 8] = bbytes[bi / 8] | (1 << (bi % 8))
          bi += 1
        page_payload.extend(bbytes)
      elsif dt == "string"
        vi = 0
        while vi < nrows
          if vals[vi] != nil
            sb = SciBin.str_to_bytes(vals[vi])
            page_payload.put_u32_le(sb.size)
            page_payload.extend(sb)
          vi += 1
      else
        vi = 0
        while vi < nrows
          if vals[vi] != nil
            SciValidate.pack_scalar_le(page_payload, vals[vi], dt)
          vi += 1

      # Write PageHeader (type=0 DATA_PAGE, uncompressed_page_size, compressed_page_size, data_page_header)
      col_offset = file_buf.len
      phdr = SciByteBuf.new(32)
      prev = 0
      prev = SciParquet.put_i32_field(phdr, 1, prev, 0)
      prev = SciParquet.put_i32_field(phdr, 2, prev, page_payload.len)
      prev = SciParquet.put_i32_field(phdr, 3, prev, page_payload.len)
      prev = SciParquet.put_field_hdr(phdr, 5, prev, 12)
      dprev = 0
      dprev = SciParquet.put_i32_field(phdr, 1, dprev, nrows)
      dprev = SciParquet.put_i32_field(phdr, 2, dprev, 0)
      dprev = SciParquet.put_i32_field(phdr, 3, dprev, 3)
      dprev = SciParquet.put_i32_field(phdr, 4, dprev, 3)
      phdr.push(0)
      phdr.push(0)

      file_buf.extend(phdr.to_bytes)
      file_buf.extend(page_payload.to_bytes)
      col_sz = file_buf.len - col_offset
      total_byte_sz += col_sz
      col_chunks_info.push([cname, dt, nullable, ptype, col_offset, col_sz])
      ci += 1

    # Build FileMetaData Thrift struct
    footer = SciByteBuf.new(512)
    fprev = 0
    fprev = SciParquet.put_i32_field(footer, 1, fprev, 1)
    # field 2: schema (list of SchemaElement: 1 root + ncols)
    fprev = SciParquet.put_list_hdr(footer, 2, fprev, 12, 1 + prep_cols.size)
    # Root SchemaElement
    sprev = 0
    sprev = SciParquet.put_bin_field(footer, 4, sprev, SciBin.str_to_bytes("schema"))
    sprev = SciParquet.put_i32_field(footer, 5, sprev, prep_cols.size)
    footer.push(0)
    ci = 0
    while ci < col_chunks_info.size
      cinfo = col_chunks_info[ci]
      cname = cinfo[0]
      dt = cinfo[1]
      nullable = cinfo[2]
      ptype = cinfo[3]
      sprev = 0
      sprev = SciParquet.put_i32_field(footer, 1, sprev, ptype)
      sprev = SciParquet.put_i32_field(footer, 3, sprev, nullable ? 1 : 0)
      sprev = SciParquet.put_bin_field(footer, 4, sprev, SciBin.str_to_bytes(cname))
      if dt == "string"
        sprev = SciParquet.put_i32_field(footer, 6, sprev, 0)
      elsif dt == "uint32"
        sprev = SciParquet.put_i32_field(footer, 6, sprev, 13)
      elsif dt == "uint64"
        sprev = SciParquet.put_i32_field(footer, 6, sprev, 14)
      footer.push(0)
      ci += 1

    # field 3: num_rows
    fprev = SciParquet.put_i64_field(footer, 3, fprev, nrows)
    # field 4: row_groups (1 RowGroup)
    fprev = SciParquet.put_list_hdr(footer, 4, fprev, 12, 1)
    rgprev = 0
    rgprev = SciParquet.put_list_hdr(footer, 1, rgprev, 12, col_chunks_info.size)
    ci = 0
    while ci < col_chunks_info.size
      cinfo = col_chunks_info[ci]
      cname = cinfo[0]
      ptype = cinfo[3]
      col_off = cinfo[4]
      col_sz = cinfo[5]
      ccprev = 0
      ccprev = SciParquet.put_i64_field(footer, 2, ccprev, col_off)
      ccprev = SciParquet.put_field_hdr(footer, 3, ccprev, 12)
      cmprev = 0
      cmprev = SciParquet.put_i32_field(footer, 1, cmprev, ptype)
      cmprev = SciParquet.put_list_hdr(footer, 2, cmprev, 5, 2)
      SciParquet.put_ivarint(footer, 0)
      SciParquet.put_ivarint(footer, 3)
      cmprev = SciParquet.put_list_hdr(footer, 3, cmprev, 8, 1)
      nb = SciBin.str_to_bytes(cname)
      SciParquet.put_uvarint(footer, nb.size)
      footer.extend(nb)
      cmprev = SciParquet.put_i32_field(footer, 4, cmprev, 0)
      cmprev = SciParquet.put_i64_field(footer, 5, cmprev, nrows)
      cmprev = SciParquet.put_i64_field(footer, 6, cmprev, col_sz)
      cmprev = SciParquet.put_i64_field(footer, 7, cmprev, col_sz)
      cmprev = SciParquet.put_i64_field(footer, 9, cmprev, col_off)
      footer.push(0)
      footer.push(0)
      ci += 1
    rgprev = SciParquet.put_i64_field(footer, 2, rgprev, total_byte_sz)
    rgprev = SciParquet.put_i64_field(footer, 3, rgprev, nrows)
    footer.push(0)

    # field 5: key_value_metadata (user meta_kv + ARROW:schema)
    fprev = SciParquet.put_list_hdr(footer, 5, fprev, 12, meta_kv.size + 1)
    ki = 0
    while ki < meta_kv.size
      kvprev = 0
      kvprev = SciParquet.put_bin_field(footer, 1, kvprev, meta_kv[ki][0])
      kvprev = SciParquet.put_bin_field(footer, 2, kvprev, meta_kv[ki][1])
      footer.push(0)
      ki += 1
    kvprev = 0
    kvprev = SciParquet.put_bin_field(footer, 1, kvprev, SciBin.str_to_bytes("ARROW:schema"))
    kvprev = SciParquet.put_bin_field(footer, 2, kvprev, schema_b64)
    footer.push(0)

    fprev = SciParquet.put_bin_field(footer, 6, fprev, SciBin.str_to_bytes("tungsten-sciio"))
    footer.push(0)

    footer_bytes = footer.to_bytes
    file_buf.extend(footer_bytes)
    file_buf.put_u32_le(footer_bytes.size)
    file_buf.extend(SciBin.str_to_bytes("PAR1"))
    File.write_bytes(path, file_buf.to_bytes)
    {"written" => true, "path" => path}

