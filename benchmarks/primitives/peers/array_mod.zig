const std = @import("std");
fn now() f64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts);
    return @as(f64, @floatFromInt(ts.sec)) + @as(f64, @floatFromInt(ts.nsec)) / 1e9;
}
// Wraparound (masked-index) array read: `tab[i & 1023]` in a flat loop. The
// volatile n keeps the trip count runtime-unknown. Mirrors array_mod.w.
pub fn main() void {
    var vn: i64 = 1000000000;
    const n: i64 = @as(*volatile i64, &vn).*;
    var chk: i64 = 0;
    var tab: [1024]i64 = undefined;
    var j: i64 = 0; while (j < 1024) : (j += 1) { tab[@intCast(j)] = j *% 2654435761; }
    const t0 = now();
    var i: i64 = 0;
    while (i < n) : (i += 1) { chk ^= tab[@intCast(i & 1023)]; }
    const el = now() - t0;
    var buf: [256]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "{d}\nops: {d}\nelapsed: {d:.6}s\n", .{ chk, n, el }) catch return;
    _ = std.c.write(1, out.ptr, out.len);
}
