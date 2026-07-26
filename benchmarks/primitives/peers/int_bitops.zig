const std = @import("std");
fn now() f64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts);
    return @as(f64, @floatFromInt(ts.sec)) + @as(f64, @floatFromInt(ts.nsec)) / 1e9;
}
pub fn main() void {
    const n: i64 = 300000000; var s: i64 = 1;
    const t0 = now(); var i: i64 = 0;
    while (i < n) : (i += 1) { s = (s << @as(u6, 13)) ^ (s >> @as(u6, 7)) ^ i; }
    const el = now() - t0;
    var buf: [256]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "{d}\nops: {d}\nelapsed: {d:.6}s\n", .{ s, n, el }) catch return;
    _ = std.c.write(1, out.ptr, out.len);
}
