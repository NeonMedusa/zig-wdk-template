param(
    [switch]$Clean,   # Force clean cache
    [switch]$Verbose  # Show detailed output
)

Write-Host "=== Building Windows Driver with Zig ===" -ForegroundColor Cyan

# -------------------- 配置区 --------------------
# 请根据你的开发环境修改以下路径和版本
$WDK_ROOT        = "C:\Program Files (x86)\Windows Kits\10"
$VS_MSVC_ROOT    = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207"
$WDK_VERSION     = "10.0.26100.0"          # 用于路径构建（文件夹名）
$WDK_FULL_VERSION = "10.0.26100.6584"      # 完整的 WDK 版本号（用于补丁匹配）
$WDK_SHARED_VERSION = $WDK_VERSION          # 通常与 WDK_VERSION 相同
# ------------------------------------------------

# 计算具体路径
$WDK_INC_KM      = "$WDK_ROOT\Include\$WDK_VERSION\km"
$WDK_INC_SHARED  = "$WDK_ROOT\Include\$WDK_SHARED_VERSION\shared"
$WDK_INC_UCRT    = "$WDK_ROOT\Include\$WDK_SHARED_VERSION\ucrt"
$VS_INCLUDE      = "$VS_MSVC_ROOT\include"
$VS_BIN          = "$VS_MSVC_ROOT\bin\Hostx64\x64"
$WDK_LIB_PATH    = "$WDK_ROOT\Lib\$WDK_VERSION\km\x64"

# 验证必要路径是否存在
Write-Host "`n[1/4] Validating paths..." -ForegroundColor Yellow
$pathsToCheck = @(
    @{Path=$WDK_INC_KM; Desc="WDK km include"},
    @{Path=$WDK_INC_SHARED; Desc="WDK shared include"},
    @{Path=$WDK_INC_UCRT; Desc="WDK ucrt include"},
    @{Path=$VS_INCLUDE; Desc="VS include"},
    @{Path=$WDK_LIB_PATH; Desc="WDK lib path"},
    @{Path=$VS_BIN; Desc="VS bin path (link.exe location)"}
)

$allValid = $true
foreach ($item in $pathsToCheck) {
    if (Test-Path $item.Path) {
        Write-Host "  ✓ $($item.Desc)" -ForegroundColor Green
    } else {
        Write-Host "  ✗ $($item.Desc) not found at:`n    $($item.Path)" -ForegroundColor Red
        $allValid = $false
    }
}

if (-not $allValid) {
    Write-Host "`n❌ ERROR: One or more required paths are incorrect." -ForegroundColor Red
    Write-Host "Please edit this script (build.ps1) directly and update the configuration section" -ForegroundColor Magenta
    Write-Host "with the correct paths for your WDK and Visual Studio installations." -ForegroundColor Magenta
    Write-Host "Do NOT try to set environment variables or use other config files." -ForegroundColor Magenta
    exit 1
}

# 将 Visual Studio 的 link.exe 加入 PATH
$env:PATH = "$VS_BIN;$env:PATH"

Write-Host "`n[2/4] Configuration:" -ForegroundColor Yellow
Write-Host @"
  WDK Include (km)     = $WDK_INC_KM
  WDK Include (shared) = $WDK_INC_SHARED
  WDK Include (ucrt)   = $WDK_INC_UCRT
  VS Include           = $VS_INCLUDE
  WDK Lib Path         = $WDK_LIB_PATH
  VS Bin Path          = $VS_BIN
  WDK Version          = $WDK_VERSION
"@ -ForegroundColor Green

# 验证 link.exe 是否可访问（PATH 已包含）
if (Get-Command "link.exe" -ErrorAction SilentlyContinue) {
    Write-Host "  ✓ link.exe found in PATH" -ForegroundColor Green
} else {
    Write-Host "  ✗ link.exe not found in PATH" -ForegroundColor Red
    Write-Host "    This should not happen after path validation; something is wrong." -ForegroundColor Red
    exit 1
}

# 强制清理缓存
if ($Clean) {
    Write-Host "`n[3/4] Force cleaning cache..." -ForegroundColor Yellow
    Remove-Item -Path ".zig-cache" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "zig-out" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  ✓ Cache cleaned" -ForegroundColor Green
} else {
    Write-Host "`n[3/4] Preserving cache (use -Clean to force clean)..." -ForegroundColor Green
}

# 尝试编译，最多尝试2次（第二次在修补后）
Write-Host "`n[4/4] Building driver..." -ForegroundColor Yellow
$logFile = "build.log"
$maxAttempts = 2

for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    # 构建命令行参数，使用 -D 形式传递选项
    $zigArgs = @(
        "build",
        "driver",
        "-Dwdk-inc-km=$WDK_INC_KM",
        "-Dwdk-inc-shared=$WDK_INC_SHARED",
        "-Dwdk-inc-ucrt=$WDK_INC_UCRT",
        "-Dvs-inc=$VS_INCLUDE",
        "-Dwdk-lib=$WDK_LIB_PATH"
    )

    if ($Verbose) {
        & "zig" $zigArgs 2>&1 | Tee-Object -FilePath $logFile
    } else {
        & "zig" $zigArgs 2>&1 | Out-File -FilePath $logFile -Encoding utf8
    }

    # 读取编译日志
    $log = Get-Content $logFile -Raw -ErrorAction SilentlyContinue

    if ($LASTEXITCODE -eq 0) {
        # 编译成功
        if (Test-Path "zig-out/driver/owo.sys") {
            $fileInfo = Get-Item "zig-out/driver/owo.sys"
            Write-Host "`n✓ Success! Driver built successfully!" -ForegroundColor Green
            Write-Host "  Output: zig-out/driver/owo.sys ($($fileInfo.Length) bytes)" -ForegroundColor Cyan
        }
        break
    }

    # 检查是否是需要修补的错误
    if ($log -match "opaque types have unknown size") {
        if ($attempt -eq 1) {
            Write-Host "`n  Detected opaque type error, applying patch..." -ForegroundColor Yellow

            # 从日志中提取 cimport.zig 路径
            $pattern = '\.zig-cache\\o\\([a-f0-9]+)\\cimport\.zig'
            if ($log -match $pattern) {
                $cimportPath = $matches[0]
                Write-Host "  Found cimport.zig at: $cimportPath" -ForegroundColor Green

                # 执行修补，并传递 WDK 版本
                Write-Host "  Running patch_cimport.zig for WDK version $WDK_VERSION..." -ForegroundColor Yellow
                $patchOutput = zig run patch_cimport.zig -- $cimportPath $WDK_FULL_VERSION 2>&1

                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  ✓ Patch applied, retrying build..." -ForegroundColor Green
                } else {
                    Write-Host "  ✗ Patch failed" -ForegroundColor Red
                    if ($Verbose) { Write-Host $patchOutput -ForegroundColor Gray }
                    Remove-Item $logFile -Force -ErrorAction SilentlyContinue
                    exit 1
                }
            } else {
                Write-Host "  ✗ Could not find cimport.zig path in log" -ForegroundColor Red
                if ($Verbose) { Write-Host "Full log:" -ForegroundColor Gray; Write-Host $log }
                Remove-Item $logFile -Force -ErrorAction SilentlyContinue
                exit 1
            }
        } else {
            Write-Host "`n✗ Build failed after patch" -ForegroundColor Red
            if ($Verbose) { Write-Host "Full log:" -ForegroundColor Gray; Write-Host $log }
            Remove-Item $logFile -Force -ErrorAction SilentlyContinue
            exit 1
        }
    } else {
        # 其他错误
        Write-Host "`n✗ Build failed (unrelated to opaque types)" -ForegroundColor Red
        if ($Verbose) {
            Write-Host "Full log:" -ForegroundColor Gray
            Write-Host $log
        } else {
            $errors = $log -split "`n" | Select-Object -First 30
            Write-Host "Recent errors:" -ForegroundColor Yellow
            $errors | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
        }
        Remove-Item $logFile -Force -ErrorAction SilentlyContinue
        exit 1
    }
}

# 清理日志
Remove-Item $logFile -Force -ErrorAction SilentlyContinue

Write-Host "`n=== Build completed ===" -ForegroundColor Cyan