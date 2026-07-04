# frozen_string_literal: true

require "fileutils"
require "open-uri"
require "rubygems/version"
require "tmpdir"
require "uri"

module Tungsten
  module ExternalDependencies
    ROOT = File.expand_path("../..", __dir__)
    USER_AGENT = "tungsten-deps/1.0"
    CURRENT_SELECTORS = %w[current latest].freeze

    class Error < StandardError; end

    Dependency = Struct.new(:name, :requested_version, keyword_init: true) do
      def initialize(name:, requested_version:)
        super(name: name.to_s.strip.downcase, requested_version: requested_version.to_s.strip)
      end

      def current_selector?
        CURRENT_SELECTORS.include?(requested_version.downcase)
      end
    end

    PlanItem = Struct.new(:provider, :version, :roles, keyword_init: true) do
      def label
        "#{provider.name} #{version}"
      end

      def install_dir(root)
        File.join(root, "src", "pristine", provider.install_dir_name(version))
      end

      def archive_name
        provider.archive_name(version)
      end

      def download_url
        provider.download_url(version)
      end

      def extracted_root_name
        provider.extracted_root_name(version)
      end
    end

    InstallResult = Struct.new(:item, :path, :status, keyword_init: true) do
      def downloaded?
        status == :downloaded
      end
    end

    class Provider
      VERSION_PATTERN = /\A\d+\.\d+\.\d+\z/.freeze

      attr_reader :name

      def initialize(name:, install_dir_name:, archive_name:, extracted_root_name:, download_url:, latest_version:)
        @name = name
        @install_dir_name = install_dir_name
        @archive_name = archive_name
        @extracted_root_name = extracted_root_name
        @download_url = download_url
        @latest_version = latest_version
      end

      def resolve_version(requested_version, latest_versions)
        version = requested_version.to_s.strip
        return latest_version(latest_versions) if CURRENT_SELECTORS.include?(version.downcase)
        return version if VERSION_PATTERN.match?(version)

        raise Error, %(external "#{name}" version must be x.y.z or "current", got #{requested_version.inspect})
      end

      def latest_version(latest_versions)
        @latest_version.call(latest_versions)
      end

      def install_dir_name(version)
        @install_dir_name.call(version)
      end

      def archive_name(version)
        @archive_name.call(version)
      end

      def extracted_root_name(version)
        @extracted_root_name.call(version)
      end

      def download_url(version)
        @download_url.call(version)
      end
    end

    class LatestVersions
      RUBY_RELEASES_URL = "https://www.ruby-lang.org/en/downloads/releases/"
      LLVM_LATEST_URL = "https://github.com/llvm/llvm-project/releases/latest"
      OPENSSL_RELEASES_URL = "https://openssl-library.org/source/"

      def initialize(fetch_url: nil)
        @fetch_url = fetch_url || method(:fetch_url)
        @cache = {}
      end

      def call(name)
        @cache[name] ||= case name
                         when "ruby" then latest_ruby_version
                         when "llvm" then latest_llvm_version
                         when "openssl" then latest_openssl_version
                         else
                           raise Error, %(unsupported external dependency "#{name}")
                         end
      end

      private

      def latest_ruby_version
        html = @fetch_url.call(RUBY_RELEASES_URL)
        versions = html.scan(/Ruby\s+(\d+\.\d+\.\d+)/i).flatten.uniq
        version = versions.max_by { |entry| Gem::Version.new(entry) }
        return version if version

        raise Error, "unable to determine the current Ruby release from #{RUBY_RELEASES_URL}"
      end

      def latest_llvm_version
        final_uri = nil

        URI.open(LLVM_LATEST_URL, "User-Agent" => USER_AGENT) do |io|
          final_uri = io.base_uri
          io.read(1)
        end

        version = final_uri&.path&.match(%r{/tag/llvmorg-(\d+\.\d+\.\d+)\z})&.captures&.first
        return version if version

        raise Error, "unable to determine the current LLVM release from #{LLVM_LATEST_URL}"
      end

      def latest_openssl_version
        html = @fetch_url.call(OPENSSL_RELEASES_URL)
        versions = html.scan(/openssl-(\d+\.\d+\.\d+)\.tar\.gz/i).flatten.uniq
        version = versions.max_by { |entry| Gem::Version.new(entry) }
        return version if version

        raise Error, "unable to determine the current OpenSSL release from #{OPENSSL_RELEASES_URL}"
      end

      def fetch_url(url)
        URI.open(url, "User-Agent" => USER_AGENT, &:read)
      end
    end

    class Scanner
      EXTERNAL_PATTERN = /
        ^\s*
        external(?:_dependency)?
        \s+
        ["'](?<name>[^"']+)["']
        \s*,\s*
        ["'](?<version>[^"']+)["']
      /x.freeze

      def parse(text)
        text.each_line.filter_map do |line|
          stripped = strip_comment(line)
          next if stripped.strip.empty?

          match = stripped.match(EXTERNAL_PATTERN)
          next unless match

          Dependency.new(name: match[:name], requested_version: match[:version])
        end
      end

      def load(path)
        parse(File.read(path))
      end

      private

      def strip_comment(line)
        line.sub(/\s+#.*\z/, "")
      end
    end

    DEFAULT_PROVIDERS = {
      "ruby" => Provider.new(
        name: "ruby",
        install_dir_name: ->(version) { "ruby-#{version}" },
        archive_name: ->(version) { "ruby-#{version}.tar.xz" },
        extracted_root_name: ->(version) { "ruby-#{version}" },
        download_url: lambda { |version|
          major, minor, = version.split(".")
          "https://cache.ruby-lang.org/pub/ruby/#{major}.#{minor}/ruby-#{version}.tar.xz"
        },
        latest_version: ->(latest_versions) { latest_versions.call("ruby") }
      ),
      "llvm" => Provider.new(
        name: "llvm",
        install_dir_name: ->(version) { "llvm-#{version}" },
        archive_name: ->(version) { "llvm-project-#{version}.src.tar.xz" },
        extracted_root_name: ->(version) { "llvm-project-#{version}.src" },
        download_url: ->(version) { "https://github.com/llvm/llvm-project/releases/download/llvmorg-#{version}/llvm-project-#{version}.src.tar.xz" },
        latest_version: ->(latest_versions) { latest_versions.call("llvm") }
      ),
      "openssl" => Provider.new(
        name: "openssl",
        install_dir_name: ->(version) { "openssl-#{version}" },
        archive_name: ->(version) { "openssl-#{version}.tar.gz" },
        extracted_root_name: ->(version) { "openssl-#{version}" },
        download_url: ->(version) { "https://github.com/openssl/openssl/releases/download/openssl-#{version}/openssl-#{version}.tar.gz" },
        latest_version: ->(latest_versions) { latest_versions.call("openssl") }
      )
    }.freeze

    class Manager
      attr_reader :root

      def initialize(root: ROOT, providers: DEFAULT_PROVIDERS, latest_versions: LatestVersions.new, scanner: Scanner.new)
        @root = root
        @providers = providers
        @latest_versions = latest_versions
        @scanner = scanner
      end

      def plan_for_bitfile(bitfile_path)
        raise Error, "Bitfile not found: #{bitfile_path}" unless File.exist?(bitfile_path)

        items = {}

        @scanner.load(bitfile_path).each do |dependency|
          provider = provider_for(dependency.name)
          declared_version = provider.resolve_version(dependency.requested_version, @latest_versions)
          upsert_plan_item(items, provider, declared_version, :declared)

          current_version = provider.latest_version(@latest_versions)
          upsert_plan_item(items, provider, current_version, :current)
        end

        items.values.sort_by { |item| [item.provider.name, Gem::Version.new(item.version)] }
      end

      def install_from_bitfile(bitfile_path, io: $stdout)
        results = install_plan(plan_for_bitfile(bitfile_path), io: io)
        ensure_declared_aliases(bitfile_path, io: io)
        seed_patched_directories(bitfile_path, io: io)
        results
      end

      def install_plan(items, io: $stdout)
        return [] if items.empty?

        items.map { |item| install(item, io: io) }
      end

      private

      def provider_for(name)
        provider = @providers[name]
        return provider if provider

        supported = @providers.keys.sort.join(", ")
        raise Error, %(unsupported external dependency "#{name}" (supported: #{supported}))
      end

      def upsert_plan_item(items, provider, version, role)
        key = [provider.name, version]
        item = items[key] ||= PlanItem.new(provider: provider, version: version, roles: [])
        item.roles << role unless item.roles.include?(role)
      end

      def install(item, io:)
        destination = item.install_dir(root)
        if File.directory?(destination)
          io.puts "present #{relative_path(destination)}"
          return InstallResult.new(item: item, path: destination, status: :present)
        end

        FileUtils.mkdir_p(File.dirname(destination))
        io.puts "fetch   #{item.label} -> #{relative_path(destination)}"

        with_temp_archive(item) do |archive_path|
          extract_into_destination(item, archive_path, destination)
        end

        InstallResult.new(item: item, path: destination, status: :downloaded)
      end

      def with_temp_archive(item)
        Dir.mktmpdir("#{item.provider.name}-download-") do |dir|
          archive_path = File.join(dir, item.archive_name)
          URI.open(item.download_url, "User-Agent" => USER_AGENT) do |remote|
            File.open(archive_path, "wb") do |file|
              IO.copy_stream(remote, file)
            end
          end
          yield archive_path
        rescue OpenURI::HTTPError, Errno::ENOENT, SocketError => e
          raise Error, "download failed for #{item.label}: #{e.message}"
        end
      end

      def extract_into_destination(item, archive_path, destination)
        staging_root = Dir.mktmpdir("#{item.provider.name}-extract-", File.dirname(destination))
        extracted_root = File.join(staging_root, item.extracted_root_name)

        begin
          success = system("tar", "-xf", archive_path, "-C", staging_root)
          raise Error, "failed to extract #{archive_path}" unless success

          unless File.directory?(extracted_root)
            children = Dir.children(staging_root).map { |entry| File.join(staging_root, entry) }.select { |path| File.directory?(path) }
            extracted_root = children.first
          end

          raise Error, "could not find extracted directory for #{item.label}" unless extracted_root && File.directory?(extracted_root)

          return if File.directory?(destination)

          FileUtils.mv(extracted_root, destination)
        ensure
          FileUtils.rm_rf(staging_root)
        end
      end

      def relative_path(path)
        path.delete_prefix("#{root}/")
      end

      def ensure_declared_aliases(bitfile_path, io:)
        declared_dependencies(bitfile_path).each do |dependency|
          provider = provider_for(dependency.name)
          version = provider.resolve_version(dependency.requested_version, @latest_versions)
          target = File.join(root, "src", "pristine", provider.install_dir_name(version))
          next unless File.directory?(target)

          alias_path = File.join(root, "src", "pristine", provider.name)
          ensure_alias(alias_path, target, io: io)
        end
      end

      def ensure_alias(alias_path, target, io:)
        if File.symlink?(alias_path)
          return if File.realpath(alias_path) == File.realpath(target)
          FileUtils.rm_f(alias_path)
        elsif File.exist?(alias_path)
          io.puts "skip    #{relative_path(alias_path)} already exists and is not a symlink"
          return
        end

        FileUtils.ln_sf(File.basename(target), alias_path)
        io.puts "alias   #{relative_path(alias_path)} -> #{relative_path(target)}"
      end

      def declared_dependencies(bitfile_path)
        @scanner.load(bitfile_path)
      end

      # `src/patched/<name>` is the working copy the build system edits and
      # compiles in place (e.g. `src/patched/ruby/ruby` is the built binary,
      # `src/patched/spinel/lib/libspinel_rt.a` is its built archive). Seed
      # it from `src/pristine/<name>-<version>` the first time so users don't
      # have to copy by hand. Existing patched dirs are left untouched.
      def seed_patched_directories(bitfile_path, io:)
        declared_dependencies(bitfile_path).each do |dependency|
          provider = provider_for(dependency.name)
          version = provider.resolve_version(dependency.requested_version, @latest_versions)
          source = File.join(root, "src", "pristine", provider.install_dir_name(version))
          next unless File.directory?(source)

          patched_path = File.join(root, "src", "patched", provider.name)
          if File.exist?(patched_path) || File.symlink?(patched_path)
            io.puts "present #{relative_path(patched_path)}"
            next
          end

          FileUtils.mkdir_p(File.dirname(patched_path))
          FileUtils.cp_r(source, patched_path)
          io.puts "seed    #{relative_path(patched_path)} <- #{relative_path(source)}"
        end
      end
    end
  end
end
