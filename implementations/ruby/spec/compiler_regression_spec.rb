# frozen_string_literal: true

require_relative "spec_helper"
require "json"
require "tmpdir"
require "open3"
require "socket"
require "fileutils"

RSpec.describe "Compiler regressions" do
  TUNGSTEN_SOURCE = File.join(PROJECT_ROOT, "compiler/tungsten.w")

  RUNTIME_ARCHIVE = File.join(PROJECT_ROOT, "runtime/runtime.a")

  before(:all) do
    skip "compiled compiler not available" unless File.executable?(TUNGSTEN_BOOTSTRAP)

    runtime_c = File.join(PROJECT_ROOT, "runtime/runtime.c")
    terminal_input_c = File.join(PROJECT_ROOT, "runtime/terminal_input.c")
    metal_m   = File.join(PROJECT_ROOT, "runtime/metal.m")
    needs_rebuild = !File.exist?(RUNTIME_ARCHIVE) || File.mtime(runtime_c) > File.mtime(RUNTIME_ARCHIVE)
    needs_rebuild ||= File.mtime(terminal_input_c) > File.mtime(RUNTIME_ARCHIVE)
    needs_rebuild ||= File.exist?(metal_m) && File.mtime(metal_m) > File.mtime(RUNTIME_ARCHIVE)
    if needs_rebuild
      zstd_cflags = `pkg-config --cflags libzstd 2>/dev/null`.strip
      metal_cmd = ""
      if RUBY_PLATFORM =~ /darwin/ && File.exist?(metal_m)
        metal_cmd = " && clang -O3 -DNDEBUG -fobjc-arc-exceptions -x objective-c -c metal.m"
      end
      # Platform event-loop backend: kqueue on macOS, epoll on Linux. Hardcoding
      # event_kqueue.c left runtime.a without the w_event_* symbols on Linux
      # (kqueue is #ifdef __APPLE__, so it compiles to an empty object there),
      # breaking every link with "undefined symbol: w_event_register/init".
      event_src = RUBY_PLATFORM =~ /darwin/ ? "event_kqueue.c" : "event_epoll.c"
      system("cd #{PROJECT_ROOT}/runtime && clang -O3 -DNDEBUG #{zstd_cflags} -c runtime.c terminal_input.c #{event_src} tls_stub.c aks.c slab_zstd.c#{metal_cmd} && ar rcs runtime.a *.o && rm -f *.o")
    end
  end

  around do |example|
    skip "compiled compiler not available" unless File.executable?(TUNGSTEN_BOOTSTRAP)

    Dir.mktmpdir("compiler-regression-run") do |dir|
      @tmpdir = dir
      @compiler_path = TUNGSTEN_BOOTSTRAP
      example.run
    end
  end

  it "uses reassigned default parameters from their slot" do
    out = compile_and_run("default_param_reassign.w", <<~W)
      -> f(n = 1)
        n = n + 1
        n

      << f()
    W

    expect(out).to eq("2\n")
  end

  it "uses TUNGSTEN_ROOT when a relocated compiler runs from a bit directory" do
    relocated_dir = File.join(@tmpdir, "relocated")
    relocated_compiler = File.join(relocated_dir, "tungsten-compiler")
    bit_dir = File.join(@tmpdir, "nested-bit")
    source_path = File.join(bit_dir, "commented.w")
    bin_path = File.join(@tmpdir, "commented")

    FileUtils.mkdir_p(relocated_dir)
    FileUtils.mkdir_p(bit_dir)
    FileUtils.cp(@compiler_path, relocated_compiler, preserve: true)
    File.write(File.join(bit_dir, "Bitfile"), "name \"nested-bit\"\n")
    File.write(source_path, "# Metaflip command-line entry point.\n\n<< \"ok\"\n")

    env = {
      "TUNGSTEN_ROOT" => PROJECT_ROOT,
      "TUNGSTEN_GPU_DIALECTS" => "none"
    }
    _out, err, status = Open3.capture3(
      env, relocated_compiler, "compile", source_path, "--out", bin_path,
      "--no-lto",
      chdir: bit_dir
    )

    expect(status.success?).to be(true), err
    out, run_err, run_status = Open3.capture3(bin_path)
    expect(run_status.success?).to be(true), run_err
    expect(out).to eq("ok\n")
  end

  it "isolates concurrent LLVM scratch files for equal source basenames" do
    left_dir = File.join(@tmpdir, "left")
    right_dir = File.join(@tmpdir, "right")
    scratch_dir = File.join(@tmpdir, "llvm-scratch")
    FileUtils.mkdir_p([left_dir, right_dir, scratch_dir])
    left_source = File.join(left_dir, "same.w")
    right_source = File.join(right_dir, "same.w")
    left_bin = File.join(@tmpdir, "left-bin")
    right_bin = File.join(@tmpdir, "right-bin")
    File.write(left_source, "<< \"left\"\n")
    File.write(right_source, "<< \"right\"\n")

    env = {
      "TUNGSTEN_ROOT" => PROJECT_ROOT,
      "TUNGSTEN_LL_DIR" => scratch_dir,
      "TUNGSTEN_GPU_DIALECTS" => "none"
    }
    builds = [[left_source, left_bin], [right_source, right_bin]].map do |source, output|
      Thread.new do
        Open3.capture3(env, @compiler_path, "compile", source, "--out", output, "--no-lto")
      end
    end.map(&:value)

    builds.each do |_out, err, status|
      expect(status.success?).to be(true), err
    end
    expect(Open3.capture3(left_bin).first).to eq("left\n")
    expect(Open3.capture3(right_bin).first).to eq("right\n")
    expect(File).to exist(File.join(scratch_dir, "same.ll"))
    expect(Dir.glob(File.join(scratch_dir, "compile.*"))).to be_empty
  end

  it "treats trailing elsif chains as implicit return expressions" do
    out = compile_and_run("elsif_implicit_return.w", <<~W)
      -> f(x)
        if x == 1
          10
        elsif x == 2
          20

      << f(2)
    W

    expect(out).to eq("20\n")
  end

  it "does not keep overflow-prone loop accumulators unboxed" do
    out = compile_and_run("loop_overflow_promotion.w", <<~W)
      x = 140737488355325
      i = 0
      while i < 5
        x += 1
        i += 1
      << x
    W

    expect(out).to eq("140737488355330\n")
  end

  it "wraps a bare >2^48 literal correctly inside a Math.wrap block" do
    out = compile_and_run("math_wrap_bigint_literal.w", <<~W)
      Math.wrap ->
        a = 9000000000000000000
        << a + a
    W

    # 9e18 + 9e18 overflows signed i64 and wraps to -446744073709551616.
    # Regression: a bare >2^48 literal is boxed as a BigInt; the :wrap path used
    # to nanunbox_int the heap pointer and emit non-deterministic garbage. The
    # fix routes wrap operands through ensure_raw_i64 (w_to_i64 = low 64 bits).
    expect(out).to eq("-446744073709551616\n")
  end

  it "wraps inferred raw integer overflow inside Math.wrap blocks" do
    out = compile_and_run("math_wrap_inferred_raw_ints.w", <<~W)
      Math.wrap ->
        << 9223372036854775807 + 1
        << 3037000500 * 3037000500
    W

    expect(out).to eq("-9223372036854775808\n-9223372036709301616\n")
  end

  it "promotes inferred raw integer overflow inside Math.promote blocks" do
    out = compile_and_run("math_promote_inferred_raw_ints.w", <<~W)
      Math.promote ->
        << 9223372036854775807 + 1
        << 3037000500 * 3037000500
    W

    expect(out).to eq("9223372036854775808\n9223372037000250000\n")
  end

  it "keeps overflow modes lexical across method calls" do
    out = compile_and_run("math_overflow_lexical_method_call.w", <<~W)
      -> add_one(x)
        x + 1

      Math.wrap ->
        << 9223372036854775807 + 1
        << add_one(9223372036854775807)
    W

    expect(out).to eq("-9223372036854775808\n9223372036854775808\n")
  end

  it "traps inferred raw integer overflow inside Math.trap blocks" do
    out = compile_and_run("math_trap_no_overflow.w", <<~W)
      Math.trap ->
        << 1 + 2
    W
    expect(out).to eq("3\n")

    source_path = File.join(@tmpdir, "math_trap_inferred_raw_ints.w")
    bin_path = File.join(@tmpdir, "math_trap_inferred_raw_ints")
    File.write(source_path, <<~W)
      Math.trap ->
        << 9223372036854775807 + 1
    W

    compile_args = [@compiler_path, "compile", source_path, "--out", bin_path]
    compile_args += ["--runtime", RUNTIME_ARCHIVE] if File.exist?(RUNTIME_ARCHIVE)
    _compile_out, compile_err, compile_status = Open3.capture3(*compile_args, chdir: PROJECT_ROOT)
    expect(compile_status.success?).to be(true), compile_err

    _run_out, run_err, run_status = Open3.capture3(bin_path)
    expect(run_status.success?).to be_falsey, "expected trap, got success. stderr: #{run_err.inspect}"
  end

  it "lowers exponentiation through the compiled operator path" do
    out = compile_and_run("pow_operator.w", <<~W)
      << 2 ** 8
    W

    expect(out).to eq("256\n")
  end

  it "lowers regex match captures through =~" do
    out = compile_and_run("regex_match_captures.w", <<~W)
      value = "abc123"
      if /([a-z]+)([0-9]+)/ =~ value then << $1
      if /([a-z]+)([0-9]+)/ =~ value then << $2
    W

    expect(out).to eq("abc\n123\n")
  end

  it "accepts StandardError as a built-in superclass" do
    out = compile_and_run("standard_error_superclass.w", <<~W)
      + ConfigError < StandardError

      << "ok"
    W

    expect(out).to eq("ok\n")
  end

  it "treats constant_alias as a compile-time directive" do
    llvm = compile_to_llvm("constant_alias_directive.w", <<~W)
      constant_alias "WC"

      << "ok"
    W

    expect(llvm).not_to include("__w_constant_alias")
  end

  it "infers implicit range block params through compound assignment bodies" do
    out = compile_and_run("implicit_range_compound_assign_param.w", <<~W)
      sum = 0
      1..10 ->
        sum += i

      << sum
    W

    expect(out).to eq("55\n")
  end

  it "does not infer implicit range block params from later sibling statements" do
    out = compile_and_run("implicit_range_compound_assign_no_param.w", <<~W)
      acc = 0
      1..10 ->
        acc += 1

      << acc
    W

    expect(out).to eq("10\n")
  end

  it "passes implicit blocks to class methods that use yield" do
    out = compile_and_run("class_implicit_yield.w", <<~W)
      + Box
        ro :value

        -> new(@value)

        -> configure
          yield @value

      box = Box.new(41)
      result = box.configure -> (value)
        value + 1
      << result
    W

    expect(out).to eq("42\n")
  end

  it "keeps hinted i64 accumulators raw through range loops" do
    llvm = compile_to_llvm("hinted_i64_range_sum.w", <<~W)
      sum = 0 ## i64
      1..10 ->
        sum += i

      << sum
    W

    expect(llvm).to include(" = add i64 ")
    expect(llvm).not_to include("call i64 @w_add")
    expect(llvm).to include("call i64 @w_int(i64 ")
  end

  it "keeps hinted u64 accumulators raw through range loops" do
    llvm = compile_to_llvm("hinted_u64_range_sum.w", <<~W)
      sum = 0 ## u64
      1..10 ->
        sum += i

      << sum
    W

    expect(llvm).to include(" = add i64 ")
    expect(llvm).not_to include("call i64 @w_add")
    expect(llvm).to include("call i64 @w_u64(i64 ")
  end

  it "keeps unhinted ccall_nobox packed-int locals raw" do
    llvm = compile_to_llvm("unhinted_ccall_packed_ints.w", <<~W)
      -> raw_pack(lc, count) (i64[] i64) i64
        pos = 0
        data_ptr = ccall_nobox("w_array_data_ptr", lc)
        tag = 0xFFFC << 48
        t_id = tag | (0x01 << 38)
        len = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x20)
        pos = len + 1
        t_id | (pos << 24) | len
    W

    body = llvm[/define (?:internal )?i64 @#{Regexp.escape(symbol_matching(/\A__w_raw_pack/))}.*?\n}/m]
    expect(body).to include("call i64 @w_array_data_ptr")
    expect(body).to include("call i64 @w_lex32_scan_flag")
    expect(body).to include(" = add i64 ")
    expect(body).to include(" = or i64 ")
    expect(body).to include(" = shl i64 ")
    expect(body).not_to include("call i64 @w_add")
    expect(body).not_to include("call i64 @w_bit_or")
    expect(body).not_to include("call i64 @w_bit_shl")
  end

  it "boxes full-width hinted u64 literals precisely" do
    out = compile_and_run("hinted_u64_max_literal.w", <<~W)
      x = 18446744073709551615 ## u64
      << x
    W

    expect(out).to eq("18446744073709551615\n")
  end

  it "accepts raw wvalue literals and emits tagged hex immediates" do
    source = <<~W
      x = u0xFFF9073656C6966B
      if x == :files
        << "ok"
      else
        << "bad"
    W

    out = compile_and_run("raw_wvalue_literal.w", source)
    llvm = compile_to_llvm("raw_wvalue_literal.w", source)

    expect(out).to eq("ok\n")
    expect(llvm).to include("u0xFFF9073656C6966B")
  end

  it "does not emit unused runtime classes or declarations for a trivial program" do
    llvm = compile_to_llvm("hello_world_trim.w", <<~W)
      << "hello world"
    W

    expect(llvm).to include("@__static_slab")
    expect(llvm).to include("hello world")
    expect(llvm).to include("declare i64 @w_puts(i64) nounwind")
    expect(llvm).not_to include("@class.Socket")
    expect(llvm).not_to include("@class.Response")
    expect(llvm).not_to include("@class.StringBuffer")
    expect(llvm).not_to include("@class.Hammer")
    expect(llvm).not_to include("declare i64 @w_array_new() nounwind")
    expect(llvm).not_to include("declare i64 @w_response_new_wv(i64, i64) nounwind")
    expect(llvm).not_to include("declare void @w_argv_init(i32, ptr) nounwind")
    expect(llvm).not_to include("define internal void @__w_slab_ctor()")
    expect(llvm).not_to include("@llvm.global_ctors")
    expect(llvm).not_to include("\"frame-pointer\"=\"all\"")
    expect(llvm).not_to include(" = or i64 0, 0")
    expect(llvm).not_to match(/%t\d+ = call i64 @w_puts/)
    expect(llvm).to match(/define i32 @main\(\) #\d+ \{/)
    expect(llvm).to match(/attributes #\d+ = \{ nounwind/)
  end

  it "adds frame-pointer attributes only when requested" do
    llvm = compile_to_llvm("hello_world_frame_pointers.w", <<~W, ["--frame-pointers"])
      << "hello world"
    W

    attr_id = llvm[/define i32 @main\(\) #(\d+) \{/, 1]
    expect(attr_id).not_to be_nil
    expect(llvm).to match(/attributes ##{Regexp.escape(attr_id)} = \{ .*nounwind.*"frame-pointer"="all"/)
  end

  it "marks trivial pure runtime helpers with LLVM memory attributes" do
    llvm = compile_to_llvm("runtime_helper_attrs.w", <<~W)
      x = ccall("w_truthy", "truthy")
    W

    expect(llvm).to include("declare i64 @w_truthy(i64) nounwind willreturn memory(none) speculatable alwaysinline")
    expect(llvm).to match(/call i64 @w_truthy\(i64 .*\), !range !\{i64 0, i64 2\}/)
  end

  it "adds range metadata to fixed-tag WValue producers" do
    llvm = compile_to_llvm("fixed_tag_range_metadata.w", <<~W)
      c = U+0041
      ok = ccall("w_eq", c, c)
    W

    expect(llvm).to include("call i64 @w_box_char(i32 65), !range !{i64 -914793674309632, i64 -844424930131968}")
    expect(llvm).to match(/call i64 @w_eq\(i64 .*, i64 .*\), !range !\{i64 1, i64 3\}/)
  end

  it "adds range metadata to proven small WValue int producers" do
    llvm = compile_to_llvm("view_small_int_range_metadata.w", <<~W)
      + Packet
        - data
          u8 tag
          u16 size
          u32 code

        -> byte0
          $bytes[0]

        -> bit0
          $bits[0]

        -> tag
          $data.tag

        -> size
          $data.size

        -> code
          $data.code
    W

    expect(llvm).to include("!range !{i64 -1688849860263936, i64 -1688849860263934}")
    expect(llvm.scan("!range !{i64 -1688849860263936, i64 -1688849860263680}").size).to be >= 2
    expect(llvm).to include("!range !{i64 -1688849860263936, i64 -1688849860198400}")
    expect(llvm).to include("!range !{i64 -1688849860263936, i64 -1688845565296640}")
  end

  it "emits argv init only when ARGV or argv() is used" do
    llvm = compile_to_llvm("argv_needed.w", <<~W)
      args = argv()
      << args.size()
    W

    expect(llvm).to include("declare void @w_argv_init(i32, ptr) nounwind")
    expect(llvm).to match(/define i32 @main\(i32 %argc, ptr %argv\) #\d+ \{/)
    expect(llvm).to include("call void @w_argv_init(i32 %argc, ptr %argv)")
  end

  it "finds argv use nested inside method and block bodies" do
    sources = {
      "nested_argv_call.w" => <<~W,
        -> nested
          [0].map -> argv().size
        << "ok"
      W
      "nested_argv_constant.w" => <<~W,
        -> nested
          [0].map -> ARGV.size
        << "ok"
      W
    }

    sources.each do |name, source|
      llvm = compile_to_llvm(name, source)
      expect(llvm).to match(/define i32 @main\(i32 %argc, ptr %argv\) #\d+ \{/)
      expect(llvm).to include("call void @w_argv_init(i32 %argc, ptr %argv)")
    end
  end

  it "dispatches the compiled Int convenience surface through runtime ICs" do
    out = compile_and_run("compiled_int_surface.w", <<~W)
      x = 0
      << x.zero?
      << x.next
      << x.succ
      << x.prev
      << 255.to_s(16)

      y = 5
      << y.even?
      << y.odd?
      << y.positive?
      << (-1).negative?

      f = 1.to_f
      << f.class
      << f + ~0.5

      big = 999999999999999999999999999999999999
      << big.to_s(16).slice(0, 4)
      << big.odd?
      << big.next.prev == big
    W

    expect(out).to eq(<<~OUT)
      true
      1
      1
      -1
      ff
      false
      true
      true
      true
      Float
      1.5
      c097
      true
      true
    OUT
  end

  it "dispatches the compiled IP, CIDR, and MAC core surface" do
    out = compile_and_run("compiled_network_surface.w", <<~W)
      ip = IPv4.parse("192.168.1.42")
      net = CIDR.parse("192.168.1.0/24")
      any = CIDR.parse("0.0.0.0/0")
      v6 = IPv6.parse("2001:db8::1")
      v6net = CIDR.parse("2001:db8::/32")
      mac = MAC.parse("02-11-22-33-44-55")

      << ip.to_s
      << ip.octet(3)
      << ip.octet(~1.9)
      << ip.octets.size
      << ip.private?
      << ip.global?
      << net.prefix
      << net.network.to_s
      << net.broadcast.to_s
      << net.netmask.to_s
      << net.include?(ip)
      << net.include?(IPv4.parse("192.168.2.1"))
      << any.to_s
      << any.include?(IPv4.parse("8.8.8.8"))
      << v6.byte(0)
      << v6.byte(1)
      << v6net.prefix
      << v6net.include?(v6)
      << v6net.include?(IPv6.parse("2001:db9::1"))
      << mac.to_s
      << mac.byte(0)
      << mac.local?
      << mac.multicast?
    W

    expect(out).to eq(<<~OUT)
      192.168.1.42
      42
      168
      4
      true
      false
      24
      192.168.1.0/24
      192.168.1.255/24
      255.255.255.0
      true
      false
      0.0.0.0/0
      true
      32
      1
      32
      true
      false
      02:11:22:33:44:55
      2
      true
      false
    OUT
  end

  it "dispatches core class methods and runtime ccall helpers under eval mode" do
    source = <<~W
      ip = IPv4.parse("192.168.1.42")
      net = CIDR.parse("192.168.1.0/24")
      v6 = IPv6.parse("2001:db8::1")
      v6net = CIDR.parse("2001:db8::/32")
      mac = MAC.parse("02-11-22-33-44-55")
      uuid = UUID.v4()

      << ip.a
      << net.include?(ip)
      << v6net.include?(v6)
      << mac.local?
      << uuid.version
      << Digest.sha256("abc")
    W

    # Root `rake` has already built and fixed-point-verified this compiler. Use
    # it directly instead of rebuilding compiler/tungsten.w solely to exercise
    # the eval entry point (an otherwise redundant ~12-second compile).
    out, err, status = Open3.capture3(@compiler_path, "-e", source, chdir: PROJECT_ROOT)
    expect(status.success?).to be(true), err
    expect(out).to eq(<<~OUT)
      192
      true
      true
      true
      v4
      ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
    OUT
  end

  it "exposes packed receiver bits through $value under eval mode" do
    source = <<~W
      + IPv4
        -> raw_address
          ($value >> 12) & 0xFFFFFFFF

        -> raw_prefix
          ($value >> 6) & 0x3F

      + Nil
        -> raw_value
          $value

        -> raw_default(value = $value)
          value

      << 192.168.1.42.raw_address
      << (10.0.0.0/8).raw_prefix
      << nil.raw_value
      << nil.raw_default
    W

    out, err, status = Open3.capture3(@compiler_path, "-e", source, chdir: PROJECT_ROOT)
    expect(status.success?).to be(true), err
    expect(out).to eq("3232235818\n8\n0\n0\n")
  end

  it "autoloads source-defined Integer methods under eval mode" do
    source = <<~W
      << 0.prev
      << 0.succ
      << 0.next
      << 0.zero?
      << (-1).negative?
      << 1.positive?
      << 3.sq
      << 4.even?
      << 5.odd?
      << 140_737_488_355_327.succ
      << (-140_737_488_355_328).prev
    W

    out, err, status = Open3.capture3(@compiler_path, "-e", source, chdir: PROJECT_ROOT)
    expect(status.success?).to be(true), err
    expect(out).to eq(<<~OUT)
      -1
      1
      1
      true
      true
      true
      9
      true
      true
      140737488355328
      -140737488355329
    OUT
  end

  it "keeps a real $value global visible through a global function called by a method" do
    source = <<~W
      $value = 17

      -> global_value
        $value

      + ValueReader
        -> read
          global_value()

      << ValueReader.new.read
    W

    out, err, status = Open3.capture3(@compiler_path, "-e", source, chdir: PROJECT_ROOT)
    expect(status.success?).to be(true), err
    expect(out).to eq("17\n")
  end

  it "runs native-backed IPv4 Tungsten methods under eval mode" do
    source = <<~W
      ip = 192.168.1.42
      net = 192.168.1.42/24

      << (10.0.0.0/8).prefix
      << ip.private?
      << 8.8.8.8.global?
      << ip.octet(0)
      << ip[3]
      << (ip.octet(-1) == nil)
      << (ip[4] == nil)
      << ip.with_prefix(16).to_s
      << (ip.with_prefix(nil).prefix == nil)
      << net.network.to_s
      << net.broadcast.to_s
      << net.netmask.to_s
      << net.include?(ip)
      << net.contains?(192.168.2.1)
      << net.include?(nil)
    W

    out, err, status = Open3.capture3(@compiler_path, "-e", source, chdir: PROJECT_ROOT)
    expect(status.success?).to be(true), err
    expect(out).to eq(<<~OUT)
      8
      true
      true
      192
      42
      true
      true
      192.168.1.42/16
      true
      192.168.1.0/24
      192.168.1.255/24
      255.255.255.0
      true
      false
      false
    OUT
  end

  it "autoloads IPv4 methods for literal-only compiled calls" do
    llvm = compile_to_llvm("ipv4_literal_autoload.w", <<~W)
      << 10.0.0.1.private?
      << (192.168.0.0/16).prefix
      << 10.0.0.1.to_i
      << (192.168.1.42/24).network.to_i
      << (192.168.1.42/24).broadcast.to_i
      << (192.168.1.42/24).netmask.to_i
      << (192.168.1.0/24).include?(192.168.1.42)
      << (192.168.1.0/24).contains?(192.168.2.1)
    W

    private_fn = symbol_for("__w_IPv4_private_Q__a1")
    prefix_fn = symbol_for("__w_IPv4_prefix__a1")
    to_i_fn = symbol_for("__w_IPv4_to_i__a1")
    expect(llvm).to include("define internal i64 @#{private_fn}(")
    expect(llvm).to include("define internal i64 @#{prefix_fn}(")
    expect(llvm).to include("define internal i64 @#{to_i_fn}(")

    [private_fn, prefix_fn, to_i_fn].each do |symbol|
      body = llvm[/define internal i64 @#{Regexp.escape(symbol)}\(.*?\n}/m]
      expect(body).not_to be_nil
      expect(body).to match(/[al]shr i64/)
      expect(body).to include("and i64")
      expect(body).not_to include("@w_bit_shr")
      expect(body).not_to include("@w_bit_and")
      expect(body).not_to include("@w_eq")
    end

    native_value_fns = [
      symbol_for("__w_IPv4_network__a1"),
      symbol_for("__w_IPv4_broadcast__a1"),
      symbol_for("__w_IPv4_netmask__a1"),
      symbol_for("__w_IPv4_include_Q__a2"),
      symbol_for("__w_IPv4_contains_Q__a2")
    ].uniq
    native_value_fns.each do |symbol|
      body = llvm[/define internal i64 @#{Regexp.escape(symbol)}\(.*?\n}/m]
      expect(body).not_to be_nil
      expect(body).to match(/[al]shr i64/)
      expect(body).to include("and i64")
      expect(body).not_to include("@w_ipv4_")
      expect(body).not_to include("@w_bit_")
      expect(body).not_to include("@w_to_i64")
    end
  end

  it "autoloads native Date methods for a compiled ccall result" do
    out = compile_and_run("date_ccall_result_autoload.w", <<~W)
      value = ccall("w_date", 2024, 2, 29, 0, 0, 0, 0)
      << value.year
      << value.leap?
      << value.day_of_year
    W

    expect(out).to eq("2024\ntrue\n60\n")
  end

  it "autoloads native network methods for compiled ccall constructors and storage returns" do
    out = compile_and_run("network_ccall_result_autoload.w", <<~W)
      ip4 = ccall("w_ipv4_parse", "192.168.1.42/24")
      ip6 = ccall("w_ipv6_storage_from_words", 0x20010DB8, 0, 0, 1, 64)
      mac = ccall("w_mac_parse", "02:11:22:33:44:55")

      << ip4.network.to_s
      << ip6.prefix
      << ip6.network.to_s
      << mac.local?
    W

    expect(out).to eq("192.168.1.0/24\n64\n2001:db8:0:0:0:0:0:0/64\ntrue\n")
  end

  it "does not autoload native value classes for unrelated ccalls" do
    compile_to_llvm("unrelated_ccall_autoload.w", <<~W)
      << ccall("w_truthy", "truthy")
    W

    emitted_originals = last_sidemap.fetch("hashes").values.flat_map do |entry|
      entry.fetch("originals").map { |item| item.fetch("symbol") }
    end
    expect(emitted_originals).not_to include(
      "__w_Date_year__a1",
      "__w_IPv4_prefix__a1",
      "__w_IPv6_prefix__a1",
      "__w_MAC_local_Q__a1"
    )
  end

  it "loads the core IPv4 definition before a user reopen" do
    out = compile_and_run("ipv4_core_reopen.w", <<~W)
      + IPv4
        -> marker
          7

      ip = 1.2.3.4
      << ip.marker
      << ip.to_i
    W

    expect(out).to eq("7\n16909060\n")
  end

  it "loads the core IPv4 definition before a user reopen under eval mode" do
    source = <<~W
      + IPv4
        -> marker
          7

      ip = 1.2.3.4
      << ip.marker
      << ip.to_i
    W

    out, err, status = Open3.capture3(@compiler_path, "-e", source, chdir: PROJECT_ROOT)
    expect(status.success?).to be(true), err
    expect(out).to eq("7\n16909060\n")
  end

  it "dispatches the compiled crypto and UUID core surface" do
    out = compile_and_run("compiled_crypto_uuid.w", <<~W)
      md5 = Digest.md5("abc")
      sha1 = Digest.sha1("abc")
      ws_accept = Digest.sha1_base64("dGhlIHNhbXBsZSBub25jZQ==258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
      sha224 = Digest.sha224("abc")
      sha256 = Digest.sha256("abc")
      sha384 = Digest.sha384("abc")
      sha512 = Digest.sha512("abc")
      sha512_224 = Digest.sha512_224("abc")
      sha512_256 = Digest.sha512_256("abc")
      sha2_224 = Digest.sha2("abc", 224)
      sha2_256 = Digest.sha2("abc")
      sha2_384 = Digest.sha2("abc", 384)
      sha2_512 = Digest.sha2("abc", 512)
      sha2_512_224 = Digest.sha2("abc", "512/224")
      sha2_512_256 = Digest.sha2("abc", "512/256")
      crypto_sha256 = Crypto.sha256("abc")
      crypto_sha512 = Crypto.sha512("abc")
      crypto_sha2_512_256 = Crypto.sha2("abc", "512/256")
      random_size = Crypto.random_bytes(8).size

      << md5
      << sha1
      << ws_accept
      << sha224
      << sha256
      << sha384
      << sha512
      << sha512_224
      << sha512_256
      << sha2_224
      << sha2_256
      << sha2_384
      << sha2_512
      << sha2_512_224
      << sha2_512_256
      << crypto_sha256
      << crypto_sha512
      << crypto_sha2_512_256
      << Digest.sha224_bytes("abc").size
      << Digest.sha256_bytes("abc").size
      << Digest.sha384_bytes("abc").size
      << Digest.sha512_bytes("abc").size
      << Digest.sha512_224_bytes("abc").size
      << Digest.sha512_256_bytes("abc").size
      << random_size

      v1 = UUID.v1()
      << (v1.version == :v1)
      << (v1.variant == :rfc4122)

      v1_custom = UUID.v1({time: 0, mac: [2, 17, 34, 51, 68, 85]})
      << (v1_custom.byte(10) == 2)
      << (v1_custom.byte(11) == 17)
      << (v1_custom.byte(12) == 34)
      << (v1_custom.byte(13) == 51)
      << (v1_custom.byte(14) == 68)
      << (v1_custom.byte(15) == 85)

      v2 = UUID.v2({local_identifier: 123, domain: 1, time: 0, mac: [2, 17, 34, 51, 68, 85]})
      << (v2.version == :v2)
      << (v2.variant == :rfc4122)
      << (v2.byte(9) == 1)
      << (v2.byte(10) == 2)
      << (v2.byte(11) == 17)
      << (v2.byte(12) == 34)
      << (v2.byte(13) == 51)
      << (v2.byte(14) == 68)
      << (v2.byte(15) == 85)

      v3 = UUID.v3(UUID.dns(), "www.example.com")
      << (v3.version == :v3)
      << (v3.variant == :rfc4122)

      u = UUID.v4()
      << (u.version == :v4)
      << (u.variant == :rfc4122)
      << u.to_s.size

      v5 = UUID.v5(UUID.dns(), "www.example.com")
      << (v5.version == :v5)
      << (v5.variant == :rfc4122)

      v6 = UUID.v6()
      << (v6.version == :v6)
      << (v6.variant == :rfc4122)

      v7 = UUID.v7()
      << (v7.version == :v7)
      << (v7.variant == :rfc4122)

      v8 = UUID.v8()
      << (v8.version == :v8)
      << (v8.variant == :rfc4122)
      << UUID.v8(Digest.md5_bytes("abc"))

      parsed = UUID.parse("urn:uuid:2ed6657d-e927-568b-95e1-2665a8aea6a2")
      random_uuid = Random.uuid

      << v3
      << v5
      << parsed
      << (random_uuid.version == :v4)
      << (Random.uuid1().version == :v1)
      << (Random.uuid2({local_identifier: 123, domain: 1}).version == :v2)
      << (Random.uuid3(UUID.dns(), "www.example.com").version == :v3)
      << (Random.uuid4().version == :v4)
      << (Random.uuid5(UUID.dns(), "www.example.com").version == :v5)
      << (Random.uuid6().version == :v6)
      << (Random.uuid7().version == :v7)
      << (Random.uuid8().version == :v8)
    W

    expect(out).to eq(<<~OUT)
      900150983cd24fb0d6963f7d28e17f72
      a9993e364706816aba3e25717850c26c9cd0d89d
      s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
      23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7
      ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
      cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7
      ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f
      4634270f707b6a54daae7530460842e20e37ed265ceee9a43e8924aa
      53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23
      23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7
      ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
      cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7
      ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f
      4634270f707b6a54daae7530460842e20e37ed265ceee9a43e8924aa
      53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23
      ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
      ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f
      53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23
      28
      32
      48
      64
      28
      32
      8
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      36
      true
      true
      true
      true
      true
      true
      true
      true
      90015098-3cd2-8fb0-9696-3f7d28e17f72
      5df41881-3aed-3515-88a7-2f4a814cf09e
      2ed6657d-e927-568b-95e1-2665a8aea6a2
      2ed6657d-e927-568b-95e1-2665a8aea6a2
      true
      true
      true
      true
      true
      true
      true
      true
      true
    OUT
  end

  it "routes long generated runtime names through WValue helpers" do
    source = <<~W
      + RidiculouslyLongClassNameThatExceedsSixtyOneBytesForHeapRegistration
        -> new(value)
          @ridiculously_long_instance_variable_name_that_exceeds_sixty_one_bytes_for_heap = value

        -> ridiculously_long_method_name_that_exceeds_sixty_one_bytes_for_heap_registration
          @ridiculously_long_instance_variable_name_that_exceeds_sixty_one_bytes_for_heap

      obj = RidiculouslyLongClassNameThatExceedsSixtyOneBytesForHeapRegistration.new(42)
      << obj.ridiculously_long_method_name_that_exceeds_sixty_one_bytes_for_heap_registration().to_s
    W

    expect(compile_and_run("long_runtime_names_wv.w", source)).to eq("42\n")
    llvm = compile_to_llvm("long_runtime_names_wv.w", source)

    expect(llvm).to include("call i64 @w_string(ptr")
    expect(llvm).to include("@w_class_new_wv")
    expect(llvm).to include("@w_class_add_method_wv")
    expect(llvm).to include("@w_class_add_ivar_wv")
    expect(llvm).not_to include("declare i64 @w_class_new(ptr")
    expect(llvm).not_to include("declare void @w_class_add_method(i64, ptr")
    expect(llvm).not_to include("declare i32 @w_class_add_ivar(i64, ptr")
  end

  it "keeps string mutator and format parity for compiled rosetta cases" do
    out = compile_and_run("string_mutator_parity.w", <<~W)
      size = "little"
      << "Mary had a [size] lamb."
      << "Mary had a %s lamb." % size

      s = "Hello wo"
      s += "rld"
      s << "!"
      << s

      s = "llo world"
      s.prepend("He")
      << s

      s = "hello"
      s << " appended"
      << s
      s = "hello"
      << s.concat(" literal")
      << s
      << s.prepend("She said: ")
      << s

      "alphaBETA".swapcase
      "alphaBETA".capitalize
    W

    expect(out).to eq(<<~OUT)
      Mary had a little lamb.
      Mary had a little lamb.
      Hello world!
      Hello world
      hello appended
      hello literal
      hello literal
      She said: hello literal
      She said: hello literal
    OUT
  end

  it "keeps two-argument memoized fn recursion correct" do
    out = compile_and_run("memoized_mutual_recursion.w", <<~W)
      fn g(m, n)
        if n == 0
          return f(m - 1, 1)
        return f(m - 1, f(m, n - 1))

      fn f(m, n)
        if m == 0
          return n + 1
        return g(m, n)

      << f(3, 2)
      << f(3, 3)
      << f(3, 4)
    W

    expect(out).to eq("29\n61\n125\n")
  end

  it "parses type hint headers before function definitions" do
    out = compile_and_run("type_hint_header_fn.w", <<~W)
      ## i32 i, j, k
      fn demo
        1

      << demo
    W

    expect(out).to eq("1\n")
  end

  it "lowers hinted u128 arithmetic to LLVM i128 ops" do
    llvm = compile_to_llvm("hinted_u128_mul_compare.w", <<~W)
      x = 0xFFFFFFFFFFFFFFFF ## u64
      y = x ## u128
      z = y * y ## u128
      if z > y
        << "ok"
      end
    W

    expect(llvm).to include("mul i128")
    expect(llvm).to include("icmp ugt i128")
    expect(llvm).to include("zext i64")
  end

  it "emits compact slab headers without inline hashes" do
    llvm = compile_to_llvm("static_slab_layout.w", <<~W)
      << "hello world"
    W

    expect(llvm).to include("@__static_slab")
    expect(llvm).to match(/@__static_slab = private constant \[\d+ x i8\] c".*", align 8/)
    expect(llvm).to match(/@__static_slab = .*c"(?:\\00){32}\\01\\0bhello world/m)
    expect(llvm).not_to match(/@__static_slab = .*c"(?:\\00){40}\\0b\\01hello world/m)
  end

  it "keeps unrelated and dynamic empty? calls off the String autoload path" do
    source = <<~W
      text = ""
      values = []
      << text.empty?
      << values.empty?
    W

    expect(compile_and_run("dynamic_empty_fallback.w", source)).to eq("true\ntrue\n")
    compile_to_llvm("dynamic_empty_fallback.w", source)
    expect(File.read(@last_sidemap_path)).not_to include("__w_String_empty_Q__a1")
  end

  it "autoloads the source String#empty? body for a proven String receiver" do
    llvm = compile_to_llvm("literal_string_empty_autoload.w", <<~W)
      << "".empty?
    W

    symbol = symbol_for("__w_String_empty_Q__a1")
    body = llvm[/define internal i64 @#{Regexp.escape(symbol)}\(.*?^\}/m]
    expect(body).not_to be_nil
    expect(body).to include("and i64")
    expect(body).not_to include("@w_method_call")
  end

  it "supports zstd-compressed static slab blobs" do
    llvm = compile_to_llvm("static_slab_zstd.w", <<~W, ["--intern", "zstd"])
      << "hello world"
    W

    expect(llvm).to include("@__static_slab_zstd")
    expect(llvm).to match(/@__static_slab_zstd = private constant \[\d+ x i8\] c".*", align 8/)
    expect(llvm).to include("declare void @w_slab_init_static_zstd(ptr, i32, i32)")
    expect(llvm).to include("call void @w_slab_init_static_zstd(ptr @__static_slab_zstd")
    expect(llvm).not_to include("@__static_slab = private constant")
  end

  it "keeps 61-byte literals in the slab" do
    llvm = compile_to_llvm("static_slab_61.w", <<~W)
      << "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ123456789"
    W

    expect(llvm).to include("@__static_slab")
    expect(llvm).to match(/@__static_slab = .*\\03\\3dabcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ123456789\\00", align 8/m)
  end

  it "runs binaries compiled with zstd slab encoding" do
    out = compile_and_run("static_slab_zstd_run.w", <<~W, ["--intern", "zstd"])
      << "hello world"
    W

    expect(out).to eq("hello world\n")
  end

  it "dispatches JSON.parse through class vtable after intrinsic removal" do
    # Phase 0c: the JSON intrinsic bypass was removed from lowering.w;
    # JSON.parse now routes through the class method vtable to core's
    # recursive-descent parser. BIT_HOME=/nonexistent disables bit
    # resolution so this test exercises the core path in isolation
    # (the tungsten-json bit's own parse is tested separately).
    out = compile_and_run("json_vtable_regression.w", <<~W, [], env: {"BIT_HOME" => "/nonexistent"})
      use json
      r = JSON.parse("{\\"a\\":1}")
      << r["a"].to_s
    W

    expect(out).to eq("1\n")
  end

  it "handles += on a function parameter inside a while loop" do
    # Phase 0c discovered a pre-existing compiler bug: `n += 1` on a
    # typed-nil parameter inside a loop hit the string-append fast path
    # in lower_compound_assign, corrupting the value and hanging the
    # loop. Fix: require `lt == :string` (not `lt == nil`) to enter
    # the string-append path.
    out = compile_and_run("param_compound_loop.w", <<~W)
      -> count_up(n)
        while n < 5
          n += 1
        n

      << count_up(0).to_s
    W

    expect(out).to eq("5\n")
  end

  it "formats lex errors with source context and caret" do
    # Phase 1: raise sites in lexer.w emit structured :compile_error hashes
    # that the top-level driver routes through error_formatter.format.
    source_path = File.join(@tmpdir, "bad_lex.w")
    File.write(source_path, "x = 1\ny = 2\nz = `\nw = 4\n")

    _compile_out, compile_err, compile_status = Open3.capture3(
      {"NO_COLOR" => "1"}, @compiler_path, "compile", source_path,
      "--out", File.join(@tmpdir, "bad_lex"),
      chdir: PROJECT_ROOT
    )
    expect(compile_status.success?).to be(false)
    expect(compile_err + _compile_out).to include("error: Unexpected character '`'")
    expect(compile_err + _compile_out).to include("bad_lex.w:3:5")
    expect(compile_err + _compile_out).to match(/3 \| z = `/)
    expect(compile_err + _compile_out).to match(/\|\s+\^/)
  end

  it "formats parse errors with source context" do
    source_path = File.join(@tmpdir, "bad_parse.w")
    File.write(source_path, "x = 1\ny = )\nz = 3\n")

    _compile_out, compile_err, compile_status = Open3.capture3(
      {"NO_COLOR" => "1"}, @compiler_path, "compile", source_path,
      "--out", File.join(@tmpdir, "bad_parse"),
      chdir: PROJECT_ROOT
    )
    expect(compile_status.success?).to be(false)
    expect(compile_err + _compile_out).to include("error: Unexpected token")
    expect(compile_err + _compile_out).to include("bad_parse.w:2:5")
  end

  it "supports `in` operator with space-separated tuple" do
    out = compile_and_run("in_op_match.w", <<~W)
      c = 0x29
      if c in (0x28 0x29 0x3B)
        << "match"
      else
        << "no match"
    W
    expect(out).to eq("match\n")
  end

  it "`in` operator returns false for non-members" do
    out = compile_and_run("in_op_no_match.w", <<~W)
      c = 0x42
      if c in (0x28 0x29 0x3B)
        << "match"
      else
        << "no match"
    W
    expect(out).to eq("no match\n")
  end

  it "`in` operator with single element rewrites to ==" do
    out = compile_and_run("in_op_single.w", <<~W)
      c = 0x42
      if c in (0x42)
        << "match"
    W
    expect(out).to eq("match\n")
  end

  it "`in` operator binds tighter than && for natural composition" do
    out = compile_and_run("in_op_and.w", <<~W)
      c = 0x29
      d = 5
      if c in (0x28 0x29 0x3B) && d > 0
        << "both"
      else
        << "not both"
    W
    expect(out).to eq("both\n")
  end

  it "fixed-point inference resolves recursive fn return type (Phase 3b)" do
    out = compile_and_run("recur_fact.w", <<~W)
      fn fact(n)
        if n <= 1
          return 1
        return n * fact(n - 1)

      << fact(10).to_s
    W
    expect(out).to eq("3628800\n")
  end

  it "fixed-point inference resolves mutually recursive fns (Phase 3b)" do
    out = compile_and_run("recur_mutual.w", <<~W)
      fn is_even(n)
        if n == 0
          return true
        return is_odd(n - 1)

      fn is_odd(n)
        if n == 0
          return false
        return is_even(n - 1)

      if is_even(10)
        << "10 is even"
      if is_odd(7)
        << "7 is odd"
    W
    expect(out).to eq("10 is even\n7 is odd\n")
  end

  it "fixed-point inference resolves a call chain a → b → c (Phase 3b)" do
    out = compile_and_run("chain_infer.w", <<~W)
      fn c(n)
        n + 3

      fn b(n)
        c(n) + 2

      fn a(n)
        b(n) + 1

      << a(10).to_s
    W
    expect(out).to eq("16\n")
  end

  it "method accumulator form with int seed returns accumulated value" do
    out = compile_and_run("method_accumulator_int.w", <<~W)
      -> sum_to(n) 0
        i = 0
        while i < n
          out += i
          i += 1

      << sum_to(10).to_s
      << sum_to(100).to_s
    W
    expect(out).to eq("45\n4950\n")
  end

  it "method accumulator form with acc name works" do
    out = compile_and_run("method_accumulator_acc.w", <<~W)
      -> product(n) 1
        i = 1
        while i <= n
          acc *= i
          i += 1

      << product(5).to_s
      << product(10).to_s
    W
    expect(out).to eq("120\n3628800\n")
  end

  it "method accumulator form with array seed builds the array" do
    out = compile_and_run("method_accumulator_array.w", <<~W)
      -> build_list(n) []
        i = 0
        while i < n
          out.push(i * 2)
          i += 1

      r = build_list(5)
      << r.size.to_s
      << r[0].to_s
      << r[4].to_s
    W
    expect(out).to eq("5\n0\n8\n")
  end

  it "Array#unshift prepends value, bumping start pointer backward" do
    out = compile_and_run("array_unshift.w", <<~W)
      a = [2, 3, 4]
      a.unshift(1)
      << a.size.to_s
      << a[0].to_s
      << a[3].to_s
    W
    expect(out).to eq("4\n1\n4\n")
  end

  it "Array#shift + Array#unshift pair uses start-pointer fast path" do
    out = compile_and_run("array_shift_unshift.w", <<~W)
      b = [10, 20, 30]
      s = b.shift
      << s.to_s
      b.unshift(5)
      << b[0].to_s
      << b.size.to_s
    W
    expect(out).to eq("10\n5\n3\n")
  end

  it "TypedArray#unshift prepends value to typed buffer" do
    out = compile_and_run("typed_array_unshift.w", <<~W)
      t = i32[3]
      t[0] = 100
      t[1] = 200
      t[2] = 300
      t.unshift(50)
      << t.size.to_s
      << t[0].to_s
      << t[1].to_s
      << t[3].to_s
    W
    expect(out).to eq("4\n50\n100\n300\n")
  end

  it "lowers machine typed-array numeric kernels directly" do
    # `T[N]` now allocates size = cap = N (zero-filled), so the test
    # populates slots by indexed write rather than the legacy push-to-fill.
    source = <<~W
      u8s = u8[3]
      u8s[0] = 1
      u8s[1] = 255
      u8s[2] = 3
      << "u8 [u8s.min()] [u8s.max()] [u8s.sum()]"

      u4s = u4[3]
      u4s[0] = 1
      u4s[1] = 15
      u4s[2] = 3
      << "u4 [u4s.min()] [u4s.max()] [u4s.sum()] [u4s[1]]"

      i8s = i8[3]
      i8s[0] = -2
      i8s[1] = 3
      i8s[2] = -1
      << "i8 [i8s.min()] [i8s.max()] [i8s.sum()]"

      i4s = i4[3]
      i4s[0] = -2
      i4s[1] = 3
      i4s[2] = -1
      << "i4 [i4s.min()] [i4s.max()] [i4s.sum()] [i4s[0]]"

      u16s = u16[2]
      u16s[0] = 65535
      u16s[1] = 7
      << "u16 [u16s.min()] [u16s.max()] [u16s.sum()]"

      i16s = i16[2]
      i16s[0] = -20
      i16s[1] = 7
      << "i16 [i16s.min()] [i16s.max()] [i16s.sum()]"

      u32s = u32[2]
      u32s[0] = 4000000000
      u32s[1] = 7
      << "u32 [u32s.min()] [u32s.max()] [u32s.sum()]"

      i32s = i32[2]
      i32s[0] = -20
      i32s[1] = 7
      << "i32 [i32s.min()] [i32s.max()] [i32s.sum()]"

      u64s = u64[2]
      u64s[0] = 5
      u64s[1] = 7
      << "u64 [u64s.min()] [u64s.max()] [u64s.sum()]"

      i64s = i64[2]
      i64s[0] = -5
      i64s[1] = 7
      << "i64 [i64s.min()] [i64s.max()] [i64s.sum()]"

      f64s = f64[3]
      f64s[0] = ~4.0
      f64s[1] = ~9.0
      f64s[2] = ~16.0
      roots = f64s.sqrt()
      f64_plus = f64s[1] + ~1.0
      << "f64 [f64s.min()] [f64s.max()] [f64s.sum()] [f64_plus] [roots.size()] [roots[0]] [roots[2]]"

      f32s = f32[3]
      f32s[0] = ~4.0
      f32s[1] = ~9.0
      f32s[2] = ~16.0
      f32_roots = f32s.sqrt()
      f32_plus = f32s[1] + ~1.0
      << "f32 [f32s[0]] [f32s.min()] [f32s.max()] [f32s.sum()] [f32_plus] [f32_roots.size()] [f32_roots[0]] [f32_roots[2]]"

      cos_src = u8[2]
      cos_src[0] = 0
      cos_src[1] = 1
      cos_out = cos_src.cos()
      << "cos [cos_out.size()] [cos_out[0]]"
    W

    out = compile_and_run("typed_array_numeric_kernels.w", source)
    expect(out).to eq(<<~OUT)
      u8 1 255 259
      u4 1 15 19 15
      i8 -2 3 0
      i4 -2 3 0 -2
      u16 7 65535 65542
      i16 -20 7 -13
      u32 7 4000000000 4000000007
      i32 -20 7 -13
      u64 5 7 12
      i64 -5 7 2
      f64 4 16 29 10 3 2 4
      f32 4 4 16 29 10 3 2 4
      cos 2 1
    OUT

    llvm = compile_to_llvm("typed_array_numeric_kernels.w", source)
    expect(llvm).to include("call i64 @w_array_zeros(i64 4")
    expect(llvm).to include("call i64 @w_array_zeros(i64 -32")
    expect(llvm).to include("call i64 @w_array_min_unsigned")
    expect(llvm).to include("call i64 @w_array_min_signed")
    expect(llvm).to include("call i64 @w_array_min_float")
    expect(llvm).to include("call i64 @w_array_cos_unsigned")
    # Elementwise sqrt now fuses into typed loops and calls libm directly;
    # retaining the old whole-array runtime kernel would be a regression.
    expect(llvm).to include("call double @sqrt(double")
    expect(llvm).not_to include("call i64 @w_array_sqrt_float")
  end

  it "preserves stacktrace metadata through llvm.used" do
    llvm = compile_to_llvm("llvm_low_level_hints.w", <<~W)
      << "metadata"
    W

    expect(llvm).to include("@llvm.used = appending global")
    expect(llvm).to include("ptr @__w_fn_meta")
    expect(llvm).to include("ptr @__w_call_site")
  end

  it "parses `(i64 i64) i64 : body` fully-annotated method signature (Phase 3)" do
    out = compile_and_run("phase3_fully_typed.w", <<~W)
      -> add(a, b) (i64 i64) i64 : a + b
      << add(3, 4).to_s
    W
    expect(out).to eq("7\n")
  end

  it "parses return-type-only annotation `i64 : body` (Phase 3)" do
    out = compile_and_run("phase3_return_type_only.w", <<~W)
      -> mult(x, y) i64 : x * y
      << mult(5, 6).to_s
    W
    expect(out).to eq("30\n")
  end

  it "parses param-types-only annotation `(i64 i64) : body` (Phase 3)" do
    out = compile_and_run("phase3_param_types_only.w", <<~W)
      -> diff(a, b) (i64 i64) : a - b
      << diff(10, 3).to_s
    W
    expect(out).to eq("7\n")
  end

  it "parses naked `:` inline-body form with no annotations (Phase 3)" do
    out = compile_and_run("phase3_naked_inline.w", <<~W)
      -> pick(p, q) : p + q
      << pick(7, 8).to_s
    W
    expect(out).to eq("15\n")
  end

  it "keeps untyped back-compat: bare trailing expression still works (Phase 3)" do
    out = compile_and_run("phase3_untyped_backcompat.w", <<~W)
      -> greet(name)
        "hi " + name

      << greet("world")
    W
    expect(out).to eq("hi world\n")
  end

  it "parses fully-typed signature with post-body fallthrough `: body : default` (Phase 3)" do
    # The post-body `: default` form pushes `default` onto the body as
    # the last statement. Since Tungsten returns the last expression,
    # the fallthrough value ends up being what the method returns when
    # nothing else in the body was the tail. Here the inline body `v`
    # is followed by the fallthrough `0`, so `0` becomes the final
    # statement and the return value.
    out = compile_and_run("phase3_fallthrough.w", <<~W)
      -> maybe(flag, v) i64 : v : 0
      << maybe(true, 42).to_s
    W
    expect(out).to eq("0\n")
  end

  it "resolves typed overloads statically from inferred argument types" do
    llvm = compile_to_llvm("typed_overloads_static.w", <<~W)
      -> add(x, y) (i64 i64) i64
        x + y

      -> add(x, y) (string string) string
        x + y

      << add(1, 2)
      << add("a", "b")
    W

    main = llvm[/define i32 @main.*?\n}/m]
    add_i64 = symbol_for("__w_add__i64_i64")
    add_string = symbol_for("__w_add__string_string")
    expect(llvm).to match(/define internal i64 @#{Regexp.escape(add_i64)}/)
    expect(llvm).to match(/define internal i64 @#{Regexp.escape(add_string)}/)
    expect(main).to include("call i64 @#{add_i64}")
    expect(main).to include("call i64 @#{add_string}")
    expect(main).not_to include("call i64 @__w_add(")
    expect(main).not_to include("@w_method_call_cached")
  end

  it "lowers synthesized operator-overload gates and workers as direct calls" do
    llvm = compile_to_llvm("direct_operator_overload_dispatch.w", <<~W)
      + DispatchAnimal
      + DispatchDog < DispatchAnimal

      + DispatchProbe
        -> */1(DispatchDog)
          11

        -> */1(DispatchAnimal)
          22

      probe = DispatchProbe.new
      << (probe * DispatchDog.new).to_s
    W

    dispatcher = symbol_for("__w_DispatchProbe__STAR__a2")
    dog_worker = symbol_for("__w_DispatchProbe__STAR__ovl_DispatchDog__a2")
    animal_worker = symbol_for("__w_DispatchProbe__STAR__ovl_DispatchAnimal__a2")
    body = llvm[/define internal i64 @#{Regexp.escape(dispatcher)}.*?^}/m]

    expect(body).to include("call i64 @w_value_is_a")
    expect(body).to include("call i64 @#{dog_worker}")
    expect(body).to include("call i64 @#{animal_worker}")
    expect(body).not_to include("@w_method_call_cached")
  end

  it "rejects user calls to compiler-only overload intrinsics" do
    source_path = File.join(@tmpdir, "overload_intrinsic_escape.w")
    File.write(source_path, <<~W)
      __compiler_overload_worker("w_puts", "owned")
    W

    compile_out, compile_err, compile_status = Open3.capture3(
      {"NO_COLOR" => "1"}, @compiler_path, "compile", source_path,
      "--out", File.join(@tmpdir, "overload_intrinsic_escape"),
      chdir: PROJECT_ROOT
    )

    expect(compile_status.success?).to be(false)
    expect(compile_err + compile_out).to include("reserved compiler intrinsic '__compiler_overload_worker'")
  end

  it "extends compact symbol prefixes on collisions" do
    functions = 40.times.map do |idx|
      <<~W
        -> collide#{idx}(x)
          x + #{idx}
      W
    end.join("\n")

    llvm = compile_to_llvm(
      "symbol_prefix_collision.w",
      "#{functions}\n<< collide39(1).to_s\n",
      env: { "TUNGSTEN_SYMBOL_PREFIX_HEX" => "1" }
    )

    symbols = last_sidemap.fetch("hashes").values.map { |entry| entry.fetch("symbol") }
    expect(llvm).to include("define i32 @main")
    expect(last_sidemap.fetch("prefix_hex")).to eq(1)
    expect(symbols.size).to be > 16
    expect(symbols.uniq.size).to eq(symbols.size)
    expect(symbols).to all(match(/\A__wy_[0-9a-f]{1,16}(?:_\d+)?\z/))
    expect(symbols.any? { |symbol| symbol.delete_prefix("__wy_").size > 1 }).to be(true)
  end

  it "symbolicates compact symbols through the sidecar helper" do
    compile_to_llvm("symbolicate_sidecar.w", <<~W)
      -> alpha(x)
        x + 1

      << alpha(41).to_s
    W

    compact = symbol_for("__w_alpha")
    out, err, status = Open3.capture3(
      File.join(PROJECT_ROOT, "bin/tungsten"),
      "symbolicate",
      @last_sidemap_path,
      compact,
      chdir: PROJECT_ROOT
    )

    expect(status.success?).to be(true), err
    expect(out).to include(compact)
    expect(out).to include("alpha")
  end

  it "omits enhanced stacktrace metadata in release builds" do
    llvm = compile_to_llvm("release_stacktrace_metadata.w", <<~W, [ "--release" ])
      -> alpha(x)
        x + 1

      << alpha(41).to_s
    W

    expect(llvm).not_to match(/^@__w_fn_meta/)
    expect(llvm).not_to match(/^@__w_call_site/)
    expect(llvm).not_to match(/^declare .*@__w_loc_set_col/)
    expect(llvm).not_to match(/^  .*notail call/)
    expect(File.exist?(@last_sidemap_path)).to be(true)
    expect(symbol_for("__w_alpha")).to start_with("__wy_")
  end

  it "passes typed i64 class-method params raw for direct static calls" do
    source = <<~W
      + RawStatic
        -> .bump(x, y) (i64 i64) i64
          x + y

        -> .call_bump(n) (i64) i64
          bump(n, 1)

      << RawStatic.call_bump(140737488355329)
    W

    out = compile_and_run("raw_static_i64_abi.w", source)
    llvm = compile_to_llvm("raw_static_i64_abi.w", source)
    call_bump = symbol_for("__w_RawStatic_S_call_bump")
    bump = symbol_for("__w_RawStatic_S_bump")
    bump_boxed = symbol_for("__w_RawStatic_S_bump__boxed")
    body = llvm[/define (?:internal )?i64 @#{Regexp.escape(call_bump)}.*?\n}/m]

    expect(out).to eq("140737488355330\n")
    expect(body).to include("call i64 @#{bump}")
    expect(body).not_to include("call i64 @w_int")
    expect(llvm).to include("ptr @#{bump_boxed}")
  end

  it "can mark safe internal direct calls fastcc behind an env flag" do
    source = <<~W
      + RawStatic
        -> .bump(x, y) (i64 i64) i64
          x + y

        -> .call_bump(n) (i64) i64
          bump(n, 1)

      << RawStatic.call_bump(41)
    W

    default_llvm = compile_to_llvm("fastcc_raw_static_i64_default.w", source)
    expect(default_llvm).not_to match(/define internal fastcc i64 @/)
    expect(default_llvm).not_to match(/call fastcc i64 @/)

    llvm = compile_to_llvm(
      "fastcc_raw_static_i64.w",
      source,
      [],
      env: { "TUNGSTEN_LLVM_FASTCC" => "1" }
    )
    bump = symbol_for("__w_RawStatic_S_bump")
    bump_boxed = symbol_for("__w_RawStatic_S_bump__boxed")

    expect(llvm).to match(/define internal fastcc i64 @#{Regexp.escape(bump)}\(/)
    expect(llvm).to match(/call fastcc i64 @#{Regexp.escape(bump)}\(/)
    expect(llvm).to match(/define internal i64 @#{Regexp.escape(bump_boxed)}\(/)
    expect(llvm).not_to match(/define internal fastcc i64 @#{Regexp.escape(bump_boxed)}\(/)
    expect(llvm).to include("ptr @#{bump_boxed}")
  end

  it "caches dynamic static dispatch by class identity" do
    out = compile_and_run("static_dispatch_class_ic.w", <<~W)
      + A
        -> .value
          1

      + B
        -> .value
          2

      i = 0
      total = 0
      while i < 4
        k = A
        if i == 1 || i == 3
          k = B
        total += k.value
        i += 1

      << total
    W

    expect(out).to eq("6\n")
  end

  it "keeps typed raw static returns raw across closure captures" do
    llvm = compile_to_llvm("raw_static_return_capture.w", <<~W)
      + RawCapture
        -> .source() i64
          41

        -> .sink(n) (i64) i64
          n + 1

        -> .run() i64
          n = source()
          go ->
            sink(n)
          n

      RawCapture.run()
    W

    block = llvm[/define (?:internal )?i64 @#{Regexp.escape(symbol_matching(/\A__block_\d+\z/))}.*?\n}/m]
    expect(block).to include("call i64 @#{symbol_for("__w_RawCapture_S_sink")}")
    expect(block).not_to include("call i64 @w_to_i64")
  end

  it "lowers StringBuffer#<< string appends to the typed runtime helper" do
    llvm = compile_to_llvm("string_buffer_lshift_typed.w", <<~W)
      buf = StringBuffer(16)
      buf << "hello"
      << buf.to_s
    W

    main = llvm[/define i32 @main.*?\n}/m]
    expect(main).to include("call i64 @w_strbuf_append")
    expect(main).to include("call i64 @w_strbuf_to_s")
    expect(main).not_to include("call i64 @w_bit_shl")
    expect(main).not_to include("@w_method_call_cached")
  end

  it "`:-X` char literal is a raw ASCII integer (Phase 7)" do
    # Phase 7 updated: `:-X` now lowers to a raw int constant, not a
    # boxed Char. Printing as .to_s yields the decimal value. Use
    # U+0041 (codepoint form) if you want a first-class char value.
    out = compile_and_run("char_lit_ascii.w", <<~W)
      a = :-A
      b = :-B
      c = :-)
      << a.to_s
      << b.to_s
      << c.to_s
      << (:-A + 1).to_s
    W
    expect(out).to eq("65\n66\n41\n66\n")
  end

  it "`:-X` supports the `in` operator for structural-char checks (Phase 7)" do
    out = compile_and_run("char_in_test.w", <<~W)
      c = :-(
      if c in (:-( :-) :-;)
        << "structural"
      else
        << "other"
    W
    expect(out).to eq("structural\n")
  end

  it "`:-` followed by whitespace still lexes as method-name symbol (Phase 7 back-compat)" do
    out = compile_and_run("colon_minus_symbol.w", <<~W)
      sym = :-
      << sym.to_s
    W
    expect(out).to eq("-\n")
  end

  it "waits for complete HTTP response bodies in raw Hammer-style parsing" do
    out = compile_and_run("hammer_response_length_complete_body.w", <<~W)
      -> response_length_at_raw(data, length, start) (i64 i64 i64) i64
        if length - start < 15
          return 0

        crlfcrlf = 0x0A0D0A0D ## i64
        limit = length - 4
        pos = start
        header_end = -1
        while pos <= limit
          if raw_load_u32(data, pos) == crlfcrlf
            header_end = pos
            break
          pos += 1

        if header_end < 0
          return 0

        p = start
        while p < header_end
          c = raw_load_u8(data, p)
          if c in (:-C :-c)
            if header_end - p >= 15
              e = raw_load_u8(data, p + 9)
              if e in (:-E :-e)
                v = p + 15
                loop
                  break if v >= header_end
                  break if raw_load_u8(data, v) != :-\\s
                  v += 1
                n = 0
                digit_start = v
                loop
                  break if v >= header_end
                  d = raw_load_u8(data, v)
                  break if d < :-0
                  break if d > :-9
                  n = n * 10 + d - :-0
                  v += 1
                if v > digit_start
                  total_len = header_end - start + 4 + n ## i64
                  return total_len if length - start >= total_len
                  return 0
          loop
            break if p >= header_end
            break if raw_load_u8(data, p) == :-\\n
            p += 1
          p++

        header_end - start + 4

      -> response_length(s) (string) i64
        data = ccall_nobox("w_string_byte_ptr", s)
        length = ccall_nobox("w_string_byte_length", s)
        response_length_at_raw(data, length, 0)

      no_space = "HTTP/1.1 200 OK\\r\\nContent-Length:4\\r\\n\\r\\ntest"
      one_space = "HTTP/1.1 200 OK\\r\\nContent-Length: 4\\r\\n\\r\\ntest"
      many_spaces = "HTTP/1.1 200 OK\\r\\nContent-Length:    4\\r\\n\\r\\ntest"
      two_digits = "HTTP/1.1 200 OK\\r\\nContent-Length: 12\\r\\n\\r\\nhello world!"
      partial = "HTTP/1.1 200 OK\\r\\nContent-Length: 4\\r\\n\\r\\nte"
      no_body = "HTTP/1.1 204 No Content\\r\\n\\r\\n"

      << response_length(no_space).to_s
      << response_length(one_space).to_s
      << response_length(many_spaces).to_s
      << response_length(two_digits).to_s
      << response_length(partial).to_s
      << response_length(no_body).to_s
    W
    expect(out).to eq("41\n42\n45\n51\n0\n27\n")
  end

  it "round-trips through raw fd socket helpers" do
    server = nil
    server_thread = nil
    begin
      server = TCPServer.new("127.0.0.1", 0)
    rescue Errno::EACCES, Errno::EPERM => e
      skip "loopback TCP bind unavailable: #{e.message}"
    end
    port = server.addr[1]
    received = nil
    server_thread = Thread.new do
      client = server.accept
      received = client.read(4)
      client.write("pong")
    rescue IOError
      nil
    ensure
      client&.close
    end

    out = compile_and_run("raw_fd_socket_helpers.w", <<~W)
      host = "127.0.0.1"
      fd = ccall_nobox("w_socket_connect_fd", host, #{port}) ## i64
      msg = "ping"
      msg_ptr = ccall_nobox("w_string_byte_ptr", msg) ## i64
      msg_len = ccall_nobox("w_string_byte_length", msg) ## i64
      wrote = ccall_nobox("w_socket_write_fd", fd, msg_ptr, msg_len) ## i64
      buf = ccall_nobox("w_raw_malloc", 16) ## i64
      read = ccall_nobox("w_socket_read_fd", fd, buf, 16) ## i64
      ok = 0
      if read == 4
        if raw_load_u8(buf, 0) == :-p
          if raw_load_u8(buf, 1) == :-o
            if raw_load_u8(buf, 2) == :-n
              if raw_load_u8(buf, 3) == :-g
                ok = 1
      ccall_nobox("w_socket_close_fd", fd)
      ccall_nobox("w_raw_free", buf)
      << wrote.to_s
      << read.to_s
      << ok.to_s
    W

    server_thread.join(2)
    expect(received).to eq("ping")
    expect(out).to eq("4\n4\n1\n")
  ensure
    server&.close unless server&.closed?
    server_thread&.kill if server_thread&.alive?
  end

  it "stores bytes through the raw_store_u8 intrinsic without boxing pointers" do
    out = compile_and_run("raw_store_u8.w", <<~W)
      ptr = ccall_nobox("w_raw_malloc", 4) ## i64
      first = raw_store_u8(ptr, 0, 0x141) ## i64
      second = raw_store_u8(ptr, 1, 0x1FF) ## i64
      loaded_first = raw_load_u8(ptr, 0) ## i64
      loaded_second = raw_load_u8(ptr, 1) ## i64
      ccall_nobox("w_raw_free", ptr)
      << first.to_s
      << second.to_s
      << loaded_first.to_s
      << loaded_second.to_s
    W

    expect(out).to eq("65\n255\n65\n255\n")
  end

  it "`## w64` hint annotates explicitly-boxed integer (Phase 4)" do
    out = compile_and_run("w64_hint.w", <<~W)
      x = 0 ## w64
      if x
        << "boxed zero is truthy"
      else
        << "wrong"
      y = 42 ## w64
      << (y + 100).to_s
    W
    expect(out).to eq("boxed zero is truthy\n142\n")
  end

  it "w_array_set soft-fails on out-of-bounds write (Phase 5)" do
    out = compile_and_run("array_oob_set.w", <<~W)
      a = [1, 2, 3]
      a[10] = "x"
      << "still running"
      << a.size.to_s
    W
    expect(out).to eq("still running\n3\n")
  end

  it "integer literal 0 is truthy (Tungsten rule: only nil/false are falsy)" do
    out = compile_and_run("zero_is_truthy.w", <<~W)
      if 0
        << "truthy"
      else
        << "falsy"
    W
    expect(out).to eq("truthy\n")
  end

  it "integer literal 1 is truthy" do
    out = compile_and_run("one_is_truthy.w", <<~W)
      if 1
        << "truthy"
      else
        << "falsy"
    W
    expect(out).to eq("truthy\n")
  end

  it "integer literal -1 is truthy" do
    out = compile_and_run("neg_one_is_truthy.w", <<~W)
      if -1
        << "truthy"
      else
        << "falsy"
    W
    expect(out).to eq("truthy\n")
  end

  it "nil is the only falsy primitive besides false" do
    out = compile_and_run("nil_is_falsy.w", <<~W)
      x = nil
      if x
        << "wrong"
      else
        << "right"
    W
    expect(out).to eq("right\n")
  end

  it "float literal 0.0 is truthy" do
    out = compile_and_run("zero_float_is_truthy.w", <<~W)
      if 0.0
        << "truthy"
      else
        << "falsy"
    W
    expect(out).to eq("truthy\n")
  end

  it "empty string is truthy" do
    out = compile_and_run("empty_string_truthy.w", <<~W)
      if ""
        << "truthy"
      else
        << "falsy"
    W
    expect(out).to eq("truthy\n")
  end

  it "peephole-dispatches homogeneous OR chain to straight-line icmp+or" do
    llvm = compile_to_llvm("or_chain_dispatch.w", <<~W)
      c = 0x29
      if c == 0x28 || c == 0x29 || c == 0x3B
        << "match"
    W
    # Single-block straight-line sequence: three icmp eq, two or i1,
    # one select to box. No w_eq runtime calls, no short-circuit
    # branching (sc.rhs / sc.end labels absent).
    expect(llvm).to match(/icmp eq i64 .*, -1688849860263896/)
    expect(llvm).to match(/icmp eq i64 .*, -1688849860263895/)
    expect(llvm).to match(/icmp eq i64 .*, -1688849860263877/)
    expect(llvm).to match(/or i1 /)
    expect(llvm).not_to include("call i64 @w_eq")
    # The peephole replaces sc.rhs/sc.end scaffolding for this chain.
    # Its body (the `<<` call) still lives in if.then/if.end, but the
    # condition no longer goes through sc.* labels.
    main = llvm[/define i32 @main.*?\n}/m] || ""
    expect(main).not_to include("sc.rhs")
    expect(main).not_to include("sc.end")
  end

  it "peephole applies to `in` operator (both produce the same dispatch)" do
    llvm = compile_to_llvm("in_op_dispatch.w", <<~W)
      c = 0x29
      if c in (0x28 0x29 0x3B)
        << "match"
    W
    expect(llvm).to match(/icmp eq i64 .*, -1688849860263896/)
    expect(llvm).to match(/icmp eq i64 .*, -1688849860263895/)
    expect(llvm).to match(/icmp eq i64 .*, -1688849860263877/)
    expect(llvm).not_to include("call i64 @w_eq")
  end

  it "pairwise 2-arm OR chain stays below peephole threshold" do
    llvm = compile_to_llvm("or_two_arm.w", <<~W)
      c = 0x28
      if c == 0x28 || c == 0x29
        << "match"
    W
    # 2 arms is below the homogeneity threshold (≥3 required). Falls
    # through to the pairwise short-circuit path. Signature of the
    # short-circuit path: sc.rhs / sc.end labels, and the `store` of
    # the LHS result into the sc_result slot.
    main = llvm[/define i32 @main.*?\n}/m] || ""
    expect(main).to match(/sc\.(rhs|end)/)
  end

  it "mixed-LHS OR chain falls through to pairwise (no dispatch)" do
    llvm = compile_to_llvm("or_mixed_lhs.w", <<~W)
      x = 1
      y = 2
      if x == 1 || y == 2 || x == 3
        << "ok"
    W
    # Arms share LHS across arm 0 and arm 2 but not arm 1.
    # Homogeneity check fails → pairwise short-circuit path with
    # sc.rhs / sc.end block scaffolding.
    main = llvm[/define i32 @main.*?\n}/m] || ""
    expect(main).to match(/sc\.(rhs|end)/)
  end

  it "lowers dense machine-int case dispatch to an LLVM switch" do
    source = <<~W
      -> pick(n) (i64) i64
        case n
        when 1
          10
        when 2
          20
        when 3
          30
        else
          40

      << pick(3).to_s
    W

    out = compile_and_run("dense_case_switch.w", source)
    expect(out).to eq("30\n")

    llvm = compile_to_llvm("dense_case_switch.w", source)
    expect(llvm).to include("switch i64")
    expect(llvm).to include("i64 1, label %case.arm")
    expect(llvm).to include("i64 2, label %case.arm")
    expect(llvm).to include("i64 3, label %case.arm")
  end

  it "emits unreachable after exit and omits the scheduler drain" do
    llvm = compile_to_llvm("exit_unreachable.w", <<~W)
      exit(0)
      << "after"
    W

    main = llvm[/define i32 @main.*?\n}/m] || ""
    expect(main).to match(/call i64 @__w_exit\(i64 .*\)\n\s+unreachable/)
    expect(main).not_to include("@w_scheduler_run")
    expect(llvm).not_to include("after")
  end

  it "`in` operator accepts bitwise LHS without parentheses" do
    out = compile_and_run("in_op_bitwise.w", <<~W)
      flags = 0x0B
      if (flags & 0x08) in (0x08)
        << "bit set"
      else
        << "bit clear"
    W
    expect(out).to eq("bit set\n")
  end

  it "formats lower errors with file path even when row is unknown" do
    source_path = File.join(@tmpdir, "bad_lower.w")
    File.write(source_path, "@@counter = 0\n<< @@counter.to_s\n")

    _compile_out, compile_err, compile_status = Open3.capture3(
      {"NO_COLOR" => "1"}, @compiler_path, "compile", source_path,
      "--out", File.join(@tmpdir, "bad_lower"),
      chdir: PROJECT_ROOT
    )
    expect(compile_status.success?).to be(false)
    expect(compile_err + _compile_out).to include("error: class variable '@@counter' used outside of a class")
    expect(compile_err + _compile_out).to include("bad_lower.w")
  end

  # ---- Runtime error location reporting ----------------------------------
  # Pin L1 (fn-meta), L2 (call-site col), and the source-context gutter.
  # L1 resolves the enclosing Tungsten fn via dladdr → __w_fn_meta; L2
  # resolves the exact dispatch site via __w_call_site (or __w_loc_set_col
  # hook for noreturn sites); the source-context printer reads the file
  # at the resolved path and prints ±2 lines with a caret under `col`.

  it "labels the innermost frame with fn + file:line:col on method-dispatch errors" do
    err = compile_and_run_error("err_dispatch.w", <<~W)
      -> fib(n)
        if n <= 1
          return nil.upcase()
        fib(n - 1) + fib(n - 2)

      fib(5)
    W
    expect(err).to match(%r{at fib \([^)]+err_dispatch\.w:3:\d+\)})
  end

  it "labels outer frames with fn + file:line via fn-meta fallback" do
    err = compile_and_run_error("err_outer.w", <<~W, [ "--frame-pointers" ])
      -> fib(n)
        if n <= 1
          return nil.upcase()
        fib(n - 1) + fib(n - 2)

      fib(3)
    W
    # At least one outer fib frame should resolve via fn-meta (no col).
    expect(err).to match(%r{at fib \([^)]+err_outer\.w:1\)})
    expect(err).to match(%r{at main \([^)]+err_outer\.w:1\)})
  end

  it "reports precise file:line:col for explicit raise via loc-set hook" do
    err = compile_and_run_error("err_raise.w", <<~W)
      -> boom
        raise "kaboom"

      boom()
    W
    expect(err).to include("unhandled exception: kaboom")
    # Source-context gutter picks up the loc even though w_raise is
    # noreturn (which defeats the side-table).
    expect(err).to match(%r{--> [^:\s]+err_raise\.w:2:\d+})
  end

  it "hides raw runtime (C) frames by default" do
    err = compile_and_run_error("err_cframes.w", <<~W)
      nil.upcase()
    W
    expect(err).to include("runtime error: undefined method 'upcase' for nil")
    expect(err).to include("set TUNGSTEN_BACKTRACE=1")
    expect(err).not_to match(/w_method_dispatch|dief|w_method_call_cached/)
  end

  it "prints a source-context window with caret under the failing column" do
    err = compile_and_run_error("err_context.w", <<~W)
      -> fib(n)
        if n <= 1
          return nil.upcase()
        fib(n - 1) + fib(n - 2)

      fib(5)
    W

    # `-->` gutter header pointing at line 3.
    expect(err).to match(%r{--> [^:\s]+err_context\.w:3:\d+})
    # Gutter-formatted context lines with line numbers.
    expect(err).to include(" 1 | -> fib(n)")
    expect(err).to include(" 2 |   if n <= 1")
    expect(err).to include(" 3 |     return nil.upcase()")
    # Caret line appears after the failing line (pipe + spaces + `^`).
    expect(err).to match(/^\s+\|\s+\^$/)
  end

  it "emits a .metal sidecar file for @gpu fn kernels" do
    # Phase 0 kernel provenance smoke. Proves the source → MSL half of
    # `@gpu fn`. Dispatch wiring (metal.m + core/metal.w) lands in a
    # follow-up phase; here we verify the parser recognizes the
    # attribute, the emitter lowers a trivial kernel to valid MSL, and
    # the .metal sidecar appears next to the emitted .ll.
    source_path = File.join(@tmpdir, "add_one.w")
    bin_path = File.join(@tmpdir, "add_one")
    File.write(source_path, <<~W)
      ## f32[]: x
      ## f32[]: y
      ## i32: n
      @gpu fn add_one(x, y, n)
        i = gpu.thread_position_in_grid.x ## i32
        if i < n
          y[i] = x[i] + 1.0

      << "host ok"
    W

    compile_args = [@compiler_path, "compile", source_path, "--out", bin_path]
    compile_args += ["--runtime", RUNTIME_ARCHIVE] if File.exist?(RUNTIME_ARCHIVE)
    compile_args += ["--ll"]
    _, compile_err, compile_status = Open3.capture3(*compile_args, chdir: PROJECT_ROOT)
    expect(compile_status.success?).to be(true), compile_err

    metal_path = source_path.sub(/\.w\z/, ".metal")
    expect(File.exist?(metal_path)).to be(true), "expected #{metal_path} to exist"
    metal = File.read(metal_path)

    # Header + MSL preamble.
    expect(metal).to include("#include <metal_stdlib>")
    expect(metal).to include("using namespace metal;")
    # Kernel signature: typed buffer params + thread_position_in_grid.
    expect(metal).to match(/kernel void add_one\(/)
    expect(metal).to include("device float *x [[buffer(0)]]")
    expect(metal).to include("device float *y [[buffer(1)]]")
    expect(metal).to include("constant int &n [[buffer(2)]]")
    expect(metal).to include("uint3 __tid [[thread_position_in_grid]]")
    # Body: thread-id mapped (3D thread position, .x component), array subscript, float arithmetic.
    expect(metal).to include("int i = int(__tid.x);")
    expect(metal).to match(/if \(\(?i < n\)?\)/)
    expect(metal).to include("y[i] = (x[i] + 1.0f)")
  end

  it "dispatches an @gpu kernel and reads back the result (Metal end-to-end)", :metal do
    # Phase 0 closure: compiles add_one, then loads its emitted MSL,
    # builds a pipeline, fills an input buffer with [1.0, 2.0, 3.0],
    # dispatches threads=3, reads back and asserts [2.0, 3.0, 4.0].
    # Skipped on non-darwin and on darwin without xcrun metal toolchain.
    skip "Metal not available on this platform" unless RUBY_PLATFORM =~ /darwin/
    # No xcrun toolchain check needed — newLibraryWithSource: uses the
    # Metal runtime, not the offline `xcrun metal` compiler.

    source_path = File.join(@tmpdir, "smoke.w")
    bin_path = File.join(@tmpdir, "smoke")
    File.write(source_path, <<~W)
      use core/metal

      ## f32[]: x
      ## f32[]: y
      ## i32: n
      @gpu fn add_one(x, y, n)
        i = gpu.thread_position_in_grid.x ## i32
        if i < n
          y[i] = x[i] + 1.0

      msl = read_file("#{File.join(@tmpdir, "smoke.metal")}")
      device = metal_device()
      library = metal_compile_source(device, msl)
      pipeline = metal_pipeline(library, "add_one")

      input = metal_buffer(device, 12)
      output = metal_buffer(device, 12)
      n_buf = metal_buffer(device, 4)
      metal_buffer_write_f32(input, 0, ~1.0)
      metal_buffer_write_f32(input, 1, ~2.0)
      metal_buffer_write_f32(input, 2, ~3.0)
      metal_buffer_write_i32(n_buf, 0, 3)

      queue = metal_queue(device)
      metal_dispatch1(queue, pipeline, input, output, n_buf, 3)

      << metal_buffer_read_f32(output, 0).to_s
      << metal_buffer_read_f32(output, 1).to_s
      << metal_buffer_read_f32(output, 2).to_s
    W

    compile_args = [@compiler_path, "compile", source_path, "--out", bin_path, "--ll"]
    compile_args += ["--runtime", RUNTIME_ARCHIVE] if File.exist?(RUNTIME_ARCHIVE)
    _, compile_err, compile_status = Open3.capture3(*compile_args, chdir: PROJECT_ROOT)
    expect(compile_status.success?).to be(true), compile_err

    out, run_err, run_status = Open3.capture3(bin_path)
    if !run_status.success? && run_err.include?("Metal: no default device available")
      skip "Metal default device unavailable"
    end
    expect(run_status.success?).to be(true), run_err
    lines = out.lines.map(&:strip)
    # Tungsten's Float#to_s elides `.0` on integer-valued floats, so
    # 2.0 prints as "2". The values are still floats — they came back
    # from a Metal float buffer.
    expect(lines).to eq(["2", "3", "4"])
  end

  it "falls back gracefully when the source file is unreadable" do
    # Compile first, then delete the source — runtime tries to fopen the
    # path recorded in the fn-meta table, fails, and should still dump
    # error + backtrace without a source-context window.
    source_path = File.join(@tmpdir, "err_nosource.w")
    bin_path = File.join(@tmpdir, "err_nosource")
    File.write(source_path, <<~W)
      nil.upcase()
    W
    compile_args = [@compiler_path, "compile", source_path, "--out", bin_path]
    compile_args += ["--runtime", RUNTIME_ARCHIVE] if File.exist?(RUNTIME_ARCHIVE)
    _, compile_err, compile_status = Open3.capture3(*compile_args, chdir: PROJECT_ROOT)
    expect(compile_status.success?).to be(true), compile_err

    File.delete(source_path)
    _out, err, status = Open3.capture3(bin_path)
    expect(status.success?).to be(false)
    expect(err).to include("runtime error:")
    # No `-->` header because the file couldn't be opened.
    expect(err).not_to match(/--> .+err_nosource\.w:/)
    # Backtrace remains concise by default even when source is missing.
    expect(err).to include("set TUNGSTEN_BACKTRACE=1")
    expect(err).not_to match(/w_method_dispatch|dief|w_method_call_cached/)
  end

  it "parses `and` and `or` as logical operators inside while conditions" do
    out = compile_and_run("phase0_while_and.w", <<~W)
      i = 0
      ok = true
      while i < 5 and ok
        i = i + 1
        if i > 3
          ok = false
      << i
    W

    expect(out).to eq("4\n")
  end

  it "lexes division between two parenthesized constants without falling into regex mode" do
    out = compile_and_run("phase0_paren_div.w", <<~W)
      N = 32
      M = 16
      x = (N / 8) * (M / 8)
      << x
    W

    expect(out).to eq("8\n")
  end

  it "registers rw accessor functions with arity-suffixed mangled names" do
    out = compile_and_run("phase0_rw_accessor.w", <<~W)
      + Foo
        rw :foo_bar
        -> new(@foo_bar = 0)

      f = Foo.new(7)
      << f.foo_bar
      f.foo_bar = 99
      << f.foo_bar
    W

    expect(out).to eq("7\n99\n")
  end

  it "allows `lib` as a regular identifier outside of `extern lib` blocks" do
    out = compile_and_run("phase0_lib_var.w", <<~W)
      lib = "hello"
      << lib
    W

    expect(out).to eq("hello\n")
  end

  it "captures top-level mutable variables by reference inside closures" do
    out = compile_and_run("phase0_closure_capture.w", <<~W)
      count = 0
      inc = -> () count = count + 1
      inc()
      inc()
      << count
    W

    expect(out).to eq("2\n")
  end

  it "applies dot-prefix elementwise add to a typed array (Phase 4e)" do
    out = compile_and_run("phase4_dot_add.w", <<~W)
      a = u8[4]
      a[0] = 1
      a[1] = 2
      a[2] = 3
      a[3] = 4
      b = a .+ 10
      << b[0]
      << b[1]
      << b[2]
      << b[3]
    W
    expect(out).to eq("11\n12\n13\n14\n")
  end

  it "applies dot-prefix elementwise bitwise-or across typed arrays (Phase 4e)" do
    out = compile_and_run("phase4_dot_bor.w", <<~W)
      a = u32[3]
      a[0] = 12
      a[1] = 12
      a[2] = 12
      b = u32[3]
      b[0] = 3
      b[1] = 5
      b[2] = 9
      c = a .| b
      << c[0]
      << c[1]
      << c[2]
    W
    expect(out).to eq("15\n13\n13\n")
  end

  it "applies dot-prefix elementwise shift to a typed array (Phase 4e)" do
    out = compile_and_run("phase4_dot_shl.w", <<~W)
      a = u32[3]
      a[0] = 1
      a[1] = 2
      a[2] = 3
      c = a .<< 2
      << c[0]
      << c[1]
      << c[2]
    W
    expect(out).to eq("4\n8\n12\n")
  end

  it "broadcasts a float scalar across an f32 array via .* (Phase 4e)" do
    # `~1.0` is the IEEE-double literal syntax in Tungsten; `1.0` parses
    # as Decimal (exact sig+scale) and is rejected by the float-storage
    # path. f32 arrays only accept floats.
    out = compile_and_run("phase4_f32_dot_mul.w", <<~W)
      a = f32[3]
      a[0] = ~1.0
      a[1] = ~2.0
      a[2] = ~3.0
      b = a .* ~2.5
      << b[0]
      << b[1]
      << b[2]
    W
    # f32 print elides trailing .0; 2.0 * 2.5 prints as "5"
    expect(out).to eq("2.5\n5\n7.5\n")
  end

  it "applies dot-prefix elementwise multiply across two typed arrays (Phase 4e)" do
    out = compile_and_run("phase4_dot_mul.w", <<~W)
      a = u8[3]
      a[0] = 10
      a[1] = 20
      a[2] = 30
      b = u8[3]
      b[0] = 1
      b[1] = 2
      b[2] = 3
      c = a .* b
      << c[0]
      << c[1]
      << c[2]
    W
    expect(out).to eq("10\n40\n90\n")
  end

  it "broadcasts a value across a typed array via arr.fill (Phase 4e)" do
    out = compile_and_run("phase4_fill.w", <<~W)
      a = u8[8]
      a.push(1)
      a.push(2)
      a.push(3)
      a.fill(99)
      << a[0]
      << a[1]
      << a[2]
    W

    expect(out).to eq("99\n99\n99\n")
  end

  it "parses typed-array sigils as hash-key symbols (Phase 4e shadowing fix)" do
    out = compile_and_run("phase4_hash_sigil.w", <<~W)
      h = {u8: 100, f32: 99}
      << h[:u8]
      << h[:f32]
    W

    expect(out).to eq("100\n99\n")
  end

  it "reinterprets a typed array via arr.view zero-copy (Phase 4e)" do
    out = compile_and_run("phase4_view.w", <<~W)
      a = u32[2]
      a[0] = 0x11223344
      a[1] = 0x55667788
      v = a.view(8)
      << v.size
      << v[0]
      << v[3]
      << v[4]
      << v[7]
    W

    # 2 u32 values = 8 bytes. Little-endian u8 view: low byte of 0x11223344
    # is 0x44 = 68; high byte is 0x11 = 17. Same for the second u32.
    expect(out).to eq("8\n68\n17\n136\n85\n")
  end

  it "exposes arr.raw_ptr as a non-zero pointer for ccall ergonomics (Phase 4e)" do
    out = compile_and_run("phase4_raw_ptr.w", <<~W)
      a = u32[4]
      a.push(100)
      a.push(200)
      ptr = a.raw_ptr
      << ptr > 0
    W

    expect(out).to eq("true\n")
  end

  it "constructs and pushes through BigArray.new (Phase 3 i64-indexed tier)" do
    out = compile_and_run("phase3_big_array.w", <<~W)
      b = BigArray.new(:u8, 100)
      b.push(42)
      b.push(43)
      b.push(44)
      << b.size
      << b[0]
      << b[1]
      << b[2]
    W

    expect(out).to eq("3\n42\n43\n44\n")
  end

  it "constructs SmallArray.new with frozen size (Phase 3 packed tier)" do
    out = compile_and_run("phase3_small_array.w", <<~W)
      s = SmallArray.new(:u8, 5)
      << s.size
      << s.empty?
    W

    expect(out).to eq("5\nfalse\n")
  end

  it "round-trips raw machine types from typed-array get into typed-param fn calls" do
    # For every machine ebits the compiler routes through typed-overload
    # dispatch, an `arr[i]` subscript flows directly into a fn whose param
    # is annotated with the matching type — without re-boxing through a
    # generic :int / :float intermediate. This is the contract that lets
    # ML inner loops (`weights.dot(...)` / `quantized_layer.matmul(...)`)
    # stay raw across user-fn boundaries.
    out = compile_and_run("typed_machine_roundtrip.w", <<~W)
      -> id_bool(x) (bool) bool : x
      -> id_i4(x)   (i4)   i4   : x
      -> id_u4(x)   (u4)   u4   : x
      -> id_i8(x)   (i8)   i8   : x
      -> id_u8(x)   (u8)   u8   : x
      -> id_i16(x)  (i16)  i16  : x
      -> id_u16(x)  (u16)  u16  : x
      -> id_i32(x)  (i32)  i32  : x
      -> id_u32(x)  (u32)  u32  : x
      -> id_i64(x)  (i64)  i64  : x
      -> id_u64(x)  (u64)  u64  : x
      -> id_bf16(x) (bf16) bf16 : x
      -> id_f32(x)  (f32)  f32  : x
      -> id_f64(x)  (f64)  f64  : x

      ab  = bool[1];  ab[0] = true;             << id_bool(ab[0]).to_s
      a4  = i4[1];    a4[0] = -3;               << id_i4(a4[0]).to_s
      au4 = u4[1];    au4[0] = 13;              << id_u4(au4[0]).to_s
      a8  = i8[1];    a8[0] = -100;             << id_i8(a8[0]).to_s
      au8 = u8[1];    au8[0] = 200;             << id_u8(au8[0]).to_s
      a16 = i16[1];   a16[0] = -32000;          << id_i16(a16[0]).to_s
      au16 = u16[1];  au16[0] = 60000;          << id_u16(au16[0]).to_s
      a32 = i32[1];   a32[0] = -2000000000;     << id_i32(a32[0]).to_s
      au32 = u32[1];  au32[0] = 4000000000;     << id_u32(au32[0]).to_s
      a64 = i64[1];   a64[0] = -9876543210;     << id_i64(a64[0]).to_s
      au64 = u64[1];  au64[0] = 18000000000;    << id_u64(au64[0]).to_s
      abf = bf16[1];  abf[0] = ~1.5;            << id_bf16(abf[0]).to_s
      af32 = f32[1];  af32[0] = ~2.5;           << id_f32(af32[0]).to_s
      af64 = f64[1];  af64[0] = ~3.5;           << id_f64(af64[0]).to_s
    W

    expect(out).to eq(<<~OUT)
      true
      -3
      13
      -100
      200
      -32000
      60000
      -2000000000
      4000000000
      -9876543210
      18000000000
      1.5
      2.5
      3.5
    OUT
  end

  it "keeps raw integer typed-array subscripts and each yields unboxed through typed identity calls" do
    {
      "i4" => "-3",
      "u4" => "13",
      "i8" => "-100",
      "u8" => "200",
      "i16" => "-32000",
      "u16" => "60000",
      "i32" => "-2000000000",
      "u32" => "4000000000",
      "i64" => "-9876543210"
    }.each do |type, value|
      llvm = compile_to_llvm("typed_#{type}_raw_call_ll.w", <<~W)
        -> id(x) (#{type}) #{type} : x

        a = #{type}[1]
        a.push(#{value})
        direct = id(a[0])
        a.each -> (v)
          iter = id(v)
      W

      symbol = symbol_for("__w_id__#{type}")
      contexts = llvm_call_contexts(llvm, symbol, before: 12)
      expect(contexts.size).to eq(2)

      aggregate_failures(type) do
        contexts.each do |context|
          expect(context).not_to match(/call i64 @w_(?:int|to_i64|u64)\b/)
          expect(context).not_to include("-1688849860263936")
          expect(context).not_to include("281474976710655")
        end
      end
    end
  end

  it "preserves typed-array each block param types for every machine element type" do
    llvm = compile_to_llvm("typed_array_each_machine_overloads.w", <<~W)
      -> tag(x) (bool) i64 : 1
      -> tag(x) (i4) i64 : 2
      -> tag(x) (u4) i64 : 3
      -> tag(x) (i8) i64 : 4
      -> tag(x) (u8) i64 : 5
      -> tag(x) (i16) i64 : 6
      -> tag(x) (u16) i64 : 7
      -> tag(x) (i32) i64 : 8
      -> tag(x) (u32) i64 : 9
      -> tag(x) (i64) i64 : 10
      -> tag(x) (u64) i64 : 11
      -> tag(x) (bf16) i64 : 12
      -> tag(x) (f32) i64 : 13
      -> tag(x) (f64) i64 : 14

      ab = bool[1]; ab.push(true)
      ab.each -> (v)
        rb = tag(v)
      a4 = i4[1]; a4.push(-3)
      a4.each -> (v)
        r4 = tag(v)
      au4 = u4[1]; au4.push(13)
      au4.each -> (v)
        ru4 = tag(v)
      a8 = i8[1]; a8.push(-100)
      a8.each -> (v)
        r8 = tag(v)
      au8 = u8[1]; au8.push(200)
      au8.each -> (v)
        ru8 = tag(v)
      a16 = i16[1]; a16.push(-32000)
      a16.each -> (v)
        r16 = tag(v)
      au16 = u16[1]; au16.push(60000)
      au16.each -> (v)
        ru16 = tag(v)
      a32 = i32[1]; a32.push(-2000000000)
      a32.each -> (v)
        r32 = tag(v)
      au32 = u32[1]; au32.push(4000000000)
      au32.each -> (v)
        ru32 = tag(v)
      a64 = i64[1]; a64.push(-9876543210)
      a64.each -> (v)
        r64 = tag(v)
      au64 = u64[1]; au64.push(18000000000)
      au64.each -> (v)
        ru64 = tag(v)
      abf = bf16[1]; abf.push(~1.5)
      abf.each -> (v)
        rbf = tag(v)
      af32 = f32[1]; af32.push(~2.5)
      af32.each -> (v)
        rf32 = tag(v)
      af64 = f64[1]; af64.push(~3.5)
      af64.each -> (v)
        rf64 = tag(v)
    W

    expect(llvm).not_to include("declare i64 @__w_tag(i64) nounwind")
    expect(llvm).not_to match(/call i64 @__w_tag\(/)

    %w[bool i4 u4 i8 u8 i16 u16 i32 u32 i64 u64 bf16 f32 f64].each do |type|
      expect(llvm).to include("call i64 @#{symbol_for("__w_tag__#{type}")}(")
    end
  end

  it "inlines non-escaping plain-array iterator blocks without closure allocation" do
    source = <<~W
      -> any_three?() bool
        A.any? -> (x)
          x == 3

      A = [1, 2, 3, 4]

      -> has_three?() bool
        found = A.find -> (x)
          x == 3
        found == 3

      -> all_small?() bool
        A.all? -> (x)
          x < 10

      -> none_big?() bool
        A.none? -> (x)
          x > 10

      -> local_bound_any?() bool
        cb = -> (x)
          x == 3
        A.any?(cb)

      << has_three?()
      << all_small?()
      << any_three?()
      << none_big?()
      << local_bound_any?()
    W

    expect(compile_and_run("plain_array_inline_iterators_run.w", source)).to eq(<<~OUT)
      true
      true
      true
      true
      true
    OUT

    llvm = compile_to_llvm("plain_array_inline_iterators_ll.w", source)
    expect(llvm).to include("array.iter.hdr")
    expect(llvm).not_to include("@w_closure_new")
    expect(llvm).not_to include("@w_method_call_cached")
  end

  it "autoloads Enumerable from core/tungsten.w when included via `is`" do
    out = compile_and_run("phase1_autoload_trait.w", <<~W)
      + Foo
        is Enumerable
        -> each/&
          1 -> &(99)

      f = Foo.new()
      f.each -> (v)
        << v
    W

    expect(out).to eq("99\n")
  end

  it "dispatches Array and Hash combinators through Enumerable bodies" do
    out = compile_and_run("enumerable_trait_dispatch.w", <<~W)
      typed = i16[3]
      typed[0] = -2
      typed[1] = 0
      typed[2] = 7
      << typed.map -> (value)
        value + 5

      hash = {a: 2, b: 5}
      << hash.map -> (key, value)
        key.to_s + value.to_s

      selected = hash.select -> (key, value)
        value >= 5
      << selected.size
      << selected[0][0]
      << selected[0][1]
    W

    expect(out).to include("[3, 5, 12]\n", "a2", "b5", "1\nb\n5\n")

    trait_source = File.read(File.join(PROJECT_ROOT, "core/traits/enumerable.w"))
    array_source = File.read(File.join(PROJECT_ROOT, "core/array.w"))
    hash_source = File.read(File.join(PROJECT_ROOT, "core/hash.w"))
    runtime_source = File.read(File.join(PROJECT_ROOT, "runtime/runtime.c"))

    expect(trait_source).to include(
      "-> map(&block) []",
      "-> select(&block) []",
      "-> reduce(init, &block)",
      "mode = __enumerable_iteration_mode"
    )
    expect(array_source).not_to match(/^\s+-> (?:map|select|reject|find|detect|reduce)\b/)
    expect(hash_source).not_to match(/^\s+-> map\b/)
    expect(runtime_source).not_to include("w_ic_array_map", "w_ic_array_select", "w_ic_hash_map")

    llvm = compile_to_llvm("enumerable_adapter_ir.w", <<~W)
      values = [1, 2, 3]
      out = values.map -> (value)
        value * 2
      << out
    W
    map_symbol = symbol_for("__w_Array_map__a2")
    map_body = llvm[/define internal i64 @#{Regexp.escape(map_symbol)}\(.*?^\}/m]
    expect(map_body).not_to be_nil
    # One mode query plus the pair- and ordinary-iterator fallbacks. Array's
    # indexed mode bypasses both callback adapters and reads storage directly.
    expect(map_body.scan("@w_method_call_cached").size).to eq(3)
    expect(map_body).to include("@w_array_size", "@w_array_idx", "@w_closure_call_1")
  end

  it "keeps Hash#size source-owned and lowers its count view directly" do
    runtime_source = File.read(File.join(PROJECT_ROOT, "runtime/runtime.c"))
    expect(runtime_source).not_to include("w_ic_hash_size")
    expect(runtime_source).not_to match(/w_ic_hash_table\[\d+\]\.name\s*=\s*WN_size/)

    llvm = compile_to_llvm("hash_size_view_field_ir.w", <<~W)
      hash = {a: 1, b: 2}
      << hash.size
    W

    size_symbol = symbol_for("__w_Hash_size__a1")
    size_body = llvm[/define internal i64 @#{Regexp.escape(size_symbol)}\(.*?^\}/m]
    expect(size_body).not_to be_nil
    expect(size_body).to include("load i32")
    expect(size_body).not_to include("call i64")
  end

  it "supports measurements, affine points, calibration, and equivalencies" do
    out = compile_and_run("advanced_units_runtime.w", <<~W)
      measurement = 10.0 ± 0.2
      << measurement
      location = (10 m).point(:map) + (2 m).delta(:map)
      << location
      << location.point?
      calibration = Calibration.linear(~2.0, ~1.0, nil, nil, ~0.1, "CAL-42")
      << calibration.apply(Measurement.new(~3.0, ~0.2))
      << (1 kg).equivalent("J", :mass_energy)
    W

    expect(out).to include("10 ± 0.2\n", "12 m\ntrue\n", "7 ± 0.412311\n", "≈8.988×10¹⁶ J\n")
  end

  it "autoloads and constructs a unit-carrying f64 Tensor" do
    out = compile_and_run("unit_tensor.w", <<~W)
      velocity = Tensor<f64, m/s>.zeros([100, 100])
      << velocity.dtype
      << velocity.unit
      << velocity.shape
    W

    expect(out).to eq("64\nm/s\n[100, 100]\n")
  end

  it "rejects known quantity dimension mismatches while compiling" do
    source_path = File.join(@tmpdir, "static_quantity_mismatch.w")
    bin_path = File.join(@tmpdir, "static_quantity_mismatch")
    File.write(source_path, <<~W)
      distance = 10 m
      elapsed = 2 s
      << distance + elapsed
    W

    args = [@compiler_path, "compile", source_path, "--out", bin_path]
    args += ["--runtime", RUNTIME_ARCHIVE] if File.exist?(RUNTIME_ARCHIVE)
    _out, err, status = Open3.capture3(*args, chdir: PROJECT_ROOT)
    expect(status.success?).to be(false)
    expect(err).to include("quantity dimension mismatch")
  end

  it "keeps the PB plus J easter egg in compiled programs" do
    out = compile_and_run("compiled_pbj.w", "<< 1 PB + 1 J\n")
    expect(out).to include("It's peanut butter jelly time!")
  end

  it "rejects two affine point annotations at runtime" do
    err = compile_and_run_error("point_plus_point.w", <<~W)
      << (10 m).point(:map) + (2 m).point(:map)
    W
    expect(err).to match(/cannot add two (?:absolute temperatures|points)/)
  end

  private

  def compile_and_run(name, source, extra_args = [], env: {})
    source_path = File.join(@tmpdir, name)
    bin_path = File.join(@tmpdir, File.basename(name, ".w"))
    File.write(source_path, source)

    compile_args = [@compiler_path, "compile", source_path, "--out", bin_path]
    compile_args += ["--runtime", RUNTIME_ARCHIVE] if File.exist?(RUNTIME_ARCHIVE)
    compile_args += extra_args

    _compile_out, compile_err, compile_status = Open3.capture3(
      env, *compile_args, chdir: PROJECT_ROOT
    )
    expect(compile_status.success?).to be(true), compile_err

    run_out, run_err, run_status = Open3.capture3(bin_path)
    expect(run_status.success?).to be(true), run_err
    run_out
  end

  # Compiles a .w file, runs it, expects a non-zero exit, and returns the
  # captured stderr so callers can match against runtime-error formatting.
  def compile_and_run_error(name, source, extra_args = [])
    source_path = File.join(@tmpdir, name)
    bin_path = File.join(@tmpdir, File.basename(name, ".w"))
    File.write(source_path, source)

    compile_args = [@compiler_path, "compile", source_path, "--out", bin_path]
    compile_args += ["--runtime", RUNTIME_ARCHIVE] if File.exist?(RUNTIME_ARCHIVE)
    compile_args += extra_args

    _compile_out, compile_err, compile_status = Open3.capture3(
      *compile_args, chdir: PROJECT_ROOT
    )
    expect(compile_status.success?).to be(true), compile_err

    _run_out, run_err, run_status = Open3.capture3(bin_path)
    expect(run_status.success?).to be(false), "expected non-zero exit, got success. stderr: #{run_err.inspect}"
    run_err
  end

  def compile_to_llvm(name, source, extra_args = [], env: {})
    source_path = File.join(@tmpdir, name)
    bin_path = File.join(@tmpdir, File.basename(name, ".w"))
    ll_path = File.join("/tmp/tungsten", "#{File.basename(name, ".w")}.ll")
    @last_sidemap_path = "#{bin_path}.sidemap"
    @last_sidemap = nil
    File.write(source_path, source)
    File.delete(ll_path) if File.exist?(ll_path)
    File.delete(@last_sidemap_path) if File.exist?(@last_sidemap_path)

    compile_args = [@compiler_path, "compile", source_path, "--out", bin_path]
    compile_args += ["--runtime", RUNTIME_ARCHIVE] if File.exist?(RUNTIME_ARCHIVE)
    compile_args += extra_args

    _compile_out, compile_err, compile_status = Open3.capture3(env, *compile_args, chdir: PROJECT_ROOT)
    expect(compile_status.success?).to be(true), compile_err
    File.read(ll_path)
  end

  def last_sidemap
    return nil unless @last_sidemap_path && File.exist?(@last_sidemap_path)

    @last_sidemap ||= JSON.parse(File.read(@last_sidemap_path))
  end

  def symbol_for(original)
    map = last_sidemap
    return original unless map

    map.fetch("hashes").each_value do |entry|
      entry.fetch("originals").each do |item|
        return entry.fetch("symbol") if item.fetch("symbol") == original
      end
    end

    raise "symbol #{original} not found in #{@last_sidemap_path}"
  end

  def llvm_call_contexts(llvm, symbol, before:)
    lines = llvm.lines
    contexts = []

    lines.each_with_index do |line, index|
      next unless line.include?("call i64 @#{symbol}(")

      from = [index - before, 0].max
      contexts << lines[from..index].join
    end

    contexts
  end

  def symbol_matching(pattern)
    map = last_sidemap
    return pattern.source unless map

    map.fetch("hashes").each_value do |entry|
      entry.fetch("originals").each do |item|
        return entry.fetch("symbol") if item.fetch("symbol").match?(pattern)
      end
    end

    raise "symbol matching #{pattern.inspect} not found in #{@last_sidemap_path}"
  end
end
