const std = @import("std");
const zhttp = @import("zhttp");

/// Web Integration Tools - Fetch and search capabilities for grounded AI responses
/// Inspired by Gemini CLI's web grounding and Claude Code's WebFetch
pub const WebTools = struct {
    allocator: std.mem.Allocator,
    http_client: *zhttp.Client,
    cache: WebCache,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        const client = try allocator.create(zhttp.Client);
        client.* = zhttp.Client.init(allocator);

        return .{
            .allocator = allocator,
            .http_client = client,
            .cache = WebCache.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.http_client.deinit();
        self.allocator.destroy(self.http_client);
        self.cache.deinit();
    }

    /// Fetch web content with automatic HTML to Markdown conversion
    pub fn fetch(
        self: *Self,
        url: []const u8,
        options: FetchOptions,
    ) !FetchResult {
        // Check cache first
        if (options.use_cache) {
            if (try self.cache.get(url)) |cached| {
                return FetchResult{
                    .content = try self.allocator.dupe(u8, cached),
                    .url = try self.allocator.dupe(u8, url),
                    .content_type = .html,
                    .from_cache = true,
                };
            }
        }

        // Fetch from web
        var request = try self.http_client.request(.GET, url);
        defer request.deinit();

        // Set headers
        try request.addHeader("User-Agent", "Zeke-AI-CLI/0.3.0");
        if (options.accept_type) |accept| {
            try request.addHeader("Accept", accept);
        }

        // Execute request with timeout
        const response = try request.send();
        defer response.deinit();

        // Handle redirects
        if (response.status >= 300 and response.status < 400) {
            if (response.getHeader("Location")) |location| {
                return try self.fetch(location, options);
            }
        }

        // Check status
        if (response.status != 200) {
            return error.HttpRequestFailed;
        }

        // Read body
        const body = try response.readAll(self.allocator);
        defer self.allocator.free(body);

        // Convert to markdown if HTML
        const content_type = detectContentType(response.getHeader("Content-Type"));
        const content = switch (content_type) {
            .html => try htmlToMarkdown(self.allocator, body),
            .markdown => try self.allocator.dupe(u8, body),
            .json => try formatJson(self.allocator, body),
            .plain_text => try self.allocator.dupe(u8, body),
        };

        // Cache result
        if (options.use_cache) {
            try self.cache.put(url, content);
        }

        return FetchResult{
            .content = content,
            .url = try self.allocator.dupe(u8, url),
            .content_type = content_type,
            .from_cache = false,
        };
    }

    /// Search the web for information
    pub fn search(
        self: *Self,
        query: []const u8,
        options: SearchOptions,
    ) ![]SearchResult {
        // Build search URL (using DuckDuckGo for privacy)
        const search_url = try std.fmt.allocPrint(
            self.allocator,
            "https://html.duckduckgo.com/html/?q={s}",
            .{try urlEncode(self.allocator, query)},
        );
        defer self.allocator.free(search_url);

        // Fetch search results
        const fetch_result = try self.fetch(search_url, .{
            .use_cache = false,
            .accept_type = "text/html",
        });
        defer fetch_result.deinit(self.allocator);

        // Parse search results
        const results = try parseSearchResults(
            self.allocator,
            fetch_result.content,
            options.max_results,
        );

        return results;
    }

    /// Extract main content from webpage (article extraction)
    pub fn extractArticle(
        self: *Self,
        url: []const u8,
    ) !ArticleContent {
        const fetch_result = try self.fetch(url, .{});
        defer fetch_result.deinit(self.allocator);

        return try extractMainContent(self.allocator, fetch_result.content);
    }

    /// Fetch and summarize multiple URLs
    pub fn fetchMultiple(
        self: *Self,
        urls: []const []const u8,
        options: FetchOptions,
    ) ![]FetchResult {
        var results = try self.allocator.alloc(FetchResult, urls.len);
        errdefer {
            for (results) |*r| r.deinit(self.allocator);
            self.allocator.free(results);
        }

        for (urls, 0..) |url, i| {
            results[i] = try self.fetch(url, options);
        }

        return results;
    }
};

/// Web cache with TTL support
pub const WebCache = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap(CacheEntry),
    ttl_seconds: i64 = 900, // 15 minutes default

    pub fn init(allocator: std.mem.Allocator) WebCache {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap(CacheEntry).init(allocator),
        };
    }

    pub fn deinit(self: *WebCache) void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.content);
        }
        self.entries.deinit();
    }

    pub fn get(self: *WebCache, url: []const u8) !?[]const u8 {
        const entry = self.entries.get(url) orelse return null;

        // Check if expired
        const now = std.time.timestamp();
        if (now - entry.timestamp > self.ttl_seconds) {
            _ = self.entries.remove(url);
            self.allocator.free(entry.content);
            return null;
        }

        return entry.content;
    }

    pub fn put(self: *WebCache, url: []const u8, content: []const u8) !void {
        const url_copy = try self.allocator.dupe(u8, url);
        errdefer self.allocator.free(url_copy);

        const content_copy = try self.allocator.dupe(u8, content);
        errdefer self.allocator.free(content_copy);

        try self.entries.put(url_copy, .{
            .content = content_copy,
            .timestamp = std.time.timestamp(),
        });
    }

    const CacheEntry = struct {
        content: []const u8,
        timestamp: i64,
    };
};

// ===== Helper Functions =====

fn detectContentType(header_value: ?[]const u8) ContentType {
    if (header_value == null) return .plain_text;

    const value = header_value.?;
    if (std.mem.indexOf(u8, value, "text/html") != null) return .html;
    if (std.mem.indexOf(u8, value, "text/markdown") != null) return .markdown;
    if (std.mem.indexOf(u8, value, "application/json") != null) return .json;

    return .plain_text;
}

fn htmlToMarkdown(allocator: std.mem.Allocator, html: []const u8) ![]const u8 {
    // Simple HTML to Markdown conversion
    // TODO: Use a proper HTML parser for better conversion

    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var in_tag = false;
    var tag_name = std.ArrayList(u8).init(allocator);
    defer tag_name.deinit();

    for (html) |char| {
        switch (char) {
            '<' => {
                in_tag = true;
                tag_name.clearRetainingCapacity();
            },
            '>' => {
                in_tag = false;
                // Handle common tags
                if (std.mem.eql(u8, tag_name.items, "br") or
                    std.mem.eql(u8, tag_name.items, "/p"))
                {
                    try result.append('\n');
                }
            },
            else => {
                if (in_tag) {
                    try tag_name.append(char);
                } else {
                    try result.append(char);
                }
            },
        }
    }

    return result.toOwnedSlice();
}

fn formatJson(allocator: std.mem.Allocator, json: []const u8) ![]const u8 {
    // TODO: Pretty-print JSON
    return try allocator.dupe(u8, json);
}

fn urlEncode(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    for (input) |char| {
        switch (char) {
            'a'...'z', 'A'...'Z', '0'...'9', '-', '_', '.', '~' => {
                try result.append(char);
            },
            ' ' => {
                try result.append('+');
            },
            else => {
                try result.writer().print("%{X:0>2}", .{char});
            },
        }
    }

    return result.toOwnedSlice();
}

fn parseSearchResults(
    allocator: std.mem.Allocator,
    html: []const u8,
    max_results: usize,
) ![]SearchResult {
    _ = html;

    // TODO: Parse DuckDuckGo HTML results
    // For now, return empty array
    const results = try allocator.alloc(SearchResult, 0);
    _ = max_results;

    return results;
}

fn extractMainContent(
    allocator: std.mem.Allocator,
    content: []const u8,
) !ArticleContent {
    // TODO: Implement article extraction algorithm
    // For now, return basic content
    return ArticleContent{
        .title = try allocator.dupe(u8, "Article"),
        .content = try allocator.dupe(u8, content),
        .author = null,
        .published_date = null,
    };
}

// ===== Types =====

pub const FetchOptions = struct {
    use_cache: bool = true,
    accept_type: ?[]const u8 = null,
    timeout_ms: u32 = 30000,
};

pub const FetchResult = struct {
    content: []const u8,
    url: []const u8,
    content_type: ContentType,
    from_cache: bool,

    pub fn deinit(self: *FetchResult, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
        allocator.free(self.url);
    }
};

pub const ContentType = enum {
    html,
    markdown,
    json,
    plain_text,
};

pub const SearchOptions = struct {
    max_results: usize = 10,
    safe_search: bool = true,
    region: ?[]const u8 = null,
};

pub const SearchResult = struct {
    title: []const u8,
    url: []const u8,
    snippet: []const u8,
    rank: usize,

    pub fn deinit(self: *SearchResult, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.url);
        allocator.free(self.snippet);
    }
};

pub const ArticleContent = struct {
    title: []const u8,
    content: []const u8,
    author: ?[]const u8,
    published_date: ?[]const u8,

    pub fn deinit(self: *ArticleContent, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.content);
        if (self.author) |a| allocator.free(a);
        if (self.published_date) |d| allocator.free(d);
    }
};

test "WebCache - put and get" {
    const allocator = std.testing.allocator;

    var cache = WebCache.init(allocator);
    defer cache.deinit();

    try cache.put("https://example.com", "Test content");

    const content = try cache.get("https://example.com");
    try std.testing.expect(content != null);
    try std.testing.expectEqualStrings("Test content", content.?);
}

test "urlEncode - basic encoding" {
    const allocator = std.testing.allocator;

    const result = try urlEncode(allocator, "hello world");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("hello+world", result);
}
