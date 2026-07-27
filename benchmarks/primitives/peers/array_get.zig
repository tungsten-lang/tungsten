const std = @import("std");
fn now() f64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts);
    return @as(f64, @floatFromInt(ts.sec)) + @as(f64, @floatFromInt(ts.nsec)) / 1e9;
}
// Sequential element read over a fixed [1024] stack array, nested reps times.
// `tab[k]+r` varies each outer pass so the reduction can't be shortcut. Mirrors
// array_get.w.
pub fn main() void {
    var vseed: i64 = 976562;
    const reps: i64 = @as(*volatile i64, &vseed).*;
    var tab: [1024]i64 = undefined;
    var j: i64 = 0; while (j < 1024) : (j += 1) { tab[@intCast(j)] = j *% 2654435761 +% reps; }
    const t0 = now();
    var chk: i64 = reps;
    var r: i64 = 0;
    while (r < reps) : (r += 1) { var k: usize = 0; while (k < 1024) : (k += 1) { chk ^= tab[k] +% r; } }
    const el = now() - t0;
    const ops: i64 = reps * 1024;
    var buf: [256]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "{d}\nops: {d}\nelapsed: {d:.6}s\n", .{ chk, ops, el }) catch return;
    _ = std.c.write(1, out.ptr, out.len);
}
