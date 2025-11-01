const std = @import("std");
const api = @import("../api/client.zig");
const ui = @import("../ui/mod.zig");

/// Token usage tracker for monitoring API consumption
pub const TokenTracker = struct {
    allocator: std.mem.Allocator,
    session_usage: std.AutoHashMap(api.ApiProvider, ProviderUsage),
    total_prompt_tokens: u64,
    total_completion_tokens: u64,
    total_tokens: u64,
    session_start: i64,

    const Self = @This();

    /// Usage statistics for a single provider
    pub const ProviderUsage = struct {
        prompt_tokens: u64,
        completion_tokens: u64,
        total_tokens: u64,
        request_count: u32,

        pub fn init() ProviderUsage {
            return .{
                .prompt_tokens = 0,
                .completion_tokens = 0,
                .total_tokens = 0,
                .request_count = 0,
            };
        }

        pub fn add(self: *ProviderUsage, usage: api.Usage) void {
            self.prompt_tokens += usage.prompt_tokens;
            self.completion_tokens += usage.completion_tokens;
            self.total_tokens += usage.total_tokens;
            self.request_count += 1;
        }
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .session_usage = std.AutoHashMap(api.ApiProvider, ProviderUsage).init(allocator),
            .total_prompt_tokens = 0,
            .total_completion_tokens = 0,
            .total_tokens = 0,
            .session_start = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.session_usage.deinit();
    }

    /// Track token usage from an API response
    pub fn track(self: *Self, provider: api.ApiProvider, usage: api.Usage) !void {
        // Update provider-specific usage
        var provider_usage = self.session_usage.get(provider) orelse ProviderUsage.init();
        provider_usage.add(usage);
        try self.session_usage.put(provider, provider_usage);

        // Update total usage
        self.total_prompt_tokens += usage.prompt_tokens;
        self.total_completion_tokens += usage.completion_tokens;
        self.total_tokens += usage.total_tokens;
    }

    /// Get usage for a specific provider
    pub fn getProviderUsage(self: *Self, provider: api.ApiProvider) ?ProviderUsage {
        return self.session_usage.get(provider);
    }

    /// Get session duration in seconds
    pub fn getSessionDuration(self: *const Self) i64 {
        return std.time.timestamp() - self.session_start;
    }

    /// Print usage summary
    pub fn printSummary(self: *Self, allocator: std.mem.Allocator) !void {
        const colors = ui.Colors;

        if (self.total_tokens == 0) {
            ui.printMuted("No token usage recorded this session.\n", .{});
            return;
        }

        // Print header
        ui.printInfo("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
        ui.printHighlight("  Token Usage Summary\n", .{});
        ui.printInfo("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

        // Print total usage
        std.debug.print("{s}Total:{s}\n", .{ colors.accent(), colors.reset() });
        std.debug.print("  {s}Prompt:{s}     {d:>8} tokens\n", .{
            colors.info(), colors.reset(), self.total_prompt_tokens
        });
        std.debug.print("  {s}Completion:{s} {d:>8} tokens\n", .{
            colors.success(), colors.reset(), self.total_completion_tokens
        });
        std.debug.print("  {s}Total:{s}      {d:>8} tokens\n", .{
            colors.highlight(), colors.reset(), self.total_tokens
        });

        // Print provider breakdown
        var provider_iter = self.session_usage.iterator();
        const has_multiple_providers = self.session_usage.count() > 1;

        if (has_multiple_providers) {
            std.debug.print("\n{s}By Provider:{s}\n", .{ colors.accent(), colors.reset() });
        }

        while (provider_iter.next()) |entry| {
            const provider = entry.key_ptr.*;
            const usage = entry.value_ptr.*;

            if (has_multiple_providers) {
                std.debug.print("\n  {s}{s}{s} ({d} requests):\n", .{
                    colors.code(),
                    @tagName(provider),
                    colors.reset(),
                    usage.request_count,
                });
                std.debug.print("    Prompt:     {d:>8} tokens\n", .{usage.prompt_tokens});
                std.debug.print("    Completion: {d:>8} tokens\n", .{usage.completion_tokens});
                std.debug.print("    Total:      {d:>8} tokens\n", .{usage.total_tokens});
            }
        }

        // Print estimated costs (rough estimates)
        const estimated_cost = try self.estimateCost(allocator);
        if (estimated_cost > 0.0) {
            std.debug.print("\n{s}Estimated Cost:{s} ", .{ colors.warning(), colors.reset() });
            std.debug.print("${d:.4}\n", .{estimated_cost});
        }

        // Print session info
        const duration = self.getSessionDuration();
        std.debug.print("\n{s}Session Duration:{s} {d}s\n", .{
            colors.muted(),
            colors.reset(),
            duration,
        });

        ui.printInfo("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    }

    /// Estimate cost based on provider pricing (rough estimates as of 2025)
    fn estimateCost(self: *Self, allocator: std.mem.Allocator) !f64 {
        _ = allocator;
        var total_cost: f64 = 0.0;

        var provider_iter = self.session_usage.iterator();
        while (provider_iter.next()) |entry| {
            const provider = entry.key_ptr.*;
            const usage = entry.value_ptr.*;

            // Rough pricing estimates (per 1M tokens)
            const pricing: struct { input: f64, output: f64 } = switch (provider) {
                .claude => .{ .input = 3.0, .output = 15.0 }, // Claude 3.5 Sonnet
                .openai => .{ .input = 5.0, .output = 15.0 }, // GPT-4
                .github_copilot => .{ .input = 0.0, .output = 0.0 }, // Fixed $10/month
                .google => .{ .input = 1.25, .output = 5.0 }, // Gemini 2.0 Flash
                .xai => .{ .input = 5.0, .output = 15.0 }, // Grok
                .azure => .{ .input = 5.0, .output = 15.0 }, // Azure OpenAI
                .ollama => .{ .input = 0.0, .output = 0.0 }, // Local/free
            };

            const input_cost = (@as(f64, @floatFromInt(usage.prompt_tokens)) / 1_000_000.0) * pricing.input;
            const output_cost = (@as(f64, @floatFromInt(usage.completion_tokens)) / 1_000_000.0) * pricing.output;

            total_cost += input_cost + output_cost;
        }

        return total_cost;
    }

    /// Print compact usage info (for displaying after each response)
    pub fn printCompact(self: *Self, provider: api.ApiProvider, usage_data: api.Usage) void {
        _ = self;
        const colors = ui.Colors;

        std.debug.print("\n{s}[{s}] ", .{ colors.muted(), @tagName(provider) });
        std.debug.print("Tokens: {d} prompt + {d} completion = {d} total{s}\n", .{
            usage_data.prompt_tokens,
            usage_data.completion_tokens,
            usage_data.total_tokens,
            colors.reset(),
        });
    }

    /// Reset session tracking
    pub fn reset(self: *Self) void {
        self.session_usage.clearRetainingCapacity();
        self.total_prompt_tokens = 0;
        self.total_completion_tokens = 0;
        self.total_tokens = 0;
        self.session_start = std.time.timestamp();
    }
};
