# Qwen3.8-Flash-Next (qwen4_exp) text architecture, from
# RadixArk/Qwen3.8-Flash-Next-NVFP4 config.json (text_config).
# 125B total / 6B active; 48 layers in a 3:1 GatedDeltaNet : full-attention
# pattern; 512-expert MoE with 10 active + 1 always-on shared expert;
# 4-branch hyper-connection residual stream; n-gram PLE injection at layer 2.

HIDDEN_SIZE = 2560
NUM_HIDDEN_LAYERS = 48
VOCAB_SIZE = 248320
FULL_ATTENTION_INTERVAL = 4

# Full attention (layers 3, 7, ..., 47).
HEAD_DIM = 256
NUM_ATTENTION_HEADS = 24
NUM_KEY_VALUE_HEADS = 2
PARTIAL_ROTARY_FACTOR = ~0.25
ROPE_THETA = ~10000000.0
MAX_POSITION_EMBEDDINGS = 262144
# q_proj emits Q and a per-head sigmoid output gate stacked ([12288, 2560]).
ATTN_OUTPUT_GATE = 1

# Qwen Sparse Attention (QSA) lightning indexer. Selection is top-2048
# micro-blocks; at sequence lengths <= INDEXER_BUDGET the selection is the
# whole context and dense SDPA is exact, so the indexer is a no-op for a
# decode benchmark capped below that.
INDEXER_N_HEADS = 4
INDEXER_HEAD_DIM = 128
INDEXER_KV_HEADS = 1
INDEXER_BUDGET = 2048
INDEXER_COMPRESS_RATIO = 4

# Linear attention / GatedDeltaNet (same geometry as Qwen3.8-27B).
LINEAR_CONV_KERNEL_DIM = 4
LINEAR_KEY_HEAD_DIM = 128
LINEAR_NUM_KEY_HEADS = 16
LINEAR_VALUE_HEAD_DIM = 128
LINEAR_NUM_VALUE_HEADS = 48

# MoE. Routed experts are the only NVFP4 tensors in the checkpoint; the
# shared expert, its sigmoid gate, and the router stay bf16.
NUM_EXPERTS = 512
NUM_EXPERTS_PER_TOK = 10
MOE_INTERMEDIATE_SIZE = 640
SHARED_EXPERT_INTERMEDIATE_SIZE = 640

# Hyper-connections: the residual stream is HC_COUNT parallel 2560-wide
# branches (10240 f32 total), read/written through low-rank dynamic mixers.
HC_COUNT = 4
HC_LOWRANK = 320

# N-gram / per-layer embedding (PLE), injected once at the START of decoder
# layer PLE_LAYER_ID (0-based; the config.json value [2] is ONE-indexed).
# 16 hash heads (8 bigram + 8 trigram) x 160 dims = 2560. Table:
# SPLIT_NGRAM_PARTS fp8 shards of [PLE_SHARD_ROWS, PLE_HEAD_DIM], one global
# scale. PLE conv is depthwise kernel-4 with DILATION 3 (taps t-9,t-6,t-3,t).
NGRAM_SIZE = 3
HEADS_PER_NGRAM = 8
PLE_N_HEADS = 16
PLE_HEAD_DIM = 160
PLE_EMBED_DIM = 2560
PLE_LAYER_ID = 1
PLE_CONV_KERNEL_SIZE = 4
PLE_CONV_DILATION = 3
SPLIT_NGRAM_PARTS = 128
PLE_SHARD_ROWS = 2500012
NGRAM_VOCAB_SIZE_BASE = 20000000

RMS_NORM_EPS = ~0.000001

MTP_NUM_HIDDEN_LAYERS = 1
MTP_SPECULATIVE_TOKENS = 1
