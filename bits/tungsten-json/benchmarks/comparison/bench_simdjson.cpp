// Apples-to-apples-ish benchmark of simdjson on the same JSON file
// our Tungsten lexer benchmarks use.
//
// simdjson does considerably MORE work than our lexer:
//   - structural identification (stage 1) — closest analog to our lexer
//   - validation (UTF-8, structure, escapes)
//   - on-demand value materialization
//
// We measure two numbers:
//   1. parse-only: parser.iterate(json) which triggers stage 1
//      (structurals identification) plus parser setup but no value access
//   2. full walk: iterate the entire document and touch every value
//
// Both numbers are reported in MB/s of source bytes.

#include <simdjson.h>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <vector>

using namespace simdjson;
using namespace std::chrono;

static std::string slurp(const char *path) {
    std::ifstream in(path, std::ios::in | std::ios::binary);
    std::ostringstream buf;
    buf << in.rdbuf();
    return buf.str();
}

int main(int argc, char **argv) {
    if (argc < 2) {
        std::fprintf(stderr, "usage: %s <file.json> [rounds]\n", argv[0]);
        return 1;
    }
    int rounds = (argc >= 3) ? std::atoi(argv[2]) : 10;
    std::string source = slurp(argv[1]);
    size_t bytes = source.size();
    std::printf("simdjson %s on %s\n", SIMDJSON_VERSION, argv[1]);
    std::printf("  bytes: %zu  rounds: %d\n", bytes, rounds);
    std::printf("  implementation: %s\n",
                get_active_implementation()->name().c_str());
    padded_string padded(source);

    // ── Stage 1 only (closest to our lexer) ───────────────────────────────
    // Use ondemand parser; iterate() triggers stage 1 (structural indexing)
    // and returns a document handle without touching any values.
    {
        ondemand::parser parser;
        // Warm-up
        auto doc = parser.iterate(padded);
        (void)doc;

        auto t0 = high_resolution_clock::now();
        for (int r = 0; r < rounds; r++) {
            auto d = parser.iterate(padded);
            // Force the iterate to actually run by using the result address.
            asm volatile("" : : "r"(&d) : "memory");
        }
        auto t1 = high_resolution_clock::now();
        double ms = duration_cast<microseconds>(t1 - t0).count() / 1000.0;
        double mb_per_sec = (bytes * (double)rounds / (1024.0 * 1024.0)) / (ms / 1000.0);
        std::printf("  parse-only (iterate):   %7.1f ms  %7.1f MB/s\n",
                    ms, mb_per_sec);
    }

    // ── DOM parser stage1+stage2 ──────────────────────────────────────────
    // Older API: dom::parser::parse() runs the full DOM construction.
    {
        dom::parser parser;
        // Warm-up
        auto element = parser.parse(padded);
        (void)element;

        auto t0 = high_resolution_clock::now();
        for (int r = 0; r < rounds; r++) {
            auto e = parser.parse(padded);
            asm volatile("" : : "r"(&e) : "memory");
        }
        auto t1 = high_resolution_clock::now();
        double ms = duration_cast<microseconds>(t1 - t0).count() / 1000.0;
        double mb_per_sec = (bytes * (double)rounds / (1024.0 * 1024.0)) / (ms / 1000.0);
        std::printf("  full DOM parse:         %7.1f ms  %7.1f MB/s\n",
                    ms, mb_per_sec);
    }

    return 0;
}
