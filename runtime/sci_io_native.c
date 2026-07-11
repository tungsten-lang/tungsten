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
        w_raise(w_string("hdf5_read: not Tungsten contiguous f32 (TH5C); full OHDR walk TBD"));
        return W_NIL;
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
        w_raise(w_string("hdf5_list: need TH5D/TH5C (full OHDR walk TBD for foreign files)"));
        return W_NIL;
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
        w_raise(w_string("hdf5_read_named: not TH5D/TH5C"));
        return W_NIL;
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
