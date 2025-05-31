const std = @import("std");

pub const Packet = struct {
    const max_len = 1024;

    const Op = enum(u8) {
        request,
        response,
        command,
    };

    const Tag = enum(u8) {
        ping,
        hello,
        find_nodes,
        route,
        echo,
        broadcast,
    };

    op: Op,
    tag: Tag,

    pub fn write(p: Packet, writer: anytype) !void {
        try writer.writeInt(u8, @intFromEnum(p.op), .little);
        try writer.writeInt(u8, @intFromEnum(p.tag), .little);
    }

    pub fn read(reader: anytype) !Packet {
        const op: Packet.Op = @enumFromInt(try reader.readInt(u8, .little));
        const tag: Packet.Tag = @enumFromInt(try reader.readInt(u8, .little));

        const packet = Packet{
            .op = op,
            .tag = tag,
        };
        return packet;
    }
};

pub const PacketHeader = struct {
    pub const size: u32 = @sizeOf(u32) + @sizeOf(u8);

    len: u32,
    flags: u8,

    pub fn write(h: PacketHeader, writer: anytype) !void {
        try writer.writeInt(u32, h.len, .little);
        try writer.writeInt(u8, h.flags, .little);
    }

    pub fn read(reader: anytype) !PacketHeader {
        const len = try reader.readInt(u32, .little);
        const flags = try reader.readInt(u8, .little);

        return .{
            .len = len,
            .flags = flags,
        };
    }
};

pub const EncryptionMetadata = struct {
    pub const size: u32 = @sizeOf([32]u8) + @sizeOf(u32) + @sizeOf(u32);

    dh: [32]u8,
    n: u32,
    pn: u32,

    pub fn write(metadata: EncryptionMetadata, writer: anytype) !void {
        try writer.writeAll(&metadata.dh);
        try writer.writeInt(u32, metadata.n, .little);
        try writer.writeInt(u32, metadata.pn, .little);
    }

    pub fn read(reader: anytype) !EncryptionMetadata {
        const dh = try reader.readBytesNoEof(32);
        const n = try reader.readInt(u32, .little);
        const pn = try reader.readInt(u32, .little);

        return .{
            .dh = dh,
            .n = n,
            .pn = pn,
        };
    }
};
