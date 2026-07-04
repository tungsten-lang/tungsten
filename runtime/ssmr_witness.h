#ifndef W_SSMR_WITNESS_H
#define W_SSMR_WITNESS_H
#include <stdint.h>
extern const uint16_t w_ssmr_witness[262144];
#define W_SSMR_HASH_MUL 811484239U
static inline uint32_t w_ssmr_bucket(uint64_t n) {
    return ((uint32_t)n * W_SSMR_HASH_MUL) >> 14;
}
#endif
