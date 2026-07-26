const std = @import("std");
fn now() f64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts);
    return @as(f64, @floatFromInt(ts.sec)) + @as(f64, @floatFromInt(ts.nsec)) / 1e9;
}
pub fn main() void {
    const n: i64 = 20000000; var f: f64 = 0.5;
    const t0 = now(); var i: i64 = 0;
    while (i < n) : (i += 1) { f = 3.9 * f * (1.0 - f); }
    const el = now() - t0;
    var buf: [256]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "{d:.10}\nops: {d}\nelapsed: {d:.6}s\n", .{ f, n, el }) catch return;
    _ = std.c.write(1, out.ptr, out.len);
}
