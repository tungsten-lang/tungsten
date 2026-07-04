// Parallel simdjson benchmark — same shape as our Tungsten parallel
// goroutine sweep. Each thread gets its own ondemand::parser and runs
// `total_jobs / threads` iterations. Wall clock for the parallel section
// is what we report.
//
// Compares single-thread vs N-thread throughput on the same JSON file
// our Tungsten lexer benchmarks use.

#include <simdjson.h>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <thread>
#include <vector>
#include <atomic>

using namespace simdjson;
using namespace std::chrono;

static std::string slurp(const char *path) {
    std::ifstream in(path, std::ios::in | std::ios::binary);
    std::ostringstream buf;
    buf << in.rdbuf();
    return buf.str();
}

static double mb_per_sec(size_t bytes, int jobs, double ms) {
    if (ms <= 0) ms = 1;
    return (double)bytes * jobs * 1000.0 / ms / 1000000.0;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        std::fprintf(stderr, "usage: %s <file.json> [total_jobs] [threads]\n", argv[0]);
        return 1;
    }
    int total_jobs = (argc >= 3) ? std::atoi(argv[2]) : 64;
    int threads    = (argc >= 4) ? std::atoi(argv[3]) : 8;

    std::string source = slurp(argv[1]);
    size_t bytes = source.size();
    padded_string padded(source);

    std::printf("simdjson %s parallel — %s\n", SIMDJSON_VERSION, argv[1]);
    std::printf("  bytes:      %zu\n", bytes);
    std::printf("  jobs:       %d\n", total_jobs);
    std::printf("  threads:    %d\n", threads);
    std::printf("  impl:       %s\n",
                get_active_implementation()->name().c_str());

    // ── Single-thread baseline (parse-only / stage 1) ────────────────────
    {
        ondemand::parser parser;
        auto warm = parser.iterate(padded); (void)warm;

        auto t0 = high_resolution_clock::now();
        for (int r = 0; r < total_jobs; r++) {
            auto d = parser.iterate(padded);
            asm volatile("" : : "r"(&d) : "memory");
        }
        auto t1 = high_resolution_clock::now();
        double ms = duration_cast<microseconds>(t1 - t0).count() / 1000.0;
        std::printf("  Single-thread (stage 1):  %7.0f ms  %7.0f MB/sec\n",
                    ms, mb_per_sec(bytes, total_jobs, ms));
    }

    // ── Parallel (N threads × jobs/threads each, stage 1) ────────────────
    {
        int per_thread = (total_jobs + threads - 1) / threads;
        // Warm up all parsers
        std::vector<std::thread> ts;

        auto t0 = high_resolution_clock::now();
        for (int t = 0; t < threads; t++) {
            ts.emplace_back([&, t]() {
                ondemand::parser parser;
                for (int r = 0; r < per_thread; r++) {
                    auto d = parser.iterate(padded);
                    asm volatile("" : : "r"(&d) : "memory");
                }
            });
        }
        for (auto &th : ts) th.join();
        auto t1 = high_resolution_clock::now();
        double ms = duration_cast<microseconds>(t1 - t0).count() / 1000.0;
        int actual_jobs = per_thread * threads;
        std::printf("  Parallel (stage 1):       %7.0f ms  %7.0f MB/sec\n",
                    ms, mb_per_sec(bytes, actual_jobs, ms));
    }

    return 0;
}
