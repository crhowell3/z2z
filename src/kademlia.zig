const std = @import("std");
const net = std.net;
const meta = std.meta;
const mem = std.mem;
const math = std.math;
const posix = std.posix;
const fmt = std.fmt;
const assert = std.debug.assert;

const AddressContext = @import("stdx.zig").AddressContext;

pub const ID = struct {
    public_key: [32]u8,
    address: net.Address,

    // pub key + type + ip + port
    fn size(self: ID) u32 {
        return @sizeOf([32]u8) + @sizeOf(u8) + @as(u32, switch (self.address.any.family) {
            posix.AF.INET => @sizeOf([4]u8),
            posix.AF.INET6 => @sizeOf([16]u8) + @sizeOf(u32),
            else => unreachable,
        }) + @sizeOf(u16);
    }

    pub fn format(self: ID, comptime layout: []const u8, options: fmt.FormatOptions, writer: anytype) !void {
        _ = layout;
        _ = options;
        try fmt.format(writer, "{}[{}]", .{ self.address, fmt.fmtSliceHexLower(&self.public_key) });
    }

    pub fn write(self: ID, writer: anytype) !void {
        try writer.writeAll(&self.public_key);
        try writer.writeInt(u8, @intCast(self.address.any.family), .little);
        switch (self.address.any.family) {
            posix.AF.INET => {
                try writer.writeInt(u32, self.address.in.sa.addr, .little);
                try writer.writeInt(u16, self.address.in.sa.port, .little);
            },
            posix.AF.INET6 => {
                try writer.writeAll(&self.address.in6.sa.addr);
                try writer.writeInt(u32, self.address.in6.sa.scope_id, .little);
                try writer.writeInt(u32, self.address.in6.sa.flowinfo, .little);
                try writer.writeInt(u16, self.address.in6.sa.port, .little);
            },
            else => unreachable,
        }
    }

    pub fn read(reader: anytype) !ID {
        var id: ID = undefined;
        id.public_key = try reader.readBytesNoEof(32);

        switch (try reader.readInt(u8, .little)) {
            posix.AF.INET => {
                const addr = net.Ip4Address{ .sa = .{
                    .addr = try reader.readInt(u32, .little),
                    .port = try reader.readInt(u16, .little),
                } };

                id.address = .{ .in = addr };
            },
            posix.AF.INET6 => {
                const addr = net.Ip6Address{
                    .sa = .{
                        .addr = try reader.readBytesNoEof(16),
                        .scope_id = try reader.readInt(u32, .little),
                        .flowinfo = try reader.readInt(u32, .little),
                        .port = try reader.readInt(u16, .little),
                    },
                };

                id.address = .{ .in6 = addr };
            },
            else => unreachable,
        }

        return id;
    }

    pub fn eql(self: ID, other: ID) bool {
        if (!std.mem.eql(u8, &self.public_key, &other.public_key))
            return false;

        return self.address.eql(other.address);
    }
};

pub const RoutingTable = struct {
    pub const bucket_size = 16;
    pub const bucket_count = 256;

    pub const Bucket = StaticRingBuffer(ID, u64, bucket_size);

    public_key: [32]u8,
    buckets: [bucket_count]Bucket = [_]Bucket{.{}} ** bucket_count,
    addresses: StaticHashMap(net.Address, ID, AddressContext, bucket_count * bucket_size) = .{},
    len: usize = 0,

    pub fn init(allocator: mem.Allocator) RoutingTable {
        std.RingBuffer.init(allocator, bucket_size);
    }
    pub fn deinit(allocator: mem.Allocator) void {
        _ = allocator; // autofix
    }

    fn clz(public_key: [32]u8) usize {
        comptime var i = 0;
        inline while (i < 32) : (i += 1) {
            if (public_key[i] != 0) {
                return i * 8 + @as(usize, @clz(public_key[i]));
            }
        }
        return 256;
    }

    fn xor(a: [32]u8, b: [32]u8) [32]u8 {
        return @as([32]u8, @as(@Vector(32, u8), a) ^ @as(@Vector(32, u8), b));
    }

    pub const PutResult = enum {
        full,
        updated,
        inserted,
    };

    fn removeFromBucket(bucket: *Bucket, public_key: [32]u8) bool {
        var i: usize = bucket.head;
        var j: usize = bucket.head;
        while (i != bucket.tail) : (i -%= 1) {
            const it = bucket.entries[(i -% 1) & (bucket_size - 1)];
            if (!mem.eql(u8, &it.public_key, &public_key)) {
                bucket.entries[(j -% 1) & (bucket_size - 1)] = it;
                j -%= 1;
            }
        }
        if (i != j) {
            bucket.entries[(j -% 1) & (bucket_size - 1)] = undefined;
            bucket.tail = j;
        }
        return i != j;
    }

    pub fn put(self: *RoutingTable, id: ID) PutResult {
        if (mem.eql(u8, &self.public_key, &id.public_key)) {
            return .full;
        }

        const bucket = &self.buckets[clz(xor(self.public_key, id.public_key))];

        const result = self.addresses.getOrPutAssumeCapacity(id.address);
        const removed = removed: {
            if (result.found_existing) {
                const other_bucket = &self.buckets[clz(xor(self.public_key, result.value_ptr.public_key))];
                break :removed removeFromBucket(other_bucket, result.value_ptr.public_key);
            }
            break :removed removeFromBucket(bucket, id.public_key);
        };
        result.value_ptr.* = id;

        if (!removed and bucket.count() == bucket_size) {
            return .full;
        }

        bucket.push(id);

        if (removed) {
            return .updated;
        }

        self.len += 1;
        return .inserted;
    }

    pub fn delete(self: *RoutingTable, public_key: [32]u8) bool {
        if (self.len == 0 or mem.eql(u8, &self.public_key, &public_key)) {
            return false;
        }

        const bucket = &self.buckets[clz(xor(self.public_key, public_key))];
        if (!removeFromBucket(bucket, public_key)) {
            return false;
        }

        self.len -= 1;
        return true;
    }

    pub fn get(self: *const RoutingTable, public_key: [32]u8) ?ID {
        const bucket_index = clz(xor(self.public_key, public_key));
        const bucket = self.buckets[bucket_index];

        var i: usize = bucket.head;
        while (i != bucket.tail) : (i -%= 1) {
            const it = bucket.entries[(i -% 1) & (bucket_size - 1)];
            if (std.mem.eql(u8, &it.public_key, &public_key))
                return it;
        }

        return null;
    }

    pub fn closestTo(self: *const RoutingTable, dst: []ID, public_key: [32]u8) usize {
        var count: usize = 0;

        const bucket_index = clz(xor(self.public_key, public_key));
        if (!mem.eql(u8, &self.public_key, &public_key)) {
            self.fillSort(dst, &count, public_key, bucket_index);
        }

        var index: usize = 1;
        while (count < dst.len) : (index += 1) {
            var stop = true;
            if (bucket_index >= index) {
                self.fillSort(dst, &count, public_key, bucket_index - index);
                stop = false;
            }
            if (bucket_index + index < self.buckets.len) {
                self.fillSort(dst, &count, public_key, bucket_index + index);
                stop = false;
            }
            if (stop) {
                break;
            }
        }

        return count;
    }

    const BinarySearchResult = union(enum) {
        found: usize,
        not_found: usize,
    };

    fn binarySearch(our_public_key: [32]u8, slice: []ID, public_key: [32]u8) BinarySearchResult {
        var size: usize = slice.len;
        var left: usize = 0;
        var right: usize = slice.len;
        while (left < right) {
            const mid = left + size / 2;
            switch (mem.order(
                u8,
                &xor(slice[mid].public_key, our_public_key),
                &xor(public_key, our_public_key),
            )) {
                .lt => left = mid + 1,
                .gt => right = mid,
                .eq => return .{ .found = mid },
            }
            size = right - left;
        }
        return .{ .not_found = left };
    }

    fn fillSort(self: *const RoutingTable, dst: []ID, count: *usize, public_key: [32]u8, bucket_index: usize) void {
        const bucket = &self.buckets[bucket_index];

        var i: usize = bucket.head;
        while (i != bucket.tail) : (i -%= 1) {
            const it = bucket.entries[(i -% 1) & (bucket_size - 1)];
            if (!mem.eql(u8, &it.public_key, &public_key)) {
                const result = binarySearch(self.public_key, dst[0..count.*], it.public_key);
                assert(result != .found);

                const index = result.not_found;
                if (count.* < dst.len) {
                    count.* += 1;
                } else if (index >= count.*) {
                    continue;
                }
                var j: usize = count.* - 1;
                while (j > index) : (j -= 1) {
                    dst[j] = dst[j - 1];
                }
                dst[index] = it;
            }
        }
    }
};

pub fn StaticHashMap(comptime K: type, comptime V: type, comptime Context: type, comptime capacity: usize) type {
    assert(math.isPowerOfTwo(capacity));

    const shift = 63 - math.log2_int(u64, capacity) + 1;
    const overflow = capacity / 10 + (63 - @as(u64, shift) + 1) << 1;

    return struct {
        const empty_hash = math.maxInt(u64);

        pub const Entry = struct {
            hash: u64 = empty_hash,
            key: K = undefined,
            value: V = undefined,

            pub fn isEmpty(self: Entry) bool {
                return self.hash == empty_hash;
            }

            pub fn format(self: Entry, comptime layout: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
                _ = layout;
                _ = options;
                try std.fmt.format(writer, "(hash: {}, key: {}, value: {})", .{ self.hash, self.key, self.value });
            }
        };

        pub const GetOrPutResult = struct {
            value_ptr: *V,
            found_existing: bool,
        };

        const Self = @This();

        entries: [capacity + overflow]Entry = [_]Entry{.{}} ** (capacity + overflow),
        len: usize = 0,
        shift: u6 = shift,

        put_probe_count: usize = 0,
        get_probe_count: usize = 0,
        del_probe_count: usize = 0,

        pub fn clearRetainingCapacity(self: *Self) void {
            mem.set(Entry, self.slice(), .{});
            self.len = 0;
        }

        pub fn slice(self: *Self) []Self.Entry {
            return self.entries[0..@intCast(capacity + overflow)];
        }

        pub fn putAssumeCapacity(self: *Self, key: K, value: V) void {
            self.putAssumeCapacityContext(key, value, undefined);
        }

        pub fn putAssumeCapacityContext(self: *Self, key: K, value: V, ctx: Context) void {
            const result = self.getOrPutAssumeCapacityContext(key, ctx);
            if (!result.found_existing) result.value_ptr.* = value;
        }

        pub fn getOrPutAssumeCapacity(self: *Self, key: K) Self.GetOrPutResult {
            return self.getOrPutAssumeCapacityContext(key, undefined);
        }

        pub fn getOrPutAssumeCapacityContext(self: *Self, key: K, ctx: Context) Self.GetOrPutResult {
            var it: Self.Entry = .{ .hash = ctx.hash(key), .key = key, .value = undefined };
            var i = it.hash >> self.shift;

            assert(it.hash != Self.empty_hash);

            var inserted_at: ?usize = null;
            while (true) : (i += 1) {
                const entry = self.entries[i];
                if (entry.hash >= it.hash) {
                    if (ctx.eql(entry.key, key)) {
                        return .{ .found_existing = true, .value_ptr = &self.entries[i].value };
                    }
                    self.entries[i] = it;
                    if (entry.isEmpty()) {
                        self.len += 1;
                        return .{ .found_existing = false, .value_ptr = &self.entries[inserted_at orelse i].value };
                    }
                    if (inserted_at == null) {
                        inserted_at = i;
                    }
                    it = entry;
                }
                self.put_probe_count += 1;
            }
        }

        pub fn get(self: *Self, key: K) ?V {
            return self.getContext(key, undefined);
        }

        pub fn getContext(self: *Self, key: K, ctx: Context) ?V {
            const hash = ctx.hash(key);
            assert(hash != Self.empty_hash);

            var i = hash >> self.shift;
            while (true) : (i += 1) {
                const entry = self.entries[i];
                if (entry.hash >= hash) {
                    if (!ctx.eql(entry.key, key)) {
                        return null;
                    }
                    return entry.value;
                }
                self.get_probe_count += 1;
            }
        }

        pub fn delete(self: *Self, key: K) ?V {
            return self.deleteContext(key, undefined);
        }

        pub fn deleteContext(self: *Self, key: K, ctx: Context) ?V {
            const hash = ctx.hash(key);
            assert(hash != Self.empty_hash);

            var i = hash >> self.shift;
            while (true) : (i += 1) {
                const entry = self.entries[i];
                if (entry.hash >= hash) {
                    if (!ctx.eql(entry.key, key)) {
                        return null;
                    }
                    break;
                }
                self.del_probe_count += 1;
            }

            const value = self.entries[i].value;

            while (true) : (i += 1) {
                const j = self.entries[i + 1].hash >> self.shift;
                if (i < j or self.entries[i + 1].isEmpty()) {
                    break;
                }
                self.entries[i] = self.entries[i + 1];
                self.del_probe_count += 1;
            }
            self.entries[i] = .{};
            self.len -= 1;

            return value;
        }
    };
}

fn StaticRingBuffer(comptime T: type, comptime Counter: type, comptime capacity: usize) type {
    assert(math.isPowerOfTwo(capacity));

    return struct {
        const Self = @This();

        head: Counter = 0,
        tail: Counter = 0,
        entries: [capacity]T = undefined,

        /// This routine pushes an item, and optionally returns an evicted item should
        /// the insertion of the provided item overflow the existing buffer.
        pub fn pushOrNull(self: *Self, item: T) ?T {
            const evicted = evicted: {
                if (self.count() == self.entries.len) {
                    break :evicted self.pop();
                }
                break :evicted null;
            };

            self.push(item);

            return evicted;
        }

        pub fn push(self: *Self, item: T) void {
            assert(self.count() < self.entries.len);
            self.entries[self.head & (self.entries.len - 1)] = item;
            self.head +%= 1;
        }

        pub fn pushOne(self: *Self) *T {
            assert(self.count() < self.entries.len);
            const slot = &self.entries[self.head & (self.entries.len - 1)];
            self.head +%= 1;
            return slot;
        }

        pub fn prepend(self: *Self, item: T) void {
            assert(self.count() < self.entries.len);
            self.entries[(self.tail -% 1) & (self.entries.len - 1)] = item;
            self.tail -%= 1;
        }

        /// This routine pops an item from the tail of the buffer and returns it provided
        /// that the buffer is not empty.
        ///
        /// This routine is typically used in order to pop and de-initialize all items
        /// stored in the buffer.
        pub fn popOrNull(self: *Self) ?T {
            if (self.count() == 0) return null;
            return self.pop();
        }

        pub fn pop(self: *Self) T {
            assert(self.count() > 0);
            const evicted = self.entries[self.tail & (self.entries.len - 1)];
            self.tail +%= 1;
            return evicted;
        }

        pub fn get(self: Self, i: Counter) ?T {
            if (i < self.tail or i >= self.head) return null;
            return self.entries[i & (self.entries.len - 1)];
        }

        pub fn count(self: Self) usize {
            return self.head -% self.tail;
        }

        pub fn latest(self: Self) ?T {
            if (self.count() == 0) return null;
            return self.entries[(self.head -% 1) & (self.entries.len - 1)];
        }

        pub fn oldest(self: *Self) ?T {
            if (self.count() == 0) return null;
            return self.entries[self.tail & (self.entries.len - 1)];
        }
    };
}
