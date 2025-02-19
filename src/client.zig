const std = @import("std");
const net = std.net;

pub fn main() !void {
    var conn = try net.tcpConnectToAddress(net.Address.initIp4(.{ 127, 0, 0, 1 }, 9999));
    defer conn.close();

    try conn.writer().writeAll("Hello from client!\n");

    var buffer: [128]u8 = undefined;
    const bytes_read = try conn.reader().read(&buffer);
    std.debug.print("Received from peer: {s}\n", .{buffer[0..bytes_read]});
}
