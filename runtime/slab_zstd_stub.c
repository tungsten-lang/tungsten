#include "runtime.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

/*
 * Link-compatible fallback for raw-intern bootstrap builds. The compiler
 * contains the optional zstd rewrite routine, so its native binary references
 * these symbols even when it is built and invoked with --intern raw. Keeping
 * the failure at the explicit zstd call site lets source bootstraps work on
 * minimal competition hosts without silently accepting compressed slabs.
 */
static _Noreturn void slab_zstd_unavailable(void) {
    fputs(
        "zstd slab support is unavailable; rebuild Tungsten with libzstd\n",
        stderr);
    abort();
}

void w_slab_init_static_zstd(
    const uint8_t *data, uint32_t compressed_bytes, uint32_t total_slots) {
    (void)data;
    (void)compressed_bytes;
    (void)total_slots;
    slab_zstd_unavailable();
}

WValue w_zstd_compress_llvm_escaped(WValue escaped_val) {
    (void)escaped_val;
    slab_zstd_unavailable();
}

/* Without libzstd there is no Zstd.compress: nil. */
WValue w_zstd_compress(WValue data_val, WValue level_val) {
    (void)data_val;
    (void)level_val;
    return W_NIL;
}

/* Without libzstd there is no Zstd.decompress: nil (not zstd we can read). */
WValue w_zstd_decompress(WValue data_val) {
    (void)data_val;
    return W_NIL;
}
