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
        // TODO(Apaar): Initialize the map with the key and value offsets
        const segment_file = try std.fs.cwd().createFile(
            pathname,
            .{
                .truncate = false,
                .read = true,
            },
        );

        try segment_file.seekTo(try segment_file.getEndPos());

        return .{
            .allocator = allocator,
            .segment_file = segment_file,
            .key_to_value_metadata = KeyToValueMetadataMap.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var key_iter = self.key_to_value_metadata.keyIterator();
        while (key_iter.next()) |key| {
            self.allocator.free(key.*);
        }

        self.key_to_value_metadata.deinit();
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

        const key_copy = try self.allocator.alloc(u8, key.len);
        @memcpy(key_copy, key);

        try self.key_to_value_metadata.put(key_copy, ValueMetadata{
            .offset = pos + op_type_buf.len + key_len_buf.len + value_len_buf.len + key.len,
            .len = value.len,
        });
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

    const value = store.get("hello");

    if (value) |v| {
        const res = try v.readAlloc(allocator);
        defer allocator.free(res);

        std.debug.print("{s}\n", .{res});
    }
}
