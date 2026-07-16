#include "tc.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static TcAstValue *ast_get(TcAstValue hash, const char *key) {
  if (hash.kind != TC_AST_HASH || !hash.as.hash) return NULL;
  for (size_t i = 0; i < hash.as.hash->count; i++) {
    if (strcmp(hash.as.hash->items[i].key, key) == 0) return &hash.as.hash->items[i].value;
  }
  return NULL;
}

static int ast_text_eq(TcAstValue value, const char *text) {
  return (value.kind == TC_AST_STRING || value.kind == TC_AST_SYMBOL) &&
         strlen(text) == value.as.string.len &&
         memcmp(value.as.string.bytes, text, value.as.string.len) == 0;
}

static int ast_node_is(TcAstValue value, const char *node) {
  TcAstValue *node_value = ast_get(value, "node");
  return node_value && ast_text_eq(*node_value, node);
}

static int emit_const(TcChunk *chunk, TcValue value, TcError *err) {
  int id = tc_chunk_add_const(chunk, value, err);
  if (id < 0) return 0;
  return tc_emit_op_u32(chunk, TC_OP_CONST, (uint32_t)id, err);
}

static int emit_jump(TcChunk *chunk, uint8_t op, size_t *operand_pos, TcError *err) {
  if (!tc_emit_op(chunk, op, err)) return 0;
  *operand_pos = chunk->count;
  return tc_emit_u32(chunk, 0, err);
}

static void patch_jump(TcChunk *chunk, size_t operand_pos, size_t target) {
  chunk->code[operand_pos] = (uint8_t)(target & 0xFF);
  chunk->code[operand_pos + 1] = (uint8_t)((target >> 8) & 0xFF);
  chunk->code[operand_pos + 2] = (uint8_t)((target >> 16) & 0xFF);
  chunk->code[operand_pos + 3] = (uint8_t)((target >> 24) & 0xFF);
}

// Loop context stack: tracks the continue target and pending break offsets
// for the innermost loop, so `next`/`break` can emit jumps. The stack is
// file-scoped because the compiler doesn't thread a context object — every
// compile_* function only sees TcChunk*.
typedef struct LoopCtx {
  size_t continue_target;        // loop_start: where `next` jumps
  size_t break_offsets[32];      // pending break jump operand positions to patch
  size_t break_count;
} LoopCtx;

static LoopCtx loop_stack[16];
static int loop_top = -1;

static int loop_push(size_t continue_target) {
  if (loop_top + 1 >= (int)(sizeof(loop_stack) / sizeof(loop_stack[0]))) return 0;
  loop_top++;
  loop_stack[loop_top].continue_target = continue_target;
  loop_stack[loop_top].break_count = 0;
  return 1;
}

static void loop_pop_and_patch(TcChunk *chunk, size_t break_target) {
  if (loop_top < 0) return;
  LoopCtx *ctx = &loop_stack[loop_top];
  for (size_t i = 0; i < ctx->break_count; i++) {
    patch_jump(chunk, ctx->break_offsets[i], break_target);
  }
  loop_top--;
}

static int emit_nil(TcChunk *chunk, TcError *err) {
  return emit_const(chunk, tc_box_nil(), err);
}

static int emit_call_op(TcChunk *chunk, const char *name, size_t name_len, size_t argc, int has_receiver, TcError *err) {
  // Call name is emitted as TC_VAL_SYMBOL so it routes through the
  // global intern pool — every call site for the same method name
  // shares one canonical bytes pointer. The L_CALL builtin matchers
  // use ptr-equality against pre-interned static handles, replacing
  // the memcmp chain.
  char *name_copy = tc_heap_string_alloc(name_len, 0, err);
  if (!name_copy) return 0;
  memcpy(name_copy, name, name_len);
  int name_id = tc_chunk_add_const(
      chunk, tc_box_symbol_bytes(name_copy, name_len, 1), err);
  if (name_id < 0) return 0;
  return tc_emit_op(chunk, TC_OP_CALL, err) &&
         tc_emit_u32(chunk, (uint32_t)name_id, err) &&
         tc_emit_u32(chunk, (uint32_t)argc, err) &&
         tc_emit_u32(chunk, (uint32_t)has_receiver, err);
}

static char *copy_unquoted_string(TcAstValue value, size_t *len_out, TcError *err) {
  if (value.kind != TC_AST_STRING) {
    tc_error_set(err, "expected AST string");
    return NULL;
  }
  const char *bytes = value.as.string.bytes;
  size_t len = value.as.string.len;
  int quoted = len >= 2 &&
               ((bytes[0] == '"' && bytes[len - 1] == '"') || (bytes[0] == '\'' && bytes[len - 1] == '\''));
  if (!quoted) {
    char *copy = tc_heap_string_alloc(len, 0, err);
    if (!copy) return NULL;
    if (len > 0) memcpy(copy, bytes, len);
    *len_out = len;
    return copy;
  }
  if (len >= 2 && ((bytes[0] == '"' && bytes[len - 1] == '"') || (bytes[0] == '\'' && bytes[len - 1] == '\''))) {
    bytes++;
    len -= 2;
  }
  // Worst-case length is `len` bytes (no escape expansion grows). Allocate
  // upper-bound, write actual bytes, and store the real length on the
  // header so consumers see the correct value. The trailing slop in the
  // flex array is harmless.
  char *copy = tc_heap_string_alloc(len, 0, err);
  if (!copy) return NULL;
  size_t out_len = 0;
  for (size_t i = 0; i < len; i++) {
    if (bytes[i] == '\\' && i + 1 < len) {
      i++;
      switch (bytes[i]) {
        case 'n': copy[out_len++] = '\n'; break;
        case 'r': copy[out_len++] = '\r'; break;
        case 't': copy[out_len++] = '\t'; break;
        case '0': copy[out_len++] = '\0'; break;
        case '"': copy[out_len++] = '"'; break;
        case '\'': copy[out_len++] = '\''; break;
        case '\\': copy[out_len++] = '\\'; break;
        default:
          copy[out_len++] = bytes[i];
          break;
      }
    } else {
      copy[out_len++] = bytes[i];
    }
  }
  copy[out_len] = '\0';
  // The unescape pass may have produced fewer bytes than the over-
  // allocated flex array. Patch the TcHeapString header's len so
  // tc_str_len() reports the actual count.
  tc_heap_string_header(copy)->len = out_len;
  *len_out = out_len;
  return copy;
}

static int compile_expr(TcAstValue node, TcChunk *chunk, TcError *err);
static int compile_body_value(TcAstValue body, TcChunk *chunk, TcError *err);
static int compile_body_statements(TcAstValue body, TcChunk *chunk, TcError *err);
static int compile_function_def(TcAstValue node, const char *prefix, size_t prefix_len, TcChunk *chunk, TcError *err);

// Emit a TC_VAL_SYMBOL const for `name` and return its const id, or -1
// on allocation failure. The bytes go into the const pool (interned via
// tc_chunk_add_const → tc_intern), so the runtime reads the canonical
// pointer when L_IVAR_GET / L_IVAR_SET indexes the consts.
static int emit_symbol_const(TcChunk *chunk, const char *bytes, size_t len, TcError *err) {
  char *copy = tc_heap_string_alloc(len, 0, err);
  if (!copy) return -1;
  memcpy(copy, bytes, len);
  return tc_chunk_add_const(chunk, tc_box_symbol_bytes(copy, len, 1), err);
}

static int compile_var(TcAstValue node, TcChunk *chunk, TcError *err) {
  TcAstValue *name = ast_get(node, "name");
  if (!name || name->kind != TC_AST_STRING) {
    tc_error_set(err, "variable node missing name");
    return 0;
  }
  // Instance variable: read self->fields[name]. Strip the leading `@` so
  // the field key matches what the user wrote in the source.
  if (ast_node_is(node, "ivar")) {
    const char *bytes = name->as.string.bytes;
    size_t len = name->as.string.len;
    if (len > 0 && bytes[0] == '@') { bytes++; len--; }
    int cid = emit_symbol_const(chunk, bytes, len, err);
    if (cid < 0) return 0;
    return tc_emit_op_u32(chunk, TC_OP_IVAR_GET, (uint32_t)cid, err);
  }
  // Class variable: keep the verbatim `@@name` as the global key.
  if (ast_node_is(node, "cvar")) {
    int cid = emit_symbol_const(chunk, name->as.string.bytes, name->as.string.len, err);
    if (cid < 0) return 0;
    return tc_emit_op_u32(chunk, TC_OP_CVAR_GET, (uint32_t)cid, err);
  }
  static const char *zero_arg_calls[] = {
      "clock", "resolve_runtime_dir", "runtime_event_source", "extra_c_includes",
      "zstd_cflags", "zstd_ldflags", "onig_cflags", "onig_ldflags"};
  for (size_t i = 0; i < sizeof(zero_arg_calls) / sizeof(zero_arg_calls[0]); i++) {
    size_t len = strlen(zero_arg_calls[i]);
    if (name->as.string.len == len && memcmp(name->as.string.bytes, zero_arg_calls[i], len) == 0) {
      return emit_call_op(chunk, zero_arg_calls[i], len, 0, 0, err);
    }
  }
  int slot = tc_chunk_local(chunk, name->as.string.bytes, name->as.string.len, err);
  if (slot < 0) return 0;
  return tc_emit_op_u32(chunk, TC_OP_LOAD_LOCAL, (uint32_t)slot, err);
}

static int compile_parg(TcAstValue node, TcChunk *chunk, TcError *err) {
  TcAstValue *index = ast_get(node, "index");
  if (!index || index->kind != TC_AST_INT || index->as.integer <= 0) {
    tc_error_set(err, "invalid positional argument AST");
    return 0;
  }
  char name[32];
  int len = snprintf(name, sizeof(name), "__arg%lld", (long long)index->as.integer);
  if (len <= 0 || (size_t)len >= sizeof(name)) {
    tc_error_set(err, "positional argument index too large");
    return 0;
  }
  int slot = tc_chunk_local(chunk, name, (size_t)len, err);
  if (slot < 0) return 0;
  return tc_emit_op_u32(chunk, TC_OP_LOAD_LOCAL, (uint32_t)slot, err);
}

static uint8_t binary_opcode(TcAstValue op) {
  if (ast_text_eq(op, "PLUS")) return TC_OP_ADD;
  if (ast_text_eq(op, "MINUS")) return TC_OP_SUB;
  if (ast_text_eq(op, "STAR")) return TC_OP_MUL;
  if (ast_text_eq(op, "SLASH")) return TC_OP_DIV;
  if (ast_text_eq(op, "EQ")) return TC_OP_EQ;
  if (ast_text_eq(op, "NEQ")) return TC_OP_NEQ;
  if (ast_text_eq(op, "LT")) return TC_OP_LT;
  if (ast_text_eq(op, "LTE")) return TC_OP_LTE;
  if (ast_text_eq(op, "GT")) return TC_OP_GT;
  if (ast_text_eq(op, "GTE")) return TC_OP_GTE;
  if (ast_text_eq(op, "PERCENT")) return TC_OP_MOD;
  if (ast_text_eq(op, "AMPERSAND") || ast_text_eq(op, "DOT_AMP")) return TC_OP_BIT_AND;
  if (ast_text_eq(op, "PIPE") || ast_text_eq(op, "DOT_PIPE")) return TC_OP_BIT_OR;
  if (ast_text_eq(op, "CARET") || ast_text_eq(op, "DOT_CARET")) return TC_OP_BIT_XOR;
  if (ast_text_eq(op, "POW")) return TC_OP_POW;
  if (ast_text_eq(op, "DOT_PLUS")) return TC_OP_ADD;
  if (ast_text_eq(op, "DOT_MINUS")) return TC_OP_SUB;
  if (ast_text_eq(op, "DOT_STAR") || ast_text_eq(op, "DOT_PRODUCT")) return TC_OP_MUL;
  if (ast_text_eq(op, "DOT_SLASH")) return TC_OP_DIV;
  return 0;
}

static int compile_binary(TcAstValue node, TcChunk *chunk, TcError *err) {
  TcAstValue *left = ast_get(node, "left");
  TcAstValue *right = ast_get(node, "right");
  TcAstValue *op = ast_get(node, "op");
  if (left && right && op && (ast_text_eq(*op, "LSHIFT") || ast_text_eq(*op, "RSHIFT") ||
                              ast_text_eq(*op, "DOT_LSHIFT") || ast_text_eq(*op, "DOT_RSHIFT"))) {
    const char *name = (ast_text_eq(*op, "RSHIFT") || ast_text_eq(*op, "DOT_RSHIFT")) ? ">>" : "<<";
    // Was: if left is a var and op is LSHIFT, store the result back into the
    // var (treating `var << x` as `var = var << x`). That matches StringBuffer
    // append semantics for `globals_out << "..."`, but it's WRONG for integer
    // shifts — `pos << 4` got rewritten to `pos = pos << 4`, mutating pos. The
    // runtime's `<<` operator on a buffer mutates in-place and returns the
    // buffer, so the STORE_LOCAL was redundant for buffers and destructive
    // for integers. Drop it; both cases now work like a normal binary op.
    return compile_expr(*left, chunk, err) &&
           compile_expr(*right, chunk, err) &&
           emit_call_op(chunk, name, 2, 1, 1, err);
  }
  if (left && right && op && (ast_text_eq(*op, "AND") || ast_text_eq(*op, "OR"))) {
    size_t first_false = 0;
    size_t end_jump = 0;
    if (!compile_expr(*left, chunk, err) ||
        !emit_jump(chunk, TC_OP_JUMP_IF_FALSE, &first_false, err)) {
      return 0;
    }
    if (ast_text_eq(*op, "OR")) {
      size_t first_true_jump = 0;
      size_t second_true_jump = 0;
      if (!emit_const(chunk, tc_box_bool(1), err) ||
          !emit_jump(chunk, TC_OP_JUMP, &first_true_jump, err)) {
        return 0;
      }
      patch_jump(chunk, first_false, chunk->count);
      size_t second_false = 0;
      if (!compile_expr(*right, chunk, err) ||
          !emit_jump(chunk, TC_OP_JUMP_IF_FALSE, &second_false, err) ||
          !emit_const(chunk, tc_box_bool(1), err) ||
          !emit_jump(chunk, TC_OP_JUMP, &second_true_jump, err)) {
        return 0;
      }
      patch_jump(chunk, second_false, chunk->count);
      if (!emit_const(chunk, tc_box_bool(0), err)) return 0;
      patch_jump(chunk, first_true_jump, chunk->count);
      patch_jump(chunk, second_true_jump, chunk->count);
      return 1;
    }

    size_t second_false = 0;
    if (!compile_expr(*right, chunk, err) ||
        !emit_jump(chunk, TC_OP_JUMP_IF_FALSE, &second_false, err) ||
        !emit_const(chunk, tc_box_bool(1), err) ||
        !emit_jump(chunk, TC_OP_JUMP, &end_jump, err)) {
      return 0;
    }
    patch_jump(chunk, first_false, chunk->count);
    patch_jump(chunk, second_false, chunk->count);
    if (!emit_const(chunk, tc_box_bool(0), err)) return 0;
    patch_jump(chunk, end_jump, chunk->count);
    return 1;
  }
  uint8_t code = op ? binary_opcode(*op) : 0;
  if (!left || !right || code == 0) {
    if (op && (op->kind == TC_AST_STRING || op->kind == TC_AST_SYMBOL)) {
      tc_error_set(err, "unsupported binary expression: %.*s", (int)op->as.string.len, op->as.string.bytes);
    } else {
      tc_error_set(err, "unsupported binary expression");
    }
    return 0;
  }
  return compile_expr(*left, chunk, err) &&
         compile_expr(*right, chunk, err) &&
         tc_emit_op(chunk, code, err);
}

static int compile_assign(TcAstValue node, TcChunk *chunk, TcError *err) {
  TcAstValue *target = ast_get(node, "target");
  TcAstValue *value = ast_get(node, "value");
  if (!target || !value) {
    tc_error_set(err, "assignment missing target/value");
    return 0;
  }
  if (ast_node_is(*target, "call")) {
    /* `obj.attr = value` parses as :assign with target = a zero-arg
     * :call (receiver=obj, name=attr). Dispatch as a method call
     * `obj.attr=(value)` — receiver pushed, value pushed, then a
     * TC_OP_CALL on the "attr=" symbol with argc=1. Previously this
     * branch silently dropped the RHS, leaving `f.x = 42` as a
     * no-op (the C VM stage 0 limit referenced in the Stage D-2
     * notes). The L_CALL handler in vm_call_body.inc already does
     * the method lookup; both regular class setters and the
     * W_PACKED_NODE method_missing fallback are reached this way. */
    TcAstValue *t_recv = ast_get(*target, "receiver");
    TcAstValue *t_name = ast_get(*target, "name");
    TcAstValue *t_args = ast_get(*target, "args");
    int clean_setter =
        t_recv && t_recv->kind != TC_AST_NIL &&
        t_name && t_name->kind == TC_AST_STRING &&
        t_args && t_args->kind == TC_AST_ARRAY && t_args->as.array->count == 0;
    if (clean_setter) {
      if (!compile_expr(*t_recv, chunk, err)) return 0;
      if (!compile_expr(*value, chunk, err))  return 0;
      size_t setter_len = t_name->as.string.len + 1;
      char *setter = (char *)malloc(setter_len + 1);
      if (!setter) {
        tc_error_set(err, "setter name allocation failed");
        return 0;
      }
      memcpy(setter, t_name->as.string.bytes, t_name->as.string.len);
      setter[t_name->as.string.len] = '=';
      setter[setter_len] = '\0';
      int ok = emit_call_op(chunk, setter, setter_len, 1, 1, err);
      free(setter);
      return ok;
    }
    /* Unusual call-target shape (e.g. parenthesised expression or
     * something with args). Preserve the pre-existing no-op
     * behaviour: evaluate the RHS for side effects, discard. */
    return compile_expr(*value, chunk, err);
  }
  if (!ast_node_is(*target, "var") && !ast_node_is(*target, "ivar") && !ast_node_is(*target, "cvar")) {
    tc_error_set(err, "unsupported assignment target");
    return 0;
  }
  TcAstValue *name = ast_get(*target, "name");
  if (!name || name->kind != TC_AST_STRING) {
    tc_error_set(err, "assignment target missing name");
    return 0;
  }
  if (ast_node_is(*target, "ivar")) {
    const char *bytes = name->as.string.bytes;
    size_t len = name->as.string.len;
    if (len > 0 && bytes[0] == '@') { bytes++; len--; }
    int cid = emit_symbol_const(chunk, bytes, len, err);
    if (cid < 0) return 0;
    return compile_expr(*value, chunk, err) &&
           tc_emit_op_u32(chunk, TC_OP_IVAR_SET, (uint32_t)cid, err);
  }
  if (ast_node_is(*target, "cvar")) {
    int cid = emit_symbol_const(chunk, name->as.string.bytes, name->as.string.len, err);
    if (cid < 0) return 0;
    return compile_expr(*value, chunk, err) &&
           tc_emit_op_u32(chunk, TC_OP_CVAR_SET, (uint32_t)cid, err);
  }
  int slot = tc_chunk_local(chunk, name->as.string.bytes, name->as.string.len, err);
  if (slot < 0) return 0;
  return compile_expr(*value, chunk, err) &&
         tc_emit_op_u32(chunk, TC_OP_STORE_LOCAL, (uint32_t)slot, err);
}

static int compile_puts(TcAstValue node, TcChunk *chunk, TcError *err) {
  TcAstValue *value = ast_get(node, "value");
  if (!value || value->kind == TC_AST_NIL) {
    if (!emit_nil(chunk, err)) return 0;
  } else if (!compile_expr(*value, chunk, err)) {
    return 0;
  }
  return tc_emit_op(chunk, TC_OP_PRINT, err);
}

// Short-circuit logical OR / AND for `{node: "or" | "and", left, right}`.
// parse_ast.c emits these now (was previously binary_op + op="OR"/"AND",
// which compile_binary's AND/OR branch still handles for the rare
// path where some upstream builder emits the old form). The two
// shapes produce the same bytecode pattern.
static int compile_or_and(TcAstValue node, TcChunk *chunk, int is_or, TcError *err) {
  TcAstValue *left = ast_get(node, "left");
  TcAstValue *right = ast_get(node, "right");
  if (!left || !right) {
    tc_error_set(err, "logical %s missing left/right", is_or ? "or" : "and");
    return 0;
  }
  // Common pattern: evaluate left, branch on its truthiness, then for
  // OR jump-on-true and continue with right; for AND jump-on-false.
  // The result on the stack is the boolean coerced via a final emit;
  // matches compile_binary's AND/OR branch semantics.
  size_t first_false = 0;
  if (!compile_expr(*left, chunk, err) ||
      !emit_jump(chunk, TC_OP_JUMP_IF_FALSE, &first_false, err)) {
    return 0;
  }
  if (is_or) {
    size_t first_true_jump = 0;
    size_t second_true_jump = 0;
    size_t second_false = 0;
    if (!emit_const(chunk, tc_box_bool(1), err) ||
        !emit_jump(chunk, TC_OP_JUMP, &first_true_jump, err)) {
      return 0;
    }
    patch_jump(chunk, first_false, chunk->count);
    if (!compile_expr(*right, chunk, err) ||
        !emit_jump(chunk, TC_OP_JUMP_IF_FALSE, &second_false, err) ||
        !emit_const(chunk, tc_box_bool(1), err) ||
        !emit_jump(chunk, TC_OP_JUMP, &second_true_jump, err)) {
      return 0;
    }
    patch_jump(chunk, second_false, chunk->count);
    if (!emit_const(chunk, tc_box_bool(0), err)) return 0;
    patch_jump(chunk, first_true_jump, chunk->count);
    patch_jump(chunk, second_true_jump, chunk->count);
    return 1;
  }
  // AND: left was truthy → result is right's truthiness; left falsy → false.
  size_t second_false = 0;
  size_t end_jump = 0;
  if (!compile_expr(*right, chunk, err) ||
      !emit_jump(chunk, TC_OP_JUMP_IF_FALSE, &second_false, err) ||
      !emit_const(chunk, tc_box_bool(1), err) ||
      !emit_jump(chunk, TC_OP_JUMP, &end_jump, err)) {
    return 0;
  }
  patch_jump(chunk, first_false, chunk->count);
  patch_jump(chunk, second_false, chunk->count);
  if (!emit_const(chunk, tc_box_bool(0), err)) return 0;
  patch_jump(chunk, end_jump, chunk->count);
  return 1;
}

static int compile_not(TcAstValue node, TcChunk *chunk, TcError *err) {
  TcAstValue *operand = ast_get(node, "operand");
  if (!operand) {
    tc_error_set(err, "not node missing operand");
    return 0;
  }
  size_t false_jump = 0;
  size_t end_jump = 0;
  if (!compile_expr(*operand, chunk, err) ||
      !emit_jump(chunk, TC_OP_JUMP_IF_FALSE, &false_jump, err) ||
      !emit_const(chunk, tc_box_bool(0), err) ||
      !emit_jump(chunk, TC_OP_JUMP, &end_jump, err)) {
    return 0;
  }
  patch_jump(chunk, false_jump, chunk->count);
  if (!emit_const(chunk, tc_box_bool(1), err)) return 0;
  patch_jump(chunk, end_jump, chunk->count);
  return 1;
}

static int compile_if(TcAstValue node, TcChunk *chunk, TcError *err) {
  TcAstValue *condition = ast_get(node, "condition");
  TcAstValue *then_body = ast_get(node, "then_body");
  TcAstValue *elsif_clauses = ast_get(node, "elsif_clauses");
  TcAstValue *else_body = ast_get(node, "else_body");
  if (!condition || !then_body) {
    tc_error_set(err, "if node missing condition/body");
    return 0;
  }

  size_t false_jump = 0;
  size_t end_count = 0;
  size_t end_cap = 4;
  size_t *end_jumps = (size_t *)calloc(end_cap, sizeof(size_t));
  if (!end_jumps) {
    tc_error_set(err, "if jump allocation failed");
    return 0;
  }
  if (!compile_expr(*condition, chunk, err) ||
      !emit_jump(chunk, TC_OP_JUMP_IF_FALSE, &false_jump, err) ||
      !compile_body_value(*then_body, chunk, err)) {
    free(end_jumps);
    return 0;
  }
  if (!emit_jump(chunk, TC_OP_JUMP, &end_jumps[end_count++], err)) {
    free(end_jumps);
    return 0;
  }
  patch_jump(chunk, false_jump, chunk->count);
  if (elsif_clauses && elsif_clauses->kind == TC_AST_ARRAY) {
    for (size_t i = 0; i < elsif_clauses->as.array->count; i++) {
      TcAstValue pair = elsif_clauses->as.array->items[i];
      if (pair.kind != TC_AST_ARRAY || pair.as.array->count < 2) continue;
      size_t next_jump = 0;
      if (!compile_expr(pair.as.array->items[0], chunk, err) ||
          !emit_jump(chunk, TC_OP_JUMP_IF_FALSE, &next_jump, err) ||
          !compile_body_value(pair.as.array->items[1], chunk, err)) {
        free(end_jumps);
        return 0;
      }
      if (end_count == end_cap) {
        end_cap *= 2;
        size_t *next = (size_t *)realloc(end_jumps, end_cap * sizeof(size_t));
        if (!next) {
          free(end_jumps);
          tc_error_set(err, "if jump growth failed");
          return 0;
        }
        end_jumps = next;
      }
      if (!emit_jump(chunk, TC_OP_JUMP, &end_jumps[end_count++], err)) {
        free(end_jumps);
        return 0;
      }
      patch_jump(chunk, next_jump, chunk->count);
    }
  }
  if (else_body && else_body->kind != TC_AST_NIL) {
    if (!compile_body_value(*else_body, chunk, err)) {
      free(end_jumps);
      return 0;
    }
  } else if (!emit_nil(chunk, err)) {
    free(end_jumps);
    return 0;
  }
  for (size_t i = 0; i < end_count; i++) patch_jump(chunk, end_jumps[i], chunk->count);
  free(end_jumps);
  return 1;
}

static int compile_while(TcAstValue node, TcChunk *chunk, TcError *err) {
  TcAstValue *condition = ast_get(node, "condition");
  TcAstValue *body = ast_get(node, "body");
  if (!condition || !body) {
    tc_error_set(err, "while node missing condition/body");
    return 0;
  }
  size_t loop_start = chunk->count;
  size_t exit_jump = 0;
  if (!loop_push(loop_start)) {
    tc_error_set(err, "loop nesting too deep");
    return 0;
  }
  if (!compile_expr(*condition, chunk, err) ||
      !emit_jump(chunk, TC_OP_JUMP_IF_FALSE, &exit_jump, err) ||
      !compile_body_statements(*body, chunk, err) ||
      !tc_emit_op_u32(chunk, TC_OP_JUMP, (uint32_t)loop_start, err)) {
    loop_pop_and_patch(chunk, chunk->count);
    return 0;
  }
  size_t break_target = chunk->count;
  patch_jump(chunk, exit_jump, break_target);
  loop_pop_and_patch(chunk, break_target);
  return emit_nil(chunk, err);
}

static int target_name_matches(TcAstValue name) {
  if (name.kind != TC_AST_STRING && name.kind != TC_AST_SYMBOL) return 0;
#if defined(__APPLE__)
  const char *os = "macos";
#elif defined(__linux__)
  const char *os = "linux";
#elif defined(__FreeBSD__)
  const char *os = "freebsd";
#else
  const char *os = "unknown";
#endif
#if defined(__aarch64__) || defined(__arm64__)
  const char *arch = "arm64";
#elif defined(__x86_64__) || defined(_M_X64)
  const char *arch = "x86_64";
#else
  const char *arch = "unknown";
#endif
  const char *bytes = name.as.string.bytes;
  size_t len = name.as.string.len;
  size_t os_len = strlen(os);
  size_t arch_len = strlen(arch);
  if (len == os_len && memcmp(bytes, os, os_len) == 0) return 1;
  if (len == arch_len && memcmp(bytes, arch, arch_len) == 0) return 1;
  if (len == 7 && memcmp(bytes, "aarch64", 7) == 0 && strcmp(arch, "arm64") == 0) return 1;
  if (len == 5 && memcmp(bytes, "amd64", 5) == 0 && strcmp(arch, "x86_64") == 0) return 1;
  return 0;
}

static int target_predicate_matches(TcAstValue predicate) {
  if (ast_node_is(predicate, "target_designator")) {
    TcAstValue *name = ast_get(predicate, "name");
    return name && target_name_matches(*name);
  }
  if (ast_node_is(predicate, "target_and")) {
    TcAstValue *left = ast_get(predicate, "left");
    TcAstValue *right = ast_get(predicate, "right");
    return left && right && target_predicate_matches(*left) && target_predicate_matches(*right);
  }
  if (ast_node_is(predicate, "target_or")) {
    TcAstValue *left = ast_get(predicate, "left");
    TcAstValue *right = ast_get(predicate, "right");
    return left && right && (target_predicate_matches(*left) || target_predicate_matches(*right));
  }
  if (ast_node_is(predicate, "target_not")) {
    TcAstValue *expression = ast_get(predicate, "expression");
    return expression && !target_predicate_matches(*expression);
  }
  return 0;
}

static int compile_on_guard(TcAstValue node, TcChunk *chunk, TcError *err) {
  TcAstValue *predicate = ast_get(node, "predicate");
  TcAstValue *body = ast_get(node, "body");
  if (!predicate || !body) {
    tc_error_set(err, "on_guard node missing predicate/body");
    return 0;
  }
  if (target_predicate_matches(*predicate)) return compile_body_value(*body, chunk, err);
  return emit_nil(chunk, err);
}

static int compile_in_test(TcAstValue node, TcChunk *chunk, TcError *err) {
  TcAstValue *lhs = ast_get(node, "lhs");
  TcAstValue *elements = ast_get(node, "elements");
  if (!lhs || !elements || elements->kind != TC_AST_ARRAY) {
    tc_error_set(err, "malformed in_test");
    return 0;
  }
  size_t count = elements->as.array->count;
  size_t *end_jumps = count ? (size_t *)calloc(count, sizeof(size_t)) : NULL;
  if (count && !end_jumps) {
    tc_error_set(err, "in_test jump allocation failed");
    return 0;
  }
  for (size_t i = 0; i < count; i++) {
    size_t next_jump = 0;
    if (!compile_expr(*lhs, chunk, err) ||
        !compile_expr(elements->as.array->items[i], chunk, err) ||
        !tc_emit_op(chunk, TC_OP_EQ, err) ||
        !emit_jump(chunk, TC_OP_JUMP_IF_FALSE, &next_jump, err) ||
        !emit_const(chunk, tc_box_bool(1), err) ||
        !emit_jump(chunk, TC_OP_JUMP, &end_jumps[i], err)) {
      free(end_jumps);
      return 0;
    }
    patch_jump(chunk, next_jump, chunk->count);
  }
  if (!emit_const(chunk, tc_box_bool(0), err)) {
    free(end_jumps);
    return 0;
  }
  for (size_t i = 0; i < count; i++) patch_jump(chunk, end_jumps[i], chunk->count);
  free(end_jumps);
  return 1;
}

// Returns 1 if `pattern` is a `:symbol` AST node (the case-arm shape we
// can route through the CASE_SYM_LINEAR fast path). The pattern's
// `value` field carries the sym's UTF-8 bytes; the caller will intern
// those bytes to get a canonical pointer for the table key.
static int is_symbol_literal(TcAstValue pattern) {
  if (!ast_node_is(pattern, "symbol")) return 0;
  TcAstValue *value = ast_get(pattern, "value");
  return value && value->kind == TC_AST_STRING;
}

// True if every arm pattern + every when condition is a sym literal.
// One non-sym arm forces the whole case onto the slow per-arm chain
// (mixing a hash-keyed jump with EQ_CONST_BR per arm would be ugly
// and is rare enough to not be worth the complexity).
static int case_value_is_sym_only(TcAstValue *arms, TcAstValue *whens) {
  size_t total = 0;
  if (arms && arms->kind == TC_AST_ARRAY) {
    for (size_t i = 0; i < arms->as.array->count; i++) {
      TcAstValue arm = arms->as.array->items[i];
      TcAstValue *pattern = ast_get(arm, "pattern");
      if (!pattern || !is_symbol_literal(*pattern)) return 0;
      total++;
    }
  }
  if (whens && whens->kind == TC_AST_ARRAY) {
    for (size_t i = 0; i < whens->as.array->count; i++) {
      TcAstValue clause = whens->as.array->items[i];
      TcAstValue *conds = ast_get(clause, "conditions");
      if (!conds || conds->kind != TC_AST_ARRAY) return 0;
      for (size_t ci = 0; ci < conds->as.array->count; ci++) {
        if (!is_symbol_literal(conds->as.array->items[ci])) return 0;
        total++;
      }
    }
  }
  return total > 0;
}

// Sym-only case dispatch: emit a single CASE_SYM_LINEAR instruction
// that does a linear ptr-equality scan over an off-band key table.
// Replaces the per-arm chain of LOAD_LOCAL + EQ_CONST_BR + JUMP
// (~3 dispatches per arm) with one dispatch that jumps directly to
// the matched body. Targets the `case t when :var ...` shape that
// dominates compiler/lib/lowering.w.
static int compile_case_sym_linear(int subject_slot, TcAstValue *arms, TcAstValue *whens,
                                   TcAstValue *else_body, TcChunk *chunk, TcError *err) {
  size_t total = 0;
  if (arms && arms->kind == TC_AST_ARRAY) total += arms->as.array->count;
  if (whens && whens->kind == TC_AST_ARRAY) {
    for (size_t i = 0; i < whens->as.array->count; i++) {
      TcAstValue clause = whens->as.array->items[i];
      TcAstValue *conds = ast_get(clause, "conditions");
      if (conds && conds->kind == TC_AST_ARRAY) total += conds->as.array->count;
    }
  }
  int table_id = tc_chunk_alloc_case_table(chunk, (uint32_t)total, err);
  if (table_id < 0) return 0;

  // LOAD_LOCAL subject ; CASE_SYM_LINEAR table_id
  if (!tc_emit_op_u32(chunk, TC_OP_LOAD_LOCAL, (uint32_t)subject_slot, err) ||
      !tc_emit_op_u32(chunk, TC_OP_CASE_SYM_LINEAR, (uint32_t)table_id, err)) {
    return 0;
  }

  size_t end_count = 0;
  size_t end_cap = total + 1;  // +1 for default body's end-jump
  size_t *end_jumps = (size_t *)calloc(end_cap, sizeof(size_t));
  if (!end_jumps) {
    tc_error_set(err, "case sym jump allocation failed");
    return 0;
  }

  // Look up the table once; tc_chunk_alloc_case_table may have
  // realloc'd chunk->case_tables since.
  size_t entry_idx = 0;
  if (arms && arms->kind == TC_AST_ARRAY) {
    for (size_t i = 0; i < arms->as.array->count; i++) {
      TcAstValue arm = arms->as.array->items[i];
      TcAstValue *pattern = ast_get(arm, "pattern");
      TcAstValue *body = ast_get(arm, "body");
      TcAstValue *value = ast_get(*pattern, "value");
      const char *interned = tc_intern(value->as.string.bytes, value->as.string.len);
      if (!interned) {
        tc_error_set(err, "case sym intern failed");
        free(end_jumps);
        return 0;
      }
      TcCaseTable *table = &chunk->case_tables[table_id];
      table->keys[entry_idx] = interned;
      table->targets[entry_idx] = (uint32_t)chunk->count;
      entry_idx++;
      if (!compile_body_value(*body, chunk, err) ||
          !emit_jump(chunk, TC_OP_JUMP, &end_jumps[end_count++], err)) {
        free(end_jumps);
        return 0;
      }
    }
  }
  if (whens && whens->kind == TC_AST_ARRAY) {
    for (size_t i = 0; i < whens->as.array->count; i++) {
      TcAstValue clause = whens->as.array->items[i];
      TcAstValue *conds = ast_get(clause, "conditions");
      TcAstValue *body = ast_get(clause, "body");
      // All conds in this when share one body — emit body once and
      // point every cond's table entry at its start.
      uint32_t body_addr = (uint32_t)chunk->count;
      for (size_t ci = 0; ci < conds->as.array->count; ci++) {
        TcAstValue *value = ast_get(conds->as.array->items[ci], "value");
        const char *interned = tc_intern(value->as.string.bytes, value->as.string.len);
        if (!interned) {
          tc_error_set(err, "case sym intern failed");
          free(end_jumps);
          return 0;
        }
        TcCaseTable *table = &chunk->case_tables[table_id];
        table->keys[entry_idx] = interned;
        table->targets[entry_idx] = body_addr;
        entry_idx++;
      }
      if (!compile_body_value(*body, chunk, err) ||
          !emit_jump(chunk, TC_OP_JUMP, &end_jumps[end_count++], err)) {
        free(end_jumps);
        return 0;
      }
    }
  }
  // Default body: where the CASE_SYM_LINEAR runtime jumps on a miss
  // (no key match, or scrutinee isn't a sym).
  chunk->case_tables[table_id].default_target = (uint32_t)chunk->count;
  if (else_body && else_body->kind != TC_AST_NIL) {
    if (!compile_body_value(*else_body, chunk, err)) {
      free(end_jumps);
      return 0;
    }
  } else if (!emit_nil(chunk, err)) {
    free(end_jumps);
    return 0;
  }
  for (size_t i = 0; i < end_count; i++) patch_jump(chunk, end_jumps[i], chunk->count);
  free(end_jumps);
  return 1;
}

static int compile_case_value(TcAstValue node, TcChunk *chunk, TcError *err) {
  static uint32_t case_id = 0;
  char subject_name[48];
  snprintf(subject_name, sizeof(subject_name), "__case_subject_%u", case_id++);

  TcAstValue *subject = ast_get(node, "subject");
  // case_value can carry either `=>`-style arms (each {pattern, body})
  // or `when`-style whens (each {conditions: [...], body}). The
  // parser populates whichever syntax was used and leaves the other
  // empty. Both compile to the same shape: subject == X ? body : ...
  // The original implementation only handled arms — when clauses
  // (the dominant form in compiler/lib/lowering.w's `case t when :or`
  // style) were silently dropped, then the entire case fell through
  // to nil and any expression downstream of the case body got
  // mis-typed at runtime. This bug surfaced as
  // `cannot add false + false` from miscompiled `||` chains in
  // generated stage-1 binaries — `||` in the source compiled correctly,
  // but lowering.w's case-dispatch on the AST node kind ended up at
  // a fall-through path that emitted w_add for what should have been
  // short-circuit logic.
  TcAstValue *arms = ast_get(node, "arms");
  TcAstValue *whens = ast_get(node, "whens");
  TcAstValue *else_body = ast_get(node, "else_body");
  if (!subject ||
      ((!arms || arms->kind != TC_AST_ARRAY) && (!whens || whens->kind != TC_AST_ARRAY))) {
    tc_error_set(err, "case_value node missing subject/arms+whens");
    return 0;
  }

  int subject_slot = tc_chunk_local(chunk, subject_name, strlen(subject_name), err);
  if (subject_slot < 0) return 0;
  if (!compile_expr(*subject, chunk, err) ||
      !tc_emit_op_u32(chunk, TC_OP_STORE_LOCAL, (uint32_t)subject_slot, err) ||
      !tc_emit_op(chunk, TC_OP_POP, err)) {
    return 0;
  }

  // Sym-only fast path: every arm pattern is a sym literal → one
  // CASE_SYM_LINEAR dispatch instead of an N-arm chain.
  if (case_value_is_sym_only(arms, whens)) {
    return compile_case_sym_linear(subject_slot, arms, whens, else_body, chunk, err);
  }

  size_t arms_count = (arms && arms->kind == TC_AST_ARRAY) ? arms->as.array->count : 0;
  size_t whens_count = (whens && whens->kind == TC_AST_ARRAY) ? whens->as.array->count : 0;
  // Each arm contributes one end-jump; each when's condition list
  // contributes one end-jump per condition. Over-allocate; we size by
  // upper bound rather than walking the conditions twice.
  size_t end_cap = arms_count + 1;
  if (whens_count) {
    for (size_t i = 0; i < whens_count; i++) {
      TcAstValue clause = whens->as.array->items[i];
      TcAstValue *conds = ast_get(clause, "conditions");
      if (conds && conds->kind == TC_AST_ARRAY) end_cap += conds->as.array->count;
    }
  }
  size_t end_count = 0;
  size_t *end_jumps = (size_t *)calloc(end_cap, sizeof(size_t));
  if (!end_jumps) {
    tc_error_set(err, "case jump allocation failed");
    return 0;
  }

  for (size_t i = 0; i < arms_count; i++) {
    TcAstValue arm = arms->as.array->items[i];
    TcAstValue *pattern = ast_get(arm, "pattern");
    TcAstValue *body = ast_get(arm, "body");
    if (!pattern || !body) continue;
    size_t next_jump = 0;
    if (!tc_emit_op_u32(chunk, TC_OP_LOAD_LOCAL, (uint32_t)subject_slot, err) ||
        !compile_expr(*pattern, chunk, err) ||
        !tc_emit_op(chunk, TC_OP_CASE_MATCH, err) ||
        !emit_jump(chunk, TC_OP_JUMP_IF_FALSE, &next_jump, err) ||
        !compile_body_value(*body, chunk, err) ||
        !emit_jump(chunk, TC_OP_JUMP, &end_jumps[end_count++], err)) {
      free(end_jumps);
      return 0;
    }
    patch_jump(chunk, next_jump, chunk->count);
  }

  for (size_t i = 0; i < whens_count; i++) {
    TcAstValue clause = whens->as.array->items[i];
    TcAstValue *conds = ast_get(clause, "conditions");
    TcAstValue *body = ast_get(clause, "body");
    if (!conds || conds->kind != TC_AST_ARRAY || !body) continue;
    for (size_t ci = 0; ci < conds->as.array->count; ci++) {
      size_t next_jump = 0;
      if (!tc_emit_op_u32(chunk, TC_OP_LOAD_LOCAL, (uint32_t)subject_slot, err) ||
          !compile_expr(conds->as.array->items[ci], chunk, err) ||
          !tc_emit_op(chunk, TC_OP_CASE_MATCH, err) ||
          !emit_jump(chunk, TC_OP_JUMP_IF_FALSE, &next_jump, err) ||
          !compile_body_value(*body, chunk, err) ||
          !emit_jump(chunk, TC_OP_JUMP, &end_jumps[end_count++], err)) {
        free(end_jumps);
        return 0;
      }
      patch_jump(chunk, next_jump, chunk->count);
    }
  }

  if (else_body && else_body->kind != TC_AST_NIL) {
    if (!compile_body_value(*else_body, chunk, err)) {
      free(end_jumps);
      return 0;
    }
  } else if (!emit_nil(chunk, err)) {
    free(end_jumps);
    return 0;
  }
  for (size_t i = 0; i < end_count; i++) patch_jump(chunk, end_jumps[i], chunk->count);
  free(end_jumps);
  return 1;
}

static int compile_case(TcAstValue node, TcChunk *chunk, TcError *err) {
  TcAstValue *whens = ast_get(node, "whens");
  TcAstValue *else_body = ast_get(node, "else_body");
  if (!whens || whens->kind != TC_AST_ARRAY) {
    tc_error_set(err, "case node missing whens");
    return 0;
  }

  size_t end_count = 0;
  size_t end_cap = whens->as.array->count ? whens->as.array->count : 1;
  size_t *end_jumps = (size_t *)calloc(end_cap, sizeof(size_t));
  if (!end_jumps) {
    tc_error_set(err, "case jump allocation failed");
    return 0;
  }

  for (size_t i = 0; i < whens->as.array->count; i++) {
    TcAstValue clause = whens->as.array->items[i];
    TcAstValue *conditions = ast_get(clause, "conditions");
    TcAstValue *body = ast_get(clause, "body");
    if (!conditions || conditions->kind != TC_AST_ARRAY || !body) continue;
    for (size_t ci = 0; ci < conditions->as.array->count; ci++) {
      size_t next_jump = 0;
      if (!compile_expr(conditions->as.array->items[ci], chunk, err) ||
          !emit_jump(chunk, TC_OP_JUMP_IF_FALSE, &next_jump, err) ||
          !compile_body_value(*body, chunk, err) ||
          !emit_jump(chunk, TC_OP_JUMP, &end_jumps[end_count++], err)) {
        free(end_jumps);
        return 0;
      }
      patch_jump(chunk, next_jump, chunk->count);
    }
  }

  if (else_body && else_body->kind != TC_AST_NIL) {
    if (!compile_body_value(*else_body, chunk, err)) {
      free(end_jumps);
      return 0;
    }
  } else if (!emit_nil(chunk, err)) {
    free(end_jumps);
    return 0;
  }
  for (size_t i = 0; i < end_count; i++) patch_jump(chunk, end_jumps[i], chunk->count);
  free(end_jumps);
  return 1;
}

static int compile_compound_assign(TcAstValue node, TcChunk *chunk, TcError *err) {
  TcAstValue *target = ast_get(node, "target");
  TcAstValue *value = ast_get(node, "value");
  TcAstValue *op = ast_get(node, "op");
  if (!target || !value || !op) {
    tc_error_set(err, "compound assignment missing target/value/operator");
    return 0;
  }
  if (ast_node_is(*target, "call")) {
    return compile_expr(*value, chunk, err);
  }
  if (!ast_node_is(*target, "var") && !ast_node_is(*target, "ivar") && !ast_node_is(*target, "cvar")) {
    tc_error_set(err, "unsupported compound assignment target");
    return 0;
  }
  TcAstValue *name = ast_get(*target, "name");
  if (!name || name->kind != TC_AST_STRING) {
    tc_error_set(err, "compound assignment target missing name");
    return 0;
  }
  uint8_t code = binary_opcode(*op);
  if (code == 0) {
    tc_error_set(err, "unsupported compound assignment operator");
    return 0;
  }
  if (ast_node_is(*target, "ivar")) {
    const char *bytes = name->as.string.bytes;
    size_t len = name->as.string.len;
    if (len > 0 && bytes[0] == '@') { bytes++; len--; }
    int cid = emit_symbol_const(chunk, bytes, len, err);
    if (cid < 0) return 0;
    return tc_emit_op_u32(chunk, TC_OP_IVAR_GET, (uint32_t)cid, err) &&
           compile_expr(*value, chunk, err) &&
           tc_emit_op(chunk, code, err) &&
           tc_emit_op_u32(chunk, TC_OP_IVAR_SET, (uint32_t)cid, err);
  }
  if (ast_node_is(*target, "cvar")) {
    int cid = emit_symbol_const(chunk, name->as.string.bytes, name->as.string.len, err);
    if (cid < 0) return 0;
    return tc_emit_op_u32(chunk, TC_OP_CVAR_GET, (uint32_t)cid, err) &&
           compile_expr(*value, chunk, err) &&
           tc_emit_op(chunk, code, err) &&
           tc_emit_op_u32(chunk, TC_OP_CVAR_SET, (uint32_t)cid, err);
  }
  int slot = tc_chunk_local(chunk, name->as.string.bytes, name->as.string.len, err);
  if (slot < 0) return 0;
  return tc_emit_op_u32(chunk, TC_OP_LOAD_LOCAL, (uint32_t)slot, err) &&
         compile_expr(*value, chunk, err) &&
         tc_emit_op(chunk, code, err) &&
         tc_emit_op_u32(chunk, TC_OP_STORE_LOCAL, (uint32_t)slot, err);
}

static int compile_array(TcAstValue node, TcChunk *chunk, TcError *err) {
  TcAstValue *elements = ast_get(node, "elements");
  if (!elements || elements->kind != TC_AST_ARRAY) {
    tc_error_set(err, "array node missing elements");
    return 0;
  }
  for (size_t i = 0; i < elements->as.array->count; i++) {
    if (!compile_expr(elements->as.array->items[i], chunk, err)) return 0;
  }
  return tc_emit_op_u32(chunk, TC_OP_ARRAY, (uint32_t)elements->as.array->count, err);
}

static int block_first_param(TcAstValue block, const char **name_out, size_t *len_out) {
  TcAstValue *params = ast_get(block, "params");
  if (!params || params->kind != TC_AST_ARRAY || params->as.array->count == 0) return 0;

  TcAstValue first = params->as.array->items[0];
  if (first.kind == TC_AST_STRING || first.kind == TC_AST_SYMBOL) {
    *name_out = first.as.string.bytes;
    *len_out = first.as.string.len;
    return 1;
  }

  TcAstValue *first_name = ast_get(first, "name");
  if (first_name && (first_name->kind == TC_AST_STRING || first_name->kind == TC_AST_SYMBOL)) {
    *name_out = first_name->as.string.bytes;
    *len_out = first_name->as.string.len;
    return 1;
  }

  return 0;
}

static int compile_each_block(TcAstValue receiver, TcAstValue block, TcChunk *chunk, TcError *err) {
  static uint32_t each_id = 0;
  char recv_name[48];
  char idx_name[48];
  snprintf(recv_name, sizeof(recv_name), "__each_recv_%u", each_id);
  snprintf(idx_name, sizeof(idx_name), "__each_idx_%u", each_id);
  each_id++;

  int recv_slot = tc_chunk_local(chunk, recv_name, strlen(recv_name), err);
  int idx_slot = tc_chunk_local(chunk, idx_name, strlen(idx_name), err);
  if (recv_slot < 0 || idx_slot < 0) return 0;

  TcAstValue *body = ast_get(block, "body");
  const char *param_name = "__arg1";
  size_t param_len = 6;
  (void)block_first_param(block, &param_name, &param_len);
  int param_slot = tc_chunk_local(chunk, param_name, param_len, err);
  if (param_slot < 0) return 0;

  if (!compile_expr(receiver, chunk, err) ||
      !tc_emit_op_u32(chunk, TC_OP_STORE_LOCAL, (uint32_t)recv_slot, err) ||
      !tc_emit_op(chunk, TC_OP_POP, err) ||
      emit_const(chunk, tc_box_int(0), err) == 0 ||
      !tc_emit_op_u32(chunk, TC_OP_STORE_LOCAL, (uint32_t)idx_slot, err) ||
      !tc_emit_op(chunk, TC_OP_POP, err)) {
    return 0;
  }

  size_t loop_start = chunk->count;
  size_t exit_jump = 0;
  if (!tc_emit_op_u32(chunk, TC_OP_LOAD_LOCAL, (uint32_t)idx_slot, err) ||
      !tc_emit_op_u32(chunk, TC_OP_LOAD_LOCAL, (uint32_t)recv_slot, err) ||
      !tc_emit_op(chunk, TC_OP_SIZE_OF, err) ||
      !tc_emit_op(chunk, TC_OP_LT, err) ||
      !emit_jump(chunk, TC_OP_JUMP_IF_FALSE, &exit_jump, err) ||
      !tc_emit_op_u32(chunk, TC_OP_LOAD_LOCAL, (uint32_t)recv_slot, err) ||
      !tc_emit_op_u32(chunk, TC_OP_LOAD_LOCAL, (uint32_t)idx_slot, err) ||
      !tc_emit_op(chunk, TC_OP_INDEX, err) ||
      !tc_emit_op_u32(chunk, TC_OP_STORE_LOCAL, (uint32_t)param_slot, err) ||
      !tc_emit_op(chunk, TC_OP_POP, err)) {
    return 0;
  }
  if (body && !compile_body_statements(*body, chunk, err)) return 0;
  if (!tc_emit_op_u32(chunk, TC_OP_LOAD_LOCAL, (uint32_t)idx_slot, err) ||
      !emit_const(chunk, tc_box_int(1), err) ||
      !tc_emit_op(chunk, TC_OP_ADD, err) ||
      !tc_emit_op_u32(chunk, TC_OP_STORE_LOCAL, (uint32_t)idx_slot, err) ||
      !tc_emit_op(chunk, TC_OP_POP, err) ||
      !tc_emit_op_u32(chunk, TC_OP_JUMP, (uint32_t)loop_start, err)) {
    return 0;
  }
  patch_jump(chunk, exit_jump, chunk->count);
  return emit_nil(chunk, err);
}

static int compile_times_block(TcAstValue receiver, TcAstValue block, TcChunk *chunk, TcError *err) {
  static uint32_t times_id = 0;
  static uint32_t times_depth = 0;
  static const char *implicit_names[] = {"i", "j", "k", "m", "n"};
  char count_name[48];
  char idx_name[48];
  snprintf(count_name, sizeof(count_name), "__times_count_%u", times_id);
  snprintf(idx_name, sizeof(idx_name), "__times_idx_%u", times_id);
  times_id++;

  int count_slot = tc_chunk_local(chunk, count_name, strlen(count_name), err);
  int idx_slot = tc_chunk_local(chunk, idx_name, strlen(idx_name), err);
  if (count_slot < 0 || idx_slot < 0) return 0;

  TcAstValue *body = ast_get(block, "body");
  const char *param_name = NULL;
  size_t param_len = 0;
  if (!block_first_param(block, &param_name, &param_len)) {
    size_t depth = times_depth < (sizeof(implicit_names) / sizeof(implicit_names[0]))
                       ? times_depth
                       : (sizeof(implicit_names) / sizeof(implicit_names[0])) - 1;
    param_name = implicit_names[depth];
    param_len = strlen(param_name);
  }
  int param_slot = tc_chunk_local(chunk, param_name, param_len, err);
  if (param_slot < 0) return 0;

  if (!compile_expr(receiver, chunk, err) ||
      !tc_emit_op_u32(chunk, TC_OP_STORE_LOCAL, (uint32_t)count_slot, err) ||
      !tc_emit_op(chunk, TC_OP_POP, err) ||
      emit_const(chunk, tc_box_int(0), err) == 0 ||
      !tc_emit_op_u32(chunk, TC_OP_STORE_LOCAL, (uint32_t)idx_slot, err) ||
      !tc_emit_op(chunk, TC_OP_POP, err)) {
    return 0;
  }

  size_t loop_start = chunk->count;
  size_t exit_jump = 0;
  if (!tc_emit_op_u32(chunk, TC_OP_LOAD_LOCAL, (uint32_t)idx_slot, err) ||
      !tc_emit_op_u32(chunk, TC_OP_LOAD_LOCAL, (uint32_t)count_slot, err) ||
      !tc_emit_op(chunk, TC_OP_LT, err) ||
      !emit_jump(chunk, TC_OP_JUMP_IF_FALSE, &exit_jump, err) ||
      !tc_emit_op_u32(chunk, TC_OP_LOAD_LOCAL, (uint32_t)idx_slot, err) ||
      !tc_emit_op_u32(chunk, TC_OP_STORE_LOCAL, (uint32_t)param_slot, err) ||
      !tc_emit_op(chunk, TC_OP_POP, err)) {
    return 0;
  }

  times_depth++;
  int ok = !body || compile_body_statements(*body, chunk, err);
  times_depth--;
  if (!ok) return 0;

  if (!tc_emit_op_u32(chunk, TC_OP_LOAD_LOCAL, (uint32_t)idx_slot, err) ||
      !emit_const(chunk, tc_box_int(1), err) ||
      !tc_emit_op(chunk, TC_OP_ADD, err) ||
      !tc_emit_op_u32(chunk, TC_OP_STORE_LOCAL, (uint32_t)idx_slot, err) ||
      !tc_emit_op(chunk, TC_OP_POP, err) ||
      !tc_emit_op_u32(chunk, TC_OP_JUMP, (uint32_t)loop_start, err)) {
    return 0;
  }
  patch_jump(chunk, exit_jump, chunk->count);
  return tc_emit_op_u32(chunk, TC_OP_LOAD_LOCAL, (uint32_t)count_slot, err);
}

static int compile_hash(TcAstValue node, TcChunk *chunk, TcError *err) {
  TcAstValue *entries = ast_get(node, "entries");
  if (!entries || entries->kind != TC_AST_ARRAY) {
    tc_error_set(err, "hash node missing entries");
    return 0;
  }
  for (size_t i = 0; i < entries->as.array->count; i++) {
    TcAstValue pair = entries->as.array->items[i];
    if (pair.kind != TC_AST_ARRAY || pair.as.array->count < 2) {
      tc_error_set(err, "hash entry malformed");
      return 0;
    }
    if (!compile_expr(pair.as.array->items[0], chunk, err) ||
        !compile_expr(pair.as.array->items[1], chunk, err)) {
      return 0;
    }
  }
  return tc_emit_op_u32(chunk, TC_OP_HASH, (uint32_t)entries->as.array->count, err);
}

static int compile_call(TcAstValue node, TcChunk *chunk, TcError *err) {
  TcAstValue *receiver = ast_get(node, "receiver");
  TcAstValue *name = ast_get(node, "name");
  TcAstValue *args = ast_get(node, "args");
  TcAstValue *block = ast_get(node, "block");
  if (receiver && receiver->kind != TC_AST_NIL && name && ast_text_eq(*name, "each") &&
      block && block->kind != TC_AST_NIL) {
    return compile_each_block(*receiver, *block, chunk, err);
  }
  if (receiver && receiver->kind != TC_AST_NIL && name && ast_text_eq(*name, "times") &&
      block && block->kind != TC_AST_NIL) {
    return compile_times_block(*receiver, *block, chunk, err);
  }
  if (receiver && receiver->kind == TC_AST_NIL && name && ast_text_eq(*name, "puts") &&
      args && args->kind == TC_AST_ARRAY) {
    if (args->as.array->count == 0) {
      if (!emit_nil(chunk, err)) return 0;
    } else if (!compile_expr(args->as.array->items[0], chunk, err)) {
      return 0;
    }
    return tc_emit_op(chunk, TC_OP_PRINT, err);
  }

  if (!name || name->kind != TC_AST_STRING || !args || args->kind != TC_AST_ARRAY) {
    tc_error_set(err, "malformed call");
    return 0;
  }
  if (receiver && ast_node_is(*receiver, "var")) {
    TcAstValue *receiver_name = ast_get(*receiver, "name");
    if (receiver_name && receiver_name->kind == TC_AST_STRING && receiver_name->as.string.len > 0 &&
        receiver_name->as.string.bytes[0] >= 'A' && receiver_name->as.string.bytes[0] <= 'Z') {
      for (size_t i = 0; i < args->as.array->count; i++) {
        if (!compile_expr(args->as.array->items[i], chunk, err)) return 0;
      }
      size_t full_len = receiver_name->as.string.len + 1 + name->as.string.len;
      char *full_name = (char *)malloc(full_len + 1);
      if (!full_name) {
        tc_error_set(err, "class call name allocation failed");
        return 0;
      }
      memcpy(full_name, receiver_name->as.string.bytes, receiver_name->as.string.len);
      full_name[receiver_name->as.string.len] = '.';
      memcpy(full_name + receiver_name->as.string.len + 1, name->as.string.bytes, name->as.string.len);
      full_name[full_len] = '\0';
      int ok = emit_call_op(chunk, full_name, full_len, args->as.array->count, 0, err);
      free(full_name);
      return ok;
    }
  }
  int has_receiver = receiver && receiver->kind != TC_AST_NIL;
  if (has_receiver && !compile_expr(*receiver, chunk, err)) return 0;
  for (size_t i = 0; i < args->as.array->count; i++) {
    if (!compile_expr(args->as.array->items[i], chunk, err)) return 0;
  }

  // Specialised opcodes for the hottest method names (~75% of stage-1
  // CALL dispatches combined). Each skips name lookup, arg-buffer
  // setup, and the L_CALL matcher chain.
  if (has_receiver) {
    size_t argc = args->as.array->count;
    if (argc == 1 && ast_text_eq(*name, "[]"))   return tc_emit_op(chunk, TC_OP_INDEX, err);
    if (argc == 0 && ast_text_eq(*name, "size")) return tc_emit_op(chunk, TC_OP_SIZE_OF, err);
  }

  return emit_call_op(chunk, name->as.string.bytes, name->as.string.len, args->as.array->count, has_receiver, err);
}

static int compile_expr(TcAstValue node, TcChunk *chunk, TcError *err) {
  if (node.kind != TC_AST_HASH) {
    if (node.kind == TC_AST_NIL) return emit_nil(chunk, err);
    tc_error_set(err, "expected AST node");
    return 0;
  }

  if (ast_node_is(node, "int")) {
    TcAstValue *value = ast_get(node, "value");
    if (!value || value->kind != TC_AST_INT) {
      tc_error_set(err, "int node missing value");
      return 0;
    }
    return emit_const(chunk, tc_box_int(value->as.integer), err);
  }
  if (ast_node_is(node, "string")) {
    TcAstValue *value = ast_get(node, "value");
    size_t len = 0;
    char *text = value ? copy_unquoted_string(*value, &len, err) : NULL;
    if (!text) return 0;
    return emit_const(chunk, tc_box_string_bytes(text, len, 0), err);
  }
  if (ast_node_is(node, "string_interp")) {
    // Lower `"foo[bar]baz"` to a sequence of pushes + ADDs:
    //   push "foo"
    //   compile bar; CALL to_s argc=0 recv=1
    //   ADD                              (concat "foo" + bar.to_s())
    //   push "baz"
    //   ADD
    // The final result lives on the top of the stack.
    //
    // string_interp parts are an array of 2-element arrays:
    //   [:str, "literal"]   — push the string
    //   [:expr, ast_expr]   — compile expr, then `to_s` to coerce
    //
    // Empty parts list => empty string. Single part => just push it
    // (no ADD needed). The concat-on-the-fly walk mirrors what the
    // self-hosted compiler does in lower_string_interp via
    // w_to_s + w_str_concat — we end up with the same runtime IR
    // shape via TC_OP_ADD's TC_VAL_STRING branch.
    TcAstValue *parts = ast_get(node, "parts");
    if (!parts || parts->kind != TC_AST_ARRAY) {
      tc_error_set(err, "string_interp missing parts");
      return 0;
    }
    if (parts->as.array->count == 0) {
      char *empty = tc_heap_string_alloc(0, 0, err);
      if (!empty) return 0;
      return emit_const(chunk, tc_box_string_bytes(empty, 0, 0), err);
    }
    for (size_t i = 0; i < parts->as.array->count; i++) {
      TcAstValue pair = parts->as.array->items[i];
      if (pair.kind != TC_AST_ARRAY || pair.as.array->count < 2) {
        tc_error_set(err, "string_interp part malformed");
        return 0;
      }
      TcAstValue tag = pair.as.array->items[0];
      TcAstValue body = pair.as.array->items[1];
      if (tag.kind == TC_AST_SYMBOL && tag.as.string.len == 3 &&
          memcmp(tag.as.string.bytes, "str", 3) == 0) {
        // Literal segment: push it as a TC_VAL_STRING constant.
        if (body.kind != TC_AST_STRING) {
          tc_error_set(err, "string_interp :str part missing string body");
          return 0;
        }
        char *copy = tc_heap_string_alloc(body.as.string.len, 0, err);
        if (!copy) return 0;
        if (body.as.string.len > 0) memcpy(copy, body.as.string.bytes, body.as.string.len);
        if (!emit_const(chunk, tc_box_string_bytes(copy, body.as.string.len, 0), err)) return 0;
      } else {
        // Expression: compile, then call .to_s() to coerce.
        if (!compile_expr(body, chunk, err)) return 0;
        if (!emit_call_op(chunk, "to_s", 4, 0, 1, err)) return 0;
      }
      if (i > 0) {
        // Reduce: top-2 + top-1 -> top.
        if (!tc_emit_op(chunk, TC_OP_ADD, err)) return 0;
      }
    }
    return 1;
  }
  if (ast_node_is(node, "symbol")) {
    TcAstValue *value = ast_get(node, "value");
    if (!value || value->kind != TC_AST_STRING) {
      tc_error_set(err, "symbol node missing value");
      return 0;
    }
    char *text = tc_heap_string_alloc(value->as.string.len, 0, err);
    if (!text) return 0;
    memcpy(text, value->as.string.bytes, value->as.string.len);
    return emit_const(chunk, tc_box_symbol_bytes(text, value->as.string.len, 0), err);
  }
  if (ast_node_is(node, "bool")) {
    TcAstValue *value = ast_get(node, "value");
    return emit_const(chunk, tc_box_wvalue((value && value->as.boolean) ? W_TRUE : W_FALSE), err);
  }
  if (ast_node_is(node, "nil") || ast_node_is(node, "nil_lit")) return emit_nil(chunk, err);
  if (ast_node_is(node, "self") || ast_node_is(node, "self_ref")) {
    int slot = tc_chunk_local(chunk, "self", 4, err);
    if (slot < 0) return 0;
    return tc_emit_op_u32(chunk, TC_OP_LOAD_LOCAL, (uint32_t)slot, err);
  }
  if (ast_node_is(node, "char")) {
    // parse_ast.c stores the AST value as an int (the codepoint), so `:-#` is
    // {node:"char", value:35}. The lexer's `c == :-#` comparison against a
    // raw codepoint relied on this — emitting a nil here made the entire
    // comment-skip path in compiler/lib/lexer.w (and any other char-class
    // dispatch) silently fail.
    TcAstValue *value = ast_get(node, "value");
    if (!value) return emit_nil(chunk, err);
    if (value->kind == TC_AST_INT) {
      return emit_const(chunk, tc_box_int(value->as.integer), err);
    }
    if (value->kind == TC_AST_STRING) {
      char *text = tc_heap_string_alloc(value->as.string.len, 0, err);
      if (!text) return 0;
      memcpy(text, value->as.string.bytes, value->as.string.len);
      return emit_const(chunk, tc_box_string_bytes(text, value->as.string.len, 0), err);
    }
    return emit_nil(chunk, err);
  }
  if (ast_node_is(node, "codepoint") || ast_node_is(node, "decimal") || ast_node_is(node, "float")) {
    TcAstValue *value = ast_get(node, "value");
    if (!value || value->kind != TC_AST_STRING) return emit_nil(chunk, err);
    char *text = tc_heap_string_alloc(value->as.string.len, 0, err);
    if (!text) return 0;
    memcpy(text, value->as.string.bytes, value->as.string.len);
    return emit_const(chunk, tc_box_string_bytes(text, value->as.string.len, 0), err);
  }
  if (ast_node_is(node, "use") || ast_node_is(node, "method_def") || ast_node_is(node, "fn_def") ||
      ast_node_is(node, "class_def") || ast_node_is(node, "module_def") || ast_node_is(node, "trait_def") ||
      ast_node_is(node, "trait_include")) {
    return emit_nil(chunk, err);
  }
  if (ast_node_is(node, "in_test")) return compile_in_test(node, chunk, err);
  if (ast_node_is(node, "array")) return compile_array(node, chunk, err);
  if (ast_node_is(node, "hash_literal")) return compile_hash(node, chunk, err);
  if (ast_node_is(node, "case_value")) return compile_case_value(node, chunk, err);
  if (ast_node_is(node, "case")) return compile_case(node, chunk, err);
  if (ast_node_is(node, "typed_array")) {
    TcAstValue *size = ast_get(node, "size");
    if (!size || !compile_expr(*size, chunk, err)) return 0;
    return tc_emit_op(chunk, TC_OP_TYPED_ARRAY, err);
  }
  if (ast_node_is(node, "range")) {
    // Compile a :range AST as a tagged hash { __range__: true, from: ...,
    // to: ..., exclusive: ... }. INDEX recognizes the tag and does a slice;
    // anything else just sees a hash. Avoids needing a dedicated TC_VAL_RANGE
    // — pricey for a feature only the bootstrap parser/lowering ever uses.
    TcAstValue *from = ast_get(node, "from");
    TcAstValue *to = ast_get(node, "to");
    TcAstValue *exclusive = ast_get(node, "exclusive");
    int marker_cid = emit_symbol_const(chunk, "__range__", 9, err);
    int from_cid = emit_symbol_const(chunk, "from", 4, err);
    int to_cid = emit_symbol_const(chunk, "to", 2, err);
    int excl_cid = emit_symbol_const(chunk, "exclusive", 9, err);
    if (marker_cid < 0 || from_cid < 0 || to_cid < 0 || excl_cid < 0) return 0;
    if (!tc_emit_op_u32(chunk, TC_OP_CONST, (uint32_t)marker_cid, err) ||
        !emit_const(chunk, tc_box_bool(1), err) ||
        !tc_emit_op_u32(chunk, TC_OP_CONST, (uint32_t)from_cid, err)) return 0;
    if (from && from->kind != TC_AST_NIL) {
      if (!compile_expr(*from, chunk, err)) return 0;
    } else if (!emit_nil(chunk, err)) return 0;
    if (!tc_emit_op_u32(chunk, TC_OP_CONST, (uint32_t)to_cid, err)) return 0;
    if (to && to->kind != TC_AST_NIL) {
      if (!compile_expr(*to, chunk, err)) return 0;
    } else if (!emit_nil(chunk, err)) return 0;
    if (!tc_emit_op_u32(chunk, TC_OP_CONST, (uint32_t)excl_cid, err)) return 0;
    int excl_val = (exclusive && exclusive->kind == TC_AST_BOOL) ? exclusive->as.boolean : 0;
    if (!emit_const(chunk, tc_box_bool(excl_val), err)) return 0;
    return tc_emit_op_u32(chunk, TC_OP_HASH, 4, err);
  }
  if (ast_node_is(node, "case_arm") || ast_node_is(node, "block")) {
    return emit_nil(chunk, err);
  }
  if (ast_node_is(node, "break")) {
    if (loop_top < 0) {
      // outside any loop — emit nil and continue (matches old stub behavior)
      return emit_nil(chunk, err);
    }
    LoopCtx *ctx = &loop_stack[loop_top];
    if (ctx->break_count >= sizeof(ctx->break_offsets) / sizeof(ctx->break_offsets[0])) {
      tc_error_set(err, "too many `break` in one loop");
      return 0;
    }
    size_t off = 0;
    if (!emit_jump(chunk, TC_OP_JUMP, &off, err)) return 0;
    ctx->break_offsets[ctx->break_count++] = off;
    return 1;
  }
  if (ast_node_is(node, "next")) {
    if (loop_top < 0) {
      return emit_nil(chunk, err);
    }
    return tc_emit_op_u32(chunk, TC_OP_JUMP, (uint32_t)loop_stack[loop_top].continue_target, err);
  }
  if (ast_node_is(node, "begin")) {
    TcAstValue *body = ast_get(node, "body");
    return body ? compile_body_value(*body, chunk, err) : emit_nil(chunk, err);
  }
  if (ast_node_is(node, "return")) {
    TcAstValue *value = ast_get(node, "value");
    if (value && value->kind != TC_AST_NIL) {
      if (!compile_expr(*value, chunk, err)) return 0;
    } else if (!emit_nil(chunk, err)) {
      return 0;
    }
    return tc_emit_op(chunk, TC_OP_RETURN, err);
  }
  if (ast_node_is(node, "var") || ast_node_is(node, "ivar") || ast_node_is(node, "cvar")) return compile_var(node, chunk, err);
  if (ast_node_is(node, "parg")) return compile_parg(node, chunk, err);
  if (ast_node_is(node, "binary_op")) return compile_binary(node, chunk, err);
  if (ast_node_is(node, "assign")) return compile_assign(node, chunk, err);
  if (ast_node_is(node, "compound_assign")) return compile_compound_assign(node, chunk, err);
  if (ast_node_is(node, "if")) return compile_if(node, chunk, err);
  if (ast_node_is(node, "while")) return compile_while(node, chunk, err);
  if (ast_node_is(node, "on_guard")) return compile_on_guard(node, chunk, err);
  if (ast_node_is(node, "unary_op")) {
    TcAstValue *op = ast_get(node, "op");
    TcAstValue *operand = ast_get(node, "operand");
    if (op && operand && ast_text_eq(*op, "MINUS")) {
      return emit_const(chunk, tc_box_int(0), err) &&
             compile_expr(*operand, chunk, err) &&
             tc_emit_op(chunk, TC_OP_SUB, err);
    }
    return operand ? compile_expr(*operand, chunk, err) : emit_nil(chunk, err);
  }
  if (ast_node_is(node, "not")) return compile_not(node, chunk, err);
  if (ast_node_is(node, "or")) return compile_or_and(node, chunk, 1, err);
  if (ast_node_is(node, "and")) return compile_or_and(node, chunk, 0, err);
  if (ast_node_is(node, "puts") || ast_node_is(node, "print")) return compile_puts(node, chunk, err);
  if (ast_node_is(node, "call")) return compile_call(node, chunk, err);
  /* `in NAMESPACE` directive — parser applied the prefix at parse
   * time; the AST node is a marker only. Emit nil so the
   * surrounding loop's POP has something to drop. */
  if (ast_node_is(node, "namespace_decl")) return emit_nil(chunk, err);

  TcAstValue *node_name = ast_get(node, "node");
  if (node_name && (node_name->kind == TC_AST_STRING || node_name->kind == TC_AST_SYMBOL)) {
    TcAstValue *source = ast_get(node, "source");
    TcAstValue *line = ast_get(node, "line");
    if (source && source->kind == TC_AST_STRING && line && line->kind == TC_AST_INT) {
      tc_error_set(err, "unsupported AST node: %.*s at line %lld: %.*s",
                   (int)node_name->as.string.len, node_name->as.string.bytes,
                   (long long)line->as.integer,
                   (int)source->as.string.len, source->as.string.bytes);
    } else if (source && source->kind == TC_AST_STRING) {
      tc_error_set(err, "unsupported AST node: %.*s: %.*s",
                   (int)node_name->as.string.len, node_name->as.string.bytes,
                   (int)source->as.string.len, source->as.string.bytes);
    } else {
      tc_error_set(err, "unsupported AST node: %.*s", (int)node_name->as.string.len, node_name->as.string.bytes);
    }
  } else {
    tc_error_set(err, "unsupported AST node");
  }
  return 0;
}

static int compile_body_value(TcAstValue body, TcChunk *chunk, TcError *err) {
  if (body.kind != TC_AST_ARRAY) return compile_expr(body, chunk, err);
  if (body.as.array->count == 0) return emit_nil(chunk, err);
  for (size_t i = 0; i < body.as.array->count; i++) {
    if (!compile_expr(body.as.array->items[i], chunk, err)) return 0;
    if (i + 1 < body.as.array->count && !tc_emit_op(chunk, TC_OP_POP, err)) return 0;
  }
  return 1;
}

static int compile_body_statements(TcAstValue body, TcChunk *chunk, TcError *err) {
  if (body.kind != TC_AST_ARRAY) {
    return compile_expr(body, chunk, err) && tc_emit_op(chunk, TC_OP_POP, err);
  }
  for (size_t i = 0; i < body.as.array->count; i++) {
    if (!compile_expr(body.as.array->items[i], chunk, err) ||
        !tc_emit_op(chunk, TC_OP_POP, err)) {
      return 0;
    }
  }
  return 1;
}

static int compile_function_def(TcAstValue node, const char *prefix, size_t prefix_len, TcChunk *chunk, TcError *err) {
  TcAstValue *name = ast_get(node, "name");
  TcAstValue *params = ast_get(node, "params");
  TcAstValue *body = ast_get(node, "body");
  if (!name || name->kind != TC_AST_STRING || !params || params->kind != TC_AST_ARRAY || !body) {
    tc_error_set(err, "malformed method definition");
    return 0;
  }
  if (prefix_len > 0 && tc_chunk_local(chunk, "self", 4, err) < 0) return 0;

  size_t param_count = params->as.array->count;
  size_t arity = param_count;
  TcAstValue *arity_suffix = ast_get(node, "arity");
  if (param_count == 0 && arity_suffix && arity_suffix->kind == TC_AST_STRING &&
      arity_suffix->as.string.len > 0) {
    char buf[32];
    if (arity_suffix->as.string.len < sizeof(buf)) {
      memcpy(buf, arity_suffix->as.string.bytes, arity_suffix->as.string.len);
      buf[arity_suffix->as.string.len] = '\0';
      char *end = NULL;
      unsigned long parsed = strtoul(buf, &end, 10);
      if (end && *end == '\0') arity = (size_t)parsed;
    }
  }
  if (arity > UINT32_MAX) {
    tc_error_set(err, "method arity too large");
    return 0;
  }
  uint32_t *param_slots = arity ? (uint32_t *)calloc(arity, sizeof(uint32_t)) : NULL;
  if (arity && !param_slots) {
    tc_error_set(err, "method param slot allocation failed");
    return 0;
  }

  for (size_t i = 0; i < arity; i++) {
    const char *param_bytes = NULL;
    size_t param_len = 0;
    char synthetic[32];
    if (i < param_count) {
      TcAstValue param = params->as.array->items[i];
      TcAstValue *param_name = ast_get(param, "name");
      if (!param_name || param_name->kind != TC_AST_STRING) {
        free(param_slots);
        tc_error_set(err, "method param missing name");
        return 0;
      }
      param_bytes = param_name->as.string.bytes;
      param_len = param_name->as.string.len;
    } else {
      int len = snprintf(synthetic, sizeof(synthetic), "__arg%zu", i + 1);
      if (len <= 0 || (size_t)len >= sizeof(synthetic)) {
        free(param_slots);
        tc_error_set(err, "method positional arity too large");
        return 0;
      }
      param_bytes = synthetic;
      param_len = (size_t)len;
    }
    int slot = tc_chunk_local(chunk, param_bytes, param_len, err);
    if (slot < 0) {
      free(param_slots);
      return 0;
    }
    param_slots[i] = (uint32_t)slot;
  }

  size_t full_name_len = prefix_len + name->as.string.len;
  char *full_name = (char *)malloc(full_name_len + 1);
  if (!full_name) {
    free(param_slots);
    tc_error_set(err, "method name allocation failed");
    return 0;
  }
  if (prefix_len > 0) memcpy(full_name, prefix, prefix_len);
  memcpy(full_name + prefix_len, name->as.string.bytes, name->as.string.len);
  full_name[full_name_len] = '\0';

  uint32_t entry = (uint32_t)chunk->count;
  if (!tc_chunk_add_function(chunk, full_name, full_name_len, entry,
                             param_slots, (uint32_t)arity, err)) {
    free(full_name);
    free(param_slots);
    return 0;
  }
  free(full_name);
  free(param_slots);

  // Default param values: `peek(offset = 1)` lets the caller omit `offset`
  // and get 1. vm_call_function fills missing args with nil, so we emit a
  // guard at function entry that replaces *only nil* with the default —
  // `false` is a real value the caller may have passed (e.g. lower_puts's
  // `produce_value=false`), and we musn't rewrite that to the default.
  // Earlier version used JUMP_IF_FALSE which pops the value and jumps on
  // any falsy, including `false` itself; the symptom was Loader#load_program_ast's
  // `lower_puts(ctx, node, false)` silently behaving like the default
  // (`true`), so stage 1's compiler bound the puts result while stage 2's
  // didn't, and the temp counter cascade made every downstream function
  // body diverge.
  //
  // New emit shape:
  //   LOAD_LOCAL slot ; CONST nil ; EQ ; JUMP_IF_FALSE skip_default
  //   <default> ; STORE_LOCAL slot ; POP
  //   skip_default:
  // EQ pushes `slot == nil` (a real bool); JUMP_IF_FALSE then skips the
  // default when the slot was *not* nil. `false` no longer triggers the
  // default branch.
  for (size_t i = 0; i < param_count; i++) {
    TcAstValue param = params->as.array->items[i];
    TcAstValue *def = ast_get(param, "default");
    if (!def || def->kind == TC_AST_NIL) continue;
    if (def->kind == TC_AST_HASH && (ast_node_is(*def, "nil") || ast_node_is(*def, "nil_lit"))) continue;
    TcAstValue *param_name = ast_get(param, "name");
    if (!param_name || param_name->kind != TC_AST_STRING) continue;
    int param_slot = tc_chunk_local(chunk, param_name->as.string.bytes, param_name->as.string.len, err);
    if (param_slot < 0) return 0;
    if (!tc_emit_op_u32(chunk, TC_OP_LOAD_LOCAL, (uint32_t)param_slot, err) ||
        !emit_nil(chunk, err) ||
        !tc_emit_op(chunk, TC_OP_EQ, err)) {
      return 0;
    }
    size_t skip_default = 0;
    if (!emit_jump(chunk, TC_OP_JUMP_IF_FALSE, &skip_default, err)) return 0;
    if (!compile_expr(*def, chunk, err) ||
        !tc_emit_op_u32(chunk, TC_OP_STORE_LOCAL, (uint32_t)param_slot, err) ||
        !tc_emit_op(chunk, TC_OP_POP, err)) {
      return 0;
    }
    patch_jump(chunk, skip_default, chunk->count);
  }

  // `@param` syntax (parser sets ivar_assign=true on the param): mirror
  // the bound local into self's fields hash before the body runs.
  // Method `-> new(@verbose = false)` is the canonical site — the loader
  // and every Tungsten class with a constructor relies on this. We do
  // it via [LOAD_LOCAL slot, IVAR_SET name, POP] for each ivar param.
  for (size_t i = 0; i < param_count; i++) {
    TcAstValue param = params->as.array->items[i];
    TcAstValue *flag = ast_get(param, "ivar_assign");
    if (!flag || flag->kind != TC_AST_BOOL || !flag->as.boolean) continue;
    TcAstValue *param_name = ast_get(param, "name");
    if (!param_name || param_name->kind != TC_AST_STRING) continue;
    const char *bytes = param_name->as.string.bytes;
    size_t len = param_name->as.string.len;
    if (len > 0 && bytes[0] == '@') { bytes++; len--; }
    int param_slot = tc_chunk_local(chunk, param_name->as.string.bytes, param_name->as.string.len, err);
    if (param_slot < 0) return 0;
    int cid = emit_symbol_const(chunk, bytes, len, err);
    if (cid < 0) return 0;
    if (!tc_emit_op_u32(chunk, TC_OP_LOAD_LOCAL, (uint32_t)param_slot, err) ||
        !tc_emit_op_u32(chunk, TC_OP_IVAR_SET, (uint32_t)cid, err) ||
        !tc_emit_op(chunk, TC_OP_POP, err)) {
      return 0;
    }
  }

  return compile_body_value(*body, chunk, err) &&
         tc_emit_op(chunk, TC_OP_RETURN, err);
}

static int compile_class_definitions(TcAstValue node, TcChunk *chunk, TcError *err) {
  TcAstValue *name = ast_get(node, "name");
  TcAstValue *body = ast_get(node, "body");
  if (!name || name->kind != TC_AST_STRING || !body || body->kind != TC_AST_ARRAY) return 1;

  // Register slab-role classes so `ClassName.new(args)` dispatches
  // without auto-allocating a TcRuntimeObject — the body's return
  // (typically a W_PACKED_NODE from slab_alloc_init) becomes the
  // result instead. See vm_call_body.inc's .new path.
  TcAstValue *role = ast_get(node, "class_role");
  if (role && role->kind == TC_AST_STRING &&
      role->as.string.len == 4 &&
      memcmp(role->as.string.bytes, "slab", 4) == 0) {
    if (!tc_chunk_register_slab_class(chunk, name->as.string.bytes, name->as.string.len, err)) {
      return 0;
    }
  }

  size_t prefix_len = name->as.string.len + 1;
  char *prefix = (char *)malloc(prefix_len + 1);
  if (!prefix) {
    tc_error_set(err, "class method prefix allocation failed");
    return 0;
  }
  memcpy(prefix, name->as.string.bytes, name->as.string.len);
  prefix[name->as.string.len] = '#';
  prefix[prefix_len] = '\0';

  for (size_t i = 0; i < body->as.array->count; i++) {
    TcAstValue expr = body->as.array->items[i];
    if ((ast_node_is(expr, "method_def") || ast_node_is(expr, "fn_def")) &&
        !compile_function_def(expr, prefix, prefix_len, chunk, err)) {
      free(prefix);
      return 0;
    }
  }
  free(prefix);
  return 1;
}

static int ast_is_definition_node(TcAstValue expr) {
  return ast_node_is(expr, "use") ||
         ast_node_is(expr, "method_def") ||
         ast_node_is(expr, "fn_def") ||
         ast_node_is(expr, "class_def") ||
         ast_node_is(expr, "module_def") ||
         ast_node_is(expr, "trait_def") ||
         ast_node_is(expr, "trait_include") ||
         /* `in NAMESPACE` was already applied at parse time; the
          * AST node is just a marker for downstream tooling. */
         ast_node_is(expr, "namespace_decl");
}

int tc_compile_ast_initializers(TcAstValue ast, TcChunk *chunk, TcError *err) {
  if (!ast_node_is(ast, "program")) {
    tc_error_set(err, "expected program AST");
    return 0;
  }
  TcAstValue *exprs = ast_get(ast, "expressions");
  if (!exprs || exprs->kind != TC_AST_ARRAY) {
    tc_error_set(err, "program AST missing expressions");
    return 0;
  }

  for (size_t i = 0; i < exprs->as.array->count; i++) {
    TcAstValue expr = exprs->as.array->items[i];
    if (ast_is_definition_node(expr)) continue;
    if (!compile_expr(expr, chunk, err) ||
        !tc_emit_op(chunk, TC_OP_POP, err)) {
      return 0;
    }
  }
  return 1;
}

int tc_compile_ast_definitions(TcAstValue ast, TcChunk *chunk, TcError *err) {
  if (!ast_node_is(ast, "program")) {
    tc_error_set(err, "expected program AST");
    return 0;
  }
  TcAstValue *exprs = ast_get(ast, "expressions");
  if (!exprs || exprs->kind != TC_AST_ARRAY) {
    tc_error_set(err, "program AST missing expressions");
    return 0;
  }

  for (size_t i = 0; i < exprs->as.array->count; i++) {
    TcAstValue expr = exprs->as.array->items[i];
    if ((ast_node_is(expr, "method_def") || ast_node_is(expr, "fn_def")) &&
        !compile_function_def(expr, NULL, 0, chunk, err)) {
      return 0;
    }
    if (ast_node_is(expr, "class_def") && !compile_class_definitions(expr, chunk, err)) return 0;
  }

  return 1;
}

int tc_compile_ast(TcAstValue ast, TcChunk *chunk, TcError *err) {
  if (!ast_node_is(ast, "program")) {
    tc_error_set(err, "expected program AST");
    return 0;
  }
  TcAstValue *exprs = ast_get(ast, "expressions");
  if (!exprs || exprs->kind != TC_AST_ARRAY) {
    tc_error_set(err, "program AST missing expressions");
    return 0;
  }

  for (size_t i = 0; i < exprs->as.array->count; i++) {
    if (!compile_expr(exprs->as.array->items[i], chunk, err)) return 0;
    if (!tc_emit_op(chunk, TC_OP_POP, err)) return 0;
  }

  if (!emit_nil(chunk, err) ||
      !tc_emit_op(chunk, TC_OP_RETURN, err)) {
    return 0;
  }

  chunk->global_count = chunk->local_count;
  return tc_compile_ast_definitions(ast, chunk, err);
}
