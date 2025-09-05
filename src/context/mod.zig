const std = @import("std");
const api = @import("../api/client.zig");

/// Project context cache for intelligent code understanding
pub const ProjectContextCache = struct {
    allocator: std.mem.Allocator,
    cache: std.HashMap([]const u8, CachedContext, HashMapContext, 80),
    file_dependencies: std.HashMap([]const u8, [][]const u8, HashMapContext, 80),
    project_structure: ?ProjectStructure,
    cache_hits: u64,
    cache_misses: u64,
    max_cache_size: u32,
    
    const HashMapContext = std.hash_map.StringContext;
    
    pub const CachedContext = struct {
        file_path: []const u8,
        content_hash: u64,
        language: []const u8,
        imports: [][]const u8,
        exports: [][]const u8,
        functions: []FunctionInfo,
        types: []TypeInfo,
        symbols: []SymbolInfo,
        timestamp: i64,
        access_count: u32,
        
        pub fn deinit(self: *CachedContext, allocator: std.mem.Allocator) void {
            allocator.free(self.file_path);
            allocator.free(self.language);
            
            for (self.imports) |import| {
                allocator.free(import);
            }
            allocator.free(self.imports);
            
            for (self.exports) |exp| {
                allocator.free(exp);
            }
            allocator.free(self.exports);
            
            for (self.functions) |*func| {
                func.deinit(allocator);
            }
            allocator.free(self.functions);
            
            for (self.types) |*type_info| {
                type_info.deinit(allocator);
            }
            allocator.free(self.types);
            
            for (self.symbols) |*symbol| {
                symbol.deinit(allocator);
            }
            allocator.free(self.symbols);
        }
    };
    
    pub const FunctionInfo = struct {
        name: []const u8,
        signature: []const u8,
        line_start: u32,
        line_end: u32,
        parameters: [][]const u8,
        return_type: ?[]const u8,
        doc_comment: ?[]const u8,
        
        pub fn deinit(self: *FunctionInfo, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            allocator.free(self.signature);
            
            for (self.parameters) |param| {
                allocator.free(param);
            }
            allocator.free(self.parameters);
            
            if (self.return_type) |rt| allocator.free(rt);
            if (self.doc_comment) |doc| allocator.free(doc);
        }
    };
    
    pub const TypeInfo = struct {
        name: []const u8,
        kind: TypeKind,
        definition: []const u8,
        line_number: u32,
        
        pub const TypeKind = enum {
            struct_type,
            enum_type,
            union_type,
            typedef,
            interface,
            class,
        };
        
        pub fn deinit(self: *TypeInfo, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            allocator.free(self.definition);
        }
    };
    
    pub const SymbolInfo = struct {
        name: []const u8,
        kind: SymbolKind,
        line_number: u32,
        scope: []const u8,
        
        pub const SymbolKind = enum {
            variable,
            constant,
            function,
            type,
            module,
            namespace,
        };
        
        pub fn deinit(self: *SymbolInfo, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            allocator.free(self.scope);
        }
    };
    
    pub const ProjectStructure = struct {
        root_path: []const u8,
        languages: [][]const u8,
        build_files: [][]const u8,
        config_files: [][]const u8,
        main_files: [][]const u8,
        test_files: [][]const u8,
        file_tree: std.ArrayList(FileNode),
        
        pub const FileNode = struct {
            path: []const u8,
            is_directory: bool,
            size: u64,
            modified_time: i64,
            children: std.ArrayList(*FileNode),
            
            pub fn deinit(self: *FileNode, allocator: std.mem.Allocator) void {
                allocator.free(self.path);
                for (self.children.items) |child| {
                    child.deinit(allocator);
                    allocator.destroy(child);
                }
                self.children.deinit(allocator);
            }
        };
        
        pub fn deinit(self: *ProjectStructure, allocator: std.mem.Allocator) void {
            allocator.free(self.root_path);
            
            for (self.languages) |lang| {
                allocator.free(lang);
            }
            allocator.free(self.languages);
            
            for (self.build_files) |file| {
                allocator.free(file);
            }
            allocator.free(self.build_files);
            
            for (self.config_files) |file| {
                allocator.free(file);
            }
            allocator.free(self.config_files);
            
            for (self.main_files) |file| {
                allocator.free(file);
            }
            allocator.free(self.main_files);
            
            for (self.test_files) |file| {
                allocator.free(file);
            }
            allocator.free(self.test_files);
            
            for (self.file_tree.items) |*node| {
                node.deinit(allocator);
            }
            self.file_tree.deinit(allocator);
        }
    };
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .cache = std.HashMap([]const u8, CachedContext, HashMapContext, 80).init(allocator),
            .file_dependencies = std.HashMap([]const u8, [][]const u8, HashMapContext, 80).init(allocator),
            .project_structure = null,
            .cache_hits = 0,
            .cache_misses = 0,
            .max_cache_size = 1000,
        };
    }
    
    pub fn deinit(self: *Self) void {
        // Clean up cached contexts
        var cache_iter = self.cache.iterator();
        while (cache_iter.next()) |entry| {
            var context = entry.value_ptr;
            context.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.cache.deinit();
        
        // Clean up file dependencies
        var deps_iter = self.file_dependencies.iterator();
        while (deps_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |dep| {
                self.allocator.free(dep);
            }
            self.allocator.free(entry.value_ptr.*);
        }
        self.file_dependencies.deinit();
        
        // Clean up project structure
        if (self.project_structure) |*structure| {
            structure.deinit(self.allocator);
        }
    }
    
    pub fn getContext(self: *Self, file_path: []const u8) ?*CachedContext {
        if (self.cache.getPtr(file_path)) |context| {
            context.access_count += 1;
            self.cache_hits += 1;
            return context;
        }
        
        self.cache_misses += 1;
        return null;
    }
    
    pub fn cacheContext(self: *Self, file_path: []const u8, content: []const u8) !void {
        // Check if we need to evict entries
        if (self.cache.count() >= self.max_cache_size) {
            try self.evictOldestEntry();
        }
        
        // Calculate content hash
        const content_hash = std.hash.XxHash64.hash(0, content);
        
        // Check if file already cached and content hasn't changed
        if (self.cache.get(file_path)) |existing| {
            if (existing.content_hash == content_hash) {
                // Content hasn't changed, just update timestamp
                var context = self.cache.getPtr(file_path).?;
                context.timestamp = std.time.timestamp();
                context.access_count += 1;
                return;
            }
        }
        
        // Parse file and create context
        const context = try self.parseFileContent(file_path, content, content_hash);
        
        // Store in cache
        const key = try self.allocator.dupe(u8, file_path);
        try self.cache.put(key, context);
        
        // Update dependencies
        try self.updateDependencies(file_path, context.imports);
    }
    
    fn parseFileContent(self: *Self, file_path: []const u8, content: []const u8, content_hash: u64) !CachedContext {
        const language = try self.detectLanguage(file_path);
        
        var imports = std.ArrayList([]const u8){};
        var exports = std.ArrayList([]const u8){};
        var functions = std.ArrayList(FunctionInfo){};
        var types = std.ArrayList(TypeInfo){};
        var symbols = std.ArrayList(SymbolInfo){};
        
        defer {
            imports.deinit(self.allocator);
            exports.deinit(self.allocator);
            functions.deinit(self.allocator);
            types.deinit(self.allocator);
            symbols.deinit(self.allocator);
        }
        
        // Parse based on language
        if (std.mem.eql(u8, language, "zig")) {
            try self.parseZigFile(content, &imports, &exports, &functions, &types, &symbols);
        } else if (std.mem.eql(u8, language, "typescript") or std.mem.eql(u8, language, "javascript")) {
            try self.parseJSFile(content, &imports, &exports, &functions, &types, &symbols);
        } else if (std.mem.eql(u8, language, "python")) {
            try self.parsePythonFile(content, &imports, &exports, &functions, &types, &symbols);
        } else {
            // Generic parsing for other languages
            try self.parseGenericFile(content, &imports, &exports, &functions, &types, &symbols);
        }
        
        return CachedContext{
            .file_path = try self.allocator.dupe(u8, file_path),
            .content_hash = content_hash,
            .language = language,
            .imports = try imports.toOwnedSlice(self.allocator),
            .exports = try exports.toOwnedSlice(self.allocator),
            .functions = try functions.toOwnedSlice(self.allocator),
            .types = try types.toOwnedSlice(self.allocator),
            .symbols = try symbols.toOwnedSlice(self.allocator),
            .timestamp = std.time.timestamp(),
            .access_count = 1,
        };
    }
    
    fn detectLanguage(self: *Self, file_path: []const u8) ![]const u8 {
        const extension = std.fs.path.extension(file_path);
        
        if (std.mem.eql(u8, extension, ".zig")) {
            return try self.allocator.dupe(u8, "zig");
        } else if (std.mem.eql(u8, extension, ".ts")) {
            return try self.allocator.dupe(u8, "typescript");
        } else if (std.mem.eql(u8, extension, ".js")) {
            return try self.allocator.dupe(u8, "javascript");
        } else if (std.mem.eql(u8, extension, ".py")) {
            return try self.allocator.dupe(u8, "python");
        } else if (std.mem.eql(u8, extension, ".rs")) {
            return try self.allocator.dupe(u8, "rust");
        } else if (std.mem.eql(u8, extension, ".c")) {
            return try self.allocator.dupe(u8, "c");
        } else if (std.mem.eql(u8, extension, ".cpp") or std.mem.eql(u8, extension, ".cc")) {
            return try self.allocator.dupe(u8, "cpp");
        } else if (std.mem.eql(u8, extension, ".go")) {
            return try self.allocator.dupe(u8, "go");
        } else if (std.mem.eql(u8, extension, ".java")) {
            return try self.allocator.dupe(u8, "java");
        } else {
            return try self.allocator.dupe(u8, "unknown");
        }
    }
    
    fn parseZigFile(
        self: *Self,
        content: []const u8,
        imports: *std.ArrayList([]const u8),
        exports: *std.ArrayList([]const u8),
        functions: *std.ArrayList(FunctionInfo),
        types: *std.ArrayList(TypeInfo),
        symbols: *std.ArrayList(SymbolInfo)
    ) !void {
        var line_iter = std.mem.split(u8, content, "\n");
        var line_number: u32 = 1;
        
        while (line_iter.next()) |line| {
            defer line_number += 1;
            
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len == 0) continue;
            
            // Parse imports
            if (std.mem.startsWith(u8, trimmed, "const ") and std.mem.indexOf(u8, trimmed, "@import(") != null) {
                if (self.extractZigImport(trimmed)) |import| {
                    try imports.append(try self.allocator.dupe(u8, import));
                }
            }
            
            // Parse public declarations (exports)
            if (std.mem.startsWith(u8, trimmed, "pub ")) {
                if (self.extractZigExport(trimmed)) |exp| {
                    try exports.append(try self.allocator.dupe(u8, exp));
                }
            }
            
            // Parse functions
            if (std.mem.indexOf(u8, trimmed, "fn ") != null) {
                if (try self.extractZigFunction(trimmed, line_number)) |function| {
                    try functions.append(function);
                }
            }
            
            // Parse types
            if (std.mem.indexOf(u8, trimmed, "struct") != null or 
               std.mem.indexOf(u8, trimmed, "enum") != null or 
               std.mem.indexOf(u8, trimmed, "union") != null) {
                if (try self.extractZigType(trimmed, line_number)) |type_info| {
                    try types.append(type_info);
                }
            }
            
            // Parse constants and variables
            if (std.mem.startsWith(u8, trimmed, "const ") or std.mem.startsWith(u8, trimmed, "var ")) {
                if (try self.extractZigSymbol(trimmed, line_number)) |symbol| {
                    try symbols.append(symbol);
                }
            }
        }
    }
    
    // Helper methods for parsing Zig files
    fn extractZigImport(self: *Self, line: []const u8) ?[]const u8 {
        _ = self;
        
        const import_start = std.mem.indexOf(u8, line, "@import(\"") orelse return null;
        const quote_start = import_start + 9;
        const quote_end = std.mem.indexOf(u8, line[quote_start..], "\"") orelse return null;
        
        return line[quote_start..quote_start + quote_end];
    }
    
    fn extractZigExport(self: *Self, line: []const u8) ?[]const u8 {
        _ = self;
        
        // Extract the identifier after "pub "
        const pub_start = 4; // Length of "pub "
        const space_idx = std.mem.indexOf(u8, line[pub_start..], " ") orelse return null;
        const identifier_start = pub_start + space_idx + 1;
        
        // Find the end of the identifier
        var identifier_end = identifier_start;
        while (identifier_end < line.len and 
               (std.ascii.isAlphanumeric(line[identifier_end]) or line[identifier_end] == '_')) {
            identifier_end += 1;
        }
        
        if (identifier_end > identifier_start) {
            return line[identifier_start..identifier_end];
        }
        
        return null;
    }
    
    fn extractZigFunction(self: *Self, line: []const u8, line_number: u32) !?FunctionInfo {
        const fn_idx = std.mem.indexOf(u8, line, "fn ") orelse return null;
        const name_start = fn_idx + 3;
        
        // Find function name
        const paren_idx = std.mem.indexOf(u8, line[name_start..], "(") orelse return null;
        const name_end = name_start + paren_idx;
        
        const name = try self.allocator.dupe(u8, std.mem.trim(u8, line[name_start..name_end], " \t"));
        
        // Extract signature (simplified)
        const signature = try self.allocator.dupe(u8, line[fn_idx..]);
        
        return FunctionInfo{
            .name = name,
            .signature = signature,
            .line_start = line_number,
            .line_end = line_number, // TODO: Track actual end line
            .parameters = try self.allocator.alloc([]const u8, 0), // TODO: Parse parameters
            .return_type = null, // TODO: Parse return type
            .doc_comment = null, // TODO: Parse doc comments
        };
    }
    
    fn extractZigType(self: *Self, line: []const u8, line_number: u32) !?TypeInfo {
        var kind: TypeInfo.TypeKind = .struct_type;
        var keyword_start: usize = 0;
        
        if (std.mem.indexOf(u8, line, "struct")) |idx| {
            kind = .struct_type;
            keyword_start = idx;
        } else if (std.mem.indexOf(u8, line, "enum")) |idx| {
            kind = .enum_type;
            keyword_start = idx;
        } else if (std.mem.indexOf(u8, line, "union")) |idx| {
            kind = .union_type;
            keyword_start = idx;
        } else {
            return null;
        }
        
        // Find type name (before the keyword)
        var name_start: usize = 0;
        const equals_idx = std.mem.lastIndexOf(u8, line[0..keyword_start], "=") orelse return null;
        
        // Look backwards from = to find the identifier
        var i = equals_idx;
        while (i > 0 and (line[i - 1] == ' ' or line[i - 1] == '\t')) i -= 1;
        
        const name_end = i;
        while (i > 0 and (std.ascii.isAlphanumeric(line[i - 1]) or line[i - 1] == '_')) i -= 1;
        name_start = i;
        
        if (name_end > name_start) {
            const name = try self.allocator.dupe(u8, line[name_start..name_end]);
            const definition = try self.allocator.dupe(u8, line);
            
            return TypeInfo{
                .name = name,
                .kind = kind,
                .definition = definition,
                .line_number = line_number,
            };
        }
        
        return null;
    }
    
    fn extractZigSymbol(self: *Self, line: []const u8, line_number: u32) !?SymbolInfo {
        const is_const = std.mem.startsWith(u8, line, "const ");
        const keyword_len: usize = if (is_const) 6 else 4; // "const " vs "var "
        
        // Find the identifier
        const identifier_start = keyword_len;
        const colon_idx = std.mem.indexOf(u8, line[identifier_start..], ":") orelse 
                         std.mem.indexOf(u8, line[identifier_start..], "=") orelse return null;
        
        const identifier_end = identifier_start + colon_idx;
        const name = try self.allocator.dupe(u8, std.mem.trim(u8, line[identifier_start..identifier_end], " \t"));
        
        return SymbolInfo{
            .name = name,
            .kind = if (is_const) .constant else .variable,
            .line_number = line_number,
            .scope = try self.allocator.dupe(u8, "global"), // TODO: Track actual scope
        };
    }
    
    // Placeholder parsing functions for other languages
    fn parseJSFile(
        self: *Self,
        content: []const u8,
        imports: *std.ArrayList([]const u8),
        exports: *std.ArrayList([]const u8),
        functions: *std.ArrayList(FunctionInfo),
        types: *std.ArrayList(TypeInfo),
        symbols: *std.ArrayList(SymbolInfo)
    ) !void {
        // TODO: Implement JavaScript/TypeScript parsing
        _ = self;
        _ = content;
        _ = imports;
        _ = exports;
        _ = functions;
        _ = types;
        _ = symbols;
    }
    
    fn parsePythonFile(
        self: *Self,
        content: []const u8,
        imports: *std.ArrayList([]const u8),
        exports: *std.ArrayList([]const u8),
        functions: *std.ArrayList(FunctionInfo),
        types: *std.ArrayList(TypeInfo),
        symbols: *std.ArrayList(SymbolInfo)
    ) !void {
        // TODO: Implement Python parsing
        _ = self;
        _ = content;
        _ = imports;
        _ = exports;
        _ = functions;
        _ = types;
        _ = symbols;
    }
    
    fn parseGenericFile(
        self: *Self,
        content: []const u8,
        imports: *std.ArrayList([]const u8),
        exports: *std.ArrayList([]const u8),
        functions: *std.ArrayList(FunctionInfo),
        types: *std.ArrayList(TypeInfo),
        symbols: *std.ArrayList(SymbolInfo)
    ) !void {
        // TODO: Implement generic parsing
        _ = self;
        _ = content;
        _ = imports;
        _ = exports;
        _ = functions;
        _ = types;
        _ = symbols;
    }
    
    fn updateDependencies(self: *Self, file_path: []const u8, imports: [][]const u8) !void {
        // Store file dependencies
        const key = try self.allocator.dupe(u8, file_path);
        var deps = std.ArrayList([]const u8){};
        
        for (imports) |import| {
            try deps.append(self.allocator, try self.allocator.dupe(u8, import));
        }
        
        // Remove existing dependencies if any
        if (self.file_dependencies.get(file_path)) |existing| {
            for (existing) |dep| {
                self.allocator.free(dep);
            }
            self.allocator.free(existing);
        }
        
        try self.file_dependencies.put(key, try deps.toOwnedSlice(self.allocator));
    }
    
    fn evictOldestEntry(self: *Self) !void {
        // Find the least recently used entry
        var oldest_key: ?[]const u8 = null;
        var oldest_timestamp: i64 = std.math.maxInt(i64);
        var lowest_access_count: u32 = std.math.maxInt(u32);
        
        var iter = self.cache.iterator();
        while (iter.next()) |entry| {
            const context = entry.value_ptr.*;
            
            // Prefer entries with lower access count, then older timestamp
            if (context.access_count < lowest_access_count or 
                (context.access_count == lowest_access_count and context.timestamp < oldest_timestamp)) {
                oldest_key = entry.key_ptr.*;
                oldest_timestamp = context.timestamp;
                lowest_access_count = context.access_count;
            }
        }
        
        // Remove the oldest entry
        if (oldest_key) |key| {
            var context = self.cache.get(key).?;
            context.deinit(self.allocator);
            self.allocator.free(key);
            _ = self.cache.remove(key);
        }
    }
    
    pub fn analyzeProject(self: *Self, project_path: []const u8) !void {
        // Build project structure
        self.project_structure = try self.buildProjectStructure(project_path);
        
        // Analyze all relevant files
        try self.analyzeProjectFiles(project_path);
    }
    
    fn buildProjectStructure(self: *Self, project_path: []const u8) !ProjectStructure {
        const structure = ProjectStructure{
            .root_path = try self.allocator.dupe(u8, project_path),
            .languages = std.ArrayList([]const u8){},
            .build_files = std.ArrayList([]const u8){},
            .config_files = std.ArrayList([]const u8){},
            .main_files = std.ArrayList([]const u8){},
            .test_files = std.ArrayList([]const u8){},
            .file_tree = std.ArrayList(ProjectStructure.FileNode){},
        };
        
        // TODO: Implement recursive directory traversal
        // For now, return basic structure
        return structure;
    }
    
    fn analyzeProjectFiles(self: *Self, project_path: []const u8) !void {
        // TODO: Implement project file analysis
        _ = self;
        _ = project_path;
    }
    
    pub fn getDependencies(self: *Self, file_path: []const u8) ?[][]const u8 {
        return self.file_dependencies.get(file_path);
    }
    
    pub fn getRelatedFiles(self: *Self, file_path: []const u8, allocator: std.mem.Allocator) ![][]const u8 {
        var related = std.ArrayList([]const u8){};
        
        // Add direct dependencies
        if (self.getDependencies(file_path)) |deps| {
            for (deps) |dep| {
                try related.append(allocator, try allocator.dupe(u8, dep));
            }
        }
        
        // Add files that depend on this file
        var iter = self.file_dependencies.iterator();
        while (iter.next()) |entry| {
            const other_file = entry.key_ptr.*;
            const other_deps = entry.value_ptr.*;
            
            for (other_deps) |dep| {
                if (std.mem.eql(u8, dep, file_path)) {
                    try related.append(try allocator.dupe(u8, other_file));
                    break;
                }
            }
        }
        
        return related.toOwnedSlice(allocator);
    }
    
    pub fn getCacheStats(self: *const Self) struct { hits: u64, misses: u64, size: u32 } {
        return .{
            .hits = self.cache_hits,
            .misses = self.cache_misses,
            .size = @intCast(self.cache.count()),
        };
    }
    
    pub fn clearCache(self: *Self) !void {
        var iter = self.cache.iterator();
        while (iter.next()) |entry| {
            var context = entry.value_ptr;
            context.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.cache.clearAndFree();
        
        self.cache_hits = 0;
        self.cache_misses = 0;
    }
};