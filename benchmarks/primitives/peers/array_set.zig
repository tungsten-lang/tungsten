const std = @import("std");
fn now() f64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts);
    return @as(f64, @floatFromInt(ts.sec)) + @as(f64, @floatFromInt(ts.nsec)) / 1e9;
}
// Sequential element write over a fixed [1024] stack array, nested reps times.
// The loop-carried chk + final read-back keep the stores alive. Mirrors
// array_set.w.
pub fn main() void {
    var vseed: i64 = 976562;
    const reps: i64 = @as(*volatile i64, &vseed).*;
    var tab: [1024]i64 = [_]i64{0} ** 1024;
    const t0 = now();
    var chk: i64 = reps;
    var r: i64 = 0;
    while (r < reps) : (r += 1) { var k: i64 = 0; while (k < 1024) : (k += 1) { tab[@intCast(k)] = chk ^ k; chk +%= 1; } }
    const el = now() - t0;
    const out: i64 = chk ^ tab[0] ^ tab[1023];
    const ops: i64 = reps * 1024;
    var buf: [256]u8 = undefined;
    const outs = std.fmt.bufPrint(&buf, "{d}\nops: {d}\nelapsed: {d:.6}s\n", .{ out, ops, el }) catch return;
    _ = std.c.write(1, outs.ptr, outs.len);
}
