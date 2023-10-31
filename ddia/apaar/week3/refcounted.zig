const std = @import("std");

pub fn RefCounted(comptime T: type, comptime dropFn: *const fn (*T) void) type {
    return struct {
        const Self = @This();

        value: T,
        count: std.atomic.Atomic(usize) = 1,

        pub inline fn ref(self: *Self) void {
            _ = self.count.fetchAdd(1, .Monotonic);
        }

        pub inline fn unref(self: *Self) void {
            if (self.count.fetchSub(1, .Release) == 0) {
                self.count.fence(.Acquire);
                (dropFn)(self.value);
            }
        }
    };
}
