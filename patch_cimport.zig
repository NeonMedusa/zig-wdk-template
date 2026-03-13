const std = @import("std");

// ==================== 各版本补丁定义 ====================
const patches_26100_6584 = [_]Patch{
    .{ .file = "wdm.h", .line = 18754, .name = "TimerAbsoluteWake", .replacement = 
    \\packed struct {
    \\    Absolute: u1,
    \\    Wake: u1,
    \\    EncodedTolerableDelay: u6,
    \\};
    \\
    },
    .{ .file = "wdm.h", .line = 18767, .name = "TimerMisc", .replacement = 
    \\packed struct {
    \\    Index: u6,
    \\    Inserted: u1,
    \\    Expired: u1,
    \\};
    \\
    },
    .{ .file = "wdm.h", .line = 18787, .name = "Timer2Flags", .replacement = 
    \\packed struct {
    \\    Timer2Inserted: u1,
    \\    Timer2Expiring: u1,
    \\    Timer2CancelPending: u1,
    \\    Timer2SetPending: u1,
    \\    Timer2Running: u1,
    \\    Timer2Disabled: u1,
    \\    Timer2ReservedFlags: u2,
    \\};
    \\
    },
    .{ .file = "wdm.h", .line = 18806, .name = "QueueControl", .replacement = 
    \\packed struct {
    \\    Abandoned: u1,
    \\    DisableIncrement: u1,
    \\    QueueReservedControlFlags: u6,
    \\};
    \\
    },
    .{ .file = "wdm.h", .line = 18823, .name = "ThreadControl", .replacement = 
    \\packed struct {
    \\    CycleProfiling: u1,
    \\    CounterProfiling: u1,
    \\    GroupScheduling: u1,
    \\    AffinitySet: u1,
    \\    Tagged: u1,
    \\    EnergyProfiling: u1,
    \\    SchedulerAssist: u1,
    \\    ThreadReservedControlFlags: u1,
    \\};
    \\
    },
    .{ .file = "wdm.h", .line = 18850, .name = "DebugActive", .replacement = 
    \\packed struct {
    \\    ActiveDR7: u1,
    \\    Instrumented: u1,
    \\    Minimal: u1,
    \\    Reserved4: u2,
    \\    AltSyscall: u1,
    \\    Emulation: u1,
    \\    Reserved5: u1,
    \\};
    \\
    },
    .{ .file = "wdm.h", .line = 11127, .name = "SystemPowerState", .replacement = 
    \\packed struct {
    \\    Reserved1: u8,
    \\    TargetSystemState: u4,
    \\    EffectiveSystemState: u4,
    \\    CurrentSystemState: u4,
    \\    IgnoreHibernationPath: u1,
    \\    PseudoTransition: u1,
    \\    KernelSoftReboot: u1,
    \\    DirectedDripsTransition: u1,
    \\    Reserved2: u8,
    \\};
    \\
    },
    .{ .file = "wdm.h", .line = 31879, .name = "DmaWait", .replacement = 
    \\extern struct {
    \\    DmaWaitEntry: LIST_ENTRY,
    \\    NumberOfChannels: ULONG,
    \\    _bitfield: packed struct {
    \\        SyncCallback: u1,
    \\        DmaContext: u1,
    \\        ZeroMapRegisters: u1,
    \\        Reserved: u9,
    \\        NumberOfRemapPages: u20,
    \\    },
    \\};
    \\
    },
    .{ .file = "wdm.h", .line = 22888, .name = "DeviceQueueReserved", .replacement = 
    \\packed struct {
    \\    Reserved: i8,
    \\    Hint: i56,
    \\};
    \\
    },
    .{ .file = "wdm.h", .line = 27091, .name = "IoPriority", .replacement = 
    \\packed struct {
    \\    IoPriorityBoosted: u1,
    \\    OwnerReferenced: u1,
    \\    IoQoSPriorityBoosted: u1,
    \\    OwnerCount: u29,
    \\};
    \\
    },
};

// 可在此添加其他版本的补丁，例如：
// const patches_19041_1145 = [_]Patch{
//     .{ .file = "wdm.h", .line = 12345, .name = "SomeStruct", .replacement = ... },
// };

/// 根据版本获取补丁列表
fn getPatchesForVersion(version: []const u8) ?[]const Patch {
    const VersionEntry = struct { version: []const u8, patches: []const Patch };
    const entries = [_]VersionEntry{
        .{ .version = "10.0.26100.6584", .patches = &patches_26100_6584 },
        // 添加其他版本映射，例如：
        // .{ .version = "10.0.19041.1145", .patches = &patches_19041_1145 },
    };
    for (entries) |entry| {
        if (std.mem.eql(u8, version, entry.version)) {
            return entry.patches;
        }
    }
    return null;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <path-to-cimport.zig> [wdk-version]\n", .{args[0]});
        std.debug.print("Example: {s} .zig-cache/o/abc123/cimport.zig 10.0.26100.0\n", .{args[0]});
        return error.MissingPath;
    }

    const cimport_path = args[1];
    const wdk_version = if (args.len >= 3) args[2] else "10.0.26100.0";

    std.debug.print("=== Starting patch_cimport.zig ===\n", .{});
    std.debug.print("Patching: {s} (WDK version: {s})\n", .{ cimport_path, wdk_version });

    const content = try readFileWithRetry(alloc, cimport_path, 3);
    defer alloc.free(content);
    std.debug.print("Original file size: {d} bytes\n", .{content.len});

    const patches = getPatchesForVersion(wdk_version) orelse {
        std.debug.print("Warning: No patches defined for WDK version {s}, skipping.\n", .{wdk_version});
        return;
    };

    const fixed = try patchByLineNumber(alloc, content, patches);
    defer alloc.free(fixed);

    const backup_path = try std.fmt.allocPrint(alloc, "{s}.bak", .{cimport_path});
    defer alloc.free(backup_path);
    try writeFileWithRetry(backup_path, content, 3);

    try writeFileWithRetry(cimport_path, fixed, 3);

    std.debug.print("Successfully patched {s}\n", .{cimport_path});
    std.debug.print("=== patch_cimport.zig completed ===\n", .{});
}

fn readFileWithRetry(alloc: std.mem.Allocator, path: []const u8, max_retries: u32) ![]u8 {
    var retries: u32 = 0;
    while (retries < max_retries) {
        retries += 1;
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            if (retries == max_retries) return err;
            std.debug.print("Retry {d} opening file (error: {any})\n", .{ retries, err });
            std.Thread.sleep(100 * std.time.ns_per_ms);
            continue;
        };
        defer file.close();
        const content = file.readToEndAlloc(alloc, 10 * 1024 * 1024) catch |err| {
            if (retries == max_retries) return err;
            std.Thread.sleep(100 * std.time.ns_per_ms);
            continue;
        };
        return content;
    }
    return error.MaxRetriesExceeded;
}

fn writeFileWithRetry(path: []const u8, data: []const u8, max_retries: u32) !void {
    var retries: u32 = 0;
    while (retries < max_retries) {
        retries += 1;
        std.fs.cwd().writeFile(.{
            .sub_path = path,
            .data = data,
        }) catch |err| {
            if (retries == max_retries) return err;
            std.debug.print("Retry {d} writing file (error: {any})\n", .{ retries, err });
            std.Thread.sleep(100 * std.time.ns_per_ms);
            continue;
        };
        return;
    }
    return error.MaxRetriesExceeded;
}

const Patch = struct {
    file: []const u8,
    line: u32,
    name: []const u8,
    replacement: []const u8,
};

fn patchByLineNumber(alloc: std.mem.Allocator, content: []const u8, patches: []const Patch) ![]u8 {
    const result = try alloc.dupe(u8, content);
    errdefer alloc.free(result);

    var lines = std.mem.splitScalar(u8, result, '\n');
    var line_buf = std.ArrayList(u8){};
    defer line_buf.deinit(alloc);

    var current_line: usize = 0;
    var pending_patch: ?struct { line: u32, replacement: []const u8 } = null;
    var patched_count: usize = 0;

    while (lines.next()) |line| {
        current_line += 1;

        if (line.len >= 2 and line[0] == '/' and line[1] == '/') {
            if (extractFileAndLineNumber(line)) |info| {
                for (patches) |patch| {
                    if (std.mem.endsWith(u8, info.file, patch.file) and patch.line == info.line) {
                        std.debug.print("Found {s}:{d} ({s}) at cimport line {d}\n", .{ patch.file, patch.line, patch.name, current_line });
                        pending_patch = .{
                            .line = info.line,
                            .replacement = patch.replacement,
                        };
                        break;
                    }
                }
            }
        }

        if (pending_patch) |patch| {
            if (std.mem.indexOf(u8, line, "const struct_unnamed_") != null and
                std.mem.indexOf(u8, line, "= opaque {};") != null)
            {
                const start = std.mem.indexOf(u8, line, "struct_unnamed_").?;
                const end = std.mem.indexOf(u8, line, "=").?;
                var struct_name_end = end - 1;
                while (struct_name_end > start and line[struct_name_end] == ' ') {
                    struct_name_end -= 1;
                }
                const struct_name = line[start .. struct_name_end + 1];

                std.debug.print("  Replacing at line {d}: {s} with packed struct\n", .{ current_line, line });

                const new_def = try std.fmt.allocPrint(alloc, "const {s} = {s}", .{ struct_name, patch.replacement });
                defer alloc.free(new_def);

                try line_buf.appendSlice(alloc, new_def);
                pending_patch = null;
                patched_count += 1;
                continue;
            }
        }

        try line_buf.appendSlice(alloc, line);
        try line_buf.append(alloc, '\n');
    }

    std.debug.print("Patched {d} structures\n", .{patched_count});
    const output = try line_buf.toOwnedSlice(alloc);
    alloc.free(result);
    return output;
}

fn extractFileAndLineNumber(comment: []const u8) ?struct { file: []const u8, line: u32 } {
    var last_sep: usize = 0;
    for (comment, 0..) |ch, i| {
        if (ch == '/' or ch == '\\') {
            last_sep = i;
        }
    }

    const file_start = last_sep + 1;
    var file_end = file_start;
    while (file_end < comment.len and comment[file_end] != ':') {
        file_end += 1;
    }
    if (file_end <= file_start) return null;
    const file = comment[file_start..file_end];

    const line_start = file_end + 1;
    var line_end = line_start;
    while (line_end < comment.len and comment[line_end] != ':') {
        line_end += 1;
    }
    if (line_end <= line_start) return null;

    var line: u32 = 0;
    for (comment[line_start..line_end]) |ch| {
        if (ch < '0' or ch > '9') return null;
        line = line * 10 + (ch - '0');
    }

    return .{ .file = file, .line = line };
}
