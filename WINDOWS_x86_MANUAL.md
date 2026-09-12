# fswatch Windows 32位 (x86 / Win32) 开发与集成手册

本文档为 **32位 Windows (x86 / Win32)** 环境下编译、集成和使用 **fswatch 1.22.0** 及 **libfswatch** 动态库/静态库的专用手册。

---

## 目录
1. [32位环境要求与依赖安装 (MINGW32)](#1-32位环境要求与依赖安装-mingw32)
2. [32位源码补丁说明与应用](#2-32位源码补丁说明与应用)
3. [std::quick_exit 与 std::exit 的深度对比](#3-stdquick_exit-与-stdexit-的深度对比)
4. [32位 libfswatch 编译与 MSVC 导入库生成](#4-32位-libfswatch-编译与-msvc-导入库生成)
5. [在 32位 MSVC (v142) 项目中集成与关键链接参数 (/SAFESEH:NO)](#5-在-32位-msvc-v142-项目中集成与关键链接参数-safesehno)
6. [32位运行时 DLL 依赖清单与发布建议](#6-32位运行时-dll-依赖清单与发布建议)

---

## 1. 32位环境要求与依赖安装 (MINGW32)

在 MSYS2 (`C:\msys64`) 中，32位编译使用 **MINGW32** 子环境：
- **C 运行时 (CRT)**：`msvcrt.dll` (Legacy 32-bit CRT)。
- **编译器**：32位 MinGW-w64 GCC (i686)。

### 安装 32 位依赖（在 MSYS2 MINGW32 终端中运行）
```bash
pacman -S --needed \
    mingw-w64-i686-gcc \
    mingw-w64-i686-cmake \
    mingw-w64-i686-ninja \
    mingw-w64-i686-gettext \
    mingw-w64-i686-tools
```

---

## 2. 32位源码补丁说明与应用

在 32 位环境下编译，需要应用两个补丁：
1. `patches/01-windows-signal-handler.patch`：修复 Windows 下缺失 POSIX `sigaction` 的问题。
2. `patches/02-win32-msvcrt-quick-exit.patch`：修复 32位旧版 MSVCRT 缺失 `std::quick_exit` 的问题。

### 一键应用补丁命令：
```bash
git apply patches/01-windows-signal-handler.patch
git apply patches/02-win32-msvcrt-quick-exit.patch
```

> **撤销补丁命令**：
> ```bash
> git apply -R patches/01-windows-signal-handler.patch
> git apply -R patches/02-win32-msvcrt-quick-exit.patch
> ```

---

## 3. std::quick_exit 与 std::exit 的深度对比

| 对比维度 | `std::exit(code)` (C++98/03/11) | `std::quick_exit(code)` (C++11 新增) |
| :--- | :--- | :--- |
| **标准引入** | C/C++ 经典标准函数 | C11 / C++11 新增函数 |
| **静态对象析构** | **会**逐一析构所有全局对象与 `static` 局部对象 | **不**析构任何全局/局部静态对象 |
| **退出钩子调用** | 执行通过 `std::atexit()` 注册的钩子函数 | 执行通过 `std::at_quick_exit()` 注册的钩子函数 |
| **设计目的** | 正常且完整的进程终止与资源清理流程 | 专为多线程快速终止设计，防止静态对象析构或 atexit 钩子引发死锁 |
| **Windows CRT 兼容性** | **全部 CRT 均支持**（包括 32位旧版 `msvcrt.dll` 与 `ucrtbase.dll`） | **仅现代 UCRT 支持**；32位 MinGW 使用的旧版 `msvcrt.dll` 不支持该符号 |

> **能否替换？**
> **完全可以安全替换！** 在测试用例代码中，当遇到断言失败需要提前退出进程时，使用 `std::exit(code)` 即可正确向测试框架返回失败退出码，且具备最佳的跨平台与跨 CRT 兼容性。

---

## 4. 32位 libfswatch 编译与 MSVC 导入库生成

在 **MSYS2 MINGW32** 终端中执行：

```bash
# 1. 编译 32 位动态库并安装至 dist/win32-shared
cmake -B build-win32 -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_INSTALL_PREFIX=./dist/win32-shared

cmake --build build-win32
cmake --install build-win32

# 2. 生成 32 位 MSVC 原生导入库 libfswatch.lib (指定 -m i386 架构)
cd dist/win32-shared
gendef bin/libfswatch.dll
dlltool -m i386 -d libfswatch.def -l lib/libfswatch.lib -D libfswatch.dll
```

产物说明：
- `dist/win32-shared/bin/libfswatch.dll`：32位核心动态链接库。
- `dist/win32-shared/lib/libfswatch.lib`：供 32位 MSVC 链接器使用的导入库。
- `dist/win32-shared/include/libfswatch/`：头文件。

---

## 5. 在 32位 MSVC (v142) 项目中集成与关键链接参数 (/SAFESEH:NO)

### 5.1 关键链接参数：`/SAFESEH:NO`
32 位 MSVC 链接器默认启用了安全异常处理检查（`/SAFESEH`）。MinGW 编译生成的 32 位目标文件/导入库不包含 MSVC 特有的 SafeSEH 表，若不显式关闭，链接时会报：
`error LNK2026: 模块对于 SAFESEH 映像是不安全的`。

在 `demo/CMakeLists.txt` 中添加自动配置：
```cmake
if (MSVC AND CMAKE_SIZEOF_VOID_P EQUAL 4)
    # 32 位 MSVC 链接 MinGW 生成的库时必须关闭 SafeSEH 检查
    target_link_options(fswatch_cpp_demo PRIVATE /SAFESEH:NO)
endif ()
```

### 5.2 执行 32位 MSVC 编译指令 (指定 `-A Win32 -T v142`)
```cmd
cmake -S demo -B demo/build-msvc32 -G "Visual Studio 16 2019" -A Win32 -T v142 -DFSWATCH_ROOT="%cd%\dist\win32-shared"
cmake --build demo/build-msvc32 --config Release
```

---

## 6. 32位运行时 DLL 依赖清单与发布建议

当 MSVC 编译的 32 位程序分发给用户时，需将以下 32 位 DLL 放置在 `.exe` 相同目录下：

| DLL 文件名 | 来源 | 说明 |
| :--- | :--- | :--- |
| `fswatch_cpp_demo.exe` | MSVC (Win32) 生成 | 32位应用程序主程序 |
| `libfswatch.dll` | `dist/win32-shared/bin/` | 32位 fswatch 核心库 |
| `libgcc_s_dw2-1.dll` 或 `libgcc_s_sjlj-1.dll` | `C:\msys64\mingw32\bin\` | GCC 32位底层运行时支持 |
| `libstdc++-6.dll` | `C:\msys64\mingw32\bin\` | GCC 32位 C++ 标准库 |
| `libwinpthread-1.dll`| `C:\msys64\mingw32\bin\` | 32位 POSIX 线程支持 |
| `libintl-8.dll` | `C:\msys64\mingw32\bin\` | 32位 gettext 国际化支持 |
| `libiconv-2.dll` | `C:\msys64\mingw32\bin\` | 32位 字符编码转换支持 |
