# frozen_string_literal: true

require_relative "spec_helper"
require "fileutils"
require "open3"
require "socket"
require "tmpdir"

RSpec.describe "tungsten-bit CLI" do
  BIT_SOURCE = File.join(PROJECT_ROOT, "bits/tungsten-bit/lib/bit.w")
  BITS_ROOT = File.join(PROJECT_ROOT, "bits")

  before(:all) do
    skip "compiled compiler not available" unless File.executable?(TUNGSTEN_BOOTSTRAP)

    @compile_dir = Dir.mktmpdir("bit-cli-compile")
    @bit_bin = File.join(@compile_dir, "bit")

    _out, err, status = Open3.capture3(
      {"BIT_HOME" => BITS_ROOT},
      TUNGSTEN_BOOTSTRAP,
      "compile",
      BIT_SOURCE,
      "--out",
      @bit_bin,
      chdir: PROJECT_ROOT
    )
    raise err unless status.success?
  end

  after(:all) do
    FileUtils.rm_rf(@compile_dir) if @compile_dir
  end

  around do |example|
    skip "compiled compiler not available" unless File.executable?(TUNGSTEN_BOOTSTRAP)

    Dir.mktmpdir("bit-cli-run") do |dir|
      @tmpdir = dir
      example.run
    end
  end

  it "prints command-specific help" do
    out, err, status = run_bit("help", "clean")

    expect(status.success?).to be(true), err
    expect(out).to include("bit clean (options)")
    expect(out).to include("--dry-run")
    expect(out).not_to include("bit help [COMMAND]")
  end

  it "reports environment info and command listings" do
    env_out, env_err, env_status = run_bit("env", chdir: @tmpdir)
    expect(env_status.success?).to be(true), env_err
    expect(env_out).to include("bit 0.1.0")
    expect(env_out).to include("registry ")
    expect(env_out).to include("project none")

    help_out, help_err, help_status = run_bit("help", "doctor")
    expect(help_status.success?).to be(true), help_err
    expect(help_out).to include("bit doctor (options)")
    expect(help_out).to include("--local")

    commands_out, commands_err, commands_status = run_bit("help", "commands")
    expect(commands_status.success?).to be(true), commands_err
    expect(commands_out).to include("env - Show bit environment information")
    expect(commands_out).to include("doctor - Check bit environment readiness")
    expect(commands_out).to include("audit - Audit installed and locked bits")

    info_out, _info_err, info_status = run_bit("info", chdir: @tmpdir)
    expect(info_status.success?).to be(false)
    expect(info_out).to include("bit info NAME")
    expect(info_out).to include("bit env")
  end

  it "audits remote lock entries for required signatures" do
    File.write(File.join(@tmpdir, "Bitfile.lock"), <<~LOCK)
      bit "remote-bit", "1.0.0", source: "remote", path: "https://bits.example/remote-bit-1.0.0.bit", sha256: "abc", security_status: "pass", security_risk: "low"
    LOCK

    out, _err, status = run_bit("audit", "--signatures", chdir: @tmpdir)

    expect(status.success?).to be(false)
    expect(out).to include("fail remote-bit - missing signature")
    expect(out).to include("fail remote-bit - missing public key")
  end

  it "applies source cooldown to feature releases but not security releases" do
    app_dir = File.join(@tmpdir, "app")
    FileUtils.mkdir_p(app_dir)

    now = Time.now.to_i
    feature_line = 'bit "tungsten-json", "0.2.0", source: "remote", path: "https://bits.example/tungsten-json-0.2.0.bit", summary: "JSON", release_type: "feature", published_at: "' + now.to_s + '"'
    security_line = 'bit "tungsten-json", "0.2.1", source: "remote", path: "https://bits.example/tungsten-json-0.2.1.bit", summary: "JSON", release_type: "security", published_at: "' + now.to_s + '"'

    with_registry_response(feature_line + "\n") do |registry|
      write_app_bitfile(app_dir, registry, cooldown: 7)
      write_lock(app_dir, "0.1.0")

      out, err, status = run_bit("outdated", chdir: app_dir)

      expect(status.success?).to be(true), err
      expect(out).to include("All bits up to date")
    end

    with_registry_response(security_line + "\n") do |registry|
      write_app_bitfile(app_dir, registry, cooldown: 7)
      write_lock(app_dir, "0.1.0")

      out, err, status = run_bit("outdated", chdir: app_dir)

      expect(status.success?).to be(true), err
      expect(out).to include("tungsten-json 0.1.0 -> 0.2.1")
    end

    with_registry_response(feature_line + "\n") do |registry|
      write_app_bitfile(app_dir, registry, cooldown: 7, trusted: true)
      write_lock(app_dir, "0.1.0")

      out, err, status = run_bit("outdated", chdir: app_dir)

      expect(status.success?).to be(true), err
      expect(out).to include("tungsten-json 0.1.0 -> 0.2.0")
    end
  end

  it "normalizes dashed flags while scaffolding a project" do
    out, err, status = run_bit("new", "sample_app", "--skip-git", chdir: @tmpdir)

    expect(status.success?).to be(true), err
    expect(out).to include("Done! cd sample_app")
    expect(File).to exist(File.join(@tmpdir, "sample_app", "Bitfile"))
    expect(File).not_to exist(File.join(@tmpdir, "sample_app", ".git"))
    expect(File.read(File.join(@tmpdir, "sample_app", "Bitfile"))).to include('name "sample_app"')
  end

  it "searches and installs from a local BIT_HOME registry" do
    registry = File.join(@tmpdir, "registry")
    app_dir = File.join(@tmpdir, "app")
    bit_dir = write_local_bit(
      registry,
      dir_name: "tungsten-json-0.1.5",
      name: "tungsten-json",
      version: "0.1.5",
      summary: "JSON support"
    )
    write_local_bit(
      registry,
      dir_name: "tungsten-json-0.2.0",
      name: "tungsten-json",
      version: "0.2.0",
      summary: "JSON support"
    )

    FileUtils.mkdir_p(app_dir)
    File.write(File.join(app_dir, "Bitfile"), <<~BITFILE)
      tungsten "sample-0.1.0"
      name "sample"
      version "0.1.0"
      dependency "tungsten-json", "~> 0.1.0"
    BITFILE

    search_out, search_err, search_status = run_bit("search", "json", chdir: app_dir, env: {"BIT_HOME" => registry})
    expect(search_status.success?).to be(true), search_err
    expect(search_out).to include("Found 1 bits")
    expect(search_out).to include("tungsten-json (0.2.0, 0.1.5) 2 versions")

    dry_out, dry_err, dry_status = run_bit("install", "--dry-run", chdir: app_dir, env: {"BIT_HOME" => registry})
    expect(dry_status.success?).to be(true), dry_err
    expect(dry_out).to include("install: tungsten-json 0.1.5 from #{bit_dir}")

    _install_out, install_err, install_status = run_bit("install", chdir: app_dir, env: {"BIT_HOME" => registry})
    expect(install_status.success?).to be(true), install_err
    expect(File).to exist(File.join(app_dir, "vendor/bits/tungsten-json/Bitfile"))
    lockfile = File.read(File.join(app_dir, "Bitfile.lock"))
    expect(lockfile).to include('bit "tungsten-json", "0.1.5"')
    expect(lockfile).to include("path: \"#{bit_dir}\"")
  end

  it "lists, shows, updates, and prunes installed local bits" do
    registry = File.join(@tmpdir, "registry")
    app_dir = File.join(@tmpdir, "app")

    write_local_bit(registry, dir_name: "tungsten-json-0.1.0", name: "tungsten-json", version: "0.1.0")

    FileUtils.mkdir_p(app_dir)
    File.write(File.join(app_dir, "Bitfile"), <<~BITFILE)
      tungsten "sample-0.1.0"
      name "sample"
      version "0.1.0"
      dependency "tungsten-json", ">= 0.0.0"
    BITFILE

    _install_out, install_err, install_status = run_bit("install", chdir: app_dir, env: {"BIT_HOME" => registry})
    expect(install_status.success?).to be(true), install_err

    list_out, list_err, list_status = run_bit("list", chdir: app_dir, env: {"BIT_HOME" => registry})
    expect(list_status.success?).to be(true), list_err
    expect(list_out).to include("tungsten-json 0.1.0 (locked 0.1.0, local)")

    show_out, show_err, show_status = run_bit("show", "tungsten-json", chdir: app_dir, env: {"BIT_HOME" => registry})
    expect(show_status.success?).to be(true), show_err
    expect(show_out).to include("status  installed")
    expect(show_out).to include("locked  0.1.0")
    expect(show_out).to include("source  local")

    lockfile_path = File.join(app_dir, "Bitfile.lock")
    File.write(
      lockfile_path,
      File.read(lockfile_path).strip + ', security_status: "pass", security_risk: "low"' + "\n"
    )
    security_out, security_err, security_status = run_bit("show", "tungsten-json", chdir: app_dir, env: {"BIT_HOME" => registry})
    expect(security_status.success?).to be(true), security_err
    expect(security_out).to include("security pass (low)")

    audit_out, audit_err, audit_status = run_bit("audit", chdir: app_dir, env: {"BIT_HOME" => registry})
    expect(audit_status.success?).to be(true), audit_err
    expect(audit_out).to include("ok   tungsten-json 0.1.0 security pass low")
    expect(audit_out).to include("Audit passed")

    File.write(
      lockfile_path,
      File.read(lockfile_path)
          .sub('security_status: "pass"', 'security_status: "fail"')
          .sub('security_risk: "low"', 'security_risk: "high"')
    )
    bad_audit_out, _bad_audit_err, bad_audit_status = run_bit("audit", chdir: app_dir, env: {"BIT_HOME" => registry})
    expect(bad_audit_status.success?).to be(false)
    expect(bad_audit_out).to include("fail tungsten-json - security fail high")

    write_local_bit(registry, dir_name: "tungsten-json-0.2.0", name: "tungsten-json", version: "0.2.0")

    outdated_out, outdated_err, outdated_status = run_bit("outdated", chdir: app_dir, env: {"BIT_HOME" => registry})
    expect(outdated_status.success?).to be(true), outdated_err
    expect(outdated_out).to include("tungsten-json 0.1.0 -> 0.2.0")

    upgrade_dry_out, upgrade_dry_err, upgrade_dry_status = run_bit("upgrade", "--dry-run", chdir: app_dir, env: {"BIT_HOME" => registry})
    expect(upgrade_dry_status.success?).to be(true), upgrade_dry_err
    expect(upgrade_dry_out).to include("upgrade: tungsten-json 0.1.0 -> 0.2.0")

    dry_out, dry_err, dry_status = run_bit("update", "--dry-run", chdir: app_dir, env: {"BIT_HOME" => registry})
    expect(dry_status.success?).to be(true), dry_err
    expect(dry_out).to include("update: tungsten-json 0.2.0")

    _upgrade_out, upgrade_err, upgrade_status = run_bit("upgrade", chdir: app_dir, env: {"BIT_HOME" => registry})
    expect(upgrade_status.success?).to be(true), upgrade_err
    expect(File.read(File.join(app_dir, "Bitfile.lock"))).to include('bit "tungsten-json", "0.2.0"')
    expect(File.read(File.join(app_dir, "vendor/bits/tungsten-json/Bitfile"))).to include('version "0.2.0"')

    up_to_date_out, up_to_date_err, up_to_date_status = run_bit("outdated", chdir: app_dir, env: {"BIT_HOME" => registry})
    expect(up_to_date_status.success?).to be(true), up_to_date_err
    expect(up_to_date_out).to include("All bits up to date")

    stale_dir = File.join(app_dir, "vendor/bits/tungsten-old")
    FileUtils.mkdir_p(stale_dir)
    File.write(File.join(stale_dir, "Bitfile"), <<~BITFILE)
      tungsten "old-0.0.1"
      name "tungsten-old"
      version "0.0.1"
    BITFILE

    prune_out, prune_err, prune_status = run_bit("prune", "--dry-run", chdir: app_dir, env: {"BIT_HOME" => registry})
    expect(prune_status.success?).to be(true), prune_err
    expect(prune_out).to include("would remove tungsten-old 0.0.1")

    _pruned_out, pruned_err, pruned_status = run_bit("prune", chdir: app_dir, env: {"BIT_HOME" => registry})
    expect(pruned_status.success?).to be(true), pruned_err
    expect(File).not_to exist(stale_dir)
  end

  it "handles dependency groups and prerelease selection" do
    registry = File.join(@tmpdir, "registry")
    app_dir = File.join(@tmpdir, "app")

    stable_dir = write_local_bit(registry, dir_name: "tungsten-json-0.1.5", name: "tungsten-json", version: "0.1.5")
    prerelease_dir = write_local_bit(registry, dir_name: "tungsten-json-0.1.6.rc1", name: "tungsten-json", version: "0.1.6.rc1")
    dev_dir = write_local_bit(registry, dir_name: "tungsten-console-0.1.0", name: "tungsten-console", version: "0.1.0")
    optional_dir = write_local_bit(registry, dir_name: "tungsten-pg-0.1.0", name: "tungsten-pg", version: "0.1.0")

    FileUtils.mkdir_p(app_dir)
    File.write(File.join(app_dir, "Bitfile"), <<~BITFILE)
      tungsten "sample-0.1.0"
      name "sample"
      version "0.1.0"
      dependency "tungsten-json", "~> 0.1.0"

      group :development do
        dependency "tungsten-console", ">= 0.0.0"
      end

      dependency "tungsten-pg", ">= 0.0.0", optional: true
    BITFILE

    out, err, status = run_bit("install", "--dry-run", chdir: app_dir, env: {"BIT_HOME" => registry})
    expect(status.success?).to be(true), err
    expect(out).to include("tungsten-json 0.1.5 from #{stable_dir}")
    expect(out).to include("tungsten-console 0.1.0 from #{dev_dir}")
    expect(out).not_to include(prerelease_dir)
    expect(out).not_to include(optional_dir)

    pre_out, pre_err, pre_status = run_bit("install", "--dry-run", "--pre", chdir: app_dir, env: {"BIT_HOME" => registry})
    expect(pre_status.success?).to be(true), pre_err
    expect(pre_out).to include("tungsten-json 0.1.6.rc1 from #{prerelease_dir}")

    without_out, without_err, without_status = run_bit("install", "--dry-run", "--without", "development", chdir: app_dir, env: {"BIT_HOME" => registry})
    expect(without_status.success?).to be(true), without_err
    expect(without_out).not_to include("tungsten-console")

    with_out, with_err, with_status = run_bit("install", "--dry-run", "--with", "optional", chdir: app_dir, env: {"BIT_HOME" => registry})
    expect(with_status.success?).to be(true), with_err
    expect(with_out).to include("tungsten-pg 0.1.0 from #{optional_dir}")
  end

  it "packs a dry-run publish archive" do
    package_dir = File.join(@tmpdir, "package")
    FileUtils.mkdir_p(File.join(package_dir, "lib"))
    File.write(File.join(package_dir, "Bitfile"), <<~BITFILE)
      tungsten "sample-0.1.0"
      name "sample"
      version "0.1.0"
      summary "Sample package"
      license "MIT"
    BITFILE
    File.write(File.join(package_dir, "lib", "sample.w"), "# package fixture\n")

    out, err, status = run_bit("publish", "--dry-run", chdir: package_dir)

    expect(status.success?).to be(true), err
    expect(out).to include("Dry run - would publish sample 0.1.0")
    expect(File).to exist(File.join(package_dir, "pkg/sample-0.1.0.bit"))
    expect(File).to exist(File.join(package_dir, "pkg/sample-0.1.0.bit.sha256"))
  end

  it "builds manifest-declared executables and assets with a compiler override" do
    package_dir = File.join(@tmpdir, "application-bit")
    FileUtils.mkdir_p(File.join(package_dir, "lib"))
    FileUtils.mkdir_p(File.join(package_dir, "runtime", "gpu"))
    File.write(File.join(package_dir, "Bitfile"), <<~BITFILE)
      tungsten "sample-app-0.1.0"
      name "sample-app"
      version "0.1.0"
      executable "sample", source: "lib/main.w"
      asset "runtime/gpu"
      asset "lib"
    BITFILE
    File.write(File.join(package_dir, "lib", "main.w"), "<< \"hello\"\n")
    File.write(File.join(package_dir, "runtime", "gpu", "kernel.metal"), "kernel fixture\n")

    compiler_log = File.join(@tmpdir, "compiler.log")
    fake_compiler = write_fake_compiler(File.join(@tmpdir, "override-tungsten"))
    out, err, status = run_bit(
      "build", "--release",
      chdir: package_dir,
      env: {"TUNGSTEN_COMPILER" => fake_compiler, "FAKE_COMPILER_LOG" => compiler_log}
    )

    expect(status.success?).to be(true), err
    expect(out).to include("Built sample-app (1 files")
    expect(File).to be_executable(File.join(package_dir, "build/bin/sample"))
    expect(File.read(File.join(package_dir, "build/runtime/gpu/kernel.metal"))).to eq("kernel fixture\n")
    expect(File.read(File.join(package_dir, "build/lib/main.w"))).to eq("<< \"hello\"\n")
    invocation = File.read(compiler_log)
    expect(invocation).to include("compile\nlib/main.w\n--out\nbuild/bin/sample\n--release\n")

    _out, repeat_err, repeat_status = run_bit(
      "build", "--release",
      chdir: package_dir,
      env: {"TUNGSTEN_COMPILER" => fake_compiler, "FAKE_COMPILER_LOG" => compiler_log}
    )
    expect(repeat_status.success?).to be(true), repeat_err
    expect(File).not_to exist(File.join(package_dir, "build/lib/lib/main.w"))
  end

  it "finds the Tungsten driver on PATH when building outside a checkout" do
    package_dir = File.join(@tmpdir, "path-application-bit")
    tool_dir = File.join(@tmpdir, "tools")
    FileUtils.mkdir_p(File.join(package_dir, "lib"))
    FileUtils.mkdir_p(tool_dir)
    File.write(File.join(package_dir, "Bitfile"), <<~BITFILE)
      tungsten "path-app-0.1.0"
      name "path-app"
      version "0.1.0"
      executable "path-app", source: "lib/path_app.w"
    BITFILE
    File.write(File.join(package_dir, "lib", "path_app.w"), "<< \"hello\"\n")

    compiler_log = File.join(@tmpdir, "path-compiler.log")
    write_fake_compiler(File.join(tool_dir, "tungsten"))
    _out, err, status = run_bit(
      "build",
      chdir: package_dir,
      env: {
        "TUNGSTEN_COMPILER" => "",
        "TUNGSTEN" => "",
        "TUNGSTEN_ROOT" => "",
        "FAKE_COMPILER_LOG" => compiler_log,
        "PATH" => tool_dir + File::PATH_SEPARATOR + ENV.fetch("PATH")
      }
    )

    expect(status.success?).to be(true), err
    expect(File).to be_executable(File.join(package_dir, "build/bin/path-app"))
    expect(File.read(compiler_log)).to include("lib/path_app.w")
  end

  it "packs declared assets and common dual-license files" do
    package_dir = File.join(@tmpdir, "asset-bit")
    FileUtils.mkdir_p(File.join(package_dir, "lib"))
    FileUtils.mkdir_p(File.join(package_dir, "assets", "seeds"))
    FileUtils.mkdir_p(File.join(package_dir, "runtime", "gpu"))
    File.write(File.join(package_dir, "Bitfile"), <<~BITFILE)
      tungsten "asset-bit-0.1.0"
      name "asset-bit"
      version "0.1.0"
      executable "asset-bit", source: "lib/asset_bit.w"
      asset "runtime/gpu"
    BITFILE
    File.write(File.join(package_dir, "lib", "asset_bit.w"), "# fixture\n")
    File.write(File.join(package_dir, "assets", "seeds", "seed.txt"), "seed\n")
    File.write(File.join(package_dir, "runtime", "gpu", "kernel.metal"), "kernel\n")
    File.write(File.join(package_dir, "LICENSE-MIT"), "MIT\n")
    File.write(File.join(package_dir, "LICENSE-APACHE"), "Apache-2.0\n")
    File.write(File.join(package_dir, "NOTICE"), "notice\n")
    File.write(File.join(package_dir, "THIRD_PARTY.md"), "third-party notices\n")

    _out, err, status = run_bit("pack", chdir: package_dir)
    expect(status.success?).to be(true), err

    archive = File.join(package_dir, "pkg/asset-bit-0.1.0.bit")
    entries, tar_err, tar_status = Open3.capture3("tar", "-tf", archive)
    expect(tar_status.success?).to be(true), tar_err
    expect(entries.lines.map(&:chomp)).to include(
      "LICENSE-MIT",
      "LICENSE-APACHE",
      "NOTICE",
      "THIRD_PARTY.md",
      "assets/seeds/seed.txt",
      "runtime/gpu/kernel.metal"
    )
  end

  def run_bit(*args, chdir: PROJECT_ROOT, env: {})
    Open3.capture3({"BIT_HOME" => BITS_ROOT}.merge(env), @bit_bin, *args, chdir: chdir)
  end

  def write_fake_compiler(path)
    File.write(path, <<~SH)
      #!/bin/sh
      set -eu
      printf '%s\n' "$@" >> "$FAKE_COMPILER_LOG"
      output=""
      while [ "$#" -gt 0 ]; do
        if [ "$1" = "--out" ]; then
          shift
          output="$1"
        fi
        shift
      done
      test -n "$output"
      mkdir -p "$(dirname "$output")"
      printf '#!/bin/sh\nexit 0\n' > "$output"
      chmod +x "$output"
    SH
    FileUtils.chmod(0o755, path)
    path
  end

  def write_local_bit(registry, dir_name:, name:, version:, summary: "#{name} #{version}")
    bit_dir = File.join(registry, dir_name)
    FileUtils.mkdir_p(File.join(bit_dir, "lib"))
    File.write(File.join(bit_dir, "Bitfile"), <<~BITFILE)
      tungsten "tungsten-0.0.1"
      name "#{name}"
      version "#{version}"
      summary "#{summary}"
      license "MIT"
    BITFILE
    File.write(File.join(bit_dir, "lib", "#{name}.w"), "# local fixture\n")
    bit_dir
  end

  def write_app_bitfile(app_dir, registry, cooldown:, trusted: false)
    trusted_option = trusted ? ", trusted: true" : ""
    File.write(File.join(app_dir, "Bitfile"), <<~BITFILE)
      tungsten "sample-0.1.0"
      source "#{registry}", cooldown: #{cooldown}#{trusted_option}
      name "sample"
      version "0.1.0"
      dependency "tungsten-json", ">= 0.0.0"
    BITFILE
  end

  def write_lock(app_dir, version)
    File.write(File.join(app_dir, "Bitfile.lock"), <<~LOCK)
      bit "tungsten-json", "#{version}", source: "remote", path: "https://bits.example/tungsten-json-#{version}.bit", summary: "JSON", release_type: "feature", published_at: "1"
    LOCK
  end

  def with_registry_response(body)
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      loop do
        client = server.accept
        client.gets
        loop do
          line = client.gets
          break if line.nil? || line == "\r\n"
        end
        client.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
        client.close
      rescue IOError, Errno::EBADF
        break
      end
    end
    yield "http://127.0.0.1:#{server.addr[1]}"
  ensure
    server.close if server
    thread.kill if thread
  end
end
