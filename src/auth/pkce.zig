const std = @import("std");

/// PKCE (Proof Key for Code Exchange) implementation for OAuth 2.0
/// RFC 7636: https://tools.ietf.org/html/rfc7636
pub const PKCE = struct {
    allocator: std.mem.Allocator,
    code_verifier: []const u8,
    code_challenge: []const u8,

    pub fn init(allocator: std.mem.Allocator) !PKCE {
        // Generate cryptographically secure random verifier (43-128 chars)
        var random_bytes: [32]u8 = undefined;
        std.crypto.random.bytes(&random_bytes);

        const verifier = try base64UrlEncode(allocator, &random_bytes);
        errdefer allocator.free(verifier);

        const challenge = try generateChallenge(allocator, verifier);

        return .{
            .allocator = allocator,
            .code_verifier = verifier,
            .code_challenge = challenge,
        };
    }

    pub fn deinit(self: *PKCE) void {
        self.allocator.free(self.code_verifier);
        self.allocator.free(self.code_challenge);
    }

    /// Generate SHA256 challenge from verifier
    fn generateChallenge(allocator: std.mem.Allocator, verifier: []const u8) ![]const u8 {
        var hash: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(verifier, &hash, .{});
        return try base64UrlEncode(allocator, &hash);
    }

    /// Base64 URL encoding without padding (RFC 4648 §5)
    pub fn base64UrlEncode(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
        const encoder = std.base64.url_safe_no_pad;
        const encoded_len = encoder.Encoder.calcSize(data.len);
        const encoded = try allocator.alloc(u8, encoded_len);
        _ = encoder.Encoder.encode(encoded, data);
        return encoded;
    }
};

// === Tests ===

test "PKCE init and deinit" {
    const allocator = std.testing.allocator;

    var pkce = try PKCE.init(allocator);
    defer pkce.deinit();

    // Verify verifier length (43-128 chars)
    try std.testing.expect(pkce.code_verifier.len >= 43);
    try std.testing.expect(pkce.code_verifier.len <= 128);

    // Verify challenge length (base64 of SHA256 = 43 chars without padding)
    try std.testing.expectEqual(@as(usize, 43), pkce.code_challenge.len);
}

test "PKCE generates unique verifiers" {
    const allocator = std.testing.allocator;

    var pkce1 = try PKCE.init(allocator);
    defer pkce1.deinit();

    var pkce2 = try PKCE.init(allocator);
    defer pkce2.deinit();

    // Verifiers should be different
    try std.testing.expect(!std.mem.eql(u8, pkce1.code_verifier, pkce2.code_verifier));
    try std.testing.expect(!std.mem.eql(u8, pkce1.code_challenge, pkce2.code_challenge));
}

test "PKCE base64 url encoding" {
    const allocator = std.testing.allocator;

    const data = "Hello, World!";
    const encoded = try PKCE.base64UrlEncode(allocator, data);
    defer allocator.free(encoded);

    // Should not contain padding
    try std.testing.expect(std.mem.indexOf(u8, encoded, "=") == null);

    // Should only contain URL-safe characters
    for (encoded) |char| {
        const is_valid = (char >= 'A' and char <= 'Z') or
            (char >= 'a' and char <= 'z') or
            (char >= '0' and char <= '9') or
            char == '-' or char == '_';
        try std.testing.expect(is_valid);
    }
}

test "PKCE challenge deterministic" {
    const allocator = std.testing.allocator;

    const verifier = "test_verifier_12345";

    const challenge1 = try PKCE.generateChallenge(allocator, verifier);
    defer allocator.free(challenge1);

    const challenge2 = try PKCE.generateChallenge(allocator, verifier);
    defer allocator.free(challenge2);

    // Same verifier should produce same challenge
    try std.testing.expectEqualStrings(challenge1, challenge2);
}
