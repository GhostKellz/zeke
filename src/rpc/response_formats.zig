const std = @import("std");

/// Structured response formats for Zion integration APIs
pub const ResponseFormats = struct {
    
    /// Dependency information response format
    pub const DependencyResponse = struct {
        name: []const u8,
        version: ?[]const u8 = null,
        url: ?[]const u8 = null,
        hash: ?[]const u8 = null,
        registry: ?[]const u8 = null,
        security_score: ?u8 = null,
        alternatives: [][]const u8 = &[_][]const u8{},
        conflicts: [][]const u8 = &[_][]const u8{},
        size_impact: ?u64 = null, // Estimated size impact in bytes
        maintenance_score: ?u8 = null,
        popularity_score: ?u8 = null,
        
        pub fn toJson(self: DependencyResponse, allocator: std.mem.Allocator) !std.json.ObjectMap {
            var obj = std.json.ObjectMap.init(allocator);
            
            try obj.put("name", std.json.Value{ .string = self.name });
            
            if (self.version) |version| {
                try obj.put("version", std.json.Value{ .string = version });
            }
            
            if (self.url) |url| {
                try obj.put("url", std.json.Value{ .string = url });
            }
            
            if (self.hash) |hash| {
                try obj.put("hash", std.json.Value{ .string = hash });
            }
            
            if (self.registry) |registry| {
                try obj.put("registry", std.json.Value{ .string = registry });
            }
            
            if (self.security_score) |score| {
                try obj.put("security_score", std.json.Value{ .integer = @intCast(score) });
            }
            
            if (self.maintenance_score) |score| {
                try obj.put("maintenance_score", std.json.Value{ .integer = @intCast(score) });
            }
            
            if (self.popularity_score) |score| {
                try obj.put("popularity_score", std.json.Value{ .integer = @intCast(score) });
            }
            
            if (self.size_impact) |size| {
                try obj.put("size_impact_bytes", std.json.Value{ .integer = @intCast(size) });
            }
            
            // Alternatives array
            var alternatives_array = std.json.Array.init(allocator);
            for (self.alternatives) |alt| {
                try alternatives_array.append(std.json.Value{ .string = alt });
            }
            try obj.put("alternatives", std.json.Value{ .array = alternatives_array });
            
            // Conflicts array
            var conflicts_array = std.json.Array.init(allocator);
            for (self.conflicts) |conflict| {
                try conflicts_array.append(std.json.Value{ .string = conflict });
            }
            try obj.put("conflicts", std.json.Value{ .array = conflicts_array });
            
            return obj;
        }
    };
    
    /// Build analysis response format
    pub const BuildAnalysisResponse = struct {
        build_issues: []BuildIssue,
        optimization_suggestions: []OptimizationSuggestion,
        performance_metrics: ?PerformanceMetrics = null,
        
        pub const BuildIssue = struct {
            type: IssueType,
            severity: Severity,
            message: []const u8,
            suggestion: ?[]const u8 = null,
            file: ?[]const u8 = null,
            line: ?u32 = null,
            fix_command: ?[]const u8 = null,
            
            pub const IssueType = enum {
                performance,
                security,
                compatibility,
                optimization,
                dependency,
                configuration,
            };
            
            pub const Severity = enum {
                low,
                medium,
                high,
                critical,
            };
            
            pub fn toJson(self: BuildIssue, allocator: std.mem.Allocator) !std.json.ObjectMap {
                var obj = std.json.ObjectMap.init(allocator);
                
                try obj.put("type", std.json.Value{ .string = @tagName(self.type) });
                try obj.put("severity", std.json.Value{ .string = @tagName(self.severity) });
                try obj.put("message", std.json.Value{ .string = self.message });
                
                if (self.suggestion) |suggestion| {
                    try obj.put("suggestion", std.json.Value{ .string = suggestion });
                }
                
                if (self.file) |file| {
                    try obj.put("file", std.json.Value{ .string = file });
                }
                
                if (self.line) |line| {
                    try obj.put("line", std.json.Value{ .integer = @intCast(line) });
                }
                
                if (self.fix_command) |cmd| {
                    try obj.put("fix_command", std.json.Value{ .string = cmd });
                }
                
                return obj;
            }
        };
        
        pub const OptimizationSuggestion = struct {
            category: Category,
            impact: Impact,
            description: []const u8,
            implementation: []const u8,
            estimated_improvement: ?[]const u8 = null,
            
            pub const Category = enum {
                build_speed,
                binary_size,
                runtime_performance,
                dependency_management,
                configuration,
            };
            
            pub const Impact = enum {
                low,
                medium,
                high,
            };
            
            pub fn toJson(self: OptimizationSuggestion, allocator: std.mem.Allocator) !std.json.ObjectMap {
                var obj = std.json.ObjectMap.init(allocator);
                
                try obj.put("category", std.json.Value{ .string = @tagName(self.category) });
                try obj.put("impact", std.json.Value{ .string = @tagName(self.impact) });
                try obj.put("description", std.json.Value{ .string = self.description });
                try obj.put("implementation", std.json.Value{ .string = self.implementation });
                
                if (self.estimated_improvement) |improvement| {
                    try obj.put("estimated_improvement", std.json.Value{ .string = improvement });
                }
                
                return obj;
            }
        };
        
        pub const PerformanceMetrics = struct {
            estimated_build_time_ms: u64,
            estimated_binary_size_bytes: ?u64 = null,
            dependency_count: u32,
            module_count: u32,
            complexity_score: ?u8 = null,
            
            pub fn toJson(self: PerformanceMetrics, allocator: std.mem.Allocator) !std.json.ObjectMap {
                var obj = std.json.ObjectMap.init(allocator);
                
                try obj.put("estimated_build_time_ms", std.json.Value{ .integer = @intCast(self.estimated_build_time_ms) });
                try obj.put("dependency_count", std.json.Value{ .integer = @intCast(self.dependency_count) });
                try obj.put("module_count", std.json.Value{ .integer = @intCast(self.module_count) });
                
                if (self.estimated_binary_size_bytes) |size| {
                    try obj.put("estimated_binary_size_bytes", std.json.Value{ .integer = @intCast(size) });
                }
                
                if (self.complexity_score) |score| {
                    try obj.put("complexity_score", std.json.Value{ .integer = @intCast(score) });
                }
                
                return obj;
            }
        };
        
        pub fn toJson(self: BuildAnalysisResponse, allocator: std.mem.Allocator) !std.json.ObjectMap {
            var obj = std.json.ObjectMap.init(allocator);
            
            // Build issues array
            var issues_array = std.json.Array.init(allocator);
            for (self.build_issues) |issue| {
                const issue_obj = try issue.toJson(allocator);
                try issues_array.append(std.json.Value{ .object = issue_obj });
            }
            try obj.put("build_issues", std.json.Value{ .array = issues_array });
            
            // Optimization suggestions array
            var optimizations_array = std.json.Array.init(allocator);
            for (self.optimization_suggestions) |opt| {
                const opt_obj = try opt.toJson(allocator);
                try optimizations_array.append(std.json.Value{ .object = opt_obj });
            }
            try obj.put("optimization_suggestions", std.json.Value{ .array = optimizations_array });
            
            // Performance metrics
            if (self.performance_metrics) |metrics| {
                const metrics_obj = try metrics.toJson(allocator);
                try obj.put("performance_metrics", std.json.Value{ .object = metrics_obj });
            }
            
            return obj;
        }
    };
    
    /// Package recommendation response format
    pub const PackageRecommendationResponse = struct {
        query: []const u8,
        recommendations: []PackageRecommendation,
        total_found: u32,
        search_time_ms: ?u64 = null,
        
        pub const PackageRecommendation = struct {
            name: []const u8,
            score: f32,
            reason: []const u8,
            registry: []const u8,
            version: ?[]const u8 = null,
            url: ?[]const u8 = null,
            description: ?[]const u8 = null,
            tags: [][]const u8 = &[_][]const u8{},
            alternatives: []AlternativePackage = &[_]AlternativePackage{},
            
            pub const AlternativePackage = struct {
                name: []const u8,
                reason: []const u8,
                score: f32,
                
                pub fn toJson(self: AlternativePackage, allocator: std.mem.Allocator) !std.json.ObjectMap {
                    var obj = std.json.ObjectMap.init(allocator);
                    try obj.put("name", std.json.Value{ .string = self.name });
                    try obj.put("reason", std.json.Value{ .string = self.reason });
                    try obj.put("score", std.json.Value{ .float = self.score });
                    return obj;
                }
            };
            
            pub fn toJson(self: PackageRecommendation, allocator: std.mem.Allocator) !std.json.ObjectMap {
                var obj = std.json.ObjectMap.init(allocator);
                
                try obj.put("name", std.json.Value{ .string = self.name });
                try obj.put("score", std.json.Value{ .float = self.score });
                try obj.put("reason", std.json.Value{ .string = self.reason });
                try obj.put("registry", std.json.Value{ .string = self.registry });
                
                if (self.version) |version| {
                    try obj.put("version", std.json.Value{ .string = version });
                }
                
                if (self.url) |url| {
                    try obj.put("url", std.json.Value{ .string = url });
                }
                
                if (self.description) |desc| {
                    try obj.put("description", std.json.Value{ .string = desc });
                }
                
                // Tags array
                var tags_array = std.json.Array.init(allocator);
                for (self.tags) |tag| {
                    try tags_array.append(std.json.Value{ .string = tag });
                }
                try obj.put("tags", std.json.Value{ .array = tags_array });
                
                // Alternatives array
                var alternatives_array = std.json.Array.init(allocator);
                for (self.alternatives) |alt| {
                    const alt_obj = try alt.toJson(allocator);
                    try alternatives_array.append(std.json.Value{ .object = alt_obj });
                }
                try obj.put("alternatives", std.json.Value{ .array = alternatives_array });
                
                return obj;
            }
        };
        
        pub fn toJson(self: PackageRecommendationResponse, allocator: std.mem.Allocator) !std.json.ObjectMap {
            var obj = std.json.ObjectMap.init(allocator);
            
            try obj.put("query", std.json.Value{ .string = self.query });
            try obj.put("total_found", std.json.Value{ .integer = @intCast(self.total_found) });
            
            if (self.search_time_ms) |time| {
                try obj.put("search_time_ms", std.json.Value{ .integer = @intCast(time) });
            }
            
            // Recommendations array
            var recommendations_array = std.json.Array.init(allocator);
            for (self.recommendations) |rec| {
                const rec_obj = try rec.toJson(allocator);
                try recommendations_array.append(std.json.Value{ .object = rec_obj });
            }
            try obj.put("recommendations", std.json.Value{ .array = recommendations_array });
            
            return obj;
        }
    };
    
    /// Project analysis response format
    pub const ProjectAnalysisResponse = struct {
        project_info: ProjectInfo,
        dependencies: []DependencyResponse,
        build_analysis: BuildAnalysisResponse,
        summary: ProjectSummary,
        
        pub const ProjectInfo = struct {
            name: ?[]const u8 = null,
            version: ?[]const u8 = null,
            build_system: []const u8,
            target_info: ?[]const u8 = null,
            optimization_level: ?[]const u8 = null,
            
            pub fn toJson(self: ProjectInfo, allocator: std.mem.Allocator) !std.json.ObjectMap {
                var obj = std.json.ObjectMap.init(allocator);
                
                if (self.name) |name| {
                    try obj.put("name", std.json.Value{ .string = name });
                }
                
                if (self.version) |version| {
                    try obj.put("version", std.json.Value{ .string = version });
                }
                
                try obj.put("build_system", std.json.Value{ .string = self.build_system });
                
                if (self.target_info) |target| {
                    try obj.put("target_info", std.json.Value{ .string = target });
                }
                
                if (self.optimization_level) |opt| {
                    try obj.put("optimization_level", std.json.Value{ .string = opt });
                }
                
                return obj;
            }
        };
        
        pub const ProjectSummary = struct {
            health_score: u8, // 0-100
            readiness: Readiness,
            recommendations: [][]const u8,
            
            pub const Readiness = enum {
                development,
                testing,
                production,
                needs_attention,
            };
            
            pub fn toJson(self: ProjectSummary, allocator: std.mem.Allocator) !std.json.ObjectMap {
                var obj = std.json.ObjectMap.init(allocator);
                
                try obj.put("health_score", std.json.Value{ .integer = @intCast(self.health_score) });
                try obj.put("readiness", std.json.Value{ .string = @tagName(self.readiness) });
                
                var recommendations_array = std.json.Array.init(allocator);
                for (self.recommendations) |rec| {
                    try recommendations_array.append(std.json.Value{ .string = rec });
                }
                try obj.put("recommendations", std.json.Value{ .array = recommendations_array });
                
                return obj;
            }
        };
        
        pub fn toJson(self: ProjectAnalysisResponse, allocator: std.mem.Allocator) !std.json.ObjectMap {
            var obj = std.json.ObjectMap.init(allocator);
            
            // Project info
            const project_info_obj = try self.project_info.toJson(allocator);
            try obj.put("project_info", std.json.Value{ .object = project_info_obj });
            
            // Dependencies array
            var dependencies_array = std.json.Array.init(allocator);
            for (self.dependencies) |dep| {
                const dep_obj = try dep.toJson(allocator);
                try dependencies_array.append(std.json.Value{ .object = dep_obj });
            }
            try obj.put("dependencies", std.json.Value{ .array = dependencies_array });
            
            // Build analysis
            const build_analysis_obj = try self.build_analysis.toJson(allocator);
            try obj.put("build_analysis", std.json.Value{ .object = build_analysis_obj });
            
            // Summary
            const summary_obj = try self.summary.toJson(allocator);
            try obj.put("summary", std.json.Value{ .object = summary_obj });
            
            return obj;
        }
    };
};