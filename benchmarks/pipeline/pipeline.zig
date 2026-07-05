// Fused map-filter-reduce pipeline benchmark (Zig, hand-written loop).
//
// Like the C and Go baselines: the optimal eager loop an AOT compiler
// produces. The comparison point for Tungsten's fused `/select/sq:sum`,
// which recognizes the same workload as a closed-form ranged sum.
//
// Each rep uses a SHIFTED range (1+r .. N+r) so the REPS loop is not
// loop-invariant (otherwise the optimizer hoists it). N/REPS come from
// argv (defaults 1_000_000 / 100), matching every other language.
//
// Build: zig build-exe -OReleaseFast pipeline.zig && ./pipeline

const std = @import("std");

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();
    const n: u64 = if (args.next()) |a| try std.fmt.parseInt(u64, a, 10) else 1_000_000;
    const reps: u64 = if (args.next()) |a| try std.fmt.parseInt(u64, a, 10) else 100;

    var total: u64 = 0;
    var r: u64 = 0;
    while (r < reps) : (r += 1) {
        const lo: u64 = 1 + r;
        const hi: u64 = n + r;
        var x: u64 = lo;
        while (x <= hi) : (x += 1) {
            if (x % 2 == 0) {
                total +%= x *% x; // wrapping, to match C's unsigned arithmetic
            }
        }
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("{d}\n", .{total});
}
