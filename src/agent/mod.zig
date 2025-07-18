const std = @import("std");
const print = std.debug.print;

// Core agent framework
pub const Agent = struct {
    const Self = @This();
    
    // Agent metadata
    name: []const u8,
    version: []const u8,
    agent_type: AgentType,
    
    // Core function pointers
    initialize: *const fn(self: *Self, allocator: std.mem.Allocator) anyerror!void,
    execute: *const fn(self: *Self, command: []const u8, args: []const []const u8) anyerror!AgentResult,
    cleanup: *const fn(self: *Self) anyerror!void,
    
    // Agent state
    allocator: std.mem.Allocator,
    state: AgentState,
    
    pub fn init(allocator: std.mem.Allocator, name: []const u8, version: []const u8, agent_type: AgentType) Agent {
        return Agent{
            .name = name,
            .version = version,
            .agent_type = agent_type,
            .initialize = defaultInitialize,
            .execute = defaultExecute,
            .cleanup = defaultCleanup,
            .allocator = allocator,
            .state = .idle,
        };
    }
    
    pub fn run(self: *Self, command: []const u8, args: []const []const u8) !AgentResult {
        self.state = .running;
        defer self.state = .idle;
        
        return self.execute(self, command, args);
    }
    
    // Default implementations
    fn defaultInitialize(self: *Self, allocator: std.mem.Allocator) !void {
        _ = self;
        _ = allocator;
    }
    
    fn defaultExecute(self: *Self, command: []const u8, args: []const []const u8) !AgentResult {
        _ = self;
        _ = args;
        
        // Log the command that was attempted
        std.log.info("Command '{s}' not implemented for this agent", .{command});
        
        return AgentResult{ 
            .success = false, 
            .message = "Command not implemented", 
            .data = null 
        };
    }
    
    fn defaultCleanup(self: *Self) !void {
        _ = self;
    }
};

// Agent types for different operational domains
pub const AgentType = enum {
    blockchain,
    network,
    security,
    system,
    smartcontract,
    custom,
};

// Agent execution states
pub const AgentState = enum {
    idle,
    running,
    failed,
    stopped,
};

// Agent execution result
pub const AgentResult = struct {
    success: bool,
    message: []const u8,
    data: ?[]const u8,
};

// Agent manager for orchestrating multiple agents
pub const AgentManager = struct {
    const Self = @This();
    
    agents: std.ArrayList(*Agent),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .agents = std.ArrayList(*Agent).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.agents.deinit();
    }
    
    pub fn registerAgent(self: *Self, agent: *Agent) !void {
        try self.agents.append(agent);
        try agent.initialize(agent, self.allocator);
    }
    
    pub fn executeCommand(self: *Self, agent_type: AgentType, command: []const u8, args: []const []const u8) !AgentResult {
        for (self.agents.items) |agent| {
            if (agent.agent_type == agent_type) {
                return agent.run(command, args);
            }
        }
        return AgentResult{ .success = false, .message = "Agent not found", .data = null };
    }
    
    pub fn listAgents(self: *Self) void {
        print("Registered Agents:\n");
        for (self.agents.items) |agent| {
            print("  {} - {} v{}\n", .{ agent.agent_type, agent.name, agent.version });
        }
    }
};

// Export agent types
pub const blockchain = @import("blockchain.zig");
pub const smartcontract = @import("smartcontract.zig");
pub const network = @import("network.zig");
pub const security = @import("security.zig");