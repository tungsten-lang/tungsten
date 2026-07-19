        // Body of TC_OP_CALL / TC_OP_CALL_DISCARD. Included once per
        // dispatch label so the two opcodes occupy distinct code
        // addresses, giving the indirect-branch predictor a separate
        // entry per opcode kind. The label-prelude in vm.c also handles
        // CALL_DISCARD-only setup (skipping the NOP padding byte and
        // setting the discard_return flag) — by the time control reaches
        // this body, every reference is the same regardless of variant.
        uint32_t name_id = read_u32(&vm);
        uint32_t argc = read_u32(&vm);
        uint32_t has_receiver = read_u32(&vm);
        // CALL_DISCARD has a single NOP byte of padding right after the
        // operands. The label-prelude defines DISCARD_NOP_BYTES as 0
        // (CALL) or 1 (CALL_DISCARD); the compiler folds the addition.
        vm.ip += DISCARD_NOP_BYTES;
        if (name_id >= chunk->const_count || tc_kind(chunk->consts[name_id]) != TC_VAL_SYMBOL) {
          tc_error_set(err, "call name constant out of range");
          goto cleanup_fail;
        }
        TcValue stack_args[8];
        TcValue *args = NULL;
        int args_heap = 0;
        if (argc > 0) {
          if (argc <= sizeof(stack_args) / sizeof(stack_args[0])) {
            args = stack_args;
          } else {
            args = (TcValue *)calloc(argc, sizeof(TcValue));
            args_heap = 1;
            if (!args) {
              tc_error_set(err, "call argument allocation failed");
              goto cleanup_fail;
            }
          }
        }
#define FREE_ARGS() do { if (args_heap) free(args); } while (0)
        for (uint32_t i = argc; i > 0; i--) args[i - 1] = pop(&vm);
        TcValue receiver = has_receiver ? pop(&vm) : tc_box_nil();
        const char *name = tc_str_bytes_only(chunk->consts[name_id]);
        size_t name_len = tc_str_len(chunk->consts[name_id]);

        if (!has_receiver && name == NAME_ARGV) {
          FREE_ARGS();
          if (!push(&vm, tc_box_array(vm.argv), err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        // Slab-AST constructor fusion (fix #3). Dispatches
        // slab_alloc_init(kind, sc, field0, field1, ...) into the
        // bump+stores sequence natively. The compiled stages route
        // this through the :slab_alloc_init emit op which generates
        // inline LLVM IR; the C VM stage 0 handles it here so ast.w
        // constructors using slab_alloc_init self-host through stage 0.
        if (!has_receiver && name_len == 15 && memcmp(name, "slab_alloc_init", 15) == 0 && argc >= 2) {
          int64_t kind = value_is_int(args[0]) ? value_as_int(args[0]) : 0;
          int64_t sc   = value_is_int(args[1]) ? value_as_int(args[1]) : 0;
          WValue node = w_node_alloc(kind, sc);
          for (uint32_t fi = 2; fi < argc; fi++) {
            w_node_field_store(node, (int64_t)(fi - 2), args[fi]);
          }
          FREE_ARGS();
          if (!push(&vm, node, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        // PR #2 slab-AST migration: dispatch ccall_nobox calls for
        // the AST-node arena helpers natively via node_arena.c. With
        // these in place the slab side is populated during stage 0
        // interpretation, so ast.w can drop the hash-side fallback
        // entirely. Other ccall_nobox targets (json SIMD helpers, etc.)
        // aren't reachable from the bootstrap chain — they return nil.
        if (!has_receiver && name_len == 11 && memcmp(name, "ccall_nobox", 11) == 0) {
          TcValue result = tc_box_nil();
          if (argc >= 1 && tc_kind(args[0]) == TC_VAL_STRING) {
            const char *fn = tc_str_bytes_only(args[0]);
            size_t fn_len = tc_str_len(args[0]);
            if (fn_len == 12 && memcmp(fn, "w_node_alloc", 12) == 0 && argc == 3) {
              int64_t kind = value_is_int(args[1]) ? value_as_int(args[1]) : 0;
              int64_t sc   = value_is_int(args[2]) ? value_as_int(args[2]) : 0;
              result = w_node_alloc(kind, sc);
            } else if (fn_len == 18 && memcmp(fn, "w_node_field_store", 18) == 0 && argc == 4) {
              WValue wnode = args[1];
              int64_t off  = value_is_int(args[2]) ? value_as_int(args[2]) : 0;
              WValue val   = args[3];
              w_node_field_store(wnode, off, val);
            } else if (fn_len == 17 && memcmp(fn, "w_node_field_load", 17) == 0 && argc == 3) {
              WValue wnode = args[1];
              int64_t off  = value_is_int(args[2]) ? value_as_int(args[2]) : 0;
              result = w_node_field_load(wnode, off);
            } else if (fn_len == 16 && memcmp(fn, "w_ast_sparse_set", 16) == 0 && argc == 4) {
              /* PR #3 sparse store: node and sym are opaque WValue-bit
               * keys (symbols are interned, so stable per process). */
              result = w_ast_sparse_set(args[1], (int64_t)args[2], args[3]);
            } else if (fn_len == 16 && memcmp(fn, "w_ast_sparse_get", 16) == 0 && argc == 3) {
              result = w_ast_sparse_get(args[1], (int64_t)args[2]);
            } else if (fn_len == 17 && memcmp(fn, "w_ast_sparse_copy", 17) == 0 && argc == 3) {
              result = w_ast_sparse_copy(args[1], args[2]);
            } else if (fn_len == 17 && memcmp(fn, "w_ast_intern_node", 17) == 0 && argc == 3) {
              /* Inline interned leaf kinds (schema sentinel 257):
               * intern the string content, embed the dense id in the
               * W_PACKED_NODE offset bits — no arena bump. Mirrors
               * runtime.c's w_ast_intern_node; the VM extracts the
               * bytes here because node_arena.c can't decode TcValue
               * strings. */
              int64_t kind = value_is_int(args[1]) ? value_as_int(args[1]) : 0;
              if (tc_kind(args[2]) == TC_VAL_STRING) {
                const char *sb = tc_str_bytes_only(args[2]);
                size_t sl = tc_str_len(args[2]);
                result = (TcValue)w_ast_intern_node_bytes(kind, sb, sl,
                                                          (uint64_t)args[2]);
              }
            } else if (fn_len == 19 && memcmp(fn, "w_ast_intern_str_of", 19) == 0 && argc == 2) {
              /* Sentinel-257 read: intern id in the offset bits → the
               * stored VM string value (first one seen per content). */
              uint64_t sv = w_ast_intern_value_of((uint64_t)args[1]);
              if (sv != 0) result = (TcValue)sv;
            } else if (fn_len == 18 && memcmp(fn, "w_node_kind_extern", 18) == 0 && argc == 2) {
              // Extract the 11-bit kind field from a W_PACKED_NODE
              // WValue. Used by ast_kind on bare W_PACKED_NODE input
              // to look up the kind symbol via kind_sym_table_data.
              // Same name as the runtime/runtime.c shim — kept that
              // way so the Tungsten ccall site uses one symbol that
              // resolves identically in both stages.
              WValue wnode = args[1];
              result = int_value((int64_t)w_node_kind(wnode));
            } else if (fn_len == 16 && memcmp(fn, "w_is_node_extern", 16) == 0 && argc == 2) {
              // Test if a WValue is a packed AST node. Used by
              // is_ast_node? after constructors return bare
              // W_PACKED_NODE WValues — `type(node) == "Hash"` no
              // longer correctly identifies AST nodes once the hash
              // wrapper is gone.
              WValue v = args[1];
              result = int_value(w_is_node(v) ? 1 : 0);
            } else if (fn_len == 19 && memcmp(fn, "w_make_token_extern", 19) == 0 && argc == 4) {
              // Construct a W_LEXICAL_TOKEN packed i64 from (type, len, off).
              // Used by core/token.w `Token.make`. Crossing the C boundary
              // preserves the full 64-bit pattern with W_TAG_CHAR bits.
              int64_t type = value_is_int(args[1]) ? value_as_int(args[1]) : 0;
              int64_t len  = value_is_int(args[2]) ? value_as_int(args[2]) : 0;
              int64_t off  = value_is_int(args[3]) ? value_as_int(args[3]) : 0;
              result = w_box_token(0, (int)type, (int)len, (int)off);
            } else if (fn_len == 19 && memcmp(fn, "w_token_type_extern", 19) == 0 && argc == 2) {
              result = int_value((int64_t)w_unbox_token_type(args[1]));
            } else if (fn_len == 21 && memcmp(fn, "w_token_offset_extern", 21) == 0 && argc == 2) {
              result = int_value((int64_t)w_unbox_token_offset(args[1]));
            } else if (fn_len == 21 && memcmp(fn, "w_token_length_extern", 21) == 0 && argc == 2) {
              result = int_value((int64_t)w_unbox_token_length(args[1]));
            } else if (fn_len == 16 && memcmp(fn, "w_numeric_to_i64", 16) == 0 && argc == 2) {
              /* Packed lexical tokens use the full 64-bit WValue pattern and
               * may materialize as BigInt-like values in the source parser.
               * The production parser normalizes them through this runtime
               * helper before shifts; stage 0 must mirror that ccall_nobox. */
              int64_t raw = value_is_int(args[1]) ? value_as_int(args[1]) : (int64_t)args[1];
              result = int_value(raw);
            } else if (fn_len == 18 && memcmp(fn, "w_is_ast_node_full", 18) == 0 && argc == 3) {
              // Fused is_ast_node? check (fix #5): nil/W_PACKED_NODE/
              // Hash-with-:node in a single dispatch. Mirrors
              // runtime.c.
              TcValue x = args[1];
              TcValue node_sym = args[2];
              int r = 0;
              if (tc_kind(x) == TC_VAL_NIL) {
                r = 0;
              } else if (w_is_node(x)) {
                r = 1;
              } else if (tc_kind(x) == TC_VAL_HASH) {
                TcRuntimeHash *h = tc_as_hash(x);
                /* Probe the hash for the :node symbol key. */
                if (h) {
                  for (size_t i = 0; i < h->cap; i++) {
                    if (h->keys[i] == node_sym) {
                      r = (tc_kind(h->values[i]) != TC_VAL_NIL) ? 1 : 0;
                      break;
                    }
                  }
                }
              }
              result = int_value((int64_t)r);
            } else if (fn_len == 16 && memcmp(fn, "w_node_singleton", 16) == 0 && argc == 2) {
              // Tag-only singleton encoding for ast.w. Returns the
              // W_PACKED_NODE bit pattern with sc=0 and offset=0 for
              // ast_nil/ast_break/ast_next/ast_self/ast_view_*.
              // No arena bump — the reserved slot 0 (cursor starts
              // at 1) means real allocations never collide.
              int64_t kind = value_is_int(args[1]) ? value_as_int(args[1]) : 0;
              if (kind < 32) {
                result = w_box_node_compact((int)kind, /*payload*/ 0);
              } else {
                result = w_box_node((int)kind, /*sc*/ 0, /*off*/ 0);
              }
            } else if (fn_len == 18 && memcmp(fn, "w_ast_bool_cached", 17) == 0 && fn[17] == 0) {
              // unused 18-byte case
            } else if (fn_len == 21 && memcmp(fn, "w_node_inline_payload", 21) == 0 && argc == 3) {
              // Inline-encoded AST node with int payload in offset
              // bits (fix #3: :char/:lambda_arity/:superscript/
              // :regex_capture/:parg). Mirror of runtime.c.
              int64_t kind = value_is_int(args[1]) ? value_as_int(args[1]) : 0;
              int64_t payload = value_is_int(args[2]) ? value_as_int(args[2]) : 0;
              result = w_box_node((int)kind, /*sc*/ 0, (uint64_t)payload & 0xFFFFFFFFu);
            } else if (fn_len == 20 && memcmp(fn, "w_node_offset_extern", 20) == 0 && argc == 2) {
              // Extract the 32-bit offset bits of a W_PACKED_NODE
              // for inline-payload decoding.
              result = int_value((int64_t)w_node_offset(args[1]));
            } else if (fn_len == 17 && memcmp(fn, "w_ast_bool_cached", 17) == 0 && argc == 2) {
              // Cached :bool AST node (fix #7). Mirrors runtime.c —
              // one slab allocation per truthiness, cached thereafter.
              int64_t truthy = value_is_int(args[1]) ? value_as_int(args[1]) : 0;
              int idx = truthy ? 1 : 0;
              static WValue cached[2] = {0, 0};
              if (cached[idx] == 0) {
                WValue n = w_node_alloc(/*KIND_BOOL=*/39, /*SC_2=*/0);
                w_node_field_store(n, 0, truthy ? /*W_TRUE=*/2 : /*W_FALSE=*/1);
                cached[idx] = n;
              }
              result = cached[idx];
            } else if (fn_len == 15 && memcmp(fn, "w_location_file", 15) == 0 && argc == 4) {
              // Build a fully tagged W_PACKED_LOCATION WValue
              // (mode 1 = File). The parser's make_loc dispatches
              // here so the :loc / :loc_end slab slots hold proper
              // Location WValues. w_box_location_file is a static
              // inline in wvalue.h — no link dependency on
              // runtime.c's w_location_file wrapper.
              int64_t file_id = value_is_int(args[1]) ? value_as_int(args[1]) : 0;
              int64_t line    = value_is_int(args[2]) ? value_as_int(args[2]) : 0;
              int64_t col     = value_is_int(args[3]) ? value_as_int(args[3]) : 0;
              result = w_box_location_file((int)file_id, (int)line, (int)col);
            } else if (fn_len == 22 && memcmp(fn, "w_location_file_offset", 22) == 0 && argc == 3) {
              // FileOffset mode (byte offset instead of line/col) —
              // mirrors w_location_file above, one fewer argument.
              int64_t file_id = value_is_int(args[1]) ? value_as_int(args[1]) : 0;
              int64_t offset  = value_is_int(args[2]) ? value_as_int(args[2]) : 0;
              result = w_box_location_file_offset((int)file_id, (uint32_t)offset);
            } else if (fn_len == 28 && memcmp(fn, "w_unbox_location_line_extern", 28) == 0 && argc == 2) {
              // Extract the 18-bit line field (bits 11-28) from a
              // tagged W_PACKED_LOCATION WValue. Used by Node.line
              // and Location.line accessors when :loc holds a real
              // Location WValue rather than a NaN-boxed int.
              result = int_value((int64_t)w_unbox_location_line((WValue)args[1]));
            } else if (fn_len == 27 && memcmp(fn, "w_unbox_location_col_extern", 27) == 0 && argc == 2) {
              // Extract the 11-bit col field (bits 0-10).
              result = int_value((int64_t)w_unbox_location_col((WValue)args[1]));
            } else if (fn_len == 31 && memcmp(fn, "w_unbox_location_file_id_extern", 31) == 0 && argc == 2) {
              // Extract the 14-bit file_id field (bits 29-42).
              result = int_value((int64_t)w_unbox_location_file_id((WValue)args[1]));
            } else if (fn_len == 30 && memcmp(fn, "w_unbox_location_offset_extern", 30) == 0 && argc == 2) {
              // Extract the 29-bit byte offset field (FileOffset mode).
              result = int_value((int64_t)w_unbox_location_offset((WValue)args[1]));
            } else if (fn_len == 19 && memcmp(fn, "w_loc_register_file", 19) == 0 && argc == 4) {
              // Register a file's per-codepoint line/col tables and
              // return its file_id, for embedding in FileOffset
              // locations. tc_loc_register_file (vm.c) is the C VM's
              // own copy of runtime.c's w_loc_register_file — see its
              // comment for why a Tungsten-level global was unreliable
              // here, and why this isn't shared across the two (they're
              // separate processes with nothing to share regardless).
              result = int_value((int64_t)tc_loc_register_file((TcValue)args[1], (TcValue)args[2], (TcValue)args[3]));
            } else if (fn_len == 21 && memcmp(fn, "w_loc_line_for_offset", 21) == 0 && argc == 3) {
              int64_t fid = value_is_int(args[1]) ? value_as_int(args[1]) : -1;
              int64_t off = value_is_int(args[2]) ? value_as_int(args[2]) : -1;
              int line = tc_loc_line_for_offset((int)fid, (int)off);
              result = line < 0 ? W_NIL : int_value((int64_t)line);
            } else if (fn_len == 20 && memcmp(fn, "w_loc_col_for_offset", 20) == 0 && argc == 3) {
              int64_t fid = value_is_int(args[1]) ? value_as_int(args[1]) : -1;
              int64_t off = value_is_int(args[2]) ? value_as_int(args[2]) : -1;
              int col = tc_loc_col_for_offset((int)fid, (int)off);
              result = col < 0 ? W_NIL : int_value((int64_t)col);
            }
          }
          FREE_ARGS();
          if (!push(&vm, result, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        // Keep compiler-driver diagnostics on stderr when a rescue path runs
        // under the stage-0 VM. Native stages call runtime.c's w_eputs.
        if (!has_receiver && name_len == 5 && memcmp(name, "ccall", 5) == 0 && argc == 2
            && tc_kind(args[0]) == TC_VAL_STRING
            && tc_str_len(args[0]) == 7
            && memcmp(tc_str_bytes_only(args[0]), "w_eputs", 7) == 0) {
          tc_value_print(args[1], stderr);
          fputc('\n', stderr);
          fflush(stderr);
          FREE_ARGS();
          if (!push(&vm, tc_box_nil(), err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        // Slab-AST fused kind-extract + table lookup (fix #5).
        // ast_kind in compiler/lib/ast.w dispatches
        //   ccall("w_node_kind_sym", node, kind_sym_table_data)
        // to avoid the w_int boxing round-trip + kind_sym_for_id
        // function-call boundary it'd otherwise pay. The C VM
        // resolves it natively here so stage 0 produces matching IR.
        if (!has_receiver && name_len == 5 && memcmp(name, "ccall", 5) == 0 && argc == 3
            && tc_kind(args[0]) == TC_VAL_STRING
            && tc_str_len(args[0]) == 15
            && memcmp(tc_str_bytes_only(args[0]), "w_node_kind_sym", 15) == 0) {
          int kind_id = w_node_kind(args[1]);
          TcValue r = tc_box_nil();
          // Bound mirrors compiler/lib/ast_schema.w KIND_MAX. Must
          // move in lockstep with runtime/runtime.c's w_node_kind_sym.
          if (kind_id >= 0 && kind_id <= 147 && tc_kind(args[2]) == TC_VAL_ARRAY) {
            TcRuntimeArray *arr = tc_as_array(args[2]);
            if (arr && kind_id < arr->size) {
              r = arr->slots[arr->start + kind_id];
            }
          }
          FREE_ARGS();
          if (!push(&vm, r, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (!has_receiver && name == NAME_EXIT) {
          if (argc > 0 && !value_is_int(args[0])) {
            FREE_ARGS();
            tc_error_set(err, "exit status must be integer");
            goto cleanup_fail;
          }
          vm.process_status = argc > 0 ? (int)value_as_int(args[0]) : 0;
          FREE_ARGS();
          *result = tc_box_nil();
          goto cleanup_ok;
        }
        if (!has_receiver && name == NAME_RAISE) {
          // Format the raised value for error output, then propagate as a
          // VM error. Hash payloads (the compiler's structured error shape:
          // {rt: :compile_error, message: "...", file: "...", row: N, col: N})
          // get unpacked so the error message is human-readable.
          char msg_buf[1024];
          msg_buf[0] = '\0';
          TcValue val = argc >= 1 ? args[0] : tc_box_nil();
          if (tc_kind(val) == TC_VAL_HASH && tc_as_hash(val)) {
            const char *message = NULL; size_t message_len = 0;
            const char *file = NULL; size_t file_len = 0;
            int64_t row = 0, col = 0;
            for (size_t i = 0; i < tc_as_hash(val)->cap; i++) {
              TcValue k = tc_as_hash(val)->keys[i];
              if (k == TC_HASH_EMPTY || k == TC_HASH_TOMBSTONE) continue;
              TcValue v = tc_as_hash(val)->values[i];
              if (tc_kind(k) != TC_VAL_SYMBOL) continue;
              const char *kb = tc_str_bytes_only(k);
              size_t kl = tc_str_len(k);
              if (kl == 7 && memcmp(kb, "message", 7) == 0 && tc_kind(v) == TC_VAL_STRING) {
                message = tc_str_bytes_only(v); message_len = tc_str_len(v);
              } else if (kl == 4 && memcmp(kb, "file", 4) == 0 && tc_kind(v) == TC_VAL_STRING) {
                file = tc_str_bytes_only(v); file_len = tc_str_len(v);
              } else if (kl == 3 && memcmp(kb, "row", 3) == 0 && value_is_int(v)) {
                row = value_as_int(v);
              } else if (kl == 3 && memcmp(kb, "col", 3) == 0 && value_is_int(v)) {
                col = value_as_int(v);
              }
            }
            if (message) {
              if (file) {
                snprintf(msg_buf, sizeof(msg_buf), "%.*s:%lld:%lld: %.*s",
                         (int)file_len, file, (long long)row, (long long)col,
                         (int)message_len, message);
              } else {
                snprintf(msg_buf, sizeof(msg_buf), "%.*s", (int)message_len, message);
              }
            } else {
              snprintf(msg_buf, sizeof(msg_buf), "raise: <hash>");
            }
          } else if (tc_kind(val) == TC_VAL_STRING) {
            snprintf(msg_buf, sizeof(msg_buf), "%.*s",
                     (int)tc_str_len(val), tc_str_bytes_only(val));
          } else {
            snprintf(msg_buf, sizeof(msg_buf), "raise: <%s>", value_type_name(val));
          }
          FREE_ARGS();
          tc_error_set(err, "%s", msg_buf);
          goto cleanup_fail;
        }
        if (!has_receiver && name == NAME_ENV && argc == 1 && tc_kind(args[0]) == TC_VAL_STRING) {
          const char *value = getenv(tc_str_bytes_only(args[0]));
          FREE_ARGS();
          if (!value) {
            if (!push(&vm, tc_box_nil(), err)) {
              goto cleanup_fail;
            }
          } else {
            TcValue out;
            if (!make_string_value(value, strlen(value), &out, err) || !push(&vm, out, err)) {
              goto cleanup_fail;
            }
          }
          CNEXT();
        }
        if (!has_receiver && name == NAME_FILE_Q && argc == 1 && tc_kind(args[0]) == TC_VAL_STRING) {
          FILE *file = fopen(tc_str_bytes_only(args[0]), "rb");
          int exists = file != NULL;
          if (file) fclose(file);
          FREE_ARGS();
          if (!push(&vm, tc_box_wvalue(exists ? W_TRUE : W_FALSE), err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (!has_receiver && name == NAME_RUNTIME_IDENTITY && argc == 0) {
          FREE_ARGS();
          TcValue out;
          if (!make_string_value("tungsten-c", 10, &out, err) || !push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (!has_receiver && name == NAME_CLOCK && argc == 0) {
          FREE_ARGS();
          int64_t ticks = (int64_t)clock();
          if (!push(&vm, int_value(ticks), err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (!has_receiver && name == NAME_TYPE && argc == 1) {
          const char *type_name = value_type_name(args[0]);
          FREE_ARGS();
          TcValue out;
          if (!make_string_value(type_name, strlen(type_name), &out, err) || !push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (!has_receiver && name == NAME_STRING_BUFFER) {
          size_t initial_cap = 16;
          if (argc > 0 && value_is_int(args[0])) {
            int64_t requested = value_as_int(args[0]);
            if (requested > 0) initial_cap = (size_t)requested;
          }
          FREE_ARGS();
          TcRuntimeObject *buffer = runtime_string_buffer_new(initial_cap, err);
          if (!buffer || !push(&vm, tc_box_object(buffer), err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (!has_receiver && name == NAME_WYHASH64_HEX_STRING &&
            argc == 1) {
          TcValue out;
          if (!wyhash64_hex_string_value(args[0], &out, err)) {
            FREE_ARGS();
            goto cleanup_fail;
          }
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (!has_receiver && name == NAME_READ_FILE && argc == 1 && tc_kind(args[0]) == TC_VAL_STRING) {
          size_t len = 0;
          unsigned char *bytes = tc_read_file(tc_str_bytes_only(args[0]), &len, err);
          FREE_ARGS();
          if (!bytes) {
            tc_error_free(err);
            if (!push(&vm, tc_box_nil(), err)) {
              goto cleanup_fail;
            }
          } else {
            TcValue out;
            int ok = make_string_value((const char *)bytes, len, &out, err);
            free(bytes);
            if (!ok || !push(&vm, out, err)) {
              goto cleanup_fail;
            }
          }
          CNEXT();
        }
        if (!has_receiver && name == NAME_WRITE_FILE && argc == 2 &&
            tc_kind(args[0]) == TC_VAL_STRING && tc_kind(args[1]) == TC_VAL_STRING) {
          FILE *file = fopen(tc_str_bytes_only(args[0]), "wb");
          if (!file) {
            tc_error_set(err, "write_file open failed: %.*s", (int)tc_str_len(args[0]), tc_str_bytes_only(args[0]));
            FREE_ARGS();
            goto cleanup_fail;
          }
          size_t wrote = fwrite(tc_str_bytes_only(args[1]), 1, tc_str_len(args[1]), file);
          fclose(file);
          int ok = wrote == tc_str_len(args[1]);
          FREE_ARGS();
          if (!push(&vm, tc_box_wvalue(ok ? W_TRUE : W_FALSE), err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (!has_receiver && name == NAME_SYSTEM && argc == 1 &&
            tc_kind(args[0]) == TC_VAL_STRING) {
          // TUNGSTEN_C_NO_SYSTEM=1 short-circuits external commands so
          // VM-only profiling isn't dominated by clang/clock waits.
          const char *no_sys = getenv("TUNGSTEN_C_NO_SYSTEM");
          int rc = (no_sys && no_sys[0] == '1') ? 0 : system(tc_str_bytes_only(args[0]));
          FREE_ARGS();
          if (!push(&vm, tc_box_wvalue(rc == 0 ? W_TRUE : W_FALSE), err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (!has_receiver && name == NAME_CAPTURE && argc == 1 &&
            tc_kind(args[0]) == TC_VAL_STRING) {
          FILE *pipe = popen(tc_str_bytes_only(args[0]), "r");
          if (!pipe) {
            FREE_ARGS();
            TcValue out;
            if (!make_string_value("", 0, &out, err) || !push(&vm, out, err)) {
              goto cleanup_fail;
            }
            CNEXT();
          }
          size_t cap = 256;
          size_t len = 0;
          char *buf = (char *)malloc(cap);
          if (!buf) {
            pclose(pipe);
            tc_error_set(err, "capture allocation failed");
            FREE_ARGS();
            goto cleanup_fail;
          }
          int ch;
          while ((ch = fgetc(pipe)) != EOF) {
            if (len + 1 >= cap) {
              cap *= 2;
              char *next = (char *)realloc(buf, cap);
              if (!next) {
                free(buf);
                pclose(pipe);
                tc_error_set(err, "capture growth failed");
                FREE_ARGS();
                goto cleanup_fail;
              }
              buf = next;
            }
            buf[len++] = (char)ch;
          }
          pclose(pipe);
          buf[len] = '\0';
          FREE_ARGS();
          TcValue out;
          int ok = make_string_value(buf, len, &out, err);
          free(buf);
          if (!ok || !push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (!has_receiver && name_len > 4 && memcmp(name + name_len - 4, ".new", 4) == 0) {
          size_t class_len = name_len - 4;
          // Slab role: skip the auto-allocated TcRuntimeObject. The
          // body's return value (e.g. a W_PACKED_NODE from
          // slab_alloc_init) becomes the result. Lets compiler's slab
          // classes inline their constructor body into .new without
          // the wrapper-object indirection that breaks ast_kind /
          // ast_get on the result.
          int is_slab = chunk->ctor_is_slab ? chunk->ctor_is_slab[name_id] :
                                                tc_chunk_is_slab_class(chunk, name, class_len);
          TcFunction *fn = chunk->ctor_fn_for_const ? chunk->ctor_fn_for_const[name_id] :
                                                       tc_chunk_find_method(chunk, name, class_len, "new", 3);
          if (!fn) {
            tc_error_set(err, "missing initializer for class: %.*s", (int)class_len, name);
            FREE_ARGS();
            goto cleanup_fail;
          }
          if (is_slab) {
            // Static-method dispatch: no self, no return override.
            // The body must compute and return the slab node directly.
            if (!vm_call_function(&vm, fn, args, argc, tc_box_nil(), 0, tc_box_nil(), 0, err)) {
              FREE_ARGS();
              goto cleanup_fail;
            }
          } else {
            TcRuntimeObject *object = runtime_object_new(name, class_len, err);
            if (!object) {
              FREE_ARGS();
              goto cleanup_fail;
            }
            TcValue object_value = tc_box_object(object);
            if (!vm_call_function(&vm, fn, args, argc, object_value, 1, object_value, 1, err)) {
              FREE_ARGS();
              goto cleanup_fail;
            }
          }
          FREE_ARGS();
          NEXT();
        }
        if (!has_receiver) {
          // Fast path: name_id → TcFunction* was precomputed at chunk
          // finalize. Skips the per-call O(N) name walk in
          // tc_chunk_find_function for receiverless plain calls (the
          // dominant user-fn dispatch shape, e.g. `lower_var(ctx, node)`).
          TcFunction *fn = chunk->fn_for_const ? chunk->fn_for_const[name_id] : NULL;
          if (fn) {
            if (!vm_call_function(&vm, fn, args, argc, tc_box_nil(), 0,
                                  tc_box_nil(), 0, err)) {
              FREE_ARGS();
              goto cleanup_fail;
            }
            FREE_ARGS();
            NEXT();
          }
          int self_slot = find_self_slot(chunk);
          if (self_slot >= 0 && tc_kind(vm.locals[self_slot]) == TC_VAL_OBJECT && tc_as_object(vm.locals[self_slot])) {
            TcValue self = vm.locals[self_slot];
            const char *cn = tc_as_object(self)->class_name;
            size_t cn_len = tc_as_object(self)->class_name_len;
            // IC hit: same class as last call → reuse cached fn. Class
            // names are interned bytes, so pointer + length identity
            // is exact (no memcmp).
            TcFunction *fn = NULL;
            if (chunk->method_ic_class &&
                chunk->method_ic_class[name_id] == cn &&
                chunk->method_ic_class_len[name_id] == cn_len) {
              fn = chunk->method_ic_fn[name_id];
            } else {
              fn = tc_chunk_find_method(chunk, cn, cn_len, name, name_len);
              if (fn && chunk->method_ic_class) {
                chunk->method_ic_class[name_id] = cn;
                chunk->method_ic_class_len[name_id] = cn_len;
                chunk->method_ic_fn[name_id] = fn;
              }
            }
            if (fn) {
              if (!vm_call_function(&vm, fn, args, argc, self, 1,
                                    tc_box_nil(), 0, err)) {
                FREE_ARGS();
                goto cleanup_fail;
              }
              FREE_ARGS();
              NEXT();
            }
          }
        }
        // Reordered hot path: name == NAME_BRACKETS dominates stage-1
        // CALL dispatches (60%). Hoisting these blocks before the SIZE
        // matcher saves ~14M misses/run on BRACKETS calls.
        if (has_receiver && name == NAME_BRACKETS &&
            tc_kind(receiver) == TC_VAL_STRING && argc == 1 &&
            value_is_int(args[0])) {
          int64_t idx = value_as_int(args[0]);
          TcValue out = tc_box_nil();
          if (idx >= 0 && (size_t)idx < tc_str_len(receiver) &&
              !make_string_value(tc_str_bytes_only(receiver) + idx, 1, &out, err)) {
            FREE_ARGS();
            goto cleanup_fail;
          }
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_BRACKETS &&
            tc_kind(receiver) == TC_VAL_AST && argc == 1) {
          TcValue out;
          if (tc_as_ast_ptr(&receiver)->kind == TC_AST_ARRAY && tc_as_ast_ptr(&receiver)->as.array &&
              value_is_int(args[0])) {
            int64_t idx = value_as_int(args[0]);
            if (idx >= 0 && (size_t)idx < tc_as_ast_ptr(&receiver)->as.array->count) {
              if (!ast_to_value(tc_as_ast_ptr(&receiver)->as.array->items[idx], &out, err)) {
                FREE_ARGS();
                goto cleanup_fail;
              }
            } else {
              out = tc_box_nil();
            }
          } else if (tc_as_ast_ptr(&receiver)->kind == TC_AST_HASH) {
            if (!ast_hash_lookup(*tc_as_ast_ptr(&receiver), args[0], &out, err)) {
              FREE_ARGS();
              goto cleanup_fail;
            }
          } else {
            out = tc_box_nil();
          }
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_BRACKETS &&
            tc_kind(receiver) == TC_VAL_ARRAY && tc_as_array(receiver) && argc == 1 &&
            value_is_int(args[0])) {
          int64_t idx = value_as_int(args[0]);
          TcValue out = (idx >= 0 && (size_t)idx < tc_as_array(receiver)->size)
                            ? tc_as_array(receiver)->slots[idx]
                            : tc_box_nil();
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_BRACKETS &&
            tc_kind(receiver) == TC_VAL_HASH && tc_as_hash(receiver) && argc == 1) {
          TcValue out = hash_get_value(tc_as_hash(receiver), args[0]);
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_SIZE) {
          /* Fast path ONLY for receivers whose size this arm actually
           * knows. Anything else (user objects with a `size` method, and
           * notably StringBuffer) must FALL THROUGH to normal dispatch —
           * the previous unconditional `size = 0` here silently answered
           * 0 for StringBuffer, which emptied every `%w[...]` literal the
           * self-hosted lexer scanned under stage 0 (the word-flush guard
           * is `if word.size() > 0`) and broke stage1==stage2 identity. */
          int64_t size = 0;
          int known = 1;
          if (tc_kind(receiver) == TC_VAL_STRING) size = (int64_t)tc_str_len(receiver);
          else if (tc_kind(receiver) == TC_VAL_ARRAY && tc_as_array(receiver)) size = (int64_t)tc_as_array(receiver)->size;
          else if (tc_kind(receiver) == TC_VAL_HASH && tc_as_hash(receiver)) size = (int64_t)tc_as_hash(receiver)->count;
          else if (tc_kind(receiver) == TC_VAL_OBJECT && tc_as_object(receiver) &&
                   object_is_class(tc_as_object(receiver), "StringBuffer", 12)) {
            size = (int64_t)tc_as_object(receiver)->buffer_len;
          }
          else if (tc_kind(receiver) == TC_VAL_AST && tc_as_ast_ptr(&receiver)->kind == TC_AST_ARRAY && tc_as_ast_ptr(&receiver)->as.array) {
            size = (int64_t)tc_as_ast_ptr(&receiver)->as.array->count;
          } else if (tc_kind(receiver) == TC_VAL_AST && tc_as_ast_ptr(&receiver)->kind == TC_AST_HASH && tc_as_ast_ptr(&receiver)->as.hash) {
            size = (int64_t)tc_as_ast_ptr(&receiver)->as.hash->count;
          } else if (tc_kind(receiver) == TC_VAL_OBJECT && tc_as_object(receiver) &&
                     object_is_class(tc_as_object(receiver), "StringBuffer", 12)) {
            size = (int64_t)tc_as_object(receiver)->buffer_len;
          } else {
            known = 0;
          }
          if (known) {
            FREE_ARGS();
            if (!push(&vm, int_value(size), err)) {
              goto cleanup_fail;
            }
            CNEXT();
          }
        }
        if (has_receiver && name == NAME_BRACKETS_SET && argc == 2) {
          // Promote AST values before storing — see promote_ast_value
          // comment. Without this, array stores of TC_VAL_AST values
          // would lock the element to an immutable AST node.
          if (!promote_ast_value(&args[1], err)) {
            FREE_ARGS();
            goto cleanup_fail;
          }
          TcValue out = args[1];
          if (tc_kind(receiver) == TC_VAL_ARRAY && tc_as_array(receiver) && value_is_int(args[0])) {
            int64_t idx = value_as_int(args[0]);
            if (idx >= 0) {
              size_t uidx = (size_t)idx;
              if ((int32_t)uidx >= tc_as_array(receiver)->size) {
                if (!runtime_array_ensure_cap(tc_as_array(receiver), uidx + 1, err)) {
                  FREE_ARGS();
                  goto cleanup_fail;
                }
                for (int32_t j = tc_as_array(receiver)->size; j <= (int32_t)uidx; j++) {
                  tc_as_array(receiver)->slots[j] = tc_box_nil();
                }
                tc_as_array(receiver)->size = (int32_t)(uidx + 1);
              }
              tc_as_array(receiver)->slots[uidx] = args[1];
            }
          } else if (tc_kind(receiver) == TC_VAL_HASH && tc_as_hash(receiver)) {
            if (!hash_set_value(tc_as_hash(receiver), args[0], args[1], err)) {
              FREE_ARGS();
              goto cleanup_fail;
            }
          }
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_DELETE && argc == 1 &&
            tc_kind(receiver) == TC_VAL_HASH && tc_as_hash(receiver)) {
          TcValue out = hash_delete_value(tc_as_hash(receiver), args[0]);
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        // Reordered hot path: PUSH 1.6%, TO_S 1.3%, LSHIFT 4.5%,
        // RSHIFT 1.1%. Hoisted to right after BRACKETS+SIZE+BRACKETS_SET
        // — together they cover ~85% of stage-1 receiver-method calls.
        if (has_receiver && name == NAME_PUSH && argc > 0 &&
            tc_kind(receiver) == TC_VAL_ARRAY && tc_as_array(receiver)) {
          // Promote AST args before they enter the array.
          for (uint32_t i = 0; i < argc; i++) {
            if (!promote_ast_value(&args[i], err)) {
              FREE_ARGS();
              goto cleanup_fail;
            }
          }
          if (!runtime_array_ensure_cap(tc_as_array(receiver), tc_as_array(receiver)->size + argc, err)) {
            FREE_ARGS();
            goto cleanup_fail;
          }
          for (uint32_t i = 0; i < argc; i++) tc_as_array(receiver)->slots[tc_as_array(receiver)->size++] = args[i];
          FREE_ARGS();
          if (!push(&vm, receiver, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_TO_S) {
          if (tc_kind(receiver) == TC_VAL_STRING || tc_kind(receiver) == TC_VAL_SYMBOL) {
            TcValue out = tc_box_string_bytes(tc_str_bytes_only(receiver), tc_str_len(receiver), tc_managed(receiver));
            FREE_ARGS();
            if (!push(&vm, out, err)) {
              goto cleanup_fail;
            }
            CNEXT();
          }
          char *text = NULL;
          size_t len = 0;
          if (!value_to_string_copy(receiver, &text, &len, err)) {
            FREE_ARGS();
            goto cleanup_fail;
          }
          FREE_ARGS();
          TcValue out;
          int ok = make_string_value(text, len, &out, err);
          free(text);
          if (!ok || !push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && argc == 1 && tc_kind(receiver) == TC_VAL_OBJECT &&
            object_is_class(tc_as_object(receiver), "StringBuffer", 12) &&
            ((name == NAME_LSHIFT) ||
             (name == NAME_APPEND) ||
             (name == NAME_CONCAT))) {
          if (!runtime_string_buffer_append(tc_as_object(receiver), args[0], err)) {
            FREE_ARGS();
            goto cleanup_fail;
          }
          FREE_ARGS();
          if (!push(&vm, receiver, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_LSHIFT && argc == 1) {
          if (value_is_int(receiver) && value_is_int(args[0])) {
            TcValue out = int_value(value_as_int(receiver) << value_as_int(args[0]));
            FREE_ARGS();
            if (!push(&vm, out, err)) {
              goto cleanup_fail;
            }
            CNEXT();
          }
          TcValue out;
          if (!concat_values(receiver, args[0], &out, err)) {
            FREE_ARGS();
            goto cleanup_fail;
          }
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_RSHIFT && argc == 1 &&
            value_is_int(receiver) && value_is_int(args[0])) {
          TcValue out = int_value(value_as_int(receiver) >> value_as_int(args[0]));
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_STARTS_WITH_Q &&
            tc_kind(receiver) == TC_VAL_STRING && argc == 1 && tc_kind(args[0]) == TC_VAL_STRING) {
          int ok = tc_str_len(receiver) >= tc_str_len(args[0]) && memcmp(tc_str_bytes_only(receiver), tc_str_bytes_only(args[0]), tc_str_len(args[0])) == 0;
          FREE_ARGS();
          if (!push(&vm, tc_box_wvalue(ok ? W_TRUE : W_FALSE), err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_ENDS_WITH_Q &&
            tc_kind(receiver) == TC_VAL_STRING && argc == 1 && tc_kind(args[0]) == TC_VAL_STRING) {
          int ok = tc_str_len(receiver) >= tc_str_len(args[0]) &&
                   memcmp(tc_str_bytes_only(receiver) + tc_str_len(receiver) - tc_str_len(args[0]), tc_str_bytes_only(args[0]), tc_str_len(args[0])) == 0;
          FREE_ARGS();
          if (!push(&vm, tc_box_wvalue(ok ? W_TRUE : W_FALSE), err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_INCLUDE_Q && argc == 1) {
          int ok = 0;
          if (tc_kind(receiver) == TC_VAL_STRING && tc_kind(args[0]) == TC_VAL_STRING) {
            TcValue idx;
            if (!string_index_value(receiver, args[0], &idx, err)) {
              FREE_ARGS();
              goto cleanup_fail;
            }
            ok = tc_kind(idx) != TC_VAL_NIL;
          } else if (tc_kind(receiver) == TC_VAL_ARRAY && tc_as_array(receiver)) {
            for (size_t i = 0; i < tc_as_array(receiver)->size; i++) {
              if (value_equal(tc_as_array(receiver)->slots[i], args[0])) {
                ok = 1;
                break;
              }
            }
          }
          FREE_ARGS();
          if (!push(&vm, tc_box_wvalue(ok ? W_TRUE : W_FALSE), err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_EMPTY_Q && argc == 0) {
          int ok = (tc_kind(receiver) == TC_VAL_STRING && tc_str_len(receiver) == 0) ||
                   (tc_kind(receiver) == TC_VAL_ARRAY && tc_as_array(receiver) && tc_as_array(receiver)->size == 0) ||
                   tc_kind(receiver) == TC_VAL_NIL;
          FREE_ARGS();
          if (!push(&vm, tc_box_wvalue(ok ? W_TRUE : W_FALSE), err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && argc == 2 &&
            ((name == NAME_REPLACE) ||
             (name == NAME_GSUB))) {
          TcValue out;
          if (!string_replace_all(receiver, args[0], args[1], &out, err)) {
            FREE_ARGS();
            goto cleanup_fail;
          }
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_INDEX && argc == 1) {
          TcValue out;
          if (!string_index_value(receiver, args[0], &out, err)) {
            FREE_ARGS();
            goto cleanup_fail;
          }
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_RINDEX && argc == 1) {
          TcValue out;
          if (!string_rindex_value(receiver, args[0], &out, err)) {
            FREE_ARGS();
            goto cleanup_fail;
          }
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_SLICE && (argc == 1 || argc == 2)) {
          TcValue out;
          if (!string_slice_value(receiver, args[0], argc == 2 ? args[1] : (TcValue){0}, argc == 2, &out, err)) {
            FREE_ARGS();
            goto cleanup_fail;
          }
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_STRIP && argc == 0) {
          TcValue out;
          if (!string_strip_value(receiver, &out, err)) {
            FREE_ARGS();
            goto cleanup_fail;
          }
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && ((name == NAME_DOWNCASE) ||
                             (name == NAME_UPCASE)) && argc == 0) {
          TcValue out;
          int upper = name_len == 6;
          if (!string_case_value(receiver, upper, &out, err)) {
            FREE_ARGS();
            goto cleanup_fail;
          }
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_SPLIT && argc == 1) {
          TcValue out;
          if (!string_split_value(receiver, args[0], &out, err)) {
            FREE_ARGS();
            goto cleanup_fail;
          }
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_LCHS &&
            (argc == 0 || argc == 1) && tc_kind(receiver) == TC_VAL_STRING) {
          TcValue out;
          int use_lang = (argc == 1);
          if (!string_lchs_value(receiver, use_lang, &out, err)) {
            FREE_ARGS();
            goto cleanup_fail;
          }
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_CHARS && argc == 0 &&
            tc_kind(receiver) == TC_VAL_STRING) {
          size_t char_count = 0;
          for (size_t i = 0; i < tc_str_len(receiver);) {
            i += utf8_sequence_len(tc_str_bytes_only(receiver), tc_str_len(receiver), i);
            char_count++;
          }
          TcRuntimeArray *array = runtime_array_new(char_count, err);
          if (!array) {
            FREE_ARGS();
            goto cleanup_fail;
          }
          size_t out_i = 0;
          for (size_t i = 0; i < tc_str_len(receiver);) {
            size_t clen = utf8_sequence_len(tc_str_bytes_only(receiver), tc_str_len(receiver), i);
            if (!make_string_value(tc_str_bytes_only(receiver) + i, clen, &array->slots[out_i++], err)) {
              FREE_ARGS();
              runtime_array_free(array);
              goto cleanup_fail;
            }
            i += clen;
          }
          FREE_ARGS();
          if (!push(&vm, tc_box_array(array), err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_BYTES && argc == 0 &&
            tc_kind(receiver) == TC_VAL_STRING) {
          TcRuntimeArray *array = runtime_array_new(tc_str_len(receiver), err);
          if (!array) {
            FREE_ARGS();
            goto cleanup_fail;
          }
          for (size_t i = 0; i < tc_str_len(receiver); i++) {
            array->slots[i] = int_value((unsigned char)tc_str_bytes_only(receiver)[i]);
          }
          FREE_ARGS();
          if (!push(&vm, tc_box_array(array), err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_CHR && argc == 0 &&
            value_is_int(receiver)) {
          TcValue out;
          if (!make_codepoint_string_value(value_as_int(receiver), &out, err)) {
            FREE_ARGS();
            goto cleanup_fail;
          }
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_ORD && argc == 0 &&
            tc_kind(receiver) == TC_VAL_STRING) {
          int64_t code = utf8_first_codepoint(tc_str_bytes_only(receiver), tc_str_len(receiver));
          FREE_ARGS();
          if (!push(&vm, int_value(code), err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_JOIN && argc == 1) {
          TcValue out;
          if (!array_join_value(receiver, args[0], &out, err)) {
            // Free the inner error and rewrite with caller context.
            char *base = err->message;
            err->message = NULL;
            size_t fn_len = 0;
            const char *fn_name_str = current_function_name(&vm, vm.ip > 0 ? vm.ip - 1 : vm.ip, &fn_len);
            size_t caller_len = 0;
            const char *caller = NULL;
            if (vm.call_depth >= 2 && vm.frames[vm.call_depth - 2].function) {
              caller = (const char *)vm.frames[vm.call_depth - 2].function->name;
              caller_len = vm.frames[vm.call_depth - 2].function->name_len;
            }
            tc_error_set(err, "%s in %.*s (caller=%.*s)",
                         base ? base : "(no msg)",
                         (int)fn_len, fn_name_str ? fn_name_str : "?",
                         (int)caller_len, caller ? caller : "?");
            free(base);
            FREE_ARGS();
            goto cleanup_fail;
          }
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_KEYS && argc == 0) {
          TcRuntimeArray *array = NULL;
          if (tc_kind(receiver) == TC_VAL_HASH && tc_as_hash(receiver)) {
            // Walk slot-indexed keys[] in slot order (matches native's
            // hash iteration), skipping empty / tombstone slots.
            TcRuntimeHash *rh = tc_as_hash(receiver);
            array = runtime_array_new(rh->count, err);
            if (!array) {
              FREE_ARGS();
              goto cleanup_fail;
            }
            size_t out_i = 0;
            for (size_t i = 0; i < rh->cap; i++) {
              TcValue k = rh->keys[i];
              if (k == TC_HASH_EMPTY || k == TC_HASH_TOMBSTONE) continue;
              array->slots[out_i++] = k;
            }
          } else if (tc_kind(receiver) == TC_VAL_AST && tc_as_ast_ptr(&receiver)->kind == TC_AST_HASH && tc_as_ast_ptr(&receiver)->as.hash) {
            array = runtime_array_new(tc_as_ast_ptr(&receiver)->as.hash->count, err);
            if (!array) {
              FREE_ARGS();
              goto cleanup_fail;
            }
            for (size_t i = 0; i < tc_as_ast_ptr(&receiver)->as.hash->count; i++) {
              if (!make_string_value(tc_as_ast_ptr(&receiver)->as.hash->items[i].key, strlen(tc_as_ast_ptr(&receiver)->as.hash->items[i].key),
                                     &array->slots[i], err)) {
                FREE_ARGS();
                runtime_array_free(array);
                goto cleanup_fail;
              }
            }
          }
          if (array) {
            FREE_ARGS();
            if (!push(&vm, tc_box_array(array), err)) {
              goto cleanup_fail;
            }
            CNEXT();
          }
        }
        if (has_receiver && ((name == NAME_HAS_KEY_Q) ||
                             (name == NAME_KEY_Q)) && argc == 1) {
          int ok = 0;
          if (tc_kind(receiver) == TC_VAL_HASH && tc_as_hash(receiver)) {
            int found = 0;
            if (tc_as_hash(receiver)->cap > 0) {
              hash_find_slot(tc_as_hash(receiver), args[0], &found);
            }
            ok = found;
          } else if (tc_kind(receiver) == TC_VAL_AST && tc_as_ast_ptr(&receiver)->kind == TC_AST_HASH) {
            TcValue ignored;
            if (!ast_hash_lookup(*tc_as_ast_ptr(&receiver), args[0], &ignored, err)) {
              FREE_ARGS();
              goto cleanup_fail;
            }
            ok = tc_kind(ignored) != TC_VAL_NIL || (tc_kind(ignored) == TC_VAL_WVALUE && tc_as_wvalue(ignored) != W_NIL);
          }
          FREE_ARGS();
          if (!push(&vm, tc_box_wvalue(ok ? W_TRUE : W_FALSE), err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_SORT && argc == 0 &&
            tc_kind(receiver) == TC_VAL_ARRAY && tc_as_array(receiver)) {
          qsort(tc_as_array(receiver)->slots, tc_as_array(receiver)->size, sizeof(TcValue), compare_values_for_sort);
          FREE_ARGS();
          if (!push(&vm, receiver, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_TO_I && argc == 0) {
          TcValue out = tc_box_nil();
          if (value_is_int(receiver)) {
            out = receiver;
          } else if (tc_kind(receiver) == TC_VAL_STRING || tc_kind(receiver) == TC_VAL_SYMBOL) {
            char *text = (char *)malloc(tc_str_len(receiver) + 1);
            if (!text) {
              tc_error_set(err, "to_i allocation failed");
              FREE_ARGS();
              goto cleanup_fail;
            }
            memcpy(text, tc_str_bytes_only(receiver), tc_str_len(receiver));
            text[tc_str_len(receiver)] = '\0';
            out = int_value(strtoll(text, NULL, 10));
            free(text);
          }
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_TO_SYM && argc == 0 &&
          tc_kind(receiver) == TC_VAL_STRING) {
          FREE_ARGS();
          // Intern so to_sym's result shares bytes with all other syms
          // of the same content. Required by the L_EQ sym==sym ptr-only
          // fast path: every TC_VAL_SYMBOL must have a canonical bytes
          // pointer or ptr-mismatch could falsely report inequality.
          const char *interned = tc_intern(tc_str_bytes_only(receiver), tc_str_len(receiver));
          if (!interned) {
            tc_error_set(err, "symbol intern failed");
            goto cleanup_fail;
          }
          if (!push(&vm, tc_box_symbol_bytes(interned, tc_str_len(receiver), 0), err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_LAST && argc == 0 &&
            tc_kind(receiver) == TC_VAL_ARRAY && tc_as_array(receiver)) {
          TcValue out = tc_as_array(receiver)->size > 0
                            ? tc_as_array(receiver)->slots[tc_as_array(receiver)->size - 1]
                            : tc_box_nil();
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_FIRST && argc == 0 &&
            tc_kind(receiver) == TC_VAL_ARRAY && tc_as_array(receiver)) {
          TcValue out = tc_as_array(receiver)->size > 0 ? tc_as_array(receiver)->slots[0] : tc_box_nil();
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_POP && argc == 0 &&
            tc_kind(receiver) == TC_VAL_ARRAY && tc_as_array(receiver)) {
          TcValue out = tc_as_array(receiver)->size > 0
                            ? tc_as_array(receiver)->slots[--tc_as_array(receiver)->size]
                            : tc_box_nil();
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        if (has_receiver && name == NAME_SHIFT && argc == 0 &&
            tc_kind(receiver) == TC_VAL_ARRAY && tc_as_array(receiver)) {
          TcValue out = tc_box_nil();
          if (tc_as_array(receiver)->size > 0) {
            out = tc_as_array(receiver)->slots[0];
            memmove(tc_as_array(receiver)->slots, tc_as_array(receiver)->slots + 1, (tc_as_array(receiver)->size - 1) * sizeof(TcValue));
            tc_as_array(receiver)->size--;
          }
          FREE_ARGS();
          if (!push(&vm, out, err)) {
            goto cleanup_fail;
          }
          CNEXT();
        }
        // Optional C-native Loader#load_program_ast (TUNGSTEN_C_FAST_PARSE=1).
        // Speeds stage-1 bootstrap ~2× by using parse_ast.c for the entry
        // file's full `use` flatten instead of Tungsten lexer/parser
        // bytecode. Top-level only: after C parse we re-enter Tungsten
        // Loader#autoload_pass so core classes (Array/Hash/…) still load.
        // Nested load_program_ast (from autoload / use under Tungsten)
        // falls through so @loaded_files tracking stays correct.
        // MUST stay off for `tungsten build` stage1/stage2 identity —
        // C AST can drift from the canonical parser.
        if (vm.fast_parse_enabled && has_receiver &&
            tc_kind(receiver) == TC_VAL_OBJECT &&
            object_is_class(tc_as_object(receiver), "Loader", 6) && name_len == 16 &&
            memcmp(name, "load_program_ast", 16) == 0 && argc >= 1 &&
            !(argc >= 2 && (tc_kind(args[1]) == TC_VAL_STRING ||
                            tc_kind(args[1]) == TC_VAL_SYMBOL) &&
              tc_str_len(args[1]) > 0)) {
          const char *path = NULL;
          size_t path_len = 0;
          if (tc_kind(args[0]) == TC_VAL_STRING || tc_kind(args[0]) == TC_VAL_SYMBOL) {
            path = tc_str_bytes_only(args[0]);
            path_len = tc_str_len(args[0]);
          }
          if (path && path_len > 0) {
            char path_buf[4096];
            if (path_len >= sizeof(path_buf)) {
              tc_error_set(err, "load_program_ast: path too long");
              FREE_ARGS();
              goto cleanup_fail;
            }
            memcpy(path_buf, path, path_len);
            path_buf[path_len] = '\0';
            TcValue prog;
            if (!tc_vm_fast_load_program_ast(path_buf, NULL, &prog, err)) {
              FREE_ARGS();
              goto cleanup_fail;
            }
            /* Re-enter Loader#autoload_pass(prog, path) so stdlib
             * classes referenced by the compiler still materialize.
             * Without this, stage1 IR is missing @class.Array/Hash/… */
            static TcFunction *autoload_pass_fn = NULL;
            static const TcChunk *autoload_pass_chunk = NULL;
            if (autoload_pass_chunk != chunk) {
              autoload_pass_fn = tc_chunk_find_function(
                  chunk, "Loader#autoload_pass",
                  sizeof("Loader#autoload_pass") - 1);
              autoload_pass_chunk = chunk;
            }
            if (autoload_pass_fn && has_receiver) {
              TcValue path_v;
              if (!make_string_value(path_buf, path_len, &path_v, err)) {
                FREE_ARGS();
                goto cleanup_fail;
              }
              TcValue ap_args[2];
              ap_args[0] = prog;
              ap_args[1] = path_v;
              FREE_ARGS();
              if (!vm_call_function(&vm, autoload_pass_fn, ap_args, 2,
                                    receiver, 1, tc_box_nil(), 0, err)) {
                goto cleanup_fail;
              }
              NEXT();
            }
            FREE_ARGS();
            if (!push(&vm, prog, err)) goto cleanup_fail;
            CNEXT();
          }
        }
        if (has_receiver && tc_kind(receiver) == TC_VAL_OBJECT && tc_as_object(receiver)) {
          size_t full_len = tc_as_object(receiver)->class_name_len + 1 + name_len;
          char *full_name = (char *)malloc(full_len + 1);
          if (!full_name) {
            tc_error_set(err, "method name allocation failed");
            FREE_ARGS();
            goto cleanup_fail;
          }
          memcpy(full_name, tc_as_object(receiver)->class_name, tc_as_object(receiver)->class_name_len);
          full_name[tc_as_object(receiver)->class_name_len] = '#';
          memcpy(full_name + tc_as_object(receiver)->class_name_len + 1, name, name_len);
          full_name[full_len] = '\0';
          TcFunction *fn = tc_chunk_find_function(chunk, full_name, full_len);
          free(full_name);
          if (fn) {
            if (!vm_call_function(&vm, fn, args, argc, receiver, 1,
                                  tc_box_nil(), 0, err)) {
              FREE_ARGS();
              goto cleanup_fail;
            }
            FREE_ARGS();
            NEXT();
          }
        }
        /* W_PACKED_NODE receiver: method dispatch routes through the
         * AstNode class (compiler / Stage B). The class isn't a
         * normal heap object so we hardcode the "AstNode#" prefix
         * and look up the method directly in the chunk's function
         * table — same shape as the Object dispatch above.
         *
         * Fallback to AstNode#method_missing if the named method
         * isn't defined: the method-missing body gets `name` (as a
         * symbol) prepended to the call's args. Lets a single
         * method_missing replace dozens of trivial accessor wrappers
         * (`-> field; ast_get(self, :field)`) on AstNode. */
        if (has_receiver && w_is_node(receiver)) {
          static const char ASTNODE_PREFIX[] = "Tungsten:AST:Node#";
          static const size_t ASTNODE_PREFIX_LEN = sizeof(ASTNODE_PREFIX) - 1;
          /* Per-name_id resolution cache (see TcChunk.astnode_fn_cache).
           * Sound because the name is a chunk const and the function
           * table is frozen by VM-run time — the same assumption
           * method_ic_* and fn_for_const already make. Without it,
           * every node.method mallocs the prefixed name and linear-
           * scans ~1,400 functions; method_missing-bound node.field
           * reads are guaranteed full-miss scans (~20% of stage 1). */
          TcChunk *mchunk = (TcChunk *)chunk;
          if (!mchunk->astnode_fn_cache) {
            mchunk->astnode_fn_cache = (TcFunction **)calloc(chunk->const_count, sizeof(TcFunction *));
            mchunk->astnode_fn_state = (uint8_t *)calloc(chunk->const_count, 1);
          }
          TcFunction *fn = NULL;
          uint8_t ast_ic_state = mchunk->astnode_fn_state ? mchunk->astnode_fn_state[name_id] : 0;
          if (ast_ic_state == 1) {
            fn = mchunk->astnode_fn_cache[name_id];
          } else if (ast_ic_state == 0) {
            size_t full_len = ASTNODE_PREFIX_LEN + name_len;
            char *full_name = (char *)malloc(full_len + 1);
            if (!full_name) {
              tc_error_set(err, "method name allocation failed");
              FREE_ARGS();
              goto cleanup_fail;
            }
            memcpy(full_name, ASTNODE_PREFIX, ASTNODE_PREFIX_LEN);
            memcpy(full_name + ASTNODE_PREFIX_LEN, name, name_len);
            full_name[full_len] = '\0';
            fn = tc_chunk_find_function(chunk, full_name, full_len);
            free(full_name);
            if (mchunk->astnode_fn_state) {
              mchunk->astnode_fn_state[name_id] = fn ? 1 : 2;
              mchunk->astnode_fn_cache[name_id] = fn;
            }
          }
          if (fn) {
            if (!vm_call_function(&vm, fn, args, argc, receiver, 1,
                                  tc_box_nil(), 0, err)) {
              FREE_ARGS();
              goto cleanup_fail;
            }
            FREE_ARGS();
            NEXT();
          }
          /* method_missing fallback. For zero-arg getters we dispatch
           * to AstNode#method_missing(name); for one-arg setters
           * (method name ends with `=`) we dispatch to
           * AstNode#method_missing_set(name, value) with the trailing
           * `=` stripped from the symbol. Two separate entry points
           * because C VM stage 0 doesn't implement `*args` splat —
           * collapsing both into one method_missing with a splat
           * would land the value in a non-array local. */
          int is_setter = argc == 1 && name_len > 0 && name[name_len - 1] == '=';
          const char *mm_full = is_setter ? "Tungsten:AST:Node#method_missing_set"
                                          : "Tungsten:AST:Node#method_missing";
          size_t mm_full_len = is_setter ? strlen("Tungsten:AST:Node#method_missing_set")
                                         : strlen("Tungsten:AST:Node#method_missing");
          /* method_missing/_set resolve to the same two functions for
           * the life of a chunk — cache both (keyed by chunk so a VM
           * that runs multiple chunks stays correct). */
          static TcFunction *mm_cache[2];
          static const TcChunk *mm_cache_chunk;
          if (mm_cache_chunk != chunk) { mm_cache[0] = mm_cache[1] = NULL; mm_cache_chunk = chunk; }
          TcFunction *mm_fn = mm_cache[is_setter];
          if (!mm_fn) {
            mm_fn = tc_chunk_find_function(chunk, mm_full, mm_full_len);
            mm_cache[is_setter] = mm_fn;
          }
          if (mm_fn) {
            size_t field_len = is_setter ? name_len - 1 : name_len;
            uint32_t mm_argc = is_setter ? 2 : 1;
            TcValue mm_args[2];
            const char *interned_name = tc_intern(name, field_len);
            mm_args[0] = interned_name ? tc_box_symbol_bytes(interned_name, field_len, 0)
                                       : tc_box_nil();
            if (is_setter) mm_args[1] = args[0];
            int ok = vm_call_function(&vm, mm_fn, mm_args, mm_argc, receiver, 1,
                                      tc_box_nil(), 0, err);
            if (!ok) {
              FREE_ARGS();
              goto cleanup_fail;
            }
            FREE_ARGS();
            NEXT();
          }
        }

        /* Hash AST dual-rep field methods (TUNGSTEN_C_FAST_PARSE path).
         *
         * The self-hosted compiler writes `node.expressions` /
         * `node.name` / … which normally dispatch through
         * Tungsten:AST:Node on W_PACKED_NODE. C parse_ast emits
         * `{node: :program, expressions: [...]}` hashes; ast_get /
         * ast_kind already handle the Hash branch, but method-style
         * field access does not. Treat an AST-shaped Hash (has :node)
         * like Node: zero-arg getters read hash[:field] (with
         * `.kind` → `:node`), one-arg `field=` setters write it.
         * Missing keys return nil, matching ast_get. */
        if (vm.fast_parse_enabled && has_receiver &&
            tc_kind(receiver) == TC_VAL_HASH && tc_as_hash(receiver) &&
            (argc == 0 || (argc == 1 && name_len > 0 && name[name_len - 1] == '='))) {
          TcRuntimeHash *h = tc_as_hash(receiver);
          static const char *node_sym_bytes = NULL;
          if (!node_sym_bytes) node_sym_bytes = tc_intern("node", 4);
          int is_ast_hash = 0;
          if (node_sym_bytes && h && h->cap > 0) {
            TcValue node_key = tc_box_symbol_bytes(node_sym_bytes, 4, 0);
            size_t node_slot = hash_find_slot(h, node_key, &is_ast_hash);
            if (is_ast_hash && tc_kind(h->values[node_slot]) != TC_VAL_SYMBOL) {
              is_ast_hash = 0;
            }
          }
          if (is_ast_hash) {
            if (argc == 0) {
              const char *field = name;
              size_t field_len = name_len;
              /* Node#kind → ast_kind → hash[:node] */
              if (name_len == 4 && name[0] == 'k' && name[1] == 'i' &&
                  name[2] == 'n' && name[3] == 'd') {
                field = "node";
                field_len = 4;
              }
              const char *interned = tc_intern(field, field_len);
              if (interned) {
                TcValue key_v = tc_box_symbol_bytes(interned, field_len, 0);
                TcValue out = hash_get_value(h, key_v);
                FREE_ARGS();
                if (!push(&vm, out, err)) goto cleanup_fail;
                CNEXT();
              }
            } else {
              /* field= → hash[:field] = value */
              size_t field_len = name_len - 1;
              const char *interned = tc_intern(name, field_len);
              if (interned) {
                TcValue key_v = tc_box_symbol_bytes(interned, field_len, 0);
                TcValue set_val = args[0];
                if (!hash_set_value(h, key_v, set_val, err)) {
                  FREE_ARGS();
                  goto cleanup_fail;
                }
                FREE_ARGS();
                if (!push(&vm, set_val, err)) goto cleanup_fail;
                CNEXT();
              }
            }
          }
        }

        size_t fn_len = 0;
        const char *fn_name = current_function_name(&vm, op_ip, &fn_len);
        size_t caller_len = 0;
        const char *caller_name = frame_function_name(&vm, 1, &caller_len);
        tc_error_set(err, "unsupported runtime call: %.*s receiver=%s argc=%u arg0=%s fn=%.*s caller=%.*s ip=%zu",
                     (int)name_len, name, has_receiver ? value_type_name(receiver) : "<none>", argc,
                     argc > 0 ? value_type_name(args[0]) : "<none>", (int)fn_len, fn_name,
                     (int)caller_len, caller_name, op_ip);
        FREE_ARGS();
        goto cleanup_fail;
#undef FREE_ARGS
