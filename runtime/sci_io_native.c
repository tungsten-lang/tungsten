/* In-tree scientific format helpers — NO libhdf5 / libnetcdf / Arrow. */
#include "runtime.h"
#include "wvalue.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

static const char *sci_path(WValue v, char *buf, size_t buf_size) {
    char tmp[6];
    const char *s = NULL;
    size_t len = 0;
    w_str_data(v, tmp, &s, &len);
    if (len >= buf_size) len = buf_size - 1;
    memcpy(buf, s, len);
    buf[len] = 0;
    return buf;
}

/* Read n big-endian IEEE float32 values at byte offset in path → poly Array of Float. */
WValue w_sci_fits_f32_be(WValue path_wv, WValue offset_wv, WValue n_wv) {
    char path[1024];
    sci_path(path_wv, path, sizeof(path));
    int64_t off = w_as_int(offset_wv);
    int64_t n = w_as_int(n_wv);
    if (n < 0) n = 0;
    FILE *fp = fopen(path, "rb");
    if (!fp) {
        w_raise(w_string("w_sci_fits_f32_be: open failed"));
        return W_NIL;
    }
    if (fseek(fp, (long)off, SEEK_SET) != 0) {
        fclose(fp);
        w_raise(w_string("w_sci_fits_f32_be: seek failed"));
        return W_NIL;
    }
    WValue arr = w_array_new(65, n);
    WArray *a = (WArray *)w_as_ptr(arr);
    for (int64_t i = 0; i < n; i++) {
        unsigned char b[4];
        if (fread(b, 1, 4, fp) != 4) break;
        uint32_t u = ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) |
                     ((uint32_t)b[2] << 8) | (uint32_t)b[3];
        float f;
        memcpy(&f, &u, 4);
        if (a->size < a->cap) {
            ((WValue *)a->slots)[a->start + a->size] = w_float((double)f);
            a->size++;
        }
    }
    fclose(fp);
    return arr;
}

WValue w_sci_mat_level5_ok(WValue path_wv) {
    char path[1024];
    sci_path(path_wv, path, sizeof(path));
    FILE *fp = fopen(path, "rb");
    if (!fp) return w_int(0);
    char hdr[128];
    size_t got = fread(hdr, 1, 128, fp);
    fclose(fp);
    if (got < 128) return w_int(0);
    if (memcmp(hdr, "MATLAB", 6) != 0) return w_int(0);
    return w_int(1);
}

/* HDF5 superblock v0/v2/v3 sniff — returns a poly Hash-like Array of fields
 * as boxed values for Tungsten. Full object-header walk is future work. */
WValue w_sci_hdf5_superblock(WValue path_wv) {
    char path[1024];
    sci_path(path_wv, path, sizeof(path));
    FILE *fp = fopen(path, "rb");
    if (!fp) {
        w_raise(w_string("hdf5_superblock: open failed"));
        return W_NIL;
    }
    unsigned char sb[64];
    size_t got = fread(sb, 1, 64, fp);
    fclose(fp);
    if (got < 9 || memcmp(sb, "\x89HDF\r\n\x1a\n", 8) != 0) {
        w_raise(w_string("hdf5_superblock: bad signature"));
        return W_NIL;
    }
    int version = sb[8];
    /* Return [version, free_space_version_or_-1, size_of_offsets, size_of_lengths] */
    WValue arr = w_array_new(65, 8);
    WArray *a = (WArray *)w_as_ptr(arr);
    ((WValue *)a->slots)[0] = w_int(version);
    a->size = 1;
    if (version == 0 || version == 1) {
        /* superblock v0: offsets size at byte 13, lengths at 14 */
        if (got >= 15) {
            ((WValue *)a->slots)[1] = w_int(sb[13]);
            ((WValue *)a->slots)[2] = w_int(sb[14]);
            a->size = 3;
        }
    } else if (version == 2 || version == 3) {
        if (got >= 12) {
            ((WValue *)a->slots)[1] = w_int(sb[9]);  /* size of offsets */
            ((WValue *)a->slots)[2] = w_int(sb[10]); /* size of lengths */
            a->size = 3;
        }
    }
    return arr;
}

/* ---- NetCDF classic (CDF\x01) 1-D float variable write/read (little subset) ----
 * Layout (all big-endian multi-byte fields as classic NetCDF requires):
 *   magic "CDF\x01"
 *   numrecs u32 = 0
 *   dim_array: tag NC_DIMENSION(10) count=1 name="n" len=N
 *   att_array: tag NC_ATTRIBUTE(12) count=0
 *   var_array: tag NC_VARIABLE(11) count=1 name="x" ndims=1 dimid=0
 *              nc_type NC_FLOAT(5) vsize=4*N begin=offset_of_data
 *   data: N × f32 little-endian (classic allows host? Actually classic data
 *         is XDR big-endian floats)
 *
 * We write XDR big-endian floats for interoperability.
 */

#define NC_DIMENSION 10
#define NC_VARIABLE  11
#define NC_ATTRIBUTE 12
#define NC_FLOAT     5

static void be32(FILE *fp, uint32_t v) {
    unsigned char b[4] = { (unsigned char)(v>>24), (unsigned char)(v>>16),
                           (unsigned char)(v>>8), (unsigned char)v };
    fwrite(b, 1, 4, fp);
}
static void be_f32(FILE *fp, float f) {
    uint32_t u;
    memcpy(&u, &f, 4);
    be32(fp, u);
}
static uint32_t rd_be32(FILE *fp) {
    unsigned char b[4];
    if (fread(b, 1, 4, fp) != 4) return 0;
    return ((uint32_t)b[0]<<24)|((uint32_t)b[1]<<16)|((uint32_t)b[2]<<8)|(uint32_t)b[3];
}
static void wr_nc_string(FILE *fp, const char *s) {
    uint32_t n = (uint32_t)strlen(s);
    be32(fp, n);
    fwrite(s, 1, n, fp);
    /* pad to 4-byte boundary */
    while (n % 4) { fputc(0, fp); n++; }
}

/* Write 1-D f32 array (poly or typed) to classic NetCDF path. */
WValue w_sci_netcdf_write_f32_1d(WValue path_wv, WValue data_wv) {
    char path[1024];
    sci_path(path_wv, path, sizeof(path));
    if (!w_is_array(data_wv)) {
        w_raise(w_string("netcdf_write: data must be Array"));
        return W_NIL;
    }
    WArray *a = (WArray *)w_as_ptr(data_wv);
    int64_t n = a->size;
    FILE *fp = fopen(path, "wb");
    if (!fp) { w_raise(w_string("netcdf_write: open failed")); return W_NIL; }
    fwrite("CDF\x01", 1, 4, fp);
    be32(fp, 0); /* numrecs */
    /* dim_array */
    be32(fp, NC_DIMENSION);
    be32(fp, 1);
    wr_nc_string(fp, "n");
    be32(fp, (uint32_t)n);
    /* att_array empty */
    be32(fp, NC_ATTRIBUTE);
    be32(fp, 0);
    /* var_array */
    be32(fp, NC_VARIABLE);
    be32(fp, 1);
    wr_nc_string(fp, "x");
    be32(fp, 1); /* ndims */
    be32(fp, 0); /* dimid 0 */
    be32(fp, NC_ATTRIBUTE); /* var atts empty tag? actually vatt_list */
    be32(fp, 0);
    be32(fp, NC_FLOAT);
    be32(fp, (uint32_t)(4 * n)); /* vsize */
    /* begin: absolute offset of data — compute after we know header end.
     * Classic: write placeholder then patch, or compute. We compute:
     * after this be32(begin) we're at data. So begin = ftell after writing begin field.
     * Write begin as current+4. */
    long begin_pos = ftell(fp);
    be32(fp, 0); /* patch later */
    long data_pos = ftell(fp);
    fseek(fp, begin_pos, SEEK_SET);
    be32(fp, (uint32_t)data_pos);
    fseek(fp, data_pos, SEEK_SET);
    for (int64_t i = 0; i < n; i++) {
        WValue e = ((WValue *)a->slots)[a->start + i];
        float f = (float)w_as_double(e);
        be_f32(fp, f);
    }
    fclose(fp);
    return w_int(1);
}

WValue w_sci_netcdf_read_f32_1d(WValue path_wv) {
    char path[1024];
    sci_path(path_wv, path, sizeof(path));
    FILE *fp = fopen(path, "rb");
    if (!fp) { w_raise(w_string("netcdf_read: open failed")); return W_NIL; }
    char mag[4];
    if (fread(mag, 1, 4, fp) != 4 || memcmp(mag, "CDF\x01", 4) != 0) {
        fclose(fp);
        w_raise(w_string("netcdf_read: not classic CDF\\x01"));
        return W_NIL;
    }
    (void)rd_be32(fp); /* numrecs */
    /* dim_array */
    uint32_t tag = rd_be32(fp);
    if (tag != NC_DIMENSION) { fclose(fp); w_raise(w_string("netcdf_read: expected dims")); return W_NIL; }
    uint32_t nd = rd_be32(fp);
    if (nd != 1) { fclose(fp); w_raise(w_string("netcdf_read: only 1-D supported")); return W_NIL; }
    uint32_t namelen = rd_be32(fp);
    fseek(fp, ((namelen + 3) & ~3u), SEEK_CUR);
    uint32_t dimlen = rd_be32(fp);
    /* att_array */
    tag = rd_be32(fp);
    if (tag != NC_ATTRIBUTE) { fclose(fp); w_raise(w_string("netcdf_read: expected gatt")); return W_NIL; }
    uint32_t na = rd_be32(fp);
    if (na != 0) { fclose(fp); w_raise(w_string("netcdf_read: global atts not supported")); return W_NIL; }
    /* var_array */
    tag = rd_be32(fp);
    if (tag != NC_VARIABLE) { fclose(fp); w_raise(w_string("netcdf_read: expected vars")); return W_NIL; }
    uint32_t nv = rd_be32(fp);
    if (nv != 1) { fclose(fp); w_raise(w_string("netcdf_read: only 1 var supported")); return W_NIL; }
    namelen = rd_be32(fp);
    fseek(fp, ((namelen + 3) & ~3u), SEEK_CUR);
    uint32_t ndims = rd_be32(fp);
    for (uint32_t i = 0; i < ndims; i++) (void)rd_be32(fp); /* dimids */
    tag = rd_be32(fp);
    if (tag != NC_ATTRIBUTE) { fclose(fp); w_raise(w_string("netcdf_read: expected vatt")); return W_NIL; }
    na = rd_be32(fp);
    if (na != 0) { fclose(fp); w_raise(w_string("netcdf_read: var atts not supported")); return W_NIL; }
    uint32_t nctype = rd_be32(fp);
    (void)rd_be32(fp); /* vsize */
    uint32_t begin = rd_be32(fp);
    if (nctype != NC_FLOAT) { fclose(fp); w_raise(w_string("netcdf_read: only NC_FLOAT")); return W_NIL; }
    fseek(fp, (long)begin, SEEK_SET);
    WValue arr = w_array_new(65, dimlen);
    WArray *a = (WArray *)w_as_ptr(arr);
    for (uint32_t i = 0; i < dimlen; i++) {
        uint32_t u = rd_be32(fp);
        float f;
        memcpy(&f, &u, 4);
        ((WValue *)a->slots)[a->start + a->size] = w_float((double)f);
        a->size++;
    }
    fclose(fp);
    return arr;
}

/* =====================================================================
 * Foreign HDF5 subset (no libhdf5) — contiguous LE/BE numeric datasets
 * =====================================================================
 * After the 8-byte signature, if bytes@16 are TH5C/TH5D, the fast Tungsten
 * path is used. Otherwise we walk a real superblock → root group → links →
 * object headers for:
 *   - contiguous layouts (no filters / chunks)
 *   - IEEE f32/f64 and fixed-width integers (1/2/4/8)
 *   - symbol-table groups (old format) and compact link messages (OHDR v2)
 * TH5C/TH5D writers stay byte-stable.
 */

#define H5_UNDEF_ADDR_U64  ((uint64_t)0xFFFFFFFFFFFFFFFFULL)

typedef struct {
    FILE *fp;
    int so;           /* size of offsets */
    int sl;           /* size of lengths */
    uint64_t root_oh; /* root group object header address */
    int super_ver;
} H5File;

typedef struct {
    char name[256];
    uint64_t oh_addr;
} H5Link;

typedef struct {
    int rank;
    uint64_t dims[8];
    uint64_t nelem;
    int type_class;   /* 0=int 1=float */
    int type_size;
    int little_endian;
    int signed_int;
    int layout;       /* 0=compact 1=contiguous 2=chunked */
    uint64_t data_addr;
    uint64_t data_size;
} H5Dataset;

static int h5_read_u8(FILE *fp, uint8_t *v) {
    return fread(v, 1, 1, fp) == 1;
}
static int h5_read_u16le(FILE *fp, uint16_t *v) {
    unsigned char b[2];
    if (fread(b, 1, 2, fp) != 2) return 0;
    *v = (uint16_t)b[0] | ((uint16_t)b[1] << 8);
    return 1;
}
static int h5_read_u32le(FILE *fp, uint32_t *v) {
    unsigned char b[4];
    if (fread(b, 1, 4, fp) != 4) return 0;
    *v = (uint32_t)b[0] | ((uint32_t)b[1] << 8) |
         ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
    return 1;
}
static int h5_read_u64le(FILE *fp, uint64_t *v) {
    unsigned char b[8];
    if (fread(b, 1, 8, fp) != 8) return 0;
    *v = (uint64_t)b[0] | ((uint64_t)b[1] << 8) | ((uint64_t)b[2] << 16) |
         ((uint64_t)b[3] << 24) | ((uint64_t)b[4] << 32) | ((uint64_t)b[5] << 40) |
         ((uint64_t)b[6] << 48) | ((uint64_t)b[7] << 56);
    return 1;
}
static int h5_read_addr(FILE *fp, int so, uint64_t *addr) {
    unsigned char b[8];
    int i;
    if (so < 1 || so > 8) return 0;
    memset(b, 0, 8);
    if (fread(b, 1, (size_t)so, fp) != (size_t)so) return 0;
    *addr = 0;
    for (i = 0; i < so; i++)
        *addr |= ((uint64_t)b[i]) << (8 * i);
    /* all-0xFF is undefined */
    if (so == 8 && *addr == H5_UNDEF_ADDR_U64) return 1;
    {
        int all_ff = 1;
        for (i = 0; i < so; i++) if (b[i] != 0xFF) { all_ff = 0; break; }
        if (all_ff) *addr = H5_UNDEF_ADDR_U64;
    }
    return 1;
}
static int h5_read_length(FILE *fp, int sl, uint64_t *len) {
    return h5_read_addr(fp, sl, len);
}
static int h5_seek(FILE *fp, uint64_t off) {
    return fseeko(fp, (off_t)off, SEEK_SET) == 0;
}

/* Detect TH5 fast path magic at offset 16. Returns 1=TH5C, 2=TH5D, 0=foreign. */
static int h5_th5_magic(FILE *fp) {
    unsigned char m[4];
    if (!h5_seek(fp, 16)) return 0;
    if (fread(m, 1, 4, fp) != 4) return 0;
    if (memcmp(m, "TH5C", 4) == 0) return 1;
    if (memcmp(m, "TH5D", 4) == 0) return 2;
    return 0;
}

static int h5_open(const char *path, H5File *hf) {
    unsigned char sb[128];
    size_t got;
    uint64_t base_addr = 0, eof_addr = 0, root_ste = 0;
    memset(hf, 0, sizeof(*hf));
    hf->fp = fopen(path, "rb");
    if (!hf->fp) return 0;
    got = fread(sb, 1, sizeof(sb), hf->fp);
    if (got < 16 || memcmp(sb, "\x89HDF\r\n\x1a\n", 8) != 0) {
        fclose(hf->fp); hf->fp = NULL; return 0;
    }
    hf->super_ver = sb[8];
    if (hf->super_ver == 0 || hf->super_ver == 1) {
        if (got < 24) { fclose(hf->fp); hf->fp = NULL; return 0; }
        hf->so = sb[13];
        hf->sl = sb[14];
        if (hf->so < 1 || hf->so > 8 || hf->sl < 1 || hf->sl > 8) {
            fclose(hf->fp); hf->fp = NULL; return 0;
        }
        /* superblock body starts at offset 24: base, free, EOF, driver, root STE */
        if (!h5_seek(hf->fp, 24)) { fclose(hf->fp); hf->fp = NULL; return 0; }
        if (!h5_read_addr(hf->fp, hf->so, &base_addr)) { fclose(hf->fp); hf->fp = NULL; return 0; }
        if (!h5_read_addr(hf->fp, hf->so, &eof_addr)) { fclose(hf->fp); hf->fp = NULL; return 0; } /* free space */
        if (!h5_read_addr(hf->fp, hf->so, &eof_addr)) { fclose(hf->fp); hf->fp = NULL; return 0; }
        if (!h5_read_addr(hf->fp, hf->so, &eof_addr)) { fclose(hf->fp); hf->fp = NULL; return 0; } /* driver */
        /* Root group symbol table entry: link name offset (SO) + object header addr (SO) */
        if (!h5_read_addr(hf->fp, hf->so, &root_ste)) { fclose(hf->fp); hf->fp = NULL; return 0; } /* unused name */
        if (!h5_read_addr(hf->fp, hf->so, &hf->root_oh)) { fclose(hf->fp); hf->fp = NULL; return 0; }
        (void)base_addr;
    } else if (hf->super_ver == 2 || hf->super_ver == 3) {
        if (got < 12) { fclose(hf->fp); hf->fp = NULL; return 0; }
        hf->so = sb[9];
        hf->sl = sb[10];
        if (hf->so < 1 || hf->so > 8 || hf->sl < 1 || hf->sl > 8) {
            fclose(hf->fp); hf->fp = NULL; return 0;
        }
        /* v2: file space strategy (1), free space pers (1), page size (1) reserved then
         * base, super extension, EOF, root group OH address, checksum. */
        if (!h5_seek(hf->fp, 15)) { fclose(hf->fp); hf->fp = NULL; return 0; }
        if (!h5_read_addr(hf->fp, hf->so, &base_addr)) { fclose(hf->fp); hf->fp = NULL; return 0; }
        if (!h5_read_addr(hf->fp, hf->so, &eof_addr)) { fclose(hf->fp); hf->fp = NULL; return 0; } /* super ext */
        if (!h5_read_addr(hf->fp, hf->so, &eof_addr)) { fclose(hf->fp); hf->fp = NULL; return 0; }
        if (!h5_read_addr(hf->fp, hf->so, &hf->root_oh)) { fclose(hf->fp); hf->fp = NULL; return 0; }
        (void)base_addr; (void)eof_addr;
    } else {
        fclose(hf->fp); hf->fp = NULL; return 0;
    }
    if (hf->root_oh == 0 || hf->root_oh == H5_UNDEF_ADDR_U64) {
        fclose(hf->fp); hf->fp = NULL; return 0;
    }
    return 1;
}

static void h5_close(H5File *hf) {
    if (hf->fp) fclose(hf->fp);
    hf->fp = NULL;
}

/* Parse datatype message body into ds. */
static int h5_parse_datatype(const unsigned char *p, size_t n, H5Dataset *ds) {
    uint8_t class_and_ver, size_bits;
    uint32_t class_bitfield = 0;
    if (n < 8) return 0;
    class_and_ver = p[0];
    ds->type_class = class_and_ver & 0x0F; /* 0 fixed-point, 1 floating-point */
    /* size in bytes is last 4 bytes of first 8-byte header as LE u32? Actually
     * bytes 4..7 are size. */
    ds->type_size = (int)(p[4] | (p[5] << 8) | (p[6] << 16) | (p[7] << 24));
    if (ds->type_size <= 0 || ds->type_size > 16) return 0;
    class_bitfield = (uint32_t)p[1] | ((uint32_t)p[2] << 8) | ((uint32_t)p[3] << 16);
    /* bit 0 of class bitfield: little-endian for both fixed and float */
    ds->little_endian = (class_bitfield & 0x1) ? 1 : 0;
    if (ds->type_class == 0) {
        /* fixed-point: bit 3 of class bitfield = signed */
        ds->signed_int = (class_bitfield & 0x8) ? 1 : 0;
    } else if (ds->type_class == 1) {
        ds->signed_int = 1;
    } else {
        return 0; /* only int/float for now */
    }
    (void)size_bits;
    return 1;
}

static int h5_parse_dataspace(const unsigned char *p, size_t n, H5Dataset *ds) {
    uint8_t ver, dim_flags;
    int i;
    const unsigned char *q;
    if (n < 4) return 0;
    ver = p[0];
    ds->rank = p[1];
    dim_flags = p[2];
    if (ds->rank < 0 || ds->rank > 8) return 0;
    if (ver == 1) {
        q = p + 8; /* version, rank, flags, reserved, type? then dims */
        if (n < (size_t)(8 + ds->rank * 8)) return 0;
    } else if (ver == 2) {
        q = p + 4;
        if (n < (size_t)(4 + ds->rank * 8)) return 0;
    } else {
        return 0;
    }
    ds->nelem = 1;
    for (i = 0; i < ds->rank; i++) {
        uint64_t d = 0;
        int j;
        for (j = 0; j < 8; j++) d |= ((uint64_t)q[i * 8 + j]) << (8 * j);
        ds->dims[i] = d;
        if (d != 0 && ds->nelem > (UINT64_MAX / d)) return 0;
        ds->nelem *= (d == 0 ? 0 : d);
    }
    (void)dim_flags;
    return 1;
}

static int h5_parse_layout(const unsigned char *p, size_t n, H5Dataset *ds, int so) {
    uint8_t ver, cls;
    if (n < 2) return 0;
    ver = p[0];
    cls = p[1];
    ds->layout = cls; /* 0 compact, 1 contiguous, 2 chunked */
    if (cls == 1) {
        /* contiguous */
        if (ver == 3) {
            /* address then size */
            if (n < (size_t)(2 + so + 8)) return 0;
            {
                int i;
                ds->data_addr = 0;
                for (i = 0; i < so; i++)
                    ds->data_addr |= ((uint64_t)p[2 + i]) << (8 * i);
                ds->data_size = 0;
                for (i = 0; i < 8; i++)
                    ds->data_size |= ((uint64_t)p[2 + so + i]) << (8 * i);
            }
            return 1;
        } else if (ver == 1 || ver == 2) {
            /* dim sizes then address — skip dim*8 after 2-byte header + compact? */
            /* v1: version, class, reserved(6), address(so), size? simplified skip */
            if (n < (size_t)(8 + so)) return 0;
            {
                int i;
                const unsigned char *q = p + 8;
                ds->data_addr = 0;
                for (i = 0; i < so; i++)
                    ds->data_addr |= ((uint64_t)q[i]) << (8 * i);
                ds->data_size = 0; /* filled from nelem*type_size later */
            }
            return 1;
        }
    } else if (cls == 0) {
        /* compact — data follows size field; not prioritized */
        return 0;
    }
    return 0; /* chunked unsupported in this slice */
}

/* Walk one object header; if dataset fill *ds; if group collect links. */
static int h5_walk_oh(H5File *hf, uint64_t oh_addr, H5Dataset *ds_out,
                      H5Link *links, int max_links, int *n_links, int want_dataset) {
    unsigned char hdr[16];
    uint8_t ver;
    int msg_count = 0;
    uint64_t header_size = 0;
    uint64_t pos;
    int i;

    if (!h5_seek(hf->fp, oh_addr)) return 0;
    if (fread(hdr, 1, 16, hf->fp) < 4) return 0;
    ver = hdr[0];

    if (ver == 1) {
        /* v1: ver, reserved, nmsgs(u16), refcount(u32), header_size(u32) pad to 8 */
        msg_count = hdr[2] | (hdr[3] << 8);
        header_size = (uint64_t)hdr[8] | ((uint64_t)hdr[9] << 8) |
                      ((uint64_t)hdr[10] << 16) | ((uint64_t)hdr[11] << 24);
        pos = oh_addr + 16; /* after 12-byte header + 4 pad? Actually 12 then pad to 8 → 16 */
        if (header_size == 0) header_size = 256;
    } else if (ver == 2) {
        /* v2: 'O' 'H' 'D' 'R' signature optional — some files start with ver=2 without magic
         * Format: signature 4, ver, flags, (opt times), (opt nmsgs or size), messages */
        /* Standard v2 without prefix at this address: byte0=2, flags, … */
        uint8_t flags = hdr[1];
        pos = oh_addr + 6; /* ver + flags + chunk size(u32)? Wait: ver(1)+flags(1)+chunk_size(4)=6 */
        /* Actually: Version(1), Flags(1), optional fields, then chunk size u32 of first chunk */
        pos = oh_addr + 2;
        if (flags & 0x20) pos += 16; /* access/mod/change/birth times */
        if (flags & 0x10) pos += 2;  /* max compact / min dense */
        if (flags & 0x10) pos += 2;
        /* chunk size */
        if (!h5_seek(hf->fp, pos)) return 0;
        {
            uint32_t chunk_sz = 0;
            if (!h5_read_u32le(hf->fp, &chunk_sz)) return 0;
            header_size = chunk_sz;
            pos += 4;
        }
        msg_count = 64; /* walk by size until chunk exhausted */
        if (flags & 0x04) {
            /* creation order tracked — still OK */
        }
    } else {
        /* Maybe OHDR signature at address */
        if (memcmp(hdr, "OHDR", 4) == 0) {
            ver = hdr[4];
            if (ver != 2) return 0;
            {
                uint8_t flags = hdr[5];
                pos = oh_addr + 6;
                if (flags & 0x20) pos += 16;
                if (flags & 0x10) pos += 4;
                if (!h5_seek(hf->fp, pos)) return 0;
                {
                    uint32_t chunk_sz = 0;
                    if (!h5_read_u32le(hf->fp, &chunk_sz)) return 0;
                    header_size = chunk_sz;
                    pos += 4;
                }
                msg_count = 64;
            }
        } else {
            return 0;
        }
    }

    if (ds_out) memset(ds_out, 0, sizeof(*ds_out));
    if (n_links) *n_links = 0;

    for (i = 0; i < msg_count; i++) {
        unsigned char mhdr[8];
        uint16_t mtype, msize;
        uint8_t mflags;
        unsigned char body[4096];
        size_t to_read;

        if (ver == 2 || (hdr[0] == 'O')) {
            /* v2 message: type u8, size u16, flags u8 */
            if (!h5_seek(hf->fp, pos)) break;
            if (fread(mhdr, 1, 4, hf->fp) != 4) break;
            mtype = mhdr[0];
            msize = (uint16_t)mhdr[1] | ((uint16_t)mhdr[2] << 8);
            mflags = mhdr[3];
            pos += 4;
            /* shared message? */
            if (mflags & 0x02) {
                pos += msize;
                continue;
            }
        } else {
            /* v1 message: type u16, size u16, flags u8, reserved 3 */
            if (!h5_seek(hf->fp, pos)) break;
            if (fread(mhdr, 1, 8, hf->fp) != 8) break;
            mtype = (uint16_t)mhdr[0] | ((uint16_t)mhdr[1] << 8);
            msize = (uint16_t)mhdr[2] | ((uint16_t)mhdr[3] << 8);
            mflags = mhdr[4];
            pos += 8;
            (void)mflags;
        }
        if (msize == 0 && mtype == 0) break; /* NIL */
        to_read = msize;
        if (to_read > sizeof(body)) to_read = sizeof(body);
        if (!h5_seek(hf->fp, pos)) break;
        if (fread(body, 1, to_read, hf->fp) != to_read) break;
        pos += msize;
        /* pad v1 messages to 8-byte boundary */
        if (ver == 1) {
            uint64_t pad = (8 - (msize % 8)) % 8;
            pos += pad;
        }

        if (mtype == 0x0001 || mtype == 1) {
            /* Dataspace */
            if (want_dataset && ds_out)
                h5_parse_dataspace(body, to_read, ds_out);
        } else if (mtype == 0x0003 || mtype == 3) {
            /* Datatype */
            if (want_dataset && ds_out)
                h5_parse_datatype(body, to_read, ds_out);
        } else if (mtype == 0x0008 || mtype == 8) {
            /* Data layout */
            if (want_dataset && ds_out)
                h5_parse_layout(body, to_read, ds_out, hf->so);
        } else if (mtype == 0x0011 || mtype == 17) {
            /* Symbol table message (group, old format) */
            if (!want_dataset && links && n_links) {
                /* body: btree address (so) + heap address (so) */
                uint64_t btree_addr = 0, heap_addr = 0;
                int j;
                if (to_read < (size_t)(hf->so * 2)) continue;
                for (j = 0; j < hf->so; j++)
                    btree_addr |= ((uint64_t)body[j]) << (8 * j);
                for (j = 0; j < hf->so; j++)
                    heap_addr |= ((uint64_t)body[hf->so + j]) << (8 * j);
                /* Walk B-tree v1 group node: signature "TREE", type, level, entries */
                if (h5_seek(hf->fp, btree_addr)) {
                    unsigned char th[8];
                    if (fread(th, 1, 8, hf->fp) == 8 && memcmp(th, "TREE", 4) == 0) {
                        uint16_t entries = (uint16_t)th[6] | ((uint16_t)th[7] << 8);
                        uint8_t node_type = th[4];
                        uint64_t entry_pos = btree_addr + 8 + hf->so * 2; /* after left/right sibling */
                        int e;
                        if (node_type != 0) continue; /* only group nodes */
                        for (e = 0; e < entries && *n_links < max_links; e++) {
                            uint64_t key_offset = 0, obj_oh = 0;
                            char namebuf[256];
                            int k;
                            if (!h5_seek(hf->fp, entry_pos)) break;
                            /* key: local heap offset (sl?) then child pointer for internal;
                             * leaf: heap offset + symbol table entry */
                            if (!h5_read_length(hf->fp, hf->sl, &key_offset)) break;
                            /* symbol table entry: link name offset already as key in some;
                             * for leaf nodes of type 0: each entry is SO heap offset + STE */
                            /* STE: name offset SO, oh addr SO, cache type u32, reserved u4, scratch 16 */
                            if (!h5_read_addr(hf->fp, hf->so, &obj_oh)) break;
                            /* Actually leaf layout is: key (heap offset sl) then pointer (child so)
                             * for level 0 group, "pointer" is the symbol table entry address? */
                            /* Simpler: treat second field as object header address of member. */
                            entry_pos += (uint64_t)hf->sl + (uint64_t)hf->so;
                            /* Read name from local heap */
                            if (heap_addr != H5_UNDEF_ADDR_U64 && h5_seek(hf->fp, heap_addr)) {
                                unsigned char hh[16];
                                uint64_t data_seg = 0;
                                if (fread(hh, 1, 16, hf->fp) == 16 && memcmp(hh, "HEAP", 4) == 0) {
                                    for (k = 0; k < hf->so; k++)
                                        data_seg |= ((uint64_t)hh[8 + k]) << (8 * k);
                                    if (h5_seek(hf->fp, data_seg + key_offset)) {
                                        size_t ni = 0;
                                        int c;
                                        while (ni + 1 < sizeof(namebuf) && (c = fgetc(hf->fp)) != EOF && c != 0)
                                            namebuf[ni++] = (char)c;
                                        namebuf[ni] = 0;
                                        if (ni > 0 && obj_oh != 0 && obj_oh != H5_UNDEF_ADDR_U64) {
                                            strncpy(links[*n_links].name, namebuf, 255);
                                            links[*n_links].name[255] = 0;
                                            links[*n_links].oh_addr = obj_oh;
                                            (*n_links)++;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } else if (mtype == 0x0006 || mtype == 6) {
            /* Link message (compact group) */
            if (!want_dataset && links && n_links && *n_links < max_links) {
                uint8_t lver, lflags, name_len = 0;
                uint64_t target = 0;
                char namebuf[256];
                size_t off = 0;
                if (to_read < 2) continue;
                lver = body[0];
                lflags = body[1];
                off = 2;
                if (lver != 1) continue;
                if (lflags & 0x01) off += 8; /* creation order */
                if (lflags & 0x02) off += 1; /* link type length? link type follows */
                /* link type u8 */
                if (off >= to_read) continue;
                {
                    uint8_t ltype = body[off++];
                    if (ltype != 0) continue; /* hard link only */
                }
                if (lflags & 0x08) {
                    /* name charset */
                    if (off >= to_read) continue;
                    off++;
                }
                /* name length: if flag 0x10 present use u8 else u8 still for short */
                if (lflags & 0x10) {
                    if (off >= to_read) continue;
                    name_len = body[off++];
                } else {
                    /* encoded length as u8 when size small — try u8 */
                    if (off >= to_read) continue;
                    name_len = body[off++];
                }
                if (off + (size_t)name_len > to_read || (size_t)name_len >= sizeof(namebuf)) continue;
                memcpy(namebuf, body + off, name_len);
                namebuf[name_len] = 0;
                off += name_len;
                if (off + (size_t)hf->so > to_read) continue;
                {
                    int j;
                    for (j = 0; j < hf->so; j++)
                        target |= ((uint64_t)body[off + j]) << (8 * j);
                }
                if (target != 0 && target != H5_UNDEF_ADDR_U64) {
                    strncpy(links[*n_links].name, namebuf, 255);
                    links[*n_links].name[255] = 0;
                    links[*n_links].oh_addr = target;
                    (*n_links)++;
                }
            }
        }
        /* stop when past header chunk for v2 */
        if (ver != 1 && header_size > 0 && (pos - oh_addr) > header_size + 32)
            break;
    }

    if (want_dataset && ds_out) {
        if (ds_out->data_size == 0 && ds_out->nelem > 0 && ds_out->type_size > 0)
            ds_out->data_size = ds_out->nelem * (uint64_t)ds_out->type_size;
        return ds_out->layout == 1 && ds_out->data_addr != 0 && ds_out->nelem > 0;
    }
    return 1;
}

static WValue h5_read_dataset_values(H5File *hf, H5Dataset *ds) {
    uint64_t n = ds->nelem;
    WValue arr;
    WArray *a;
    uint64_t i;
    if (n > 100000000ULL) {
        w_raise(w_string("hdf5: dataset too large"));
        return W_NIL;
    }
    if (!h5_seek(hf->fp, ds->data_addr)) {
        w_raise(w_string("hdf5: seek data failed"));
        return W_NIL;
    }
    arr = w_array_new(65, (int64_t)n);
    a = (WArray *)w_as_ptr(arr);
    for (i = 0; i < n; i++) {
        unsigned char b[16];
        if (fread(b, 1, (size_t)ds->type_size, hf->fp) != (size_t)ds->type_size) break;
        if (ds->type_class == 1) {
            /* float */
            if (ds->type_size == 4) {
                float f;
                if (ds->little_endian)
                    memcpy(&f, b, 4);
                else {
                    unsigned char r[4] = { b[3], b[2], b[1], b[0] };
                    memcpy(&f, r, 4);
                }
                ((WValue *)a->slots)[a->start + a->size] = w_float((double)f);
                a->size++;
            } else if (ds->type_size == 8) {
                double d;
                if (ds->little_endian)
                    memcpy(&d, b, 8);
                else {
                    unsigned char r[8] = { b[7], b[6], b[5], b[4], b[3], b[2], b[1], b[0] };
                    memcpy(&d, r, 8);
                }
                ((WValue *)a->slots)[a->start + a->size] = w_float(d);
                a->size++;
            }
        } else {
            /* integer → boxed int */
            int64_t v = 0;
            int s = ds->type_size;
            if (ds->little_endian) {
                int j;
                for (j = 0; j < s; j++) v |= ((int64_t)b[j]) << (8 * j);
            } else {
                int j;
                for (j = 0; j < s; j++) v = (v << 8) | b[j];
            }
            if (ds->signed_int && s < 8) {
                int shift = 64 - 8 * s;
                v = (v << shift) >> shift;
            }
            ((WValue *)a->slots)[a->start + a->size] = w_int(v);
            a->size++;
        }
    }
    return arr;
}

/* List names from foreign HDF5 root group (and one level of nesting as path). */
static WValue h5_foreign_list(const char *path) {
    H5File hf;
    H5Link links[256];
    int n = 0, i;
    WValue arr;
    WArray *a;
    if (!h5_open(path, &hf)) {
        w_raise(w_string("hdf5_list: cannot open foreign HDF5"));
        return W_NIL;
    }
    h5_walk_oh(&hf, hf.root_oh, NULL, links, 256, &n, 0);
    arr = w_array_new(65, n > 0 ? n : 1);
    a = (WArray *)w_as_ptr(arr);
    for (i = 0; i < n; i++) {
        ((WValue *)a->slots)[a->start + a->size] = w_string(links[i].name);
        a->size++;
    }
    h5_close(&hf);
    return arr;
}

static WValue h5_foreign_read_named(const char *path, const char *want) {
    H5File hf;
    H5Link links[256];
    int n = 0, i;
    H5Dataset ds;
    WValue out;
    if (!h5_open(path, &hf)) {
        w_raise(w_string("hdf5_read_named: cannot open foreign HDF5"));
        return W_NIL;
    }
    h5_walk_oh(&hf, hf.root_oh, NULL, links, 256, &n, 0);
    for (i = 0; i < n; i++) {
        if (strcmp(links[i].name, want) == 0) {
            if (h5_walk_oh(&hf, links[i].oh_addr, &ds, NULL, 0, NULL, 1)) {
                out = h5_read_dataset_values(&hf, &ds);
                h5_close(&hf);
                return out;
            }
            /* Maybe nested group — not found as dataset */
            break;
        }
    }
    /* Also try reading root itself as dataset (rare) */
    if (strcmp(want, "data") == 0 || strcmp(want, "/") == 0) {
        if (h5_walk_oh(&hf, hf.root_oh, &ds, NULL, 0, NULL, 1)) {
            out = h5_read_dataset_values(&hf, &ds);
            h5_close(&hf);
            return out;
        }
    }
    h5_close(&hf);
    w_raise(w_string("hdf5_read_named: dataset not found (foreign OHDR)"));
    return W_NIL;
}

/* Write a minimal valid foreign-style HDF5 v0 file with one contiguous f32
 * dataset "data" — for specs without h5py. Not a full OHDR writer; uses the
 * same TH5C path for write, and a separate generator for foreign fixtures. */

/* ---- Mini contiguous "HDF5-flavored" f32 blob for round-trip tests ----
 * File layout (self-describing, sniffs as HDF5 via signature):
 *   0:  8-byte HDF5 signature
 *   8:  superblock version = 0
 *   9..15: zeros
 *   16: "TH5C" magic (Tungsten HDF5 Contiguous)
 *   20: u32 LE nelem
 *   24: nelem × f32 LE
 * Real HDF5 tools won't read the dataset body; our SciIO will.
 */
WValue w_sci_hdf5_write_f32_1d(WValue path_wv, WValue data_wv) {
    char path[1024];
    sci_path(path_wv, path, sizeof(path));
    if (!w_is_array(data_wv)) {
        w_raise(w_string("hdf5_write: data must be Array"));
        return W_NIL;
    }
    WArray *a = (WArray *)w_as_ptr(data_wv);
    int64_t n = a->size;
    FILE *fp = fopen(path, "wb");
    if (!fp) { w_raise(w_string("hdf5_write: open failed")); return W_NIL; }
    fwrite("\x89HDF\r\n\x1a\n", 1, 8, fp);
    fputc(0, fp); /* superblock version */
    for (int i = 0; i < 7; i++) fputc(0, fp);
    fwrite("TH5C", 1, 4, fp);
    uint32_t nu = (uint32_t)n;
    fwrite(&nu, 4, 1, fp); /* LE host */
    for (int64_t i = 0; i < n; i++) {
        float f = (float)w_as_double(((WValue *)a->slots)[a->start + i]);
        fwrite(&f, 4, 1, fp);
    }
    fclose(fp);
    return w_int(1);
}

WValue w_sci_hdf5_read_f32_1d(WValue path_wv) {
    char path[1024];
    sci_path(path_wv, path, sizeof(path));
    FILE *fp = fopen(path, "rb");
    if (!fp) { w_raise(w_string("hdf5_read: open failed")); return W_NIL; }
    unsigned char hdr[24];
    if (fread(hdr, 1, 24, fp) != 24) {
        fclose(fp);
        w_raise(w_string("hdf5_read: short file"));
        return W_NIL;
    }
    if (memcmp(hdr, "\x89HDF\r\n\x1a\n", 8) != 0) {
        fclose(fp);
        w_raise(w_string("hdf5_read: not HDF5 signature"));
        return W_NIL;
    }
    if (memcmp(hdr + 16, "TH5C", 4) != 0) {
        fclose(fp);
        /* Foreign HDF5: try root-level dataset "data" via OHDR walker */
        {
            char path2[1024];
            sci_path(path_wv, path2, sizeof(path2));
            return h5_foreign_read_named(path2, "data");
        }
    }
    uint32_t n;
    memcpy(&n, hdr + 20, 4);
    WValue arr = w_array_new(65, n);
    WArray *a = (WArray *)w_as_ptr(arr);
    for (uint32_t i = 0; i < n; i++) {
        float f;
        if (fread(&f, 4, 1, fp) != 1) break;
        ((WValue *)a->slots)[a->start + a->size] = w_float((double)f);
        a->size++;
    }
    fclose(fp);
    return arr;
}

/* =====================================================================
 * Extended native formats (still no system libs)
 * ===================================================================== */

/* ---- TH5D: multi-named contiguous f32 datasets under HDF5 signature ----
 * Layout after 16-byte stub (sig+ver+pad):
 *   "TH5D"
 *   u32 LE n_datasets
 *   repeated:
 *     u32 LE name_len
 *     name bytes (no null)
 *     u32 LE nelem
 *     nelem × f32 LE
 */

static int write_u32_le(FILE *fp, uint32_t v) {
    return fwrite(&v, 4, 1, fp) == 1;
}
static int read_u32_le(FILE *fp, uint32_t *v) {
    return fread(v, 4, 1, fp) == 1;
}

WValue w_sci_hdf5_write_datasets(WValue path_wv, WValue names_wv, WValue arrays_wv) {
    /* names: Array of String; arrays: Array of Array of Float — same length */
    char path[1024];
    sci_path(path_wv, path, sizeof(path));
    if (!w_is_array(names_wv) || !w_is_array(arrays_wv)) {
        w_raise(w_string("hdf5_write_datasets: need names[] and arrays[]"));
        return W_NIL;
    }
    WArray *names = (WArray *)w_as_ptr(names_wv);
    WArray *arrays = (WArray *)w_as_ptr(arrays_wv);
    if (names->size != arrays->size) {
        w_raise(w_string("hdf5_write_datasets: names/arrays length mismatch"));
        return W_NIL;
    }
    FILE *fp = fopen(path, "wb");
    if (!fp) { w_raise(w_string("hdf5_write_datasets: open failed")); return W_NIL; }
    fwrite("\x89HDF\r\n\x1a\n", 1, 8, fp);
    fputc(0, fp);
    for (int i = 0; i < 7; i++) fputc(0, fp);
    fwrite("TH5D", 1, 4, fp);
    write_u32_le(fp, (uint32_t)names->size);
    for (int32_t di = 0; di < names->size; di++) {
        WValue nv = ((WValue *)names->slots)[names->start + di];
        char nbuf[256];
        sci_path(nv, nbuf, sizeof(nbuf)); /* strings work via w_str_data */
        uint32_t nlen = (uint32_t)strlen(nbuf);
        write_u32_le(fp, nlen);
        fwrite(nbuf, 1, nlen, fp);
        WValue av = ((WValue *)arrays->slots)[arrays->start + di];
        if (!w_is_array(av)) { fclose(fp); w_raise(w_string("hdf5_write_datasets: bad array")); return W_NIL; }
        WArray *a = (WArray *)w_as_ptr(av);
        write_u32_le(fp, (uint32_t)a->size);
        for (int32_t i = 0; i < a->size; i++) {
            float f = (float)w_as_double(((WValue *)a->slots)[a->start + i]);
            fwrite(&f, 4, 1, fp);
        }
    }
    fclose(fp);
    return w_int(1);
}

/* List dataset names → poly Array of String */
WValue w_sci_hdf5_list(WValue path_wv) {
    char path[1024];
    sci_path(path_wv, path, sizeof(path));
    FILE *fp = fopen(path, "rb");
    if (!fp) { w_raise(w_string("hdf5_list: open failed")); return W_NIL; }
    unsigned char hdr[20];
    if (fread(hdr, 1, 20, fp) != 20) { fclose(fp); w_raise(w_string("hdf5_list: short")); return W_NIL; }
    if (memcmp(hdr, "\x89HDF\r\n\x1a\n", 8) != 0) { fclose(fp); w_raise(w_string("hdf5_list: not HDF5")); return W_NIL; }
    if (memcmp(hdr + 16, "TH5D", 4) != 0) {
        /* TH5C single anonymous: report "data" */
        if (memcmp(hdr + 16, "TH5C", 4) == 0) {
            fclose(fp);
            WValue arr = w_array_new(65, 1);
            WArray *a = (WArray *)w_as_ptr(arr);
            ((WValue *)a->slots)[0] = w_string("data");
            a->size = 1;
            return arr;
        }
        fclose(fp);
        /* Foreign HDF5 OHDR walk */
        {
            char path2[1024];
            sci_path(path_wv, path2, sizeof(path2));
            return h5_foreign_list(path2);
        }
    }
    uint32_t nd = 0;
    if (!read_u32_le(fp, &nd)) { fclose(fp); return W_NIL; }
    WValue arr = w_array_new(65, nd);
    WArray *a = (WArray *)w_as_ptr(arr);
    for (uint32_t i = 0; i < nd; i++) {
        uint32_t nlen = 0;
        if (!read_u32_le(fp, &nlen) || nlen > 1024) { fclose(fp); break; }
        char name[1025];
        if (fread(name, 1, nlen, fp) != nlen) { fclose(fp); break; }
        name[nlen] = 0;
        uint32_t ne = 0;
        if (!read_u32_le(fp, &ne)) { fclose(fp); break; }
        fseek(fp, (long)ne * 4, SEEK_CUR);
        ((WValue *)a->slots)[a->start + a->size] = w_string(name);
        a->size++;
    }
    fclose(fp);
    return arr;
}

WValue w_sci_hdf5_read_named(WValue path_wv, WValue name_wv) {
    char path[1024], want[256];
    sci_path(path_wv, path, sizeof(path));
    sci_path(name_wv, want, sizeof(want));
    FILE *fp = fopen(path, "rb");
    if (!fp) { w_raise(w_string("hdf5_read_named: open failed")); return W_NIL; }
    unsigned char hdr[20];
    if (fread(hdr, 1, 20, fp) != 20) { fclose(fp); w_raise(w_string("hdf5_read_named: short")); return W_NIL; }
    if (memcmp(hdr + 16, "TH5C", 4) == 0) {
        /* single anonymous dataset named "data" */
        fclose(fp);
        if (strcmp(want, "data") != 0) {
            w_raise(w_string("hdf5_read_named: TH5C only has 'data'"));
            return W_NIL;
        }
        return w_sci_hdf5_read_f32_1d(path_wv);
    }
    if (memcmp(hdr + 16, "TH5D", 4) != 0) {
        fclose(fp);
        {
            char path2[1024], want2[256];
            sci_path(path_wv, path2, sizeof(path2));
            sci_path(name_wv, want2, sizeof(want2));
            return h5_foreign_read_named(path2, want2);
        }
    }
    uint32_t nd = 0;
    if (!read_u32_le(fp, &nd)) { fclose(fp); return W_NIL; }
    for (uint32_t i = 0; i < nd; i++) {
        uint32_t nlen = 0;
        if (!read_u32_le(fp, &nlen) || nlen > 1024) break;
        char name[1025];
        if (fread(name, 1, nlen, fp) != nlen) break;
        name[nlen] = 0;
        uint32_t ne = 0;
        if (!read_u32_le(fp, &ne)) break;
        if (strcmp(name, want) == 0) {
            WValue arr = w_array_new(65, ne);
            WArray *a = (WArray *)w_as_ptr(arr);
            for (uint32_t j = 0; j < ne; j++) {
                float f;
                if (fread(&f, 4, 1, fp) != 1) break;
                ((WValue *)a->slots)[a->start + a->size] = w_float((double)f);
                a->size++;
            }
            fclose(fp);
            return arr;
        }
        fseek(fp, (long)ne * 4, SEEK_CUR);
    }
    fclose(fp);
    w_raise(w_string("hdf5_read_named: dataset not found"));
    return W_NIL;
}

/* ---- Parquet PLAIN f32 column (TPAR) ----
 * PAR1
 * "TPAR"
 * u32 LE ncols
 * for each col:
 *   u32 name_len, name, u32 n, n × f32 LE (PLAIN)
 * PAR1
 */
WValue w_sci_parquet_write_f32(WValue path_wv, WValue names_wv, WValue arrays_wv) {
    char path[1024];
    sci_path(path_wv, path, sizeof(path));
    WArray *names = (WArray *)w_as_ptr(names_wv);
    WArray *arrays = (WArray *)w_as_ptr(arrays_wv);
    FILE *fp = fopen(path, "wb");
    if (!fp) { w_raise(w_string("parquet_write: open failed")); return W_NIL; }
    fwrite("PAR1", 1, 4, fp);
    fwrite("TPAR", 1, 4, fp);
    write_u32_le(fp, (uint32_t)names->size);
    for (int32_t di = 0; di < names->size; di++) {
        char nbuf[256];
        sci_path(((WValue *)names->slots)[names->start + di], nbuf, sizeof(nbuf));
        uint32_t nlen = (uint32_t)strlen(nbuf);
        write_u32_le(fp, nlen);
        fwrite(nbuf, 1, nlen, fp);
        WArray *a = (WArray *)w_as_ptr(((WValue *)arrays->slots)[arrays->start + di]);
        write_u32_le(fp, (uint32_t)a->size);
        for (int32_t i = 0; i < a->size; i++) {
            float f = (float)w_as_double(((WValue *)a->slots)[a->start + i]);
            fwrite(&f, 4, 1, fp);
        }
    }
    fwrite("PAR1", 1, 4, fp);
    fclose(fp);
    return w_int(1);
}

WValue w_sci_parquet_read_f32(WValue path_wv, WValue name_wv) {
    char path[1024], want[256];
    sci_path(path_wv, path, sizeof(path));
    sci_path(name_wv, want, sizeof(want));
    FILE *fp = fopen(path, "rb");
    if (!fp) { w_raise(w_string("parquet_read: open failed")); return W_NIL; }
    char mag[8];
    if (fread(mag, 1, 8, fp) != 8 || memcmp(mag, "PAR1TPAR", 8) != 0) {
        fclose(fp);
        w_raise(w_string("parquet_read: need PAR1+TPAR (PLAIN subset)"));
        return W_NIL;
    }
    uint32_t nc = 0;
    if (!read_u32_le(fp, &nc)) { fclose(fp); return W_NIL; }
    for (uint32_t i = 0; i < nc; i++) {
        uint32_t nlen = 0;
        if (!read_u32_le(fp, &nlen) || nlen > 1024) break;
        char name[1025];
        if (fread(name, 1, nlen, fp) != nlen) break;
        name[nlen] = 0;
        uint32_t ne = 0;
        if (!read_u32_le(fp, &ne)) break;
        if (strcmp(name, want) == 0) {
            WValue arr = w_array_new(65, ne);
            WArray *a = (WArray *)w_as_ptr(arr);
            for (uint32_t j = 0; j < ne; j++) {
                float f;
                if (fread(&f, 4, 1, fp) != 1) break;
                ((WValue *)a->slots)[a->start + a->size] = w_float((double)f);
                a->size++;
            }
            fclose(fp);
            return arr;
        }
        fseek(fp, (long)ne * 4, SEEK_CUR);
    }
    fclose(fp);
    w_raise(w_string("parquet_read: column not found"));
    return W_NIL;
}

/* ---- Zarr 1-D f32 uncompressed ----
 * dir/
 *   .zarray  JSON (minimal)
 *   0        raw LE f32 chunk (entire array)
 */
WValue w_sci_zarr_write_f32_1d(WValue dir_wv, WValue data_wv) {
    char dir[1024];
    sci_path(dir_wv, dir, sizeof(dir));
    if (!w_is_array(data_wv)) {
        w_raise(w_string("zarr_write: data must be Array"));
        return W_NIL;
    }
    WArray *a = (WArray *)w_as_ptr(data_wv);
    /* mkdir */
    char cmd[1200];
    snprintf(cmd, sizeof(cmd), "mkdir -p '%s'", dir);
    if (system(cmd) != 0) {
        w_raise(w_string("zarr_write: mkdir failed"));
        return W_NIL;
    }
    char meta_path[1100], chunk_path[1100];
    snprintf(meta_path, sizeof(meta_path), "%s/.zarray", dir);
    snprintf(chunk_path, sizeof(chunk_path), "%s/0", dir);
    FILE *mf = fopen(meta_path, "w");
    if (!mf) { w_raise(w_string("zarr_write: .zarray open failed")); return W_NIL; }
    fprintf(mf,
        "{\n"
        "  \"zarr_format\": 2,\n"
        "  \"shape\": [%lld],\n"
        "  \"chunks\": [%lld],\n"
        "  \"dtype\": \"<f4\",\n"
        "  \"compressor\": null,\n"
        "  \"fill_value\": 0.0,\n"
        "  \"order\": \"C\",\n"
        "  \"filters\": null\n"
        "}\n",
        (long long)a->size, (long long)a->size);
    fclose(mf);
    FILE *cf = fopen(chunk_path, "wb");
    if (!cf) { w_raise(w_string("zarr_write: chunk open failed")); return W_NIL; }
    for (int32_t i = 0; i < a->size; i++) {
        float f = (float)w_as_double(((WValue *)a->slots)[a->start + i]);
        fwrite(&f, 4, 1, cf);
    }
    fclose(cf);
    return w_int(1);
}

WValue w_sci_zarr_read_f32_1d(WValue dir_wv) {
    char dir[1024];
    sci_path(dir_wv, dir, sizeof(dir));
    char chunk_path[1100];
    snprintf(chunk_path, sizeof(chunk_path), "%s/0", dir);
    FILE *cf = fopen(chunk_path, "rb");
    if (!cf) { w_raise(w_string("zarr_read: chunk 0 missing (uncompressed only)")); return W_NIL; }
    fseek(cf, 0, SEEK_END);
    long bytes = ftell(cf);
    fseek(cf, 0, SEEK_SET);
    if (bytes < 0 || bytes % 4 != 0) { fclose(cf); w_raise(w_string("zarr_read: bad size")); return W_NIL; }
    uint32_t n = (uint32_t)(bytes / 4);
    WValue arr = w_array_new(65, n);
    WArray *a = (WArray *)w_as_ptr(arr);
    for (uint32_t i = 0; i < n; i++) {
        float f;
        if (fread(&f, 4, 1, cf) != 1) break;
        ((WValue *)a->slots)[a->start + a->size] = w_float((double)f);
        a->size++;
    }
    fclose(cf);
    return arr;
}
