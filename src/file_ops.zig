const std = @import("std");
const zeke = @import("zeke");
const formatting = @import("formatting.zig");

pub fn handleFileRead(allocator: std.mem.Allocator, file_path: []const u8) !void {
    var formatter = formatting.Formatter.init(allocator, .plain);
    
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to open file '{s}': {}", .{ file_path, err });
        defer allocator.free(error_msg);
        
        const formatted_error = try formatter.formatError(error_msg);
        defer allocator.free(formatted_error);
        
        std.debug.print("{s}", .{formatted_error});
        return;
    };
    defer file.close();
    
    const file_size = try file.getEndPos();
    if (file_size > 1024 * 1024) { // 1MB limit
        const error_msg = try std.fmt.allocPrint(allocator, "File '{s}' is too large ({}MB). Maximum size is 1MB", .{ file_path, file_size / (1024 * 1024) });
        defer allocator.free(error_msg);
        
        const formatted_error = try formatter.formatError(error_msg);
        defer allocator.free(formatted_error);
        
        std.debug.print("{s}", .{formatted_error});
        return;
    }
    
    const content = try file.readToEndAlloc(allocator, file_size);
    defer allocator.free(content);
    
    // Detect language from file extension
    const extension = std.fs.path.extension(file_path);
    const language = detectLanguage(extension);
    
    const formatted_content = try formatter.formatCodeBlock(content, language);
    defer allocator.free(formatted_content);
    
    std.debug.print("File: {s}\n", .{file_path});
    std.debug.print("{s}", .{formatted_content});
}

pub fn handleFileWrite(allocator: std.mem.Allocator, file_path: []const u8, content: []const u8) !void {
    var formatter = formatting.Formatter.init(allocator, .plain);
    
    const file = std.fs.cwd().createFile(file_path, .{}) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to create file '{s}': {}", .{ file_path, err });
        defer allocator.free(error_msg);
        
        const formatted_error = try formatter.formatError(error_msg);
        defer allocator.free(formatted_error);
        
        std.debug.print("{s}", .{formatted_error});
        return;
    };
    defer file.close();
    
    file.writeAll(content) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to write to file '{s}': {}", .{ file_path, err });
        defer allocator.free(error_msg);
        
        const formatted_error = try formatter.formatError(error_msg);
        defer allocator.free(formatted_error);
        
        std.debug.print("{s}", .{formatted_error});
        return;
    };
    
    const success_msg = try std.fmt.allocPrint(allocator, "✅ Successfully wrote to file: {s}", .{file_path});
    defer allocator.free(success_msg);
    
    const formatted_success = try formatter.formatResponse(success_msg);
    defer allocator.free(formatted_success);
    
    std.debug.print("{s}", .{formatted_success});
}

pub fn handleFileEdit(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, file_path: []const u8, instruction: []const u8) !void {
    var formatter = formatting.Formatter.init(allocator, .plain);
    
    // Read current file content
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to open file '{s}': {}", .{ file_path, err });
        defer allocator.free(error_msg);
        
        const formatted_error = try formatter.formatError(error_msg);
        defer allocator.free(formatted_error);
        
        std.debug.print("{s}", .{formatted_error});
        return;
    };
    defer file.close();
    
    const file_size = try file.getEndPos();
    const content = try file.readToEndAlloc(allocator, file_size);
    defer allocator.free(content);
    
    // Create edit prompt
    const edit_prompt = try std.fmt.allocPrint(allocator, 
        "Edit this file according to the instruction. Return only the modified file content.\n\nFile: {s}\n\nInstruction: {s}\n\nCurrent content:\n{s}", 
        .{ file_path, instruction, content });
    defer allocator.free(edit_prompt);
    
    // Get AI response
    const response = zeke_instance.chat(edit_prompt) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Edit failed: {}", .{err});
        defer allocator.free(error_msg);
        
        const formatted_error = try formatter.formatError(error_msg);
        defer allocator.free(formatted_error);
        
        std.debug.print("{s}", .{formatted_error});
        return;
    };
    defer allocator.free(response);
    
    // Write back to file
    const backup_path = try std.fmt.allocPrint(allocator, "{s}.backup", .{file_path});
    defer allocator.free(backup_path);
    
    // Create backup
    std.fs.cwd().copyFile(file_path, std.fs.cwd(), backup_path, .{}) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to create backup: {}", .{err});
        defer allocator.free(error_msg);
        
        const formatted_error = try formatter.formatError(error_msg);
        defer allocator.free(formatted_error);
        
        std.debug.print("{s}", .{formatted_error});
        return;
    };
    
    // Write edited content
    const edited_file = std.fs.cwd().createFile(file_path, .{}) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to write edited file: {}", .{err});
        defer allocator.free(error_msg);
        
        const formatted_error = try formatter.formatError(error_msg);
        defer allocator.free(formatted_error);
        
        std.debug.print("{s}", .{formatted_error});
        return;
    };
    defer edited_file.close();
    
    edited_file.writeAll(response) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to write edited content: {}", .{err});
        defer allocator.free(error_msg);
        
        const formatted_error = try formatter.formatError(error_msg);
        defer allocator.free(formatted_error);
        
        std.debug.print("{s}", .{formatted_error});
        return;
    };
    
    const success_msg = try std.fmt.allocPrint(allocator, "✅ Successfully edited file: {s}\n📄 Backup created: {s}", .{ file_path, backup_path });
    defer allocator.free(success_msg);
    
    const formatted_success = try formatter.formatResponse(success_msg);
    defer allocator.free(formatted_success);
    
    std.debug.print("{s}", .{formatted_success});
}

pub fn handleFileGenerate(zeke_instance: *zeke.Zeke, allocator: std.mem.Allocator, file_path: []const u8, description: []const u8) !void {
    var formatter = formatting.Formatter.init(allocator, .plain);
    
    // Detect language from file extension
    const extension = std.fs.path.extension(file_path);
    const language = detectLanguage(extension);
    
    const generate_prompt = try std.fmt.allocPrint(allocator, 
        "Generate a {s} file based on this description. Return only the file content, no explanations.\n\nFile: {s}\nLanguage: {s}\nDescription: {s}", 
        .{ language orelse "text", file_path, language orelse "text", description });
    defer allocator.free(generate_prompt);
    
    const response = zeke_instance.chat(generate_prompt) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Generation failed: {}", .{err});
        defer allocator.free(error_msg);
        
        const formatted_error = try formatter.formatError(error_msg);
        defer allocator.free(formatted_error);
        
        std.debug.print("{s}", .{formatted_error});
        return;
    };
    defer allocator.free(response);
    
    // Write to file
    const file = std.fs.cwd().createFile(file_path, .{}) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to create file '{s}': {}", .{ file_path, err });
        defer allocator.free(error_msg);
        
        const formatted_error = try formatter.formatError(error_msg);
        defer allocator.free(formatted_error);
        
        std.debug.print("{s}", .{formatted_error});
        return;
    };
    defer file.close();
    
    file.writeAll(response) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to write to file '{s}': {}", .{ file_path, err });
        defer allocator.free(error_msg);
        
        const formatted_error = try formatter.formatError(error_msg);
        defer allocator.free(formatted_error);
        
        std.debug.print("{s}", .{formatted_error});
        return;
    };
    
    const success_msg = try std.fmt.allocPrint(allocator, "✅ Successfully generated file: {s}", .{file_path});
    defer allocator.free(success_msg);
    
    const formatted_success = try formatter.formatResponse(success_msg);
    defer allocator.free(formatted_success);
    
    std.debug.print("{s}", .{formatted_success});
}

fn detectLanguage(extension: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, extension, ".zig")) return "zig";
    if (std.mem.eql(u8, extension, ".rs")) return "rust";
    if (std.mem.eql(u8, extension, ".go")) return "go";
    if (std.mem.eql(u8, extension, ".js")) return "javascript";
    if (std.mem.eql(u8, extension, ".ts")) return "typescript";
    if (std.mem.eql(u8, extension, ".py")) return "python";
    if (std.mem.eql(u8, extension, ".java")) return "java";
    if (std.mem.eql(u8, extension, ".cpp") or std.mem.eql(u8, extension, ".cc")) return "cpp";
    if (std.mem.eql(u8, extension, ".c")) return "c";
    if (std.mem.eql(u8, extension, ".h")) return "c";
    if (std.mem.eql(u8, extension, ".lua")) return "lua";
    if (std.mem.eql(u8, extension, ".sh")) return "bash";
    if (std.mem.eql(u8, extension, ".md")) return "markdown";
    if (std.mem.eql(u8, extension, ".json")) return "json";
    if (std.mem.eql(u8, extension, ".yaml") or std.mem.eql(u8, extension, ".yml")) return "yaml";
    if (std.mem.eql(u8, extension, ".toml")) return "toml";
    if (std.mem.eql(u8, extension, ".xml")) return "xml";
    if (std.mem.eql(u8, extension, ".html")) return "html";
    if (std.mem.eql(u8, extension, ".css")) return "css";
    return null;
}