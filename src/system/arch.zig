const std = @import("std");

/// Arch Linux specific system integration
pub const ArchSystem = struct {
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        _ = self;
    }
    
    /// Check if running on Arch Linux
    pub fn isArchLinux() bool {
        // Check for Arch-specific files
        const arch_files = [_][]const u8{
            "/etc/arch-release",
            "/etc/pacman.conf",
            "/usr/bin/pacman",
        };
        
        for (arch_files) |file| {
            std.fs.accessAbsolute(file, .{}) catch continue;
            return true;
        }
        
        return false;
    }
    
    /// Get system information
    pub fn getSystemInfo(self: *Self) !SystemInfo {
        const info = SystemInfo{
            .kernel_version = try self.getKernelVersion(),
            .desktop_environment = try self.getDesktopEnvironment(),
            .gpu_info = try self.getGPUInfo(),
            .cpu_info = try self.getCPUInfo(),
            .memory_info = try self.getMemoryInfo(),
            .arch_packages = try self.getInstalledPackages(),
        };
        
        return info;
    }
    
    /// Check for system updates
    pub fn checkUpdates(self: *Self) ![]PackageUpdate {
        var updates = std.ArrayList(PackageUpdate){};
        defer updates.deinit(self.allocator);
        
        // Run pacman -Qu to check for updates
        var child = std.process.Child.init(&[_][]const u8{ "pacman", "-Qu" }, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        
        try child.spawn();
        
        const stdout = try child.stdout.?.reader().readAllAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(stdout);
        
        const stderr = try child.stderr.?.reader().readAllAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(stderr);
        
        const exit_code = try child.wait();
        
        if (exit_code != .Exited or exit_code.Exited != 0) {
            std.log.warn("pacman -Qu failed: {s}", .{stderr});
            return updates.toOwnedSlice(self.allocator);
        }
        
        // Parse pacman output
        var lines = std.mem.split(u8, stdout, "\n");
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            
            var parts = std.mem.split(u8, line, " ");
            const package_name = parts.next() orelse continue;
            const old_version = parts.next() orelse continue;
            const arrow = parts.next() orelse continue;
            const new_version = parts.next() orelse continue;
            
            if (std.mem.eql(u8, arrow, "->")) {
                try updates.append(self.allocator, PackageUpdate{
                    .name = try self.allocator.dupe(u8, package_name),
                    .old_version = try self.allocator.dupe(u8, old_version),
                    .new_version = try self.allocator.dupe(u8, new_version),
                });
            }
        }
        
        return updates.toOwnedSlice(self.allocator);
    }
    
    /// Create and manage btrfs snapshots
    pub fn createSnapshot(self: *Self, name: []const u8) !void {
        // Check if btrfs is available
        if (!try self.isBtrfsAvailable()) {
            return error.BtrfsNotAvailable;
        }
        
        const snapshot_path = try std.fmt.allocPrint(self.allocator, "/.snapshots/{s}", .{name});
        defer self.allocator.free(snapshot_path);
        
        // Create snapshot using btrfs
        var child = std.process.Child.init(&[_][]const u8{
            "btrfs", "subvolume", "snapshot", "/", snapshot_path
        }, self.allocator);
        
        const exit_code = try child.spawnAndWait();
        
        if (exit_code != .Exited or exit_code.Exited != 0) {
            return error.SnapshotFailed;
        }
        
        std.log.info("Created btrfs snapshot: {s}", .{snapshot_path});
    }
    
    /// List available btrfs snapshots
    pub fn listSnapshots(self: *Self) ![][]const u8 {
        var snapshots = std.ArrayList([]const u8){};
        defer snapshots.deinit(self.allocator);
        
        // Check if snapshots directory exists
        const snapshots_dir = std.fs.openDirAbsolute("/.snapshots", .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) {
                return snapshots.toOwnedSlice(self.allocator);
            }
            return err;
        };
        defer snapshots_dir.close();
        
        var iterator = snapshots_dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind == .directory) {
                try snapshots.append(self.allocator, try self.allocator.dupe(u8, entry.name));
            }
        }
        
        return snapshots.toOwnedSlice(self.allocator);
    }
    
    /// Delete a btrfs snapshot
    pub fn deleteSnapshot(self: *Self, name: []const u8) !void {
        const snapshot_path = try std.fmt.allocPrint(self.allocator, "/.snapshots/{s}", .{name});
        defer self.allocator.free(snapshot_path);
        
        // Delete snapshot using btrfs
        var child = std.process.Child.init(&[_][]const u8{
            "btrfs", "subvolume", "delete", snapshot_path
        }, self.allocator);
        
        const exit_code = try child.spawnAndWait();
        
        if (exit_code != .Exited or exit_code.Exited != 0) {
            return error.SnapshotDeleteFailed;
        }
        
        std.log.info("Deleted btrfs snapshot: {s}", .{snapshot_path});
    }
    
    /// Check system maintenance needs
    pub fn checkMaintenance(self: *Self) !MaintenanceInfo {
        const info = MaintenanceInfo{
            .orphaned_packages = try self.getOrphanedPackages(),
            .cache_size = try self.getCacheSize(),
            .log_size = try self.getLogSize(),
            .failed_services = try self.getFailedServices(),
        };
        
        return info;
    }
    
    /// Run system maintenance
    pub fn runMaintenance(self: *Self, options: MaintenanceOptions) !void {
        if (options.clean_cache) {
            try self.cleanPackageCache();
        }
        
        if (options.remove_orphans) {
            try self.removeOrphanedPackages();
        }
        
        if (options.clean_logs) {
            try self.cleanSystemLogs();
        }
        
        if (options.update_system) {
            try self.updateSystem();
        }
    }
    
    /// Get GPU information for potential eGPU support
    pub fn getGPUInfo(self: *Self) !GPUInfo {
        var gpu_info = GPUInfo{
            .cards = std.ArrayList(GPUCard){},
            .has_egpu = false,
        };
        
        // Check for GPU devices
        const gpu_dir = std.fs.openDirAbsolute("/sys/class/drm", .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) {
                return gpu_info;
            }
            return err;
        };
        defer gpu_dir.close();
        
        var iterator = gpu_dir.iterate();
        while (try iterator.next()) |entry| {
            if (std.mem.startsWith(u8, entry.name, "card")) {
                // Read GPU information
                const vendor_path = try std.fmt.allocPrint(self.allocator, "/sys/class/drm/{s}/device/vendor", .{entry.name});
                defer self.allocator.free(vendor_path);
                
                const vendor_file = std.fs.openFileAbsolute(vendor_path, .{}) catch continue;
                defer vendor_file.close();
                
                const vendor_id = try vendor_file.reader().readAllAlloc(self.allocator, 32);
                defer self.allocator.free(vendor_id);
                
                const card = GPUCard{
                    .name = try self.allocator.dupe(u8, entry.name),
                    .vendor_id = try self.allocator.dupe(u8, std.mem.trim(u8, vendor_id, " \n\t")),
                    .is_external = try self.isExternalGPU(entry.name),
                };
                
                try gpu_info.cards.append(self.allocator, card);
                
                if (card.is_external) {
                    gpu_info.has_egpu = true;
                }
            }
        }
        
        return gpu_info;
    }
    
    // Helper functions
    fn getKernelVersion(self: *Self) ![]const u8 {
        const version_file = std.fs.openFileAbsolute("/proc/version", .{}) catch |err| {
            std.log.warn("Failed to read kernel version: {}", .{err});
            return try self.allocator.dupe(u8, "unknown");
        };
        defer version_file.close();
        
        const content = try version_file.reader().readAllAlloc(self.allocator, 1024);
        defer self.allocator.free(content);
        
        // Extract version from "Linux version X.X.X..."
        const version_start = std.mem.indexOf(u8, content, "Linux version ") orelse return try self.allocator.dupe(u8, "unknown");
        const version_part = content[version_start + 14..];
        const version_end = std.mem.indexOf(u8, version_part, " ") orelse version_part.len;
        
        return try self.allocator.dupe(u8, version_part[0..version_end]);
    }
    
    fn getDesktopEnvironment(self: *Self) ![]const u8 {
        const de_env_vars = [_][]const u8{
            "KDE_FULL_SESSION",
            "GNOME_DESKTOP_SESSION_ID",
            "XDG_CURRENT_DESKTOP",
            "DESKTOP_SESSION",
        };
        
        for (de_env_vars) |env_var| {
            if (std.process.getEnvVarOwned(self.allocator, env_var)) |value| {
                return value;
            } else |_| {
                continue;
            }
        }
        
        return try self.allocator.dupe(u8, "unknown");
    }
    
    fn getCPUInfo(self: *Self) !CPUInfo {
        const cpuinfo_file = std.fs.openFileAbsolute("/proc/cpuinfo", .{}) catch |err| {
            std.log.warn("Failed to read CPU info: {}", .{err});
            return CPUInfo{
                .model = try self.allocator.dupe(u8, "unknown"),
                .cores = 0,
                .frequency = 0,
            };
        };
        defer cpuinfo_file.close();
        
        const content = try cpuinfo_file.reader().readAllAlloc(self.allocator, 8192);
        defer self.allocator.free(content);
        
        var model: []const u8 = "unknown";
        var cores: u32 = 0;
        var frequency: u32 = 0;
        
        var lines = std.mem.split(u8, content, "\n");
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "model name")) {
                const colon_pos = std.mem.indexOf(u8, line, ":") orelse continue;
                model = try self.allocator.dupe(u8, std.mem.trim(u8, line[colon_pos + 1..], " \t"));
            } else if (std.mem.startsWith(u8, line, "processor")) {
                cores += 1;
            } else if (std.mem.startsWith(u8, line, "cpu MHz")) {
                const colon_pos = std.mem.indexOf(u8, line, ":") orelse continue;
                const freq_str = std.mem.trim(u8, line[colon_pos + 1..], " \t");
                frequency = std.fmt.parseInt(u32, freq_str, 10) catch 0;
            }
        }
        
        return CPUInfo{
            .model = model,
            .cores = cores,
            .frequency = frequency,
        };
    }
    
    fn getMemoryInfo(self: *Self) !MemoryInfo {
        const meminfo_file = std.fs.openFileAbsolute("/proc/meminfo", .{}) catch |err| {
            std.log.warn("Failed to read memory info: {}", .{err});
            return MemoryInfo{
                .total = 0,
                .available = 0,
                .used = 0,
            };
        };
        defer meminfo_file.close();
        
        const content = try meminfo_file.reader().readAllAlloc(self.allocator, 4096);
        defer self.allocator.free(content);
        
        var total: u64 = 0;
        var available: u64 = 0;
        
        var lines = std.mem.split(u8, content, "\n");
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "MemTotal:")) {
                const colon_pos = std.mem.indexOf(u8, line, ":") orelse continue;
                const value_str = std.mem.trim(u8, line[colon_pos + 1..], " \t");
                const kb_pos = std.mem.indexOf(u8, value_str, " kB") orelse value_str.len;
                total = std.fmt.parseInt(u64, value_str[0..kb_pos], 10) catch 0;
                total *= 1024; // Convert to bytes
            } else if (std.mem.startsWith(u8, line, "MemAvailable:")) {
                const colon_pos = std.mem.indexOf(u8, line, ":") orelse continue;
                const value_str = std.mem.trim(u8, line[colon_pos + 1..], " \t");
                const kb_pos = std.mem.indexOf(u8, value_str, " kB") orelse value_str.len;
                available = std.fmt.parseInt(u64, value_str[0..kb_pos], 10) catch 0;
                available *= 1024; // Convert to bytes
            }
        }
        
        return MemoryInfo{
            .total = total,
            .available = available,
            .used = total - available,
        };
    }
    
    fn getInstalledPackages(self: *Self) ![][]const u8 {
        var packages = std.ArrayList([]const u8){};
        defer packages.deinit(self.allocator);
        
        var child = std.process.Child.init(&[_][]const u8{ "pacman", "-Q" }, self.allocator);
        child.stdout_behavior = .Pipe;
        
        try child.spawn();
        
        const stdout = try child.stdout.?.reader().readAllAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(stdout);
        
        _ = try child.wait();
        
        var lines = std.mem.split(u8, stdout, "\n");
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            
            var parts = std.mem.split(u8, line, " ");
            const package_name = parts.next() orelse continue;
            try packages.append(self.allocator, try self.allocator.dupe(u8, package_name));
        }
        
        return packages.toOwnedSlice(self.allocator);
    }
    
    fn isBtrfsAvailable(self: *Self) !bool {
        // Check if btrfs command is available
        var child = std.process.Child.init(&[_][]const u8{ "which", "btrfs" }, self.allocator);
        const exit_code = try child.spawnAndWait();
        
        return exit_code == .Exited and exit_code.Exited == 0;
    }
    
    fn isExternalGPU(self: *Self, card_name: []const u8) !bool {
        // Check if GPU is connected via Thunderbolt (eGPU)
        const device_path = try std.fmt.allocPrint(self.allocator, "/sys/class/drm/{s}/device/", .{card_name});
        defer self.allocator.free(device_path);
        
        // Follow symlinks to check if device is on Thunderbolt bus
        var buffer: [1024]u8 = undefined;
        const real_path = std.fs.readLinkAbsolute(device_path, &buffer) catch return false;
        
        return std.mem.indexOf(u8, real_path, "thunderbolt") != null;
    }
    
    fn getOrphanedPackages(self: *Self) ![][]const u8 {
        var packages = std.ArrayList([]const u8){};
        defer packages.deinit(self.allocator);
        
        var child = std.process.Child.init(&[_][]const u8{ "pacman", "-Qtdq" }, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        
        try child.spawn();
        
        const stdout = try child.stdout.?.reader().readAllAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(stdout);
        
        _ = try child.wait();
        
        var lines = std.mem.split(u8, stdout, "\n");
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            try packages.append(self.allocator, try self.allocator.dupe(u8, line));
        }
        
        return packages.toOwnedSlice(self.allocator);
    }
    
    fn getCacheSize(self: *Self) !u64 {
        _ = self;
        
        const cache_dir = std.fs.openDirAbsolute("/var/cache/pacman/pkg", .{ .iterate = true }) catch return 0;
        defer cache_dir.close();
        
        var total_size: u64 = 0;
        var iterator = cache_dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind == .file) {
                const stat = cache_dir.statFile(entry.name) catch continue;
                total_size += stat.size;
            }
        }
        
        return total_size;
    }
    
    fn getLogSize(self: *Self) !u64 {
        _ = self;
        
        const log_dir = std.fs.openDirAbsolute("/var/log", .{ .iterate = true }) catch return 0;
        defer log_dir.close();
        
        var total_size: u64 = 0;
        var iterator = log_dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind == .file) {
                const stat = log_dir.statFile(entry.name) catch continue;
                total_size += stat.size;
            }
        }
        
        return total_size;
    }
    
    fn getFailedServices(self: *Self) ![][]const u8 {
        var services = std.ArrayList([]const u8){};
        defer services.deinit(self.allocator);
        
        var child = std.process.Child.init(&[_][]const u8{ "systemctl", "--failed", "--no-legend" }, self.allocator);
        child.stdout_behavior = .Pipe;
        
        try child.spawn();
        
        const stdout = try child.stdout.?.reader().readAllAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(stdout);
        
        _ = try child.wait();
        
        var lines = std.mem.split(u8, stdout, "\n");
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            
            var parts = std.mem.split(u8, line, " ");
            const service_name = parts.next() orelse continue;
            try services.append(self.allocator, try self.allocator.dupe(u8, service_name));
        }
        
        return services.toOwnedSlice(self.allocator);
    }
    
    fn cleanPackageCache(self: *Self) !void {
        var child = std.process.Child.init(&[_][]const u8{ "pacman", "-Sc", "--noconfirm" }, self.allocator);
        _ = try child.spawnAndWait();
    }
    
    fn removeOrphanedPackages(self: *Self) !void {
        const orphans = try self.getOrphanedPackages();
        defer {
            for (orphans) |pkg| {
                self.allocator.free(pkg);
            }
            self.allocator.free(orphans);
        }
        
        if (orphans.len == 0) return;
        
        var args = std.ArrayList([]const u8){};
        defer args.deinit(self.allocator);
        
        try args.appendSlice(self.allocator, &[_][]const u8{ "pacman", "-Rns", "--noconfirm" });
        try args.appendSlice(self.allocator, orphans);
        
        var child = std.process.Child.init(args.items, self.allocator);
        _ = try child.spawnAndWait();
    }
    
    fn cleanSystemLogs(self: *Self) !void {
        var child = std.process.Child.init(&[_][]const u8{ "journalctl", "--vacuum-time=1month" }, self.allocator);
        _ = try child.spawnAndWait();
    }
    
    fn updateSystem(self: *Self) !void {
        var child = std.process.Child.init(&[_][]const u8{ "pacman", "-Syu", "--noconfirm" }, self.allocator);
        _ = try child.spawnAndWait();
    }
};

// Data structures
pub const SystemInfo = struct {
    kernel_version: []const u8,
    desktop_environment: []const u8,
    gpu_info: GPUInfo,
    cpu_info: CPUInfo,
    memory_info: MemoryInfo,
    arch_packages: [][]const u8,
    
    pub fn deinit(self: *SystemInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.kernel_version);
        allocator.free(self.desktop_environment);
        self.gpu_info.deinit(allocator);
        self.cpu_info.deinit(allocator);
        
        for (self.arch_packages) |pkg| {
            allocator.free(pkg);
        }
        allocator.free(self.arch_packages);
    }
};

pub const GPUInfo = struct {
    cards: std.ArrayList(GPUCard),
    has_egpu: bool,
    
    pub fn deinit(self: *GPUInfo, allocator: std.mem.Allocator) void {
        for (self.cards.items) |*card| {
            card.deinit(allocator);
        }
        self.cards.deinit(allocator);
    }
};

pub const GPUCard = struct {
    name: []const u8,
    vendor_id: []const u8,
    is_external: bool,
    
    pub fn deinit(self: *GPUCard, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.vendor_id);
    }
};

pub const CPUInfo = struct {
    model: []const u8,
    cores: u32,
    frequency: u32,
    
    pub fn deinit(self: *CPUInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.model);
    }
};

pub const MemoryInfo = struct {
    total: u64,
    available: u64,
    used: u64,
};

pub const PackageUpdate = struct {
    name: []const u8,
    old_version: []const u8,
    new_version: []const u8,
    
    pub fn deinit(self: *PackageUpdate, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.old_version);
        allocator.free(self.new_version);
    }
};

pub const MaintenanceInfo = struct {
    orphaned_packages: [][]const u8,
    cache_size: u64,
    log_size: u64,
    failed_services: [][]const u8,
    
    pub fn deinit(self: *MaintenanceInfo, allocator: std.mem.Allocator) void {
        for (self.orphaned_packages) |pkg| {
            allocator.free(pkg);
        }
        allocator.free(self.orphaned_packages);
        
        for (self.failed_services) |service| {
            allocator.free(service);
        }
        allocator.free(self.failed_services);
    }
};

pub const MaintenanceOptions = struct {
    clean_cache: bool = false,
    remove_orphans: bool = false,
    clean_logs: bool = false,
    update_system: bool = false,
};