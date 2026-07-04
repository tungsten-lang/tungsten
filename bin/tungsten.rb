#!/usr/bin/env ruby

# vim: filetype=ruby

require "optparse"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
COMPILER = File.join(ROOT, "bin/tungsten-compiler")
HAVE_COMPILER = File.executable?(COMPILER)

def load_gem!
  $LOAD_PATH.unshift(File.join(ROOT, "implementations/ruby/lib"))
  require "tungsten"
rescue LoadError => e
  # Fresh clone, no compiler yet: the Ruby interpreter fallback needs its gems.
  # Tell the user exactly how to fix it instead of dumping a raw LoadError.
  warn "tungsten: the Ruby fallback needs its gems — #{e.message}"
  warn "  install them:  (cd #{File.join(ROOT, "implementations/ruby")} && bundle install)"
  warn "  or build the native compiler (recommended):  bin/tungsten build"
  exit 1
end

COMMANDS_DIR = File.join(ROOT, "bin/commands")

case ARGV[0]
when "compile", "compile-batch"
  if HAVE_COMPILER
    cmd = ARGV.shift
    exec COMPILER, cmd, *ARGV
  else
    ARGV.shift
    load File.join(COMMANDS_DIR, "compile.rb")
  end
when "build"   then ARGV.shift; load File.join(COMMANDS_DIR, "build.rb")
when "fmt"     then ARGV.shift; load File.join(COMMANDS_DIR, "fmt.rb")
when "new"     then ARGV.shift; load File.join(COMMANDS_DIR, "new.rb")
when "start"   then ARGV.shift; load File.join(COMMANDS_DIR, "start.rb")
when "doctor"  then ARGV.shift; load File.join(COMMANDS_DIR, "doctor.rb")
when "ai"      then ARGV.shift; load File.join(COMMANDS_DIR, "ai.rb")
when "symbolicate" then ARGV.shift; load File.join(COMMANDS_DIR, "symbolicate.rb")
when "forge" then ARGV.shift; load File.join(COMMANDS_DIR, "forge.rb")
when "flame", "fire" then ARGV.shift; load File.join(COMMANDS_DIR, "flame.rb")
when "console"
  ARGV.shift
  repl_source = File.join(ROOT, "compiler/lib/repl.w")
  ENV["BUNDLE_GEMFILE"] = File.join(ROOT, "implementations/ruby/Gemfile")
  exec "ruby", File.join(ROOT, "implementations/ruby/exe/ruby-tungsten"), repl_source
else
  load File.join(COMMANDS_DIR, "compile.rb")
end
