#!/usr/bin/env ruby
# frozen_string_literal: true

# Runtime-backed Core values can bypass ordinary source-class dispatch. Their
# native inline-cache tables and compiler direct-call whitelists therefore form
# one public-method contract. This gate checks the table structure globally and
# pins Quantity's complete three-way source/lowering/runtime surface, the first
# class migrated to an exhaustive contract.

ROOT = File.expand_path("..", __dir__)
RUNTIME_PATH = File.join(ROOT, "runtime", "runtime.c")
QUANTITY_PATH = File.join(ROOT, "core", "quantity.w")
LOWERING_PATH = File.join(ROOT, "compiler", "lib", "lowering", "method_call.w")
LOADER_PATH = File.join(ROOT, "compiler", "lib", "loader.w")
TYPES_PATH = File.join(ROOT, "compiler", "lib", "lowering", "types.w")

# Every instance method on these runtime-backed classes must be classified.
# `native_ic` methods are intercepted by the runtime table even when the
# receiver's concrete type is erased. `source_fallback` methods deliberately
# dispatch through the loaded Core class. `dual_dispatch` names an intentional
# overlap where static/source dispatch and erased/native dispatch use different
# implementations (packed regex literals versus Regex objects, or Float#sqrt,
# for example). `native_declaration` is reserved for constructor/lowering
# contracts that do not use an instance IC row. A bodyless method may only be
# native-backed; listing it as a source fallback is never enough. Adding a
# source method or IC row without choosing one of those contracts is a gate
# failure.
RUNTIME_CLASS_CONTRACTS = {
  "Mmap" => {
    path: "core/mmap.w",
    table: "w_ic_mmap_table",
    dispatch_key: "0x91",
    native_ic: %w[[] byte_at close view_at],
    source_fallback: %w[as_f32 as_f64 as_i16 as_i32 as_i64 as_i8 as_u16 as_u32 as_u64 as_u8 size]
  },
  "Atomic" => {
    path: "core/atomic.w",
    table: "w_ic_atomic_table",
    dispatch_key: "0x01",
    native_ic: %w[add cas get set],
    source_fallback: %w[compare_exchange decrement exchange fetch_add fetch_sub increment load store]
  },
  "Socket" => {
    path: "core/socket.w",
    table: "w_ic_socket_table",
    native_ic: %w[accept alpn_protocol close read read_exact read_into serve_http set_timeout shutdown write write_bytes write_slice],
    source_fallback: []
  },
  "Thread" => {
    path: "core/thread.w",
    table: "w_ic_thread_table",
    dispatch_key: "0x81",
    native_ic: %w[join kill],
    native_declaration: %w[new],
    source_fallback: %w[alive?]
  },
  "Channel" => {
    path: "core/channel.w",
    table: "w_ic_channel_table",
    dispatch_key: "0x84",
    native_ic: %w[close send],
    source_fallback: %w[each receive receive_result recv try_receive try_receive_result try_send]
  },
  "BigArray" => {
    path: "core/big_array.w",
    table: "w_ic_big_array_table",
    dispatch_key: "0x92",
    native_ic: %w[[] []= get push set subview],
    native_only: %w[[] []= get push set subview],
    source_fallback: %w[__enumerable_iteration_mode __replace_elements cap each empty? mergesort! rotate rotate! shuffle shuffle! size sort sort!]
  },
  "SmallArray" => {
    path: "core/small_array.w",
    table: "w_ic_small_array_table",
    dispatch_key: "0x09",
    native_ic: %w[[] []= get set],
    native_only: %w[[] []= get set],
    source_fallback: %w[__enumerable_iteration_mode cap each empty? rotate shuffle size sort]
  },
  "IPv4" => {
    path: "core/ipv4.w",
    table: "w_ic_ipv4_table",
    dispatch_key: "0xE5",
    native_ic: %w[inspect],
    source_fallback: %w[[] a b broadcast broadcast? c cidr? contains? d global? include? link_local? loopback? mask multicast? netmask network octet octets prefix private? reserved? to_i to_s unspecified? with_prefix]
  },
  "IPv6" => {
    path: "core/ipv6.w",
    table: "w_ic_ipv6_table",
    dispatch_key: "0x86",
    native_ic: %w[inspect],
    source_fallback: %w[[] byte bytes cidr? contains? global? include? link_local? loopback? multicast? network prefix private? to_s unique_local? unspecified? with_prefix]
  },
  "MAC" => {
    path: "core/mac.w",
    table: "w_ic_mac_table",
    dispatch_key: "0x85",
    native_ic: %w[inspect],
    source_fallback: %w[[] broadcast? byte bytes local? multicast? to_s unicast? universal?]
  },
  "Hash" => {
    path: "core/hash.w",
    table: "w_ic_hash_table",
    dispatch_key: "0x05",
    native_ic: %w[[] []= delete each get has_key? keys merge! set values],
    native_only: %w[[] []= delete each get has_key? keys set values],
    source_fallback: %w[__enumerable_each __enumerable_iteration_mode __enumerable_yields_pair? each_pair fetch include? invert key? merge size transform_keys transform_values update]
  },
  "StringBuffer" => {
    path: "core/string_buffer.w",
    table: "w_ic_strbuf_table",
    dispatch_key: "0x0B",
    native_ic: %w[<< [] append byte_size clear empty? include? length size starts_with? to_s],
    native_declaration: %w[new],
    source_fallback: []
  },
  "Regex" => {
    path: "core/regex.w",
    table: "w_ic_regex_table",
    dispatch_key: "0x07",
    native_ic: %w[=== =~ match? to_s],
    native_only: %w[=== =~ to_s],
    dual_dispatch: %w[match?],
    source_fallback: %w[
      advance at_end? at_word_boundary? build_result build_skip class_escape_char
      class_match? clex collect_first compile_alt compile_node compile_opt
      compile_plus compile_rep compile_star compute_prefilter consume_at?
      decode_subject emit lazy? literal_prefix lone_flag_class make_saved match
      match? new nullable? parse_alt parse_atom parse_brace parse_class
      parse_escape parse_group parse_int parse_pattern parse_repeat parse_seq peek
      pf_advance pf_bm_search pf_set_match run set_match? set_split
      single_consuming? source span_str word_lex?
    ]
  },
  "BigInt" => {
    path: "core/numeric/big_int.w",
    table: nil,
    retired_table: "w_ic_bigint_table",
    dispatch_key: "0x02",
    native_ic: [],
    source_fallback: %w[% & * + - / << >> ^ abs abs! even? gcd isqrt lcm neg! negative? odd? positive? prime? to_f to_i to_s zero? |]
  },
  "Float" => {
    path: "core/numeric/float.w",
    table: "w_ic_float_table",
    dispatch_key: "0xFF",
    native_ic: %w[sqrt to_i to_s],
    native_only: %w[to_i to_s],
    dual_dispatch: %w[sqrt],
    autoload_guard: "float_source_method_unresolved",
    source_fallback: %w[abs ceil finite? floor infinite? nan? round sq sqrt to_f truncate]
  },
  "Decimal" => {
    path: "core/numeric/decimal.w",
    table: "w_ic_decimal_table",
    dispatch_key: "0xFD",
    native_ic: %w[abs ceil floor round sq sqrt to_d to_f to_i],
    autoload_guard: "decimal_source_method_unresolved",
    source_fallback: %w[arccos arccosh arcsin arcsinh arctan arctanh cos cosh inv normalize reciprocal sin sinh tan tanh to_s]
  },
  "Date" => {
    path: "core/date.w",
    table: "w_ic_date_table",
    dispatch_key: "0xE4",
    native_ic: %w[inspect strftime to_s],
    native_only: %w[inspect],
    source_fallback: %w[
      asctime ctime cwday cweek cwyear day day_abbr day_name day_of_month day_of_quarter
      day_of_week day_of_year days_in_month days_in_year hour jd leap? leap_year?
      minute month month_abbr month_name quarter quarter_abbr second tz
      wday yday year year_with_quarter
    ]
  },
  "String" => {
    path: "core/string_native.w",
    table: "w_ic_string_table",
    dispatch_key: "0xF9",
    native_ic: %w[
      [] << =~ append ascii? codes concat ends_with? gsub include? index lchs
      length ltrim match? ord prepend repeat replace rindex rtrim size slice split
      starts_with? strip to_d to_f to_i to_sym valid_utf8?
    ],
    native_only: %w[
      [] << =~ append ascii? codes concat ends_with? gsub include? index lchs
      ltrim match? ord prepend repeat replace rindex rtrim slice split starts_with?
      strip to_d to_f to_i to_sym valid_utf8?
    ],
    dual_dispatch: %w[length size],
    autoload_guard: "string_source_method_unresolved",
    source_fallback: %w[
      bytes capitalize center chars delete downcase empty? length lpad reverse rpad
      size squeeze swapcase to_s tr upcase
    ]
  },
  "Array" => {
    path: "core/array.w",
    table: "w_ic_array_table",
    dispatch_key: "0x0A",
    native_ic: %w[
      [] []= all? any? clear cos count cross data dot each exp fastsum fill
      find_index get has? include? index last_index log matmul_i8 matvec_i8 max
      min none? pop push raw_ptr replace_byte! scale scale! set shift sin slice
      slice_view sort sqrt stable_sort sum sumsq tan unshift view
    ],
    native_only: %w[
      [] []= all? any? clear cos count cross data dot exp fastsum fill find_index
      get has? include? index last_index log matmul_i8 matvec_i8 max min none? pop
      push raw_ptr replace_byte! scale scale! set shift sin slice slice_view sqrt
      sum sumsq tan unshift view
    ],
    dual_dispatch: %w[each sort stable_sort],
    autoload_guard: "array_source_method_unresolved",
    autoload_methods: %w[compact copy delete_at drop dup flatten join minmax reverse take uniq],
    source_fallback: %w[
      __enumerable_append_to __enumerable_iteration_mode __mergesort_copy
      __replace_elements cap chunk_while compact concat copy csort delete_at drop
      dup each empty? first flatten ipnsort join last mean median mergesort! minmax
      norm normalize pythagorean reverse rotate rotate! shuffle shuffle! size
      skasort sort sort! stable_sort stdev take to_a to_f32 to_f64 transpose
      tsort uniq variance wolfsort
    ]
  }
}.freeze

def instance_method_bodies(class_body)
  lines = class_body.lines
  methods = Hash.new { |hash, key| hash[key] = [] }

  lines.each_with_index do |line, index|
    match = line.match(/^  ->\s+(?!\.)([^\s(]+)/)
    next if match.nil?

    name = match[1]
    name = name.sub(%r{/.*\z}, "") unless name == "/"
    has_body = false
    cursor = index + 1
    while cursor < lines.size
      candidate = lines[cursor]
      stripped = candidate.strip
      if stripped.empty? || stripped.start_with?("#")
        cursor += 1
        next
      end
      has_body = candidate.start_with?("    ")
      break
    end
    methods[name] << has_body
  end

  methods
end

runtime = File.read(RUNTIME_PATH, encoding: "utf-8")
quantity = File.read(QUANTITY_PATH, encoding: "utf-8")
lowering = File.read(LOWERING_PATH, encoding: "utf-8")
loader = File.read(LOADER_PATH, encoding: "utf-8")
types = File.read(TYPES_PATH, encoding: "utf-8")
errors = []

dispatch_keys = types.scan(/^\s*"([^"]+)"\s*=>\s*(0x[0-9A-Fa-f]+)/).to_h

method_names = {}
runtime.scan(/^#define\s+(WN_\w+)\s+W_M\d+\("([^"]+)"\)/) do |constant, name|
  method_names[constant] = name
end
runtime.scan(/^\s*(WN_\w+)\s*=\s*w_string\("([^"]+)"\);/) do |constant, name|
  method_names[constant] = name
end

tables = {}
runtime.scan(/^static WICEntry\s+(w_ic_\w+_table)\[\]\s*=\s*\{(.*?)^\};/m) do |table_name, body|
  handlers = body.scan(/^\s*\{0,\s*([A-Za-z_][A-Za-z0-9_]*|NULL)\s*\}/).flatten
  if handlers.empty? || handlers.last != "NULL"
    errors << "#{table_name}: missing terminal NULL handler"
  end
  tables[table_name] = handlers.take_while { |handler| handler != "NULL" }
end

assignments = Hash.new { |hash, key| hash[key] = {} }
runtime.scan(/^\s*(w_ic_\w+_table)\[(\d+)\]\.name\s*=\s*([^;]+);/) do |table_name, index_text, expression|
  index = Integer(index_text, 10)
  handlers = tables[table_name]
  if handlers.nil?
    errors << "#{table_name}[#{index}]: initializer names an unknown table"
    next
  end
  if index >= handlers.size
    errors << "#{table_name}[#{index}]: initializer exceeds #{handlers.size} live handlers"
    next
  end
  if assignments[table_name].key?(index)
    errors << "#{table_name}[#{index}]: duplicate name initializer"
    next
  end

  name = if (match = expression.match(/\Aw_string\("([^"]+)"\)\z/))
           match[1]
         else
           method_names[expression.strip]
         end
  if name.nil?
    errors << "#{table_name}[#{index}]: unresolved method-name expression #{expression.strip.inspect}"
    next
  end
  assignments[table_name][index] = name
end

quantity_methods = quantity.scan(/^  ->\s+([^\s(]+)/).flatten
quantity_methods.concat(quantity.scan(/^  alias_method\s+:([^\s\/]+)\/\d+,/).flatten)
quantity_methods = quantity_methods.uniq.sort

quantity_gate = lowering.match(
  /if recv_is_known_quantity[^\n]*method_name in \((?<names>[^\n]+)\)/
)
if quantity_gate.nil?
  errors << "lowering: missing recv_is_known_quantity method whitelist"
  lowered_quantity_methods = []
else
  lowered_quantity_methods = quantity_gate[:names].scan(/"([^"]+)"/).flatten.uniq.sort
end

quantity_ic_methods = assignments.fetch("w_ic_quantity_table", {}).values.uniq.sort

{
  "compiler Quantity whitelist" => lowered_quantity_methods,
  "runtime Quantity IC table" => quantity_ic_methods
}.each do |label, actual|
  missing = quantity_methods - actual
  stale = actual - quantity_methods
  errors << "#{label}: missing #{missing.join(', ')}" unless missing.empty?
  errors << "#{label}: not declared by core/quantity.w: #{stale.join(', ')}" unless stale.empty?
end

RUNTIME_CLASS_CONTRACTS.each do |class_name, contract|
  source = File.read(File.join(ROOT, contract[:path]), encoding: "utf-8")
  actual_dispatch_key = dispatch_keys[class_name]
  if contract[:dispatch_key] && actual_dispatch_key != contract[:dispatch_key]
    errors << "#{class_name}: compiler dispatch key #{actual_dispatch_key.inspect}, expected #{contract[:dispatch_key]}"
  end
  body = source[/^\+ #{Regexp.escape(class_name)}(?:\s+<[^\n]+)?\s*$\n(?<body>.*?)(?=^\+ |\z)/m, :body]
  if body.nil?
    errors << "#{class_name}: missing class declaration in #{contract[:path]}"
    next
  end

  method_bodies = instance_method_bodies(body)
  source_methods = method_bodies.keys.sort
  native_methods = contract[:native_ic].uniq.sort
  native_only = contract.fetch(:native_only, []).uniq.sort
  native_declarations = contract.fetch(:native_declaration, []).uniq.sort
  fallback_methods = contract[:source_fallback].uniq.sort
  dual_dispatch = contract.fetch(:dual_dispatch, []).uniq.sort
  declared_native = native_methods - native_only
  classified = (declared_native + native_declarations + fallback_methods).uniq.sort
  overlap = native_methods & fallback_methods
  unexpected_overlap = overlap - dual_dispatch
  missing_overlap = dual_dispatch - overlap
  unless unexpected_overlap.empty?
    errors << "#{class_name}: methods classified as both native IC and source fallback without a dual-dispatch contract: #{unexpected_overlap.join(', ')}"
  end
  unless missing_overlap.empty?
    errors << "#{class_name}: dual-dispatch methods do not overlap native IC and source fallback: #{missing_overlap.join(', ')}"
  end
  invalid_native_only = native_only - native_methods
  errors << "#{class_name}: native-only methods without IC classification: #{invalid_native_only.join(', ')}" unless invalid_native_only.empty?
  declared_native_only = native_only & source_methods
  errors << "#{class_name}: native-only methods also have source declarations: #{declared_native_only.join(', ')}" unless declared_native_only.empty?

  unbacked_bodyless = method_bodies.filter_map do |name, bodies|
    name if bodies.include?(false) && !(native_methods + native_declarations).include?(name)
  end.sort
  unless unbacked_bodyless.empty?
    errors << "#{class_name}: bodyless declarations lack a native contract: #{unbacked_bodyless.join(', ')}"
  end

  unclassified = source_methods - classified
  stale = classified - source_methods
  errors << "#{class_name}: unclassified source methods: #{unclassified.join(', ')}" unless unclassified.empty?
  errors << "#{class_name}: classifications not declared in #{contract[:path]}: #{stale.join(', ')}" unless stale.empty?

  if contract[:autoload_guard]
    guard = Regexp.escape(contract[:autoload_guard])
    trigger = loader.match(/if\s+@#{guard}[^\n]*call_name in \((?<names>[^\n]+)\)\n\s*consider_autoload_name\("#{Regexp.escape(class_name)}"/)
    if trigger.nil?
      errors << "#{class_name}: missing loader trigger for @#{contract[:autoload_guard]}"
    else
      trigger_methods = trigger[:names].scan(/"([^"]+)"/).flatten.uniq.sort
      expected_trigger_methods = contract.fetch(:autoload_methods, fallback_methods).uniq.sort
      missing_trigger = expected_trigger_methods - trigger_methods
      stale_trigger = trigger_methods - expected_trigger_methods
      errors << "#{class_name}: source fallbacks missing loader triggers: #{missing_trigger.join(', ')}" unless missing_trigger.empty?
      errors << "#{class_name}: loader triggers without source fallbacks: #{stale_trigger.join(', ')}" unless stale_trigger.empty?
    end
  end

  if contract[:table] == nil
    retired_table = contract[:retired_table]
    if retired_table != nil && tables.key?(retired_table)
      errors << "#{class_name}: retired runtime IC table still exists: #{retired_table}"
    end
    actual_ic = []
  else
    actual_ic = assignments.fetch(contract[:table], {}).values.uniq.sort
  end
  missing_ic = native_methods - actual_ic
  stale_ic = actual_ic - native_methods
  errors << "#{class_name}: native IC classification missing runtime rows: #{missing_ic.join(', ')}" unless missing_ic.empty?
  errors << "#{class_name}: runtime IC rows not classified native: #{stale_ic.join(', ')}" unless stale_ic.empty?
  if contract[:table] && contract[:dispatch_key]
    table_case = /case\s+#{Regexp.escape(contract[:dispatch_key])}:\s*table\s*=\s*#{Regexp.escape(contract[:table])};/
    errors << "#{class_name}: runtime dispatch key #{contract[:dispatch_key]} does not select #{contract[:table]}" unless runtime.match?(table_case)
  end
end

unless dispatch_keys["Quantity"] == "0xC1" && runtime.include?("case 0xC1: table = w_ic_quantity_table;")
  errors << "Quantity: compiler/runtime semantic dispatch key must be 0xC1"
end

if errors.empty?
  initialized = assignments.values.sum(&:size)
  classified = RUNTIME_CLASS_CONTRACTS.size
  puts "core dispatch contracts: #{tables.size} IC tables, #{initialized} named rows, #{quantity_methods.size} Quantity methods, #{classified} runtime classes consistent"
else
  warn "core dispatch contracts: FAIL (#{errors.size} disagreement#{errors.size == 1 ? '' : 's'})"
  errors.each { |error| warn "  - #{error}" }
  exit 1
end
