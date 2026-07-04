# qwen3.6/35b-a3b-nvfp4 architecture spec.
#
# Source: ~/.cache/huggingface/hub/models--mlx-community--Qwen3.6-35B-A3B-nvfp4/
#         snapshots/<sha>/config.json (text_config field).
#
# Architecture name in HuggingFace: Qwen3_5MoeForConditionalGeneration
# Model type:                       qwen3_5_moe
#
# This file is constants-only — no inference path exists yet.
# Forward pass requires:
#   - Mamba/SSM (linear_attention) kernel for 30/40 layers — selective_scan
#   - Dual MoE: shared expert + 256 routed experts, top-8 per token
#   - Standard full_attention for the remaining 10/40 layers
# See README.md for the port plan.

# Topology
HIDDEN_SIZE        = 2048
NUM_HIDDEN_LAYERS  = 40

# Attention (full_attention layers — 10 of 40, every 4th)
HEAD_DIM           = 256                # 2× Lightning's 128
NUM_ATTENTION_HEADS = 16
NUM_KEY_VALUE_HEADS = 2                 # extreme GQA
GQA_GROUP_SIZE      = 8                 # 16 / 2
ATTN_OUTPUT_GATE    = 1                 # NEW: per-head gate on attention output (vs Lightning)
FULL_ATTENTION_INTERVAL = 4             # every 4th layer is full_attention

# Mamba / linear_attention (30 of 40 layers)
LINEAR_CONV_KERNEL_DIM = 4
LINEAR_KEY_HEAD_DIM    = 128
LINEAR_NUM_KEY_HEADS   = 16
LINEAR_VALUE_HEAD_DIM  = 128
LINEAR_NUM_VALUE_HEADS = 32

# MoE
MOE_INTERMEDIATE_SIZE          = 512    # per routed expert
SHARED_EXPERT_INTERMEDIATE_SIZE = 512
NUM_EXPERTS                    = 256    # 2× qwen3-30b-a3b's 128
NUM_EXPERTS_PER_TOK            = 8      # same as qwen3

# Vocab + positional
VOCAB_SIZE              = 248320        # 1.6× Lightning's 151936
MAX_POSITION_EMBEDDINGS = 262144        # 256K context
ROPE_THETA              = 10000000      # 10M
TIE_WORD_EMBEDDINGS     = 0             # lm_head is independent

# Misc
RMS_NORM_EPS = ~0.000001
HIDDEN_ACT   = "silu"
