# frozen_string_literal: true

require "open3"
require "tmpdir"

# Layer-2 CLI surface: command discoverability in --help, did-you-mean for
# mistyped commands, and the single-sourced --version. These drive the Ruby CLI
# (bin/tungsten.rb) directly so they pass on a checkout with no compiled
# binary — the same funnel the bash wrapper delegates unknown commands to.
RSpec.describe "CLI commands surface" do
  project_root = File.expand_path("../../..", __dir__)
  shell_cli    = File.join(project_root, "bin/tungsten")
  ruby_cli     = File.join(project_root, "bin/tungsten.rb")

  def run_cli(ruby_cli, *args)
    Open3.capture3(RbConfig.ruby, ruby_cli, *args)
  end

  def run_shell_cli(shell_cli, *args)
    Open3.capture3(shell_cli, *args)
  end

  describe "--help" do
    it "lists the command set" do
      out, _err, status = run_cli(ruby_cli, "--help")
      expect(status.exitstatus).to eq(0)
      expect(out).to include("Commands:")
      %w[compile run repl start new build doctor fmt bit].each do |cmd|
        expect(out).to match(/^\s+#{Regexp.escape(cmd)}\b/)
      end
    end

    it "names console as the repl alias" do
      out, = run_cli(ruby_cli, "--help")
      expect(out).to include("alias: console")
    end
  end

  describe "did-you-mean for mistyped commands" do
    it "suggests the closest command within 2 edits" do
      _out, err, status = run_cli(ruby_cli, "biuld")
      expect(status.exitstatus).to eq(1)
      expect(err).to include("File not found: biuld")
      expect(err).to include("Did you mean: tungsten build")
    end

    it "stays quiet when nothing is close" do
      _out, err, status = run_cli(ruby_cli, "zzzzzzz")
      expect(status.exitstatus).to eq(1)
      expect(err).not_to include("Did you mean")
    end

    it "treats extension-bearing arguments as files, not commands" do
      _out, err, status = run_cli(ruby_cli, "missing.w")
      expect(status.exitstatus).to eq(1)
      expect(err).to include("File not found: missing.w")
      expect(err).not_to include("Did you mean")
    end

    it "treats path-bearing arguments as files, not commands" do
      _out, err, status = run_cli(ruby_cli, "no/such/dir")
      expect(status.exitstatus).to eq(1)
      expect(err).not_to include("Did you mean")
    end
  end

  describe "--version" do
    it "reports the version from the repo-root VERSION file" do
      version = File.read(File.join(project_root, "VERSION")).strip
      out, _err, status = run_cli(ruby_cli, "--version")
      expect(status.exitstatus).to eq(0)
      expect(out).to include("tungsten #{version}")
    end
  end

  describe "doctor" do
    it "checks the required clang/lld toolchain without requiring standalone llc" do
      out, err, status = run_cli(ruby_cli, "doctor")

      expect(status.exitstatus).to eq(0), err
      expect(out).to include("clang")
      expect(out).to include("lld linker")
      expect(out).to include("libzstd (zstd.h)")
      expect(out).not_to include("llc")
      expect(out).to match(%r{\d+/7 checks passed})
    end
  end

  describe "script arguments" do
    it "passes user args to argv() and ARGV without the script path" do
      Dir.mktmpdir("tungsten-cli-argv") do |dir|
        script = File.join(dir, "argv.w")
        File.write(script, <<~W)
          << argv().join("|")
          << ARGV.join("|")
        W

        ruby_out, ruby_err, ruby_status = run_cli(ruby_cli, "--ruby", script, "--", "--flag", "value with spaces")
        default_out, default_err, default_status = run_cli(ruby_cli, script, "--", "--flag", "value with spaces")

        expect(ruby_status.exitstatus).to eq(0), ruby_err
        expect(default_status.exitstatus).to eq(0), default_err
        expect(ruby_out).to eq("--flag|value with spaces\n--flag|value with spaces\n")
        expect(default_out).to eq("--flag|value with spaces\n--flag|value with spaces\n")
      end
    end

    it "keeps the public wrapper argv-correct for run and bare file execution" do
      Dir.mktmpdir("tungsten-shell-argv") do |dir|
        script = File.join(dir, "argv.w")
        File.write(script, <<~W)
          << argv().join("|")
          << ARGV.join("|")
        W

        run_out, run_err, run_status = run_shell_cli(shell_cli, "run", script, "--", "--flag", "value")
        bare_out, bare_err, bare_status = run_shell_cli(shell_cli, script, "--", "--flag", "value")

        expect(run_status.exitstatus).to eq(0), run_err
        expect(bare_status.exitstatus).to eq(0), bare_err
        expect(run_out).to eq("--flag|value\n--flag|value\n")
        expect(bare_out).to eq("--flag|value\n--flag|value\n")
      end
    end
  end
end
