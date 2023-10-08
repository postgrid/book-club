const std = @import("std");
const File = std.fs.File;
const Allocator = std.mem.Allocator;

const WriteOpType = enum(u2) { set, del };
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
const ValueProxy = struct {
    file: *File,
    value_metadata: ValueMetadata,

    pub fn readAlloc(self: @This(), allocator: Allocator) ![]u8 {
        const pos = try self.file.getPos();

        try self.file.seekTo(self.value_metadata.offset);

        const buf = try allocator.alloc(u8, self.value_metadata.len);

        // TODO(Apaar): Handle EOF case
        _ = try self.file.readAll(buf);

        try self.file.seekTo(pos);

        return buf;
    }
};

const Store = struct {
    allocator: Allocator,
    segment_file: File,
    key_to_value_metadata: KeyToValueMetadataMap,

    const Self = @This();

    pub fn init(allocator: Allocator, pathname: []const u8) !Self {
        const segment_file = try std.fs.cwd().createFile(
            pathname,
            .{
                .truncate = false,
                .read = true,
            },
        );
        errdefer {
            segment_file.close();
        }

        var key_to_value_metadata = KeyToValueMetadataMap.init(allocator);
        errdefer {
            // TODO(Apaar): Free keys
            key_to_value_metadata.deinit();
        }

        // TODO(Apaar): Initialize the map with the key and value offsets
        var op_type_key_len_buf: [1 + 8]u8 = undefined;

        var temp_key_buf = std.ArrayList(u8).init(allocator);
        defer temp_key_buf.deinit();

        while (true) {
            const count = try segment_file.readAll(&op_type_key_len_buf);
            if (count == 0) {
                break;
            }

            const op_type: WriteOpType = @enumFromInt(op_type_key_len_buf[0]);

            var key_len_buf: [8]u8 align(@alignOf(u64)) = undefined;
            @memcpy(&key_len_buf, op_type_key_len_buf[1..]);

            const key_len: u64 = @bitCast(key_len_buf);

            switch (op_type) {
                .set => {
                    var value_len_buf: [8]u8 align(@alignOf(u64)) = undefined;

                    _ = try segment_file.readAll(&value_len_buf);

                    const value_len: u64 = @bitCast(value_len_buf);

                    // Read in the key
                    try temp_key_buf.resize(key_len);

                    _ = try segment_file.readAll(temp_key_buf.items);

                    const value_metadata = ValueMetadata{
                        // We should be at the value now since we read in the key above
                        .offset = try segment_file.getPos(),
                        .len = value_len,
                    };

                    // Skip over the value
                    _ = try segment_file.seekBy(@intCast(value_len));

                    const entry = try key_to_value_metadata.getOrPutAdapted(
                        @as([]const u8, temp_key_buf.items),
                        key_to_value_metadata.ctx,
                    );

                    if (!entry.found_existing) {
                        // Copy it into our own non-temp buffer under our allocator
                        const key_buf = try allocator.alloc(u8, key_len);
                        @memcpy(key_buf, temp_key_buf.items);

                        entry.key_ptr.* = key_buf;
                    }

                    entry.value_ptr.* = value_metadata;
                },

                .del => {
                    const removed = key_to_value_metadata.fetchRemove(temp_key_buf.items);

                    if (removed) |entry| {
                        // TODO(Apaar): Do not assume we always own the keys
                        allocator.free(entry.key);
                    }
                },
            }
        }

        try segment_file.seekTo(try segment_file.getEndPos());

        return .{
            .allocator = allocator,
            .segment_file = segment_file,
            .key_to_value_metadata = key_to_value_metadata,
        };
    }

    pub fn deinit(self: *Self) void {
        var key_iter = self.key_to_value_metadata.keyIterator();
        while (key_iter.next()) |key| {
            self.allocator.free(key.*);
        }

        self.key_to_value_metadata.deinit();
        self.segment_file.close();
    }

    pub fn get(self: *Self, key: []const u8) ?ValueProxy {
        var value_metadata = self.key_to_value_metadata.get(key) orelse return null;

        return ValueProxy{
            .file = &self.segment_file,
            .value_metadata = value_metadata,
        };
    }

    pub fn setAllocKey(self: *Self, key: []const u8, value: []const u8) !void {
        const op_type_buf = [_]u8{@intFromEnum(WriteOpType.set)};
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

        const pos = try self.segment_file.getPos();

        try self.segment_file.writevAll(&iovecs);

        const value_metadata = ValueMetadata{
            .offset = pos + op_type_buf.len + key_len_buf.len + value_len_buf.len + key.len,
            .len = value.len,
        };

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

        const op_type_buf = [_]u8{@intFromEnum(WriteOpType.del)};
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

        try self.segment_file.writevAll(&iovecs);

        return true;
    }
};

pub fn main() !void {
    var gpa = Gpa{};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var store = try Store.init(allocator, "test.log");
    defer store.deinit();

    try store.setAllocKey("hello", "world");
    try store.setAllocKey("goodbye", "universe");

    const value = store.get("hello");

    if (value) |v| {
        const res = try v.readAlloc(allocator);
        defer allocator.free(res);

        std.debug.print("{s}\n", .{res});
    }
}
