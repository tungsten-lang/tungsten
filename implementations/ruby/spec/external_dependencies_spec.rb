# frozen_string_literal: true

require "fileutils"
require "stringio"
require "tmpdir"

require_relative "../../../lib/tungsten/external_dependencies"

RSpec.describe Tungsten::ExternalDependencies do
  def build_manager(latest_versions)
    root = Dir.mktmpdir("tungsten-external-deps-root-")
    @tmpdirs << root

    stub = Class.new do
      def initialize(versions)
        @versions = versions
      end

      def call(name)
        @versions.fetch(name)
      end
    end.new(latest_versions)

    Tungsten::ExternalDependencies::Manager.new(root: root, latest_versions: stub)
  end

  def with_bitfile(contents)
    Dir.mktmpdir("tungsten-bitfile-") do |dir|
      path = File.join(dir, "Bitfile")
      File.write(path, contents)
      yield path
    end
  end

  before { @tmpdirs = [] }
  after { @tmpdirs.each { |dir| FileUtils.rm_rf(dir) } }

  describe Tungsten::ExternalDependencies::Scanner do
    it "extracts external dependencies from bitfile text" do
      text = <<~BITFILE
        tungsten "tungsten-0.0.1"
        bit "tungsten-compiler", local: true

        external "ruby", "4.0.2"
        external_dependency "llvm", "current" # keep testing against head
        external "openssl", "current"
      BITFILE

      dependencies = described_class.new.parse(text)

      expect(dependencies.map { |d| [d.name, d.requested_version] }).to eq(
        [["ruby", "4.0.2"], ["llvm", "current"], ["openssl", "current"]]
      )
    end
  end

  describe Tungsten::ExternalDependencies::Manager do
    it "includes declared and current versions when they differ" do
      manager = build_manager("ruby" => "4.1.0", "llvm" => "21.1.7", "openssl" => "3.6.1")

      plan = with_bitfile(<<~BITFILE) { |path| manager.plan_for_bitfile(path) }
        external "ruby", "4.0.2"
        external "llvm", "current"
        external "openssl", "current"
      BITFILE

      expect(plan.map { |item| [item.provider.name, item.version, item.roles.sort] }).to eq(
        [
          ["llvm", "21.1.7", %i[current declared].sort],
          ["openssl", "3.6.1", %i[current declared].sort],
          ["ruby", "4.0.2", [:declared]],
          ["ruby", "4.1.0", [:current]]
        ]
      )
    end

    it "deduplicates when declared version is already current" do
      manager = build_manager("ruby" => "4.0.2")

      plan = with_bitfile(%(external "ruby", "4.0.2"\n)) { |path| manager.plan_for_bitfile(path) }

      expect(plan.length).to eq(1)
      expect(plan.first.provider.name).to eq("ruby")
      expect(plan.first.version).to eq("4.0.2")
      expect(plan.first.roles.sort).to eq(%i[current declared])
    end

    it "creates declared aliases on install" do
      manager = build_manager("ruby" => "4.1.0", "llvm" => "21.1.7", "openssl" => "3.6.1")

      with_bitfile(<<~BITFILE) do |path|
        external "ruby", "4.0.2"
        external "openssl", "current"
      BITFILE
        FileUtils.mkdir_p(File.join(manager.root, "src", "pristine", "ruby-4.0.2"))
        FileUtils.mkdir_p(File.join(manager.root, "src", "pristine", "ruby-4.1.0"))
        FileUtils.mkdir_p(File.join(manager.root, "src", "pristine", "openssl-3.6.1"))

        manager.install_from_bitfile(path, io: StringIO.new)

        ruby_link = File.join(manager.root, "src", "pristine", "ruby")
        openssl_link = File.join(manager.root, "src", "pristine", "openssl")

        expect(File.symlink?(ruby_link)).to be true
        expect(File.readlink(ruby_link)).to eq("ruby-4.0.2")
        expect(File.symlink?(openssl_link)).to be true
        expect(File.readlink(openssl_link)).to eq("openssl-3.6.1")
      end
    end

    it "seeds src/patched/<name> from the declared pristine version" do
      manager = build_manager("ruby" => "4.0.2", "openssl" => "3.6.1")

      with_bitfile(<<~BITFILE) do |path|
        external "ruby", "4.0.2"
        external "openssl", "current"
      BITFILE
        ruby_pristine = File.join(manager.root, "src", "pristine", "ruby-4.0.2")
        openssl_pristine = File.join(manager.root, "src", "pristine", "openssl-3.6.1")
        FileUtils.mkdir_p(ruby_pristine)
        FileUtils.mkdir_p(openssl_pristine)
        File.write(File.join(ruby_pristine, "marker"), "ruby")
        File.write(File.join(openssl_pristine, "marker"), "openssl")

        manager.install_from_bitfile(path, io: StringIO.new)

        ruby_patched = File.join(manager.root, "src", "patched", "ruby")
        openssl_patched = File.join(manager.root, "src", "patched", "openssl")

        expect(File.directory?(ruby_patched)).to be true
        expect(File.read(File.join(ruby_patched, "marker"))).to eq("ruby")
        expect(File.directory?(openssl_patched)).to be true
        expect(File.read(File.join(openssl_patched, "marker"))).to eq("openssl")
      end
    end

    it "leaves an existing src/patched/<name> untouched" do
      manager = build_manager("ruby" => "4.0.2")

      with_bitfile(%(external "ruby", "4.0.2"\n)) do |path|
        FileUtils.mkdir_p(File.join(manager.root, "src", "pristine", "ruby-4.0.2"))
        existing = File.join(manager.root, "src", "patched", "ruby")
        FileUtils.mkdir_p(existing)
        File.write(File.join(existing, "user_edit"), "do not clobber")

        manager.install_from_bitfile(path, io: StringIO.new)

        expect(File.read(File.join(existing, "user_edit"))).to eq("do not clobber")
      end
    end
  end

  describe "provider download URLs" do
    it "matches expected release archives" do
      ruby = Tungsten::ExternalDependencies::DEFAULT_PROVIDERS.fetch("ruby")
      llvm = Tungsten::ExternalDependencies::DEFAULT_PROVIDERS.fetch("llvm")
      openssl = Tungsten::ExternalDependencies::DEFAULT_PROVIDERS.fetch("openssl")

      expect(ruby.download_url("4.0.2")).to eq(
        "https://cache.ruby-lang.org/pub/ruby/4.0/ruby-4.0.2.tar.xz"
      )
      expect(llvm.download_url("21.1.7")).to eq(
        "https://github.com/llvm/llvm-project/releases/download/llvmorg-21.1.7/llvm-project-21.1.7.src.tar.xz"
      )
      expect(openssl.download_url("3.6.1")).to eq(
        "https://github.com/openssl/openssl/releases/download/openssl-3.6.1/openssl-3.6.1.tar.gz"
      )
    end
  end
end
