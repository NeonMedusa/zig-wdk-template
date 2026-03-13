# 🌀 ZIG WDK Template

> 一个开发虚拟音频输出设备失败的副产品，用非常抽象的手段让 Zig 调用 WDK 成为可能。

## 🤔 这是什么？

这是一个 **Zig + WDK** 的 Windows 驱动开发模板，**但它不是一个正经的项目**，是一个失败项目的副产品。

原本我想用 Zig 开发一个虚拟音频输出设备，用于另一个我自己弄的音频路由软件，结果发现低估了这个任务的复杂度，现在已经打算放弃了。不过在折腾的过程中，至少把 Zig 调用 WDK 的环境配好了，还写了一个非常**抽象**的 `cimport.zig` 补丁工具来解决 Zig 翻译 C 头文件时的位域问题。

所以这个项目存在的意义就是：**如果你也想用 Zig 折腾 Windows 驱动，可以少走一些弯路**。

## ✨ 它能做什么？

- ✅ 勉强可用的 Zig + WDK 构建环境
- ✅ 半自动 `cimport.zig` 补丁工具（解决 Zig translate-c 的位域问题）
- ✅ 可编译通过的虚拟音频驱动框架（虽然**完全没有实际功能**）
- ✅ 一个 INF 文件模板（让设备能出现在设备管理器里）

## 🎯 适用人群

这个项目**只适合喜欢折腾的人**。如果你：

- 想用 Zig 写 Windows 驱动玩玩
- 对内核开发有好奇心
- 不介意使用一些非常 hacky 的手段

## 🚀 快速开始

### 前置条件

- Windows 10/11（x64）
- Zig 0.15.2
- WDK（Windows Driver Kit）10.1.26100.6584 （必须用这个版本）
- MSVC v143（建议用这个版本）

### 配置步骤

1. **安装 WDK 10.1.26100.6584**  
   从以下两个链接中找到WDK 10.1.26100.6584，版本号一定要准确，如果用其他版本需要自己手动到patch_cimport.zig中编写补丁
   https://learn.microsoft.com/zh-cn/windows-hardware/drivers/other-wdk-downloads
   https://learn.microsoft.com/zh-cn/windows-hardware/drivers/legacy-wdk-downloads

2. **安装 MSVC v143**  
   使用Visual Studio Installer安装 https://visualstudio.microsoft.com/zh-hans/downloads/

3. **克隆项目**
   ```bash
   git clone https://github.com/yourname/zig-wdk-template.git
   cd zig-wdk-template
   ```

4. **编辑 `build.ps1`**  
   用编辑器打开 `build.ps1`，修改开头的配置区为你机器上的实际路径：
   ```powershell
   $WDK_ROOT         = "C:\Program Files (x86)\Windows Kits\10"
   $VS_MSVC_ROOT     = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207"
   $WDK_VERSION      = "10.0.26100.0"
   $WDK_FULL_VERSION = "10.0.26100.6584"
   ```

5. **运行构建脚本**
   ```powershell
   .\build.ps1
   ```
   如果一切顺利，`zig-out/driver/owo.sys` 就是生成的驱动文件。

6. **测试驱动（危险！）**  
   ⚠️ **一定要在虚拟机中进行安装和测试！** 不然系统崩崩崩文件爆爆爆。

   - 虚拟机使用 **Win11 系统**，开启**测试模式**，关闭驱动签名验证。
   - 在虚拟机中准备好以下工具：
     - **DebugView**：https://learn.microsoft.com/zh-cn/sysinternals/downloads/debugview
     - **devcon.exe**：从物理机复制 `C:\Program Files (x86)\Windows Kits\10\Tools\10.0.26100.0\x64\devcon.exe`
   - **给虚拟机创建一个检查点或备份**，一定要备份！
   - 以管理员身份运行 DebugView，将 **Capture → Capture Kernel** 勾上，这样就可以查看内核消息了。
   - 将编译好的 `owo.sys` 和 `src/owo.inf` 复制到虚拟机中，以管理员身份执行：
     ```cmd
     devcon.exe install owo.inf Root\OWO_VIRTUAL_AUDIO
     ```
   - 然后你就能在 DebugView 中看到我们程序在内核中打印出来的消息。
   - 在设备管理器 → **声音、视频和游戏控制器** 中也能看到这个没用的东西。

## 🧩 项目结构

```
zig-wdk-template/
├── build.ps1           # 主构建脚本（编辑这里配置环境路径）
├── build.zig           # Zig 构建文件（一般不需要动）
├── patch_cimport.zig   # 核心抽象工具：修复 translate-c 的位域问题
├── src/
   ├── main.zig        # 驱动入口（可修改为你自己的逻辑）
   └── owo.inf         # 驱动安装配置文件
```

## 🪄 这个抽象工具是什么？

`patch_cimport.zig` 是一个**非常抽象**的补丁工具：

1. Zig 的 `@cImport` 在翻译 WDK 头文件时，遇到 C 位域会变成 `opaque {}`
2. 第一次编译会失败，但会生成 `cimport.zig` 并报错
3. 这个工具会自动找到 `cimport.zig`，定位报错的行号
4. 根据预设的补丁表（推荐让AI编写），将 `opaque {}` 替换为正确的 `packed struct`
5. 然后重新编译，就能通过了


将来 Zig 的 translate-c 如果完善了位域支持，这个工具就会**一无是处**。但至少现在，它还挺有用的（鸡肋警告）。

## 🙏 致谢

这个项目大量参考了 **SoraTenshi** 的博客：

👉 [Writing Windows drivers in Zig](https://neoncity.dev/blog/wdk-in-zig/)

是他首先想到手动修复 `cimport.zig` 中的翻译错误，验证了用 Zig 调用 WDK 开发 Windows 驱动的可行性。本项目基本上就是将他的修复过程**半自动化**了而已。感谢他的探索与分享！

## ⚠️ 免责声明

- 这是一个**失败项目的副产品**，很多代码（包括这个meread.md文件）都由AI生成
- 驱动程序**没有任何实际功能**，只为了证明能编译通过
- 永远不要在物理机中安装和测试驱动程序！所有后果都由你自己负责

## 📜 许可证

MIT License - 随便玩，不负责。

---
