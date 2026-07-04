# GGUF metadata value-type tags and ggml tensor-type tags.
#
# Spec reference: https://github.com/ggml-org/ggml/blob/master/docs/gguf.md
# We pin to GGUF v3.

in Tungsten:Llama

# -- gguf_metadata_value_type --

GGUF_TYPE_UINT8   = 0
GGUF_TYPE_INT8    = 1
GGUF_TYPE_UINT16  = 2
GGUF_TYPE_INT16   = 3
GGUF_TYPE_UINT32  = 4
GGUF_TYPE_INT32   = 5
GGUF_TYPE_FLOAT32 = 6
GGUF_TYPE_BOOL    = 7
GGUF_TYPE_STRING  = 8
GGUF_TYPE_ARRAY   = 9
GGUF_TYPE_UINT64  = 10
GGUF_TYPE_INT64   = 11
GGUF_TYPE_FLOAT64 = 12

-> gguf_type_name(t)
  case t
  when GGUF_TYPE_UINT8   then "u8"
  when GGUF_TYPE_INT8    then "i8"
  when GGUF_TYPE_UINT16  then "u16"
  when GGUF_TYPE_INT16   then "i16"
  when GGUF_TYPE_UINT32  then "u32"
  when GGUF_TYPE_INT32   then "i32"
  when GGUF_TYPE_FLOAT32 then "f32"
  when GGUF_TYPE_BOOL    then "bool"
  when GGUF_TYPE_STRING  then "string"
  when GGUF_TYPE_ARRAY   then "array"
  when GGUF_TYPE_UINT64  then "u64"
  when GGUF_TYPE_INT64   then "i64"
  when GGUF_TYPE_FLOAT64 then "f64"
  else
    "unknown([t])"

# -- ggml_type: on-disk tensor element encoding --
#
# Values mirror llama.cpp/ggml/include/ggml.h enum ggml_type.

GGML_TYPE_F32     = 0
GGML_TYPE_F16     = 1
GGML_TYPE_Q4_0    = 2
GGML_TYPE_Q4_1    = 3
GGML_TYPE_Q5_0    = 6
GGML_TYPE_Q5_1    = 7
GGML_TYPE_Q8_0    = 8
GGML_TYPE_Q8_1    = 9
GGML_TYPE_Q2_K    = 10
GGML_TYPE_Q3_K    = 11
GGML_TYPE_Q4_K    = 12
GGML_TYPE_Q5_K    = 13
GGML_TYPE_Q6_K    = 14
GGML_TYPE_Q8_K    = 15
GGML_TYPE_IQ2_XXS = 16
GGML_TYPE_IQ2_XS  = 17
GGML_TYPE_IQ3_XXS = 18
GGML_TYPE_IQ1_S   = 19
GGML_TYPE_IQ4_NL  = 20
GGML_TYPE_IQ3_S   = 21
GGML_TYPE_IQ2_S   = 22
GGML_TYPE_IQ4_XS  = 23
GGML_TYPE_I8      = 24
GGML_TYPE_I16     = 25
GGML_TYPE_I32     = 26
GGML_TYPE_I64     = 27
GGML_TYPE_F64     = 28
GGML_TYPE_IQ1_M   = 29
GGML_TYPE_BF16    = 30
GGML_TYPE_TQ1_0   = 34
GGML_TYPE_TQ2_0   = 35
GGML_TYPE_MXFP4   = 39

-> ggml_type_name(t)
  case t
  when GGML_TYPE_F32     then "F32"
  when GGML_TYPE_F16     then "F16"
  when GGML_TYPE_Q4_0    then "Q4_0"
  when GGML_TYPE_Q4_1    then "Q4_1"
  when GGML_TYPE_Q5_0    then "Q5_0"
  when GGML_TYPE_Q5_1    then "Q5_1"
  when GGML_TYPE_Q8_0    then "Q8_0"
  when GGML_TYPE_Q8_1    then "Q8_1"
  when GGML_TYPE_Q2_K    then "Q2_K"
  when GGML_TYPE_Q3_K    then "Q3_K"
  when GGML_TYPE_Q4_K    then "Q4_K"
  when GGML_TYPE_Q5_K    then "Q5_K"
  when GGML_TYPE_Q6_K    then "Q6_K"
  when GGML_TYPE_Q8_K    then "Q8_K"
  when GGML_TYPE_I8      then "I8"
  when GGML_TYPE_I16     then "I16"
  when GGML_TYPE_I32     then "I32"
  when GGML_TYPE_I64     then "I64"
  when GGML_TYPE_F64     then "F64"
  when GGML_TYPE_BF16    then "BF16"
  when GGML_TYPE_MXFP4   then "MXFP4"
  else
    "TYPE_[t]"

# Bytes per block for the quant formats we currently care about.
# A "block" holds block_size elements.
#
# Q8_0:  32 int8 quants + 1 f16 scale = 34 bytes per 32 elements
# F32:   4 bytes per element (trivial block of size 1)
# F16:   2 bytes per element
# MXFP4: 32 four-bit quants (16 bytes) + 1 u8 scale = 17 bytes per 32 elements

-> ggml_block_size(t)
  case t
  when GGML_TYPE_F32   then 1
  when GGML_TYPE_F16   then 1
  when GGML_TYPE_BF16  then 1
  when GGML_TYPE_Q8_0  then 32
  when GGML_TYPE_MXFP4 then 32
  when GGML_TYPE_Q4_0  then 32
  when GGML_TYPE_Q4_1  then 32
  when GGML_TYPE_Q5_0  then 32
  when GGML_TYPE_Q5_1  then 32
  when GGML_TYPE_Q6_K  then 256
  when GGML_TYPE_Q4_K  then 256
  when GGML_TYPE_Q5_K  then 256
  when GGML_TYPE_Q3_K  then 256
  when GGML_TYPE_Q2_K  then 256
  when GGML_TYPE_I8    then 1
  when GGML_TYPE_I16   then 1
  when GGML_TYPE_I32   then 1
  when GGML_TYPE_I64   then 1
  when GGML_TYPE_F64   then 1
  else
    0

-> ggml_type_size(t)
  case t
  when GGML_TYPE_F32   then 4
  when GGML_TYPE_F16   then 2
  when GGML_TYPE_BF16  then 2
  when GGML_TYPE_Q8_0  then 34
  when GGML_TYPE_MXFP4 then 17
  when GGML_TYPE_Q4_0  then 18
  when GGML_TYPE_Q4_1  then 20
  when GGML_TYPE_Q5_0  then 22
  when GGML_TYPE_Q5_1  then 24
  when GGML_TYPE_Q6_K  then 210
  when GGML_TYPE_Q4_K  then 144
  when GGML_TYPE_Q5_K  then 176
  when GGML_TYPE_Q3_K  then 110
  when GGML_TYPE_Q2_K  then 84
  when GGML_TYPE_I8    then 1
  when GGML_TYPE_I16   then 2
  when GGML_TYPE_I32   then 4
  when GGML_TYPE_I64   then 8
  when GGML_TYPE_F64   then 8
  else
    0
