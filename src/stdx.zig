const std = @import("std");

const Address = std.net.Address;

pub fn parseIpAddress(address: []const u8) !Address {
    const parsed = splitHostPort(address) catch |err| return switch (err) {
        error.DelimiterNotFound => Address.parseIp("127.0.0.1", try std.fmt.parseUnsigned(u16, address, 10)),
        else => err,
    };

    const parsed_host = parsed.host;
    const parsed_port = try std.fmt.parseUnsigned(u16, parsed.port, 10);
    if (parsed_host.len == 0) return Address.parseIp("0.0.0.0", parsed_port);

    return Address.parseIp(parsed_host, parsed_port);
}

const HostPort = struct {
    host: []const u8,
    port: []const u8,
};

fn splitHostPort(address: []const u8) !HostPort {
    var j: usize = 0;
    var k: usize = 0;

    const i = std.mem.lastIndexOfScalar(u8, address, ':') orelse return error.DelimiterNotFound;

    const host = parse: {
        if (address[0] == '[') {
            const end = std.mem.indexOfScalar(u8, address, ']') orelse return error.MissingEndBracket;
            if (end + 1 == i) {} else if (end + 1 == address.len) {
                return error.MissingRightBracket;
            } else {
                return error.MissingPort;
            }

            j = 1;
            k = end + 1;
            break :parse address[1..end];
        }

        if (std.mem.indexOfScalar(u8, address[0..i], ':') != null) {
            return error.TooManyColons;
        }
        break :parse address[0..i];
    };

    if (std.mem.indexOfScalar(u8, address[j..], '[') != null) {
        return error.UnexpectedLeftBracket;
    }
    if (std.mem.indexOfScalar(u8, address[k..], ']') != null) {
        return error.UnexpectedRightBracket;
    }

    const port = address[i + 1 ..];

    return HostPort{ .host = host, .port = port };
}

pub const AddressContext = struct {
    const log = std.log.scoped(.address_context);
    pub fn hash(_: @This(), address: std.net.Address) u64 {
        return hashIpAddress(address);
    }

    pub fn eql(_: @This(), a: std.net.Address, b: std.net.Address) bool {
        if (a.any.family != b.any.family)
            return false;

        return a.eql(b);
    }
};

fn hashIpAddress(address: std.net.Address) u64 {
    var hasher = std.hash.Wyhash.init(0);
    switch (address.any.family) {
        std.posix.AF.INET => {
            hasher.update(std.mem.asBytes(&address.in.sa.addr));
            hasher.update(std.mem.asBytes(&address.in.sa.port));
        },
        std.posix.AF.INET6 => {
            hasher.update(std.mem.asBytes(&address.in6.sa.addr));
            hasher.update(std.mem.asBytes(&address.in6.sa.scope_id));
            hasher.update(std.mem.asBytes(&address.in6.sa.port));
        },
        else => unreachable,
    }
    return hasher.final();
}
