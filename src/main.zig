const builtin = @import("builtin");

// 覆盖标准库的 panic 实现，内核模式不能使用它
pub fn panic(msg: []const u8, error_return_trace: ?*anyopaque, ret_addr: ?usize) noreturn {
    _ = msg;
    _ = error_return_trace;
    _ = ret_addr;
    while (true) {}
}

// 覆盖标准库的 assert 实现，内核模式不能使用它
pub fn assert(ok: bool) void {
    if (!ok) while (true) {};
}

// 导入 WDK 头文件，注意必须禁用 libc
const wdk = @cImport({
    @cDefine("_AMD64_", "1");
    @cDefine("_KERNEL_MODE", "1");
    @cInclude("wdm.h");
    @cInclude("ntddk.h");
    @cInclude("portcls.h"); // PortCls 音频框架
    @cInclude("ks.h");
    @cInclude("ksmedia.h");
});

// 全局状态（仅保存 PortCls 原始卸载函数）
var g_pc_unload_routine: ?wdk.PDRIVER_UNLOAD = null;

// 主驱动入口
export fn DriverEntry(driver: wdk.PDRIVER_OBJECT, registry: *const wdk.UNICODE_STRING) callconv(.c) wdk.NTSTATUS {
    _ = wdk.DbgPrintEx(wdk.DPFLTR_IHVDRIVER_ID, wdk.DPFLTR_ERROR_LEVEL, "DriverEntry called\n");

    // 初始化 PortCls 音频适配器驱动
    const status = wdk.PcInitializeAdapterDriver(driver, @constCast(registry), AddDevice);
    if (status != 0) {
        _ = wdk.DbgPrintEx(wdk.DPFLTR_IHVDRIVER_ID, wdk.DPFLTR_ERROR_LEVEL, "PcInitializeAdapterDriver failed: 0x%x\n", status);
        return status;
    }

    // 设置 PNP 处理函数（必须）
    driver.*.MajorFunction[wdk.IRP_MJ_PNP] = PnpHandler;

    // 保存 PortCls 的原始卸载函数，并用我们的替换
    g_pc_unload_routine = driver.*.DriverUnload;
    driver.*.DriverUnload = DriverUnload;

    _ = wdk.DbgPrintEx(wdk.DPFLTR_IHVDRIVER_ID, wdk.DPFLTR_ERROR_LEVEL, "DriverEntry completed\n");
    return wdk.STATUS_SUCCESS;
}

// 添加设备回调（PortCls 要求）
export fn AddDevice(driver: wdk.PDRIVER_OBJECT, pdo: wdk.PDEVICE_OBJECT) callconv(.c) wdk.NTSTATUS {
    _ = wdk.DbgPrintEx(wdk.DPFLTR_IHVDRIVER_ID, wdk.DPFLTR_ERROR_LEVEL, "AddDevice called\n");
    // 预留两个音频对象（扬声器 + 麦克风）
    const status = wdk.PcAddAdapterDevice(driver, pdo, StartDevice, 2, 0);
    if (status != 0) {
        _ = wdk.DbgPrintEx(wdk.DPFLTR_IHVDRIVER_ID, wdk.DPFLTR_ERROR_LEVEL, "PcAddAdapterDevice failed: 0x%x\n", status);
    }
    return status;
}

// 设备启动回调（PortCls 调用）
export fn StartDevice(device: wdk.PDEVICE_OBJECT, irp: wdk.PIRP, resource_list: wdk.PRESOURCELIST) callconv(.c) wdk.NTSTATUS {
    _ = device;
    _ = irp;
    _ = resource_list;
    _ = wdk.DbgPrintEx(wdk.DPFLTR_IHVDRIVER_ID, wdk.DPFLTR_ERROR_LEVEL, "StartDevice called\n");
    return wdk.STATUS_SUCCESS;
}

// 最小化 PNP 处理：仅完成 IRP，返回成功
export fn PnpHandler(device: wdk.PDEVICE_OBJECT, irp: wdk.PIRP) callconv(.c) wdk.NTSTATUS {
    _ = device;
    irp.*.IoStatus.unnamed_0.Status = 0;
    irp.*.IoStatus.Information = 0;
    wdk.IoCompleteRequest(irp, wdk.IO_NO_INCREMENT);
    return wdk.STATUS_SUCCESS;
}

// 驱动卸载
export fn DriverUnload(driver: wdk.PDRIVER_OBJECT) callconv(.c) void {
    _ = wdk.DbgPrintEx(wdk.DPFLTR_IHVDRIVER_ID, wdk.DPFLTR_ERROR_LEVEL, "DriverUnload called\n");
    if (g_pc_unload_routine) |unload| unload.?(driver);
}
