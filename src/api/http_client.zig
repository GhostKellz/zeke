const std = @import("std");
const zhttp = @import("zhttp");

pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    client: zhttp.Client,
    
    pub fn init(allocator: std.mem.Allocator) HttpClient {
        return HttpClient{
            .allocator = allocator,
            .client = zhttp.Client.init(allocator, .{
                .connect_timeout = 30000,
                .read_timeout = 60000,
                .user_agent = "Zeke/0.2.7",
                .max_redirects = 3,
                .tls = .{
                    .verify_certificates = true,
                    .min_version = .tls_1_2,
                },
            }),
        };
    }
    
    pub fn deinit(self: *HttpClient) void {
        self.client.deinit();
    }
    
    pub fn get(self: *HttpClient, url: []const u8, headers: ?std.StringHashMap([]const u8)) !HttpResponse {
        var request = zhttp.Request.init(self.allocator, .GET, url);
        defer request.deinit();
        
        if (headers) |h| {
            var iter = h.iterator();
            while (iter.next()) |entry| {
                try request.addHeader(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
        
        const response = try self.client.send(request);
        return HttpResponse.fromZhttpResponse(response, self.allocator);
    }
    
    pub fn post(self: *HttpClient, url: []const u8, body: []const u8, headers: ?std.StringHashMap([]const u8)) !HttpResponse {
        var request = zhttp.Request.init(self.allocator, .POST, url);
        defer request.deinit();
        
        request.setBody(zhttp.Body.fromString(body));
        
        if (headers) |h| {
            var iter = h.iterator();
            while (iter.next()) |entry| {
                try request.addHeader(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
        
        // Add Content-Type if not provided
        if (headers == null or !headers.?.contains("Content-Type")) {
            try request.addHeader("Content-Type", "application/json");
        }
        
        const response = try self.client.send(request);
        return HttpResponse.fromZhttpResponse(response, self.allocator);
    }
    
    pub fn postJson(self: *HttpClient, url: []const u8, json_data: []const u8, auth_header: ?[]const u8) !HttpResponse {
        var headers = std.StringHashMap([]const u8).init(self.allocator);
        defer headers.deinit();
        
        try headers.put("Content-Type", "application/json");
        if (auth_header) |auth| {
            try headers.put("Authorization", auth);
        }
        
        return self.post(url, json_data, headers);
    }
    
    pub fn put(self: *HttpClient, url: []const u8, body: []const u8, headers: ?std.StringHashMap([]const u8)) !HttpResponse {
        var request = zhttp.Request.init(self.allocator, .PUT, url);
        defer request.deinit();
        
        request.setBody(zhttp.Body.fromString(body));
        
        if (headers) |h| {
            var iter = h.iterator();
            while (iter.next()) |entry| {
                try request.addHeader(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
        
        const response = try self.client.send(request);
        return HttpResponse.fromZhttpResponse(response, self.allocator);
    }
    
    pub fn delete(self: *HttpClient, url: []const u8, headers: ?std.StringHashMap([]const u8)) !HttpResponse {
        var request = zhttp.Request.init(self.allocator, .DELETE, url);
        defer request.deinit();
        
        if (headers) |h| {
            var iter = h.iterator();
            while (iter.next()) |entry| {
                try request.addHeader(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
        
        const response = try self.client.send(request);
        return HttpResponse.fromZhttpResponse(response, self.allocator);
    }
};

pub const HttpResponse = struct {
    status: u16,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    allocator: std.mem.Allocator,
    
    pub fn fromZhttpResponse(zhttp_response: zhttp.Response, allocator: std.mem.Allocator) !HttpResponse {
        var headers = std.StringHashMap([]const u8).init(allocator);
        
        // Copy headers from zhttp response
        const header_items = zhttp_response.headers.items();
        for (header_items) |header| {
            const key = try allocator.dupe(u8, header.name);
            const value = try allocator.dupe(u8, header.value);
            try headers.put(key, value);
        }
        
        // Get body content
        const body = try zhttp_response.text(10 * 1024 * 1024); // 10MB max
        const owned_body = try allocator.dupe(u8, body);
        
        return HttpResponse{
            .status = zhttp_response.status,
            .headers = headers,
            .body = owned_body,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *HttpResponse) void {
        var iter = self.headers.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
        self.allocator.free(self.body);
    }
    
    pub fn isSuccess(self: HttpResponse) bool {
        return self.status >= 200 and self.status < 300;
    }
    
    pub fn getHeader(self: HttpResponse, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }
    
    pub fn parseJson(self: HttpResponse, comptime T: type) !T {
        return std.json.parseFromSlice(T, self.allocator, self.body, .{});
    }
};

pub const HttpError = error{
    NetworkError,
    InvalidResponse,
    Timeout,
    TooManyRedirects,
    AuthenticationFailed,
    RateLimited,
    ServerError,
    BadRequest,
} || std.mem.Allocator.Error || std.json.ParseError;

pub fn createAuthHeader(allocator: std.mem.Allocator, token: []const u8, auth_type: AuthType) ![]const u8 {
    return switch (auth_type) {
        .Bearer => try std.fmt.allocPrint(allocator, "Bearer {s}", .{token}),
        .ApiKey => try std.fmt.allocPrint(allocator, "Api-Key {s}", .{token}),
        .Basic => try std.fmt.allocPrint(allocator, "Basic {s}", .{token}),
    };
}

pub const AuthType = enum {
    Bearer,
    ApiKey,
    Basic,
};