# Tungsten Ruby Reference Implementation

This directory contains Tungsten's Ruby lexer, parser, tree-walking
interpreter, formatter, and reference literal implementations. It is useful for
language development and differential testing; the self-hosted native compiler
at the repository root is the most complete execution path.

## Running it

From the repository root:

```sh
bin/tungsten --ruby program.w
bin/tungsten --ruby -e '<< 1 + 1'
```

Or run the gem executable directly:

```sh
cd implementations/ruby
bundle install
bundle exec ruby exe/ruby-tungsten ../../doc/examples/01-basics/hello.w
```

Programmatic parsing is available through `Tungsten.parse(source)` or
`Tungsten::Parser.parse(source)`.

## Development

```sh
bundle install
bundle exec rake spec
bundle exec rspec spec/lexer_spec.rb
bundle exec rspec spec/parser_spec.rb:42
bundle exec rake expensive
bundle exec rubocop
```

Run the complete cross-implementation suite with `rake` from the repository
root. That command builds and fixed-point-verifies the self-hosted compiler
before running the Ruby, native runtime, Tungsten, and parity suites.

## Installing the gem

```sh
gem install tungsten-lang
ruby-tungsten -e '<< "hello world"'
```

The gem is distributed under the MIT license. The full repository is dual
licensed as described in the root README.
