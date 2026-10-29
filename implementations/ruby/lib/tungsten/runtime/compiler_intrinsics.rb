# frozen_string_literal: true

module Tungsten
  module Runtime
    class PackedNode
      attr_accessor :kind, :sc, :offset, :fields, :sparse, :analysis, :ivar_offsets, :ivar_count, :intern_str

      def initialize(kind, sc = 0, offset = 0, fields = nil, intern_str: nil)
        @kind = kind
        @sc = sc
        @offset = offset
        @fields = fields || []
        @sparse = nil
        @analysis = nil
        @ivar_offsets = nil
        @ivar_count = nil
        @intern_str = intern_str
      end

      def to_s
        "[ast]"
      end
    end

    class WireRecord
      attr_accessor :kind, :keys, :values, :index_by_key

      def initialize(kind, keys = nil, values = nil, index_by_key = nil)
        @kind = kind
        @keys = keys || []
        @values = values || []
        @index_by_key = index_by_key || {}
      end

      def store_at(idx, sym, val)
        key = sym.is_a?(String) ? sym.to_sym : sym
        @keys[idx] = key
        @values[idx] = val
        @index_by_key[key] = idx
        val
      end

      def store(sym, val)
        key = sym.is_a?(String) ? sym.to_sym : sym
        idx = @index_by_key[key]
        if idx
          @values[idx] = val
        else
          idx = @keys.length
          @keys << key
          @values << val
          @index_by_key[key] = idx
        end
        val
      end

      def load(sym)
        key = sym.is_a?(String) ? sym.to_sym : sym
        idx = @index_by_key[key]
        idx ? @values[idx] : nil
      end

      def [](sym)
        load(sym)
      end

      def []=(sym, val)
        store(sym, val)
      end

      def clone_record
        WireRecord.new(@kind, @keys.dup, @values.dup, @index_by_key.dup)
      end
    end

    class WireSequence
      attr_accessor :items

      def initialize(items)
        @items = items
      end

      def size
        @items.length
      end
      alias length size

      def empty?
        @items.empty?
      end

      def [](idx)
        i = idx.to_i
        i < 0 ? @items[@items.length + i] : @items[i]
      end

      def []=(idx, val)
        i = idx.to_i
        return nil if i < 0 || i >= @items.length

        @items[i] = val
      end

      def each(&block)
        @items.each(&block)
      end

      def to_a
        @items
      end

      def clone_sequence
        WireSequence.new(@items.dup)
      end
    end

    module CompilerIntrinsics
      W_PACKED_TOKEN_MASK = 0xFFFF_C000_0000_0000
      W_PACKED_TOKEN_TAG  = 0xFFFC_0000_0000_0000
      W_PACKED_LOC_BASE   = 0xFFFE_0000_0000_0000 | (7 << 45)
      U64_MASK            = 0xFFFF_FFFF_FFFF_FFFF
      I64_SIGN_BIT        = 1 << 63
      I64_MOD             = 1 << 64
      COMPILER_CCALL_MISS = Object.new.freeze

      SKIP_COMPILER_CORE_USE_PATHS = {
        "core/numeric/int" => true,
        "core/numeric/float" => true,
        "core/numeric/big_int" => true,
        "core/string" => true,
        "core/string_buffer" => true
      }.freeze

      def init_compiler_intrinsics
        @ast_next_offset = 1
        @ast_store_gen = 1
        @ast_singletons = {}
        @ast_inline_nodes = {}
        @ast_bool_nodes = {}
        @ast_intern_table = {}
        @ast_intern_nodes = {}
        @ast_intern_next_id = 0
        @loc_files_by_path = {}
        @loc_line_tables = {}
        @loc_col_tables = {}
        @loc_source_texts = {}
      end

      def packed_token_int?(val)
        val.is_a?(Integer) && (val & W_PACKED_TOKEN_MASK) == W_PACKED_TOKEN_TAG
      end

      def to_signed_i64(u64)
        v = u64 & U64_MASK
        v >= I64_SIGN_BIT ? v - I64_MOD : v
      end

      def dispatch_slab_alloc_init(args)
        kind = args[0].to_i
        sc = args[1].to_i
        fields = args.length > 2 ? args[2..] : []
        offset = (@ast_next_offset += 8)
        PackedNode.new(kind, sc, offset, fields)
      end

      def content_temp_ordinal(name)
        return -1 unless name.is_a?(String)
        return -1 if name.bytesize < 3 || name.getbyte(0) != 37 || name.getbyte(1) != 116 # "%t"

        val = 0
        i = 2
        len = name.bytesize
        while i < len
          digit = name.getbyte(i) - 48
          return -1 if digit < 0 || digit > 9

          val = (val * 10) + digit
          return -1 if val > 0x7FFF_FFFF

          i += 1
        end
        val
      end

      def wire_temp_operands_for(wire)
        return [] unless wire.is_a?(WireRecord)

        out = []
        keys = wire.keys
        values = wire.values
        count = keys.length
        fi = 0
        while fi < count
          sym = keys[fi]
          val = values[fi]
          fi += 1
          next if sym == :temp || val.nil?

          if val.is_a?(WireSequence)
            items = val.items
            si = 0
            seq_count = items.length
            while si < seq_count
              item = items[si]
              si += 1
              if item.is_a?(String) && !item.empty? && item.getbyte(0) == 37
                out << item
              elsif item.is_a?(Hash)
                iv = hash_indifferent_get(item, :value)
                out << iv if iv.is_a?(String) && !iv.empty? && iv.getbyte(0) == 37
              elsif item.is_a?(Array)
                return nil
              end
            end
          elsif val.is_a?(String) && !val.empty? && val.getbyte(0) == 37
            out << val
          elsif val.is_a?(Array) || val.is_a?(Hash)
            return nil
          end
        end
        out
      end

      COMPILER_CCALL_IDS = {
        "w_is_node_extern" => 1,
        "w_is_ast_node_full" => 2,
        "w_node_alloc" => 3,
        "w_node_field_store" => 4,
        "w_node_field_load" => 5,
        "w_node_kind_extern" => 6,
        "w_node_kind_sym" => 7,
        "w_node_offset_extern" => 8,
        "w_node_size_class_extern" => 9,
        "w_node_singleton" => 10,
        "w_node_inline_payload" => 11,
        "w_ast_bool_cached" => 12,
        "w_ast_intern_node" => 13,
        "w_ast_intern_str_of" => 14,
        "w_ast_sparse_set" => 15,
        "w_ast_sparse_get" => 16,
        "w_ast_sparse_copy" => 17,
        "w_ast_analysis_set" => 18,
        "w_ast_analysis_get" => 19,
        "w_ast_ivar_offsets_set" => 20,
        "w_ast_ivar_offsets_get" => 21,
        "w_ast_ivar_count_set" => 22,
        "w_ast_ivar_count_get" => 23,
        "w_ast_store_reset" => 24,
        "w_ast_store_generation" => 25,
        "w_ast_stats_dump" => 26,
        "w_ast_body_builder_new" => 27,
        "w_ast_body_builder_push" => 28,
        "w_ast_body_builder_finish" => 29,
        "w_content_temp_map_new" => 30,
        "w_content_temp_map_seed" => 31,
        "w_content_temp_norm" => 32,
        "w_wire_function_record_new" => 33,
        "w_wire_block_record_new" => 34,
        "w_wire_alloc" => 35,
        "w_wire_alloc_reserve" => 35,
        "w_wire_field_store_at" => 36,
        "w_wire_field_store" => 37,
        "w_wire_field_load" => 38,
        "w_wire_field_load_nil" => 38,
        "w_wire_field_count" => 39,
        "w_wire_field_symbol_at" => 40,
        "w_wire_field_value_at" => 41,
        "w_wire_kind_extern" => 42,
        "w_wire_kind_sym" => 43,
        "w_is_wire_extern" => 44,
        "w_wire_sequence_from_array" => 45,
        "w_wire_sequence_size" => 46,
        "w_wire_sequence_get" => 47,
        "w_wire_sequence_set" => 48,
        "w_wire_store_reset" => 49,
        "w_wire_store_mark" => 50,
        "w_wire_clone" => 51,
        "w_wire_temp_operands" => 52,
        "w_make_token_extern" => 53,
        "w_token_type_extern" => 54,
        "w_token_length_extern" => 55,
        "w_token_offset_extern" => 56,
        "w_parser_tok_raw" => 57,
        "w_parser_chars_equal_ascii" => 58,
        "w_location_file" => 59,
        "w_location_file_offset" => 60,
        "w_unbox_location_file_id_extern" => 61,
        "w_unbox_location_line_extern" => 62,
        "w_unbox_location_col_extern" => 63,
        "w_unbox_location_offset_extern" => 64,
        "w_loc_register_file" => 65,
        "w_loc_register_source_text" => 66,
        "w_loc_line_for_offset" => 67,
        "w_loc_col_for_offset" => 68,
        "w_numeric_to_i64" => 69,
        "w_array_data_ptr" => 70,
        "w_lex64_scan_to_cp" => 71,
        "w_string_byte_length" => 72,
        "w_string_len" => 72,
        "w_string_slice_bytes" => 73,
        "w_string_eq_bytes_lit" => 74,
        "w_string_first_byte" => 75,
        "w_u64" => 76,
        "w_int" => 76,
        "w_int_to_hex_str" => 77,
        "w_algebra_rewrite_source" => 78,
        "w_compiler_image_lean_profile" => 79,
        "w_eputs" => 80,
        "w_flush" => 81,
        "w_setenv" => 82,
        "w_run_argv" => 83,
        "w_host_cache_bytes_extern" => 84,
        "w_executable_dir" => 85,
        "w_executable_path" => 86,
        "w_runtime_dir" => 87,
        "w_isatty_stdout" => 88,
        "w_isatty_stdin" => 89,
        "w_cpu_count" => 90,
        "__w_cpu_count" => 90,
        "w_slab_freeze_safe" => 91,
        "w_slab_is_frozen" => 92,
        "w_freeze" => 93,
        "w_frozen_p" => 94,
        "w_core_cache_read" => 95,
        "w_core_cache_read_rebase_locations" => 95,
        "w_core_cache_write" => 96,
        "w_zstd_compress_llvm_escaped" => 97,
        "__w_bit_ctpop_u32" => 98,
        "__w_bit_ctpop_u64" => 99,
        "__w_bit_cttz_u32" => 100,
        "__w_bit_cttz_u64" => 101,
        "__w_bit_ctlz_u64" => 102
      }.freeze

      def dispatch_compiler_ccall(cname, args)
        ccall_id = COMPILER_CCALL_IDS[cname]
        return COMPILER_CCALL_MISS unless ccall_id

        case ccall_id
        when 1
          args[1].is_a?(PackedNode) ? 1 : 0
        when 2
          x = args[1]
          node_sym = args[2]
          if x.nil?
            0
          elsif x.is_a?(PackedNode)
            1
          elsif x.is_a?(Hash)
            hash_indifferent_get(x, node_sym).nil? ? 0 : 1
          else
            0
          end
        when 3
          kind = args[1].to_i
          sc = args[2].to_i
          PackedNode.new(kind, sc, (@ast_next_offset += 8), [])
        when 4
          node = args[1]
          off = args[2].to_i
          val = args[3]
          node.fields[off] = val if node.is_a?(PackedNode)
          val
        when 5
          node = args[1]
          off = args[2].to_i
          node.is_a?(PackedNode) ? node.fields[off] : nil
        when 6
          node = args[1]
          node.is_a?(PackedNode) ? node.kind : 0
        when 7
          node = args[1]
          table = args[2]
          if node.is_a?(PackedNode) && table.is_a?(Array)
            table[node.kind]
          end
        when 8
          node = args[1]
          node.is_a?(PackedNode) ? node.offset : 0
        when 9
          node = args[1]
          node.is_a?(PackedNode) ? node.sc : 0
        when 10
          kind = args[1].to_i
          @ast_singletons[kind] ||= PackedNode.new(kind, 0, 0, [])
        when 11
          kind = args[1].to_i
          payload = args[2].to_i & 0xFFFF_FFFF
          @ast_inline_nodes[[kind, payload]] ||= PackedNode.new(kind, 0, payload, [])
        when 12
          truthy = args[1].to_i != 0
          key = truthy ? 1 : 0
          @ast_bool_nodes[key] ||= PackedNode.new(39, 0, (@ast_next_offset += 2), [truthy])
        when 13
          kind = args[1].to_i
          str = args[2].to_s
          id, canonical_str = (@ast_intern_table[str] ||= [(@ast_intern_next_id += 1), str])
          @ast_intern_nodes[[kind, id]] ||= PackedNode.new(kind, 0, id, [], intern_str: canonical_str)
        when 14
          node = args[1]
          node.is_a?(PackedNode) ? node.intern_str : nil
        when 15
          node = args[1]
          sym = args[2]
          val = args[3]
          return val unless node.is_a?(PackedNode)

          key = sym.is_a?(String) ? sym.to_sym : sym
          case key
          when :lowering_analysis
            node.analysis = val
          when :ivar_offsets
            node.ivar_offsets = val
          when :ivar_count
            node.ivar_count = val
          else
            (node.sparse ||= {})[key] = val
          end
          val
        when 16
          node = args[1]
          sym = args[2]
          return nil unless node.is_a?(PackedNode)

          key = sym.is_a?(String) ? sym.to_sym : sym
          case key
          when :lowering_analysis
            node.analysis
          when :ivar_offsets
            node.ivar_offsets
          when :ivar_count
            node.ivar_count
          else
            node.sparse ? node.sparse[key] : nil
          end
        when 17
          src = args[1]
          dst = args[2]
          if src.is_a?(PackedNode) && dst.is_a?(PackedNode)
            dst.sparse = src.sparse ? src.sparse.dup : nil
            dst.analysis = src.analysis
            dst.ivar_offsets = src.ivar_offsets
            dst.ivar_count = src.ivar_count
          end
          dst
        when 18
          node = args[1]
          val = args[2]
          node.analysis = val if node.is_a?(PackedNode)
          val
        when 19
          node = args[1]
          node.is_a?(PackedNode) ? node.analysis : nil
        when 20
          node = args[1]
          val = args[2]
          node.ivar_offsets = val if node.is_a?(PackedNode)
          val
        when 21
          node = args[1]
          node.is_a?(PackedNode) ? node.ivar_offsets : nil
        when 22
          node = args[1]
          val = args[2]
          node.ivar_count = val if node.is_a?(PackedNode)
          val
        when 23
          node = args[1]
          node.is_a?(PackedNode) ? node.ivar_count : nil
        when 24
          @ast_store_gen += 1
          @ast_bool_nodes.clear
          @ast_intern_table.clear
          @ast_intern_nodes.clear
          @ast_intern_next_id = 0
          @ast_store_gen
        when 25
          @ast_store_gen
        when 26
          0
        when 27
          []
        when 28
          arr = args[1]
          arr.push(args[3]) if arr.is_a?(Array)
          arr
        when 29
          args[1]
        when 30
          [Array.new(args[1].to_i), {}, args[2].to_i]
        when 31
          state = args[1]
          name = args[2]
          idx = args[3]
          ordinal = content_temp_ordinal(name)
          dense = state[0]
          if ordinal >= 0 && ordinal < dense.length
            dense[ordinal] = idx
          else
            state[1][name] = idx
          end
          nil
        when 32
          name = args[1]
          state = args[2]
          dense = state[0]
          fallback = state[1]
          ordinal = content_temp_ordinal(name)
          out = (ordinal >= 0 && ordinal < dense.length) ? dense[ordinal] : fallback[name]
          if out.nil?
            out = state[2]
            if ordinal >= 0 && ordinal < dense.length
              dense[ordinal] = out
            else
              fallback[name] = out
            end
            state[2] = out + 1
          end
          out
        when 33
          fields = args[1]
          rec = WireRecord.new(265)
          values = [
            args[2], args[2], args[3], args[6], args[4], args[5],
            [], {}, {},
            0, 0, 0, 0,
            [], 0, [],
            [], [nil], {},
            [], {},
            false, false, nil, nil
          ]
          i = 0
          while i < 25
            rec.store_at(i, fields[i], values[i])
            i += 1
          end
          rec
        when 34
          fields = args[1]
          rec = WireRecord.new(266)
          rec.store_at(0, fields[0], args[2])
          rec.store_at(1, fields[1], [])
          rec
        when 35
          WireRecord.new(args[1].to_i)
        when 36
          rec = args[1]
          rec.store_at(args[2].to_i, args[3], args[4]) if rec.is_a?(WireRecord)
        when 37
          rec = args[1]
          rec.store(args[2], args[3]) if rec.is_a?(WireRecord)
        when 38
          rec = args[1]
          rec.is_a?(WireRecord) ? rec.load(args[2]) : nil
        when 39
          rec = args[1]
          rec.is_a?(WireRecord) ? rec.keys.length : 0
        when 40
          rec = args[1]
          rec.is_a?(WireRecord) ? rec.keys[args[2].to_i] : nil
        when 41
          rec = args[1]
          rec.is_a?(WireRecord) ? rec.values[args[2].to_i] : nil
        when 42
          v = args[1]
          if v.is_a?(WireRecord)
            v.kind
          elsif v.is_a?(WireSequence)
            267
          else
            0
          end
        when 43
          v = args[1]
          syms = args[2]
          if v.is_a?(WireRecord) && syms.is_a?(Array)
            syms[v.kind]
          end
        when 44
          v = args[1]
          (v.is_a?(WireRecord) || v.is_a?(WireSequence)) ? 1 : 0
        when 45
          arr = args[1]
          if arr.is_a?(WireSequence)
            arr
          elsif arr.is_a?(Array)
            WireSequence.new(arr.dup)
          end
        when 46
          seq = args[1]
          if seq.is_a?(WireSequence)
            seq.size
          elsif seq.is_a?(Array)
            seq.length
          else
            0
          end
        when 47
          seq = args[1]
          idx = args[2].to_i
          if seq.is_a?(WireSequence) || seq.is_a?(Array)
            seq[idx]
          end
        when 48
          seq = args[1]
          idx = args[2].to_i
          val = args[3]
          if seq.is_a?(WireSequence) || seq.is_a?(Array)
            seq[idx] = val
          end
        when 49
          0
        when 50
          1
        when 51
          v = args[1]
          if v.is_a?(WireRecord)
            v.clone_record
          elsif v.is_a?(WireSequence)
            v.clone_sequence
          else
            v
          end
        when 52
          wire_temp_operands_for(args[1])
        when 53
          t = args[1].to_i & 0xFF
          l = args[2].to_i & 0xFFF
          o = args[3].to_i & 0xFF_FFFF
          to_signed_i64(W_PACKED_TOKEN_TAG | (t << 38) | (l << 26) | (o << 2))
        when 54
          (args[1].to_i >> 38) & 0xFF
        when 55
          (args[1].to_i >> 26) & 0xFFF
        when 56
          (args[1].to_i >> 2) & 0xFF_FFFF
        when 57
          args[1].to_i
        when 58
          chars = args[1]
          off = args[2].to_i
          len = args[3].to_i
          lit = args[4].to_s
          if chars.is_a?(Array) && off >= 0 && len >= 0 && off + len <= chars.length && len == lit.bytesize
            i = 0
            equal = 1
            while i < len
              ch = chars[off + i]
              b = lit.getbyte(i)
              if b >= 0x80 || !ch.is_a?(String) || ch.bytesize != 1 || ch.getbyte(0) != b
                equal = 0
                break
              end
              i += 1
            end
            equal
          else
            0
          end
        when 59
          fid = args[1].to_i & 0x3FFF
          line = args[2].to_i & 0x3FFFF
          col = args[3].to_i & 0x7FF
          to_signed_i64(W_PACKED_LOC_BASE | (1 << 43) | (fid << 29) | (line << 11) | col)
        when 60
          fid = args[1].to_i & 0x3FFF
          off = args[2].to_i & 0x1FFF_FFFF
          to_signed_i64(W_PACKED_LOC_BASE | (2 << 43) | (fid << 29) | off)
        when 61
          (args[1].to_i >> 29) & 0x3FFF
        when 62
          (args[1].to_i >> 11) & 0x3FFFF
        when 63
          args[1].to_i & 0x7FF
        when 64
          args[1].to_i & 0x1FFF_FFFF
        when 65
          path = args[1].to_s
          line_at = args[2].is_a?(Array) ? args[2] : []
          col_at = args[3].is_a?(Array) ? args[3] : []
          register_loc_file_entry(path, line_at, col_at)
        when 66
          path = args[1].to_s
          source = args[2].to_s
          @loc_source_texts[path] = source
          line_at, col_at = build_loc_tables_from_source(source)
          register_loc_file_entry(path, line_at, col_at)
        when 67
          fid = args[1].to_i
          off = args[2].to_i
          tbl = @loc_line_tables[fid]
          if tbl && off >= 0 && off < tbl.length
            tbl[off] || -1
          else
            -1
          end
        when 68
          fid = args[1].to_i
          off = args[2].to_i
          tbl = @loc_col_tables[fid]
          if tbl && off >= 0 && off < tbl.length
            tbl[off] || -1
          else
            -1
          end
        when 69
          v = args[1]
          v.is_a?(Tungsten::CharValue) ? v.codepoint : v.to_i
        when 70
          args[1]
        when 71
          data = args[1]
          n = args[2].to_i
          p = args[3].to_i
          target = args[4]
          cp_target = target.is_a?(Tungsten::CharValue) ? target.codepoint : target.to_i
          if data.is_a?(Array)
            while p < n
              break if ((data[p].to_i >> 18) & 0x1FFFFF) == cp_target

              p += 1
            end
          end
          p
        when 72
          args[1].to_s.bytesize
        when 73
          args[1].to_s.byteslice(args[2].to_i, args[3].to_i) || ""
        when 74
          args[1].to_s.byteslice(args[2].to_i, args[3].to_i) == args[4].to_s
        when 75
          v = args[1]
          if v.is_a?(String)
            v.empty? ? -1 : v.getbyte(0)
          else
            -2
          end
        when 76
          args[1]
        when 77
          format("%016x", args[1].to_i & U64_MASK)
        when 78
          args[1]
        when 79
          nil
        when 80
          $stderr.puts(w_to_s(args[1]))
          $stderr.flush
          nil
        when 81
          $stdout.flush
          $stderr.flush
          nil
        when 82
          Tungsten::Env.set(args[1], args[2])
        when 83
          argv_arr = args[1]
          if argv_arr.is_a?(Array) && !argv_arr.empty?
            cmd = argv_arr.map(&:to_s)
            Kernel.system(*cmd)
            status = $?
            if status.nil?
              -1
            elsif status.exited?
              status.exitstatus
            elsif status.signaled?
              256 + status.termsig.to_i
            else
              -1
            end
          else
            -1
          end
        when 84
          0
        when 85
          ENV["TUNGSTEN_ROOT"] ? File.join(ENV["TUNGSTEN_ROOT"], "bin") : File.expand_path("../../../../../bin", __dir__)
        when 86
          ENV["TUNGSTEN_ROOT"] ? File.join(ENV["TUNGSTEN_ROOT"], "bin/tungsten-compiler") : File.expand_path("../../../../../bin/tungsten-compiler", __dir__)
        when 87
          ENV["TUNGSTEN_ROOT"] ? File.join(ENV["TUNGSTEN_ROOT"], "runtime") : File.expand_path("../../../../../runtime", __dir__)
        when 88
          $stdout.tty?
        when 89
          $stdin.tty?
        when 90
          4
        when 91
          nil
        when 92
          false
        when 93
          args[1]
        when 94
          false
        when 95
          nil
        when 96
          false
        when 97
          nil
        when 98
          (args[1].to_i & 0xFFFF_FFFF).to_s(2).count("1")
        when 99
          (args[1].to_i & U64_MASK).to_s(2).count("1")
        when 100
          raw = args[1].to_i & 0xFFFF_FFFF
          raw.zero? ? 32 : (raw & -raw).bit_length - 1
        when 101
          raw = args[1].to_i & U64_MASK
          raw.zero? ? 64 : (raw & -raw).bit_length - 1
        when 102
          raw = args[1].to_i & U64_MASK
          raw.zero? ? 64 : 64 - raw.bit_length
        else
          COMPILER_CCALL_MISS
        end
      end

      def register_loc_file_entry(path, line_at, col_at)
        existing_fids = @loc_files_by_path[path]
        if existing_fids
          existing_fids.each do |fid|
            if @loc_line_tables[fid] == line_at && @loc_col_tables[fid] == col_at
              return fid
            end
          end
        else
          existing_fids = []
          @loc_files_by_path[path] = existing_fids
        end
        fid = @loc_line_tables.size + 1
        @loc_line_tables[fid] = line_at.dup
        @loc_col_tables[fid] = col_at.dup
        existing_fids << fid
        fid
      end

      def build_loc_tables_from_source(source)
        line_at = []
        col_at = []
        line = 1
        col = 1
        off = 0
        len = source.bytesize
        while off < len
          c = source.getbyte(off)
          line_at << line
          col_at << col
          if c == 10
            line += 1
            col = 1
          else
            col += 1
          end
          step = c >= 0xF0 ? 4 : c >= 0xE0 ? 3 : c >= 0xC0 ? 2 : 1
          step = len - off if step > len - off
          off += step
        end
        line_at << line
        col_at << col
        [line_at, col_at]
      end

      def snapshot_ast_cache_state(value)
        return value unless value.is_a?(PackedNode)

        loader = @self_stack.last
        loader_state =
          if loader.is_a?(WObject)
            {
              manifest_files: loader.get_ivar("@manifest_files"),
              autoload_registry: loader.get_ivar("@autoload_registry"),
              core_root: loader.get_ivar("@core_root"),
              loaded_files: loader.get_ivar("@loaded_files")
            }
          end

        {
          __tungsten_ast_cache_v3__: true,
          value: value,
          loader_state: loader_state,
          ast_next_offset: @ast_next_offset,
          ast_singletons: @ast_singletons,
          ast_inline_nodes: @ast_inline_nodes,
          ast_bool_nodes: @ast_bool_nodes,
          ast_intern_table: @ast_intern_table,
          ast_intern_nodes: @ast_intern_nodes,
          ast_intern_next_id: @ast_intern_next_id,
          loc_files_by_path: @loc_files_by_path,
          loc_line_tables: @loc_line_tables,
          loc_col_tables: @loc_col_tables,
          loc_source_texts: @loc_source_texts
        }
      end

      def restore_ast_cache_state(loaded)
        return nil if loaded.is_a?(PackedNode) || loaded.is_a?(WObject)
        return nil if loaded.is_a?(Hash) && loaded[:__tungsten_ast_cache_v2__]
        return loaded unless loaded.is_a?(Hash) && loaded[:__tungsten_ast_cache_v3__]

        @ast_next_offset = loaded[:ast_next_offset] if loaded[:ast_next_offset]
        @ast_singletons = loaded[:ast_singletons] if loaded[:ast_singletons]
        @ast_inline_nodes = loaded[:ast_inline_nodes] if loaded[:ast_inline_nodes]
        @ast_bool_nodes = loaded[:ast_bool_nodes] if loaded[:ast_bool_nodes]
        @ast_intern_table = loaded[:ast_intern_table] if loaded[:ast_intern_table]
        @ast_intern_nodes = loaded[:ast_intern_nodes] if loaded[:ast_intern_nodes]
        @ast_intern_next_id = loaded[:ast_intern_next_id] if loaded[:ast_intern_next_id]
        @loc_files_by_path = loaded[:loc_files_by_path] if loaded[:loc_files_by_path]
        @loc_line_tables = loaded[:loc_line_tables] if loaded[:loc_line_tables]
        @loc_col_tables = loaded[:loc_col_tables] if loaded[:loc_col_tables]
        @loc_source_texts = loaded[:loc_source_texts] if loaded[:loc_source_texts]
        loader = @self_stack.last
        if loader.is_a?(WObject) && (ls = loaded[:loader_state])
          loader.set_ivar("@manifest_files", ls[:manifest_files]) if ls[:manifest_files]
          loader.set_ivar("@autoload_registry", ls[:autoload_registry]) if ls[:autoload_registry]
          loader.set_ivar("@core_root", ls[:core_root]) if ls[:core_root]
          loader.set_ivar("@loaded_files", ls[:loaded_files]) if ls[:loaded_files]
        end
        loaded[:value]
      end
    end
  end
end
