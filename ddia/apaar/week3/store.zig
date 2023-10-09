const std = @import("std");
const File = std.fs.File;
const Allocator = std.mem.Allocator;

const Gpa = std.heap.GeneralPurposeAllocator(.{});

const ValueMetadata = struct {
    offset: u64,
    len: u64,
};

const KeyToValueMetadataMap = std.StringHashMap(ValueMetadata);

// Use this to either read and process the value in-place or copy it elsewhere.
// Up to you.
//
// Actually I'm not sure this works because technically the file underneath could
// get swapped out if the background worker/thread compacts/merges segments.
//
// I should acquire a reader lock for that particular segment file and that should
// prevent it from being compacted for that duration. But that sort of defeats
// the scalability of the whole thing because now we can't compact while people
// are reading.
//
// I'd probably want some kinda refcounting for the files where we keep it around while
// there are still ValueProxy's in use for that file. This way, we can update our
// key to segment offset map immediately (sort of, we greatly limit the lock time) when we
// compact/merge.
//
// Let's say that our store gets bombarded with reads; this would still not be a problem because
// we'll swap out the segment map as soon as the compaction is completed and our `get` fn below
// returns. So we'll have only as many references to the original segment file as there were ValueProxies
// that called `get` in parallel; a number which is limited in practice by the number of cores on the machine.
const ValueProxy = struct {
    file: *File,
    value_metadata: ValueMetadata,

    const Self = @This();

    pub fn readInto(self: *const Self, out_buf: []u8) ![]u8 {
        std.debug.assert(out_buf.len == self.value_metadata.len);

        const pos = try self.file.getPos();

        // Automatically resets the file cursor regardless of whether an error occurred
        defer self.file.seekTo(pos);

        try self.file.seekTo(self.value_metadata.offset);

        // TODO(Apaar): Handle EOF case
        _ = try self.file.readAll(out_buf);

        return out_buf;
    }

    pub fn readAlloc(self: *const Self, allocator: Allocator) ![]u8 {
        const buf = try allocator.alloc(u8, self.value_metadata.len);
        return self.readInto(buf);
    }
};

const SegmentOpType = enum(u2) { set, del };

const SegmentOpHeader = union(SegmentOpType) {
    set: struct {
        key_len: u64,
        value_len: u64,
    },
    del: struct {
        key_len: u64,
    },
};

const Segment = struct {
    allocator: Allocator,
    file: File,

    const Self = @This();

    pub fn init(allocator: Allocator, pathname: []const u8) !Self {
        const file = try std.fs.cwd().createFile(pathname, .{
            .truncate = false,
            .read = true,
        });

        return .{ .allocator = allocator, .file = file };
    }

    pub fn deinit(self: *Self) void {
        self.file.close();
    }

    /// If this returns null, then we're at the end of the segment file so far.
    /// The key and value (if applicable) are placed directly after this header.
    pub fn readHeader(self: *Self) !?SegmentOpHeader {
        // TODO(Apaar): Initialize the map with the key and value offsets
        var op_type_key_len_buf: [1 + 8]u8 = undefined;

        const count = try self.file.readAll(&op_type_key_len_buf);

        if (count == 0) {
            return null;
        }

        const op_type: SegmentOpType = @enumFromInt(op_type_key_len_buf[0]);

        var key_len_buf: [8]u8 align(@alignOf(u64)) = undefined;
        @memcpy(&key_len_buf, op_type_key_len_buf[1..]);

        const key_len: u64 = @bitCast(key_len_buf);

        switch (op_type) {
            .set => {
                var value_len_buf: [8]u8 = undefined;
                _ = try self.file.readAll(&value_len_buf);

                const value_len: u64 = @bitCast(value_len_buf);

                return .{
                    .set = .{
                        .key_len = key_len,
                        .value_len = value_len,
                    },
                };
            },

            .del => {
                return .{
                    .del = .{
                        .key_len = key_len,
                    },
                };
            },
        }
    }

    pub fn writeSet(self: *Self, key: []const u8, value: []const u8) !ValueMetadata {
        const op_type_buf = [_]u8{@intFromEnum(SegmentOpType.set)};
        const key_len_buf: [8]u8 = @bitCast(key.len);
        const value_len_buf: [8]u8 = @bitCast(value.len);

        var iovecs = [_]std.os.iovec_const{
            .{
                .iov_base = &op_type_buf,
                .iov_len = op_type_buf.len,
            },
            .{
                .iov_base = &key_len_buf,
                .iov_len = key_len_buf.len,
            },
            .{
                .iov_base = &value_len_buf,
                .iov_len = value_len_buf.len,
            },
            .{
                .iov_base = key.ptr,
                .iov_len = key.len,
            },
            .{
                .iov_base = value.ptr,
                .iov_len = value.len,
            },
        };

        const pos = try self.file.getPos();

        try self.file.writevAll(&iovecs);

        const value_metadata = ValueMetadata{
            .offset = pos + op_type_buf.len + key_len_buf.len + value_len_buf.len + key.len,
            .len = value.len,
        };

        return value_metadata;
    }

    pub fn writeDel(self: *Self, key: []const u8) !void {
        const op_type_buf = [_]u8{@intFromEnum(SegmentOpType.del)};
        const key_len_buf: [8]u8 = @bitCast(key.len);

        var iovecs = [_]std.os.iovec_const{
            .{
                .iov_base = &op_type_buf,
                .iov_len = op_type_buf.len,
            },
            .{
                .iov_base = &key_len_buf,
                .iov_len = key_len_buf.len,
            },
            .{
                .iov_base = key.ptr,
                .iov_len = key.len,
            },
        };

        try self.file.writevAll(&iovecs);
    }
};

const Store = struct {
    allocator: Allocator,
    segment: Segment,
    key_to_value_metadata: KeyToValueMetadataMap,

    const Self = @This();

    pub fn init(allocator: Allocator, pathname: []const u8) !Self {
        var segment = try Segment.init(allocator, pathname);
        errdefer segment.deinit();

        var key_to_value_metadata = KeyToValueMetadataMap.init(allocator);
        errdefer {
            var key_iter = key_to_value_metadata.keyIterator();
            while (key_iter.next()) |key| {
                allocator.free(key.*);
            }

            key_to_value_metadata.deinit();
        }

        var temp_key_buf = std.ArrayList(u8).init(allocator);
        defer temp_key_buf.deinit();

        while (true) {
            const header_opt = try segment.readHeader();
            if (header_opt == null) {
                break;
            }

            const header = header_opt.?;
            switch (header) {
                .set => |op| {
                    // Read in the key
                    try temp_key_buf.resize(op.key_len);

                    _ = try segment.file.readAll(temp_key_buf.items);

                    const value_metadata = ValueMetadata{
                        // We should be at the value now since we read in the key above
                        .offset = try segment.file.getPos(),
                        .len = op.value_len,
                    };

                    // Skip over the value
                    _ = try segment.file.seekBy(@intCast(op.value_len));

                    const entry = try key_to_value_metadata.getOrPutAdapted(
                        @as([]const u8, temp_key_buf.items),
                        key_to_value_metadata.ctx,
                    );

                    if (!entry.found_existing) {
                        // Copy it into our own non-temp buffer under our allocator
                        const key_buf = try allocator.alloc(u8, op.key_len);
                        @memcpy(key_buf, temp_key_buf.items);

                        entry.key_ptr.* = key_buf;
                    }

                    entry.value_ptr.* = value_metadata;
                },

                .del => |op| {
                    // Skip the key
                    try segment.file.seekBy(@intCast(op.key_len));

                    const removed = key_to_value_metadata.fetchRemove(temp_key_buf.items);

                    if (removed) |entry| {
                        // TODO(Apaar): Do not assume we always own the keys
                        allocator.free(entry.key);
                    }
                },
            }
        }

        return .{
            .allocator = allocator,
            .segment = segment,
            .key_to_value_metadata = key_to_value_metadata,
        };
    }

    pub fn deinit(self: *Self) void {
        var key_iter = self.key_to_value_metadata.keyIterator();
        while (key_iter.next()) |key| {
            self.allocator.free(key.*);
        }

        self.key_to_value_metadata.deinit();
        self.segment.deinit();
    }

    pub fn get(self: *Self, key: []const u8) ?ValueProxy {
        var value_metadata = self.key_to_value_metadata.get(key) orelse return null;

        return ValueProxy{
            .file = &self.segment.file,
            .value_metadata = value_metadata,
        };
    }

    pub fn setAllocKey(self: *Self, key: []const u8, value: []const u8) !void {
        const value_metadata = try self.segment.writeSet(key, value);

        // TODO(Apaar): Idk why I can have a .{} here for the ctx but if I try to do the same thing in the `init` function
        // it complains that my context is incomplete.
        //
        // Compiler bug?
        //
        // Nvm it's complaining again???? Oh it was eliminating the dead code of this function.
        const entry = try self.key_to_value_metadata.getOrPutAdapted(key, self.key_to_value_metadata.ctx);

        if (!entry.found_existing) {
            var key_copy = try self.allocator.alloc(u8, key.len);
            @memcpy(key_copy, key);

            entry.key_ptr.* = key_copy;
        }

        entry.value_ptr.* = value_metadata;
    }

    pub fn del(self: *Self, key: []const u8) !bool {
        const removed = self.key_to_value_metadata.fetchRemove(key) orelse return false;

        // TODO(Apaar): Do not assume we always own the keys
        self.allocator.free(removed.key);

        try self.segment.writeDel(key);

        return true;
    }
};

test "set and get" {
    var store = try Store.init(std.testing.allocator, "test.log");
    defer store.deinit();

    try store.setAllocKey("hello", "world");

    const proxy = store.get("hello").?;

    var value = try proxy.readAlloc(std.testing.allocator);
    defer std.testing.allocator.free(value);

    std.debug.assert(std.mem.eql(u8, value, "world"));
}

test "set, close, open, and get" {
    {
        var store = try Store.init(std.testing.allocator, "test.log");
        defer store.deinit();

        try store.setAllocKey("hello", "world");
    }

    var store = try Store.init(std.testing.allocator, "test.log");
    defer store.deinit();

    const proxy = store.get("hello").?;

    var value = try proxy.readAlloc(std.testing.allocator);
    defer std.testing.allocator.free(value);

    std.debug.assert(std.mem.eql(u8, value, "world"));
}

test "set, del, and get" {
    var store = try Store.init(std.testing.allocator, "test.log");
    defer store.deinit();

    try store.setAllocKey("hello", "world");
    std.debug.assert(try store.del("hello"));

    const proxy = store.get("hello");
    std.debug.assert(proxy == null);
}

test "set, del, close, open, and get" {
    {
        var store = try Store.init(std.testing.allocator, "test.log");
        defer store.deinit();

        try store.setAllocKey("hello", "world");
        std.debug.assert(try store.del("hello"));
    }

    var store = try Store.init(std.testing.allocator, "test.log");
    defer store.deinit();

    const proxy = store.get("hello");
    std.debug.assert(proxy == null);
}
