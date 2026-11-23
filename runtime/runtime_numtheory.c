#ifndef W_RUNTIME_UNITY_INCLUDE
#include "runtime_internal.h"
#include "ssmr_witness.h"
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
#ifdef __APPLE__
#include <sys/sysctl.h>
#endif
#if defined(__has_include)
#  if __has_include("generated/bigint_thresholds.h")
#    include "generated/bigint_thresholds.h"
#  endif
#endif
#ifndef BN_MUL_POWER2_FIXED
#ifdef __aarch64__
#define BN_MUL_POWER2_FIXED 1
#else
#define BN_MUL_POWER2_FIXED 0
#endif
#endif
#ifndef BN_ADDMUL_2
#ifdef __aarch64__
#define BN_ADDMUL_2 1
#else
#define BN_ADDMUL_2 0
#endif
#endif
#ifndef BN_MUL_EQ16_ADDMUL2
#ifdef __aarch64__
#define BN_MUL_EQ16_ADDMUL2 1
#else
#define BN_MUL_EQ16_ADDMUL2 0
#endif
#endif
#ifndef BN_POWM_REDC_ADDMUL2
#define BN_POWM_REDC_ADDMUL2 1
#endif
#define die w_rt_die
#define dief w_rt_dief
#define die_as w_rt_die_as
#define as_str w_rt_as_str
#define w_string_n w_rt_string_n
#define w_string_n_known_ascii w_rt_string_n_known_ascii
#define bigint_box w_rt_bigint_box
#define bn_copy_tail w_rt_bn_copy_tail
#define bigint_alloc w_rt_bigint_alloc
#define bigint_alloc_raw w_rt_bigint_alloc_raw
#define bigint_backing_free w_rt_bigint_backing_free
#define bigint_release w_rt_bigint_release
#define bigint_release_if_live w_rt_bigint_release_if_live
#define bigint_normalize w_rt_bigint_normalize
#define bigint_finish_mag_sub w_rt_bigint_finish_mag_sub
#define bigint_from_u64 w_rt_bigint_from_u64
#define integer_limbs w_rt_integer_limbs
#define integer_low_i64 w_rt_integer_low_i64
#define mag_cmp w_rt_mag_cmp
#define bn_add_n w_rt_bn_add_n
#define bn_sub_n w_rt_bn_sub_n
#define bn_mul_1 w_rt_bn_mul_1
#define bn_addmul_1 w_rt_bn_addmul_1
#define bn_addmul_2 w_rt_bn_addmul_2
#define bn_mul_2 w_rt_bn_mul_2
#define bn_addto w_rt_bn_addto
#define bigint_mul_dispatch w_rt_bigint_mul_dispatch
#define bigint_sqr_dispatch w_rt_bigint_sqr_dispatch
#define mag_mod_single w_rt_mag_mod_single
#define mag_divmod w_rt_mag_divmod
#define bn_cmp_n w_rt_bn_cmp_n
#define bn_mul_eq4_inline w_rt_bn_mul_eq4_inline
#define bn_mul_eq6_inline w_rt_bn_mul_eq6_inline
#define bn_mul_eq8_inline w_rt_bn_mul_eq8_inline
#define bn_sqr4_inline w_rt_bn_sqr4_inline
#define bn_sqr6_inline w_rt_bn_sqr6_inline
#define bn_sqr8_inline w_rt_bn_sqr8_inline
#define bn_sqr16_split w_rt_bn_sqr16_split
#ifdef __aarch64__
#define bn_add16_fixed w_rt_bn_add16_fixed
#define bn_sub16_fixed w_rt_bn_sub16_fixed
#endif
#endif

/* ---- Int#prime? — tiered deterministic primality ----
 * Integer literals are NaN-boxed primitives with no class pointer, so
 * `n.prime?` dispatches here through the Int IC table (exactly like gcd/sqrt)
 * rather than to the `.w` method body in core/numeric/int.w. Tiers, fastest-
 * first by magnitude:
 *   • small-prime screen   — trial by the primes ≤ 37; settles every n < 1681.
 *   • prime-factor scan    — up to √n, for n ≤ 10⁶, using exact reciprocal
 *     divisibility by prime candidates (no hardware division in the hot loop).
 *     Profiling selects a conservative, mixed-distribution 10⁶ boundary.
 *   • Miller-Rabin (u64)    — O(log n) Montgomery arithmetic (division-free): a
 *     single hashed Forišek–Jančina base for n < 2³² (one round, exact), then a
 *     minimal deterministic witness ladder (3→4→5→6→7 bases) up to 2⁶⁴.
 *   • BPSW (bigint)         — for n ≥ 2⁶⁴: 7-base Miller-Rabin on BigInt WValues
 *     THEN a strong Lucas test (Baillie-PSW). The MR witness set is deterministic
 *     — an exact proof — for every n < 3.317·10²⁴ (Sinclair); above that the
 *     strong Lucas pass makes it BPSW, which has no known counterexample at any
 *     size (the two tests fail on near-disjoint pseudoprime families).
 * Mersenne fast path: a bigint of the form 2^p-1 skips Miller-Rabin entirely
 * and takes the Lucas-Lehmer test (w_prime_test_lucas_lehmer) — one chain of
 * p-2 modular squarings with a division-free Mersenne reduction, exact at any
 * magnitude and ~25-30× faster than 7-base bigint MR at these sizes. */
static const uint64_t W_PRIME_MR_BASES[] = {2,325,9375,28178,450775,9780504,1795265022};
static const uint16_t W_PRIME_TRIAL_DIVISORS[] = {
    41,43,47,53,59,61,67,71,73,79,83,89,97,101,103,107,
    109,113,127,131,137,139,149,151,157,163,167,173,179,181,191,193,
    197,199,211,223,227,229,233,239,241,251,257,263,269,271,277,281,
    283,293,307,311,313,317,331,337,347,349,353,359,367,373,379,383,
    389,397,401,409,419,421,431,433,439,443,449,457,461,463,467,479,
    487,491,499,503,509,521,523,541,547,557,563,569,571,577,587,593,
    599,601,607,613,617,619,631,641,643,647,653,659,661,673,677,683,
    691,701,709,719,727,733,739,743,751,757,761,769,773,787,797,809,
    811,821,823,827,829,839,853,857,859,863,877,881,883,887,907,911,
    919,929,937,941,947,953,967,971,977,983,991,997,1009,1013,1019,1021,
    1031,1033,1039,1049,1051,1061,1063,1069,1087,1091,1093,1097,1103,1109,1117,1123,
    1129,1151,1153,1163,1171,1181,1187,1193,1201,1213,1217,1223,1229,1231,1237,1249,
    1259,1277,1279,1283,1289,1291,1297,1301,1303,1307,1319,1321,1327,1361,1367,1373,
    1381,1399,1409,1423,1427,1429,1433,1439,1447,1451,1453,1459,1471,1481,1483,1487,
    1489,1493,1499,1511,1523,1531,1543,1549,1553,1559,1567,1571,1579,1583,1597,1601,
    1607,1609,1613,1619,1621,1627,1637,1657,1663,1667,1669,1693,1697,1699,1709,1721,
    1723,1733,1741,1747,1753,1759,1777,1783,1787,1789,1801,1811,1823,1831,1847,1861,
    1867,1871,1873,1877,1879,1889,1901,1907,1913,1931,1933,1949,1951,1973,1979,1987,
    1993,1997,1999,2003,2011,2017,2027,2029,2039,2053,2063,2069,2081,2083,2087,2089,
    2099,2111,2113,2129,2131,2137,2141,2143,2153,2161,2179,2203,2207,2213,2221,2237,
    2239,2243,2251,2267,2269,2273,2281,2287,2293,2297,2309,2311,2333,2339,2341,2347,
    2351,2357,2371,2377,2381,2383,2389,2393,2399,2411,2417,2423,2437,2441,2447,2459,
    2467,2473,2477,2503,2521,2531,2539,2543,2549,2551,2557,2579,2591,2593,2609,2617,
    2621,2633,2647,2657,2659,2663,2671,2677,2683,2687,2689,2693,2699,2707,2711,2713,
    2719,2729,2731,2741,2749,2753,2767,2777,2789,2791,2797,2801,2803,2819,2833,2837,
    2843,2851,2857,2861,2879,2887,2897,2903,2909,2917,2927,2939,2953,2957,2963,2969,
    2971,2999,3001,3011,3019,3023,3037,3041,3049,3061,3067,3079,3083,3089,3109,3119,
    3121,3137,3163,3167,3169,3181,3187,3191,3203,3209,3217,3221,3229,3251,3253,3257,
    3259,3271,3299,3301,3307,3313,3319,3323,3329,3331,3343,3347,3359,3361,3371,3373,
    3389,3391,3407,3413,3433,3449,3457,3461,3463,3467,3469,3491,3499,3511,3517,3527,
    3529,3533,3539,3541,3547,3557,3559,3571,3581,3583,3593,3607,3613,3617,3623,3631,
    3637,3643,3659,3671,3673,3677,3691,3697,3701,3709,3719,3727,3733,3739,3761,3767,
    3769,3779,3793,3797,3803,3821,3823,3833,3847,3851,3853,3863,3877,3881,3889,3907,
    3911,3917,3919,3923,3929,3931,3943,3947,3967,3989,4001,4003,4007,4013,4019,4021,
    4027,4049,4051,4057,4073,4079,4091,4093,4099,4111,4127,4129,4133,4139,4153,4157,
    4159,4177,4201,4211,4217,4219,4229,4231,4241,4243,4253,4259,4261,4271,4273,4283,
    4289,4297,4327,4337,4339,4349,4357,4363,4373,4391,4397,4409,4421,4423,4441,4447,
    4451,4457,4463,4481,4483,4493,4507,4513,4517,4519,4523,4547,4549,4561,4567,4583,
    4591,4597,4603,4621,4637,4639,4643,4649,4651,4657,4663,4673,4679,4691,4703,4721,
    4723,4729,4733,4751,4759,4783,4787,4789,4793,4799,4801,4813,4817,4831,4861,4871,
    4877,4889,4903,4909,4919,4931,4933,4937,4943,4951,4957,4967,4969,4973,4987,4993,
    4999,5003,5009,5011,5021,5023,5039,5051,5059,5077,5081,5087,5099,5101,5107,5113,
    5119,5147,5153,5167,5171,5179,5189,5197,5209,5227,5231,5233,5237,5261,5273,5279,
    5281,5297,5303,5309,5323,5333,5347,5351,5381,5387,5393,5399,5407,5413,5417,5419,
    5431,5437,5441,5443,5449,5471,5477,5479,5483,5501,5503,5507,5519,5521,5527,5531,
    5557,5563,5569,5573,5581,5591,5623,5639,5641,5647,5651,5653,5657,5659,5669,5683,
    5689,5693,5701,5711,5717,5737,5741,5743,5749,5779,5783,5791,5801,5807,5813,5821,
    5827,5839,5843,5849,5851,5857,5861,5867,5869,5879,5881,5897,5903,5923,5927,5939,
    5953,5981,5987,6007,6011,6029,6037,6043,6047,6053,6067,6073,6079,6089,6091,6101,
    6113,6121,6131,6133,6143,6151,6163,6173,6197,6199,6203,6211,6217,6221,6229,6247,
    6257,6263,6269,6271,6277,6287,6299,6301,6311,6317,6323,6329,6337,6343,6353,6359,
    6361,6367,6373,6379,6389,6397,6421,6427,6449,6451,6469,6473,6481,6491,6521,6529,
    6547,6551,6553,6563,6569,6571,6577,6581,6599,6607,6619,6637,6653,6659,6661,6673,
    6679,6689,6691,6701,6703,6709,6719,6733,6737,6761,6763,6779,6781,6791,6793,6803,
    6823,6827,6829,6833,6841,6857,6863,6869,6871,6883,6899,6907,6911,6917,6947,6949,
    6959,6961,6967,6971,6977,6983,6991,6997,7001,7013,7019,7027,7039,7043,7057,7069,
    7079,7103,7109,7121,7127,7129,7151,7159,7177,7187,7193,7207,7211,7213,7219,7229,
    7237,7243,7247,7253,7283,7297,7307,7309,7321,7331,7333,7349,7351,7369,7393,7411,
    7417,7433,7451,7457,7459,7477,7481,7487,7489,7499,7507,7517,7523,7529,7537,7541,
    7547,7549,7559,7561,7573,7577,7583,7589,7591,7603,7607,7621,7639,7643,7649,7669,
    7673,7681,7687,7691,7699,7703,7717,7723,7727,7741,7753,7757,7759,7789,7793,7817,
    7823,7829,7841,7853,7867,7873,7877,7879,7883,7901,7907,7919,7927,7933,7937,7949,
    7951,7963,7993,8009,8011,8017,8039,8053,8059,8069,8081,8087,8089,8093,8101,8111,
    8117,8123,8147,8161,8167,8171,8179,8191,8209,8219,8221,8231,8233,8237,8243,8263,
    8269,8273,8287,8291,8293,8297,8311,8317,8329,8353,8363,8369,8377,8387,8389,8419,
    8423,8429,8431,8443,8447,8461,8467,8501,8513,8521,8527,8537,8539,8543,8563,8573,
    8581,8597,8599,8609,8623,8627,8629,8641,8647,8663,8669,8677,8681,8689,8693,8699,
    8707,8713,8719,8731,8737,8741,8747,8753,8761,8779,8783,8803,8807,8819,8821,8831,
    8837,8839,8849,8861,8863,8867,8887,8893,8923,8929,8933,8941,8951,8963,8969,8971,
    8999,9001,9007,9011,9013,9029,9041,9043,9049,9059,9067,9091,9103,9109,9127,9133,
    9137,9151,9157,9161,9173,9181,9187,9199,9203,9209,9221,9227,9239,9241,9257,9277,
    9281,9283,9293,9311,9319,9323,9337,9341,9343,9349,9371,9377,9391,9397,9403,9413,
    9419,9421,9431,9433,9437,9439,9461,9463,9467,9473,9479,9491,9497,9511,9521,9533,
    9539,9547,9551,9587,9601,9613,9619,9623,9629,9631,9643,9649,9661,9677,9679,9689,
    9697,9719,9721,9733,9739,9743,9749,9767,9769,9781,9787,9791,9803,9811,9817,9829,
    9833,9839,9851,9857,9859,9871,9883,9887,9901,9907,9923,9929,9931,9941,9949,9967,
    9973
};

/* Lemire's exact divisibility test for odd 32-bit divisors: with inv=d^-1
 * mod 2^32, d divides n iff (uint32_t)(n*inv) <= floor((2^32-1)/d).  Pack
 * threshold:inverse so the hot loop needs one load, one low multiply and one
 * compare instead of udiv.  Entries mirror W_PRIME_TRIAL_DIVISORS through 997,
 * the largest divisor reachable at the current 10^6 cutoff. */
static const uint64_t W_PRIME_TRIAL_RECIP32[] = {
    UINT64_C(0x063e7063c18f9c19),UINT64_C(0x05f417d02fa0be83),UINT64_C(0x0572620a677d46cf),UINT64_C(0x04d4873e8c13521d),UINT64_C(0x0456c797a08ad8f3),UINT64_C(0x04325c53c10c9715),
    UINT64_C(0x03d2263507a44c6b),UINT64_C(0x039b0ad1e327a977),UINT64_C(0x0381c0e0c7e3f1f9),UINT64_C(0x033d91d2613716af),UINT64_C(0x031597212b2e43db),UINT64_C(0x02e05c0bfa3f47e9),
    UINT64_C(0x02a3a0fd5f02a3a1),UINT64_C(0x0288df0c7c32b16d),UINT64_C(0x027c4597d3431b57),UINT64_C(0x02647c698d28ac43),UINT64_C(0x02593f69da6c0965),UINT64_C(0x0243f6f00fdbc091),
    UINT64_C(0x02040810efdfbf7f),UINT64_C(0x01f44659c9484e2b),UINT64_C(0x01de5d6e077975b9),UINT64_C(0x01d77b6570586723),UINT64_C(0x01b7d6c38ce2cabd),UINT64_C(0x01b20364bf937f27),
    UINT64_C(0x01a16d3f2c0685b5),UINT64_C(0x01920fb4451ab30b),UINT64_C(0x01886e5fdb35a717),UINT64_C(0x017ad2200d516325),UINT64_C(0x016e1f76d962ae7b),UINT64_C(0x016a13cd10f8ed9d),
    UINT64_C(0x01571ed3ee936f3f),UINT64_C(0x0153909490948f41),UINT64_C(0x014cab883d137e0d),UINT64_C(0x0149539eef46c0f7),UINT64_C(0x013698df6e68575b),UINT64_C(0x0125e227db43bb1f),
    UINT64_C(0x0120b4709ba144cb),UINT64_C(0x011e2ef3478bbced),UINT64_C(0x011945381fdcd759),UINT64_C(0x0112358e437b2e0f),UINT64_C(0x010fef0110fef011),UINT64_C(0x0105197f9a020a33),
    UINT64_C(0x00ff00ffff00ff01),UINT64_C(0x00f92fb270e99cb7),UINT64_C(0x00f3a0d56205b5c5),UINT64_C(0x00f1d48ba27acdef),UINT64_C(0x00ec979125e4463d),UINT64_C(0x00e939650749cb29),
    UINT64_C(0x00e79372c9b97113),UINT64_C(0x00dfac1f84ce32ad),UINT64_C(0x00d578e9c74be1fb),UINT64_C(0x00d2ba08a7198487),UINT64_C(0x00d1615439409d09),UINT64_C(0x00cebcf86f71de15),
    UINT64_C(0x00c5fe74bfce8063),UINT64_C(0x00c27806f61fe7b1),UINT64_C(0x00bcdd5370e046d3),UINT64_C(0x00bbc840f1545af5),UINT64_C(0x00b9a7869a7862a1),UINT64_C(0x00b68d312a128a57),
    UINT64_C(0x00b2927cb7747d8f),UINT64_C(0x00afb321bb5e06dd),UINT64_C(0x00aceb0f12e9b5b3),UINT64_C(0x00ab1cbdec9dbe7f),UINT64_C(0x00a87917ec41cf4d),UINT64_C(0x00a513fdaec02945),
    UINT64_C(0x00a36e718382df71),UINT64_C(0x00a03c1684b1c2a9),UINT64_C(0x009c691675eb3a0b),UINT64_C(0x009baadefa86fe2d),UINT64_C(0x00980e413f8df54f),UINT64_C(0x00975a750975a751),
    UINT64_C(0x009548e4c3efac07),UINT64_C(0x0093efd1a8299b73),UINT64_C(0x0091f5bc9ba70e41),UINT64_C(0x008f67a123d9e879),UINT64_C(0x008e2917c494d305),UINT64_C(0x008d8be3ab67652f),
    UINT64_C(0x008c5584fb10fe5b),UINT64_C(0x0088d180bf54fa1f),UINT64_C(0x00869222b98f81d7),UINT64_C(0x0085797be90f1ec3),UINT64_C(0x008355acbed87f3b),UINT64_C(0x00824a4e16e70fc7),
    UINT64_C(0x0080c1219dece355),UINT64_C(0x007dc9f373f62c39),UINT64_C(0x007d4ecead46f9a3),UINT64_C(0x0079237d24e8d035),UINT64_C(0x0077cf532319bd8b),UINT64_C(0x0075a8acc7ed9da5),
    UINT64_C(0x007467acfea2c8fb),UINT64_C(0x00732d70ce0f4c09),UINT64_C(0x0072c62a544986f3),UINT64_C(0x007194a155a10dc1),UINT64_C(0x006fa54985e33763),UINT64_C(0x006e8419d84886b1),
    UINT64_C(0x006d68b531260967),UINT64_C(0x006d0b80d1ff25e9),UINT64_C(0x006bf7905b84d99f),UINT64_C(0x006ae9071335df6d),UINT64_C(0x006a379975d5add9),UINT64_C(0x0069dfbd3c619a43),
    UINT64_C(0x0067dc4c04767747),UINT64_C(0x00663d8000663d81),UINT64_C(0x0065ec17671ddc2b),UINT64_C(0x00654ac8c1e12337),UINT64_C(0x00645c859cd09045),UINT64_C(0x0063729991496b9b),
    UINT64_C(0x00632591c7d7b8bd),UINT64_C(0x006160ff9f006161),UINT64_C(0x0060cdb55e28152d),UINT64_C(0x005ff40100bfe803),UINT64_C(0x005ed79e9e907c7b),UINT64_C(0x005d7d4276528895),
    UINT64_C(0x005c6f3501ce2c0d),UINT64_C(0x005b2618bed7c42f),UINT64_C(0x005a2553d4b010e7),UINT64_C(0x0059686c1ebbe575),UINT64_C(0x0058ae97b47b52cb),UINT64_C(0x0058345f64f3f0d7),
    UINT64_C(0x005743d5316d6c0f),UINT64_C(0x005692c491c1195d),UINT64_C(0x00561e46a27b1f49),UINT64_C(0x005538ede508fd01),UINT64_C(0x0054c807133551cd),UINT64_C(0x005345ef2d8a3f1b),
    UINT64_C(0x00523a75c34ad735),UINT64_C(0x005102370a714919),UINT64_C(0x0050cf1224eea383),UINT64_C(0x004fd31942ba771d),UINT64_C(0x004fa17007772287),UINT64_C(0x004f3ed65e69ddf3),
    UINT64_C(0x004f0de53b4a6c15),UINT64_C(0x004e1caec606b677),UINT64_C(0x004cd47b46d3e1fd),UINT64_C(0x004c78ae484a14e9),UINT64_C(0x004c4b191ce874d3),UINT64_C(0x004bf0930473189f),
    UINT64_C(0x004aba3c372b7e65),UINT64_C(0x004a63604f9e5d91),UINT64_C(0x004a383e446bd9bb),UINT64_C(0x0049e28fe777c647),UINT64_C(0x0048417bf61f0c23),UINT64_C(0x0047f043a5cbbb6f),
    UINT64_C(0x00474ff269daac27),UINT64_C(0x00468b6f637aa061),UINT64_C(0x0045f13f1fb15099),UINT64_C(0x0045a522712c5825),UINT64_C(0x0045342cff30637b),UINT64_C(0x0044c4a201131289),
    UINT64_C(0x0043c5c20f5acdf7),UINT64_C(0x00437e494d3f89e3),UINT64_C(0x0043142dd2253531),UINT64_C(0x0042ab5c7bf69fe7),UINT64_C(0x00422195cfb1781f),UINT64_C(0x0041bbb2318e81ed),
};

static int w_prime_trial_recip32(uint32_t n) {
    size_t reciprocal_count = sizeof(W_PRIME_TRIAL_RECIP32) / sizeof(W_PRIME_TRIAL_RECIP32[0]);
    for (size_t i = 0; i < reciprocal_count; i += 4) {
        uint32_t p = (uint32_t)W_PRIME_TRIAL_DIVISORS[i];
        if ((uint64_t)p * p > n) break;
        uint64_t r0 = W_PRIME_TRIAL_RECIP32[i];
        uint64_t r1 = W_PRIME_TRIAL_RECIP32[i + 1];
        uint64_t r2 = W_PRIME_TRIAL_RECIP32[i + 2];
        uint64_t r3 = W_PRIME_TRIAL_RECIP32[i + 3];
        if (((uint32_t)(n * (uint32_t)r0) <= (uint32_t)(r0 >> 32)) |
            ((uint32_t)(n * (uint32_t)r1) <= (uint32_t)(r1 >> 32)) |
            ((uint32_t)(n * (uint32_t)r2) <= (uint32_t)(r2 >> 32)) |
            ((uint32_t)(n * (uint32_t)r3) <= (uint32_t)(r3 >> 32)))
            return 0;
    }
    return 1;
}

static uint64_t w_prime_mulmod(uint64_t a, uint64_t b, uint64_t m) {
    return (uint64_t)(((__uint128_t)a * (__uint128_t)b) % m);
}
static uint64_t w_prime_powmod(uint64_t base, uint64_t exp, uint64_t m) {
    uint64_t result = 1ULL % m;
    uint64_t b = base % m;
    while (exp != 0ULL) {
        if ((exp & 1ULL) != 0ULL) result = w_prime_mulmod(result, b, m);
        b = w_prime_mulmod(b, b, m);
        exp >>= 1U;
    }
    return result;
}
/* Montgomery arithmetic for the u64 Miller-Rabin path — replaces the 128-bit
 * hardware division in w_prime_mulmod with a multiply + shift + conditional
 * subtract (the division was ~3/4 of every modmul). n⁻¹ mod 2^64 by Newton
 * with Dumas's 5-bit kickstart (3n ^ 2, 4 iterations to 80 bits); the
 * reduction is carry-aware so it stays exact for moduli with the top bit set
 * (n > 2^63), where x + m·n exceeds 2^128 and a naive __uint128 reduction
 * would silently wrap — a correctness trap for the largest u64 primes. */
static inline uint64_t w_mont_ninv(uint64_t n) {
    uint64_t inv = (3ULL * n) ^ 2ULL;                   /* correct mod 32 (odd n) */
    inv *= 2ULL - n * inv;                              /* 5→10 bits */
    inv *= 2ULL - n * inv;                              /* 10→20 bits */
    inv *= 2ULL - n * inv;                              /* 20→40 bits */
    inv *= 2ULL - n * inv;                              /* 40→80 bits */
    return inv;
}
static inline uint64_t w_mont_mul(uint64_t a, uint64_t b, uint64_t n, uint64_t np) {
    __uint128_t x  = (__uint128_t)a * b;
    uint64_t x_hi = (uint64_t)(x >> 64),  x_lo  = (uint64_t)x;
    uint64_t    m  = x_lo * np;                         /* x·(−n⁻¹) mod 2^64 */
    uint64_t mn_hi = (uint64_t)(((__uint128_t)m * n) >> 64);
    /* m·n ≡ −x_lo (mod 2^64) by construction, so the low halves sum to
     * exactly 0 or 2^64: the carry is (x_lo != 0) and the low product is
     * never needed. */
    uint64_t carry = x_lo != 0;
    uint64_t res = x_hi + mn_hi + carry;                /* high limb of (x + m·n) >> 64 */
    int of = (res < x_hi) || (carry && res == x_hi);    /* 65th-bit carry-out */
    if (of || res >= n) res -= n;                       /* pre-reduce value < 2n ⇒ 1 subtract */
    return res;
}
/* Subtract-form Montgomery reduction with positive inverse inv = n⁻¹ mod 2^64:
 * m = x_lo·inv mod 2^64 makes m·n ≡ x_lo (mod 2^64), so the low 64 bits of
 * x − m·n cancel with zero borrow and (x − m·n)/2^64 = x_hi − y_hi ∈ (−n, n)
 * even when n > 2^63. Compiles to 7 branchless instructions. */
static inline uint64_t w_mont_mul_sub(uint64_t a, uint64_t b, uint64_t n, uint64_t inv) {
    __uint128_t x = (__uint128_t)a * b;
    uint64_t m = (uint64_t)x * inv;
    uint64_t x_hi = (uint64_t)(x >> 64);
    uint64_t y_hi = (uint64_t)(((__uint128_t)m * n) >> 64);
    uint64_t res = x_hi - y_hi;
    return x_hi < y_hi ? res + n : res;
}
/* 32-bit Montgomery arithmetic (R = 2^32) for the n < 2^32 FJ32 tier: all
 * products fit in uint64_t and entry (base << 32) % n is a single hardware
 * 64-bit udiv with no R² setup. */
static inline uint32_t w_mont32_ninv(uint32_t n) {
    uint32_t inv = (3U * n) ^ 2U;                       /* correct mod 32 (odd n) */
    inv *= 2U - n * inv;                                /* 5→10 bits */
    inv *= 2U - n * inv;                                /* 10→20 bits */
    inv *= 2U - n * inv;                                /* 20→40 bits */
    return inv;
}
static inline uint32_t w_mont32_mul(uint32_t a, uint32_t b, uint32_t n, uint32_t inv) {
    uint64_t x = (uint64_t)a * b;
    uint32_t m = (uint32_t)x * inv;
    int64_t d = (int64_t)(x >> 32) - (int64_t)(((uint64_t)m * n) >> 32);
    return (uint32_t)(d < 0 ? d + n : d);
}
/* Deterministic Montgomery Miller-Rabin over an explicit witness set. n is odd
 * (the small-prime screen ran first) and larger than every base. */
static int w_prime_mont_mr(uint64_t n, const uint64_t *bases, size_t nb) {
    if ((n & 1ULL) == 0ULL) return n == 2ULL;           /* defensive: Montgomery needs odd n */
    uint64_t inv = w_mont_ninv(n);                      /* n⁻¹ mod 2^64 */
    /* Montgomery setup, kept division-cheap (the setup runs per-n on every MR
     * call, including composites that exit after one base):
     *   one_m = R mod n = 2^64 mod n, computed as (2^64 − n) mod n so it's a
     *     HARDWARE u64 divide, not the __umodti3 software 128/64 of `(1<<64)%n`.
     *   r2 = R² mod n = one_m². For n < 2^32 (⇒ one_m < 2^32) the square fits a
     *     u64, so a hardware u64 mod suffices; only wider moduli need __uint128.
     *   nm1_m: (n−1)·R ≡ −R (mod n), so the Montgomery form of n−1 is just
     *     n − one_m — no multiply. */
    uint64_t one_m = (0ULL - n) % n;                    /* R mod n (hardware u64 divide) */
    uint64_t nm1_m = n - one_m;                         /* (n−1) in Montgomery form */
    uint64_t r2 = 0ULL;
    int s = __builtin_ctzll(n - 1ULL);
    uint64_t d = (n - 1ULL) >> s;
    for (size_t i = 0; i < nb; i++) {
        uint64_t bm;
        if (bases[i] == 2ULL && n > 2ULL) {
            bm = (one_m >= nm1_m) ? (one_m - nm1_m) : (one_m + one_m);
        } else {
            uint64_t a = (bases[i] < n) ? bases[i] : (bases[i] % n);
            if (a == 0ULL) continue;                    /* base ≡ 0: this witness says nothing */
            if (r2 == 0ULL) {
                r2 = (n <= 0xFFFFFFFFULL)
                        ? (one_m * one_m) % n
                        : (uint64_t)(((__uint128_t)one_m * one_m) % n);  /* R² mod n */
            }
            bm = w_mont_mul_sub(a, r2, n, inv);
        }
        uint64_t xm = bm;                               /* d is odd: bit 0 seeds xm = bm */
        if (d > 1ULL) {
            bm = w_mont_mul_sub(bm, bm, n, inv);
            for (uint64_t e = d >> 1; e > 1ULL; e >>= 1) {
                uint64_t prod = w_mont_mul_sub(xm, bm, n, inv);
                bm = w_mont_mul_sub(bm, bm, n, inv);
                if (e & 1ULL) xm = prod;
            }
            xm = w_mont_mul_sub(xm, bm, n, inv);
        }
        if (xm == one_m || xm == nm1_m) continue;       /* strong probable prime, this base */
        int ok = 0;
        for (int r = 1; r < s; r++) {
            xm = w_mont_mul_sub(xm, xm, n, inv);
            if (xm == nm1_m) { ok = 1; break; }
        }
        if (!ok) return 0;
    }
    return 1;
}
/* Forišek–Jančina hashed-base table for the 32-bit range: one deterministic
 * Miller-Rabin base per hash bucket. A SINGLE round with W_FJ32_BASES[(n>>8)&255]
 * settles primality for EVERY n < 2^32 — verified exhaustively against the exact
 * {2,7,61} test over all 2^32 integers (0 mismatches). One base ≈ ⅓ the modpows
 * of the {2,7,61} rung it replaces. Source: Forišek & Jančina 2015 (FJ32_256),
 * table via Dana Jacobsen's Math-Prime-Util; re-verified here, not trusted. */
static const uint16_t W_FJ32_BASES[256] = {
   4816, 6332,  958, 6124, 1001, 1431, 9644, 3700, 9251,20069, 7085, 2484,
   3255,  218, 4660,  732, 1863, 3716, 2480, 2120, 2464,38264, 3070, 2621,
   1592,17862,15223, 2926, 9119, 2181,24932, 4407,10915,13832, 1965, 3646,
   2470,   62, 8548,  449, 4440, 7656, 1065,10100, 6497, 1868,33282, 4277,
    805,  636,11536,   34, 2065,  406, 6435, 1043,27985, 7134, 1357, 3056,
   6077, 4704, 6174,  865,15190,14419,   38, 6161,18774, 3990,  976, 1267,
   3251,  233, 7387,  241, 3871, 4331, 8780, 2233,30331, 1656,  462, 5585,
    194,10300, 1072, 1197, 1573, 1144, 1273,19439,  696, 1477,15858, 2684,
   6022,   80, 9726, 6731, 1132,  774, 2202, 3668,19479,10837,  183,   71,
    403, 5245, 1995, 2019, 5209,  174,  503,13830,21013, 3284, 7164, 2607,
  10769,  473,  119, 8227, 1216, 3550, 1450, 1399,45822,  609,  721,   47,
   9665, 4242,  767, 4880,16037,  844,  333, 8560, 1907, 2532,13468,  302,
   2589, 5546,14312, 1548,18013, 8452,12427, 4431,10248, 4022, 5545, 1399,
  41507, 1160, 1865,  219, 1254, 3330,13627, 1070, 3304, 5537, 6085,26999,
  10279, 5369, 4992,38919, 2191, 1663,46961, 6570,11876,21689, 2804, 1202,
   5764,  275, 2862, 2139, 7799, 4646, 1696, 4964,19016,12891, 4282, 4741,
   7274,  174,  541,26596, 7524, 2777, 1819,  339, 1399, 2636,  668,  291,
    559, 4992,  520, 7874, 2544, 4618, 4122, 1128,  326,  275,13080,  156,
    236, 7015, 6349,11673, 2632,  475, 4560, 1543,   78, 3611,   34, 3811,
    137,  737,31269, 2522,13354, 2033, 8577, 3597, 9269, 3815, 2511, 8088,
    903,  109,12454, 1985, 8065,17637, 1645, 1404, 6106, 3661,  328, 6160,
   1602, 6601, 1491, 8657
};
/* FJ32 single-base test in 32-bit Montgomery arithmetic. Caller guarantees n
 * odd, coprime to 2..37, and n > 10⁶ (⇒ n ≫ 107²). Extend the small-prime
 * screen through 107 first (16 primes = four 4-lane NEON vectors reduced in a
 * single umaxv.16b), then enter the R = 2^32 Montgomery domain directly via
 * (base << 32) % n. */
static int w_prime_fj32(uint64_t n64) {
    uint32_t n = (uint32_t)n64;
    if ((n * 0xc18f9c19U <= 0x063e7063U) | (n * 0x2fa0be83U <= 0x05f417d0U) |
        (n * 0x677d46cfU <= 0x0572620aU) | (n * 0x8c13521dU <= 0x04d4873eU) |
        (n * 0xa08ad8f3U <= 0x0456c797U) | (n * 0xc10c9715U <= 0x04325c53U) |
        (n * 0x07a44c6bU <= 0x03d22635U) | (n * 0xe327a977U <= 0x039b0ad1U) |
        (n * 0xc7e3f1f9U <= 0x0381c0e0U) | (n * 0x613716afU <= 0x033d91d2U) |
        (n * 0x2b2e43dbU <= 0x03159721U) | (n * 0xfa3f47e9U <= 0x02e05c0bU) |
        (n * 0x5f02a3a1U <= 0x02a3a0fdU) | (n * 0x7c32b16dU <= 0x0288df0cU) |
        (n * 0xd3431b57U <= 0x027c4597U) | (n * 0x8d28ac43U <= 0x02647c69U)) return 0;
    uint32_t inv = w_mont32_ninv(n);
    uint64_t base = W_FJ32_BASES[(n >> 8) & 255U];
    uint32_t bm = (uint32_t)((base << 32) % n);
    if (bm == 0U) return 1;
    int s = __builtin_ctz(n - 1U);
    uint32_t d = (n - 1U) >> s;
    uint32_t xm = bm;
    if (d > 1U) {
        bm = w_mont32_mul(bm, bm, n, inv);
        for (uint32_t e = d >> 1; e > 1U; e >>= 1) {
            if (e & 1U) {
                __asm__ volatile("" : "+r"(xm));
                xm = w_mont32_mul(xm, bm, n, inv);
            }
            bm = w_mont32_mul(bm, bm, n, inv);
        }
        xm = w_mont32_mul(xm, bm, n, inv);
    }
    uint32_t one_m = (0U - n) % n;
    uint32_t nm1_m = n - one_m;
    if (xm == one_m || xm == nm1_m) return 1;
    for (int r = 1; r < s; r++) {
        xm = w_mont32_mul(xm, xm, n, inv);
        if (xm == nm1_m) return 1;
    }
    return 0;
}
/* SSMR hashed single-base test for [2^32, 2^47): Machine-prime witness table
 * (JASory/machine-prime, strong MR, proven for all n < 2^47).
 * idx = ((uint32_t)n*811484239)>>14. Since n < 2^47 and base < 2^16,
 * base * one_m < 2^63 fits in uint64_t, so (base * one_m) % n enters the
 * Montgomery domain in one hardware u64 divide without computing R² mod n. */
/* The 512KB witness table lives in ssmr_witness.c, linked only when the IR
 * probe sees prime usage; this weak twin returns NULL otherwise and the SSMR
 * tier is skipped (the multi-base ladder covers its whole range exactly). */
__attribute__((weak)) const uint16_t *w_ssmr_witness_ptr(void) { return NULL; }

static int w_prime_ssmr(uint64_t n, const uint16_t *witness) {
    if (n % 41ULL == 0ULL || n % 43ULL == 0ULL || n % 47ULL == 0ULL || n % 53ULL == 0ULL ||
        n % 59ULL == 0ULL || n % 61ULL == 0ULL || n % 67ULL == 0ULL || n % 71ULL == 0ULL ||
        n % 73ULL == 0ULL || n % 79ULL == 0ULL || n % 83ULL == 0ULL || n % 89ULL == 0ULL ||
        n % 97ULL == 0ULL) return 0;
    uint64_t inv = w_mont_ninv(n);
    uint64_t one_m = (0ULL - n) % n;
    uint64_t base = (uint64_t)witness[w_ssmr_bucket(n)];
    uint64_t bm = (base * one_m) % n;
    int s = __builtin_ctzll(n - 1ULL);
    uint64_t d = (n - 1ULL) >> s;
    uint64_t xm = bm;
    if (d > 1ULL) {
        bm = w_mont_mul_sub(bm, bm, n, inv);
        for (uint64_t e = d >> 1; e > 1ULL; e >>= 1) {
            uint64_t prod = w_mont_mul_sub(xm, bm, n, inv);
            bm = w_mont_mul_sub(bm, bm, n, inv);
            if (e & 1ULL) xm = prod;
        }
        xm = w_mont_mul_sub(xm, bm, n, inv);
    }
    uint64_t nm1_m = n - one_m;
    if (xm == one_m || xm == nm1_m) return 1;
    for (int r = 1; r < s; r++) {
        xm = w_mont_mul_sub(xm, xm, n, inv);
        if (xm == nm1_m) return 1;
    }
    return 0;
}
/* Tier 3 — deterministic Miller-Rabin for n > 10⁶, shared by every u64 variant.
 * Each range takes the smallest proven witness set — fewer bases = fewer modpows.
 * Bounds are exact (verified against the all-u64 Sinclair set):
 *   n < 2^32     Forišek–Jančina     1 hashed base (exhaustive proof over 2^32)
 *   n < 2^47     SSMR                1 hashed base (Machine-prime, n < 2^47)
 *   n < 1.12e12  {2,13,23,1662803}   4 bases (fallback when ssmr_witness absent)
 *   n < 2.15e12  {2,3,5,7,11}        5 bases (fallback when ssmr_witness absent)
 *   n < 3.47e12  {2,3,5,7,11,13}     6 bases (fallback when ssmr_witness absent)
 *   else         Sinclair            7 bases (exact for all u64)
 * All arithmetic is Montgomery (division-free). */
static int w_prime_test_u64_mr(uint64_t n) {
    if (n < 4294967296ULL)     return w_prime_fj32(n);   /* n < 2^32: one hashed base */
    if (n < 140737488355328ULL) {                        /* n < 2^47: one SSMR hashed base */
        const uint16_t *wit = w_ssmr_witness_ptr();
        if (wit) return w_prime_ssmr(n, wit);
    }
    static const uint64_t B4[] = {2ULL, 13ULL, 23ULL, 1662803ULL};
    static const uint64_t B5[] = {2ULL, 3ULL, 5ULL, 7ULL, 11ULL};
    static const uint64_t B6[] = {2ULL, 3ULL, 5ULL, 7ULL, 11ULL, 13ULL};
    if (n < 1122004669633ULL)  return w_prime_mont_mr(n, B4, 4);
    if (n < 2152302898747ULL)  return w_prime_mont_mr(n, B5, 5);
    if (n < 3474749660383ULL)  return w_prime_mont_mr(n, B6, 6);
    return w_prime_mont_mr(n, W_PRIME_MR_BASES,
                           sizeof(W_PRIME_MR_BASES)/sizeof(W_PRIME_MR_BASES[0]));
}

/* Tiers 2 & 3 shared by prime?: n has passed the small-prime screen (no factor
 * ≤ 37) and n ≥ 1681. Tier 2 scans a precomputed PRIME table up to √n using
 * exact reciprocal divisibility; at this cutoff no entry above 997 is visited.
 * Cutoff is 10⁶, a conservative distribution-tuned boundary: worst-case primes
 * cross near 5·10⁵, while mixed inputs through 10⁶ still benefit from cheap
 * composite exits. Above 10⁶, one Montgomery FJ round wins. */
static int w_prime_test_u64_post_screen(uint64_t n) {
    if (n <= 1000000ULL) {
        return w_prime_trial_recip32((uint32_t)n);
    }
    return w_prime_test_u64_mr(n);
}

/* Integer √n (floor), overflow-safe. */
static uint64_t w_isqrt_u64(uint64_t n) {
    if (n == 0) return 0;
    uint64_t r = (uint64_t)sqrtl((long double)n);
    while (r > n / r) r--;                    /* r*r > n without overflowing */
    while ((r + 1) <= n / (r + 1)) r++;       /* (r+1)^2 <= n */
    return r;
}

/* Wheel index of a coprime-to-6 value: 0↔1, 1↔5, 2↔7, 3↔11, 4↔13, … */
static inline uint64_t w_widx6(uint64_t n) { return 2 * (n / 6) + (n % 6 == 5); }

/* Count primes in a contiguous chunk [lo,hi] with a mod-6 wheel segmented sieve,
 * given SHARED read-only base primes bp[0..nbp) (coprime to 6, ≤ √hi). Stores
 * only coprime-to-6 integers (⅓ of them); each base prime's two residue classes
 * are a CONSTANT-stride (2p) additive march (no per-mark division). Two extra
 * refinements over the naive segmented sieve:
 *   • CARRIED STATE — each class keeps its resume index (ci0/ci1) across this
 *     chunk's segments, so the per-segment `ceil(s/p)` division is paid once per
 *     prime (at activation), not once per prime per segment. The gain grows with
 *     N: once √N nears the segment width the division stops amortizing.
 *   • SEGMENT SPLIT — interior full segments (s ≥ start and block-aligned end)
 *     count with a tight `count += seg[i]==0` loop, with NO per-position
 *     `v ≥ start && v < segend` bounds checks; only the first (s < start) and
 *     last (partial) segments pay them. */
/* Pattern presieve: the combined composite pattern of the wheel primes
 * {5,7,11,13,17} is periodic in wheel-byte space with period
 * 2·5·7·11·13·17 = 170170 bytes (each prime's marks are two stride-2p
 * progressions, so its pattern repeats every 2p bytes). Those five primes
 * account for ~60% of ALL mark writes (marking work ∝ Σ 1/p, Mertens), so
 * initializing each segment by a phased memcpy of the pattern replaces both
 * the memset and the five hottest marking loops with sequential copies. */
#define W_PRESIEVE_PERIOD 170170u
static uint8_t *w_presieve_pattern(void) {
    uint8_t *pat = (uint8_t *)malloc(W_PRESIEVE_PERIOD);
    if (!pat) return NULL;
    for (uint32_t g = 0; g < W_PRESIEVE_PERIOD; g++) {
        uint64_t v = 6ULL * (g >> 1) + ((g & 1) ? 5 : 1);
        pat[g] = (v % 5 == 0 || v % 7 == 0 || v % 11 == 0 || v % 13 == 0 || v % 17 == 0);
    }
    return pat;
}

static uint64_t w_prime_count_chunk(uint64_t lo, uint64_t hi, const uint64_t *bp, int nbp,
                                    const uint8_t *pat) {
    uint64_t count = 0;
    if (lo <= 2 && hi >= 2) count++;
    if (lo <= 3 && hi >= 3) count++;
    uint64_t start = (lo <= 5) ? 5 : lo;               /* first coprime-to-6 ≥ max(lo,5) */
    while (start % 2 == 0 || start % 3 == 0) start++;
    if (start > hi) return count;

    const uint64_t BLOCKS = 1u << 16;
    const uint64_t W = 6 * BLOCKS;                      /* integers per (full) segment */
    uint8_t  *seg = (uint8_t  *)malloc(2 * BLOCKS);
    uint64_t *ci0 = (uint64_t *)malloc((size_t)(nbp + 1) * sizeof(uint64_t));
    uint64_t *ci1 = (uint64_t *)malloc((size_t)(nbp + 1) * sizeof(uint64_t));
    if (!seg || !ci0 || !ci1) { free(seg); free(ci0); free(ci1); return count; }
    int nact = 0;                                       /* primes activated so far (bp is sorted) */
    for (uint64_t s = (start / 6) * 6; s <= hi; s += W) {
        uint64_t segend = (s + W < hi + 1) ? s + W : hi + 1;   /* exclusive */
        uint64_t nblk = (segend - s + 5) / 6;
        if (nblk > BLOCKS) nblk = BLOCKS;
        uint64_t lim = 2 * nblk;
        /* init = phased copy of the presieve pattern (replaces memset AND the
         * marking loops of 5,7,11,13,17) */
        {
            uint64_t off = ((s / 6) * 2) % W_PRESIEVE_PERIOD;
            uint64_t pos = 0;
            while (pos < lim) {
                uint64_t nn = W_PRESIEVE_PERIOD - off;
                if (nn > lim - pos) nn = lim - pos;
                memcpy(seg + pos, pat + off, nn);
                pos += nn;
                off += nn;
                if (off == W_PRESIEVE_PERIOD) off = 0;
            }
        }
        /* the pattern marks 5..17 themselves (p | p); unmark them in range */
        if (s < 18) {
            static const uint64_t WPAT[5] = {5, 7, 11, 13, 17};
            for (int k = 0; k < 5; k++) {
                uint64_t p = WPAT[k];
                if (p >= s && p < segend) {
                    uint64_t d = p - s;
                    seg[(d / 6) * 2 + (d % 6 == 5)] = 0;
                }
            }
        }
        /* activate primes whose p² first enters this segment (one division each,
         * once; the m0<s branch also seeds small primes at a chunk's start). */
        while (nact < nbp && bp[nact] * bp[nact] < segend) {
            uint64_t p = bp[nact], m0 = p * p;
            if (m0 < s) { uint64_t c = (s + p - 1) / p; while (c % 2 == 0 || c % 3 == 0) c++; m0 = p * c; }
            uint64_t d0 = m0 - s; ci0[nact] = (d0 / 6) * 2 + (d0 % 6 == 5);
            uint64_t m1 = m0 + (m0 % 6 == p % 6 ? 4 * p : 2 * p);
            uint64_t d1 = m1 - s; ci1[nact] = (d1 / 6) * 2 + (d1 % 6 == 5);
            nact++;
        }
        for (int k = 0; k < nact; k++) {                /* mark; carry overshoot (index shifts by lim/full seg) */
            uint64_t step = 2 * bp[k];
            uint64_t i = ci0[k]; for (; i < lim; i += step) seg[i] = 1; ci0[k] = i - lim;
            i = ci1[k];          for (; i < lim; i += step) seg[i] = 1; ci1[k] = i - lim;
        }
        if (s >= start && segend == s + W) {            /* interior full segment: no bounds checks */
            for (uint64_t i = 0; i < lim; i++) count += (seg[i] == 0);
        } else {                                         /* first (s<start) or last (partial) segment */
            for (uint64_t b = 0; b < nblk; b++) {
                uint64_t v1 = s + b * 6 + 1, v5 = s + b * 6 + 5;
                if (v1 >= start && v1 < segend && seg[b * 2] == 0)     count++;
                if (v5 >= start && v5 < segend && seg[b * 2 + 1] == 0) count++;
            }
        }
    }
    free(seg); free(ci0); free(ci1);
    return count;
}

typedef struct { uint64_t lo, hi; const uint64_t *bp; int nbp; const uint8_t *pat; uint64_t out; } WPrimeCountJob;
static void *w_prime_count_worker(void *arg) {
    WPrimeCountJob *j = (WPrimeCountJob *)arg;
    j->out = w_prime_count_chunk(j->lo, j->hi, j->bp, j->nbp, j->pat);
    return NULL;
}

/* Bulk prime COUNT over [lo, hi] inclusive via a mod-6 wheel segmented sieve —
 * the right tool when the whole range is wanted (π(N) / count-in-range), versus
 * per-number prime? testing. O(n log log n), ~40× the fused `/prime?:count`
 * loop. Base primes ≤ √hi are computed once and shared read-only; large ranges
 * are split into disjoint contiguous chunks across threads, each with its own
 * buffers + carried state (no shared writes ⇒ near-linear scaling). Base sieve
 * is ~√hi bytes, so keep hi in reason (√1e18 ⇒ ~0.5 GB). 2 and 3 are counted
 * outside the wheel (only ever by the chunk containing them). */
uint64_t w_prime_count_u64_mod6(uint64_t lo, uint64_t hi) {
    if (hi < 2 || hi < lo) return 0;
    if (lo < 2) lo = 2;

    /* base primes coprime to 6 in [5, √hi], once; gap 4c iff j%6==c%6 (mult ≡1). */
    uint64_t root = w_isqrt_u64(hi);
    uint64_t bn = w_widx6(root) + 1;
    uint8_t *bs = (uint8_t *)calloc(bn ? bn : 1, 1);
    uint64_t *bp = (uint64_t *)malloc((bn + 1) * sizeof(uint64_t));
    if (!bs || !bp) { free(bs); free(bp); return 0; }
    int nbp = 0;
    for (uint64_t c = 5; c <= root; c += (c % 6 == 1) ? 4 : 2) {
        if (!bs[w_widx6(c)]) {
            bp[nbp++] = c;
            for (uint64_t j = c * c; j <= root; j += (j % 6 == c % 6 ? 4 * c : 2 * c)) bs[w_widx6(j)] = 1;
        }
    }
    free(bs);

    uint8_t *pat = w_presieve_pattern();
    if (!pat) { free(bp); return 0; }
    /* the pattern covers {5,7,11,13,17}: the march starts above them */
    int skip = 0;
    while (skip < nbp && bp[skip] <= 17) skip++;
    const uint64_t *bpm = bp + skip;
    int nbpm = nbp - skip;

    /* Thread only when the range is large enough to amortize spawn/join. */
    int T = 1;
    if (hi - lo > 100000000ULL) {
        long ncpu = sysconf(_SC_NPROCESSORS_ONLN);
        if (ncpu > 1) T = (ncpu > 64) ? 64 : (int)ncpu;
    }
    uint64_t total;
    if (T <= 1) {
        total = w_prime_count_chunk(lo, hi, bpm, nbpm, pat);
    } else {
        pthread_t th[64];
        WPrimeCountJob jobs[64];
        int live[64], spawned = 0;
        uint64_t csz = ((hi - lo) / (uint64_t)T / 6 + 1) * 6;   /* chunk width, multiple of 6 */
        for (int t = 0; t < T; t++) {
            uint64_t clo = (t == 0) ? lo : lo + (uint64_t)t * csz;
            if (clo > hi) break;
            uint64_t chi = (t == T - 1) ? hi : lo + (uint64_t)(t + 1) * csz - 1;
            if (chi > hi) chi = hi;
            jobs[spawned].lo = clo; jobs[spawned].hi = chi;
            jobs[spawned].bp = bpm; jobs[spawned].nbp = nbpm;
            jobs[spawned].pat = pat; jobs[spawned].out = 0;
            if (pthread_create(&th[spawned], NULL, w_prime_count_worker, &jobs[spawned]) == 0) {
                live[spawned] = 1;
            } else {                                    /* spawn failed → run inline */
                jobs[spawned].out = w_prime_count_chunk(clo, chi, bpm, nbpm, pat);
                live[spawned] = 0;
            }
            spawned++;
        }
        total = 0;
        for (int t = 0; t < spawned; t++) {
            if (live[t]) pthread_join(th[t], NULL);
            total += jobs[t].out;
        }
    }
    free(pat);
    free(bp);
    return total;
}

/* Tiered test for n that fits in 64 bits. Exact for all n < 2⁶⁴. */
#ifndef BN_PRIME_PREFILTER
#define BN_PRIME_PREFILTER 1
#endif
static int w_prime_test_u64(uint64_t n) {
    if ((n & 1ULL) == 0ULL) return n == 2ULL;

#if !BN_PRIME_PREFILTER
    /* Benchmark control: retain an exact all-u64 primality test while
     * bypassing every cheap candidate prefilter.  The measured fixtures are
     * above the smaller witness tiers, so both variants reach this same
     * seven-base test whenever the production screen does not reject first. */
    if (n < 2ULL) return 0;
    return w_prime_mont_mr(
        n, W_PRIME_MR_BASES,
        sizeof(W_PRIME_MR_BASES) / sizeof(W_PRIME_MR_BASES[0]));
#else

    /* Tier 1 — bitmask resolves all n < 64; 32-bit/64-bit reciprocal screen
     * by 3..37 resolves every n < 41² = 1681 without n == p branches. */
    if (n < 64ULL) return (int)((0x28208A20A08A28ACULL >> n) & 1ULL);
    if ((n >> 32) == 0ULL) {
        uint32_t n32 = (uint32_t)n;
        if ((n32 * 0xaaaaaaabU <= 0x55555555U) |
            (n32 * 0xcccccccdU <= 0x33333333U) |
            (n32 * 0xb6db6db7U <= 0x24924924U)) return 0;
        if ((n32 * 0xba2e8ba3U <= 0x1745d174U) |
            (n32 * 0xc4ec4ec5U <= 0x13b13b13U) |
            (n32 * 0xf0f0f0f1U <= 0x0f0f0f0fU) |
            (n32 * 0x286bca1bU <= 0x0d79435eU) |
            (n32 * 0xe9bd37a7U <= 0x0b21642cU) |
            (n32 * 0x4f72c235U <= 0x08d3dcb0U) |
            (n32 * 0xbdef7bdfU <= 0x08421084U) |
            (n32 * 0x914c1badU <= 0x06eb3e45U)) return 0;
        if (n32 < 1681U) return 1;  /* no factor ≤ 37 and below 41² ⇒ prime */
        return w_prime_test_u64_post_screen(n);
    }
    if (n % 3ULL == 0ULL || n % 5ULL == 0ULL || n % 7ULL == 0ULL ||
        n % 11ULL == 0ULL || n % 13ULL == 0ULL || n % 17ULL == 0ULL ||
        n % 19ULL == 0ULL || n % 23ULL == 0ULL || n % 29ULL == 0ULL ||
        n % 31ULL == 0ULL || n % 37ULL == 0ULL) return 0;
    return w_prime_test_u64_post_screen(n);
#endif
}

/* prime_12k?: a FAST primality test for a candidate already known coprime to 6
 * (a 12m+{1,5,7,11} wheel offset). Skips only the 2 and 3 screen checks the
 * caller has guaranteed away, then runs the same fast inner test as prime?
 * (division-free prime-factor scan ≤ 10⁶, Montgomery Miller-Rabin above). The wheel
 * lives in the CALLER's candidate generation, not here. CONTRACT: gcd(n,6)==1, n ≥ 5 —
 * a multiple of 2 or 3 would be misreported. u64-only. */
static int w_prime_test_u64_12k(uint64_t n) {
    if (n < 64ULL) return (int)((0x28208A20A08A28A0ULL >> n) & 1ULL);
    if ((n >> 32) == 0ULL) {
        uint32_t n32 = (uint32_t)n;
        if ((n32 * 0xcccccccdU <= 0x33333333U) |
            (n32 * 0xb6db6db7U <= 0x24924924U)) return 0;
        if ((n32 * 0xba2e8ba3U <= 0x1745d174U) |
            (n32 * 0xc4ec4ec5U <= 0x13b13b13U) |
            (n32 * 0xf0f0f0f1U <= 0x0f0f0f0fU) |
            (n32 * 0x286bca1bU <= 0x0d79435eU) |
            (n32 * 0xe9bd37a7U <= 0x0b21642cU) |
            (n32 * 0x4f72c235U <= 0x08d3dcb0U) |
            (n32 * 0xbdef7bdfU <= 0x08421084U) |
            (n32 * 0x914c1badU <= 0x06eb3e45U)) return 0;
        if (n32 < 1681U) return 1;
        return w_prime_test_u64_post_screen(n);
    }
    if (n % 5ULL == 0ULL || n % 7ULL == 0ULL || n % 11ULL == 0ULL ||
        n % 13ULL == 0ULL || n % 17ULL == 0ULL || n % 19ULL == 0ULL ||
        n % 23ULL == 0ULL || n % 29ULL == 0ULL || n % 31ULL == 0ULL ||
        n % 37ULL == 0ULL) return 0;
    return w_prime_test_u64_post_screen(n);
}

/* prime_30k?: like prime_12k? for a candidate known coprime to 30 (a mod-30
 * offset: 1,7,11,13,17,19,23,29). Skips the 2, 3, AND 5 screen checks, then the
 * shared fast inner test. CONTRACT: gcd(n,30)==1, n ≥ 7. u64-only. */
static int w_prime_test_u64_30k(uint64_t n) {
    if (n < 64ULL) return (int)((0x28208A20A08A2880ULL >> n) & 1ULL);
    if ((n >> 32) == 0ULL) {
        uint32_t n32 = (uint32_t)n;
        if (n32 * 0xb6db6db7U <= 0x24924924U) return 0;
        if ((n32 * 0xba2e8ba3U <= 0x1745d174U) |
            (n32 * 0xc4ec4ec5U <= 0x13b13b13U) |
            (n32 * 0xf0f0f0f1U <= 0x0f0f0f0fU) |
            (n32 * 0x286bca1bU <= 0x0d79435eU) |
            (n32 * 0xe9bd37a7U <= 0x0b21642cU) |
            (n32 * 0x4f72c235U <= 0x08d3dcb0U) |
            (n32 * 0xbdef7bdfU <= 0x08421084U) |
            (n32 * 0x914c1badU <= 0x06eb3e45U)) return 0;
        if (n32 < 1681U) return 1;
        return w_prime_test_u64_post_screen(n);
    }
    if (n % 7ULL == 0ULL || n % 11ULL == 0ULL || n % 13ULL == 0ULL ||
        n % 17ULL == 0ULL || n % 19ULL == 0ULL || n % 23ULL == 0ULL ||
        n % 29ULL == 0ULL || n % 31ULL == 0ULL || n % 37ULL == 0ULL) return 0;
    return w_prime_test_u64_post_screen(n);
}

/* ---- mod-30 wheel, bit-packed segmented sieve (w_p30_*) ------------------
 * Storage: byte b holds the eight candidates 30b + {1,7,11,13,17,19,23,29},
 * one per bit. That is 1 byte per 30 integers — 10× denser than the mod-6
 * byte-per-candidate sieve above, so a 128 KB segment (one M-series L1D)
 * covers 3.9M integers instead of 393K.
 *
 * Marking: for a prime p coprime to 30 the multiples split into eight
 * arithmetic progressions p*(30t + R[j]). Each has CONSTANT byte stride p
 * (30p integers = p bytes) and a CONSTANT bit mask, because
 * p*(30t+R[j]) ≡ p*R[j] (mod 30) independent of t. So the inner loop stays
 * `seg[b] |= m; b += p` with no tables and no division.
 *
 * Large primes: a prime with stride ≥ segment width marks at most once per
 * segment, so re-examining every base prime per segment dominates at 1e12+.
 * Each progression is instead filed in a ring of buckets keyed by the segment
 * it next lands in (ring depth √hi/seg_bytes + 3), and only the current
 * bucket is walked.
 *
 * Counting: popcount over the segment as u64 words — one popcount per 8
 * candidates (240 integers per word) instead of one compare per candidate.
 *
 * Presieve: {7,11,13,17,19} are periodic in byte space with period
 * 7·11·13·17·19 = 323323, so each segment starts as a phased memcpy of that
 * pattern. Replaces the memset AND the five densest marking loops (~22% of
 * all marks). */

static const uint8_t W30_R[8] = {1, 7, 11, 13, 17, 19, 23, 29};
static const int8_t W30_BIT[30] = {
    -1,  0, -1, -1, -1, -1, -1,  1, -1, -1,
    -1,  2, -1,  3, -1, -1, -1,  4, -1,  5,
    -1, -1, -1,  6, -1, -1, -1, -1, -1,  7
};
#define W_P30_PRESIEVE 323323u
#define W_P30_SEG_BYTES (128u * 1024u)

static uint8_t *w_p30_pattern(void) {
    uint8_t *pat = (uint8_t *)malloc(W_P30_PRESIEVE);
    if (!pat) return NULL;
    for (uint32_t b = 0; b < W_P30_PRESIEVE; b++) {
        uint8_t v = 0;
        for (int j = 0; j < 8; j++) {
            uint64_t x = 30ULL * b + W30_R[j];
            if (x % 7 == 0 || x % 11 == 0 || x % 13 == 0 || x % 17 == 0 || x % 19 == 0)
                v |= (uint8_t)(1u << j);
        }
        pat[b] = v;
    }
    return pat;
}

typedef struct {
    uint8_t  *seg;
    uint32_t *nxt;    /* byte offset from chunk base of this entry's next mark */
    uint8_t  *msk;
    int32_t  *link;
    int32_t  *head;
    uint32_t  ring;
    uint32_t  seg_bytes;
    int       nbp;
} WP30Scratch;

static void w_p30_scratch_free(WP30Scratch *sc) {
    if (!sc) return;
    free(sc->seg); free(sc->nxt); free(sc->msk); free(sc->link); free(sc->head);
    sc->seg = NULL; sc->nxt = NULL; sc->msk = NULL; sc->link = NULL; sc->head = NULL;
}

static int w_p30_scratch_init(WP30Scratch *sc, int nbp, uint64_t root, uint32_t seg_bytes) {
    size_t e = (size_t)nbp * 8 + 8;
    sc->seg_bytes = seg_bytes;
    sc->ring = (uint32_t)(root / seg_bytes) + 3;
    sc->nbp = nbp;
    sc->seg  = (uint8_t  *)malloc(seg_bytes);
    sc->nxt  = (uint32_t *)malloc(e * sizeof(uint32_t));
    sc->msk  = (uint8_t  *)malloc(e);
    sc->link = (int32_t  *)malloc(e * sizeof(int32_t));
    sc->head = (int32_t  *)malloc((size_t)sc->ring * sizeof(int32_t));
    if (!sc->seg || !sc->nxt || !sc->msk || !sc->link || !sc->head) {
        w_p30_scratch_free(sc);
        return 0;
    }
    return 1;
}

/* First multiple of p that is ≥ start and ≡ p*R[j] (mod 30), as a byte index. */
static inline uint64_t w_p30_first_byte(uint64_t p, uint64_t rj, uint64_t start) {
    uint64_t q = (start + p - 1) / p;
    if (q < p) q = p;
    uint64_t t = (q > rj) ? (q - rj + 29) / 30 : 0;
    return (p * (30 * t + rj)) / 30;
}

/* Sieve [lo,hi) — both multiples of 30 — and count the primes there.
 * want > 0  : stop at the want-th prime of the chunk, store it in *found.
 * out       : append every prime found (bounded by out_cap), *out_n advances. */
static uint64_t w_p30_chunk(uint64_t lo, uint64_t hi, const uint64_t *bp, int nbp,
                            const uint8_t *pat, WP30Scratch *sc,
                            uint64_t want, uint64_t *found,
                            uint64_t *out, uint64_t out_cap, uint64_t *out_n) {
    const uint64_t base_byte  = lo / 30;
    const uint64_t end_byte   = hi / 30;
    const uint64_t chunk_bytes = end_byte - base_byte;
    const uint32_t seg_bytes  = sc->seg_bytes;
    const uint32_t ring       = sc->ring;
    uint8_t  *seg  = sc->seg;
    uint32_t *nxt  = sc->nxt;
    uint8_t  *msk  = sc->msk;
    int32_t  *link = sc->link;
    int32_t  *head = sc->head;
    uint64_t count = 0;

    for (uint32_t i = 0; i < ring; i++) head[i] = -1;

    /* Primes already in play at lo: file all eight progressions. */
    int active = 0;
    while (active < nbp && bp[active] * bp[active] < lo) {
        uint64_t p = bp[active];
        for (int j = 0; j < 8; j++) {
            uint64_t gb = w_p30_first_byte(p, W30_R[j], lo);
            if (gb < end_byte) {
                int32_t k = active * 8 + j;
                uint32_t off = (uint32_t)(gb - base_byte);
                nxt[k]  = off;
                msk[k]  = (uint8_t)(1u << W30_BIT[(p % 30) * W30_R[j] % 30]);
                uint32_t slot = (off / seg_bytes) % ring;
                link[k] = head[slot];
                head[slot] = k;
            }
        }
        active++;
    }

    uint32_t rp = 0;
    for (uint64_t cur_off = 0; cur_off < chunk_bytes; cur_off += seg_bytes) {
        uint64_t nb64 = chunk_bytes - cur_off;
        uint32_t nbytes = (nb64 > seg_bytes) ? seg_bytes : (uint32_t)nb64;
        uint64_t seg_lo_byte = base_byte + cur_off;

        /* phased copy of the presieve pattern */
        {
            uint64_t off = seg_lo_byte % W_P30_PRESIEVE;
            uint32_t pos = 0;
            while (pos < nbytes) {
                uint64_t n = W_P30_PRESIEVE - off;
                if (n > nbytes - pos) n = nbytes - pos;
                memcpy(seg + pos, pat + off, (size_t)n);
                pos += (uint32_t)n;
                off += n;
                if (off == W_P30_PRESIEVE) off = 0;
            }
            /* the pattern marks 7,11,13,17,19 themselves — unmark them */
            if (seg_lo_byte == 0) {
                static const uint8_t SELF[5] = {7, 11, 13, 17, 19};
                for (int k = 0; k < 5; k++)
                    seg[0] &= (uint8_t)~(1u << W30_BIT[SELF[k]]);
                seg[0] |= 1u;      /* the candidate 1 is not prime */
            }
        }

        /* primes whose square first lands in this segment enter now */
        uint64_t top = (seg_lo_byte + nbytes) * 30;
        while (active < nbp && bp[active] * bp[active] < top) {
            uint64_t p = bp[active];
            for (int j = 0; j < 8; j++) {
                uint64_t gb = w_p30_first_byte(p, W30_R[j], p * p);
                if (gb < end_byte) {
                    int32_t k = active * 8 + j;
                    uint32_t off = (uint32_t)(gb - base_byte);
                    nxt[k]  = off;
                    msk[k]  = (uint8_t)(1u << W30_BIT[(p % 30) * W30_R[j] % 30]);
                    uint32_t slot = (uint32_t)(((off - cur_off) / seg_bytes + rp) % ring);
                    link[k] = head[slot];
                    head[slot] = k;
                }
            }
            active++;
        }

        /* mark this segment's bucket, then re-file each entry forward */
        {
            int32_t k = head[rp];
            head[rp] = -1;
            while (k >= 0) {
                int32_t nk = link[k];
                uint64_t p = bp[k >> 3];
                uint32_t by = (uint32_t)(nxt[k] - cur_off);
                uint8_t m = msk[k];
                while (by < nbytes) { seg[by] |= m; by += (uint32_t)p; }
                uint64_t gb = (uint64_t)by + cur_off;
                if (gb < chunk_bytes) {
                    nxt[k] = (uint32_t)gb;
                    uint32_t slot = (uint32_t)(((gb - cur_off) / seg_bytes + rp) % ring);
                    link[k] = head[slot];
                    head[slot] = k;
                }
                k = nk;
            }
        }

        /* count (or enumerate) */
        if (!want && !out) {
            uint32_t w = nbytes >> 3;
            const uint64_t *ws = (const uint64_t *)(const void *)seg;
            uint64_t zeros = 0;
            for (uint32_t i = 0; i < w; i++) zeros += 64 - (uint64_t)__builtin_popcountll(ws[i]);
            for (uint32_t i = w << 3; i < nbytes; i++) zeros += 8 - (uint64_t)__builtin_popcount(seg[i]);
            count += zeros;
        } else {
            for (uint32_t i = 0; i < nbytes; i++) {
                uint8_t v = seg[i];
                if (v == 0xFF) continue;
                uint64_t bb = seg_lo_byte + i;
                for (int j = 0; j < 8; j++) {
                    if (v & (1u << j)) continue;
                    count++;
                    uint64_t prime = 30 * bb + W30_R[j];
                    if (out && *out_n < out_cap) out[(*out_n)++] = prime;
                    if (want && count == want) { if (found) *found = prime; return count; }
                }
            }
        }
        rp++;
        if (rp >= ring) rp = 0;
    }
    return count;
}

/* Base primes in [23, root], coprime to 30 (7..19 are handled by the presieve
 * pattern, so the marching list starts above them). */
static uint64_t *w_p30_base_primes(uint64_t root, int *out_n) {
    uint64_t half = root / 2 + 1;
    uint8_t *comp = (uint8_t *)calloc(half + 2, 1);
    uint64_t *bp = (uint64_t *)malloc((size_t)(half / 2 + 64) * sizeof(uint64_t));
    if (!comp || !bp) { free(comp); free(bp); *out_n = 0; return NULL; }
    for (uint64_t i = 1, p = 3; p * p <= root; i++, p = 2 * i + 1) {
        if (comp[i]) continue;
        for (uint64_t j = (p * p - 1) / 2; j <= half; j += p) comp[j] = 1;
    }
    int n = 0;
    for (uint64_t k = 1; 2 * k + 1 <= root; k++) {
        uint64_t q = 2 * k + 1;
        if (!comp[k] && q >= 23 && q % 3 && q % 5) bp[n++] = q;
    }
    free(comp);
    *out_n = n;
    return bp;
}

static int w_p30_threads(void) {
    const char *e = getenv("TUNGSTEN_PRIME_THREADS");
    if (e && *e) { int t = atoi(e); if (t > 0) return t > 64 ? 64 : t; }
    long ncpu = sysconf(_SC_NPROCESSORS_ONLN);
    if (ncpu < 2) return 1;
    long t = ncpu - 1;                 /* leave one core for the OS + main thread */
    return (int)(t > 64 ? 64 : t);
}

typedef struct {
    uint64_t lo, hi, chunk, nchunks, root;
    const uint64_t *bp; int nbp;
    const uint8_t *pat;
    uint32_t seg_bytes;
    _Atomic uint64_t next;
    uint64_t *counts;
    int failed;
} WP30Run;

static void *w_p30_worker(void *arg) {
    WP30Run *r = (WP30Run *)arg;
    WP30Scratch sc;
    if (!w_p30_scratch_init(&sc, r->nbp, r->root, r->seg_bytes)) { r->failed = 1; return NULL; }
    for (;;) {
        uint64_t c = atomic_fetch_add(&r->next, (uint64_t)1);
        if (c >= r->nchunks) break;
        uint64_t clo = r->lo + c * r->chunk;
        uint64_t chi = clo + r->chunk;
        if (chi > r->hi) chi = r->hi;
        r->counts[c] = w_p30_chunk(clo, chi, r->bp, r->nbp, r->pat, &sc, 0, NULL, NULL, 0, NULL);
    }
    w_p30_scratch_free(&sc);
    return NULL;
}

/* Count the wheel-candidate primes in [lo,hi), both multiples of 30, in
 * parallel. counts_out (optional) receives the per-chunk tallies. */
static uint64_t w_p30_sieve_parallel(uint64_t lo, uint64_t hi, uint64_t root,
                                     const uint64_t *bp, int nbp, const uint8_t *pat,
                                     uint64_t **counts_out, uint64_t *chunk_out,
                                     uint64_t *nchunks_out) {
    if (hi <= lo) return 0;
    int T = w_p30_threads();
    uint64_t span = hi - lo;
    /* ~4 chunks per thread so a slow chunk cannot strand a core, but never
     * smaller than 4 segments (chunk setup costs nbp divisions). */
    uint64_t chunk = span / ((uint64_t)T * 4) + 1;
    uint64_t minchunk = (uint64_t)W_P30_SEG_BYTES * 30 * 4;
    if (chunk < minchunk) chunk = minchunk;
    chunk = (chunk / 30) * 30;
    if (chunk == 0) chunk = 30;
    uint64_t nchunks = (span + chunk - 1) / chunk;

    uint64_t *counts = (uint64_t *)calloc((size_t)nchunks + 1, sizeof(uint64_t));
    if (!counts) return 0;

    WP30Run run;
    run.lo = lo; run.hi = hi; run.chunk = chunk; run.nchunks = nchunks; run.root = root;
    run.bp = bp; run.nbp = nbp; run.pat = pat; run.seg_bytes = W_P30_SEG_BYTES;
    run.counts = counts; run.failed = 0;
    atomic_init(&run.next, (uint64_t)0);

    int nth = (int)(nchunks < (uint64_t)T ? nchunks : (uint64_t)T);
    pthread_t th[64];
    int live = 0;
    for (int t = 1; t < nth; t++)
        if (pthread_create(&th[live], NULL, w_p30_worker, &run) == 0) live++;
    w_p30_worker(&run);                       /* the caller is a worker too */
    for (int t = 0; t < live; t++) pthread_join(th[t], NULL);

    uint64_t total = 0;
    for (uint64_t c = 0; c < nchunks; c++) total += counts[c];
    if (counts_out) { *counts_out = counts; } else { free(counts); }
    if (chunk_out) *chunk_out = chunk;
    if (nchunks_out) *nchunks_out = nchunks;
    return total;
}

/* π(lo..hi) inclusive, via the mod-30 bit sieve. Edge candidates outside the
 * 30-aligned window are resolved with the scalar test (at most 8 per side). */
uint64_t w_p30_count_u64(uint64_t lo, uint64_t hi) {
    if (hi < 2 || hi < lo) return 0;
    if (lo < 2) lo = 2;
    uint64_t count = 0;
    if (lo <= 2 && hi >= 2) count++;
    if (lo <= 3 && hi >= 3) count++;
    if (lo <= 5 && hi >= 5) count++;
    if (hi < 7) return count;
    if (lo < 7) lo = 7;

    uint64_t alo = (lo / 30) * 30;
    uint64_t ahi = ((hi / 30) + 1) * 30;
    uint64_t root = w_isqrt_u64(hi);
    int nbp = 0;
    uint64_t *bp = w_p30_base_primes(root, &nbp);
    uint8_t *pat = w_p30_pattern();
    if (!bp || !pat) { free(bp); free(pat); return count; }

    count += w_p30_sieve_parallel(alo, ahi, root, bp, nbp, pat, NULL, NULL, NULL);
    /* drop candidates that fell outside [lo,hi] */
    for (uint64_t x = alo; x < lo; x++)
        if (W30_BIT[x % 30] >= 0 && x > 1 && w_prime_test_u64(x)) count--;
    for (uint64_t x = hi + 1; x < ahi; x++)
        if (W30_BIT[x % 30] >= 0 && w_prime_test_u64(x)) count--;
    free(bp); free(pat);
    return count;
}

/* ---- prime checkpoints -------------------------------------------------
 * Each entry is (n, p_n): the n-th prime. One table serves both directions —
 *   nth_prime(n)  : exact hit returns immediately; otherwise sieve forward
 *                   from p_k needing only n - k more primes.
 *   pi(0..N)      : = k + (primes in (p_k, N]), so the sieve skips everything
 *                   below the checkpoint.
 * Entries are spaced 1,2,…,9 per decade of n (a log10 ladder), which bounds
 * the residual range at ~1/2 of N in the worst case and 0 on an exact hit.
 * Every entry at or below n = 1e11 was computed by this sieve (see
 * tools/gen_prime_lut); the entries above it are the published values of
 * A006988 and are not independently verified here. */
typedef struct { uint64_t n, p; } WPrimeCk;
static const WPrimeCk W_PRIME_CK[] = {
#include "prime_lut.inc"
};
#define W_PRIME_CK_N (sizeof(W_PRIME_CK) / sizeof(W_PRIME_CK[0]))

/* largest checkpoint with n ≤ want (NULL if none) */
static const WPrimeCk *w_prime_ck_by_rank(uint64_t want) {
    const WPrimeCk *best = NULL;
    for (size_t i = 0; i < W_PRIME_CK_N; i++) {
        if (W_PRIME_CK[i].n <= want) best = &W_PRIME_CK[i]; else break;
    }
    return best;
}

/* largest checkpoint with p ≤ x (NULL if none) */
static const WPrimeCk *w_prime_ck_by_value(uint64_t x) {
    const WPrimeCk *best = NULL;
    for (size_t i = 0; i < W_PRIME_CK_N; i++) {
        if (W_PRIME_CK[i].p <= x) best = &W_PRIME_CK[i]; else break;
    }
    return best;
}

/* Count primes in (after, hi]: sieve forward from a checkpoint. */
static uint64_t w_p30_count_above(uint64_t after, uint64_t hi) {
    if (hi <= after) return 0;
    uint64_t count = 0;
    uint64_t lo = after + 1;
    uint64_t alo = (lo / 30) * 30;
    uint64_t ahi = ((hi / 30) + 1) * 30;
    uint64_t root = w_isqrt_u64(hi);
    int nbp = 0;
    uint64_t *bp = w_p30_base_primes(root, &nbp);
    uint8_t *pat = w_p30_pattern();
    if (!bp || !pat) { free(bp); free(pat); return 0; }
    count = w_p30_sieve_parallel(alo, ahi, root, bp, nbp, pat, NULL, NULL, NULL);
    for (uint64_t x = alo; x < lo; x++)
        if (W30_BIT[x % 30] >= 0 && x > 1 && w_prime_test_u64(x)) count--;
    for (uint64_t x = hi + 1; x < ahi; x++)
        if (W30_BIT[x % 30] >= 0 && w_prime_test_u64(x)) count--;
    free(bp); free(pat);
    return count;
}

/* π(0..hi) with the checkpoint skip. */
uint64_t w_prime_pi_u64(uint64_t hi) {
    if (hi < 2) return 0;
    const WPrimeCk *ck = w_prime_ck_by_value(hi);
    if (!ck) return w_p30_count_u64(2, hi);
    if (ck->p == hi) return ck->n;
    return ck->n + w_p30_count_above(ck->p, hi);
}

/* The n-th prime, seeded from (rank0, prime0) — the LUT generator walks the
 * ladder with this, each rung seeded by the one below it. */
static uint64_t w_nth_prime_from(uint64_t n, uint64_t rank0, uint64_t prime0) {
    static const uint64_t TINY[9] = {2, 3, 5, 7, 11, 13, 17, 19, 23};
    if (n == 0) return 0;
    if (n <= 9 && rank0 == 0) return TINY[n - 1];
    if (n == rank0) return prime0;

    uint64_t need = n - rank0;
    /* Dusart: p_n < n(ln n + ln ln n) for n ≥ 6 — a safe upper end. */
    double dn = (double)n;
    double ln = log(dn), lnln = log(ln > 1.0 ? ln : 2.0);
    uint64_t hi = (uint64_t)(dn * (ln + lnln)) + 64;
    uint64_t lo = ((prime0 ? prime0 : 6) / 30) * 30 + 30;
    if (hi <= lo) hi = lo + 30;

    /* primes between the checkpoint and the aligned window start */
    for (uint64_t x = prime0 + 1; x < lo; x++)
        if (w_prime_test_u64(x)) { if (--need == 0) return x; }

    uint64_t root_hi = hi;
    for (;;) {
        uint64_t ahi = ((root_hi / 30) + 1) * 30;
        uint64_t root = w_isqrt_u64(ahi);
        int nbp = 0;
        uint64_t *bp = w_p30_base_primes(root, &nbp);
        uint8_t *pat = w_p30_pattern();
        if (!bp || !pat) { free(bp); free(pat); return 0; }

        uint64_t *counts = NULL, chunk = 0, nchunks = 0;
        uint64_t total = w_p30_sieve_parallel(lo, ahi, root, bp, nbp, pat,
                                              &counts, &chunk, &nchunks);
        if (total >= need) {
            uint64_t acc = 0, c = 0;
            for (; c < nchunks; c++) {
                if (acc + counts[c] >= need) break;
                acc += counts[c];
            }
            uint64_t clo = lo + c * chunk;
            uint64_t chi = clo + chunk;
            if (chi > ahi) chi = ahi;
            WP30Scratch sc;
            uint64_t found = 0;
            if (w_p30_scratch_init(&sc, nbp, root, W_P30_SEG_BYTES)) {
                w_p30_chunk(clo, chi, bp, nbp, pat, &sc, need - acc, &found, NULL, 0, NULL);
                w_p30_scratch_free(&sc);
            }
            free(counts); free(bp); free(pat);
            return found;
        }
        /* undershot the estimate — extend and try again */
        need -= total;
        lo = ahi;
        root_hi = ahi + ahi / 16 + 1000;
        free(counts); free(bp); free(pat);
    }
}

uint64_t w_nth_prime_u64(uint64_t n) {
    if (n == 0) return 0;
    const WPrimeCk *ck = w_prime_ck_by_rank(n);
    if (ck && ck->n == n) return ck->p;
    return w_nth_prime_from(n, ck ? ck->n : 0, ck ? ck->p : 0);
}

/* WValue wrappers */
WValue w_nth_prime_u64_w(WValue n) {
    return w_int((int64_t)w_nth_prime_u64((uint64_t)w_as_int(n)));
}
WValue w_prime_pi_u64_w(WValue hi) {
    return w_int((int64_t)w_prime_pi_u64((uint64_t)w_as_int(hi)));
}



/* ---- Int.primes(n): the first n primes, in order ------------------------
 * Two passes over the same chunk decomposition: pass 1 counts each chunk in
 * parallel (that is the expensive part), a prefix sum turns those counts into
 * write offsets, and pass 2 re-sieves each chunk in parallel writing straight
 * into its own slice of the output. No locks, no ordering problem. */
typedef struct {
    uint64_t lo, chunk, nchunks, root, cap;
    const uint64_t *bp; int nbp;
    const uint8_t *pat;
    const uint64_t *offs;      /* write offset of each chunk */
    const uint64_t *counts;
    uint64_t *out;
    _Atomic uint64_t next;
} WP30Fill;

static void *w_p30_fill_worker(void *arg) {
    WP30Fill *f = (WP30Fill *)arg;
    WP30Scratch sc;
    if (!w_p30_scratch_init(&sc, f->nbp, f->root, W_P30_SEG_BYTES)) return NULL;
    for (;;) {
        uint64_t c = atomic_fetch_add(&f->next, (uint64_t)1);
        if (c >= f->nchunks) break;
        if (f->offs[c] >= f->cap) continue;
        uint64_t clo = f->lo + c * f->chunk;
        uint64_t chi = clo + f->chunk;
        uint64_t room = f->cap - f->offs[c];
        uint64_t wrote = 0;
        w_p30_chunk(clo, chi, f->bp, f->nbp, f->pat, &sc, 0, NULL,
                    f->out + f->offs[c], room, &wrote);
    }
    w_p30_scratch_free(&sc);
    return NULL;
}

/* Fills out[0..n) with the first n primes. Returns how many were written. */
static uint64_t w_primes_first_fill(uint64_t n, uint64_t *out) {
    if (n == 0) return 0;
    static const uint64_t SMALL[3] = {2, 3, 5};
    uint64_t head = n < 3 ? n : 3;
    for (uint64_t i = 0; i < head; i++) out[i] = SMALL[i];
    if (n <= 3) return n;

    uint64_t need = n - 3;              /* the wheel supplies everything ≥ 7 */
    double dn = (double)n;
    double ln = log(dn < 6.0 ? 6.0 : dn), lnln = log(ln > 1.0 ? ln : 2.0);
    uint64_t hi = (uint64_t)(dn * (ln + lnln)) + 64;
    uint64_t lo = 0;

    for (;;) {
        uint64_t ahi = ((hi / 30) + 1) * 30;
        uint64_t root = w_isqrt_u64(ahi);
        int nbp = 0;
        uint64_t *bp = w_p30_base_primes(root, &nbp);
        uint8_t *pat = w_p30_pattern();
        if (!bp || !pat) { free(bp); free(pat); return head; }

        uint64_t *counts = NULL, chunk = 0, nchunks = 0;
        uint64_t total = w_p30_sieve_parallel(lo, ahi, root, bp, nbp, pat,
                                              &counts, &chunk, &nchunks);
        if (total < need) {                       /* estimate fell short */
            free(counts); free(bp); free(pat);
            hi += hi / 8 + 1000;
            continue;
        }
        uint64_t *offs = (uint64_t *)malloc((size_t)(nchunks + 1) * sizeof(uint64_t));
        if (!offs) { free(counts); free(bp); free(pat); return head; }
        uint64_t acc = 0;
        for (uint64_t c = 0; c < nchunks; c++) { offs[c] = acc; acc += counts[c]; }

        WP30Fill f;
        f.lo = lo; f.chunk = chunk; f.nchunks = nchunks; f.root = root; f.cap = need;
        f.bp = bp; f.nbp = nbp; f.pat = pat; f.offs = offs; f.counts = counts;
        f.out = out + 3;
        atomic_init(&f.next, (uint64_t)0);
        int T = w_p30_threads();
        int nth = (int)(nchunks < (uint64_t)T ? nchunks : (uint64_t)T);
        pthread_t th[64];
        int live = 0;
        for (int t = 1; t < nth; t++)
            if (pthread_create(&th[live], NULL, w_p30_fill_worker, &f) == 0) live++;
        w_p30_fill_worker(&f);
        for (int t = 0; t < live; t++) pthread_join(th[t], NULL);

        free(offs); free(counts); free(bp); free(pat);
        return n;
    }
}

WValue w_primes_first_w(WValue nv) {
    int64_t n = w_as_int(nv);
    if (n < 0) n = 0;
    if (n > 200000000LL)
        w_raise(w_string("Int.primes: refusing above 200M primes (1.6 GB) — sieve a range instead"));
    WValue arr = w_array_zeros(66, n);          /* ebits 66 = i64 */
    if (n == 0) return arr;
    WArray *a = w_as_array(arr);
    uint64_t *out = (uint64_t *)a->slots + a->start;
    w_primes_first_fill((uint64_t)n, out);
    return arr;
}

/* π(lo..hi) — the public entry point the fused `range /prime? :count`
 * pipeline calls. Routes to the mod-30 bit sieve, and uses the prime
 * checkpoints to skip the range below the nearest tabulated prime when that
 * is cheaper than sieving it. w_prime_count_u64_mod6 is the previous mod-6
 * byte-per-candidate implementation, kept as a cross-check oracle. */
uint64_t w_prime_count_u64(uint64_t lo, uint64_t hi) {
    if (hi < 2 || hi < lo) return 0;
    if (lo < 2) lo = 2;
    if (lo == 2) return w_prime_pi_u64(hi);
    const WPrimeCk *ch = w_prime_ck_by_value(hi);
    const WPrimeCk *cl = w_prime_ck_by_value(lo - 1);
    uint64_t direct = hi - lo;
    uint64_t viack = (ch ? hi - ch->p : hi) + (cl ? (lo - 1) - cl->p : lo);
    if (ch && viack < direct) return w_prime_pi_u64(hi) - w_prime_pi_u64(lo - 1);
    return w_p30_count_u64(lo, hi);
}

/* Build-time preflight. macOS runs a first-execution malware scan
 * (AppleSystemPolicy -> syspolicyd -> XProtect YARA) on every new executable
 * vnode, ~150-250 ms, keyed by vnode and cached until the file is replaced —
 * and clang -o replaces the file on every link. The compiler therefore spawns
 * each freshly linked binary once with TUNGSTEN_PREFLIGHT set, detached, so
 * the scan happens during the build's tail instead of the user's first run.
 * This must be the first thing main does: the scan completes during exec, so
 * exiting here is enough, and nothing observable has happened yet. */
void w_preflight(void) {
    const char *e = getenv("TUNGSTEN_PREFLIGHT");
    if (e && *e) _exit(0);
}

/* Number of cores this machine will actually run threads on — the same
 * answer as System.cpu_count (w_cpu_count), exposed raw for call_direct_i64
 * and as a __w_ builtin. */
int64_t w_cpu_count_i64(void) { return w_as_int(w_cpu_count()); }
WValue __w_cpu_count(void) { return w_cpu_count(); }

/* L1 data-cache size in bytes for the cores work actually runs on. Apple
 * Silicon's generic hw.l1dcachesize reports the E-core (64 KB on M3 Max);
 * hw.perflevel0.l1dcachesize is the P-core (128 KB), which is what a
 * cache-sized sieve segment should match. Falls back to 128 KB. */
int64_t w_l1d_cache_bytes_i64(void) {
#ifdef __APPLE__
    int64_t v = 0; size_t len = sizeof(v);
    if (sysctlbyname("hw.perflevel0.l1dcachesize", &v, &len, NULL, 0) == 0 && v > 0) return v;
    len = sizeof(v);
    if (sysctlbyname("hw.l1dcachesize", &v, &len, NULL, 0) == 0 && v > 0) return v;
#endif
    return 128 * 1024;
}
WValue __w_l1d_cache_bytes(void) { return w_int(w_l1d_cache_bytes_i64()); }

/* L2 cache bytes for the same cores (P-core perflevel on Apple Silicon; the
 * generic hw.l2cachesize reports the E-core's). Falls back to 4 MB. */
int64_t w_l2_cache_bytes_i64(void) {
#ifdef __APPLE__
    int64_t v = 0; size_t len = sizeof(v);
    if (sysctlbyname("hw.perflevel0.l2cachesize", &v, &len, NULL, 0) == 0 && v > 0) return v;
    len = sizeof(v);
    if (sysctlbyname("hw.l2cachesize", &v, &len, NULL, 0) == 0 && v > 0) return v;
#endif
    return 4 * 1024 * 1024;
}
WValue __w_l2_cache_bytes(void) { return w_int(w_l2_cache_bytes_i64()); }

/* Cores sharing one L2 (the P-core cluster on Apple Silicon: hw.perflevel0
 * .cpusperl2; hw.cacheconfig[2] otherwise). The per-core L2 share is
 * l2_cache_bytes / cpus_per_l2 — what a thread can count on when every core
 * of its cluster is busy. Falls back to 1. */
int64_t w_cpus_per_l2_i64(void) {
#ifdef __APPLE__
    int64_t v = 0; size_t len = sizeof(v);
    if (sysctlbyname("hw.perflevel0.cpusperl2", &v, &len, NULL, 0) == 0 && v > 0) return v;
    uint64_t cfg[8] = {0}; len = sizeof(cfg);
    if (sysctlbyname("hw.cacheconfig", cfg, &len, NULL, 0) == 0 && cfg[2] > 0) return (int64_t)cfg[2];
#endif
    return 1;
}
WValue __w_cpus_per_l2(void) { return w_int(w_cpus_per_l2_i64()); }

int64_t w_host_cache_bytes_extern(WValue name_wv) {
#ifdef __APPLE__
    char ibuf[6];
    const char *ptr;
    size_t len;
    if (!w_is_stringy(name_wv)) return 0;
    w_str_data(name_wv, ibuf, &ptr, &len);
    if (len == 15 && memcmp(ptr, "l1d_cache_bytes", 15) == 0) {
        int64_t v = 0; size_t slen = sizeof(v);
        if (sysctlbyname("hw.perflevel0.l1dcachesize", &v, &slen, NULL, 0) == 0 && v > 0) return v;
        slen = sizeof(v);
        if (sysctlbyname("hw.l1dcachesize", &v, &slen, NULL, 0) == 0 && v > 0) return v;
        return 0;
    }
    if (len == 14 && memcmp(ptr, "l2_cache_bytes", 14) == 0) {
        int64_t v = 0; size_t slen = sizeof(v);
        if (sysctlbyname("hw.perflevel0.l2cachesize", &v, &slen, NULL, 0) == 0 && v > 0) return v;
        slen = sizeof(v);
        if (sysctlbyname("hw.l2cachesize", &v, &slen, NULL, 0) == 0 && v > 0) return v;
        return 0;
    }
    if (len == 11 && memcmp(ptr, "cpus_per_l2", 11) == 0) {
        int64_t v = 0; size_t slen = sizeof(v);
        if (sysctlbyname("hw.perflevel0.cpusperl2", &v, &slen, NULL, 0) == 0 && v > 0) return v;
        uint64_t cfg[8] = {0}; slen = sizeof(cfg);
        if (sysctlbyname("hw.cacheconfig", cfg, &slen, NULL, 0) == 0 && cfg[2] > 0) return (int64_t)cfg[2];
        return 0;
    }
#else
    (void)name_wv;
#endif
    return 0;
}

/* Raw-i64 entry points for prime?/prime_12k?/prime_30k? on a known-Int receiver.
 * The compiled lowering calls these directly (call_direct_i64), skipping WValue
 * method/IC dispatch entirely in ordinary (non-fused) loops. Return 0/1;
 * negative ⇒ not prime (mirrors w_ic_int_prime_q's n<0 guard). */
int64_t w_prime_test_i64(int64_t n)     { return (n < 0) ? 0 : (int64_t)w_prime_test_u64((uint64_t)n); }
int64_t w_prime_test_i64_12k(int64_t n) { return (n < 0) ? 0 : (int64_t)w_prime_test_u64_12k((uint64_t)n); }
int64_t w_prime_test_i64_30k(int64_t n) { return (n < 0) ? 0 : (int64_t)w_prime_test_u64_30k((uint64_t)n); }

/* BigInt path for n ≥ 2⁶⁴: the same Miller-Rabin on BigInt WValues, using the
 * runtime's bigint-aware w_mul/w_mod/w_sub/w_div. Slower (heap temporaries per
 * op) but primality at this scale is rare. Caller guarantees n is a positive
 * bigint, so n is far larger than any small prime. */
static WValue w_prime_bn_mulmod(WValue a, WValue b, WValue m) {
    return w_mod(w_mul(a, b), m);
}

/* Montgomery (CIOS) applies for odd one-limb and 3..W_MONT_MAX_LIMBS moduli:
 * k=2 has a dedicated register-Barrett path; above the cap, Barrett's
 * subquadratic multiplies beat CIOS's fixed 2k² schoolbook. */
#ifndef W_MONT_MAX_LIMBS
#define W_MONT_MAX_LIMBS 96
#endif
/* Keep CIOS storage independent of the policy cutoff so threshold tuning does
 * not reshape this function (or every function laid out after it).  CIOS is
 * used once during Montgomery context setup even when timed products use SOS. */
#ifndef W_MONT_CIOS_CAPACITY
#define W_MONT_CIOS_CAPACITY 128
#endif
#if W_MONT_MAX_LIMBS > W_MONT_CIOS_CAPACITY
#error "W_MONT_MAX_LIMBS exceeds W_MONT_CIOS_CAPACITY"
#endif

typedef struct {
    WValue modulus;
    WValue mu;
    WValue bkp1;
    int32_t limbs;
    uint64_t *work;           /* limb scratch for Barrett mulmod (one calloc per test) */
    int32_t work_cap;         /* limb count of work[] */
    WBigint *slot[3];         /* rotating result buffers — avoids per-mul bigint_alloc */
    WValue slotv[3];
    int sloti;
    /* Montgomery domain (mont != 0): modctx_mul computes a·b·R⁻¹ mod n via CIOS
     * (R = 2^(64k)); values live in the domain (x ↔ xR mod n). Zero is domain-
     * invariant, and callers compare only against one_m / nm1_m, so nothing ever
     * converts out. In Barrett mode one_m = 1 and nm1_m = n−1, keeping the
     * MR/Lucas bodies domain-agnostic. */
    int mont;
    uint64_t nprime;          /* −n⁻¹ mod 2^64 (n odd) */
    WBigint *r2b;  WValue r2v;    /* R² mod n (the μ division's remainder — free) */
    WBigint *onemb; WValue onemv; /* domain image of 1  (mont: R mod n;  else 1) */
    WBigint *nm1mb; WValue nm1mv; /* domain image of n−1 (mont: n − one_m; else n−1) */
} WPrimeModCtx;

/* Montgomery CIOS multiply: out[0..k) = a·b·R⁻¹ mod n, R = 2^(64k), n odd with
 * exactly k limbs, a,b < n (shorter operands zero-padded). Interleaves the
 * multiply and reduction (Koç CIOS): 2k²+k limb-multiplies, no separate q1·μ /
 * q3·n passes and no division anywhere. Column sums fit u128 exactly
 * ((2⁶⁴−1)² + 2·(2⁶⁴−1) = 2¹²⁸−1); the invariant t < 2n holds per iteration, so
 * one conditional subtract finishes. */
static void w_mont_cios_mul(uint64_t *out,
                            const uint64_t *a, int32_t alen,
                            const uint64_t *b, int32_t blen,
                            const uint64_t *n, int32_t k, uint64_t nprime) {
    uint64_t t[W_MONT_CIOS_CAPACITY + 2];
    uint64_t bp[W_MONT_CIOS_CAPACITY];
    for (int32_t j = 0; j < k; j++) bp[j] = j < blen ? b[j] : 0;
    for (int32_t j = 0; j <= k + 1; j++) t[j] = 0;
    for (int32_t i = 0; i < k; i++) {
        uint64_t ai = i < alen ? a[i] : 0;
        uint64_t c = 0;
        for (int32_t j = 0; j < k; j++) {
            __uint128_t s = (__uint128_t)ai * bp[j] + t[j] + c;
            t[j] = (uint64_t)s;
            c = (uint64_t)(s >> 64);
        }
        __uint128_t s = (__uint128_t)t[k] + c;
        t[k] = (uint64_t)s;
        t[k + 1] += (uint64_t)(s >> 64);              /* ≤ 1 */
        uint64_t m = t[0] * nprime;                    /* makes t[0] vanish */
        s = (__uint128_t)m * n[0] + t[0];
        c = (uint64_t)(s >> 64);                       /* low limb is 0 by design */
        for (int32_t j = 1; j < k; j++) {
            s = (__uint128_t)m * n[j] + t[j] + c;
            t[j - 1] = (uint64_t)s;                    /* fused >>64 limb shift */
            c = (uint64_t)(s >> 64);
        }
        s = (__uint128_t)t[k] + c;
        t[k - 1] = (uint64_t)s;
        t[k] = t[k + 1] + (uint64_t)(s >> 64);
        t[k + 1] = 0;
    }
    int ge = t[k] != 0;                                /* t ≥ R > n */
    if (!ge) {
        ge = 1;
        for (int32_t j = k - 1; j >= 0; j--)
            if (t[j] != n[j]) { ge = t[j] > n[j]; break; }
    }
    if (ge) {                                          /* t < 2n ⇒ one subtract */
        uint64_t bw = 0;
        for (int32_t j = 0; j < k; j++) {
            uint64_t tv = t[j] - n[j];
            uint64_t b1 = t[j] < n[j];
            uint64_t d = tv - bw;
            uint64_t b2 = tv < bw;
            t[j] = d;
            bw = b1 | b2;                              /* two-step borrow (all-ones safe) */
        }
    }
    for (int32_t j = 0; j < k; j++) out[j] = t[j];
}

/* SOS Montgomery: T = a·b through the (asm-kernel) fast multiply dispatcher,
 * then REDC as k bn_addmul_1 rows — every inner loop rides the ~1.6 c/l asm
 * kernel, where CIOS's interleaved loops are serial-carry (~2.5 c/l) and, at
 * larger k, forgo Karatsuba on the product half. Wins once the product
 * amortizes the dispatcher call; W_MONT_SOS_MIN gates it and CIOS keeps the
 * small-k path (and serves as the equivalence-fuzz reference). T: 2k+2 limbs
 * of caller scratch (the modctx work buffer, unused in Montgomery mode). */
#ifndef W_MONT_SOS_MIN
#define W_MONT_SOS_MIN 8
#endif
/* REDC half of SOS Montgomery: T[0..2k+1] holds the (zero-padded) product;
 * k bn_addmul_1 rows clear the low limbs, then one conditional subtract.
 * Shared by the multiply and squaring entries. */
static void w_mont_sos_redc(uint64_t *out, uint64_t *T,
                            const uint64_t *n, int32_t k, uint64_t nprime) {
    for (int32_t i = 0; i < k; i++) {
        uint64_t m = T[i] * nprime;                 /* makes T[i] vanish */
        uint64_t c = bn_addmul_1(T + i, n, k, m);
        int32_t p = i + k;
        while (c) { uint64_t old = T[p]; T[p] = old + c; c = (T[p] < old); p++; }
    }
    /* result = T[k..2k] (top slot ≤ 1, standard T < 2n·β^k invariant) */
    int ge = T[2 * k] != 0;
    if (!ge) {
        ge = 1;
        for (int32_t j = k - 1; j >= 0; j--)
            if (T[k + j] != n[j]) { ge = T[k + j] > n[j]; break; }
    }
    if (ge) bn_sub_n(out, T + k, n, k);
    else    for (int32_t j = 0; j < k; j++) out[j] = T[k + j];
}
static void w_mont_sos_mul(uint64_t *out, const uint64_t *a, int32_t alen,
                           const uint64_t *b, int32_t blen,
                           const uint64_t *n, int32_t k, uint64_t nprime,
                           uint64_t *T) {
    for (int32_t i = 0; i <= 2 * k + 1; i++) T[i] = 0;
    int32_t at = alen, bt = blen;
    while (at > 0 && a[at - 1] == 0) at--;
    while (bt > 0 && b[bt - 1] == 0) bt--;
    if (at && bt) bigint_mul_dispatch(T, a, at, b, bt);
    w_mont_sos_redc(out, T, n, k, nprime);
}
/* Squaring twin: the product half rides bigint_sqr_dispatch (~0.7 of a
 * same-size multiply); the REDC half is identical. Modular exponentiation is
 * mostly squarings, so powmod collects most of the sqr/mul gap for free. */
#ifndef W_MONT_SOS_SQR_MIN
#define W_MONT_SOS_SQR_MIN W_MONT_SOS_MIN
#endif
static void w_mont_sos_sqr(uint64_t *out, const uint64_t *a, int32_t alen,
                           const uint64_t *n, int32_t k, uint64_t nprime,
                           uint64_t *T) {
    for (int32_t i = 0; i <= 2 * k + 1; i++) T[i] = 0;
    int32_t at = alen;
    while (at > 0 && a[at - 1] == 0) at--;
    if (at) bigint_sqr_dispatch(T, a, at);
    w_mont_sos_redc(out, T, n, k, nprime);
}

/* ---- powmod's dual-row REDC (aarch64) ----
 * REDC rows come in pairs: m = (T[i] + T[i+1]·B)·(−n⁻¹ mod B²) mod B², then
 * one fused two-scalar pass T += m·n — half the T-row load/store traffic of
 * two bn_addmul_1 rows and ~10% faster end to end. Only powmod uses it; the
 * primality paths keep w_mont_sos_redc untouched. */
#if defined(__aarch64__)
#define W_POWM_REDC2 1
/* rp[0..n) += up[0..n) · (v0 + v1·B); the leftover carry pair is added into
 * rp[n], rp[n+1]; returns the final 0/1 carry beyond rp[n+1]. The carry pair
 * obeys c ≤ v0 + v1·B + 1, so its high limb cannot wrap while v0 and v1 are
 * not simultaneously all-ones — the caller guards that (rare) pair. */
__attribute__((naked, noinline, aligned(64)))
static uint64_t bn_powm_addmul_2(uint64_t *rp, const uint64_t *up, int32_t n,
                                 uint64_t v0, uint64_t v1) {
    __asm__(
        "mov x5, xzr\n"            /* c0 */
        "mov x6, xzr\n"            /* c1 */
        "tbz w2, #0, 1f\n"
        "ldr x7, [x1], #8\n"       /* odd-length prefix limb */
        "mul x9, x7, x3\n"
        "umulh x10, x7, x3\n"
        "mul x11, x7, x4\n"
        "umulh x12, x7, x4\n"
        "ldr x8, [x0]\n"
        "adds x9, x9, x8\n"
        "adcs x5, x10, x11\n"
        "adc  x6, x12, xzr\n"
        "str x9, [x0], #8\n"
        "1:\n"
        "lsr w2, w2, #1\n"
        "cbz w2, 3f\n"
        "2:\n"
        "ldp x7, x8, [x1], #16\n"
        "mul   x9,  x7, x3\n"      /* l00 */
        "umulh x10, x7, x3\n"      /* h00 */
        "mul   x11, x7, x4\n"      /* l01 */
        "umulh x12, x7, x4\n"      /* h01 */
        "mul   x13, x8, x3\n"      /* l10 */
        "umulh x14, x8, x3\n"      /* h10 */
        "mul   x15, x8, x4\n"      /* l11 */
        "umulh x16, x8, x4\n"      /* h11 */
        /* carry-independent accumulation (not loop-carried) */
        "adds  x10, x10, x11\n"    /* s1 = h00 + l01 */
        "cset  x11, hs\n"
        "adds  x10, x10, x13\n"    /* s1 += l10 */
        "cinc  x11, x11, hs\n"     /* f12 ≤ 2 */
        "adds  x12, x12, x14\n"    /* c0acc = h01 + h10 */
        "cset  x14, hs\n"
        "adds  x12, x12, x15\n"    /* c0acc += l11 */
        "cinc  x14, x14, hs\n"
        "adds  x12, x12, x11\n"    /* c0acc += f12 */
        "cinc  x14, x14, hs\n"     /* f34 ≤ 3 */
        "add   x16, x16, x14\n"    /* c1acc = h11 + f34 */
        /* memory chain */
        "ldp x7, x8, [x0]\n"
        "adds  x9,  x9,  x7\n"     /* t0 = l00 + r0 */
        "adcs  x10, x10, x8\n"     /* t1 = s1 + r1 */
        "adcs  x12, x12, xzr\n"
        "adc   x16, x16, xzr\n"
        /* short loop-carried chain */
        "adds  x9,  x9,  x5\n"     /* t0 += c0 */
        "adcs  x10, x10, x6\n"     /* t1 += c1 */
        "adcs  x5,  x12, xzr\n"    /* c0 out */
        "adc   x6,  x16, xzr\n"    /* c1 out */
        "stp x9, x10, [x0], #16\n"
        "sub w2, w2, #1\n"
        "cbnz w2, 2b\n"
        "3:\n"
        "ldp x7, x8, [x0]\n"
        "adds x7, x7, x5\n"
        "adcs x8, x8, x6\n"
        "stp x7, x8, [x0]\n"
        "cset x0, hs\n"
        "ret\n"
    );
}

/* ITEM 2 (round 3): fold each two-row REDC pass into a SINGLE bn_addmul_2
 * pass instead of two bn_addmul_1 rows, halving the accumulator/memory
 * traffic of the pair.  bn_addmul_2(rp, up, k, m0, m1) accumulates
 * rp[0..k) += n·(m0 + m1·B) in place, WRITES rp[k] = c0 (the column-(i+k)
 * carry) and RETURNS c1 (the column-(i+k+1) carry).  c0 and c1 map exactly
 * onto the pair's two parked carries, so the T layout, the parked-carry
 * fold, and the conditional final subtract are all unchanged.  Unlike the
 * naked bn_powm_addmul_2, the item-18 bn_addmul_2 family carries no
 * all-ones restriction on (m0,m1), so no guard is needed.  The classic
 * two-addmul_1 path stays byte-identical under the knob off. */
#ifndef BN_POWM_REDC_ADDMUL2
#define BN_POWM_REDC_ADDMUL2 1
#endif
static inline __attribute__((always_inline))
void w_powm_redc2_pair(uint64_t *T, const uint64_t *n, int32_t k,
                       uint64_t np0, uint64_t np1, int32_t i) {
    uint64_t t0 = T[i], t1 = T[i + 1];
    __uint128_t p = (__uint128_t)t0 * np0;
    uint64_t m0 = (uint64_t)p;
    uint64_t m1 = (uint64_t)(p >> 64) + t0 * np1 + t1 * np0;
    uint64_t saved = T[i + k];
#if BN_POWM_REDC_ADDMUL2 && BN_ADDMUL_2
    uint64_t cy1 = bn_addmul_2(T + i, n, k, m0, m1); /* writes T[i+k] = c0 */
    T[i] = T[i + k];      /* retired slot i <- c0 (column i+k) */
    T[i + 1] = cy1;       /* retired slot i+1 <- c1 (column i+k+1) */
#else
    T[i + k] = bn_addmul_1(T + i, n, k, m0);         /* park cy0 on top */
    uint64_t cy1 = bn_addmul_1(T + i + 1, n, k, m1); /* absorbs parked cy0 */
    T[i] = T[i + k];      /* retired slot i <- carry for column i+k */
    T[i + 1] = cy1;       /* retired slot i+1 <- carry for column i+k+1 */
#endif
    T[i + k] = saved;
}

static inline __attribute__((always_inline))
void w_powm_redc2_finish(uint64_t *out, uint64_t *T, const uint64_t *n,
                         int32_t k) {
    uint64_t cy = bn_add_n(out, T + k, T, k);
    int ge = cy != 0;
    if (!ge) {
        ge = 1;
        for (int32_t j = k - 1; j >= 0; j--)
            if (out[j] != n[j]) { ge = out[j] > n[j]; break; }
    }
    if (ge) bn_sub_n(out, out, n, k);
}

#ifndef W_POWM_FIXED_REDC2_FINISH
#define W_POWM_FIXED_REDC2_FINISH 1
#endif
static inline __attribute__((always_inline))
void w_powm_redc2_finish_fixed(uint64_t *out, uint64_t *T,
                               const uint64_t *n, int32_t k) {
#if defined(__aarch64__) && W_POWM_FIXED_REDC2_FINISH
    uint64_t cy = k == 16
        ? bn_add16_fixed(out, T + k, T)
        : bn_add_n(out, T + k, T, k);
#else
    uint64_t cy = bn_add_n(out, T + k, T, k);
#endif
    int ge = cy != 0;
    if (!ge) {
        ge = 1;
        for (int32_t j = k - 1; j >= 0; j--)
            if (out[j] != n[j]) { ge = out[j] > n[j]; break; }
    }
    if (ge) {
#if defined(__aarch64__) && W_POWM_FIXED_REDC2_FINISH
        if (k == 16) bn_sub16_fixed(out, out, n);
        else         bn_sub_n(out, out, n, k);
#else
        bn_sub_n(out, out, n, k);
#endif
    }
}

#ifndef W_POWM_FIXED_REDC2
#define W_POWM_FIXED_REDC2 1
#endif
#ifndef W_POWM_REDC2_BLOCK16
#define W_POWM_REDC2_BLOCK16 1
#endif
#ifndef W_POWM_REDC2_F16
#define W_POWM_REDC2_F16 1
#endif
#if W_POWM_REDC2_F16 && BN_MUL_POWER2_FIXED
#define W_POWM_REDC2_ADD16(rp, up, v) bn_addmul_1_f16((rp), (up), (v))
#elif W_POWM_REDC2_BLOCK16
#define W_POWM_REDC2_ADD16(rp, up, v) bn_addmul_1_blocks((rp), (up), 4, (v))
#else
#define W_POWM_REDC2_ADD16(rp, up, v) bn_addmul_1((rp), (up), 16, (v))
#endif
#if W_POWM_FIXED_REDC2
static void w_powm_redc2_pairs8(uint64_t *out, uint64_t *T,
                                const uint64_t *n, uint64_t np0,
                                uint64_t np1) {
    w_powm_redc2_pair(T, n, 8, np0, np1, 0);
    w_powm_redc2_pair(T, n, 8, np0, np1, 2);
    w_powm_redc2_pair(T, n, 8, np0, np1, 4);
    w_powm_redc2_pair(T, n, 8, np0, np1, 6);
    w_powm_redc2_finish_fixed(out, T, n, 8);
}

static void w_powm_redc2_pairs16(uint64_t *out, uint64_t *T,
                                 const uint64_t *n, uint64_t np0,
                                 uint64_t np1) {
#if BN_POWM_REDC_ADDMUL2 && BN_ADDMUL_2 && BN_MUL_EQ16_ADDMUL2
/* One fixed 16-limb two-row addmul_2 pass per pair (see w_powm_redc2_pair). */
#define W_POWM_REDC2_PAIR16(i) do {                                      \
    uint64_t t0 = T[i], t1 = T[(i) + 1];                                 \
    __uint128_t p = (__uint128_t)t0 * np0;                               \
    uint64_t m0 = (uint64_t)p;                                            \
    uint64_t m1 = (uint64_t)(p >> 64) + t0 * np1 + t1 * np0;             \
    uint64_t saved = T[(i) + 16];                                         \
    uint64_t cy1 = bn_addmul_2_f16(T + (i), n, m0, m1); /* T[i+16]=c0 */  \
    T[i] = T[(i) + 16];                                                    \
    T[(i) + 1] = cy1;                                                      \
    T[(i) + 16] = saved;                                                   \
} while (0)
#else
#define W_POWM_REDC2_PAIR16(i) do {                                      \
    uint64_t t0 = T[i], t1 = T[(i) + 1];                                 \
    __uint128_t p = (__uint128_t)t0 * np0;                               \
    uint64_t m0 = (uint64_t)p;                                            \
    uint64_t m1 = (uint64_t)(p >> 64) + t0 * np1 + t1 * np0;             \
    uint64_t saved = T[(i) + 16];                                         \
    T[(i) + 16] = W_POWM_REDC2_ADD16(T + (i), n, m0);                    \
    uint64_t cy1 = W_POWM_REDC2_ADD16(T + (i) + 1, n, m1);               \
    T[i] = T[(i) + 16];                                                    \
    T[(i) + 1] = cy1;                                                      \
    T[(i) + 16] = saved;                                                   \
} while (0)
#endif
    W_POWM_REDC2_PAIR16(0);
    W_POWM_REDC2_PAIR16(2);
    W_POWM_REDC2_PAIR16(4);
    W_POWM_REDC2_PAIR16(6);
    W_POWM_REDC2_PAIR16(8);
    W_POWM_REDC2_PAIR16(10);
    W_POWM_REDC2_PAIR16(12);
    W_POWM_REDC2_PAIR16(14);
#undef W_POWM_REDC2_PAIR16
    w_powm_redc2_finish_fixed(out, T, n, 16);
}
#endif
#undef W_POWM_REDC2_ADD16

static void w_powm_redc2_pairs(uint64_t *out, uint64_t *T, const uint64_t *n,
                               int32_t k, uint64_t np0, uint64_t np1) {
    int32_t i = 0;
    for (; i + 2 <= k; i += 2)
        w_powm_redc2_pair(T, n, k, np0, np1, i);
    if (i < k) {                                         /* odd k tail row */
        uint64_t m = T[i] * np0;
        T[i] = bn_addmul_1(T + i, n, k, m);
    }
    w_powm_redc2_finish(out, T, n, k);
}

static void w_powm_redc2(uint64_t *out, uint64_t *T, const uint64_t *n,
                         int32_t k, uint64_t np0, uint64_t np1) {
#if W_POWM_FIXED_REDC2
    if (k == 8) { w_powm_redc2_pairs8(out, T, n, np0, np1); return; }
    if (k == 16) { w_powm_redc2_pairs16(out, T, n, np0, np1); return; }
#endif
    if (k >= 8) { w_powm_redc2_pairs(out, T, n, k, np0, np1); return; }
    int32_t i = 0;
    for (; i + 1 < k; i += 2) {
        uint64_t t0 = T[i], t1 = T[i + 1];
        __uint128_t p = (__uint128_t)t0 * np0;
        uint64_t m0 = (uint64_t)p;
        uint64_t m1 = (uint64_t)(p >> 64) + t0 * np1 + t1 * np0;
        if (__builtin_expect((m0 & m1) == ~0ULL, 0)) {
            /* carry-pair invariant guard: split into two classic rows */
            uint64_t c = bn_addmul_1(T + i, n, k, m0);
            int32_t q = i + k;
            while (c) { uint64_t old = T[q]; T[q] = old + c; c = (T[q] < old); q++; }
            c = bn_addmul_1(T + i + 1, n, k, m1);
            q = i + 1 + k;
            while (c) { uint64_t old = T[q]; T[q] = old + c; c = (T[q] < old); q++; }
            continue;
        }
        uint64_t c = bn_powm_addmul_2(T + i, n, k, m0, m1);
        for (int32_t q = i + k + 2; c; q++) {
            uint64_t old = T[q];
            T[q] = old + c;
            c = T[q] < old;
        }
    }
    for (; i < k; i++) {                          /* odd k tail row */
        uint64_t m = T[i] * np0;
        uint64_t c = bn_addmul_1(T + i, n, k, m);
        int32_t q = i + k;
        while (c) { uint64_t old = T[q]; T[q] = old + c; c = (T[q] < old); q++; }
    }
    int ge = T[2 * k] != 0;
    if (!ge) {
        ge = 1;
        for (int32_t j = k - 1; j >= 0; j--)
            if (T[k + j] != n[j]) { ge = T[k + j] > n[j]; break; }
    }
    if (ge) bn_sub_n(out, T + k, n, k);
    else    for (int32_t j = 0; j < k; j++) out[j] = T[k + j];
}
#else
#define W_POWM_REDC2 0
#endif

/* ---- Subquadratic REDC for large even k ----
 * Row-based REDC costs k² limb-products no matter how good the row kernel.
 * Compute m = T_lo·(−n⁻¹ mod B^k) with a truncated product, then recover
 * the needed high half of m·n through a recursive product modulo B^k-1.  The
 * cyclic product replaces one full k-by-k multiply with products of sizes
 * k/2,k/4,... and moves the measured crossover down to 48 limbs.  The k-limb
 * inverse is Newton-lifted once per powmod call and amortized over the ladder. */
#ifndef W_POWM_REDC_MULLO_MIN
#define W_POWM_REDC_MULLO_MIN 48
#endif
#ifndef W_MULLO_BASE_MAX
#define W_MULLO_BASE_MAX 32
#endif
/* out[0..n) = (a·b) mod B^n (basecase: truncated rows) */
static void w_mullo_base(uint64_t *out, const uint64_t *a, const uint64_t *b,
                         int32_t n) {
    if (n == 1) { out[0] = a[0] * b[0]; return; }
#if BN_ADDMUL_2
    (void)bn_mul_2(out, b, n - 1, a[0], a[1]);
    uint64_t top = out[n - 1] + b[n - 1] * a[0];
    int32_t i = 2;
    for (; i + 1 < n; i += 2) {
        int32_t len = n - 1 - i;
        (void)bn_addmul_2(out + i, b, len, a[i], a[i + 1]);
        top += out[n - 1] + b[len] * a[i];
    }
    if (i < n) top += b[0] * a[i];
    out[n - 1] = top;
#else
    (void)bn_mul_1(out, b, n, a[0]);
    for (int32_t i = 1; i < n; i++)
        (void)bn_addmul_1(out + i, b, n - i, a[i]);
#endif
}
/* Karatsuba-style mullo: full a0·b0 + B^h·(mullo(a1,b0) + mullo(a0,b1)).
 * scratch: ≥ n limbs at every level (h cross buffer + recursion). */
static void w_mullo_n(uint64_t *out, const uint64_t *a, const uint64_t *b,
                      int32_t n, uint64_t *scratch) {
    if (n <= W_MULLO_BASE_MAX || (n & 1)) { w_mullo_base(out, a, b, n); return; }
    int32_t h = n >> 1;
    bigint_mul_dispatch(out, a, h, b, h);        /* a0·b0 full: out[0..n) */
    uint64_t *cross = scratch;
    w_mullo_n(cross, a + h, b, h, scratch + h);  /* a1·b0 mod B^h */
    bn_addto(out + h, h, cross, h);
    w_mullo_n(cross, a, b + h, h, scratch + h);  /* a0·b1 mod B^h */
    bn_addto(out + h, h, cross, h);
}
/* Newton lift: mip[0..k) = −n⁻¹ mod B^k from the single-limb inverse.
 * m' = m·(2 + n·m) mod B^{2s}. tmp: 3k limbs. */
static void w_mont_ninv_k(uint64_t *mip, const uint64_t *n, int32_t k,
                          uint64_t np0, uint64_t *tmp) {
    uint64_t *t1 = tmp, *t2 = tmp + k, *sc = tmp + 2 * k;
    mip[0] = np0;
    int32_t cur = 1;
    while (cur < k) {
        int32_t next = 2 * cur <= k ? 2 * cur : k;
        for (int32_t j = cur; j < next; j++) mip[j] = 0;
        w_mullo_n(t1, n, mip, next, sc);         /* n·m mod B^next */
        uint64_t c = 2;                          /* t1 = 2 + t1 */
        for (int32_t j = 0; j < next && c; j++) {
            uint64_t old = t1[j];
            t1[j] = old + c;
            c = t1[j] < old;
        }
        w_mullo_n(t2, mip, t1, next, sc);
        for (int32_t j = 0; j < next; j++) mip[j] = t2[j];
        cur = next;
    }
}

/* Canonical arithmetic modulo B^n-1.  The all-ones word vector is the other
 * representation of zero in this ring; keeping only the ordinary zero makes
 * the CRT reconstruction below unambiguous. */
static inline int w_limbs_zero(const uint64_t *a, int32_t n) {
    for (int32_t i = 0; i < n; i++) if (a[i]) return 0;
    return 1;
}
static inline int w_limbs_all_ones(const uint64_t *a, int32_t n) {
    for (int32_t i = 0; i < n; i++) if (a[i] != UINT64_MAX) return 0;
    return 1;
}
static inline void w_bnm1_canonicalize(uint64_t *a, int32_t n) {
    if (w_limbs_all_ones(a, n))
        memset(a, 0, (size_t)n * sizeof(uint64_t));
}
static void w_bnm1_end_around(uint64_t *a, int32_t n, uint64_t carry) {
    while (carry) {
        int32_t i = 0;
        for (; i < n && carry; i++) {
            uint64_t old = a[i];
            a[i] = old + 1;
            carry = a[i] == 0;
        }
        /* Overflow is another B^n, hence another +1 modulo B^n-1. */
    }
    w_bnm1_canonicalize(a, n);
}
static void w_bnm1_add(uint64_t *out, const uint64_t *a,
                       const uint64_t *b, int32_t n) {
    uint64_t carry = bn_add_n(out, a, b, n);
    w_bnm1_end_around(out, n, carry);
}
static void w_bnm1_sub_one(uint64_t *a, int32_t n) {
    if (w_limbs_zero(a, n)) {
        memset(a, 0xff, (size_t)n * sizeof(uint64_t));
        a[0]--;                       /* -1 mod (B^n-1) = B^n-2 */
        return;
    }
    for (int32_t i = 0; i < n; i++) {
        uint64_t old = a[i];
        a[i] = old - 1;
        if (old) break;
    }
}

/* out = a0-a1 modulo B^n+1, normalized into out[0..n] with a top limb of
 * zero or one.  A top one implies every low limb is zero. */
static void w_bnp1_diff(uint64_t *out, const uint64_t *a0,
                        const uint64_t *a1, int32_t n) {
    uint64_t borrow = bn_sub_n(out, a0, a1, n);
    out[n] = 0;
    if (borrow) {
        uint64_t carry = 1;
        for (int32_t i = 0; i < n && carry; i++) {
            uint64_t old = out[i];
            out[i] = old + 1;
            carry = out[i] == 0;
        }
        out[n] = carry;
    }
}

/* out = -(a[0..n] mod B^n+1), with the same normalized representation.
 * This is safe in place: B^n+1-a is (~a + 2) in the low n limbs. */
static void w_bnp1_neg(uint64_t *out, uint64_t *out_top,
                       const uint64_t *a, int32_t n) {
    if (w_limbs_zero(a, n)) {
        memset(out, 0, (size_t)n * sizeof(uint64_t));
        *out_top = 0;
        return;
    }
    uint64_t carry = 2;
    for (int32_t i = 0; i < n; i++) {
        __uint128_t sum = (__uint128_t)(~a[i]) + carry;
        out[i] = (uint64_t)sum;
        carry = (uint64_t)(sum >> 64);
    }
    *out_top = carry;
}

/* Product modulo B^n+1.  The operands and result use the normalized n+1
 * representation above; product[0..2n) is caller scratch. */
static void w_mulmod_bnp1(uint64_t *out, uint64_t *out_top,
                          const uint64_t *a, uint64_t atop,
                          const uint64_t *b, uint64_t btop,
                          int32_t n, uint64_t *product) {
    if (atop) {
        if (btop) {
            memset(out, 0, (size_t)n * sizeof(uint64_t));
            out[0] = 1;
            *out_top = 0;
        } else {
            w_bnp1_neg(out, out_top, b, n);
        }
        return;
    }
    if (btop) {
        w_bnp1_neg(out, out_top, a, n);
        return;
    }
    bigint_mul_dispatch(product, a, n, b, n);
    uint64_t borrow = bn_sub_n(out, product, product + n, n);
    *out_top = 0;
    if (borrow) {
        uint64_t carry = 1;
        for (int32_t i = 0; i < n && carry; i++) {
            uint64_t old = out[i];
            out[i] = old + 1;
            carry = out[i] == 0;
        }
        *out_top = carry;
    }
}

#ifndef W_BNM1_BASE_MAX
#define W_BNM1_BASE_MAX 8
#endif

/* out = a*b mod B^n-1, canonical in n limbs.  Splitting n=2h, evaluation at
 * B^h=+1 gives one recursive cyclic product; evaluation at B^h=-1 gives one
 * ordinary h-limb product modulo B^h+1.  The two residues reconstruct through
 * CRT.  Thus a 128-limb cyclic product pays 64,32,16,8-limb full products
 * instead of one complete 128-limb product.  scratch need is <4n+4 limbs. */
static void w_mulmod_bnm1(uint64_t *out, const uint64_t *a,
                          const uint64_t *b, int32_t n,
                          uint64_t *scratch) {
    if (n <= W_BNM1_BASE_MAX || (n & 1)) {
        bigint_mul_dispatch(scratch, a, n, b, n);
        uint64_t carry = bn_add_n(out, scratch, scratch + n, n);
        w_bnm1_end_around(out, n, carry);
        return;
    }

    int32_t h = n >> 1;
    uint64_t *ap = scratch;                       /* h+1 */
    uint64_t *bp = ap + h + 1;                    /* h+1 */
    uint64_t *product = bp + h + 1;               /* n */
    uint64_t *child = product + n;                /* recursive scratch */

    /* +1 residue: (a0+a1)(b0+b1) modulo B^h-1. */
    w_bnm1_add(ap, a, a + h, h);
    w_bnm1_add(bp, b, b + h, h);
    w_mulmod_bnm1(out, ap, bp, h, child);          /* xm in out[0..h) */

    /* -1 residue: (a0-a1)(b0-b1) modulo B^h+1. */
    w_bnp1_diff(ap, a, a + h, h);
    w_bnp1_diff(bp, b, b + h, h);
    uint64_t xp_top;
    w_mulmod_bnp1(ap, &xp_top, ap, ap[h], bp, bp[h], h, product);
    ap[h] = xp_top;                                /* xp in ap[0..h] */

    /* q=(xm+xp)/2 mod B^h-1.  Division by two in the Mersenne ring is a
     * one-bit rotate: odd q first borrows the modulus's high bit. */
    memcpy(bp, ap, (size_t)h * sizeof(uint64_t));
    w_bnm1_end_around(bp, h, xp_top);              /* xp mod B^h-1 */
    w_bnm1_add(bp, out, bp, h);
    uint64_t lowbit = bp[0] & 1ULL;
    for (int32_t i = 0; i < h - 1; i++)
        bp[i] = (bp[i] >> 1) | (bp[i + 1] << 63);
    bp[h - 1] = (bp[h - 1] >> 1) | (lowbit << 63); /* q in bp */

    /* x = q + (q-xp)B^h modulo B^(2h)-1. */
    int negative = xp_top || bn_cmp_n(bp, ap, h) < 0;
    memcpy(out, bp, (size_t)h * sizeof(uint64_t));
    (void)bn_sub_n(out + h, bp, ap, h);
    if (negative) {
        int decrements = xp_top && w_limbs_zero(bp, h) ? 2 : 1;
        while (decrements--) {
            for (int32_t i = 0; i < n; i++) {
                uint64_t old = out[i];
                out[i] = old - 1;
                if (old) break;
            }
        }
    }
    w_bnm1_canonicalize(out, n);
}

#ifndef W_POWM_REDC_BNM1
#define W_POWM_REDC_BNM1 1
#endif

/* T: 2k limbs (top slots zero). scratch: >= 6k+4 limbs for the cyclic path,
 * or 4k+2 for the retained full-product A/B fallback. */
static void w_powm_redc_mullo(uint64_t *out, uint64_t *T, const uint64_t *n,
                              int32_t k, const uint64_t *mip,
                              uint64_t *scratch) {
    uint64_t *m = scratch;               /* k */
    uint64_t *work = scratch + k;
    w_mullo_n(m, T, mip, k, work);
    uint64_t cy;
#if W_POWM_REDC_BNM1
    if ((k & 1) == 0) {
        uint64_t *uhi = scratch + k;      /* k */
        uint64_t *cyclic_scratch = scratch + 2 * k;
        w_mulmod_bnm1(uhi, m, n, k, cyclic_scratch);
        int low_carry = !w_limbs_zero(T, k);
        /* m*n mod (B^k-1) = Ulo+Uhi.  Since Ulo=-Tlo mod B^k,
         * Uhi = residue+Tlo-(Tlo!=0) mod B^k-1.  Uhi<B^k-1, so the canonical
         * residue is the exact high half rather than merely a congruence. */
        w_bnm1_add(uhi, uhi, T, k);
        if (low_carry) w_bnm1_sub_one(uhi, k);
        cy = bn_add_n(out, T + k, uhi, k);
        uint64_t add = (uint64_t)low_carry;
        for (int32_t j = 0; add && j < k; j++) {
            uint64_t old = out[j];
            out[j] = old + add;
            add = out[j] < old;
        }
        cy += add;
    } else {
#endif
        uint64_t *U = scratch + k;        /* 2k */
        uint64_t *sc = scratch + 3 * k;   /* mullo scratch */
        bigint_mul_dispatch(U, m, k, n, k);
        uint64_t c = 0;
        for (int32_t j = 0; j < k; j++) if (T[j]) { c = 1; break; }
        cy = bn_add_n(out, T + k, U + k, k);
        for (int32_t j = 0; c && j < k; j++) {
            out[j]++;
            c = out[j] == 0;
        }
        cy += c;
#if W_POWM_REDC_BNM1
    }
#endif
    int ge = cy != 0;
    if (!ge) {
        ge = 1;
        for (int32_t j = k - 1; j >= 0; j--)
            if (out[j] != n[j]) { ge = out[j] > n[j]; break; }
    }
    if (ge) bn_sub_n(out, out, n, k);
}

/* Fully-inlined fixed-k modular squaring (k = 4, 8): the inline squaring
 * kernel feeds a completely unrolled REDC on a stack-resident T — no calls,
 * no dispatch, no row-function overhead. ~35% faster than the generic
 * SOS route at k = 4. Preconditions: a < n (ladder invariant), odd n. */
#define W_POWM_DEF_SQRREDC(K, SQRFN)                                         \
static __attribute__((unused)) void w_powm_sqrredc##K(uint64_t *out, const uint64_t *a, \
                              const uint64_t *n, uint64_t np0) {             \
    uint64_t T[2 * K + 1];                                                   \
    SQRFN(T, a);                                                             \
    T[2 * K] = 0;                                                            \
    uint64_t hi = 0;                     /* carry column above T[i+K] */     \
    for (int32_t i = 0; i < K; i++) {                                        \
        uint64_t m = T[i] * np0;                                             \
        __uint128_t c = 0;                                                   \
        for (int32_t j = 0; j < K; j++) {                                    \
            __uint128_t s = (__uint128_t)m * n[j] + T[i + j] + (uint64_t)c;  \
            T[i + j] = (uint64_t)s;                                          \
            c = s >> 64;                                                     \
        }                                                                    \
        __uint128_t s2 = (__uint128_t)T[i + K] + (uint64_t)c + hi;           \
        T[i + K] = (uint64_t)s2;                                             \
        hi = (uint64_t)(s2 >> 64);                                           \
    }                                                                        \
    T[2 * K] += hi;                                                          \
    int ge = T[2 * K] != 0;                                                  \
    if (!ge) {                                                               \
        ge = 1;                                                              \
        for (int32_t j = K - 1; j >= 0; j--)                                 \
            if (T[K + j] != n[j]) { ge = T[K + j] > n[j]; break; }           \
    }                                                                        \
    if (ge) {                                                                \
        uint64_t bw = 0;                                                     \
        for (int32_t j = 0; j < K; j++) {                                    \
            uint64_t tv = T[K + j] - n[j];                                   \
            uint64_t b1 = T[K + j] < n[j];                                   \
            uint64_t d = tv - bw;                                            \
            uint64_t b2 = tv < bw;                                           \
            out[j] = d;                                                      \
            bw = b1 | b2;                                                    \
        }                                                                    \
    } else {                                                                 \
        for (int32_t j = 0; j < K; j++) out[j] = T[K + j];                   \
    }                                                                        \
}
W_POWM_DEF_SQRREDC(4, bn_sqr4_inline)
W_POWM_DEF_SQRREDC(6, bn_sqr6_inline)
W_POWM_DEF_SQRREDC(8, bn_sqr8_inline)
W_POWM_DEF_SQRREDC(16, bn_sqr16_split)

/* Same shape for the window multiplies (both operands k-limb padded, < n). */
#define W_POWM_DEF_MULREDC(K, MULFN)                                         \
static __attribute__((unused)) void w_powm_mulredc##K(uint64_t *out, const uint64_t *a, \
                              const uint64_t *b, const uint64_t *n,          \
                              uint64_t np0) {                                \
    uint64_t T[2 * K + 1];                                                   \
    MULFN(T, a, b);                                                          \
    T[2 * K] = 0;                                                            \
    uint64_t hi = 0;                                                         \
    for (int32_t i = 0; i < K; i++) {                                        \
        uint64_t m = T[i] * np0;                                             \
        __uint128_t c = 0;                                                   \
        for (int32_t j = 0; j < K; j++) {                                    \
            __uint128_t s = (__uint128_t)m * n[j] + T[i + j] + (uint64_t)c;  \
            T[i + j] = (uint64_t)s;                                          \
            c = s >> 64;                                                     \
        }                                                                    \
        __uint128_t s2 = (__uint128_t)T[i + K] + (uint64_t)c + hi;           \
        T[i + K] = (uint64_t)s2;                                             \
        hi = (uint64_t)(s2 >> 64);                                           \
    }                                                                        \
    T[2 * K] += hi;                                                          \
    int ge = T[2 * K] != 0;                                                  \
    if (!ge) {                                                               \
        ge = 1;                                                              \
        for (int32_t j = K - 1; j >= 0; j--)                                 \
            if (T[K + j] != n[j]) { ge = T[K + j] > n[j]; break; }           \
    }                                                                        \
    if (ge) {                                                                \
        uint64_t bw = 0;                                                     \
        for (int32_t j = 0; j < K; j++) {                                    \
            uint64_t tv = T[K + j] - n[j];                                   \
            uint64_t b1 = T[K + j] < n[j];                                   \
            uint64_t d = tv - bw;                                            \
            uint64_t b2 = tv < bw;                                           \
            out[j] = d;                                                      \
            bw = b1 | b2;                                                    \
        }                                                                    \
    } else {                                                                 \
        for (int32_t j = 0; j < K; j++) out[j] = T[K + j];                   \
    }                                                                        \
}
W_POWM_DEF_MULREDC(4, bn_mul_eq4_inline)
W_POWM_DEF_MULREDC(6, bn_mul_eq6_inline)
W_POWM_DEF_MULREDC(8, bn_mul_eq8_inline)

#ifndef W_POWM_DIRECT_SQR8_16
#define W_POWM_DIRECT_SQR8_16 1
#endif

/* powmod's Montgomery ops on raw k-limb rows (high-zero padded, no trims kept):
 * product through the sqr/mul dispatchers, reduction through the dual-row
 * REDC when available, else the shared single-row REDC. Only the top two
 * product slots need pre-clearing — the dispatchers write 2·len limbs. */
static inline void w_powm_mont_sqr(uint64_t *out, const uint64_t *a, int32_t k,
                                   const uint64_t *n, uint64_t np0, uint64_t np1,
                                   const uint64_t *mip, uint64_t *T) {
    if (k == 4) { w_powm_sqrredc4(out, a, n, np0); return; }
    if (k == 6) { w_powm_sqrredc6(out, a, n, np0); return; }
#if !W_POWM_REDC2
    /* Without the pairs REDC the fused C kernels still win at 8/16. With it
     * (aarch64), sqr_dispatch + pairs REDC beats them by 12% / 32%. */
    if (k == 8) { w_powm_sqrredc8(out, a, n, np0); return; }
    if (k == 16) { w_powm_sqrredc16(out, a, n, np0); return; }
#elif W_POWM_DIRECT_SQR8_16
    /* The aarch64 pairs reducer wins over the fused C reducer, but routing
     * its fixed 8/16-limb square through the general size dispatcher is pure
     * overhead in the exponentiation ladder. */
    if (k == 8 || k == 16) {
        if (k == 8) bn_sqr8_inline(T, a);
        else        bn_sqr16_split(T, a);
        T[2 * k] = 0;
        T[2 * k + 1] = 0;
        w_powm_redc2(out, T, n, k, np0, np1);
        return;
    }
#endif
    bigint_sqr_dispatch(T, a, k);       /* zero-padded rows: exact-k dispatch */
    T[2 * k] = 0;
    T[2 * k + 1] = 0;
    if (mip) { w_powm_redc_mullo(out, T, n, k, mip, T + 2 * k + 2); return; }
#if W_POWM_REDC2
    w_powm_redc2(out, T, n, k, np0, np1);
#else
    (void)np1;
    w_mont_sos_redc(out, T, n, k, np0);
#endif
}
static inline void w_powm_mont_mul(uint64_t *out, const uint64_t *a,
                                   const uint64_t *b, int32_t blen, int32_t k,
                                   const uint64_t *n, uint64_t np0, uint64_t np1,
                                   const uint64_t *mip, uint64_t *T) {
    if (blen == k) {
        if (k == 4) { w_powm_mulredc4(out, a, b, n, np0); return; }
        if (k == 6) { w_powm_mulredc6(out, a, b, n, np0); return; }
        if (k == 8) { w_powm_mulredc8(out, a, b, n, np0); return; }
    }
    int32_t bt = blen;
    while (bt > 0 && b[bt - 1] == 0) bt--;
    if (!bt) { for (int32_t j = 0; j < k; j++) out[j] = 0; return; }
    bigint_mul_dispatch(T, a, k, b, bt);
    for (int32_t j = k + bt; j <= 2 * k + 1; j++) T[j] = 0;
    if (mip) { w_powm_redc_mullo(out, T, n, k, mip, T + 2 * k + 2); return; }
#if W_POWM_REDC2
    w_powm_redc2(out, T, n, k, np0, np1);
#else
    (void)np1;
    w_mont_sos_redc(out, T, n, k, np0);
#endif
}
/* Domain exit is REDC of the bare value (MontMul(x, 1)) — no multiply. */
static void w_powm_mont_exit(uint64_t *out, const uint64_t *x, int32_t k,
                             const uint64_t *n, uint64_t np0, uint64_t np1,
                             const uint64_t *mip, uint64_t *T) {
    for (int32_t j = 0; j < k; j++) T[j] = x[j];
    for (int32_t j = k; j <= 2 * k + 1; j++) T[j] = 0;
    if (mip) { w_powm_redc_mullo(out, T, n, k, mip, T + 2 * k + 2); return; }
#if W_POWM_REDC2
    w_powm_redc2(out, T, n, k, np0, np1);
#else
    (void)np1;
    w_mont_sos_redc(out, T, n, k, np0);
#endif
}

static WValue w_bigint_pow_base_limbs(int32_t limb_index) {
    WBigint *r = bigint_alloc(limb_index + 1);
    r->limbs[limb_index] = 1ULL;
    r->size = limb_index + 1;
    return bigint_box(r);
}

static WValue w_mag_shr_limbs_value(WValue t, int32_t drop_limbs) {
    if (drop_limbs <= 0) return t;
    uint64_t st; int32_t tl;
    const uint64_t *limbs = integer_limbs(t, &st, &tl);
    if (tl <= 0 || drop_limbs >= tl) return w_box_int(0);
    int32_t rlen = tl - drop_limbs;
    WBigint *r = bigint_alloc(rlen);
    for (int32_t i = 0; i < rlen; i++) r->limbs[i] = limbs[drop_limbs + i];
    r->size = rlen;
    return bigint_normalize(r);
}

static WValue w_mag_low_limbs_value(WValue t, int32_t keep_limbs) {
    if (keep_limbs <= 0) return w_box_int(0);
    uint64_t st; int32_t tl;
    const uint64_t *limbs = integer_limbs(t, &st, &tl);
    if (tl <= keep_limbs) return t;
    WBigint *r = bigint_alloc(keep_limbs);
    for (int32_t i = 0; i < keep_limbs; i++) r->limbs[i] = limbs[i];
    r->size = keep_limbs;
    return bigint_normalize(r);
}

static int32_t w_prime_sub_mag_inplace(uint64_t *a, int32_t alen, const uint64_t *b, int32_t blen);

/* mont_cap: largest limb count admitted to Montgomery mode (0 forces Barrett —
 * required for EVEN moduli, whose limb 0 has no inverse mod 2^64). The prime
 * paths always pass W_MONT_MAX_LIMBS with an odd modulus; bigint_powmod_any
 * passes 0 for even moduli and its own cap for odd ones. */
/* powm_only: the caller is bigint_powmod_any's Montgomery ladder, which
 * enters the domain by one division (x·B^k mod n, see w_powm_mont_enter) and
 * never touches R², one_m, (n−1)_m or Barrett's μ.  Skipping them removes a
 * 2k-by-k division and two Montgomery multiplies of pure setup — for RSA-style
 * public exponents (3, 65537) that setup was most of the call.  The idea comes
 * from the EIP-8200 MODEXP work: convert into Montgomery form by shifting the
 * operand limb by limb and reducing, instead of multiplying by a precomputed
 * R² mod n. */
static void w_prime_modctx_init_cap_mode(WPrimeModCtx *ctx, WValue modulus,
                                         int32_t mont_cap, int powm_only) {
    uint64_t sm;
    int32_t mlen;
    const uint64_t *mlimbs = integer_limbs(modulus, &sm, &mlen);
    if (mlen <= 0) die("invalid modulus");
    ctx->modulus = modulus;
    ctx->limbs = mlen;
    ctx->sloti = 0;

    /* Domain policy first: k=1 and 3..mont_cap use Montgomery; k=2 keeps the
     * register-Barrett fast path and large k keeps Barrett (subquadratic
     * muls).  A powm-only Montgomery context skips every constant below. */
    int mont = mont_cap > 0 &&
               (mlen == 1 || (mlen >= 3 && mlen <= mont_cap)) &&
               (powm_only || mlen <= W_MONT_CIOS_CAPACITY);
    int skip_constants = powm_only && mont;
    ctx->bkp1 = skip_constants ? W_NIL : w_bigint_pow_base_limbs(mlen + 1);

    WBigint *mu = NULL;
    WBigint *r2rem = NULL;      /* b^2k mod n = R² mod n — Montgomery's constant */
    if (!skip_constants) {
        WBigint *b2k = bigint_alloc(2 * mlen + 1);
        b2k->limbs[2 * mlen] = 1ULL;
        b2k->size = 2 * mlen + 1;
        mag_divmod(b2k->limbs, b2k->size, mlimbs, mlen, &mu, &r2rem);
        bigint_backing_free(b2k);
    }
    ctx->mu = mu ? bigint_normalize(mu) : W_NIL;

    /* work-buffer layout (see w_prime_modctx_reduce_limbs), sized to the ACTUAL
     * Barrett scratch, not three temporaries: a 4k product region + six regions
     * q1,q2,q3,r1,r2,tmp. q2=q1·μ and tmp=q3·n each hold ~2k limbs (and NTT may
     * write 2·max+2), so strides are k+2 / 2k+4:
     *   4k + (k+2) + (2k+4) + (k+2) + (k+2) + (k+2) + (2k+4) = 12k+16.
     * The previous 7k+7 undersized this — tmp ran off the end (heap corruption,
     * surfacing as a Barrett mulmod mismatch). */
    ctx->work_cap = 12 * mlen + 16;
    ctx->work = (uint64_t *)calloc((size_t)ctx->work_cap, sizeof(uint64_t));
    for (int i = 0; i < 3; i++) {
        ctx->slot[i] = skip_constants ? NULL : bigint_alloc(mlen + 2);
        ctx->slotv[i] = ctx->slot[i] ? bigint_box(ctx->slot[i]) : W_NIL;
    }

    ctx->mont = mont;
    ctx->nprime = 0;
    ctx->r2b = NULL;
    ctx->r2v = 0;
    ctx->onemb = skip_constants ? NULL : bigint_alloc(mlen + 2);
    ctx->nm1mb = skip_constants ? NULL : bigint_alloc(mlen + 2);
    ctx->onemv = ctx->onemb ? bigint_box(ctx->onemb) : W_NIL;
    ctx->nm1mv = ctx->nm1mb ? bigint_box(ctx->nm1mb) : W_NIL;
    if (skip_constants) {
        ctx->nprime = 0ULL - w_mont_ninv(mlimbs[0]);
    } else if (ctx->mont) {
        ctx->nprime = 0ULL - w_mont_ninv(mlimbs[0]);
        ctx->r2b = r2rem;
        ctx->r2v = bigint_box(r2rem);
        int32_t rl = r2rem->size < 0 ? -r2rem->size : r2rem->size;
        uint64_t onelimb = 1;
        /* one_m = R mod n = MontMul(R², 1) */
        w_mont_cios_mul(ctx->onemb->limbs, r2rem->limbs, rl, &onelimb, 1,
                        mlimbs, mlen, ctx->nprime);
        int32_t ol = mlen;
        while (ol > 0 && ctx->onemb->limbs[ol - 1] == 0) ol--;
        ctx->onemb->size = ol;
        /* nm1_m = (n−1)·R ≡ −R ⇒ n − one_m */
        for (int32_t i = 0; i < mlen; i++) ctx->nm1mb->limbs[i] = mlimbs[i];
        ctx->nm1mb->size = w_prime_sub_mag_inplace(ctx->nm1mb->limbs, mlen,
                                                   ctx->onemb->limbs, ol);
    } else {
        bigint_backing_free(r2rem);
        uint64_t onelimb = 1;
        ctx->onemb->limbs[0] = 1;
        ctx->onemb->size = 1;
        for (int32_t i = 0; i < mlen; i++) ctx->nm1mb->limbs[i] = mlimbs[i];
        ctx->nm1mb->size = w_prime_sub_mag_inplace(ctx->nm1mb->limbs, mlen, &onelimb, 1);
    }
}

static void w_prime_modctx_init_cap(WPrimeModCtx *ctx, WValue modulus, int32_t mont_cap) {
    w_prime_modctx_init_cap_mode(ctx, modulus, mont_cap, 0);
}

static void w_prime_modctx_init(WPrimeModCtx *ctx, WValue modulus) {
    w_prime_modctx_init_cap_mode(ctx, modulus, W_MONT_MAX_LIMBS, 0);
}

/* Montgomery domain entry by division: out = x·B^k mod n for a reduced k-limb
 * x (high-zero padded).  One 2k-by-k division replaces MontMul(x, R²) and the
 * R² = B^2k mod n division behind it. */
static void w_powm_mont_enter(uint64_t *out, const uint64_t *x, int32_t k,
                              const uint64_t *n) {
    int32_t xl = k;
    while (xl > 0 && x[xl - 1] == 0) xl--;
    if (xl == 0) {
        for (int32_t j = 0; j < k; j++) out[j] = 0;
        return;
    }
    uint64_t u_stack[64];
    uint64_t *u = (k + xl <= 64)
        ? u_stack
        : (uint64_t *)calloc((size_t)(k + xl), sizeof(uint64_t));
    if (u == u_stack)
        memset(u_stack, 0, (size_t)k * sizeof(uint64_t));
    for (int32_t j = 0; j < xl; j++) u[k + j] = x[j];
    WBigint *rem = NULL;
    mag_divmod(u, k + xl, n, k, NULL, &rem);
    if (u != u_stack) free(u);
    int32_t rl = rem->size < 0 ? -rem->size : rem->size;
    for (int32_t j = 0; j < rl; j++) out[j] = rem->limbs[j];
    for (int32_t j = rl; j < k; j++) out[j] = 0;
    bigint_backing_free(rem);
}

static inline int w_powm_bit(const uint64_t *l, int32_t len, int i);
static inline int w_powm_bits(const uint64_t *l, int32_t len, int lo, int cnt);

/* Highest odd-power table row the sliding window over e will read: replays
 * the ladder's window selection without arithmetic, so a fixed exponent such
 * as 65537 = 2^16 + 1 (windows "1" and "1") builds no b², b³ at all. */
static int32_t w_powm_table_rows_used(const uint64_t *el, int32_t elen, int eb,
                                      int wbits) {
    int32_t maxidx = 0;
    int i = eb - 1;
    while (i >= 0) {
        if (!w_powm_bit(el, elen, i)) { i--; continue; }
        int l = i - wbits + 1;
        if (l < 0) l = 0;
        while (!w_powm_bit(el, elen, l)) l++;
        int32_t idx = (int32_t)(w_powm_bits(el, elen, l, i - l + 1) >> 1);
        if (idx > maxidx) maxidx = idx;
        i = l - 1;
    }
    return maxidx + 1;
}

static void w_prime_modctx_fini(WPrimeModCtx *ctx) {
    free(ctx->work);
    ctx->work = NULL;
    for (int i = 0; i < 3; i++) {
        if (ctx->slot[i]) {
            bigint_backing_free(ctx->slot[i]);
            ctx->slot[i] = NULL;
        }
    }
    if (ctx->r2b)  { bigint_backing_free(ctx->r2b);  ctx->r2b  = NULL; }
    if (ctx->onemb) { bigint_backing_free(ctx->onemb); ctx->onemb = NULL; }
    if (ctx->nm1mb) { bigint_backing_free(ctx->nm1mb); ctx->nm1mb = NULL; }
    /* Both values are minted by w_prime_modctx_init (the quotient from
     * b^(2k)/n and b^(k+1), respectively).  They are not borrowed from the
     * caller and were the two context-owned allocations missing above. */
    if (w_is_bigint(ctx->mu)) bigint_backing_free(w_as_bigint(ctx->mu));
    if (w_is_bigint(ctx->bkp1)) bigint_backing_free(w_as_bigint(ctx->bkp1));
    ctx->mu = W_NIL;
    ctx->bkp1 = W_NIL;
}

/* Copy the low `keep` limbs of magnitude u[0..ulen) into out[0..keep). */
static int32_t w_prime_copy_low_limbs(uint64_t *out, int32_t keep,
                                      const uint64_t *u, int32_t ulen) {
    int32_t uabs = ulen < 0 ? -ulen : ulen;
    if (keep <= 0) return 0;
    if (uabs < keep) keep = uabs;
    for (int32_t i = 0; i < keep; i++) out[i] = u[i];
    return keep;
}

/* Right-shift a magnitude by `drop` limbs into out (reuses ctx->work tail). */
static int32_t w_prime_shr_limbs(uint64_t *out, const uint64_t *u, int32_t ulen, int32_t drop) {
    int32_t uabs = ulen < 0 ? -ulen : ulen;
    if (drop <= 0) return w_prime_copy_low_limbs(out, uabs, u, ulen);
    if (drop >= uabs) return 0;
    int32_t rlen = uabs - drop;
    for (int32_t i = 0; i < rlen; i++) out[i] = u[drop + i];
    return rlen;
}

/* Compare magnitudes a[0..alen) vs b[0..blen); returns -1/0/1. */
static int w_prime_cmp_mag(const uint64_t *a, int32_t alen, const uint64_t *b, int32_t blen) {
    while (alen > 0 && a[alen - 1] == 0) alen--;
    while (blen > 0 && b[blen - 1] == 0) blen--;
    if (alen != blen) return alen < blen ? -1 : 1;
    for (int32_t i = alen - 1; i >= 0; i--) {
        if (a[i] != b[i]) return a[i] < b[i] ? -1 : 1;
    }
    return 0;
}

/* Subtract magnitude b from a (a ≥ b), in place in a; returns alen. Borrow is
 * propagated in two steps (av-bv, then -borrow) so it survives a 0xFFFF…FFFF
 * limb: the naive `sub = b[i] + borrow` overflows to 0 when b[i]==UINT64_MAX and
 * borrow==1, silently dropping the borrow (wrong result for moduli near a power
 * of two, e.g. 2^64+13 where q3·n has an all-ones limb). */
static int32_t w_prime_sub_mag_inplace(uint64_t *a, int32_t alen, const uint64_t *b, int32_t blen) {
    uint64_t borrow = 0;
    for (int32_t i = 0; i < blen; i++) {
        uint64_t av = (i < alen) ? a[i] : 0;
        uint64_t bv = b[i];
        uint64_t t = av - bv;
        uint64_t bout1 = (av < bv);
        uint64_t d = t - borrow;
        uint64_t bout2 = (t < borrow);
        a[i] = d;
        borrow = bout1 | bout2;
    }
    for (int32_t i = blen; borrow && i < alen; i++) {
        uint64_t av = a[i];
        a[i] = av - borrow;
        borrow = av < borrow;
    }
    while (alen > 0 && a[alen - 1] == 0) alen--;
    return alen;
}

/* Add magnitude b into a (separate dest), returns dest length. */
static int32_t w_prime_add_mag(uint64_t *out, const uint64_t *a, int32_t alen,
                               const uint64_t *b, int32_t blen) {
    int32_t m = alen > blen ? alen : blen;
    uint64_t carry = 0;
    for (int32_t i = 0; i < m; i++) {
        __uint128_t s = (__uint128_t)(i < alen ? a[i] : 0) + (i < blen ? b[i] : 0) + carry;
        out[i] = (uint64_t)s;
        carry = (uint64_t)(s >> 64);
    }
    if (carry) { out[m] = carry; m++; }
    while (m > 0 && out[m - 1] == 0) m--;
    return m;
}

/* Limb-native modular helpers for the Lucas ladder (all operands < n, results
 * < n; dest capacity ≥ nlen+1). dest may alias a (index-ascending ops). */
static int32_t w_prime_mod_add_limbs(uint64_t *dest, const uint64_t *a, int32_t al,
                                     const uint64_t *b, int32_t bl,
                                     const uint64_t *n, int32_t nl) {
    int32_t dl = w_prime_add_mag(dest, a, al, b, bl);
    if (w_prime_cmp_mag(dest, dl, n, nl) >= 0)
        dl = w_prime_sub_mag_inplace(dest, dl, n, nl);
    return dl;
}
static int32_t w_prime_mod_sub_limbs(uint64_t *dest, const uint64_t *a, int32_t al,
                                     const uint64_t *b, int32_t bl,
                                     const uint64_t *n, int32_t nl) {
    int32_t dl;
    if (w_prime_cmp_mag(a, al, b, bl) >= 0) {
        for (int32_t i = 0; i < al; i++) dest[i] = a[i];
        dl = w_prime_sub_mag_inplace(dest, al, b, bl);
    } else {
        dl = w_prime_add_mag(dest, a, al, n, nl);   /* a + n ≥ b since b < n */
        dl = w_prime_sub_mag_inplace(dest, dl, b, bl);
    }
    return dl;
}
/* dest = a/2 mod n for odd n: if a is odd, a+n is even; then shift right 1. */
static int32_t w_prime_mod_half_limbs(uint64_t *dest, const uint64_t *a, int32_t al,
                                      const uint64_t *n, int32_t nl) {
    int32_t dl;
    if (al > 0 && (a[0] & 1ULL)) {
        dl = w_prime_add_mag(dest, a, al, n, nl);
    } else {
        for (int32_t i = 0; i < al; i++) dest[i] = a[i];
        dl = al;
    }
    for (int32_t i = 0; i < dl - 1; i++) dest[i] = (dest[i] >> 1) | (dest[i + 1] << 63);
    if (dl > 0) { dest[dl - 1] >>= 1; if (dest[dl - 1] == 0) dl--; }
    return dl;
}

/* Barrett reduction: x[0..xlen) mod n into dest[0..k). Returns result length. */
static int32_t w_prime_modctx_reduce_into(uint64_t *dest, WPrimeModCtx *ctx,
                                          const uint64_t *x, int32_t xlen) {
    int32_t k = ctx->limbs;
    uint64_t sm; int32_t nlen;
    const uint64_t *nlimbs = integer_limbs(ctx->modulus, &sm, &nlen);
    int32_t nabs = nlen < 0 ? -nlen : nlen;
    /* Region strides fit each write incl. NTT's 2·max+2: q2=q1·μ and tmp=q3·n
     * need 2k+4; the rest ≤ k+2. Total 12k+16 = ctx->work_cap (see init). */
    uint64_t *w = ctx->work;
    uint64_t *q1 = w + 4 * k;
    uint64_t *q2 = q1 + (k + 2);
    uint64_t *q3 = q2 + (2 * k + 4);
    uint64_t *r1 = q3 + (k + 2);
    uint64_t *r2 = r1 + (k + 2);
    uint64_t *tmp = r2 + (k + 2);

    int32_t q1l = w_prime_shr_limbs(q1, x, xlen, k - 1);
    int32_t q2l = 0, q3l = 0;
    if (q1l > 0) {
        uint64_t st; int32_t mulen;
        const uint64_t *mlimbs = integer_limbs(ctx->mu, &st, &mulen);
        int32_t mabs = mulen < 0 ? -mulen : mulen;
        bigint_mul_dispatch(q2, q1, q1l, mlimbs, mabs);
        q2l = q1l + mabs;
        while (q2l > 0 && q2[q2l - 1] == 0) q2l--;
        q3l = w_prime_shr_limbs(q3, q2, q2l, k + 1);
    }
    int32_t r1l = w_prime_copy_low_limbs(r1, k + 1, x, xlen);
    int32_t r2l = 0;
    if (q3l > 0) {
        bigint_mul_dispatch(tmp, q3, q3l, nlimbs, nabs);
        int32_t tmpl = q3l + nabs;
        while (tmpl > 0 && tmp[tmpl - 1] == 0) tmpl--;
        r2l = w_prime_copy_low_limbs(r2, k + 1, tmp, tmpl);
    }
    int32_t rl;
    if (w_prime_cmp_mag(r1, r1l, r2, r2l) < 0) {
        uint64_t st; int32_t bl;
        const uint64_t *blimbs = integer_limbs(ctx->bkp1, &st, &bl);
        int32_t blabs = bl < 0 ? -bl : bl;
        int32_t suml = w_prime_add_mag(tmp, r1, r1l, blimbs, blabs);
        rl = w_prime_sub_mag_inplace(tmp, suml, r2, r2l);
        memcpy(r1, tmp, (size_t)rl * sizeof(uint64_t));
    } else {
        rl = w_prime_sub_mag_inplace(r1, r1l, r2, r2l);
    }
    while (w_prime_cmp_mag(r1, rl, nlimbs, nabs) >= 0)
        rl = w_prime_sub_mag_inplace(r1, rl, nlimbs, nabs);

    for (int32_t i = 0; i < rl; i++) dest[i] = r1[i];
    return rl;
}

/* Barrett reduction into a rotating ctx slot (legacy WValue path). */
static WValue w_prime_modctx_reduce_limbs(WPrimeModCtx *ctx, const uint64_t *x, int32_t xlen) {
    WBigint *out = ctx->slot[ctx->sloti % 3];
    ctx->sloti++;
    out->size = w_prime_modctx_reduce_into(out->limbs, ctx, x, xlen);
    return ctx->slotv[(ctx->sloti - 1) % 3];
}

static WValue w_prime_modctx_reduce(WPrimeModCtx *ctx, WValue x) {
    if (w_lt(x, ctx->modulus) == W_TRUE) return x;
    uint64_t st; int32_t xl;
    const uint64_t *xlimbs = integer_limbs(x, &st, &xl);
    return w_prime_modctx_reduce_limbs(ctx, xlimbs, xl);
}

/* k == 2 Barrett mulmod into dest[0..2). Returns result length. */
static int32_t w_prime_modctx_mul2_into(uint64_t *out, WPrimeModCtx *ctx,
                                        const uint64_t *al, int32_t la,
                                        const uint64_t *bl, int32_t lb) {
    uint64_t sm, su;
    int32_t lm, lu;
    const uint64_t *nl = integer_limbs(ctx->modulus, &sm, &lm);
    const uint64_t *ml = integer_limbs(ctx->mu, &su, &lu);
    int32_t aa = la < 0 ? -la : la, ba = lb < 0 ? -lb : lb;
    int32_t ua = lu < 0 ? -lu : lu;
    uint64_t a0 = aa > 0 ? al[0] : 0, a1 = aa > 1 ? al[1] : 0;
    uint64_t b0 = ba > 0 ? bl[0] : 0, b1 = ba > 1 ? bl[1] : 0;
    uint64_t n0 = nl[0], n1 = nl[1];

    /* p = a·b (4 limbs), u128 column accumulation (each column sum < 2^66). */
    __uint128_t x00 = (__uint128_t)a0 * b0, x01 = (__uint128_t)a0 * b1;
    __uint128_t x10 = (__uint128_t)a1 * b0, x11 = (__uint128_t)a1 * b1;
    uint64_t p[4];
    p[0] = (uint64_t)x00;
    __uint128_t col = (x00 >> 64) + (uint64_t)x01 + (uint64_t)x10;
    p[1] = (uint64_t)col;
    col = (col >> 64) + (x01 >> 64) + (x10 >> 64) + (uint64_t)x11;
    p[2] = (uint64_t)col;
    p[3] = (uint64_t)((col >> 64) + (x11 >> 64));

    /* q1 = p >> 64 (3 limbs); q2 = q1·μ (row-wise schoolbook, 6 limbs);
     * q3 = q2 >> 192 (3 limbs). */
    uint64_t q1[3] = { p[1], p[2], p[3] };
    uint64_t muv[3] = { ua > 0 ? ml[0] : 0, ua > 1 ? ml[1] : 0, ua > 2 ? ml[2] : 0 };
    uint64_t q2[6] = {0};
    for (int i = 0; i < 3; i++) {
        uint64_t carry = 0;
        for (int j = 0; j < 3; j++) {
            __uint128_t t = (__uint128_t)q1[i] * muv[j] + q2[i + j] + carry;
            q2[i + j] = (uint64_t)t;
            carry = (uint64_t)(t >> 64);
        }
        q2[i + 3] += carry;                       /* row's top slot was 0 or prior carry */
    }
    uint64_t q3[3] = { q2[3], q2[4], q2[5] };

    /* r = (p − q3·n) mod 2^192: 3-limb wraparound subtraction IS the +b^(k+1)
     * correction, so no branch. */
    uint64_t r2l[3] = {0};
    for (int i = 0; i < 3; i++) {
        uint64_t carry = 0;
        for (int j = 0; j < 2 && i + j < 3; j++) {
            __uint128_t t = (__uint128_t)q3[i] * (j == 0 ? n0 : n1) + r2l[i + j] + carry;
            r2l[i + j] = (uint64_t)t;
            carry = (uint64_t)(t >> 64);
        }
        if (i + 2 < 3) r2l[i + 2] += carry;
    }
    uint64_t r0, r1, r2, bw;
    r0 = p[0] - r2l[0];              bw = p[0] < r2l[0];
    { uint64_t t = p[1] - r2l[1];    uint64_t b2 = p[1] < r2l[1];
      r1 = t - bw;                   bw = b2 | (t < bw); }
    { uint64_t t = p[2] - r2l[2];    uint64_t b2 = p[2] < r2l[2];
      r2 = t - bw;                   bw = b2 | (t < bw); }   /* wrap = Barrett correction */

    /* r < 3n ⇒ at most two subtractions of n. */
    for (;;) {
        int ge = (r2 > 0) || (r1 > n1) || (r1 == n1 && r0 >= n0);
        if (!ge) break;
        uint64_t t = r0 - n0; uint64_t bb = r0 < n0;
        r0 = t;
        uint64_t t1 = r1 - n1; uint64_t b2 = r1 < n1;
        r1 = t1 - bb; bw = b2 | (t1 < bb);
        r2 -= bw;
    }

    out[0] = r0; out[1] = r1;
    return r1 ? 2 : (r0 ? 1 : 0);
}

/* k == 2 fast path (WValue wrapper around mul2_into). */
static WValue w_prime_modctx_mul2(WPrimeModCtx *ctx, WValue a, WValue b) {
    uint64_t sa, sb;
    int32_t la, lb;
    const uint64_t *al = integer_limbs(a, &sa, &la);
    const uint64_t *bl = integer_limbs(b, &sb, &lb);
    WBigint *slot = ctx->slot[ctx->sloti % 3];
    ctx->sloti++;
    slot->size = w_prime_modctx_mul2_into(slot->limbs, ctx, al, la, bl, lb);
    return ctx->slotv[(ctx->sloti - 1) % 3];
}

/* Stable-buffer mulmod: writes into dest (capacity ≥ ctx->limbs+2). */
static int32_t w_prime_modctx_mul_bigint_into(WBigint *dest, WPrimeModCtx *ctx,
                                              WBigint *a, WBigint *b) {
    int32_t aabs = a->size < 0 ? -a->size : a->size;
    int32_t babs = b->size < 0 ? -b->size : b->size;
    if (ctx->limbs == 2)
        return w_prime_modctx_mul2_into(dest->limbs, ctx, a->limbs, aabs, b->limbs, babs);
    if (ctx->mont) {
        uint64_t smod; int32_t lmod;
        const uint64_t *nlimbs = integer_limbs(ctx->modulus, &smod, &lmod);
        int32_t k = ctx->limbs;
        if (k >= W_MONT_SOS_MIN)
            w_mont_sos_mul(dest->limbs, a->limbs, aabs, b->limbs, babs,
                           nlimbs, k, ctx->nprime, ctx->work);
        else
            w_mont_cios_mul(dest->limbs, a->limbs, aabs, b->limbs, babs,
                            nlimbs, k, ctx->nprime);
        int32_t rl = k;
        while (rl > 0 && dest->limbs[rl - 1] == 0) rl--;
        return rl;
    }
    if (aabs == 0 || babs == 0) return 0;   /* zero divisors exist mod composite n */
    bigint_mul_dispatch(ctx->work, a->limbs, aabs, b->limbs, babs);
    int32_t plen = aabs + babs;
    while (plen > 0 && ctx->work[plen - 1] == 0) plen--;
    return w_prime_modctx_reduce_into(dest->limbs, ctx, ctx->work, plen);
}

/* Modular squaring into dest (capacity ≥ ctx->limbs+2): same contract as
 * w_prime_modctx_mul_bigint_into with b == a, but the product half rides the
 * squaring dispatcher where one exists (SOS Montgomery and Barrett modes; the
 * k==2 register path and small-k CIOS interleave multiply and reduction, so
 * they square via their multiply). dest may alias a. */
static int32_t w_prime_modctx_sqr_bigint_into(WBigint *dest, WPrimeModCtx *ctx, WBigint *a) {
    int32_t aabs = a->size < 0 ? -a->size : a->size;
    if (ctx->limbs == 2)
        return w_prime_modctx_mul2_into(dest->limbs, ctx, a->limbs, aabs, a->limbs, aabs);
    int32_t k = ctx->limbs;
    uint64_t smod; int32_t lmod;
    const uint64_t *nlimbs = integer_limbs(ctx->modulus, &smod, &lmod);
    if (ctx->mont) {
        if (k >= W_MONT_SOS_SQR_MIN)
            w_mont_sos_sqr(dest->limbs, a->limbs, aabs, nlimbs, k, ctx->nprime, ctx->work);
        else
            w_mont_cios_mul(dest->limbs, a->limbs, aabs, a->limbs, aabs,
                            nlimbs, k, ctx->nprime);
        int32_t rl = k;
        while (rl > 0 && dest->limbs[rl - 1] == 0) rl--;
        return rl;
    }
    int32_t at = aabs;
    while (at > 0 && a->limbs[at - 1] == 0) at--;
    if (at == 0) return 0;
    bigint_sqr_dispatch(ctx->work, a->limbs, at);
    int32_t plen = 2 * at;
    while (plen > 0 && ctx->work[plen - 1] == 0) plen--;
    return w_prime_modctx_reduce_into(dest->limbs, ctx, ctx->work, plen);
}

/* Convert plain < n into ctx domain directly into dest. */
static int32_t w_prime_modctx_plain_into(WBigint *dest, WPrimeModCtx *ctx, uint64_t plain) {
    if (!ctx->mont) {
        dest->limbs[0] = plain;
        return plain ? 1 : 0;
    }
    WBigint *r2 = ctx->r2b;
    int32_t r2l = r2->size < 0 ? -r2->size : r2->size;
    int32_t plen = plain ? 1 : 0;
    if (ctx->limbs == 2)
        return w_prime_modctx_mul2_into(dest->limbs, ctx, &plain, plen, r2->limbs, r2l);
    uint64_t smod; int32_t lmod;
    const uint64_t *nlimbs = integer_limbs(ctx->modulus, &smod, &lmod);
    int32_t k = ctx->limbs;
    if (k >= W_MONT_SOS_MIN)
        w_mont_sos_mul(dest->limbs, &plain, plen, r2->limbs, r2l,
                       nlimbs, k, ctx->nprime, ctx->work);
    else
        w_mont_cios_mul(dest->limbs, &plain, plen, r2->limbs, r2l,
                        nlimbs, k, ctx->nprime);
    int32_t rl = k;
    while (rl > 0 && dest->limbs[rl - 1] == 0) rl--;
    return rl;
}

static int w_prime_domain_eq(const WBigint *a, const WBigint *dom) {
    int32_t al = a->size < 0 ? -a->size : a->size;
    int32_t dl = dom->size < 0 ? -dom->size : dom->size;
    return w_prime_cmp_mag(a->limbs, al, dom->limbs, dl) == 0;
}

static WValue w_prime_modctx_mul(WPrimeModCtx *ctx, WValue a, WValue b) {
    if (ctx->limbs == 2) return w_prime_modctx_mul2(ctx, a, b);
    uint64_t sa, sb;
    int32_t la, lb;
    const uint64_t *alimbs = integer_limbs(a, &sa, &la);
    const uint64_t *blimbs = integer_limbs(b, &sb, &lb);
    int32_t aabs = la < 0 ? -la : la;
    int32_t babs = lb < 0 ? -lb : lb;
    if (ctx->mont) {                         /* Montgomery: SOS (large k) or CIOS */
        uint64_t smod; int32_t lmod;
        const uint64_t *nlimbs = integer_limbs(ctx->modulus, &smod, &lmod);
        int32_t k = ctx->limbs;
        WBigint *out = ctx->slot[ctx->sloti % 3];
        ctx->sloti++;
        if (k >= W_MONT_SOS_MIN)             /* ctx->work is free in mont mode */
            w_mont_sos_mul(out->limbs, alimbs, aabs, blimbs, babs, nlimbs, k, ctx->nprime, ctx->work);
        else
            w_mont_cios_mul(out->limbs, alimbs, aabs, blimbs, babs, nlimbs, k, ctx->nprime);
        int32_t rl = k;
        while (rl > 0 && out->limbs[rl - 1] == 0) rl--;
        out->size = rl;
        return ctx->slotv[(ctx->sloti - 1) % 3];
    }
    uint64_t *prod = ctx->work;
    bigint_mul_dispatch(prod, alimbs, aabs, blimbs, babs);
    int32_t plen = aabs + babs;
    while (plen > 0 && prod[plen - 1] == 0) plen--;
    return w_prime_modctx_reduce_limbs(ctx, prod, plen);
}

/* Convert a plain value (< n) into the ctx's domain: Montgomery form xR mod n
 * when the ctx is Montgomery (MontMul(x, R²) = xR), identity under Barrett.
 * Returns a rotating-slot value in mont mode — copy out before the next mul. */
static WValue w_prime_modctx_to_domain(WPrimeModCtx *ctx, WValue x) {
    if (!ctx->mont) return x;
    return w_prime_modctx_mul(ctx, x, ctx->r2v);
}

/* ---- BPSW strong Lucas component (Selfridge parameters) ----
 * The Sinclair 7-base MR set is PROVEN only for n < 2^64 (Feitsma-Galway);
 * for bigints an MR pass is only "strong probable prime". Pairing MR (which includes base 2) with a
 * strong Lucas test is Baillie-PSW: the two tests fail on near-disjoint
 * pseudoprime families, and no composite is known to pass both — at any size. */

/* Jacobi symbol (a/n) for small odd modulus n > 0 (both int64). */
static int w_jacobi_small(int64_t a, int64_t n) {
    a %= n; if (a < 0) a += n;
    int result = 1;
    while (a != 0) {
        while ((a & 1) == 0) {
            a >>= 1;
            int64_t m = n & 7;
            if (m == 3 || m == 5) result = -result;
        }
        int64_t t = a; a = n; n = t;            /* reciprocity swap */
        if ((a & 3) == 3 && (n & 3) == 3) result = -result;
        a %= n;
    }
    return n == 1 ? result : 0;
}

/* Jacobi symbol (D/n): small int64 D (may be negative), big positive odd n.
 * Only n mod 8 (low limb) and one big-by-small remainder (n mod a) touch the
 * bignum; after the first reciprocity flip both operands are small. */
static int w_jacobi_dn(int64_t D, WValue n) {
    int result = 1;
    int n8 = (int)(integer_low_i64(n) & 7);     /* n odd > 0 */
    int64_t a = D;
    if (a < 0) { a = -a; if ((n8 & 3) == 3) result = -result; }
    while ((a & 1) == 0) { a >>= 1; if (n8 == 3 || n8 == 5) result = -result; }
    if (a == 1) return result;
    if ((a & 3) == 3 && (n8 & 3) == 3) result = -result;
    int64_t r = integer_low_i64(w_mod(n, w_int(a)));   /* n mod a, small */
    return result * w_jacobi_small(r, a);
}

static int w_int_bit_length(WValue v) {
    uint64_t scratch; int32_t len;
    const uint64_t *limbs = integer_limbs(v, &scratch, &len);
    if (len < 0) len = -len;
    if (len == 0) return 0;
    return (len - 1) * 64 + (64 - __builtin_clzll(limbs[len - 1]));
}
static int w_int_test_bit(WValue v, int i) {
    uint64_t scratch; int32_t len;
    const uint64_t *limbs = integer_limbs(v, &scratch, &len);
    if (len < 0) len = -len;
    int limb = i >> 6, bit = i & 63;
    if (limb >= len) return 0;
    return (int)((limbs[limb] >> bit) & 1ULL);
}

static int w_prime_mag_bit_length(const uint64_t *limbs, int32_t len) {
    while (len > 0 && limbs[len - 1] == 0) len--;
    if (len == 0) return 0;
    return (len - 1) * 64 + (64 - __builtin_clzll(limbs[len - 1]));
}

/* Trailing zero bits of n−1 for odd n (n−1 = n with bit 0 cleared). */
static int w_prime_nm1_trailing_zeros(const uint64_t *nl, int32_t nlen) {
    if (nlen <= 0 || (nl[0] & 1ULL) == 0) return 0;
    uint64_t low0 = nl[0] & ~1ULL;
    if (low0 != 0) return __builtin_ctzll(low0);
    int32_t i = 1;
    while (i < nlen && nl[i] == 0) i++;
    if (i >= nlen) return 0;
    return i * 64 + __builtin_ctzll(nl[i]);
}

/* Bit i of n−1 for odd n; bit 0 is always 0. */
static int w_prime_nm1_test_bit(const uint64_t *nl, int32_t nlen, int bit) {
    if (bit <= 0) return 0;
    int limb = bit >> 6, sh = bit & 63;
    if (limb >= nlen) return 0;
    return (int)((nl[limb] >> sh) & 1ULL);
}

/* x/2 mod n for odd n, assuming 0 <= x < n: if x is odd, x+n is even. */
static WValue w_halve_mod(WValue x, WValue n) {
    if (integer_low_i64(x) & 1) x = w_add(x, n);
    return w_div(x, w_int(2));
}
/* (a - b) mod n in [0, n). w_mod follows the sign of the dividend, so a
 * negative difference needs one corrective add. */
static WValue w_sub_mod(WValue a, WValue b, WValue n) {
    WValue r = w_mod(w_sub(a, b), n);
    if (w_lt(r, w_int(0)) == W_TRUE) r = w_add(r, n);
    return r;
}

/* Strong Lucas probable-prime test — REFERENCE implementation on boxed WValues
 * (w_mul/w_mod allocate ~5-7 heap bigints per bit of d). Kept for the bigint
 * bench's A/B + agreement check; production uses w_prime_lucas_strong_ctx,
 * which routes through the Barrett modctx and limb-native add/sub/half. */
__attribute__((unused))
static int w_prime_lucas_strong(WValue n) {
    WValue zero = w_int(0), one = w_int(1), two = w_int(2);

    int64_t D = 5;
    for (int tries = 0; ; tries++) {
        int j = w_jacobi_dn(D, n);
        if (j == 0) return 0;                       /* gcd(D,n) > 1 ⇒ composite */
        if (j == -1) break;
        D = (D > 0) ? -(D + 2) : -(D - 2);          /* 5, -7, 9, -11, … */
        if (tries > 4096) return 0;                 /* no D ⇒ perfect square ⇒ composite */
    }
    int64_t Qi = (1 - D) / 4;
    WValue P  = one;
    WValue Q  = w_int(Qi); if (Qi < 0) Q  = w_add(Q,  n);   /* Q mod n */
    WValue Dv = w_int(D);  if (D  < 0) Dv = w_add(Dv, n);   /* D mod n */

    /* n + 1 = d·2^s with d odd (δ = n - Jacobi(D,n) = n + 1). */
    WValue d = w_add(n, one);
    int s = 0;
    while ((integer_low_i64(d) & 1) == 0) { d = w_div(d, two); s++; }

    /* Lucas ladder over the bits of d below the leading 1, tracking
     * (U_k, V_k, Q^k) mod n. Double: U←UV, V←V²-2Qᵏ, Qᵏ←(Qᵏ)²; on a set bit
     * advance one index: U←(PU+V)/2, V←(DU+PV)/2, Qᵏ←Qᵏ·Q. */
    WValue U = one, V = P, Qk = Q;
    for (int i = w_int_bit_length(d) - 2; i >= 0; i--) {
        U  = w_mod(w_mul(U, V), n);
        V  = w_sub_mod(w_mul(V, V), w_mul(two, Qk), n);
        Qk = w_mod(w_mul(Qk, Qk), n);
        if (w_int_test_bit(d, i)) {
            WValue nU = w_mod(w_add(w_mul(P,  U), V), n);
            WValue nV = w_mod(w_add(w_mul(Dv, U), w_mul(P, V)), n);
            U  = w_halve_mod(nU, n);
            V  = w_halve_mod(nV, n);
            Qk = w_mod(w_mul(Qk, Q), n);
        }
    }

    /* Strong test: U_d ≡ 0, or V_{d·2^r} ≡ 0 for some 0 ≤ r < s. */
    if (w_eq(U, zero) == W_TRUE) return 1;
    for (int r = 0; r < s; r++) {
        if (w_eq(V, zero) == W_TRUE) return 1;
        V  = w_sub_mod(w_mul(V, V), w_mul(two, Qk), n);
        Qk = w_mod(w_mul(Qk, Qk), n);
    }
    return 0;
}

/* Copy src's magnitude into a caller-owned stable buffer and box it. Used to
 * lift a value out of the ctx's rotating result slots when it must survive many
 * subsequent modctx muls (dest must have capacity ≥ the modulus limb count). */
static WValue w_prime_stable_copy(WBigint *dest, WValue src) {
    uint64_t sc; int32_t l;
    const uint64_t *sl = integer_limbs(src, &sc, &l);
    int32_t la = l < 0 ? -l : l;
    for (int32_t j = 0; j < la; j++) dest->limbs[j] = sl[j];
    dest->size = la;
    return bigint_box(dest);
}

/* Strong Lucas probable-prime test through the Barrett modctx (Selfridge:
 * D = first of 5,-7,9,-11,… with Jacobi(D,n) = -1; P = 1, Q = (1-D)/4).
 * Same algorithm as the reference above, but:
 *   • U, V, Q^k live in preallocated stable limb buffers — zero allocations
 *     per ladder bit (the reference allocated 5-7 heap bigints per bit);
 *   • multiplications go through w_prime_modctx_mul (Barrett, division-free);
 *   • add/sub/half are limb-native (w_prime_mod_{add,sub,half}_limbs);
 *   • the exponent d = (n+1)>>s is walked via bit tests on n+1 (bit i of d is
 *     bit i+s of n+1) — no bigint divisions to peel s or step the ladder.
 * Each modctx result is consumed (copied/reduced into a stable buffer) before
 * the next mul, so the ctx's 3 rotating slots are never aliased. Precondition:
 * odd bigint n that already passed MR (D-search terminates; cap = square). */
static int w_prime_lucas_strong_ctx(WValue n, WPrimeModCtx *ctx) {
    int64_t D = 5;
    for (int tries = 0; ; tries++) {
        int j = w_jacobi_dn(D, n);
        if (j == 0) return 0;                       /* gcd(D,n) > 1 ⇒ composite */
        if (j == -1) break;
        D = (D > 0) ? -(D + 2) : -(D - 2);          /* 5, -7, 9, -11, … */
        if (tries > 4096) return 0;                 /* no D ⇒ perfect square ⇒ composite */
    }
    int64_t Qi = (1 - D) / 4;

    uint64_t sn; int32_t nl_;
    const uint64_t *nlimbs = integer_limbs(n, &sn, &nl_);
    int32_t k = nl_ < 0 ? -nl_ : nl_;

    /* stable state buffers (k+2 limbs: room for a+n before reduction) */
    WBigint *Ub  = bigint_alloc(k + 2), *Vb  = bigint_alloc(k + 2);
    WBigint *Qkb = bigint_alloc(k + 2), *Qb  = bigint_alloc(k + 2);
    WBigint *Dvb = bigint_alloc(k + 2), *Tb  = bigint_alloc(k + 2);
    WBigint *T2b = bigint_alloc(k + 2);
    WValue Uv = bigint_box(Ub), Vv = bigint_box(Vb), Qkv = bigint_box(Qkb);
    WValue Qv = bigint_box(Qb), Dvv = bigint_box(Dvb);

    /* U = V = P = 1, in the ctx's domain (Barrett: 1; Montgomery: R mod n).
     * Zero stays zero in either domain, so the U/V ≡ 0 checks are unchanged. */
    w_prime_stable_copy(Ub, ctx->onemv);
    w_prime_stable_copy(Vb, ctx->onemv);
    /* Q mod n and D mod n: |Qi|,|D| are small; negatives become n - |value|.
     * Built plain, then converted into the ctx's domain (identity for Barrett). */
    if (Qi >= 0) { Qb->limbs[0] = (uint64_t)Qi; Qb->size = (Qi != 0); }
    else {
        for (int32_t i = 0; i < k; i++) Qb->limbs[i] = nlimbs[i];
        uint64_t qa = (uint64_t)(-Qi);
        Qb->size = w_prime_sub_mag_inplace(Qb->limbs, k, &qa, 1);
    }
    if (D >= 0) { Dvb->limbs[0] = (uint64_t)D; Dvb->size = (D != 0); }
    else {
        for (int32_t i = 0; i < k; i++) Dvb->limbs[i] = nlimbs[i];
        uint64_t da = (uint64_t)(-D);
        Dvb->size = w_prime_sub_mag_inplace(Dvb->limbs, k, &da, 1);
    }
    w_prime_stable_copy(Qb, w_prime_modctx_to_domain(ctx, Qv));
    w_prime_stable_copy(Dvb, w_prime_modctx_to_domain(ctx, Dvv));
    for (int32_t i = 0; i < (Qb->size < 0 ? -Qb->size : Qb->size); i++) Qkb->limbs[i] = Qb->limbs[i];
    Qkb->size = Qb->size;                            /* Q^1 = Q (in-domain) */

    /* n + 1 = d·2^s: s and d's bits read straight off n+1 (one add, no divs). */
    WValue np1 = w_add(n, w_int(1));
    int nbp1 = w_int_bit_length(np1);
    int s = 0;
    while (s < nbp1 && w_int_test_bit(np1, s) == 0) s++;

    /* Ladder over the bits of d below its leading 1 (bit i of d = bit i+s of
     * n+1). Double: U←UV, V←V²−2Qᵏ, Qᵏ←(Qᵏ)²; set bit ⇒ advance one index:
     * U←(U+V)/2, V←(D·U+V)/2 (P=1), Qᵏ←Qᵏ·Q. */
    for (int i = (nbp1 - s) - 2; i >= 0; i--) {
        uint64_t st; int32_t tl;
        /* U ← U·V */
        const uint64_t *sl = integer_limbs(w_prime_modctx_mul(ctx, Uv, Vv), &st, &tl);
        int32_t ta = tl < 0 ? -tl : tl;
        for (int32_t j = 0; j < ta; j++) Ub->limbs[j] = sl[j];
        Ub->size = ta;
        /* V ← V² − 2Qᵏ */
        sl = integer_limbs(w_prime_modctx_mul(ctx, Vv, Vv), &st, &tl);
        ta = tl < 0 ? -tl : tl;
        T2b->size = w_prime_mod_add_limbs(T2b->limbs, Qkb->limbs, Qkb->size,
                                          Qkb->limbs, Qkb->size, nlimbs, k);
        Vb->size = w_prime_mod_sub_limbs(Vb->limbs, sl, ta,
                                         T2b->limbs, T2b->size, nlimbs, k);
        /* Qᵏ ← (Qᵏ)² */
        sl = integer_limbs(w_prime_modctx_mul(ctx, Qkv, Qkv), &st, &tl);
        ta = tl < 0 ? -tl : tl;
        for (int32_t j = 0; j < ta; j++) Qkb->limbs[j] = sl[j];
        Qkb->size = ta;

        if (w_int_test_bit(np1, i + s)) {
            /* Tb ← D·U (before U is overwritten) */
            sl = integer_limbs(w_prime_modctx_mul(ctx, Dvv, Uv), &st, &tl);
            ta = tl < 0 ? -tl : tl;
            for (int32_t j = 0; j < ta; j++) Tb->limbs[j] = sl[j];
            Tb->size = ta;
            /* U ← (U + V)/2 */
            T2b->size = w_prime_mod_add_limbs(T2b->limbs, Ub->limbs, Ub->size,
                                              Vb->limbs, Vb->size, nlimbs, k);
            Ub->size = w_prime_mod_half_limbs(Ub->limbs, T2b->limbs, T2b->size, nlimbs, k);
            /* V ← (D·U_old + V)/2 */
            T2b->size = w_prime_mod_add_limbs(T2b->limbs, Tb->limbs, Tb->size,
                                              Vb->limbs, Vb->size, nlimbs, k);
            Vb->size = w_prime_mod_half_limbs(Vb->limbs, T2b->limbs, T2b->size, nlimbs, k);
            /* Qᵏ ← Qᵏ·Q */
            sl = integer_limbs(w_prime_modctx_mul(ctx, Qkv, Qv), &st, &tl);
            ta = tl < 0 ? -tl : tl;
            for (int32_t j = 0; j < ta; j++) Qkb->limbs[j] = sl[j];
            Qkb->size = ta;
        }
    }

    /* Strong test: U_d ≡ 0, or V_{d·2^r} ≡ 0 for some 0 ≤ r < s. */
    int ok = 0;
    if (Ub->size == 0) ok = 1;
    for (int r = 0; !ok && r < s; r++) {
        if (Vb->size == 0) { ok = 1; break; }
        uint64_t st; int32_t tl;
        const uint64_t *sl = integer_limbs(w_prime_modctx_mul(ctx, Vv, Vv), &st, &tl);
        int32_t ta = tl < 0 ? -tl : tl;
        T2b->size = w_prime_mod_add_limbs(T2b->limbs, Qkb->limbs, Qkb->size,
                                          Qkb->limbs, Qkb->size, nlimbs, k);
        Vb->size = w_prime_mod_sub_limbs(Vb->limbs, sl, ta,
                                         T2b->limbs, T2b->size, nlimbs, k);
        sl = integer_limbs(w_prime_modctx_mul(ctx, Qkv, Qkv), &st, &tl);
        ta = tl < 0 ? -tl : tl;
        for (int32_t j = 0; j < ta; j++) Qkb->limbs[j] = sl[j];
        Qkb->size = ta;
    }
    bigint_backing_free(Ub); bigint_backing_free(Vb);
    bigint_backing_free(Qkb); bigint_backing_free(Qb);
    bigint_backing_free(Dvb); bigint_backing_free(Tb);
    bigint_backing_free(T2b);
    return ok;
}

static int w_prime_test_bigint(WValue n) {
    /* Small-factor screen: divisible by a small prime ⇒ composite. Limb-native
     * (mag_mod_single) — no w_mod / w_eq per prime. */
    static const uint64_t SMALL[] = {2,3,5,7,11,13,17,19,23,29,31,37,41};
    uint64_t sn; int32_t nl;
    const uint64_t *nlimbs = integer_limbs(n, &sn, &nl);
    int32_t nabs = nl < 0 ? -nl : nl;
    for (size_t i = 0; i < sizeof(SMALL)/sizeof(SMALL[0]); i++)
        if (mag_mod_single(nlimbs, nabs, SMALL[i]) == 0ULL) return 0;

    WPrimeModCtx modctx;
    w_prime_modctx_init(&modctx, n);

    /* n−1 = d·2^s: trailing zeros and exponent bits read off n's limbs (odd n). */
    int nb1 = w_prime_mag_bit_length(nlimbs, nabs);
    int s = w_prime_nm1_trailing_zeros(nlimbs, nabs);

    /* x and base persist across the whole square-and-multiply, but the ctx's
     * result slots ROTATE (only 3): a value held while `base` squares through a
     * run of zero exponent bits would be clobbered when the rotation cycles back.
     * Keep x and base in their own stable buffers, copying each modctx result out
     * of the transient rotating slot. */
    WBigint *xbuf = bigint_alloc(modctx.limbs + 2);
    WBigint *basebuf = bigint_alloc(modctx.limbs + 2);

    for (size_t i = 0; i < sizeof(W_PRIME_MR_BASES)/sizeof(W_PRIME_MR_BASES[0]); i++) {
        /* Limb-native square-and-multiply: stable x/base buffers, mul_into, limb SPRP. */
        {
            int32_t ol = modctx.onemb->size < 0 ? -modctx.onemb->size : modctx.onemb->size;
            xbuf->size = ol;
            for (int32_t j = 0; j < ol; j++) xbuf->limbs[j] = modctx.onemb->limbs[j];
        }
        basebuf->size = w_prime_modctx_plain_into(basebuf, &modctx,
                                                  (uint64_t)W_PRIME_MR_BASES[i]);
        for (int bit = s; bit < nb1; bit++) {
            if (w_prime_nm1_test_bit(nlimbs, nabs, bit))
                xbuf->size = w_prime_modctx_mul_bigint_into(xbuf, &modctx, xbuf, basebuf);
            basebuf->size = w_prime_modctx_mul_bigint_into(basebuf, &modctx, basebuf, basebuf);
        }
        if (w_prime_domain_eq(xbuf, modctx.onemb) || w_prime_domain_eq(xbuf, modctx.nm1mb))
            continue;
        int composite = 1;
        for (int r = 1; r < s; r++) {
            xbuf->size = w_prime_modctx_mul_bigint_into(xbuf, &modctx, xbuf, xbuf);
            if (w_prime_domain_eq(xbuf, modctx.nm1mb)) { composite = 0; break; }
        }
        if (composite) { bigint_backing_free(xbuf); bigint_backing_free(basebuf); w_prime_modctx_fini(&modctx); return 0; }
    }
    bigint_backing_free(xbuf); bigint_backing_free(basebuf);
    /* All MR bases passed (probable prime — the Sinclair set is proven only
     * below 2^64). Confirm with a strong Lucas test → Baillie-PSW: no known
     * counterexample at any size, but for n ≥ 2^64 this is a (deterministic,
     * reproducible) probable-prime verdict, not a proof — unlike the u64
     * ladder, Lucas-Lehmer (Mersenne), and Proth paths, which are exact. */
    int ok = w_prime_lucas_strong_ctx(n, &modctx);
    w_prime_modctx_fini(&modctx);
    return ok;
}

/* Proth shape test: N−1 = k·2^s with k odd is Proth iff k < 2^s, i.e.
 * bitlen(N−1) ≤ 2s. For odd N, N−1 is N with bit 0 cleared (borrowless), so
 * both s and the bit length read straight off N's limbs. Returns s or 0. */
static int w_prime_proth_shape(const uint64_t *nl, int32_t nlen) {
    if (nlen <= 0 || (nl[0] & 1ULL) == 0) return 0;
    uint64_t low0 = nl[0] & ~1ULL;
    int s;
    if (low0 != 0) s = __builtin_ctzll(low0);
    else {
        int32_t i = 1;
        while (i < nlen && nl[i] == 0) i++;
        if (i >= nlen) return 0;                /* N == 1 */
        s = i * 64 + __builtin_ctzll(nl[i]);
    }
    int nb = (nlen - 1) * 64 + (64 - __builtin_clzll(nl[nlen - 1]));
    return (nb - s <= s) ? s : 0;
}

/* Proth's theorem: for N = k·2^s + 1 (odd k < 2^s) and a witness a with
 * Jacobi(a, N) = −1, N is prime ⟺ a^((N−1)/2) ≡ −1 (mod N). Exact in BOTH
 * directions (⇐ is the theorem, ⇒ is Euler's criterion for prime N), so one
 * half-length modexp replaces the whole 7-base MR + Lucas battery — and unlike
 * BPSW above the MR determinism bound, it is a proof. The modexp runs through
 * the domain-aware modctx exactly like the MR loop. Returns 1 prime /
 * 0 composite / −1 no witness among the candidates (perfect squares have no
 * QNR in any fixed list) — caller falls back to BPSW. */
static int w_prime_test_proth(WValue n) {
    static const int64_t CAND[] = {3,5,7,11,13,17,19,23,29,31,37,41,43,47,
                                   53,59,61,67,71,73,79,83,89,97};
    int64_t a = 0;
    for (size_t i = 0; i < sizeof(CAND)/sizeof(CAND[0]); i++) {
        int j = w_jacobi_dn(CAND[i], n);
        if (j == 0) return 0;                   /* gcd(a,N) > 1, N ≫ a ⇒ proper factor */
        if (j == -1) { a = CAND[i]; break; }
    }
    if (a == 0) return -1;
    uint64_t sn; int32_t nl;
    const uint64_t *nlimbs = integer_limbs(n, &sn, &nl);
    int32_t nabs = nl < 0 ? -nl : nl;
    int nb1 = w_prime_mag_bit_length(nlimbs, nabs);
    WPrimeModCtx ctx;
    w_prime_modctx_init(&ctx, n);
    WBigint *xbuf = bigint_alloc(ctx.limbs + 2);
    WBigint *basebuf = bigint_alloc(ctx.limbs + 2);
    WValue x = w_prime_stable_copy(xbuf, ctx.onemv);
    WValue base = w_prime_stable_copy(basebuf,
        w_prime_modctx_to_domain(&ctx, w_int(a)));
    for (int bit = 1; bit < nb1; bit++) {       /* exponent (N−1)/2 = (N−1) >> 1 */
        if (w_prime_nm1_test_bit(nlimbs, nabs, bit))
            x = w_prime_stable_copy(xbuf, w_prime_modctx_mul(&ctx, x, base));
        base = w_prime_stable_copy(basebuf, w_prime_modctx_mul(&ctx, base, base));
    }
    int prime = (w_eq(x, ctx.nm1mv) == W_TRUE);
    bigint_backing_free(xbuf); bigint_backing_free(basebuf);
    w_prime_modctx_fini(&ctx);
    return prime;
}

/* ---- General modular exponentiation (Int#modpow / Integer#pow(e, m)) ----
 * pow(a, e, m) over int48/BigInt WValues, result in [0, |m|). Reuses the
 * WPrimeModCtx machinery above:
 * Montgomery (CIOS below W_MONT_SOS_MIN limbs, SOS with asm-kernel product +
 * addmul_1 REDC above) for odd moduli up to W_POWM_MONT_MAX_LIMBS limbs, the
 * k==2 register-Barrett path, and subquadratic Barrett beyond the cap and for
 * even moduli (which Montgomery cannot represent). The exponent is walked
 * MSB→LSB straight off its limbs with an exponent-sized sliding window;
 * squarings ride w_prime_modctx_sqr_bigint_into. Unlike the primality users,
 * powmod must leave the Montgomery domain: entry is MontMul(x, R²), exit is
 * MontMul(x, 1) = x·R⁻¹. */
#ifndef W_POWM_MONT_MAX_LIMBS
#define W_POWM_MONT_MAX_LIMBS 384
#endif

static inline int w_powm_bit(const uint64_t *l, int32_t len, int i) {
    int32_t limb = i >> 6;
    if (limb >= len) return 0;
    return (int)((l[limb] >> (i & 63)) & 1ULL);
}

/* Bits lo..lo+cnt-1 of the magnitude (cnt ≤ 8), LSB-first packing. */
static inline int w_powm_bits(const uint64_t *l, int32_t len, int lo, int cnt) {
    int v = 0;
    for (int j = cnt - 1; j >= 0; j--) v = (v << 1) | w_powm_bit(l, len, lo + j);
    return v;
}

/* Sliding-window width selected from the exponent bit count.  The
 * thresholds are the exact 2^(w-1) + eb/(w+1) breakevens (673, 1793 and
 * 4609 are where w and w+1 tie); W_POWM_WINDOW_FORCE pins a width for
 * A/B measurement builds. */
static int w_powm_window_bits(int eb) {
#ifdef W_POWM_WINDOW_FORCE
    (void)eb;
    return W_POWM_WINDOW_FORCE;
#endif
    if (eb < 7) return 1;
    if (eb < 25) return 2;
    if (eb < 81) return 3;
    if (eb < 241) return 4;
    if (eb < 673) return 5;
    if (eb < 1793) return 6;
    if (eb < 4609) return 7;
    return 8;
}

/* Single-limb odd modulus: pure register Montgomery (w_mont_mul), no ctx and
 * no allocation. Sliding window over e's bits. Measured against the fixed-
 * window + branchless-csel variants: the data-dependent conditional subtract
 * and per-bit branch are effectively free on Apple cores, while csel adds two
 * serial cycles to every multiply — sliding+branchy wins by ~35%. b0 is the
 * base already reduced into [0, n). */
static WValue w_powmod_u64_odd(uint64_t b0, const uint64_t *el, int32_t elen,
                               int eb, uint64_t n) {
    if (b0 == 0) return w_box_int(0);            /* eb ≥ 1 here */
    if (b0 == 1) return w_box_int(1);
    uint64_t inv = w_mont_ninv(n);
    uint64_t one_m = (0ULL - n) % n;             /* R mod n (hardware u64 divide) */
    uint64_t bm;
    if (b0 == 2ULL) {
        bm = (one_m >= n - one_m) ? (one_m - (n - one_m)) : (one_m + one_m);
    } else if (((b0 | one_m) >> 32) == 0ULL) {
        bm = (b0 * one_m) % n;
    } else {
        uint64_t r2 = (uint64_t)(((__uint128_t)one_m * one_m) % n);
        bm = w_mont_mul_sub(b0, r2, n, inv);
    }
    int wbits = w_powm_window_bits(eb);
    if (wbits > 6) wbits = 6;
    int tcount = 1 << (wbits - 1);
    uint64_t tbl[32];                            /* odd powers b^1, b^3, … */
    tbl[0] = bm;
    if (tcount > 1) {
        uint64_t b2 = w_mont_mul_sub(bm, bm, n, inv);
        for (int t = 1; t < tcount; t++) tbl[t] = w_mont_mul_sub(tbl[t - 1], b2, n, inv);
    }
    int i = eb - 1;
    uint64_t x;
    {
        int l = i - wbits + 1;
        if (l < 0) l = 0;
        while (!w_powm_bit(el, elen, l)) l++;
        x = tbl[w_powm_bits(el, elen, l, i - l + 1) >> 1];
        i = l - 1;
    }
    while (i >= 0) {
        if (!w_powm_bit(el, elen, i)) {
            x = w_mont_mul_sub(x, x, n, inv);
            i--;
        } else {
            int l = i - wbits + 1;
            if (l < 0) l = 0;
            while (!w_powm_bit(el, elen, l)) l++;
            for (int s = i - l + 1; s > 0; s--) x = w_mont_mul_sub(x, x, n, inv);
            x = w_mont_mul_sub(x, tbl[w_powm_bits(el, elen, l, i - l + 1) >> 1], n, inv);
            i = l - 1;
        }
    }
    uint64_t res = w_mont_mul_sub(x, 1ULL, n, inv);   /* domain exit: x·R⁻¹ */
    if (res <= (uint64_t)W_INT48_MAX) return w_box_int((int64_t)res);
    return bigint_from_u64(res);
}

/* Same ladder for a one-limb exponent held in a register: the window scans
 * are plain shifts instead of bounds-checked limb reads. */
static WValue w_powmod_u64_odd_e1(uint64_t b0, uint64_t e, int eb, uint64_t n) {
    if (b0 == 0) return w_box_int(0);
    if (b0 == 1) return w_box_int(1);
    if ((n >> 32) == 0ULL && eb <= 32) {
        uint32_t n32 = (uint32_t)n;
        uint32_t inv32 = w_mont32_ninv(n32);
        uint32_t bm32 = (uint32_t)((b0 << 32) % n);
        uint32_t x32 = bm32;
        uint32_t e32 = (uint32_t)e;
        for (int bit = eb - 2; bit >= 0; bit--) {
            x32 = w_mont32_mul(x32, x32, n32, inv32);
            if ((e32 >> bit) & 1U) x32 = w_mont32_mul(x32, bm32, n32, inv32);
        }
        uint32_t res32 = w_mont32_mul(x32, 1U, n32, inv32);
        return w_box_int((int64_t)res32);
    }
    uint64_t inv = w_mont_ninv(n);
    uint64_t one_m = (0ULL - n) % n;
    uint64_t bm;
    if (b0 == 2ULL) {
        bm = (one_m >= n - one_m) ? (one_m - (n - one_m)) : (one_m + one_m);
    } else if (((b0 | one_m) >> 32) == 0ULL) {
        bm = (b0 * one_m) % n;
    } else {
        uint64_t r2 = (uint64_t)(((__uint128_t)one_m * one_m) % n);
        bm = w_mont_mul_sub(b0, r2, n, inv);
    }
    int wbits = w_powm_window_bits(eb);
    if (wbits > 6) wbits = 6;
    int tcount = 1 << (wbits - 1);
    uint64_t tbl[32];
    tbl[0] = bm;
    if (tcount > 1) {
        uint64_t b2 = w_mont_mul_sub(bm, bm, n, inv);
        for (int t = 1; t < tcount; t++) tbl[t] = w_mont_mul_sub(tbl[t - 1], b2, n, inv);
    }
    int i = eb - 1;
    uint64_t x;
    {
        int l = i - wbits + 1;
        if (l < 0) l = 0;
        while (!((e >> l) & 1ULL)) l++;
        int cnt = i - l + 1;
        x = tbl[((e >> l) & ((1ULL << cnt) - 1ULL)) >> 1];
        i = l - 1;
    }
    while (i >= 0) {
        if (!((e >> i) & 1ULL)) {
            x = w_mont_mul_sub(x, x, n, inv);
            i--;
        } else {
            int l = i - wbits + 1;
            if (l < 0) l = 0;
            while (!((e >> l) & 1ULL)) l++;
            int cnt = i - l + 1;
            for (int s = cnt; s > 0; s--) x = w_mont_mul_sub(x, x, n, inv);
            x = w_mont_mul_sub(x, tbl[((e >> l) & ((1ULL << cnt) - 1ULL)) >> 1], n, inv);
            i = l - 1;
        }
    }
    uint64_t res = w_mont_mul_sub(x, 1ULL, n, inv);
    if (res <= (uint64_t)W_INT48_MAX) return w_box_int((int64_t)res);
    return bigint_from_u64(res);
}

#if BN_ALGEBRAIC_IDENTITY_FAST
/* Recognize e = p - 1 for the BN254 and secp256k1 base-field primes.
 * Constants are little-endian 64-bit limbs from EIP-196 and SEC 2 v2 §2.4.1:
 * https://eips.ethereum.org/EIPS/eip-196
 * https://www.secg.org/sec2-v2.pdf
 * These are exact prime checks, not a probable-prime test. Both low limbs
 * are nonzero, so subtracting one never borrows into the upper limbs. */
static inline int w_powm_fermat_prime_exponent(const uint64_t *m, int32_t mlen,
                                             const uint64_t *e, int32_t elen) {
    if (mlen != 4 || elen != 4) return 0;
    if (e[0] != m[0] - 1 || e[1] != m[1] ||
        e[2] != m[2] || e[3] != m[3]) return 0;
    return (m[0] == 0x3c208c16d87cfd47ULL &&
            m[1] == 0x97816a916871ca8dULL &&
            m[2] == 0xb85045b68181585dULL &&
            m[3] == 0x30644e72e131a029ULL) ||
           (m[0] == 0xfffffffefffffc2fULL &&
            m[1] == 0xffffffffffffffffULL &&
            m[2] == 0xffffffffffffffffULL &&
            m[3] == 0xffffffffffffffffULL);
}
#endif

WValue bigint_powmod_any(WValue base, WValue expv, WValue modv) {
    if (!w_is_integer_any(base) || !w_is_integer_any(expv) ||
        !w_is_integer_any(modv))
        die("modpow: integer operands required");
    uint64_t sb, se, sm;
    int32_t lb, le, lm;
    const uint64_t *el = integer_limbs(expv, &se, &le);
    if (le < 0) die("modpow: negative exponent");
    const uint64_t *ml = integer_limbs(modv, &sm, &lm);
    int32_t mabs = lm < 0 ? -lm : lm;
    if (mabs == 0) die("modpow: modulus must be nonzero");
    if (mabs == 1 && ml[0] == 1ULL) return w_box_int(0);   /* mod ±1 → 0 */
    int eb = w_prime_mag_bit_length(el, le < 0 ? -le : le);
    if (eb == 0) return w_box_int(1);                      /* e == 0 → 1 % m, |m| > 1 */

    const uint64_t *bl = integer_limbs(base, &sb, &lb);
    int bneg = lb < 0;
    int32_t babs = bneg ? -lb : lb;

#if BN_ALGEBRAIC_IDENTITY_FAST
    WValue one = w_box_int(1);
    if (base == one) return one;                         /* 1**e mod m = 1 */
    if (base == w_box_int(-1)) {
        if ((el[0] & 1ULL) == 0) return one;             /* (-1)**even = 1 */
        if (mabs == 1) return bigint_from_u64(ml[0] - 1);
        WBigint *minus_one = bigint_alloc_raw_hot(mabs);
        memcpy(minus_one->limbs, ml, (size_t)mabs * sizeof(uint64_t));
        uint64_t borrow = 1;
        for (int32_t i = 0; i < mabs && borrow; i++) {
            uint64_t before = minus_one->limbs[i];
            minus_one->limbs[i] = before - borrow;
            borrow = before < borrow;
        }
        minus_one->size = mabs;
        return bigint_normalize(minus_one);              /* odd -> |m| - 1 */
    }
    if (expv == one && !bneg &&
        (babs < mabs ||
         (babs == mabs && mag_cmp(bl, babs, ml, mabs) < 0))) {
        /* Alias return: mark shared so releasing the result cannot
         * recycle the still-live base. */
        if (w_is_bigint(base)) w_bigint_mark_shared(w_as_bigint(base));
        return base;                                     /* already canonical */
    }
#endif

    if (mabs == 1) {
        uint64_t n = ml[0];
        uint64_t b0 = babs == 1 ? (bl[0] < n ? bl[0] : bl[0] % n)
                    : babs      ? mag_mod_single(bl, babs, n)
                                : 0;
        if (bneg && b0) b0 = n - b0;
        if (n & 1ULL) {
            int32_t elen = le < 0 ? -le : le;
            if (elen == 1) return w_powmod_u64_odd_e1(b0, el[0], eb, n);
            return w_powmod_u64_odd(b0, el, elen, eb, n);
        }
        /* even single-limb modulus: rare — fall through to the Barrett ctx */
    }

    /* Reduce the base into [0, |m|): truncated remainder (sign of the
     * dividend), then one magnitude fold for negative bases. The general
     * division keeps oversized bases out of Barrett's x < b^(2k) window. */
    WValue r0v = base;
    if (babs >= mabs) r0v = bigint_mod_any(base, modv);
    uint64_t sr; int32_t lr;
    const uint64_t *rl0 = integer_limbs(r0v, &sr, &lr);
    int rneg = lr < 0;
    int32_t rabs = rneg ? -lr : lr;
    if (rabs == 0) return w_box_int(0);                    /* base ≡ 0, e ≥ 1 */

#if BN_ALGEBRAIC_IDENTITY_FAST
    if (w_powm_fermat_prime_exponent(ml, mabs, el, le)) {
        /* Fermat: a nonzero residue has a^(p-1) = 1 mod p. Divisible
         * bases already returned zero above. Signs need no fold here;
         * the modulus magnitude and nonzero test suffice. */
        if (r0v != base && w_is_bigint(r0v))
            bigint_release_if_live(w_as_bigint(r0v));
        return w_box_int(1);
    }
#endif

    /* The ctx wants a positive modulus value; |m| drives everything else. */
    WBigint *mposb = NULL;
    WValue modmag = modv;
    if (lm < 0) {
        if (mabs == 1 && ml[0] <= (uint64_t)W_INT48_MAX) {
            modmag = w_box_int((int64_t)ml[0]);
        } else {
            mposb = bigint_alloc(mabs);
            for (int32_t i = 0; i < mabs; i++) mposb->limbs[i] = ml[i];
            mposb->size = mabs;
            modmag = bigint_box(mposb);
        }
    }

    WPrimeModCtx ctx;
    /* The raw-row ladder below (odd modulus, k >= 3) enters the domain by
     * division and needs none of the context's Montgomery constants. */
    w_prime_modctx_init_cap_mode(&ctx, modmag,
                                 (ml[0] & 1ULL) ? W_POWM_MONT_MAX_LIMBS : 0,
                                 (ml[0] & 1ULL) && mabs >= 3);
    int32_t k = ctx.limbs, cap = k + 2;
    int wbits = w_powm_window_bits(eb);
    int32_t tcount = 1 << (wbits - 1);
    int32_t elen = le < 0 ? -le : le;
    /* Only the odd-power rows the exponent's windows actually select. */
    int32_t tused = w_powm_table_rows_used(el, elen, eb, wbits);

    if (ctx.mont && k >= 3) {
        /* Fast Montgomery ladder on raw k-limb rows: direct dispatcher +
         * REDC calls, no per-op WValue plumbing, dual-row REDC on aarch64,
         * and a multiply-free REDC domain exit. */
        uint64_t smod2; int32_t lmod2;
        const uint64_t *nl = integer_limbs(ctx.modulus, &smod2, &lmod2);
        uint64_t np0 = ctx.nprime, np1;
        {   /* high limb of −n⁻¹ mod B² by one Newton lift of the B-inverse */
            uint64_t i0 = w_mont_ninv(nl[0]);
            __uint128_t ni = (__uint128_t)nl[0] * i0;
            uint64_t e2 = (uint64_t)(ni >> 64) + nl[1] * i0;
            np1 = ~(0ULL - i0 * e2);
        }
        uint64_t *T = ctx.work;                     /* 12k+16 ≥ 6k+4 limbs */
        /* The cyclic high product needs an even split.  Odd widths stay on
         * pairs REDC instead of paying mullo plus a fallback full product. */
        int use_mullo = k >= W_POWM_REDC_MULLO_MIN && (k & 1) == 0;
        /* One-page ladders carry their REDC scratch and modulus stream in
         * the SAME allocation as the window table, each region >= 512 B
         * from the others — pairwise page offsets are then fixed by
         * construction.  Split across independent blocks (T = ctx->work,
         * the modulus wherever its owner put it), the relative page
         * offsets are an allocation lottery, and a draw that lands a hot
         * row or the modulus inside the LSU's 4 KiB store->load window of
         * the per-op REDC stores taxes every operation (measured ~1.1% on
         * powmod@8; the bigint arena's 512 B placement grid made the bad
         * draw stable instead of occasional).  Multi-page ladders keep the
         * status quo: their table alone blankets every page phase, so no
         * placement is categorically safe.  The pairs REDC touches
         * T[0..2k+1] only; mullo widths (>= 48 limbs) never fit the page
         * and stay on ctx->work with its full 6k+4 window. */
        size_t lad_limbs = ((size_t)tcount + 1 + (use_mullo ? 1 : 0)) *
                           (size_t)k;
        size_t t_off = 0, nl_off = 0, el_off = 0;
        if (!use_mullo) {
            /* Even limb offsets keep each region 16-byte aligned (odd k
             * would otherwise tilt every region off the vector kernels'
             * natural alignment). */
            t_off = (lad_limbs + 64 + 1) & ~(size_t)1; /* >= 512 B past x */
            size_t n_off = t_off + 2 * (size_t)k + 2 + 64;
            size_t e_off = (n_off + (size_t)k + 64 + 1) & ~(size_t)1;
            if ((e_off + (size_t)elen) * sizeof(uint64_t) <= 4096u) {
                nl_off = n_off;
                el_off = e_off;
                lad_limbs = e_off + (size_t)elen;
            } else {
                t_off = 0;
            }
        }
        uint64_t *arena =
            (uint64_t *)malloc(lad_limbs * sizeof(uint64_t));
        uint64_t *x = arena + (size_t)tcount * (size_t)k;
        if (nl_off) {
            T = arena + t_off;
            uint64_t *nl_copy = arena + nl_off;
            for (int32_t j = 0; j < k; j++) nl_copy[j] = nl[j];
            nl = nl_copy;
            /* The exponent is the other per-step read stream (w_powm_bit
             * on every ladder iteration); pin its page offsets with the
             * rest of the working set. */
            uint64_t *el_copy = arena + el_off;
            for (int32_t j = 0; j < elen; j++) el_copy[j] = el[j];
            el = el_copy;
        }
        const uint64_t *mip = NULL;
        if (use_mullo) {                            /* Newton k-limb inverse */
            uint64_t *mipw = arena + ((size_t)tcount + 1) * (size_t)k;
            w_mont_ninv_k(mipw, nl, k, np0, T);     /* T free until ladder */
            mip = mipw;
        }
#define W_POWM_ROW(t) (arena + (size_t)(t) * (size_t)k)
        if (rneg) {                                 /* plain base = |m| − |r| */
            for (int32_t j = 0; j < k; j++) x[j] = ml[j];
            (void)w_prime_sub_mag_inplace(x, k, rl0, rabs);
        } else {
            for (int32_t j = 0; j < rabs; j++) x[j] = rl0[j];
            for (int32_t j = rabs; j < k; j++) x[j] = 0;
        }
        /* The reduced base has been copied out; a heap remainder minted by
         * the bigint_mod_any above was previously leaked (one k-limb buffer
         * per call). */
        if (r0v != base && w_is_bigint(r0v))
            bigint_release_if_live(w_as_bigint(r0v));
        /* domain entry: tbl[0] = base·R mod n by one division (no R²) */
        w_powm_mont_enter(W_POWM_ROW(0), x, k, nl);
        if (tused > 1) {                            /* odd powers via base² (staged in x) */
            w_powm_mont_sqr(x, W_POWM_ROW(0), k, nl, np0, np1, mip, T);
            for (int32_t t = 1; t < tused; t++)
                w_powm_mont_mul(W_POWM_ROW(t), W_POWM_ROW(t - 1), x, k, k,
                                nl, np0, np1, mip, T);
        }
        int i = eb - 1;
        {
            int l = i - wbits + 1;
            if (l < 0) l = 0;
            while (!w_powm_bit(el, elen, l)) l++;
            const uint64_t *seed =
                W_POWM_ROW(w_powm_bits(el, elen, l, i - l + 1) >> 1);
            for (int32_t j = 0; j < k; j++) x[j] = seed[j];
            i = l - 1;
        }
        while (i >= 0) {
            if (!w_powm_bit(el, elen, i)) {
                w_powm_mont_sqr(x, x, k, nl, np0, np1, mip, T);
                i--;
            } else {
                int l = i - wbits + 1;
                if (l < 0) l = 0;
                while (!w_powm_bit(el, elen, l)) l++;
                for (int s = i - l + 1; s > 0; s--)
                    w_powm_mont_sqr(x, x, k, nl, np0, np1, mip, T);
                w_powm_mont_mul(x, x,
                                W_POWM_ROW(w_powm_bits(el, elen, l, i - l + 1) >> 1),
                                k, k, nl, np0, np1, mip, T);
                i = l - 1;
            }
        }
        w_powm_mont_exit(x, x, k, nl, np0, np1, mip, T);
#undef W_POWM_ROW
        int32_t rl2 = k;
        while (rl2 > 0 && x[rl2 - 1] == 0) rl2--;
        WValue result;
        if (rl2 == 0) {
            result = w_box_int(0);
        } else if (rl2 == 1 && x[0] <= (uint64_t)W_INT48_MAX) {
            result = w_box_int((int64_t)x[0]);
        } else {
            WBigint *r = bigint_alloc(rl2);
            for (int32_t j = 0; j < rl2; j++) r->limbs[j] = x[j];
            r->size = rl2;
            result = bigint_normalize(r);
        }
        free(arena);
        w_prime_modctx_fini(&ctx);
        if (mposb) bigint_backing_free(mposb);
        return result;
    }

    /* Stable working buffers: the result, one scratch (base², later the plain
     * 1 for domain exit), and the odd-power window table b^1, b^3, …, all in
     * the ctx's domain. */
    WBigint *xbuf = bigint_alloc(cap);
    WBigint *gg = bigint_alloc(cap);
    WBigint *tbl[128];                                     /* wbits ≤ 8 */
    for (int32_t t = 0; t < tcount; t++) tbl[t] = bigint_alloc(cap);

    if (rneg) {                                            /* |m| − |r| */
        for (int32_t i = 0; i < k; i++) xbuf->limbs[i] = ml[i];
        xbuf->size = w_prime_sub_mag_inplace(xbuf->limbs, k, rl0, rabs);
    } else {
        for (int32_t i = 0; i < rabs; i++) xbuf->limbs[i] = rl0[i];
        xbuf->size = rabs;
    }
    /* Same leak as the ladder branch: release the minted remainder. */
    if (r0v != base && w_is_bigint(r0v))
        bigint_release_if_live(w_as_bigint(r0v));

    /* Domain entry: tbl[0] = base·R (Montgomery) or the plain base (Barrett). */
    if (ctx.mont) {
        tbl[0]->size = w_prime_modctx_mul_bigint_into(tbl[0], &ctx, xbuf, ctx.r2b);
    } else {
        int32_t bs = xbuf->size;
        for (int32_t i = 0; i < bs; i++) tbl[0]->limbs[i] = xbuf->limbs[i];
        tbl[0]->size = bs;
    }
    if (tused > 1) {
        gg->size = w_prime_modctx_sqr_bigint_into(gg, &ctx, tbl[0]);
        for (int32_t t = 1; t < tused; t++)
            tbl[t]->size = w_prime_modctx_mul_bigint_into(tbl[t], &ctx, tbl[t - 1], gg);
    }

    /* Left-to-right sliding window over e's bits. The leading window seeds the
     * accumulator directly (no initial 1·x multiply). */
    int i = eb - 1;
    {
        int l = i - wbits + 1;
        if (l < 0) l = 0;
        while (!w_powm_bit(el, elen, l)) l++;
        WBigint *seed = tbl[w_powm_bits(el, elen, l, i - l + 1) >> 1];
        int32_t ss = seed->size;
        for (int32_t j = 0; j < ss; j++) xbuf->limbs[j] = seed->limbs[j];
        xbuf->size = ss;
        i = l - 1;
    }
    while (i >= 0) {
        if (!w_powm_bit(el, elen, i)) {
            xbuf->size = w_prime_modctx_sqr_bigint_into(xbuf, &ctx, xbuf);
            i--;
        } else {
            int l = i - wbits + 1;
            if (l < 0) l = 0;
            while (!w_powm_bit(el, elen, l)) l++;
            for (int s = i - l + 1; s > 0; s--)
                xbuf->size = w_prime_modctx_sqr_bigint_into(xbuf, &ctx, xbuf);
            xbuf->size = w_prime_modctx_mul_bigint_into(
                xbuf, &ctx, xbuf, tbl[w_powm_bits(el, elen, l, i - l + 1) >> 1]);
            i = l - 1;
        }
    }

    if (ctx.mont) {                                        /* exit: MontMul(x, 1) = x·R⁻¹ */
        gg->limbs[0] = 1ULL;
        gg->size = 1;
        xbuf->size = w_prime_modctx_mul_bigint_into(xbuf, &ctx, xbuf, gg);
    }

    int32_t rl2 = xbuf->size;
    WValue result;
    if (rl2 == 0) {
        result = w_box_int(0);
    } else if (rl2 == 1 && xbuf->limbs[0] <= (uint64_t)W_INT48_MAX) {
        result = w_box_int((int64_t)xbuf->limbs[0]);
    } else {
        WBigint *r = bigint_alloc(rl2);
        for (int32_t j = 0; j < rl2; j++) r->limbs[j] = xbuf->limbs[j];
        r->size = rl2;
        result = bigint_normalize(r);
    }

    bigint_backing_free(xbuf);
    bigint_backing_free(gg);
    for (int32_t t = 0; t < tcount; t++) bigint_backing_free(tbl[t]);
    w_prime_modctx_fini(&ctx);
    if (mposb) bigint_backing_free(mposb);
    return result;
}

/* If a positive bigint magnitude (nlimbs 64-bit little-endian limbs) equals
 * 2^p - 1, return p; otherwise 0. A Mersenne magnitude is all-ones in binary:
 * every limb below the top is ~0, and the top limb is itself all-ones, which
 * holds exactly when (top & (top+1)) == 0 (and top != 0). The exponent is then
 * the total bit count — no division and no 2^p materialization needed. */
static uint64_t w_mersenne_exponent(const uint64_t *limbs, int32_t nlimbs) {
    for (int32_t i = 0; i < nlimbs - 1; i++)
        if (limbs[i] != ~0ULL) return 0;
    uint64_t top = limbs[nlimbs - 1];
    if (top == 0ULL) return 0;                   /* non-canonical / not all-ones */
    if ((top & (top + 1ULL)) != 0ULL) return 0;  /* top is not of the form 2^k-1 */
    return (uint64_t)(nlimbs - 1) * 64ULL + (uint64_t)__builtin_popcountll(top);
}

/* t >> p, for a non-negative integer WValue t and p > 0. Drops the low p bits
 * by skipping p/64 whole limbs and shifting the rest down by p%64. */
static WValue w_mag_shr(WValue t, uint64_t p) {
    uint64_t st; int32_t tl;
    const uint64_t *tlimbs = integer_limbs(t, &st, &tl);
    if (tl <= 0) return w_box_int(0);
    uint32_t q = (uint32_t)(p >> 6), b = (uint32_t)(p & 63);
    if ((int32_t)q >= tl) return w_box_int(0);   /* everything shifted away */
    int32_t rlen = tl - (int32_t)q;
    WBigint *r = bigint_alloc(rlen);
    if (b == 0) {
        for (int32_t i = 0; i < rlen; i++) r->limbs[i] = tlimbs[q + i];
    } else {
        for (int32_t i = 0; i < rlen; i++) {
            uint64_t lo = tlimbs[q + i] >> b;
            uint64_t hi = ((int32_t)(q + i + 1) < tl) ? (tlimbs[q + i + 1] << (64 - b)) : 0;
            r->limbs[i] = lo | hi;
        }
    }
    r->size = rlen;
    return bigint_normalize(r);
}

/* t & (2^p - 1) — the low p bits of a non-negative integer WValue t. */
static WValue w_mag_low(WValue t, uint64_t p) {
    uint64_t st; int32_t tl;
    const uint64_t *tlimbs = integer_limbs(t, &st, &tl);
    if (tl <= 0) return w_box_int(0);
    uint32_t q = (uint32_t)(p >> 6), b = (uint32_t)(p & 63);
    int32_t keep = (int32_t)q + (b ? 1 : 0);
    /* Strictly fewer limbs than p needs ⇒ t < 2^p already. At tl == keep the
     * top limb still has to be masked, so only short-circuit when tl < keep. */
    if (tl < keep) return t;
    WBigint *r = bigint_alloc(keep);
    for (int32_t i = 0; i < (int32_t)q; i++) r->limbs[i] = tlimbs[i];
    if (b) r->limbs[q] = tlimbs[q] & ((1ULL << b) - 1ULL);
    r->size = keep;
    return bigint_normalize(r);
}

/* t mod (2^p - 1) by shift-and-add, for 0 <= t < 2^(2p). Since 2^p ≡ 1
 * (mod 2^p-1), t ≡ (t >> p) + (t & (2^p-1)); folding repeats until t < 2^p
 * (each fold strictly shrinks t: t-(hi+lo) = hi·(2^p-1) > 0). A final
 * subtraction maps the lone remaining value 2^p-1 to 0. No division — the
 * whole point of running Lucas-Lehmer on the Mersenne form. */
static WValue w_mersenne_mod(WValue t, uint64_t p, WValue n) {
    for (;;) {
        WValue hi = w_mag_shr(t, p);
        if (w_eq(hi, w_int(0)) == W_TRUE) break;
        t = w_add(w_mag_low(t, p), hi);
    }
    while (w_lt(t, n) != W_TRUE) t = w_sub(t, n);  /* t <= 2^p-1 already: runs 0-1x */
    return t;
}

static void w_mersenne_add_limb(uint64_t *acc, int32_t acc_len, int32_t pos, uint64_t value) {
    uint64_t carry = value;
    for (int32_t i = pos; carry && i < acc_len; i++) {
        uint64_t old = acc[i];
        acc[i] = old + carry;
        carry = acc[i] < old;
    }
}

static void w_mersenne_fold_overflow(uint64_t *acc, int32_t nlimbs, uint32_t top_bits, uint64_t top_mask) {
    for (;;) {
        uint64_t overflow;
        if (top_bits == 64) {
            overflow = acc[nlimbs];
            acc[nlimbs] = 0;
        } else {
            overflow = acc[nlimbs - 1] >> top_bits;
            acc[nlimbs - 1] &= top_mask;
        }
        if (overflow == 0) break;
        w_mersenne_add_limb(acc, nlimbs + 1, 0, overflow);
    }
}

static int w_mersenne_acc_ge_mod(const uint64_t *acc, int32_t nlimbs, uint64_t top_mask) {
    for (int32_t i = nlimbs - 1; i >= 0; i--) {
        uint64_t mod_limb = (i == nlimbs - 1) ? top_mask : ~0ULL;
        if (acc[i] != mod_limb) return acc[i] > mod_limb;
    }
    return 1;
}

static void w_mersenne_acc_sub_mod(uint64_t *acc, int32_t nlimbs, uint64_t top_mask) {
    uint64_t borrow = 0;
    for (int32_t i = 0; i < nlimbs; i++) {
        uint64_t mod_limb = (i == nlimbs - 1) ? top_mask : ~0ULL;
        uint64_t sub = mod_limb + borrow;
        uint64_t next_borrow = (sub < mod_limb) || (acc[i] < sub);
        acc[i] -= sub;
        borrow = next_borrow;
    }
}

static WValue w_mersenne_reduce_product_limbs(const uint64_t *prod, int32_t prod_len,
                                               uint64_t p, uint64_t *acc) {
    int32_t nlimbs = (int32_t)((p + 63ULL) >> 6);
    uint32_t bit_shift = (uint32_t)(p & 63ULL);
    uint32_t top_bits = bit_shift == 0 ? 64U : bit_shift;
    uint64_t top_mask = top_bits == 64U ? ~0ULL : ((1ULL << top_bits) - 1ULL);
    memset(acc, 0, ((size_t)nlimbs + 1) * sizeof(uint64_t));

    int32_t low_len = prod_len < nlimbs ? prod_len : nlimbs;
    for (int32_t i = 0; i < low_len; i++) acc[i] = prod[i];
    acc[nlimbs - 1] &= top_mask;

    int32_t limb_shift = (int32_t)(p >> 6);
    for (int32_t i = 0; i < nlimbs; i++) {
        int32_t src = limb_shift + i;
        uint64_t word = 0;
        if (src < prod_len) {
            word = bit_shift == 0 ? prod[src] : (prod[src] >> bit_shift);
            if (bit_shift != 0 && src + 1 < prod_len) word |= prod[src + 1] << (64U - bit_shift);
        }
        if (word) w_mersenne_add_limb(acc, nlimbs + 1, i, word);
    }

    w_mersenne_fold_overflow(acc, nlimbs, top_bits, top_mask);
    if (w_mersenne_acc_ge_mod(acc, nlimbs, top_mask)) w_mersenne_acc_sub_mod(acc, nlimbs, top_mask);

    WBigint *r = bigint_alloc_raw(nlimbs);
    for (int32_t i = 0; i < nlimbs; i++) r->limbs[i] = acc[i];
    r->size = nlimbs;
    return bigint_normalize(r);
}

/* Lucas-Lehmer repeatedly squares residues of one fixed size.  Keep its
 * product and reduction accumulator in a separate TLS arena: the square
 * dispatcher already owns bn_ws for recursive scratch, so sharing that arena
 * would allow a growth realloc to invalidate the product pointer. */
static __thread uint64_t *w_mersenne_ws = NULL;
static __thread size_t w_mersenne_ws_cap = 0;
static uint64_t *w_mersenne_ws_get(size_t limbs) {
    if (limbs > w_mersenne_ws_cap) {
        free(w_mersenne_ws);
        size_t ncap = limbs + limbs / 2 + 16;
        w_mersenne_ws = (uint64_t *)malloc(ncap * sizeof(uint64_t));
        w_mersenne_ws_cap = w_mersenne_ws ? ncap : 0;
    }
    return w_mersenne_ws;
}

/* The p=127 Lucas-Lehmer residue is exactly two limbs.  Avoid routing its
 * four-word square through the generic dispatcher and fold loops: construct
 * the square directly, then use 2^127 == 1 for a two-word end-around carry. */
static WValue w_mersenne_square_mod_127(const uint64_t *a, int32_t n) {
    uint64_t a0 = a[0];
    uint64_t a1 = n > 1 ? a[1] : 0;
    __uint128_t z0 = (__uint128_t)a0 * a0;
    __uint128_t z1 = (__uint128_t)a0 * a1;
    __uint128_t z2 = (__uint128_t)a1 * a1;
    uint64_t z1lo = (uint64_t)z1;
    uint64_t z1hi = (uint64_t)(z1 >> 64);
    uint64_t cross0 = z1lo << 1;
    uint64_t cross1 = (z1hi << 1) | (z1lo >> 63);
    uint64_t cross2 = z1hi >> 63;
    __uint128_t t1 = (__uint128_t)(uint64_t)(z0 >> 64) + cross0;
    __uint128_t t2 = (__uint128_t)(uint64_t)z2 + cross1 + (uint64_t)(t1 >> 64);
    uint64_t p0 = (uint64_t)z0;
    uint64_t p1 = (uint64_t)t1;
    uint64_t p2 = (uint64_t)t2;
    uint64_t p3 = (uint64_t)(z2 >> 64) + cross2 + (uint64_t)(t2 >> 64);

    const uint64_t mask = UINT64_MAX >> 1;
    uint64_t r0 = p0;
    uint64_t r1 = p1 & mask;
    uint64_t h0 = (p1 >> 63) | (p2 << 1);
    uint64_t h1 = (p2 >> 63) | (p3 << 1);
    __uint128_t s0 = (__uint128_t)r0 + h0;
    __uint128_t s1 = (__uint128_t)r1 + h1 + (uint64_t)(s0 >> 64);
    r0 = (uint64_t)s0;
    r1 = (uint64_t)s1;
    uint64_t overflow = r1 >> 63;
    r1 &= mask;
    while (overflow) {
        uint64_t old = r0;
        r0 += overflow;
        uint64_t carry = r0 < old;
        r1 += carry;
        overflow = r1 >> 63;
        r1 &= mask;
    }
    if (r0 == UINT64_MAX && r1 == mask)
        return w_box_int(0);
    WBigint *r = bigint_alloc_raw(2);
    r->limbs[0] = r0;
    r->limbs[1] = r1;
    r->size = r1 ? 2 : (r0 ? 1 : 0);
    return bigint_normalize(r);
}

static WValue w_mersenne_square_mod(WValue s, uint64_t p) {
    uint64_t scratch;
    int32_t slen;
    const uint64_t *slimbs = integer_limbs(s, &scratch, &slen);
    if (slen <= 0) return w_box_int(0);
    if (p == 127 && slen <= 2)
        return w_mersenne_square_mod_127(slimbs, slen);

    int32_t nlimbs = (int32_t)((p + 63ULL) >> 6);
    size_t prod_limbs = (size_t)(2 * slen);
    size_t total = prod_limbs + (size_t)nlimbs + 1;
    uint64_t *prod = w_mersenne_ws_get(total);
    int owned = 0;
    if (!prod) {
        prod = (uint64_t *)malloc(total * sizeof(uint64_t));
        owned = 1;
    }
    if (!prod) die("out of memory");
    bigint_sqr_dispatch(prod, slimbs, slen);
    WValue r = w_mersenne_reduce_product_limbs(prod, 2 * slen, p, prod + prod_limbs);
    if (owned) free(prod);
    return r;
}

/* Cheap trial-factor screen for large Mersenne numbers. For odd prime p, every
 * prime factor q of M_p is q = 2kp + 1 and q ≡ 1 or 7 (mod 8). Testing
 * 2^p ≡ 1 (mod q) is all-u64 arithmetic and can avoid an expensive
 * Lucas-Lehmer run for composite search candidates. */
static int w_mersenne_has_u64_factor(uint64_t p) {
    static const uint64_t MIN_P = 65536ULL;
    static const uint64_t MAX_K = 100000ULL;
    static const uint64_t MAX_Q = 1ULL << 40;
    if (p < MIN_P || p > (UINT64_MAX - 1ULL) / 2ULL) return 0;
    uint64_t step = p << 1U;
    if (step + 1ULL > MAX_Q) return 0;
    uint64_t limit = (MAX_Q - 1ULL) / step;
    if (limit > MAX_K) limit = MAX_K;
    for (uint64_t k = 1ULL; k <= limit; k++) {
        uint64_t q = step * k + 1ULL;
        uint64_t r = q & 7ULL;
        if (r != 1ULL && r != 7ULL) continue;
        if (w_prime_powmod(2ULL, p, q) == 1ULL) return 1;
    }
    return 0;
}

/* Lucas-Lehmer — an exact, deterministic primality *proof* specialised to the
 * Mersenne form M_p = 2^p - 1. A single chain of p-2 modular squarings
 * (s_0 = 4, s = s^2 - 2 mod M_p); M_p is prime iff the final residue is 0.
 * Dramatically cheaper than the 7-base bigint Miller-Rabin on the same n — one
 * modular square per step versus ~7 full modular exponentiations — and unlike
 * MR above 3.3e24 it is a proof, not a strong-probable-prime test. The mod step
 * uses the division-free Mersenne reduction (w_mersenne_mod).
 * Precondition: n = 2^p - 1 with exponent p (as returned by the detector). */
static int w_prime_test_lucas_lehmer(WValue n, uint64_t p) {
    if (p == 2) return 1;                  /* M_2 = 3 is prime */
    if (!w_prime_test_u64(p)) return 0;    /* composite p  =>  composite M_p */
    if (w_mersenne_has_u64_factor(p)) return 0;
    WValue zero = w_int(0), two = w_int(2);
    WValue s = w_int(4);
    for (uint64_t i = 0; i < p - 2; i++) {
        /* s in [0, n) so s^2 in [0, 2^(2p)); reduce, then subtract 2. The
         * residue can dip to -1/-2 (s = 1/0); one add floors it into [0, n). */
        WValue r = w_mersenne_square_mod(s, p);
        s = w_sub(r, two);
        if (w_lt(s, zero) == W_TRUE) s = w_add(s, n);
    }
    return w_eq(s, zero) == W_TRUE;
}

static WValue w_ic_bigint_prime_q(WValue r, WValue *a, int c) {
    (void)a; (void)c;
    if (w_lt(r, w_int(2)) == W_TRUE) return w_bool(0);   /* negatives, 0, 1 */
    WBigint *b = w_as_bigint(r);
    int32_t alen = b->size < 0 ? -b->size : b->size;
    if (alen <= 1) return w_bool(w_prime_test_u64((uint64_t)b->limbs[0]));  /* fits u64 */
    /* Mersenne fast path: 2^p-1 gets an exact Lucas-Lehmer proof instead of
     * the generic (and, at this scale, probabilistic) Miller-Rabin. */
    uint64_t p = w_mersenne_exponent(b->limbs, alen);
    if (p != 0) return w_bool(w_prime_test_lucas_lehmer(r, p));
    /* Proth fast path: N = k·2^s+1 (odd k < 2^s) gets an exact one-modexp
     * proof (Proth's theorem) instead of the 7-base MR + Lucas battery. */
    if (w_prime_proth_shape(b->limbs, alen)) {
        int pr = w_prime_test_proth(r);
        if (pr >= 0) return w_bool(pr);       /* −1: no witness ⇒ fall through */
    }
    return w_bool(w_prime_test_bigint(r));
}

/* Exported ccall boundary for the BigInt#prime? source shim
 * (core/numeric/big_int.w). The screen/Mersenne/Proth/BPSW policy above
 * stays in the runtime until source code can index limbs directly. */
WValue w_bigint_prime_q(WValue r) {
    return w_ic_bigint_prime_q(r, NULL, 0);
}

W_RT_INTERNAL int w_rt_prime_test_u64(uint64_t n) {
    return w_prime_test_u64(n);
}
W_RT_INTERNAL int w_rt_int_bit_length(WValue v) {
    return w_int_bit_length(v);
}
W_RT_INTERNAL void w_rt_mulmod_bnm1(uint64_t *out, const uint64_t *a, const uint64_t *b, int32_t n, uint64_t *scratch) {
    w_mulmod_bnm1(out, a, b, n, scratch);
}
W_RT_INTERNAL void w_rt_mersenne_ws_release_thread(void) {
    free(w_mersenne_ws);
    w_mersenne_ws = NULL;
    w_mersenne_ws_cap = 0;
}
