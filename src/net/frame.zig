const std = @import("std");
const Ed25519 = std.crypto.sign.Ed25519;

const coro = @import("coro");

const Session = @import("../end2end.zig").Session;
const ID = @import("../kademlia.zig").ID;
const Client = @import("../main.zig").Client;
const PacketHeader = @import("./packet.zig").PacketHeader;
const EncryptionMetadata = @import("./packet.zig").EncryptionMetadata;

pub const HelloFrame = struct {
    const Self = @This();
    peer_id: ID,
    public_key: [32]u8,
    nonce: [16]u8,

    pub fn read(reader: anytype) !Self {
        const peer_id = try ID.read(reader);
        const key = try reader.readBytesNoEof(32);
        const nonce = try reader.readBytesNoEof(16);
        return .{ .peer_id = peer_id, .public_key = key, .nonce = nonce };
    }

    pub fn write(frame: Self, writer: anytype) !void {
        try frame.peer_id.write(writer);
        try writer.writeAll(&frame.public_key);
        try writer.writeAll(&frame.nonce);
    }
};

pub const FindNodeFrame = struct {
    pub const Request = struct {
        public_key: [32]u8,

        pub fn write(frame: Request, writer: anytype) !void {
            return writer.writeAll(frame.public_key);
        }

        pub fn read(reader: anytype) !Request {
            return .{
                .public_key = try reader.readBytesNoEof(32),
            };
        }
    };

    pub const Response = struct {
        peer_ids: []ID,

        pub fn write(frame: Response, writer: anytype) !void {
            try writer.writeInt(u8, @intCast(frame.peer_ids.len), .little);
            for (frame.peer_ids) |peer_id| {
                try peer_id.write(writer);
            }
        }

        pub fn read(reader: anytype) !Response {
            const len = try reader.readInt(u8, .little);
            var peer_ids: [16]ID = undefined; // TODO: dynamic alloc?

            for (0..len) |i| {
                peer_ids[i] = try ID.read(reader);
            }

            return .{
                .peer_ids = peer_ids[0..len],
            };
        }
    };
};

pub const RouteFrame = struct {
    src: [32]u8,
    dst: [32]u8,
    hops: []ID = &[_]ID{},

    pub fn write(frame: RouteFrame, writer: anytype) !void {
        try writer.writeAll(&frame.src);
        try writer.writeAll(&frame.dst);
        try writer.writeInt(u8, @intCast(frame.hops.len), .little);
        for (frame.hops) |peer_id| {
            try peer_id.write(writer);
        }
    }

    pub fn read(allocator: std.mem.Allocator, reader: anytype) !RouteFrame {
        const src = try reader.readBytesNoEof(32);
        const dst = try reader.readBytesNoEof(32);
        const len = try reader.readInt(u8, .little);
        var hops = try allocator.alloc(ID, len);

        for (0..len) |i| {
            hops[i] = try ID.read(reader);
        }

        return .{
            .src = src,
            .dst = dst,
            .hops = hops,
        };
    }

    pub fn format(self: RouteFrame, comptime layout: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = layout;
        _ = options;
        try std.fmt.format(writer, "RouteFrame[{} => {} ({any})]", .{ std.fmt.fmtSliceHexLower(&self.src), std.fmt.fmtSliceHexLower(&self.dst), self.hops });
    }
};

pub const EchoFrame = struct {
    txt: []u8,

    pub fn write(frame: EchoFrame, writer: anytype) !void {
        try writer.writeInt(u64, frame.txt.len, .little);
        try writer.writeAll(frame.txt);
    }

    pub fn read(allocator: std.mem.Allocator, reader: anytype) !EchoFrame {
        const len = try reader.readInt(u64, .little);
        const txt = try allocator.alloc(u8, len);
        _ = try reader.readAll(txt);
        return EchoFrame{
            .txt = txt,
        };
    }
};

pub const BroadcastFrame = struct {
    src: [32]u8,
    nonce: [16]u8,
    ts: i128, // ts in ns
    n: u8, // amount of hops

    pub fn read(reader: anytype) !BroadcastFrame {
        const src = try reader.readBytesNoEof(32);
        const nonce = try reader.readBytesNoEof(16);
        const ts = try reader.readInt(i128, .little);
        const n = try reader.readInt(u8, .little);

        return .{
            .src = src,
            .nonce = nonce,
            .ts = ts,
            .n = n,
        };
    }

    pub fn write(frame: BroadcastFrame, writer: anytype) !void {
        try writer.writeAll(&frame.src);
        try writer.writeAll(&frame.nonce);
        try writer.writeInt(i128, frame.ts, .little);
        try writer.writeInt(u8, frame.n, .little);
    }
};

pub fn randomNonce() [16]u8 {
    var buff: [16]u8 = undefined;
    std.crypto.random.bytes(&buff);
    return buff;
}

pub fn readFrame(client: *Client, allocator: std.mem.Allocator) anyerror![]u8 {
    var buffer = std.fifo.LinearFifo(u8, .Dynamic).init(allocator);

    defer buffer.deinit();
    var num_bytes: u64 = undefined;

    try coro.io.single(.recv, .{ .socket = client.socket, .buffer = try buffer.writableWithSize(1024), .out_read = &num_bytes });

    if (num_bytes == 0x0) return error.Eof;
    buffer.update(num_bytes);

    const packet_header = try PacketHeader.read(buffer.reader());
    if (buffer.count < packet_header.len) {
        try coro.io.single(.recv, .{ .socket = client.socket, .buffer = try buffer.writableWithSize(packet_header.len), .out_read = &num_bytes });
    }

    const raw_frame = try allocator.alloc(u8, packet_header.len);
    defer allocator.free(raw_frame);

    try buffer.reader().readNoEof(raw_frame);
    const session: ?*Session = if (client.conn.session) |_| client.conn.session.? else null;

    const processed_frame = try processFrame(allocator, client.peer_id.public_key, session, packet_header, raw_frame);
    return processed_frame;
}

pub fn processFrame(allocator: std.mem.Allocator, peer_id_pk: [32]u8, session: ?*Session, packet_header: PacketHeader, raw_frame: []u8) ![]u8 {
    var frame = try allocator.dupe(u8, raw_frame);

    // TODO: extract flags
    if (packet_header.flags & 0x1 != 0x0) {
        var signature: [Ed25519.Signature.encoded_length]u8 = undefined;

        @memcpy(&signature, frame[frame.len - signature.len ..]);
        frame = frame[0 .. frame.len - signature.len];

        verifySignature(peer_id_pk, signature, frame) catch |err| {
            std.log.debug("verifying sig: {} ({})", .{ std.fmt.fmtSliceHexLower(&signature), err });
            return err;
        };
        std.log.debug("verifying sig: {} (ok)", .{std.fmt.fmtSliceHexLower(&signature)});
    }

    if (packet_header.flags & 0x2 != 0x0) {
        var s = session orelse return error.MissingSession;
        var stream = std.io.fixedBufferStream(frame);
        const encryption_metadata = try EncryptionMetadata.read(stream.reader());

        frame = try s.decrypt(.{
            .dh = encryption_metadata.dh,
            .n = encryption_metadata.n,
            .pn = encryption_metadata.pn,
            .cipher_text = stream.buffer[stream.pos..],
        });
    }

    return frame;
}

fn verifySignature(public_key: [32]u8, raw_signature: [64]u8, msg: []u8) !void {
    const pk = try Ed25519.PublicKey.fromBytes(public_key);
    const sig = Ed25519.Signature.fromBytes(raw_signature);

    try sig.verify(msg, pk);
}
