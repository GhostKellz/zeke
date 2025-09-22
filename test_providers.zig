const std = @import("std");
const OpenAIProvider = @import("src/providers/openai.zig").OpenAIProvider;
const ClaudeProvider = @import("src/providers/claude.zig").ClaudeProvider;
const ChatMessage = @import("src/providers/openai.zig").ChatMessage;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("Testing provider implementations...", .{});
    
    // Test environment variable reading
    const openai_key = std.process.getEnvVarOwned(allocator, "OPENAI_API_KEY") catch {
        std.log.warn("OPENAI_API_KEY not set - skipping OpenAI test", .{});
        return;
    };
    defer allocator.free(openai_key);
    
    std.log.info("Found OpenAI API key", .{});
    
    // Test OpenAI provider
    var openai = OpenAIProvider.init(allocator, openai_key);
    defer openai.deinit();
    
    const messages = [_]ChatMessage{
        .{ .role = "user", .content = "Say hello in one word" },
    };
    
    std.log.info("Testing OpenAI chat completion...", .{});
    
    const response = openai.chatCompletion(&messages, "test-conversation") catch |err| {
        std.log.err("OpenAI test failed: {}", .{err});
        return;
    };
    
    std.log.info("OpenAI Response: {s}", .{response.content});
    std.log.info("Model: {s}", .{response.model});
    std.log.info("Tokens: {} prompt, {} completion, {} total", .{
        response.usage.prompt_tokens, 
        response.usage.completion_tokens, 
        response.usage.total_tokens
    });
    
    // Cleanup
    allocator.free(response.content);
    allocator.free(response.model);
    
    std.log.info("Provider test completed successfully!", .{});
}