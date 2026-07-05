# frozen_string_literal: true

require_relative "lib/tungsten/version"

Gem::Specification.new do |spec|
  spec.name          = "tungsten-lang"
  spec.version       = Tungsten::VERSION
  spec.authors       = ["Erik Peterson"]
  spec.email         = ["thecompanygardener@gmail.com"]

  spec.summary       = "The Tungsten programming language"
  spec.description   = "A lexer, parser, interpreter, and formatter for the Tungsten language. AI-native, token-efficient, with built-in units and quantities."
  spec.post_install_message = "✶ Tungsten installed. Try: tungsten -e '<< \"hello world\"'"
  spec.homepage      = "https://tungsten-lang.org"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  # Prevent pushing this gem to RubyGems.org by setting 'allowed_push_host', or
  # delete this section to allow pushing this gem to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "https://rubygems.org"

    spec.metadata["homepage_uri"]    = spec.homepage
    spec.metadata["source_code_uri"] = "https://github.com/tungsten-lang/tungsten"

    # spec.metadata["changelog_uri"]   = "TODO: Put your gem's CHANGELOG.md URL here."
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", ">= 2.3.9"
  spec.add_development_dependency "rake",    ">= 10.0"

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
end
