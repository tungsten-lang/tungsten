# frozen_string_literal: true

require_relative "spec_helper"
require "tmpdir"
require "open3"

RSpec.describe "f64[] compile path" do
  TUNGSTEN_RB = File.join(PROJECT_ROOT, "bin/tungsten.rb")
  RUNTIME_DIR = File.join(PROJECT_ROOT, "runtime")

  def event_source
    case RUBY_PLATFORM
    when /darwin/
      File.join(RUNTIME_DIR, "event_kqueue.c")
    when /linux/
      File.join(RUNTIME_DIR, "event_epoll.c")
    else
      skip "unsupported platform for compile test: #{RUBY_PLATFORM}"
    end
  end

  def clang_args
    args = ["clang", "-O3", "-DNDEBUG"]
    args << "-Wl,-dead_strip" if RUBY_PLATFORM =~ /darwin/
    args << "-lm" if RUBY_PLATFORM =~ /linux/
    args
  end

  it "compiles and runs f64 typed array operations" do
    Dir.mktmpdir("tungsten-f64-array") do |dir|
      source_path = File.join(dir, "f64_array.w")
      ll_path = File.join(dir, "f64_array.ll")
      bin_path = File.join(dir, "f64_array")

      File.write(source_path, <<~W)
        # `f64[N]` now allocates size = cap = N (zero-filled), so we
        # index-write the first three slots and drop the trailing zero.
        b = f64[4]
        b[0] = ~1.5
        b[1] = 2
        b[2] = ~3.25
        b.pop()
        << b.size
        << b[1]
        b[1] = ~2.5
        << b[1]
        << b[0] + b[2]
        << b.shift()
        << b.pop()
        << b.size
      W

      ir, err, status = Open3.capture3("ruby", TUNGSTEN_RB, "--ll", source_path, chdir: PROJECT_ROOT)
      expect(status.success?).to be(true), err
      File.write(ll_path, ir)

      ok = system(
        *clang_args,
        File.join(RUNTIME_DIR, "runtime.c"),
        event_source,
        File.join(RUNTIME_DIR, "aks.c"),
        File.join(RUNTIME_DIR, "tls_stub.c"),
        ll_path,
        "-o",
        bin_path,
        out: File::NULL,
        err: File::NULL
      )
      expect(ok).to be(true), "clang failed for generated f64[] test program"

      out, run_err, run_status = Open3.capture3(bin_path)
      expect(run_status.success?).to be(true), run_err
      expect(out).to eq(<<~OUT)
        3
        2
        2.5
        4.75
        1.5
        3.25
        1
      OUT
    end
  end
end
