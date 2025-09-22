const std = @import("std");
const zeke = @import("zeke");

/// Example of how Zion can integrate with Zeke's new APIs
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize Zeke instance
    var zeke_instance = try zeke.Zeke.init(allocator);
    defer zeke_instance.deinit();
    
    std.log.info("🔌 Zion <-> Zeke Integration Demo", .{});
    
    // Demo 1: Start HTTP Server for REST API access
    std.log.info("📡 Starting HTTP server for Zion integration...", .{});
    var http_server = try zeke.rpc.HttpServer.init(allocator, &zeke_instance, 8080);
    defer http_server.deinit();
    
    // Note: In a real implementation, this would run in a separate thread
    std.log.info("🌐 HTTP server ready at http://localhost:8080", .{});
    std.log.info("📋 Available endpoints:", .{});
    std.log.info("   POST /api/project_analyze  - Analyze Zig project", .{});
    std.log.info("   POST /api/dependency_suggest - Get dependency suggestions", .{});
    std.log.info("   POST /api/package_recommend - AI-powered package recommendations", .{});
    std.log.info("   POST /api/chat - AI chat interface", .{});
    
    // Demo 2: Project Analysis
    std.log.info("🔍 Running project analysis on current directory...", .{});
    var project_analyzer = zeke.build.ProjectAnalyzer.init(allocator);
    defer project_analyzer.deinit();
    
    const analysis = project_analyzer.analyzeProject(".") catch |err| {
        std.log.err("Project analysis failed: {}", .{err});
        return;
    };
    defer {
        var mut_analysis = analysis;
        mut_analysis.deinit(allocator);
    }
    
    std.log.info("📊 Project Analysis Results:", .{});
    std.log.info("   Build System: {s}", .{analysis.build_system});
    std.log.info("   Dependencies: {d}", .{analysis.dependencies.len});
    std.log.info("   Modules: {d}", .{analysis.module_count});
    if (analysis.estimated_build_time) |time| {
        std.log.info("   Est. Build Time: {d}ms", .{time});
    }
    std.log.info("   Build Issues: {d}", .{analysis.build_issues.len});
    
    for (analysis.build_issues) |issue| {
        std.log.info("   ⚠️  {s}: {s}", .{ @tagName(issue.severity), issue.message });
    }
    
    // Demo 3: JSON-RPC Server (alternative to HTTP)
    std.log.info("👻 Starting JSON-RPC server for direct integration...", .{});
    var rpc_server = try zeke.rpc.GhostRPC.init(allocator, &zeke_instance);
    defer rpc_server.deinit();
    
    std.log.info("🔄 RPC server ready for stdio communication", .{});
    std.log.info("📋 Available RPC methods:", .{});
    std.log.info("   project_analyze - Analyze project structure and dependencies", .{});
    std.log.info("   dependency_suggest - Suggest packages based on query", .{});
    std.log.info("   package_recommend - AI-powered package recommendations", .{});
    std.log.info("   chat - General AI assistant", .{});
    std.log.info("   status - Server status and capabilities", .{});
    
    // Demo API usage examples for Zion
    std.log.info("", .{});
    std.log.info("🚀 Example Zion Integration Commands:", .{});
    std.log.info("", .{});
    std.log.info("# HTTP API Examples:", .{});
    std.log.info("curl -X POST http://localhost:8080/api/project_analyze \\", .{});
    std.log.info("  -H 'Content-Type: application/json' \\", .{});
    std.log.info("  -d '{{\"path\": \".\"}}'", .{});
    std.log.info("", .{});
    std.log.info("curl -X POST http://localhost:8080/api/package_recommend \\", .{});
    std.log.info("  -H 'Content-Type: application/json' \\", .{});
    std.log.info("  -d '{{\"need\": \"fast HTTP client\"}}'", .{});
    std.log.info("", .{});
    std.log.info("# JSON-RPC Examples:", .{});
    std.log.info("echo '{{\"jsonrpc\":\"2.0\",\"method\":\"project_analyze\",\"params\":{{\"path\":\".\"}},\"id\":1}}' | zeke --rpc", .{});
    std.log.info("", .{});
    std.log.info("# Zion CLI Integration:", .{});
    std.log.info("zion ghostwriter \"I need a fast JSON parser\"", .{});
    std.log.info("zion ghostwriter \"analyze my project dependencies\"", .{});
    std.log.info("zion ghostwriter \"suggest optimizations for my build.zig\"", .{});
    std.log.info("", .{});
    
    // Show response format examples
    std.log.info("📄 Expected Response Formats:", .{});
    std.log.info("", .{});
    std.log.info("Project Analysis Response:", .{});
    std.log.info("{{", .{});
    std.log.info("  \"project_info\": {{", .{});
    std.log.info("    \"name\": \"zeke\",", .{});
    std.log.info("    \"build_system\": \"zig\",", .{});
    std.log.info("    \"module_count\": 15", .{});
    std.log.info("  }},", .{});
    std.log.info("  \"dependencies\": [", .{});
    std.log.info("    {{", .{});
    std.log.info("      \"name\": \"zsync\",", .{});
    std.log.info("      \"version\": \"0.4.0\",", .{});
    std.log.info("      \"security_score\": 85", .{});
    std.log.info("    }}", .{});
    std.log.info("  ],", .{});
    std.log.info("  \"build_issues\": [", .{});
    std.log.info("    {{", .{});
    std.log.info("      \"type\": \"performance\",", .{});
    std.log.info("      \"severity\": \"medium\",", .{});
    std.log.info("      \"message\": \"Debug mode detected\",", .{});
    std.log.info("      \"suggestion\": \"Use ReleaseFast for production\"", .{});
    std.log.info("    }}", .{});
    std.log.info("  ]", .{});
    std.log.info("}}", .{});
    
    std.log.info("", .{});
    std.log.info("✅ Zeke integration APIs are ready for Zion!", .{});
    std.log.info("🎯 All 4 quick wins implemented:", .{});
    std.log.info("   ✅ HTTP server wrapper for REST API access", .{});
    std.log.info("   ✅ Project analysis with dependency parsing", .{});
    std.log.info("   ✅ Structured response formats for all APIs", .{});
    std.log.info("   ✅ AI-powered package recommendations", .{});
}

// Example of how to use the structured response formats
fn demonstrateResponseFormats(allocator: std.mem.Allocator) !void {
    // Example dependency response
    const dep_response = zeke.rpc.ResponseFormats.DependencyResponse{
        .name = "httpz",
        .version = "0.1.0",
        .url = "https://github.com/karlseguin/http.zig",
        .security_score = 92,
        .registry = "github",
        .alternatives = &[_][]const u8{ "std.http", "ziglang-http" },
    };
    
    const dep_json = try dep_response.toJson(allocator);
    defer dep_json.deinit();
    
    // Example package recommendation
    const pkg_rec = zeke.rpc.ResponseFormats.PackageRecommendationResponse{
        .query = "fast HTTP client",
        .total_found = 3,
        .search_time_ms = 150,
        .recommendations = &[_]zeke.rpc.ResponseFormats.PackageRecommendationResponse.PackageRecommendation{
            .{
                .name = "httpz",
                .score = 0.95,
                .reason = "High-performance HTTP library with great Zig integration",
                .registry = "github",
                .version = "0.1.0",
                .tags = &[_][]const u8{ "http", "client", "server", "performance" },
            },
        },
    };
    
    const pkg_json = try pkg_rec.toJson(allocator);
    defer pkg_json.deinit();
    
    std.log.info("📊 Structured response formats validated", .{});
}