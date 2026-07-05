#!/bin/bash
# LexChar benchmark — compare Ruby vs compiled Tungsten lexer
set -e
cd "$(dirname "$0")/../.."

FILE=${1:-compiler/lib/lexer.w}
echo "=== LexChar benchmark: $FILE ==="
echo ""

# Ruby lexer
echo "--- Ruby lexer ---"
cd implementations/ruby
bundle exec ruby ../../benchmarks/lexchar/bench_ruby_lexer.rb "../../$FILE"
cd ../..

# Compiled lexer
echo "--- Compiled lexer ---"
if [ ! -f /tmp/bench_lexchar.wc ]; then
  echo "  compiling..."
  bin/tungsten-compiler compile benchmarks/lexchar/bench_compiled_lexer.w --out /tmp/bench_lexchar.wc
fi
/tmp/bench_lexchar.wc "$FILE" 10
