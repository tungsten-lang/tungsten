# Brain float 16
#
# float32:  1 sign | 8 exponent | 23 mantissa  (32 bits)
# bfloat16: 1 sign | 8 exponent |  7 mantissa  (16 bits)
# float16:  1 sign | 5 exponent | 10 mantissa  (16 bits)
# // C++ with compiler intrinsics (no standard type yet)
#
# #include <cuda_bf16.h>          // NVIDIA
# __nv_bfloat16 x = __float2bfloat16(3.14f);
#
# // Or Intel
# #include <immintrin.h>
# __bfloat16 x = _mm_cvtness_sbh(3.14f);
# ```
#
# ## The precision tradeoff in practice
#
# 7 mantissa bits gives you roughly 2–3 decimal digits of precision:
# ```
# float32:  3.14159265358979...
# bfloat16: 3.140625
# float16:  3.140625            (happens to match here, but differs elsewhere)
+ BF16 < Float
  -> .bits 16
  -> .mantissa_bits 7
  -> .exponent_bits 8
