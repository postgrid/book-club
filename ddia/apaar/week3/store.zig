const std = @import("std");
const File = std.fs.File;
const Allocator = std.mem.Allocator;

const Gpa = std.heap.GeneralPurposeAllocator(.{});

const ValueMetadata = struct {
    // TODO(Apaar): Rename to segment_file_index
    segment_files_index: u16,
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
    store: *Store,
    segment_file_index: u16,
    offset: u64,
    len: u64,

    const Self = @This();

    pub fn readInto(self: *const Self, out_buf: []u8) ![]u8 {
        std.debug.assert(out_buf.len == self.len);

        var file = &self.store.segment_files.items[self.segment_file_index];

        const pos = try file.getPos();

        // Automatically resets the file cursor regardless of whether an error occurred
        defer file.seekTo(pos) catch {};

        try file.seekTo(self.offset);

        const count = try file.readAll(out_buf);
        std.debug.assert(count == out_buf.len);

        return out_buf;
    }

    pub fn readAlloc(self: *const Self, allocator: Allocator) ![]u8 {
        const buf = try allocator.alloc(u8, self.len);
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

pub fn readSegmentOpHeader(file: *File) !?SegmentOpHeader {
    // TODO(Apaar): Initialize the map with the key and value offsets
    var op_type_key_len_buf: [1 + 8]u8 = undefined;

    const count = try file.readAll(&op_type_key_len_buf);

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
            _ = try file.readAll(&value_len_buf);

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

const rand_path_bytes = 12;
const rand_path_len = std.fs.base64_encoder.calcSize(rand_path_bytes);
const RandPath = [rand_path_len]u8;

fn randPath() RandPath {
    var bytes: [rand_path_bytes]u8 = undefined;
    std.crypto.random.bytes(&bytes);

    var path: RandPath = undefined;
    _ = std.fs.base64_encoder.encode(&path, &bytes);

    return path;
}

const Store = struct {
    allocator: Allocator,
    dir_path: []const u8,
    segment_files: std.ArrayList(File),
    max_segment_size: u64,
    key_to_value_metadata: KeyToValueMetadataMap,

    const Self = @This();

    /// The store takes ownership of the given `dir`.
    pub fn init(allocator: Allocator, dir_path: []const u8, max_segment_size: u64) !Self {
        var dir_path_copy = try allocator.alloc(u8, dir_path.len);
        errdefer allocator.free(dir_path_copy);

        @memcpy(dir_path_copy, dir_path);

        var dir = try std.fs.cwd().makeOpenPathIterable(dir_path, .{});
        defer dir.close();

        var self = Self{
            .allocator = allocator,
            .dir_path = dir_path_copy,
            .segment_files = std.ArrayList(File).init(allocator),
            .key_to_value_metadata = KeyToValueMetadataMap.init(allocator),
            .max_segment_size = max_segment_size,
        };

        errdefer self.deinit();

        var dir_iter = dir.iterate();

        // Load up every file in the directory
        while (try dir_iter.next()) |entry| {
            switch (entry.kind) {
                .file => {
                    try self.segment_files.append(
                        // TODO(Apaar): Open every file as read only and then re-open as read-write below
                        try dir.dir.openFile(entry.name, .{ .mode = .read_write }),
                    );
                },
                else => {},
            }
        }

        // Find the smallest segment file that's below the threshold and then work on that; if none is found,
        // create one.
        //
        // The active segment file will always be the last one in the list.

        var min_size = max_segment_size;
        var smallest_segment_file_index: i32 = -1;

        for (self.segment_files.items, 0..) |segment_file, i| {
            const size = try segment_file.getEndPos();

            if (size < min_size) {
                smallest_segment_file_index = @intCast(i);
            }
        }

        if (smallest_segment_file_index < 0) {
            const path = randPath();

            var file = try dir.dir.createFile(&path, .{ .read = true });
            errdefer file.close();

            try self.segment_files.append(file);
        } else if (smallest_segment_file_index != self.segment_files.items.len - 1) {
            // Swap the smallest file to the end of the array
            std.mem.swap(
                File,
                &self.segment_files.items[@intCast(smallest_segment_file_index)],
                &self.segment_files.items[self.segment_files.items.len - 1],
            );
        }

        var temp_key_buf = std.ArrayList(u8).init(allocator);
        defer temp_key_buf.deinit();

        // Go through every segment op in every segment file and fill up our
        // key value metadata.
        for (self.segment_files.items, 0..) |*segment_file, segment_file_index| {
            while (try readSegmentOpHeader(segment_file)) |header| {
                switch (header) {
                    .set => |op| {
                        // Read in the key
                        try temp_key_buf.resize(op.key_len);

                        _ = try segment_file.readAll(temp_key_buf.items);

                        const value_metadata = ValueMetadata{
                            // We should be at the value now since we read in the key above
                            .offset = try segment_file.getPos(),
                            .len = op.value_len,
                            .segment_files_index = @intCast(segment_file_index),
                        };

                        // Skip over the value
                        _ = try segment_file.seekBy(@intCast(op.value_len));

                        const entry = try self.key_to_value_metadata.getOrPutAdapted(
                            @as([]const u8, temp_key_buf.items),
                            self.key_to_value_metadata.ctx,
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
                        // Read in the key
                        try temp_key_buf.resize(op.key_len);

                        _ = try segment_file.readAll(temp_key_buf.items);

                        const removed = self.key_to_value_metadata.fetchRemove(temp_key_buf.items);

                        if (removed) |entry| {
                            // TODO(Apaar): Do not assume we always own the keys
                            self.allocator.free(entry.key);
                        }
                    },
                }
            }
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        var entry_iter = self.key_to_value_metadata.iterator();

        while (entry_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }

        self.key_to_value_metadata.deinit();

        for (self.segment_files.items) |*segment_file| {
            segment_file.close();
        }

        self.segment_files.deinit();

        self.allocator.free(self.dir_path);
    }

    pub fn get(self: *Self, key: []const u8) ?ValueProxy {
        const value_metadata = self.key_to_value_metadata.get(key) orelse return null;

        return .{
            .store = self,
            .segment_file_index = value_metadata.segment_files_index,
            .offset = value_metadata.offset,
            .len = value_metadata.len,
        };
    }

    pub fn setAllocKey(self: *Self, key: []const u8, value: []const u8) !void {
        var file = self.segment_files.items[self.segment_files.items.len - 1];

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

        const pos = try file.getPos();

        try file.writevAll(&iovecs);

        const value_metadata = ValueMetadata{
            .offset = pos + op_type_buf.len + key_len_buf.len + value_len_buf.len + key.len,
            .len = value.len,
            .segment_files_index = @intCast(self.segment_files.items.len - 1),
        };

        const entry = try self.key_to_value_metadata.getOrPutAdapted(key, self.key_to_value_metadata.ctx);

        if (!entry.found_existing) {
            var key_copy = try self.allocator.alloc(u8, key.len);
            @memcpy(key_copy, key);

            entry.key_ptr.* = key_copy;
        }

        entry.value_ptr.* = value_metadata;

        if (value_metadata.offset + value.len > self.max_segment_size) {
            // Append a new segment file because this last one is too big
            const path = randPath();

            var dir = try std.fs.cwd().openDir(self.dir_path, .{});
            defer dir.close();

            var new_file = try dir.createFile(&path, .{ .read = true });
            errdefer new_file.close();

            try self.segment_files.append(new_file);
        }
    }

    pub fn del(self: *Self, key: []const u8) !bool {
        // We do not record a delete operation if the key does not exist because that means a delete
        // operation was already recorded prior.
        const removed = self.key_to_value_metadata.fetchRemove(key) orelse return false;

        // TODO(Apaar): Do not assume we always own the keys
        self.allocator.free(removed.key);

        var file = self.segment_files.items[self.segment_files.items.len - 1];

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

        try file.writevAll(&iovecs);

        return true;
    }

    // TODO(Apaar): Implement compaction. Just pick a random segment that's not the last segment
    // and compact it? Or maybe we should just have each compaction run as eagerly as possible? Try
    // to compact and merge as many segments as possible:
    //
    // - Create a hashtable just for processing our compaction.
    // - Loop through every non-active segment file (i.e. everything except the last segment) and
    // build up this hash table same as our init function for this store. We can avoid allocating and
    // copying new keys if we're willing to lock our `self.key_to_value_metadata` map and look up new keys.
    //
    // The whole point of this is to avoid locking at all during compaction otherwise
    // I'd just loop through our existing hashtable.
    //
    // Let's say we just copy keys. It's a little memory intensive but we might be able to do a thing where
    // if we're about to run out of memory we just dump our hashtable so far.
    //
    // Anyways we build up this hash table and then we can iterate through it, ...
    //
    // Well, regardless of what we do, I don't want to lock our main hash table ever. How can we avoid this?
    // I guess I could use a pointer to refer to the hash table, and then swap out that pointer atomically
    // once we've built up a new hashtable that has compacted data. We'd still need to do an atomic read of that
    // table but that's probably better than locking.
    //
    // I wanna see what the perf of an uncontended lock vs an atomic load is. Maybe it's not worth the complexity
    // because the only time we'd lock is very briefly at the end of the compaction.
    //
    // TO BE CONTINUED

    pub fn compactForMillis(self: *Self, ms: u64) !void {
        var start_time: std.os.timeval = undefined;
        try std.os.gettimeofday(&start_time, null);

        // We don't want to interact with self.segment_files and self.key_to_value_metadata as much as possible,
        // so we open our directory again here rather than accessing either of these.

        _ = ms;
        _ = self;
    }
};

const temp_prefix = "tmp/";
const TempPath = [temp_prefix.len + rand_path_len]u8;

fn tempPath() TempPath {
    var path: TempPath = undefined;
    @memcpy(path[0..temp_prefix.len], temp_prefix);

    var rand_path = randPath();
    @memcpy(path[temp_prefix.len..], &rand_path);

    return path;
}

const test_max_segment_size = 16;

test "set and get" {
    var dir_path = tempPath();

    var store = try Store.init(std.testing.allocator, &dir_path, test_max_segment_size);

    defer store.deinit();

    try store.setAllocKey("hello", "world");

    const proxy = store.get("hello").?;

    var value = try proxy.readAlloc(std.testing.allocator);
    defer std.testing.allocator.free(value);

    try std.testing.expectEqualStrings("world", value);
}

test "set, close, open, and get" {
    var dir_path = tempPath();

    {
        var store = try Store.init(std.testing.allocator, &dir_path, test_max_segment_size);
        defer store.deinit();

        try store.setAllocKey("hello", "world");
    }

    var store = try Store.init(std.testing.allocator, &dir_path, test_max_segment_size);
    defer store.deinit();

    const proxy = store.get("hello").?;

    var value = try proxy.readAlloc(std.testing.allocator);
    defer std.testing.allocator.free(value);

    try std.testing.expectEqualStrings("world", value);
}

test "set, del, and get" {
    var dir_path = tempPath();

    var store = try Store.init(std.testing.allocator, &dir_path, test_max_segment_size);
    defer store.deinit();

    try store.setAllocKey("hello", "world");
    try std.testing.expect(try store.del("hello"));

    const proxy = store.get("hello");
    try std.testing.expectEqual(proxy, null);
}

test "set, del, close, open, and get" {
    var dir_path = tempPath();

    {
        var store = try Store.init(std.testing.allocator, &dir_path, test_max_segment_size);
        defer store.deinit();

        try store.setAllocKey("hello", "world");
        try std.testing.expect(try store.del("hello"));
    }

    var store = try Store.init(std.testing.allocator, &dir_path, test_max_segment_size);
    defer store.deinit();

    const proxy = store.get("hello");
    try std.testing.expectEqual(@as(?ValueProxy, null), proxy);
}
