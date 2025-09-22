const std = @import("std");

// Test the timestamp usage fix
test "timestamp usage" {
    const timestamp = std.time.timestamp();
    const seed = @as(u64, @intCast(timestamp));
    var prng = std.rand.DefaultPrng.init(seed);
    _ = prng;
}

// Test the HashMap fix
const ApiProvider = enum {
    openai,
    claude,
};

test "hashmap usage" {
    var map = std.AutoHashMap(ApiProvider, u32).init(std.testing.allocator);
    defer map.deinit();
    
    try map.put(.openai, 42);
    try std.testing.expect(map.get(.openai).? == 42);
}