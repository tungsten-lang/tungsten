# frozen_string_literal: true

require "open3"
require "pty"
require "timeout"

# Layer-3 REPL playground surface (Decision 4A harness): drives the COMPILED
# REPL — piped stdin for the cooked-mode paths (banner, :help, ? inspection,
# error formatting) and a PTY for the raw-mode editor (Tab completion). Skips
# when bin/tungsten-compiler isn't built (plain `rake` on a fresh clone); CI's
# linux-bootstrap job builds it and exercises these.
RSpec.describe "REPL playground" do
  project_root = File.expand_path("../../..", __dir__)
  wrapper      = File.join(project_root, "bin/wit")
  compiler     = File.join(project_root, "bin/tungsten-compiler")

  before(:all) do
    skip "bin/tungsten-compiler not built" unless File.executable?(compiler)
  end

  # Pipe `input` lines into `wit` (non-tty → cooked reads) and return
  # combined output with ANSI escapes stripped.
  def repl_piped(wrapper, project_root, input)
    out, _err, _status = Open3.capture3(
      wrapper, stdin_data: input, chdir: project_root
    )
    out.gsub(/\e\[[0-9;]*m/, "")
  end

  def read_pty_until(reader, output, needle)
    loop do
      clean = output.gsub(/\e\[[0-9;]*[A-Za-z]/, "")
      return if clean.include?(needle)

      raise Timeout::Error, "PTY output did not include #{needle.inspect}" unless IO.select([reader], nil, nil, 5)

      output << reader.readpartial(4096)
    end
  end

  describe "banner" do
    it "shows the version from the VERSION file and advertises the playground" do
      version = File.read(File.join(project_root, "VERSION")).strip
      out = repl_piped(wrapper, project_root, "")
      expect(out).to include("Tungsten")
      expect(out).to include("v#{version}")
      expect(out).to include("? help")
      expect(out).to include(":help NAME")
    end
  end

  describe "? help" do
    it "documents inspect, :help, Tab, scrub, and the jit/hot flags" do
      out = repl_piped(wrapper, project_root, "?\n")
      expect(out).to include("? EXPR")
      expect(out).to include(":help NAME")
      expect(out).to include("Tab")
      expect(out).to include("scrub")
      expect(out).to include("--jit")
      expect(out).to include("--hot")
    end
  end

  describe ":help" do
    it "prints a stdlib class summary from its source header" do
      out = repl_piped(wrapper, project_root, ":help Array\n")
      expect(out).to include("# Array")
      expect(out).to include("core/array.w")
      expect(out).to match(/ordered, mutable collection/i)
    end

    it "explains itself when the class is unknown" do
      out = repl_piped(wrapper, project_root, ":help NoSuchClass\n")
      expect(out).to include("no stdlib class named NoSuchClass")
    end

    it "prints usage with no argument" do
      out = repl_piped(wrapper, project_root, ":help\n")
      expect(out).to include("usage: :help")
    end
  end

  describe "evaluation and errors" do
    it "evaluates an expression" do
      out = repl_piped(wrapper, project_root, "<< 6 * 7\n")
      expect(out).to include("42")
    end

    it "renders runtime errors via the shared formatter, not a backtrace" do
      out = repl_piped(wrapper, project_root, "undefined_variable_xyz\n")
      expect(out).to include("error:")
      expect(out).not_to include("__wy_")
      expect(out).not_to include("unhandled exception")
    end

    it "survives an error and keeps evaluating" do
      out = repl_piped(wrapper, project_root, "undefined_variable_xyz\n<< 1 + 1\n")
      expect(out).to include("error:")
      expect(out).to include("2")
    end
  end

  describe "? EXPR inspection" do
    it "inspects a value" do
      out = repl_piped(wrapper, project_root, "? 42\n")
      expect(out).to include("42")
    end
  end

  describe "math scenes (Σ / ∫)" do
    it "sums a capital-sigma polynomial over the labeled default range" do
      out = repl_piped(wrapper, project_root, "? Σ(2x⁷ + 3x²)\n")
      expect(out).to include("36162005")           # Σ 2x⁷+3x², x=1..10
      expect(out).to include("x = 1..10")
      expect(out).to include("default range")
    end

    it "accepts explicit bounds" do
      out = repl_piped(wrapper, project_root, "? Σ(x², 1..3)\n")
      expect(out).to include("14")
      expect(out).to include("x = 1..3")
    end

    it "plots an integral with shaded area under the curve" do
      out = repl_piped(wrapper, project_root, "? ∫(x², 0..2)\n")
      expect(out).to include("2.66667")            # 8/3 (Simpson exact here)
      expect(out).to match(/[⠁-⣿]/)      # braille dots = the plot
    end

    it "evaluates ∫ as a plain expression too" do
      out = repl_piped(wrapper, project_root, "<< ∫(x⁴, 0..1)\n")
      expect(out).to include("0.2")                # ∫x⁴ over [0,1] = 1/5
    end

    it "sums a billion-term polynomial instantly via the closed form" do
      require "timeout"
      out = Timeout.timeout(15) do
        repl_piped(wrapper, project_root, "? Σ(2x⁷ + 3x², 0..1000000000)\n")
      end
      # Exact Faulhaber BigInt — the same w_range_pow_sum the compiled path uses.
      expect(out).to include("250000001000000001166666666666666666083333334333333335000000000500000000")
    end

    it "handles backwards ∫ bounds with the sign convention instead of erroring" do
      out = repl_piped(wrapper, project_root, "? ∫(x², 2..0)\n")
      expect(out).to include("-2.66667")
      expect(out).to include("bounds reversed")
      expect(out).to match(/[⠁-⣿]/)               # the plot still renders
      expect(out).not_to include("error")
    end
  end

  describe "Tab completion (PTY, raw-mode editor)" do
    it "completes a stdlib method after a dot" do
      output = +""
      PTY.spawn(wrapper, chdir: project_root) do |reader, writer, pid|
        Timeout.timeout(30) do
          # Wait for the prompt, type a receiver + dot + partial, hit Tab.
          read_pty_until(reader, output, "wit> ")
          writer.write(%q{"abc".uppercas} + "\t")
          read_pty_until(reader, output, "uppercase")
          writer.write("\x03") # Ctrl+C cancels the line
          writer.write("\x04") # Ctrl+D exits
          begin
            loop { output << reader.readpartial(4096) }
          rescue EOFError, Errno::EIO
            # session ended
          end
          Process.wait(pid)
        end
      rescue Timeout::Error
        Process.kill("KILL", pid) rescue nil
        raise
      end
      clean = output.gsub(/\e\[[0-9;]*[A-Za-z]/, "")
      # The raw-mode editor echoes the completed word: uppercas → uppercase.
      expect(clean).to include("uppercase")
    end
  end
end
