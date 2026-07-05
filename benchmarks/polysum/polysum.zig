// Polynomial ranged-sum benchmark — multi-term polynomials (Zig, fixed u64).
//
// IMPORTANT: overflows 2^64 past degree 2 (x^7/x^20 at once) — values are
// mod 2^64 via wrapping ops, so they are WRONG. Native-loop SPEED reference
// only. N/REPS from argv (defaults 1_000_000 / 100).
//
// Targets Zig 0.16: main takes std.process.Init.Minimal (args via
// init.args.iterate()), output via std.posix.write (the std I/O writer
// path needs an explicit Io instance in 0.16). The args/I/O APIs churn
// between Zig versions — this file is 0.16-specific.
//
// Build: zig build-exe -OReleaseFast polysum.zig -femit-bin=polysum

const std = @import("std");

fn ipow(base: u64, e: u32) u64 {
    var r: u64 = 1;
    var i: u32 = 0;
    while (i < e) : (i += 1) r *%= base;
    return r;
}

pub fn main(init: std.process.Init.Minimal) !void {
    var it = init.args.iterate();
    _ = it.next(); // argv[0]
    var n: u64 = 1_000_000;
    var reps: u64 = 100;
    if (it.next()) |a| n = try std.fmt.parseInt(u64, a, 10);
    if (it.next()) |a| reps = try std.fmt.parseInt(u64, a, 10);

    var t1: u64 = 0;
    var t2: u64 = 0;
    var t3: u64 = 0;
    var t7: u64 = 0;
    var t20: u64 = 0;
    var r: u64 = 0;
    while (r < reps) : (r += 1) {
        const lo: u64 = 1 + r;
        const hi: u64 = n + r;
        var x: u64 = lo;
        while (x <= hi) : (x += 1) {
            t1 +%= 2 *% x +% 3;
            t2 +%= 5 *% ipow(x, 2) -% 3 *% x +% 1;
            t3 +%= 4 *% ipow(x, 3) -% 2 *% ipow(x, 2) +% 7 *% x -% 5;
            t7 +%= 92 *% ipow(x, 7) +% 13 *% ipow(x, 3) -% 5 *% x +% 8;
            t20 +%= ipow(x, 20) +% 17 *% ipow(x, 13) -% 4 *% ipow(x, 5) +% 2 *% x +% 9;
        }
    }

    var buf: [256]u8 = undefined;
    const s = try std.fmt.bufPrint(&buf, "{d}\n{d}\n{d}\n{d}\n{d}\n", .{ t1, t2, t3, t7, t20 });
    _ = std.c.write(std.posix.STDOUT_FILENO, s.ptr, s.len);
}
