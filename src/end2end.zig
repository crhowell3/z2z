const std = @import("std");
const crypto = std.crypto;
const X25519 = crypto.dh.X25519;
const KeyPair = X25519.KeyPair;
const HmacSha256 = crypto.auth.hmac.sha2.HmacSha256;
const Aes256 = crypto.core.aes.Aes256;
const AesEncryptCtx = crypto.core.aes.AesEncryptCtx;
const HkdfSha256 = crypto.kdf.hkdf.HkdfSha256;
const ctr = crypto.core.modes.ctr;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const _allocator = gpa.allocator();

pub fn init(allocator: std.mem.Allocator, id: []const u8, shared_key: [32]u8, keys: KeyPair) Session {
    return Session.init(allocator, id, shared_key, keys);
}

pub fn initRemoteKey(allocator: std.mem.Allocator, id: []const u8, shared_key: [32]u8, remote_key: [32]u8) !Session {
    return Session.initRemoteKey(allocator, id, shared_key, remote_key);
}

pub fn randomId() []u8 {
    var id: [16]u8 = undefined;
    crypto.random.bytes(&id);
    return &id;
}
fn kdfRk(rootKey: [32]u8, dhOut: [32]u8) struct {
    root_key: [32]u8,
    chain_key: [32]u8,
    new_header_key: [32]u8,
} {
    const prk = HkdfSha256.extract(&rootKey, &dhOut);
    var out: [96]u8 = undefined;
    HkdfSha256.expand(&out, "rsZUpEuXUqqwXBvSy3EcievAh4cMj6QL", prk);

    return .{
        .root_key = out[0..32].*,
        .chain_key = out[32..64].*,
        .new_header_key = out[64..].*,
    };
}

fn KdfCK(ck: []u8) struct { chain_key: [32]u8, message_key: [32]u8 } {
    var h = HmacSha256.init(ck);

    var chain_key: [32]u8 = undefined;
    h.update(&[_]u8{15});

    h.final(&chain_key);

    var message_key: [32]u8 = undefined;
    h.update(&[_]u8{16});
    h.final(&message_key);
    return .{
        .chain_key = chain_key,
        .message_key = message_key,
    };
}

fn DH(kp: KeyPair, public_key: [32]u8) ![32]u8 {
    return try X25519.scalarmult(kp.secret_key, public_key);
}

fn deriveEncKeys(mk: [32]u8) struct { enc_key: [32]u8, auth_key: [32]u8, iv: [16]u8 } {
    const prk = HkdfSha256.extract(&mk, &mk);
    var out: [80]u8 = undefined;
    HkdfSha256.expand(&out, "pcwSByyx2CRdryCffXJwy7xgVZWtW5Sh", prk);
    return .{
        .enc_key = out[0..32].*,
        .auth_key = out[32..64].*,
        .iv = out[64..].*,
    };
}

fn _encrypt(mk: [32]u8, in: []const u8, ad: []const u8) ![]u8 {
    const keys = deriveEncKeys(mk);

    const out = try _allocator.alloc(u8, in.len + keys.iv.len + 32);

    @memcpy(out[0..16], &keys.iv);

    const ctx = Aes256.initEnc(keys.enc_key);
    ctr(AesEncryptCtx(Aes256), ctx, out[16 .. 16 + in.len], in, keys.iv, .little);

    const sig = computeSignature(keys.auth_key, out[0 .. out.len - 32], ad);

    @memcpy(out[out.len - 32 ..], &sig);
    return out;
}

fn computeSignature(key: [32]u8, cipherText: []const u8, associatedData: []const u8) [HmacSha256.mac_length]u8 {
    var out: [32]u8 = undefined;
    var h = HmacSha256.init(&key);
    h.update(associatedData);
    h.update(cipherText);

    h.final(&out);
    return out;
}

fn _decrypt(mk: [32]u8, in: []const u8, ad: []const u8) ![]u8 {
    const keys = deriveEncKeys(mk);
    const signature = in[in.len - 32 ..];

    const ciphertext = in[16 .. in.len - 32];
    const iv = in[0..16].*;

    const s = computeSignature(keys.auth_key, in[0 .. in.len - 32], ad);
    if (!std.mem.eql(u8, signature, &s)) {
        return error.SignatureMismatch;
    }

    const out = try _allocator.alloc(u8, ciphertext.len);

    const ctx = Aes256.initEnc(keys.enc_key);
    ctr(AesEncryptCtx(Aes256), ctx, out, ciphertext, iv, .little);
    return out;
}

const RootChain = struct {
    chain_key: [32]u8,

    // next performs symmetric ratchet step and returns a new chain and new header key.
    fn next(self: *RootChain, key: [32]u8) struct { chain: Chain, nhk: [32]u8 } {
        const keys = kdfRk(self.chain_key, key);

        self.chain_key = keys.root_key;
        return .{ .chain = Chain{ .chain_key = keys.chain_key, .n = 0 }, .nhk = keys.new_header_key };
    }
};

const Chain = struct {
    chain_key: [32]u8,
    n: u32,

    fn next(self: *Chain) [32]u8 {
        const keys = KdfCK(&self.chain_key);

        self.n += 1;
        self.chain_key = keys.chain_key;

        return keys.message_key;
    }
};

const State = struct {
    const skippedKey = struct {
        key: [32]u8,
        nr: u32,
        mk: [32]u8,
        seq: u32,
    };

    // DH Ratchet public key (the remote key).
    DHr: [32]u8,

    // DH Ratchet key pair (the self ratchet key).
    DHs: KeyPair,

    // Symmetric ratchet root chain.
    root_chain: RootChain,

    // Symmetric ratchet sending and receiving chains.
    send_chain: Chain,
    receive_chain: Chain,

    // Number of messages in previous sending chain.
    pn: u32,

    // Dictionary of skipped-over message keys, indexed by ratchet public key or header key
    // and message number.
    mk_skipped: KeyStorage,

    // The maximum number of message keys that can be skipped in a single chain.
    // WithMaxSkip should be set high enough to tolerate routine lost or delayed messages,
    // but low enough that a malicious sender can't trigger excessive recipient computation.
    max_skip: u32,

    // How long we keep messages keys, counted in number of messages received,
    // for example if MaxKeep is 5 we only keep the last 5 messages keys, deleting everything n - 5.
    max_keep: u32,
    // Max number of message keys per session, older keys will be deleted in FIFO fashion
    max_message_keys_per_session: u32,

    // The number of the current ratchet step.
    step: u32,

    // KeysCount the number of keys generated for decrypting
    keys_count: u32,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, shared_key: [32]u8, kp: KeyPair) State {
        return State{
            .DHs = kp,
            .DHr = shared_key,

            .root_chain = RootChain{ .chain_key = shared_key },
            .send_chain = Chain{ .chain_key = shared_key, .n = 0 },
            .receive_chain = Chain{ .chain_key = shared_key, .n = 0 },

            .pn = 0,
            .mk_skipped = KeyStorage.init(allocator),
            .max_skip = 1000,
            .max_keep = 2000,
            .max_message_keys_per_session = 2000,
            .keys_count = 0,
            .step = 0,
            .allocator = allocator,
        };
    }

    fn skipMessageKeys(self: *State, key: [32]u8, until: u32) ![]skippedKey {
        if (until < self.receive_chain.n) {
            // out of order message
            unreachable;
        }

        if (self.receive_chain.n + self.max_skip < until) {
            // too many messages
            unreachable;
        }

        var skipped_keys = try self.allocator.alloc(skippedKey, until - self.receive_chain.n);

        while (self.receive_chain.n < until) {
            const mk = self.receive_chain.next();

            skipped_keys[until - self.receive_chain.n] = .{ .key = key, .nr = self.receive_chain.n - 1, .mk = mk, .seq = self.keys_count };
            self.keys_count += 1;
        }

        return skipped_keys;
    }

    /// set the next receive and send chain
    fn next(self: *State, dh: [32]u8) !void {
        self.pn = self.send_chain.n;
        self.DHr = dh;
        // TODO: header keys

        const recv_key = try DH(self.DHs, self.DHr);
        self.receive_chain = self.root_chain.next(recv_key).chain;

        self.DHs = KeyPair.generate();

        const send_key = try DH(self.DHs, self.DHr);
        self.send_chain = self.root_chain.next(send_key).chain;
    }
};

const KeyStorage = struct {
    const Self = @This();
    const Entry = struct { session_id: []const u8, message_key: [32]u8, seq_num: u32 };
    const HashMap = std.AutoHashMap([32]u8, std.AutoHashMap(u32, Entry));

    allocator: std.mem.Allocator,
    storage: HashMap,

    fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator, .storage = HashMap.init(allocator) };
    }

    fn get(self: *Self, k: [32]u8, msg_num: u32) ?[32]u8 {
        const msgs = self.storage.get(k) orelse return null;
        const entry = msgs.get(msg_num) orelse return null;
        return entry.message_key;
    }

    fn put(self: *Self, session_id: []const u8, pub_key: [32]u8, msg_num: u32, mk: [32]u8, seq_num: u32) !void {
        const v = try self.storage.getOrPut(pub_key);

        if (!v.found_existing) {
            v.value_ptr.* = std.AutoHashMap(u32, Entry).init(self.allocator);
        }

        try v.value_ptr.put(msg_num, .{
            .session_id = session_id,
            .message_key = mk,
            .seq_num = seq_num,
        });
    }
};

pub const Session = struct {
    const Self = @This();

    id: []const u8,
    state: State,
    allocator: std.mem.Allocator,

    const Header = struct {
        const encoded_len = @sizeOf([32]u8) + @sizeOf(u32) + @sizeOf(u32);
        dh: [32]u8,
        n: u32,
        pn: u32,

        fn encode(self: Header) [Header.encoded_len]u8 {
            var out: [Header.encoded_len]u8 = undefined;
            @memcpy(out[0..32], &self.dh);
            std.mem.writeInt(u32, out[32..36], self.n, .little);
            std.mem.writeInt(u32, out[36..40], self.pn, .little);

            return out;
        }
    };

    fn init(allocator: std.mem.Allocator, id: []const u8, shared_key: [32]u8, keys: KeyPair) Session {
        return Session{ .allocator = allocator, .id = id, .state = State.init(allocator, shared_key, keys) };
    }

    fn initRemoteKey(allocator: std.mem.Allocator, id: []const u8, shared_key: [32]u8, remote_key: [32]u8) !Session {
        const keys = KeyPair.generate();
        var session = Session{ .allocator = allocator, .id = id, .state = State.init(allocator, shared_key, keys) };

        session.state.DHr = remote_key;

        const key = try DH(session.state.DHs, session.state.DHr);
        session.state.send_chain = session.state.root_chain.next(key).chain;

        return session;
    }

    pub fn encrypt(self: *Self, plain_text: []const u8) !struct { dh: [32]u8, n: u32, pn: u32, cipher_text: []u8 } {
        const h = Header{
            .dh = self.state.DHs.public_key,
            .n = self.state.send_chain.n,
            .pn = self.state.pn,
        };

        const message_key = self.state.send_chain.next();

        return .{
            .dh = h.dh,
            .n = h.n,
            .pn = h.pn,
            .cipher_text = try _encrypt(message_key, plain_text, &h.encode()),
        };
    }

    pub fn decrypt(self: *Session, message: struct { dh: [32]u8, n: u32, pn: u32, cipher_text: []const u8 }) ![]u8 {
        const ad = (Header{
            .dh = message.dh,
            .n = message.n,
            .pn = message.pn,
        }).encode();

        // we skipped the key, let's decrypt.
        if (self.state.mk_skipped.get(message.dh, message.n)) |message_key| {
            return try _decrypt(message_key, message.cipher_text, &ad);
        }

        var next_state = self.state;
        var skipped_keys = std.ArrayList(State.skippedKey).init(self.allocator);
        defer skipped_keys.deinit();

        if (!std.mem.eql(u8, &message.dh, &next_state.DHr)) {
            const skipped_message_keys = try next_state.skipMessageKeys(next_state.DHr, message.pn);
            try skipped_keys.appendSlice(skipped_message_keys);

            try next_state.next(message.dh);
        }

        const skipped_message_keys = try next_state.skipMessageKeys(next_state.DHr, message.n);
        try skipped_keys.appendSlice(skipped_message_keys);

        const message_key = next_state.receive_chain.next();
        const plain_text = _decrypt(message_key, message.cipher_text, &ad);

        try skipped_keys.append(.{
            .key = next_state.DHr,
            .nr = message.n,
            .mk = message_key,
            .seq = next_state.keys_count,
        });

        next_state.keys_count += 1;
        for (skipped_keys.items) |skipped| {
            try next_state.mk_skipped.put(self.id, skipped.key, skipped.nr, skipped.mk, skipped.seq);
        }

        self.state = next_state; // TODO: trim keys
        return plain_text;
    }
};
