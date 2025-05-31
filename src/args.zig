//! Configuration struct for "flags" pkg arg parser
const Args = @This();

listen_addr: []const u8 = "127.0.0.1:5884",
interactive: bool = false,
positional: struct {
    trailing: []const []const u8,
},

pub const descriptions = .{
    .listen_addr = "Address to listen for peers on. [default: 127.0.0.1:5884]",
    .interactive = "Open an interactive TTY. [default: false]",
};

pub const switches = .{
    .listen_addr = 'l',
    .interactive = 'i',
};
