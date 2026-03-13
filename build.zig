const std = @import("std");

pub fn build(b: *std.Build) !void {
    // 定义命令行选项
    const wdk_inc_km = b.option([]const u8, "wdk-inc-km", "Path to WDK km include directory") orelse {
        std.debug.print("\x1b[31mError: Missing required option: -Dwdk-inc-km\x1b[0m\n", .{});
        std.debug.print("\x1b[33mPlease run .\\build.ps1 to build the driver.\x1b[0m\n", .{});
        return error.MissingRequiredOption;
    };
    const wdk_inc_shared = b.option([]const u8, "wdk-inc-shared", "Path to WDK shared include directory") orelse {
        std.debug.print("\x1b[31mError: Missing required option: -Dwdk-inc-shared\x1b[0m\n", .{});
        std.debug.print("\x1b[33mPlease run .\\build.ps1 to build the driver.\x1b[0m\n", .{});
        return error.MissingRequiredOption;
    };
    const wdk_inc_ucrt = b.option([]const u8, "wdk-inc-ucrt", "Path to WDK ucrt include directory") orelse {
        std.debug.print("\x1b[31mError: Missing required option: -Dwdk-inc-ucrt\x1b[0m\n", .{});
        std.debug.print("\x1b[33mPlease run .\\build.ps1 to build the driver.\x1b[0m\n", .{});
        return error.MissingRequiredOption;
    };
    const vs_inc = b.option([]const u8, "vs-inc", "Path to Visual Studio MSVC include directory") orelse {
        std.debug.print("\x1b[31mError: Missing required option: -Dvs-inc\x1b[0m\n", .{});
        std.debug.print("\x1b[33mPlease run .\\build.ps1 to build the driver.\x1b[0m\n", .{});
        return error.MissingRequiredOption;
    };
    const wdk_lib = b.option([]const u8, "wdk-lib", "Path to WDK library directory (km/x64)") orelse {
        std.debug.print("\x1b[31mError: Missing required option: -Dwdk-lib\x1b[0m\n", .{});
        std.debug.print("\x1b[33mPlease run .\\build.ps1 to build the driver.\x1b[0m\n", .{});
        return error.MissingRequiredOption;
    };

    const target = b.resolveTargetQuery(.{
        .os_tag = .windows,
        .abi = .msvc,
        .cpu_arch = .x86_64,
    });
    const optimize = b.standardOptimizeOption(.{});

    // 创建模块
    const module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = false,
        .link_libcpp = false,
        .single_threaded = true,
        .strip = true,
        .unwind_tables = .none,
        .code_model = .kernel,
        .stack_protector = false,
        .stack_check = false,
        .sanitize_c = .off,
        .sanitize_thread = false,
        .fuzz = false,
        .valgrind = false,
        .pic = true,
        .red_zone = false,
        .omit_frame_pointer = true,
        .error_tracing = false,
        .no_builtin = true,
    });

    // 添加包含路径
    module.addIncludePath(.{ .cwd_relative = wdk_inc_km });
    module.addIncludePath(.{ .cwd_relative = wdk_inc_shared });
    module.addIncludePath(.{ .cwd_relative = wdk_inc_ucrt });
    module.addIncludePath(.{ .cwd_relative = vs_inc });

    // 编译为目标文件
    const obj = b.addObject(.{
        .name = "wdk-zig",
        .root_module = module,
    });

    // 安装目标文件
    const install_obj = b.addInstallFile(obj.getEmittedBin(), "obj/wdk-zig.obj");
    install_obj.step.dependOn(&obj.step);

    // 创建输出目录
    const mk_driver = b.addSystemCommand(&.{ "cmd", "/c", "if not exist zig-out\\driver mkdir zig-out\\driver" });
    mk_driver.step.dependOn(&install_obj.step);

    // 链接命令
    const link_cmd = b.addSystemCommand(&.{"link.exe"});
    link_cmd.addArgs(&.{
        "/TIME",
        "/DEBUG",
        "/DRIVER",
        "/NODEFAULTLIB",
        "/NODEFAULTLIB:libucrt.lib",
        "/NODEFAULTLIB:libucrtd.lib",
        "/SUBSYSTEM:NATIVE",
        "/ENTRY:DriverEntry",
        "/NODEFAULTLIB:msvcrt.lib",
        "/OPT:REF",
        "/OPT:ICF",
        "/FORCE:MULTIPLE",
    });

    link_cmd.addArg(b.fmt("/LIBPATH:{s}", .{wdk_lib}));
    link_cmd.addArgs(&.{
        "ntoskrnl.lib",
        "hal.lib",
        "wmilib.lib",
        "portcls.lib",
        "ks.lib",
        "ksguid.lib",
    });

    // 目标文件路径
    const obj_path = b.fmt("{s}/obj/wdk-zig.obj", .{b.install_path});
    link_cmd.addArg(obj_path);

    // 输出文件
    const sys_path = b.fmt("{s}/driver/owo.sys", .{b.install_path});
    const pdb_path = b.fmt("{s}/driver/owo.pdb", .{b.install_path});
    const map_path = b.fmt("{s}/driver/owo.map", .{b.install_path});

    link_cmd.addArgs(&.{b.fmt("/OUT:{s}", .{sys_path})});
    link_cmd.addArgs(&.{b.fmt("/PDB:{s}", .{pdb_path})});
    link_cmd.addArgs(&.{b.fmt("/MAP:{s}", .{map_path})});

    link_cmd.step.dependOn(&mk_driver.step);

    // 定义构建步骤
    const driver_step = b.step("driver", "Build the Windows driver");
    driver_step.dependOn(&link_cmd.step);
    b.default_step = driver_step;
}
