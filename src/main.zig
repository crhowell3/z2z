const std = @import("std");
const net = std.net;
const posix = std.posix;
const fmt = std.fmt;
const Ed25519 = std.crypto.sign.Ed25519;
const X25519 = std.crypto.dh.X25519;

const aio = @import("aio");
const coro = @import("coro");
const flags = @import("flags");

const e2e = @import("./end2end.zig");
const PacketHeader = @import("./net//packet.zig").PacketHeader;
const EncryptionMetadata = @import("./net//packet.zig").EncryptionMetadata;
const frames = @import("./net/frame.zig");
const Packet = @import("./net/packet.zig").Packet;
const Args = @import("args.zig");
const Kademlia = @import("kademlia.zig");
const ID = Kademlia.ID;
const stdx = @import("stdx.zig");

pub const std_options: std.Options = .{
    .log_level = .debug,
};

var scheduler: coro.Scheduler = undefined;

pub fn main() !void {
    // Define basic logger for outputting messages to the terminal
    const log = std.log.scoped(.main);

    // Create the general purpose memory allocator
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    // Create coro scheduler
    scheduler = try coro.Scheduler.init(allocator, .{});
    defer scheduler.deinit();

    // Create argument allocator
    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    // Parse command line options
    const options = flags.parseOrExit(args, "z2z", Args, .{});
    const listen_addr = try stdx.parseIpAddress(options.listen_addr);

    // Create secure key pair for encrypting communication
    const keys = Ed25519.KeyPair.generate();
    var node: Node = undefined;
    try node.init(allocator, keys, listen_addr);
    try node.bind();

    log.debug("public key: {}", .{fmt.fmtSliceHexLower(&keys.public_key.bytes)});
    log.debug("secret key: {}", .{fmt.fmtSliceHexLower(keys.secret_key.bytes[0..32])});
    log.debug("peer id: {}", .{node.id});

    _ = try scheduler.spawn(Node.runAcceptLoop, .{ &node, allocator }, .{});

    // If interactive is requested, create a thread and a TTY interface
    if (options.interactive) {
        var th = try std.Thread.spawn(.{}, openTTY, .{ &node, allocator });
        th.detach();
    }

    var bootstrap_tasks = std.ArrayList(coro.Task).init(gpa.allocator());
    defer bootstrap_tasks.deinit();

    for (options.positional.trailing) |bootstrap_addr| {
        const addr = stdx.parseIpAddress(bootstrap_addr) catch |err| {
            log.warn("Could not parse bootstrap addr {s}: {}", .{ bootstrap_addr, err });
            continue;
        };

        const client = node.getOrCreateClient(gpa.allocator(), addr) catch |err| {
            log.warn("Could not connect to bootstrap node {}: {}", .{ addr, err });
            continue;
        };
        _ = client;
    }

    try scheduler.run(.wait);
}

fn bootstrapNodeWithPeer(allocator: std.mem.Allocator, node: *Node, client: *Client) !void {
    const log = std.log.scoped(.main);
    log.debug("boostrapping with node {}", .{client.peer_id});

    try client.aquireReader();
    defer client.releaseReader();

    try (Packet{
        .op = .request,
        .tag = .find_nodes,
    }).write(client.writer());

    (frames.FindNodeFrame.Request{
        .public_key = node.id.public_key,
    }).write(client.writer());

    try client.flush(allocator);

    const raw_frame = try Node.readFrame(client, allocator);

    var stream = std.io.fixedBufferStream(raw_frame);
    const packet = try Packet.read(stream.reader());
    if (packet.op != .response) return error.UnexpectedOp;
    if (packet.tag != .find_nodes) return error.UnexpectedTag;

    const frame = try frames.FindNodeFrame.Response.read(stream.reader());

    for (frame.peer_ids) |peer_id| {
        _ = node.getOrCreateClient(allocator, peer_id.address) catch |err| {
            log.warn("could not connect to peer {}: {}", .{ peer_id, err });
            continue;
        };
    }
}

fn openTTY(node: *Node, allocator: std.mem.Allocator) !void {
    const log = std.log.scoped(.main);
    log.info("Opening interactive TTY...", .{});
    defer log.info("Closing interactive TTY...", .{});

    // Create a buffer for text entered into TTY session
    const buffer = try allocator.alloc(u8, 1024);

    // TODO: Use a proper sentinel for controlling this loop
    while (true) {
        // Read command from the TTY until newline is read
        const command = std.io.getStdIn().reader().readUntilDelimiter(buffer, '\n') catch continue;

        if (std.mem.eql(u8, "id", command)) {
            std.debug.print("{}\n", .{node.id});
        } else if (std.mem.eql(u8, "help", command)) {
            std.debug.print("Commands\n", .{});
            std.debug.print("\thelp        Shows this menu\n", .{});
            std.debug.print("\tid          Prints the ID of the current node\n", .{});
            std.debug.print("\techo        Echoes a message to the terminal\n", .{});
            std.debug.print("\troute       Routes a packet to the specified node\n", .{});
            std.debug.print("\tpeers       Lists all nodes that the current node is connected to\n", .{});
            std.debug.print("\tbroadcast   Sends a message to all connected nodes\n", .{});
            std.debug.print("\texit        Terminate the current node and exit program\n", .{});
        } else if (std.mem.startsWith(u8, command, "echo ")) {
            const message = command["echo ".len..];
            std.debug.print("{s}\n", .{message});
        } else if (std.mem.eql(u8, "peers", command)) {
            log.debug("Connected to {} peers", .{node.clients.size});
            var it = node.clients.valueIterator();
            while (it.next()) |client| {
                std.debug.print("Connected to {}\n", .{client.*.peer_id});
            }
        } else if (std.mem.startsWith(u8, command, "route ")) {
            const route_data = command["route ".len..];

            const id_end = std.mem.indexOf(u8, route_data, " ") orelse route_data.len;
            const id = route_data[0..id_end];

            if (id.len != 64) {
                std.debug.print("Error: route data must be 32 bytes long\n", .{});
                continue;
            }

            var dest_key: [32]u8 = undefined;
            _ = std.fmt.hexToBytes(&dest_key, id) catch |err| {
                std.debug.print("Error: route data must be a valid hex string: {}\n", .{err});
                continue;
            };

            const msg = route_data[id_end..];
            const next_hop_id = Routing.nextHop(node, node.id.public_key, dest_key, &[_]ID{}) orelse {
                log.warn("Could not route packet to {}", .{fmt.fmtSliceHexLower(&dest_key)});
                continue;
            };

            const next_hop = try node.getOrCreateClient(allocator, next_hop_id.address);

            try (Packet{
                .op = .command,
                .tag = .route,
            }).write(next_hop.writer());

            try (frames.RouteFrame{
                .src = node.id.public_key,
                .dst = dest_key,
            }).write(next_hop.writer());

            var dest_conn = Connection.init(allocator, .{ .connection = &next_hop.conn }, &node.keys);

            const key_pair = try X25519.KeyPair.fromEd25519(node.keys);
            const remote_public_key = try X25519.publicKeyFromEd25519(try Ed25519.PublicKey.fromBytes(dest_key));
            const shared_key = try X25519.scalarmult(key_pair.secret_key, remote_public_key);
            dest_conn.session = try Routing.getOrCreateSession(allocator, shared_key, .{ .key_pair = key_pair });
            dest_conn.flags = 0x3;

            try (Packet{
                .op = .command,
                .tag = .echo,
            }).write(dest_conn.writer());

            try (frames.EchoFrame{
                .txt = msg,
            }).write(dest_conn.writer());

            try dest_conn.flush(allocator);
            try next_hop.flush(allocator);
            log.info("Routed packet to {}", .{fmt.fmtSliceHexLower(&dest_key)});
        } else if (std.mem.startsWith(u8, command, "broadcast ")) {
            const msg = command["broadcast ".len..];
            var frame = std.ArrayList(u8).init(allocator);

            try (Packet{
                .op = .command,
                .tag = .broadcast,
            }).write(frame.writer());

            try (frames.BroadcastFrame{
                .src = node.id.public_key,
                .nonce = frames.randomNonce(),
                .ts = std.time.nanoTimestamp() + std.time.ns_per_s * 5,
                .n = 0,
            }).write(frame.writer());

            try (Packet{
                .op = .command,
                .tag = .echo,
            }).write(frame.writer());

            try (frames.EchoFrame{
                .txt = msg,
            }).write(frame.writer());

            const c: *Client = undefined;

            try node.handleNodePacket(allocator, c, try frame.toOwnedSlice());
        } else if (std.mem.eql(u8, "exit", command)) {
            log.info("Terminating node...", .{});
            std.process.exit(0);
        }
    }
}

const Node = struct {
    const Self = @This();
    const log = std.log.scoped(.node);

    id: ID,
    socket: std.posix.socket_t,
    address: std.net.Address,
    keys: Ed25519.KeyPair,

    table: Kademlia.RoutingTable,

    clients: std.HashMapUnmanaged(net.Address, *Client, stdx.AddressContext, std.hash_map.default_max_load_percentage),
    client_pool: std.heap.MemoryPool(Client),

    processed_nonces: std.AutoHashMap([16]u8, void),

    fn init(self: *Self, allocator: std.mem.Allocator, keys: Ed25519.KeyPair, address: std.net.Address) !void {
        self.id = .{ .public_key = keys.public_key.toBytes(), .address = address };
        self.keys = keys;
        self.address = address;
        self.clients = .{};
        self.table = .{ .public_key = keys.public_key.toBytes() };
        self.client_pool = std.heap.MemoryPool(Client).init(allocator);
        self.processed_nonces = std.AutoHashMap([16]u8, void).init(allocator);
    }
    fn bind(self: *Self) !void {
        var socket: std.posix.socket_t = undefined;
        try coro.io.single(.socket, .{
            .domain = std.posix.AF.INET,
            .flags = std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC,
            .protocol = std.posix.IPPROTO.TCP,
            .out_socket = &socket,
        });

        try std.posix.setsockopt(socket, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        if (@hasDecl(std.posix.SO, "REUSEPORT")) {
            try std.posix.setsockopt(socket, std.posix.SOL.SOCKET, std.posix.SO.REUSEPORT, &std.mem.toBytes(@as(c_int, 1)));
        }
        try std.posix.bind(socket, &self.address.any, self.address.getOsSockLen());
        try std.posix.listen(socket, 128);
        var sock_address: std.net.Address = undefined;
        var sock_address_len: std.posix.socklen_t = @sizeOf(std.net.Address);
        try std.posix.getsockname(socket, &sock_address.any, &sock_address_len);

        log.info("listening on {}", .{sock_address});

        self.address = sock_address;
        self.id.address = sock_address;
        self.socket = socket;
    }

    fn runAcceptLoop(self: *Self, allocator: std.mem.Allocator) !void {
        while (true) {
            var client_socket: std.posix.socket_t = undefined;
            var client_addr: std.net.Address = undefined;
            var client_addrlen: posix.socklen_t = @sizeOf(std.net.Address);

            try coro.io.single(.accept, .{ .socket = self.socket, .out_socket = &client_socket, .out_addr = &client_addr.any, .inout_addrlen = &client_addrlen });

            const client: *Client = try self.client_pool.create();
            errdefer self.client_pool.destroy(client);

            client.* = Client.init(allocator, client_socket, client_addr, &self.keys) catch |err| {
                coro.io.single(.close_socket, .{ .socket = client_socket }) catch {};
                log.err("failed to initialize client: {}", .{err});
                return err;
            };
            errdefer client.deinit(allocator);
            try self.clients.put(allocator, client_addr, client);

            _ = try scheduler.spawn(Node.runReadLoop, .{ self, allocator, client }, .{});
        }
    }

    fn runReadLoop(self: *Self, allocator: std.mem.Allocator, client: *Client) !void {
        defer self.closeClient(allocator, client);

        while (true) {
            try client.can_read.wait();
            const task = try scheduler.spawn(frames.readFrame, .{ client, allocator }, .{});
            client.read_task = &task;

            const frame = task.complete(.wait) catch |err| {
                log.warn("could not read from {} ({}): {}", .{ client.socket, client.address, err });
                break;
            };

            self.handleNodePacket(allocator, client, frame) catch |err| {
                log.warn("could not handle node packet: {}", .{err});
                continue;
            };
        }
    }

    fn handleNodePacket(self: *Node, allocator: std.mem.Allocator, client: *Client, raw_frame: []u8) !void {
        var stream = std.io.fixedBufferStream(raw_frame);
        const reader = stream.reader();
        const packet = try Packet.read(reader);

        switch (packet.op) {
            .request => {
                switch (packet.tag) {
                    .hello => {
                        const frame = try frames.HelloFrame.read(reader);
                        const signer = try Ed25519.PublicKey.fromBytes(frame.peer_id.public_key);
                        const signature = Ed25519.Signature.fromBytes(try reader.readBytesNoEof(64));

                        // without the signature
                        const msg = raw_frame[0 .. raw_frame.len - Ed25519.Signature.encoded_length];
                        try signature.verify(msg, signer);

                        switch (self.table.put(frame.peer_id)) {
                            .full => log.info("incoming handshake from {} (peer ignored)", .{frame.peer_id}),
                            .updated => log.info("incoming handshake from {} (peer updated)", .{frame.peer_id}),
                            .inserted => log.info("incoming handshake from {} (peer registered)", .{frame.peer_id}),
                        }

                        var signing_writer = SigningWriter(Connection.Writer){
                            .signer = try self.keys.signer(null),
                            .underlying_stream = client.writer(),
                        };

                        const nonce = frames.randomNonce();

                        try (Packet{
                            .op = .response,
                            .tag = .hello,
                        }).write(signing_writer.writer());

                        try (frames.HelloFrame{
                            .peer_id = self.id,
                            .public_key = client.keys.public_key,
                            .nonce = nonce,
                        }).write(signing_writer.writer());

                        try signing_writer.sign();

                        try client.flush(allocator);

                        try client.configurePeer(allocator, frame.peer_id, frame.public_key, frame.nonce ++ nonce, .remoteKey);
                    },
                    .find_nodes => {
                        const public_key = try reader.readBytesNoEof(32);
                        var peer_ids: [16]ID = undefined;
                        const n = self.table.closestTo(&peer_ids, public_key);

                        try (Packet{
                            .op = .response,
                            .tag = .find_nodes,
                        }).write(client.writer());

                        try (frames.FindNodeFrame.Response{
                            .peer_ids = peer_ids[0..n],
                        }).write(client.writer());

                        try client.flush(allocator);
                    },
                    else => return error.UnexpectedTag,
                }
            },
            .command => {
                switch (packet.tag) {
                    .route => {
                        var frame = try frames.RouteFrame.read(allocator, reader);
                        log.debug("received routing frame: {}", .{frame});

                        // well, it's received
                        if (std.mem.eql(u8, &frame.dst, &self.id.public_key)) {
                            const header = try PacketHeader.read(reader);
                            const keypair = try X25519.KeyPair.fromEd25519(self.keys);
                            const remote_public_key = try X25519.publicKeyFromEd25519(try Ed25519.PublicKey.fromBytes(frame.src));
                            const shared_secret = try X25519.scalarmult(keypair.secret_key, remote_public_key);

                            const session = try Routing.getOrCreateSession(allocator, shared_secret, .{ .remote_key = remote_public_key });

                            const original_frame = try frames.processFrame(allocator, frame.src, session, header, stream.buffer[stream.pos..]);
                            log.debug("key count: {}", .{session.state.keys_count});

                            return self.handleNodePacket(allocator, client, original_frame);
                        }

                        const peer_id = Routing.nextHop(self, frame.src, frame.dst, frame.hops) orelse {
                            log.warn("could not forward route", .{});
                            return;
                        };

                        const next_client = try self.getOrCreateClient(allocator, peer_id.address);

                        var hops = std.ArrayList(ID).init(allocator);
                        try hops.appendSlice(frame.hops);
                        try hops.append(self.id);

                        try (Packet{
                            .op = .command,
                            .tag = .route,
                        }).write(next_client.writer());

                        try (frames.RouteFrame{
                            .src = frame.src,
                            .dst = frame.dst,
                            .hops = try hops.toOwnedSlice(),
                        }).write(next_client.writer());
                        try next_client.writer().writeAll(stream.buffer[stream.pos..]);

                        stream.seekTo(stream.buffer.len) catch unreachable;

                        try next_client.flush(allocator);
                    },
                    .echo => {
                        const frame = try frames.EchoFrame.read(allocator, reader);

                        std.debug.print("{s}\n", .{frame.txt});
                    },
                    .broadcast => {
                        const frame = try frames.BroadcastFrame.read(reader);

                        if (frame.n == 5) {
                            log.debug("processing broadcast {} (ignored: n = 5)", .{fmt.fmtSliceHexLower(&frame.nonce)});
                            return;
                        }

                        if (std.time.nanoTimestamp() > frame.ts) {
                            log.debug("processing broadcast {} (ignored: now>ts)", .{fmt.fmtSliceHexLower(&frame.nonce)});
                        }

                        const nonce_entry = try self.processed_nonces.getOrPut(frame.nonce);
                        if (nonce_entry.found_existing) {
                            log.debug("processing broadcast {} (ignored: processed)", .{fmt.fmtSliceHexLower(&frame.nonce)});
                            return;
                        }

                        var it = self.clients.valueIterator(); // TODO: randomize? A map does not guarantee order anyway..?
                        const frame_to_broadcast = stream.buffer[stream.pos..];
                        stream.seekTo(stream.buffer.len) catch unreachable;

                        try self.handleNodePacket(allocator, client, frame_to_broadcast);

                        var count: u32 = 0;
                        while (it.next()) |candidate| {
                            if (count == 5)
                                break;

                            if (std.mem.eql(u8, &candidate.*.peer_id.public_key, &frame.src))
                                continue;

                            try (Packet{
                                .op = .command,
                                .tag = .broadcast,
                            }).write(candidate.*.writer());

                            try (frames.BroadcastFrame{
                                .src = frame.src,
                                .nonce = frame.nonce,
                                .ts = frame.ts,
                                .n = frame.n + 1,
                            }).write(candidate.*.writer());

                            try candidate.*.writer().writeAll(frame_to_broadcast);
                            try candidate.*.flush(allocator);

                            count += 1;
                        }

                        try self.processed_nonces.put(frame.nonce, {});
                        log.debug("processing broadcast {} (ok: {} peers)", .{ fmt.fmtSliceHexLower(&frame.nonce), count });
                    },
                    else => return error.UnexpectedTag,
                }
            },
            else => return error.UnexpectedOp,
        }

        std.debug.assert(stream.pos == stream.buffer.len);
    }

    fn getOrCreateClient(self: *Node, allocator: std.mem.Allocator, address: net.Address) !*Client {
        const result = try self.clients.getOrPut(allocator, address);
        if (!result.found_existing) {
            errdefer std.debug.assert(self.clients.remove(address));
            var socket: std.posix.socket_t = undefined;

            try coro.io.single(.socket, .{
                .domain = std.posix.AF.INET,
                .flags = std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC,
                .protocol = std.posix.IPPROTO.TCP,
                .out_socket = &socket,
            });

            try coro.io.single(.connect, .{
                .socket = socket,
                .addr = &address.any,
                .addrlen = address.getOsSockLen(),
            });

            const client: *Client = try self.client_pool.create();
            errdefer self.client_pool.destroy(client);

            client.* = try Client.init(
                allocator,
                socket,
                address,
                &self.keys,
            );
            result.value_ptr.* = client;

            var signing_writer = SigningWriter(Connection.Writer){
                .signer = try self.keys.signer(null),
                .underlying_stream = result.value_ptr.*.writer(),
            };

            const nonce = frames.randomNonce();

            try (Packet{
                .op = .request,
                .tag = .hello,
            }).write(signing_writer.writer());

            try (frames.HelloFrame{
                .peer_id = self.id,
                .public_key = client.keys.public_key,
                .nonce = nonce,
            }).write(signing_writer.writer());

            try signing_writer.sign();

            try result.value_ptr.*.flush(allocator);

            var response = std.io.fixedBufferStream(try frames.readFrame(client, allocator));
            const packet = try Packet.read(response.reader());
            if (packet.op != .response) {
                return error.UnexpectedOp;
            }

            if (packet.tag != .hello) {
                return error.UnexpectedTag;
            }

            const frame = try frames.HelloFrame.read(response.reader());

            try client.configurePeer(allocator, frame.peer_id, frame.public_key, nonce ++ frame.nonce, .keyPair);
            switch (self.table.put(frame.peer_id)) {
                .full => log.info("handshaked with {} (peer ignored)", .{frame.peer_id}),
                .updated => log.info("handshaked with {} (peer updated)", .{frame.peer_id}),
                .inserted => log.info("handshaked with {} (peer registered)", .{frame.peer_id}),
            }
            _ = try scheduler.spawn(Node.runReadLoop, .{ self, allocator, client }, .{});
        }

        return result.value_ptr.*;
    }

    fn closeClient(self: *Node, allocator: std.mem.Allocator, client: *Client) void {
        log.info("closing client {}", .{client.peer_id});
        coro.io.single(.close_socket, .{ .socket = client.socket }) catch {};

        _ = self.table.delete(client.peer_id.public_key);
        _ = self.clients.remove(client.address);

        client.deinit(allocator);
        self.client_pool.destroy(client);
    }
};

pub const Client = struct {
    const log = std.log.scoped(.client);

    socket: std.posix.socket_t,
    address: std.net.Address,

    conn: Connection,
    peer_id: ID = undefined,
    keys: X25519.KeyPair,

    read_task: *const coro.Task.Generic(anyerror![]u8) = undefined,
    can_read: coro.ResetEvent = .{ .is_set = true },

    fn init(allocator: std.mem.Allocator, socket: std.posix.socket_t, address: std.net.Address, node_keys: *Ed25519.KeyPair) !Client {
        return Client{
            .socket = socket,
            .address = address,

            .conn = Connection.init(allocator, .{ .socket = socket }, node_keys),
            .keys = X25519.KeyPair.generate(),
        };
    }

    fn deinit(self: *Client, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.conn.deinit();
    }

    fn writer(self: *Client) Connection.Writer {
        return self.conn.writer();
    }

    fn flush(self: *Client, allocator: std.mem.Allocator) !void {
        try self.conn.flush(allocator);
    }

    fn aquireReader(self: *Client) !void {
        self.read_task.cancel();
        self.can_read.reset();
    }

    fn releaseReader(self: *Client) void {
        self.can_read.set();
    }

    fn configurePeer(self: *Client, allocator: std.mem.Allocator, peer_id: ID, public_key: [32]u8, nonce: [32]u8, key_type: enum { remoteKey, keyPair }) !void {
        const shared_key = try X25519.scalarmult(self.keys.secret_key, public_key);
        var shared_secret: [32]u8 = undefined;

        var hasher = std.crypto.hash.Blake3.init(.{});
        hasher.update(&shared_key);
        hasher.update(&nonce);
        hasher.final(&shared_secret);

        self.peer_id = peer_id;

        const session = try allocator.create(e2e.Session);
        session.* = switch (key_type) {
            .keyPair => e2e.init(allocator, e2e.randomId(), shared_secret, self.keys),
            .remoteKey => try e2e.initRemoteKey(allocator, e2e.randomId(), shared_secret, public_key),
        };

        self.conn.session = session;

        self.conn.flags |= FLAG_SIGNED;
        self.conn.flags |= FLAG_ENCRYPTED;
    }
};

const Routing = struct {
    const log = std.log.scoped(.routing);
    var sessions: Kademlia.StaticHashMap([32]u8, *e2e.Session, std.hash_map.AutoContext([32]u8), 128) = .{};

    fn nextHop(node: *Node, src: [32]u8, public_key: [32]u8, prev_hops: []const ID) ?ID {
        if (node.table.get(public_key)) |peer_id| {
            return peer_id;
        }

        var peer_ids: [16]ID = undefined;
        const len = node.table.closestTo(&peer_ids, public_key);
        for (0..len) |i| {
            var ok = true;
            for (prev_hops) |prev| {
                if (std.mem.eql(u8, &prev.public_key, &src))
                    continue;

                if (prev.eql(peer_ids[i])) {
                    ok = false;
                    break;
                }
            }
            if (ok) return peer_ids[i];
        }

        return null;
    }

    fn getOrCreateSession(allocator: std.mem.Allocator, key: [32]u8, key_type: union(enum) { key_pair: X25519.KeyPair, remote_key: [32]u8 }) !*e2e.Session {
        const result = Routing.sessions.getOrPutAssumeCapacity(key);
        if (!result.found_existing) {
            const session = try allocator.create(e2e.Session);
            log.debug("creating new session for {}", .{fmt.fmtSliceHexLower(&key)});
            session.* = switch (key_type) {
                .key_pair => |kp| e2e.init(allocator, e2e.randomId(), key, kp),
                .remote_key => |remote_key| try e2e.initRemoteKey(allocator, e2e.randomId(), key, remote_key),
            };

            result.value_ptr.* = session;
        }

        return result.value_ptr.*;
    }
};

// TODO: extract
const FLAG_SIGNED = 0x1;
const FLAG_ENCRYPTED = 0x2;

const Connection = struct {
    const log = std.log.scoped(.connection);

    const Writer = std.ArrayList(u8).Writer;
    const Backend = union(enum) {
        socket: std.posix.socket_t,
        connection: *Connection,
    };

    write_buffer: std.ArrayList(u8),
    backend: Backend,
    flags: u8 = 0x0,
    node_keys: *Ed25519.KeyPair,
    session: ?*e2e.Session = null,

    fn init(allocator: std.mem.Allocator, backend: Backend, node_keys: *Ed25519.KeyPair) Connection {
        return .{
            .write_buffer = std.ArrayList(u8).init(allocator),
            .backend = backend,
            .node_keys = node_keys,
        };
    }

    fn deinit(self: Connection) void {
        self.write_buffer.deinit();
    }

    fn writer(self: *Connection) Writer {
        return self.write_buffer.writer();
    }

    fn flush(self: *Connection, allocator: std.mem.Allocator) !void {
        log.debug("flushing with flags 0x{x:0>2}", .{self.flags});

        var data_to_write = try self.write_buffer.toOwnedSlice();
        const is_signed = self.flags & FLAG_SIGNED != 0x0;
        const is_encrypted = self.flags & FLAG_ENCRYPTED != 0x0;

        var stream = std.io.fixedBufferStream(try allocator.alloc(u8, 1024));
        var encryption_metadata: ?EncryptionMetadata = null;

        var out = stream.writer().any();

        if (is_encrypted) {
            var session = self.session orelse return error.MissingSession;
            const message = try session.encrypt(data_to_write);

            encryption_metadata = EncryptionMetadata{
                .dh = message.dh,
                .n = message.n,
                .pn = message.pn,
            };

            data_to_write = message.cipher_text;
        }

        const packet_len = data_to_write.len +
            (if (is_signed) Ed25519.Signature.encoded_length else 0) +
            (if (is_encrypted) EncryptionMetadata.size else 0);

        try (PacketHeader{
            .flags = self.flags,
            .len = @intCast(packet_len),
        }).write(out);

        if (encryption_metadata) |metadata| {
            try metadata.write(out);
        }

        try out.writeAll(data_to_write);

        if (is_signed) {
            // TODO: should we also sign the header or just the frame?
            // TODO: use signing writer
            const msg = stream.buffer[5..stream.pos];
            const sig = try self.node_keys.sign(msg, null);

            try out.writeAll(&sig.toBytes());
            // try signed_writer.?.sign();
        }

        // total data written = packet header + packet frame
        std.debug.assert(PacketHeader.size + packet_len == stream.getWritten().len);

        switch (self.backend) {
            .socket => |socket| {
                try aio.single(.send, .{ .socket = socket, .buffer = stream.getWritten() });
            },
            .connection => |conn| {
                try conn.writer().writeAll(stream.getWritten());
            },
        }
    }
};

fn SigningWriter(comptime WriterType: type) type {
    const log = std.log.scoped(.signing_writer);
    _ = log;

    return struct {
        const Self = @This();
        pub const Error = WriterType.Error;
        pub const Writer = std.io.Writer(*Self, Error, write);

        underlying_stream: WriterType,
        signer: Ed25519.Signer,

        pub fn write(self: *Self, bytes: []const u8) Error!usize {
            self.signer.update(bytes);

            return self.underlying_stream.write(bytes);
        }

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }

        fn sign(self: *Self) Error!void {
            const signature = self.signer.finalize();

            return self.underlying_stream.writeAll(&signature.toBytes());
        }
    };
}
